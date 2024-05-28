#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "Kernels.metal"
#include "Maths.metal"
#include "Renderer.metal"
#include "SpatialHashing.metal"

#define PI M_PI_F

using namespace metal;

// Fonction kernel pour initialiser les particules
kernel void initParticles(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]] // Thread position in grid
) {
    // Génère un état aléatoire basé sur l'ID du thread et le temps
    uint randomState = id+uint(uniform.time*1000);

    // Calcule la position initiale de la particule
    float3 position =
        float3(uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x/3 * random(&randomState), 
               uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y/3 * random(&randomState),
               uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z/3 * random(&randomState));

    particles[id].position = (uniform.localToWorld * float4(position, 1)).xyz;

    // Initialise la position, la prochaine position, la vitesse et la couleur de la particule
    particles[id].nextPosition = particles[id].position;
    particles[id].velocity = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
}

// Fonction du noyau pour calculer les densités et les pressions de chaque particule
kernel void CALCULATE_DENSITIES(
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Buffer des indices de départ
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Buffer des particules triées
    constant Uniform &uniform [[buffer(10)]], // Buffer uniforme
    uint id [[thread_position_in_grid]]) // Position du thread dans la grille
{
    // Obtient la particule à la position actuelle du thread
    Particle particle = SORTED_PARTICLES[id];

    // Calcule les coordonnées de la cellule pour la prochaine position de la particule et l'origine
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);

    // Initialise la densité et la densité proche de la particule
    particle.density = DensityKernel(0, uniform.H);
    particle.nearDensity = NearDensityKernel(0, uniform.H);

    // Calcule la longueur de lissage au carré
    float sqrdH = uniform.H * uniform.H;

    // Initialise le tableau pour stocker les cellules voisines
    uint NEIGHBOURING_CELLS[27];

    // Boucle sur toutes les cellules voisines
    for (int CELLID = 0; CELLID < 27; CELLID++) {
        // Calcule les coordonnées de la cellule voisine
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        // Si le tri par index Z est activé, calcule les vraies coordonnées de la cellule et obtient la clé de la courbe Z
        // Sinon, calcule le nouveau hash normalisé
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }

        // Obtient l'indice de départ et le nombre de voisins pour la cellule voisine actuelle
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        // Si l'indice de départ est inférieur au nombre de particules, boucle sur tous les voisins
        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                // Obtient l'autre particule
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];

                // Si l'autre particule est la particule actuelle, saute cette itération
                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;

                // Calcule le décalage et la distance au carré entre les particules
                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                // Si la distance au carré est supérieure à la longueur de lissage au carré, saute cette itération
                if (sqrdDist > sqrdH) continue;

                // Calcule la distance entre les particules
                float dist = sqrt(sqrdDist);

                // Met à jour la densité et la densité proche de la particule
                particle.density += DensityKernel(dist, uniform.H);
                particle.nearDensity += NearDensityKernel(dist, uniform.H);
            }
        }
    }

    // Calcule la pression et la pression proche de la particule
    particle.pressure = (particle.density - uniform.TARGET_DENSITY) * uniform.GAZ_CONSTANT;
    particle.nearPressure = uniform.NEAR_GAZ_CONSTANT * particle.nearDensity;

    // Stocke la particule mise à jour dans le tampon des particules triées
    SORTED_PARTICLES[id] = particle;
}

// Fonction du noyau pour calculer les forces de pression et de viscosité
kernel void CALCULATE_PRESSURE_VISCOSITY(
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Buffer of start indices
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Buffer of sorted particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]] // Thread position in grid
) {
    // Obtient la particule à la position actuelle du thread
    Particle particle = SORTED_PARTICLES[id];

    // Calcule le delta de mise à jour du temps
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Calcule les coordonnées de la cellule pour la prochaine position de la particule et l'origine
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);

    // Initialise les forces de pression et de viscosité
    float3 pressureForce = float3(0, 0, 0);
    float3 viscosityForce = float3(0, 0, 0);

    // Calcul la distance carré de lissage
    float sqrdH = uniform.H * uniform.H;

    // Initialise le tableau pour stocker les cellules voisines
    uint NEIGHBOURING_CELLS[27];

    // Boucle sur toutes les cellules voisines
    for (int CELLID = 0; CELLID < 27; CELLID++) {
        // Calcule les coordonnées de la cellule voisine
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        // Si le tri par index Z est activé, calcule les vraies coordonnées (dans la mémoire) de la cellule et obtient la clé de la courbe Z
        // Sinon, calcule le nouveau hash normalisé
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }

        // Obtient l'indice de départ et le nombre de voisins pour la cellule voisine actuelle
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        // Si l'indice de départ est inférieur au nombre de particules, boucle sur tous les voisins
        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                // Obtient l'autre particule
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];

                // Si l'autre particule est la particule actuelle, saute cette itération
                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;

                // Calcule le décalage et la distance au carré entre les particules
                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                // Si la distance au carré est supérieure à la longueur de lissage au carré, saute cette itération
                if (sqrdDist > sqrdH) continue;

                // Calcule la distance entre les particules
                float dist = sqrt(sqrdDist);
                float3 dir = dist == 0 ? float3(0, 1, 0) : offset/dist;

                // Calcule la pression et la pression proche partagées
                float sharedPressure = (particle.pressure + otherParticle.pressure)/2;
                float sharedNearPressure = (particle.nearPressure + otherParticle.nearPressure)/2;

                // Met à jour la force de pression
                pressureForce += dir * sharedPressure * DensityDerivative(dist, uniform.H);
                pressureForce += dir * sharedNearPressure * NearDensityDerivative(dist, uniform.H);

                // Met à jour la force de viscosité
                float weight = SmoothingKernelPoly6(dist, uniform.H);
                viscosityForce += (otherParticle.velocity - particle.velocity) * uniform.VISCOSITY * (weight*weight);
            }
        }
    }

    // Met à jour la vitesse de la particule en ajoutant la force de pression et la force de viscosité
    particle.velocity += (pressureForce / particle.density + viscosityForce/particle.density) * updateDeltaTime;
    SORTED_PARTICLES[id] = particle;
}

// Fonction du noyau pour calculer les forces de surface
kernel void PREDICTION(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]]) // Thread position in grid
{
    // Obtient la particule à la position actuelle du thread
    Particle particle = particles[id];

    // Calcule le delta de mise à jour du temps
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Calcule les coordonnées de la cellule pour la prochaine position de la particule et l'origine
    particle.velocity += float3(0, -9.81, 0) * updateDeltaTime;

    // Calcule la prochaine position de la particule
    particle.nextPosition = particle.position + particle.velocity * uniform.dt/2;

    // Stocke la particule mise à jour dans le tampon des particules
    particles[id] = particle;
}


// Fonction du noyau pour calculer les forces de surface
kernel void updateParticles(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Start indices
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Sorted particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    constant Stats &stats [[buffer(11)]], // Statistics
    uint SerializedID [[thread_position_in_grid]]) // Thread position in grid
{
    // Récupère l'ID de la particule
    uint id = SerializedID;

    // Calcule le layout de la mémoire
    float memLayout = float(id)/float(uniform.PARTICLECOUNT);

    // Obtient la particule à la position actuelle du thread
    Particle particle = SORTED_PARTICLES[id];

    // Calcule le delta de mise à jour du temps
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Calcule les coordonnées de la cellule pour la prochaine position de la particule et l'origine
    int3 CELL_COORDINATES = CELL_COORDS(particle.position, uniform.H);

    // Si le tri par index Z est activé, calcule les vraies coordonnées de la cellule et obtient la clé de la courbe Z
    uint KEY;
    if (uniform.ZINDEXSORT){            
        int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
        int3 true_CELL_COORDINATES = true_CELL_COORDS(CELL_COORDINATES, origin_CELL_COORDINATES, uniform.H);
        KEY = ZCURVE_key(true_CELL_COORDINATES, uniform.TABLE_SIZE);
    }
    else{
        KEY = NEW_HASH_NORMALIZED(CELL_COORDINATES, uniform.TABLE_SIZE);
    }
    
    // Établit l'état aléatoire basé sur la clé de la cellule
    uint RANDOM_STATE = KEY;

    // Défini la couleur de la particule selon la visualisation
    particle.color = (uniform.VISUAL == 0) * uniform.COLOR;
    particle.color += (uniform.VISUAL == 1) * CalculateDensityVisualization(particle.density, uniform.TARGET_DENSITY, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 2) * CalculatePressureVisualization(particle.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 3) * CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 4) * float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    particle.color += (uniform.VISUAL == 5) * float3(1, 1-memLayout, 1-memLayout);

    // Met a jour la position de la particule
    particle.position += particle.velocity * updateDeltaTime;

    float3 particleLocalPosition = (uniform.worldToLocal * float4(particle.position, 1)).xyz;
    float3 particleLocalVelocity = (uniform.worldToLocal * float4(particle.velocity, 1)).xyz;

    if (particleLocalPosition.y > uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y) {
        particleLocalPosition.y = uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y;
        float difference = abs(particleLocalVelocity.y - uniform.velBOUNDING_BOX.y) ;
        particleLocalVelocity.y = -1 * difference * uniform.DUMPING_FACTOR;
    } 
    else if (particleLocalPosition.y < uniform.originBOUNDING_BOX.y) {
        particleLocalPosition.y = uniform.originBOUNDING_BOX.y;
        float difference = abs(particleLocalVelocity.y - uniform.velBOUNDING_BOX.y);
        particleLocalVelocity.y = 1 * difference * uniform.DUMPING_FACTOR;
    }

    if (particleLocalPosition.x > uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x) {
        particleLocalPosition.x = uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x;
        float difference = abs(particleLocalVelocity.x - uniform.velBOUNDING_BOX.x);
        particleLocalVelocity.x = -1 * difference * uniform.DUMPING_FACTOR;
    } 
    else if (particleLocalPosition.x < uniform.originBOUNDING_BOX.x) {
        particleLocalPosition.x = uniform.originBOUNDING_BOX.x;
        float difference = abs(particleLocalVelocity.x);
        particleLocalVelocity.x = 1 * difference * uniform.DUMPING_FACTOR;
    }
    if (particleLocalPosition.z > uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z) {
        particleLocalPosition.z = uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z;
        float difference = abs(particleLocalVelocity.z - uniform.velBOUNDING_BOX.z);
        particleLocalVelocity.z = -1 * difference * uniform.DUMPING_FACTOR;
    } else if (particleLocalPosition.z < uniform.originBOUNDING_BOX.z) {
        particleLocalPosition.z = uniform.originBOUNDING_BOX.z;
        float difference = abs(particleLocalVelocity.z - uniform.velBOUNDING_BOX.z);
        particleLocalVelocity.z = 1 * difference * uniform.DUMPING_FACTOR;
    }

    particle.position = (uniform.localToWorld * float4(particleLocalPosition, 1)).xyz;
    particle.velocity = (uniform.localToWorld * float4(particleLocalVelocity, 1)).xyz;

    // Stocke la particule mise à jour dans le tampon des particules
    SORTED_PARTICLES[id] = particle;
    particles[id] = particle;
}
#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "Kernels.metal"
#include "Maths.metal"
#include "Renderer.metal"
#include "SpatialHashing.metal"

#define PI M_PI_F

using namespace metal;

kernel void initParticles(device Particle *particles [[buffer(1)]],
                          constant Uniform &uniform [[buffer(10)]],
                          uint id [[thread_position_in_grid]])
{
    uint randomState = id;
    float3 position =
        float3(uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x * random(&randomState), uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y * random(&randomState),
               uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z * random(&randomState));
    particles[id].position = position;
    particles[id].nextPosition = position;
    particles[id].velocity = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
}

kernel void CALCULATE_DENSITIES(constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                device Particle *SORTED_PARTICLES [[buffer(5)]],
                                constant Uniform &uniform [[buffer(10)]],
                                uint id [[thread_position_in_grid]])
{
    Particle particle = SORTED_PARTICLES[id];
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);

    particle.density = DensityKernel(0, uniform.H);
    particle.nearDensity = NearDensityKernel(0, uniform.H);

    float sqrdH = uniform.H * uniform.H;
    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        }
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];
                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;
                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);
                if (sqrdDist > sqrdH) continue;
                float dist = sqrt(sqrdDist);
                particle.density += DensityKernel(dist, uniform.H);
                particle.nearDensity += NearDensityKernel(dist, uniform.H);
            }
        }
    }
    particle.pressure = (particle.density - uniform.TARGET_DENSITY) * uniform.GAZ_CONSTANT;
    particle.nearPressure = uniform.NEAR_GAZ_CONSTANT * particle.nearDensity;
    SORTED_PARTICLES[id] = particle;
}

kernel void CALCULATE_PRESSURE_VISCOSITY(constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                         device Particle *SORTED_PARTICLES [[buffer(5)]],
                                         constant Uniform &uniform [[buffer(10)]],
                                         uint id [[thread_position_in_grid]])
{
    Particle particle = SORTED_PARTICLES[id];

    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
    

    float3 pressureForce = float3(0, 0, 0);
    float3 viscosityForce = float3(0, 0, 0);
    float sqrdH = uniform.H * uniform.H;


    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        }
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];

                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;


                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                if (sqrdDist > sqrdH) continue;

                float dist = sqrt(sqrdDist);
                float3 dir = dist == 0 ? float3(0, 1, 0) : offset/dist;
                
                float sharedPressure = (particle.pressure + otherParticle.pressure) / (2*otherParticle.density);
                float sharedNearPressure = (particle.nearPressure + otherParticle.nearPressure) / (2*otherParticle.nearDensity);
                
                pressureForce += dir * sharedPressure * DensityDerivative(dist, uniform.H);
                pressureForce += dir * sharedNearPressure * NearDensityDerivative(dist, uniform.H);

                viscosityForce += (otherParticle.velocity - particle.velocity) * uniform.VISCOSITY * SmoothingKernelPoly6(dist, uniform.H);

                
            }
        }
    }
    particle.velocity += (pressureForce / particle.density + viscosityForce/particle.density) * updateDeltaTime;
    SORTED_PARTICLES[id] = particle;
}

kernel void PREDICTION(device Particle *particles [[buffer(1)]],
                            constant Uniform &uniform [[buffer(10)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    particle.velocity += float3(0, -9.81, 0) * updateDeltaTime;
    particle.nextPosition = particle.position + particle.velocity * uniform.dt/2;
    particles[id] = particle;
}

kernel void updateParticles(device Particle *particles [[buffer(1)]],
                            constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                            device Particle *SORTED_PARTICLES [[buffer(5)]],
                            constant Uniform &uniform [[buffer(10)]],
                            constant Stats &stats [[buffer(11)]],
                            uint SerializedID [[thread_position_in_grid]])
{
    uint id = SerializedID;
    float memLayout = float(id)/float(uniform.PARTICLECOUNT);
    Particle particle = SORTED_PARTICLES[id];
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    int3 CELL_COORDINATES = CELL_COORDS(particle.position, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
    int3 true_CELL_COORDINATES = true_CELL_COORDS(CELL_COORDINATES, origin_CELL_COORDINATES, uniform.H);
    uint ZCURVE_KEY = ZCURVE_key(true_CELL_COORDINATES, uniform.PARTICLECOUNT);
    uint RANDOM_STATE = ZCURVE_KEY;
    particle.color = (uniform.VISUAL == 0) * uniform.COLOR;
    particle.color += (uniform.VISUAL == 1) * CalculateDensityVisualization(particle.density, uniform.TARGET_DENSITY, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 2) * CalculatePressureVisualization(particle.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 3) * CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 4) * float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    particle.color += (uniform.VISUAL == 5) * float3(1, 1-memLayout, 1-memLayout);
    particle.position += particle.velocity * updateDeltaTime;


    if (particle.position.y <= uniform.originBOUNDING_BOX.y) {
        particle.position.y = uniform.originBOUNDING_BOX.y;
        float difference = abs(particle.velocity.y - uniform.velBOUNDING_BOX.y);
        particle.velocity.y = 1*difference * uniform.DUMPING_FACTOR;
    }
    else if (particle.position.y >= uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y) {
        particle.position.y = uniform.BOUNDING_BOX.y;
        particle.velocity.y = 0;
    }

    if (particle.position.x > uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x) {
        particle.position.x = uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x;
        float difference = abs(particle.velocity.x - uniform.velBOUNDING_BOX.x);
        particle.velocity.x = -1 * difference * uniform.DUMPING_FACTOR;
    } 
    else if (particle.position.x < uniform.originBOUNDING_BOX.x) {
        particle.position.x = uniform.originBOUNDING_BOX.x;
        float difference = abs(particle.velocity.x - uniform.velBOUNDING_BOX.x);
        particle.velocity.x = 1*difference * uniform.DUMPING_FACTOR;
    }
    if (particle.position.z > uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z) {
        particle.position.z = uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z;
        float difference = abs(particle.velocity.z - uniform.velBOUNDING_BOX.z);
        particle.velocity.z = -1 * difference * uniform.DUMPING_FACTOR;
    } else if (particle.position.z < uniform.originBOUNDING_BOX.z) {
        particle.position.z = uniform.originBOUNDING_BOX.z;
        float difference = abs(particle.velocity.z - uniform.velBOUNDING_BOX.z);
        particle.velocity.z = 1 * difference * uniform.DUMPING_FACTOR;
    }

    SORTED_PARTICLES[id] = particle;
    particles[id] = particle;
}
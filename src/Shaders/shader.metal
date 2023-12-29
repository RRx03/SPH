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
        float3(uniform.BOUNDING_BOX.x * 2 * (random(&randomState) - 0.5), random(&randomState) * uniform.BOUNDING_BOX.y + 3,
               uniform.BOUNDING_BOX.z * 2 *(random(&randomState) - 0.5));
    particles[id].position = position;
    particles[id].oldPosition = position;
    particles[id].nextPosition = position;
    particles[id].forces = float3(0, 0, 0);
    particles[id].velocity = float3(0, 0, 0);
    particles[id].acceleration = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
    particles[id].density = Poly6(0, uniform.H) * uniform.MASS;
    particles[id].nearDensity = particles[id].density;
    particles[id].pressure = 0;
    particles[id].nearPressure = particles[id].pressure;
    particles[id].pressureForce = float3(0, 0, 0);
    particles[id].viscosityForce = float3(0, 0, 0);
}

kernel void CALCULATE_DENSITIES(constant Particle *particlesREAD [[buffer(1)]],
                                device Particle *particlesWRITE [[buffer(9)]],
                                constant uint *DENSE_TABLE [[buffer(3)]],
                                constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                constant Uniform &uniform [[buffer(10)]],
                                constant Stats &stats [[buffer(11)]],
                                uint id [[thread_position_in_grid]])
{
    Particle particleREAD = particlesREAD[id];
    Particle particleWRITE = particlesREAD[id];

    int3 CELL_COORDINATES = CELL_COORDS(particleREAD.nextPosition, 2 * uniform.H);

    float density = 0;
    float nearDensity = 0;

    density += Poly6(0, uniform.H) * uniform.MASS;
    nearDensity += Spiky(0, uniform.H) * uniform.MASS;

    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                if (OPID == id)
                    continue;
                float3 r = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float dist = length(r);
                if (dist < uniform.H) {
                    density += Poly6(dist, uniform.H) * uniform.MASS;
                    nearDensity += Spiky(dist, uniform.H) * uniform.MASS;
                }
            }
        }
    }
    particleWRITE.density = density;
    particleWRITE.nearDensity = nearDensity;
    particleWRITE.pressure = OldCalculatePressure(density, uniform.TARGET_DENSITY, uniform.GAZ_CONSTANT);
    particleWRITE.nearPressure = uniform.NEAR_GAZ_CONSTANT * particleREAD.nearDensity;
    particlesWRITE[id] = particleWRITE;
}

kernel void CALCULATE_PRESSURE_VISCOSITY(constant Particle *particlesREAD [[buffer(1)]],
                                         device Particle *particlesWRITE [[buffer(9)]],
                                         constant uint *DENSE_TABLE [[buffer(3)]],
                                         constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                         constant Uniform &uniform [[buffer(10)]],
                                         constant Stats &stats [[buffer(11)]],
                                         uint id [[thread_position_in_grid]])
{
    Particle particleREAD = particlesREAD[id];
    Particle particleWRITE = particlesREAD[id];


    int3 CELL_COORDINATES = CELL_COORDS(particleREAD.nextPosition, 2 * uniform.H);
    int CELL_HASH = HASH(CELL_COORDINATES, uniform.PARTICLECOUNT);
    uint RANDOM_STATE = CELL_HASH;

    particleWRITE.pressureForce = float3(0, 0, 0);
    particleWRITE.viscosityForce = float3(0, 0, 0);


    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                if (OPID == id)
                    continue;
                float3 r = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float dist = length(r);
                float3 dir;
                RANDOM_STATE = OPID;
                float3 jitter = float3(random(&RANDOM_STATE)-1/2, random(&RANDOM_STATE)-1/2, random(&RANDOM_STATE)-1/2);
                if (dist == 0) {
                    dir = float3(2 * (random(&RANDOM_STATE) - 0.5), 2 * (random(&RANDOM_STATE) - 0.5),
                                 2 * (random(&RANDOM_STATE) - 0.5));
                } else {
                    dir = r / dist + jitter;
                }
                if (dist < uniform.H) {
                    dir = normalize(dir);
                    particleWRITE.pressureForce +=
                        uniform.MASS *
                        ((particlesREAD[OPID].pressure + particleREAD.pressure) / (2 * particlesREAD[OPID].density)) *
                        GSpiky(r, uniform.H);
                    particleWRITE.pressureForce += uniform.MASS *
                                                   ((particlesREAD[OPID].nearPressure + particleREAD.nearPressure) /
                                                    (2 * particlesREAD[OPID].nearDensity)) *
                                                   GSpiky(r, uniform.H);
                    particleWRITE.viscosityForce +=
                        uniform.MASS *
                        ((particlesREAD[OPID].velocity - particleREAD.velocity) / particlesREAD[OPID].density) *
                        uniform.VISCOSITY * LViscosity(dist, uniform.H);

                    // Editer l'integration de la position, les fonction des kernels, corriger l'equation de navier
                    // stokes, revoir le calcul de la pression avec la nouvelle fonction, ajouter tension de surface
                }
            }
        }
    }
    particlesWRITE[id] = particleWRITE;
}

kernel void updateParticles(constant Particle *particlesREAD [[buffer(1)]],
                            device Particle *particlesWRITE [[buffer(9)]],
                            constant uint *DENSE_TABLE [[buffer(3)]],
                            constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                            constant Uniform &uniform [[buffer(10)]],
                            constant Stats &stats [[buffer(11)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particleREAD = particlesREAD[id];
    Particle particleWRITE = particlesWRITE[id];
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    int3 CELL_COORDINATES = CELL_COORDS(particlesREAD[id].position, 2 * uniform.H);
    int CELL_HASH = HASH(CELL_COORDINATES, uniform.PARTICLECOUNT);

    uint RANDOM_STATE = CELL_HASH;
    float3 COLOR = uniform.COLOR;
    // COLOR = float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    // COLOR = CalculateSpeedVisualization(length(particleREAD.velocity), stats.MAX_GLOBAL_SPEED, stats.MIN_GLOBAL_SPEED);
    // COLOR = CalculateDensityVisualization(particleREAD.density, Poly6(0, uniform.H) * uniform.MASS, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, 500);
    // COLOR = CalculatePressureVisualization(particleREAD.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, 100);
    particleWRITE.color = COLOR;


    particleWRITE.forces = float3(0, -9.81 * particleREAD.density, 0);
    particleWRITE.forces += particleREAD.pressureForce;
    particleWRITE.forces += particleREAD.viscosityForce;
    particleWRITE.acceleration = particleWRITE.forces / particleREAD.density;
    particleWRITE.velocity += particleWRITE.acceleration * updateDeltaTime;
    particleWRITE.position += particleWRITE.velocity * updateDeltaTime;


    if (particleWRITE.position.y <= uniform.RADIUS) {
        particleWRITE.position.y = uniform.RADIUS;
        particleWRITE.velocity.y *= -1 * uniform.DUMPING_FACTOR;
    }
    if (particleWRITE.position.x > uniform.BOUNDING_BOX.x + uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY))) {
        particleWRITE.position.x = uniform.BOUNDING_BOX.x + uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY));
        particleWRITE.velocity.x *= -1 * uniform.DUMPING_FACTOR;
    } else if (particleWRITE.position.x <
               -uniform.BOUNDING_BOX.x - uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY))) {
        particleWRITE.position.x = -uniform.BOUNDING_BOX.x - uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY));
        particleWRITE.velocity.x *= -1 * uniform.DUMPING_FACTOR;
    }
    if (particleWRITE.position.z > uniform.BOUNDING_BOX.z) {
        particleWRITE.position.z = uniform.BOUNDING_BOX.z;
        particleWRITE.velocity.z *= -1 * uniform.DUMPING_FACTOR;
    } else if (particleWRITE.position.z < -uniform.BOUNDING_BOX.z) {
        particleWRITE.position.z = -uniform.BOUNDING_BOX.z;
        particleWRITE.velocity.z *= -1 * uniform.DUMPING_FACTOR;
    }

    particleWRITE.nextPosition = particleWRITE.position + particleWRITE.velocity * updateDeltaTime;
    particlesWRITE[id] = particleWRITE;
}
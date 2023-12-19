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
        float3(3 * (random(&randomState) - 0.5), random(&randomState) * 3 + 3, 3 * (random(&randomState) - 0.5));
    particles[id].position = position;
    particles[id].oldPosition = position;
    particles[id].nextPosition = position;
    particles[id].forces = float3(0, 0, 0);
    particles[id].velocity = float3(0, 0, 0);
    particles[id].acceleration = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
    particles[id].density = SpikyKernelPow2(0, uniform.H) * uniform.MASS;
    particles[id].nearDensity = particles[id].density;
    particles[id].pressure = uniform.GAZ_CONSTANT * (particles[id].density - uniform.REST_DENSITY);
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

    density += SpikyKernelPow2(0, uniform.H) * uniform.MASS;
    nearDensity += SpikyKernelPow3(0, uniform.H) * uniform.MASS;

    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                float3 diff = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float sqrdDist = dot(diff, diff);
                if (sqrdDist < uniform.H * uniform.H) {
                    if (OPID != id) {
                        float Wij = SpikyKernelPow2(sqrt(sqrdDist), uniform.H);
                        density += Wij * uniform.MASS;
                        nearDensity += SpikyKernelPow3(sqrt(sqrdDist), uniform.H) * uniform.MASS;
                    }
                }
            }
        }
    }
    particleWRITE.density = density;
    particleWRITE.nearDensity = nearDensity;
    particleWRITE.pressure = uniform.GAZ_CONSTANT * (particleREAD.density - uniform.REST_DENSITY);
    particleWRITE.nearPressure = uniform.NEAR_GAZ_CONSTANT * particleREAD.nearDensity;
    particlesWRITE[id] = particleWRITE;
}

kernel void CALCULATE_PRESSURE(constant Particle *particlesREAD [[buffer(1)]],
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


    particleWRITE.pressureForce = 0;


    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                float3 diff = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float sqrdDist = dot(diff, diff);
                float3 dir = float3(2 * (random(&RANDOM_STATE) - 0.5), 2 * (random(&RANDOM_STATE) - 0.5),
                                    2 * (random(&RANDOM_STATE) - 0.5));
                float dist = 0;
                if (sqrdDist < uniform.H * uniform.H) {
                    if (sqrdDist > 0) {
                        dist = length(diff);
                        dir = diff / dist;
                    }
                    if (OPID != id) {
                        particleWRITE.pressureForce += uniform.MASS *
                                                       ((particlesREAD[OPID].pressure + particleREAD.pressure) /
                                                        (2 * particlesREAD[OPID].density+particleREAD.density)) *
                                                       DerivativeSpikyPow2(dist, uniform.H) * (dir);
                        particleWRITE.pressureForce += uniform.MASS *
                                                       ((particlesREAD[OPID].nearPressure + particleREAD.nearPressure) /
                                                        (2 * particlesREAD[OPID].nearDensity+particleREAD.nearDensity)) *
                                                       DerivativeSpikyPow3(dist, uniform.H) * (dir);
                    }
                }
            }
        }
    }
    particlesWRITE[id] = particleWRITE;
}

kernel void CALCULATE_VISCOSITY(constant Particle *particlesREAD [[buffer(1)]],
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
                float3 diff = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float sqrdDist = dot(diff, diff);
                float dist = 0;
                if (sqrdDist < uniform.H * uniform.H) {
                    if (sqrdDist > 0) {
                        dist = length(diff);
                    }
                    if (OPID != id) {
                        particleWRITE.viscosityForce += (particlesREAD[OPID].velocity - particleREAD.velocity) *
                                                        uniform.VISCOSITY * SmoothingKernelPoly6(dist, uniform.H);
                    }
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
    float3 COLOR = float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    // COLOR = CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED,
    // stats.MIN_GLOBAL_SPEED); // rajouter Threshold
    COLOR = CalculateDensityVisualization(particleREAD.density, uniform.REST_DENSITY, stats.MAX_GLOBAL_DENSITY,
                                          stats.MIN_GLOBAL_DENSITY, 500);
    particleWRITE.color = COLOR;
    float3 WEIGHT_FORCE = float3(0, -9.81 * uniform.MASS, 0);

    particleWRITE.forces = float3(0, 0, 0);
    particleWRITE.forces += WEIGHT_FORCE;
    particleWRITE.acceleration = particleWRITE.forces / uniform.MASS;
    particleWRITE.acceleration += particleREAD.viscosityForce;
    particleWRITE.acceleration += particleREAD.pressureForce;
    particleWRITE.velocity += particleWRITE.acceleration * updateDeltaTime;
    particleWRITE.position += particleWRITE.velocity * updateDeltaTime;


    float frequency = 0.2;
    float amplitude = 3;

    if (particleWRITE.position.y <= uniform.RADIUS) {
        particleWRITE.position.y = uniform.RADIUS;
    }
    if (particleWRITE.position.x > uniform.BOUNDING_BOX.x + amplitude * sin(uniform.time * PI * 2 * frequency)) {
        particleWRITE.position.x = uniform.BOUNDING_BOX.x + amplitude * sin(uniform.time * PI * 2 * frequency);
    } else if (particleWRITE.position.x <
               -uniform.BOUNDING_BOX.x - amplitude * sin(uniform.time * PI * 2 * frequency)) {
        particleWRITE.position.x = -uniform.BOUNDING_BOX.x - amplitude * sin(uniform.time * PI * 2 * frequency);
    }
    if (particleWRITE.position.z > uniform.BOUNDING_BOX.z) {
        particleWRITE.position.z = uniform.BOUNDING_BOX.z;
    } else if (particleWRITE.position.z < -uniform.BOUNDING_BOX.z) {
        particleWRITE.position.z = -uniform.BOUNDING_BOX.z;
    }
    particleWRITE.nextPosition = particleWRITE.position + particleWRITE.velocity * updateDeltaTime;
    particlesWRITE[id] = particleWRITE;
}
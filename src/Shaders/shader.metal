#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "Kernels.metal"
#include "LagueKernels.metal"
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
    particles[id].density = 0;
    particles[id].nearDensity = 0;
    particles[id].pressure = 0;
    particles[id].nearPressure = 0;
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

    particleWRITE.density = 0;
    particleWRITE.nearDensity = 0;

    float sqrdH = uniform.H * uniform.H;
    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                float3 offset = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float sqrdDist = dot(offset, offset);
                if (sqrdDist > sqrdH) continue;
                float dist = sqrt(sqrdDist);
                particleWRITE.density += DensityKernel(dist, uniform.H);
                particleWRITE.nearDensity += NearDensityKernel(dist, uniform.H);
            }
        }
    }
    particleWRITE.pressure = (particleWRITE.density - uniform.TARGET_DENSITY) * uniform.GAZ_CONSTANT;
    particleWRITE.nearPressure = uniform.NEAR_GAZ_CONSTANT * particleWRITE.nearDensity;
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

    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    int3 CELL_COORDINATES = CELL_COORDS(particleREAD.nextPosition, 2 * uniform.H);

    particleWRITE.pressureForce = float3(0, 0, 0);
    particleWRITE.viscosityForce = float3(0, 0, 0);
    float sqrdH = uniform.H * uniform.H;


    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        NEIGHBOURING_CELLS[CELLID] = HASH(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                if (OPID == id) continue;


                float3 offset = particlesREAD[OPID].nextPosition - particleREAD.nextPosition;
                float sqrdDist = dot(offset, offset);

                if (sqrdDist > sqrdH) continue;

                float dist = sqrt(sqrdDist);
                float3 dir = dist == 0 ? float3(0, 1, 0) : offset / dist;

                float sharedPressure = (particleREAD.pressure + particlesREAD[OPID].pressure) / 2;
                float sharedNearPressure = (particleREAD.nearPressure + particlesREAD[OPID].nearPressure) / 2;

                particleWRITE.pressureForce += dir * sharedPressure * DensityDerivative(dist, uniform.H) / particlesREAD[OPID].density;
                particleWRITE.pressureForce += dir * sharedNearPressure * NearDensityDerivative(dist, uniform.H) / particlesREAD[OPID].nearDensity;

                particleWRITE.viscosityForce += (particlesREAD[OPID].velocity - particleREAD.velocity) * uniform.VISCOSITY * SmoothingKernelPoly6(dist, uniform.H) / particlesREAD[OPID].density;

                
            }
        }
    }
    float3 acceleration = particleWRITE.pressureForce / particleREAD.density;
    particleWRITE.velocity += (acceleration + particleWRITE.viscosityForce) * updateDeltaTime;
    particlesWRITE[id] = particleWRITE;
}

kernel void PREDICTION(constant Particle *particlesREAD [[buffer(1)]],
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


    particleWRITE.velocity = particleREAD.velocity + float3(0, -9.81, 0) * updateDeltaTime;

    particleWRITE.nextPosition = particleREAD.position + particleWRITE.velocity * 1/120;

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
    float3 COLOR = uniform.COLOR;

    // int3 CELL_COORDINATES = CELL_COORDS(particlesREAD[id].position, 2 * uniform.H);
    // int CELL_HASH = HASH(CELL_COORDINATES, uniform.PARTICLECOUNT);
    // uint RANDOM_STATE = CELL_HASH;
    // COLOR = float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    // COLOR = CalculateSpeedVisualization(length(particleREAD.velocity), stats.MAX_GLOBAL_SPEED, stats.MIN_GLOBAL_SPEED);
    // COLOR = CalculateDensityVisualization(particleREAD.density, Poly6(0, uniform.H) * uniform.MASS, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, 500);
    // COLOR = CalculatePressureVisualization(particleREAD.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, 100);
    particleWRITE.color = COLOR;

    particleWRITE.position += particleREAD.velocity * updateDeltaTime;


    if (particleWRITE.position.y <= 0) {
        particleWRITE.position.y = 0;
        particleWRITE.velocity.y *= -1 * uniform.DUMPING_FACTOR;
    }
    else if (particleWRITE.position.y >= uniform.BOUNDING_BOX.y) {
        particleWRITE.position.y = uniform.BOUNDING_BOX.y;
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

    particlesWRITE[id] = particleWRITE;
}
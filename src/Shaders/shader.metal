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
    particles[id].nextPosition = position;
    particles[id].velocity = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
}

kernel void CALCULATE_DENSITIES(device Particle *particles [[buffer(1)]],
                                constant uint *DENSE_TABLE [[buffer(3)]],
                                constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                constant Uniform &uniform [[buffer(10)]],
                                uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, 2 * uniform.H);

    particle.density = DensityKernel(0, uniform.H);
    particle.nearDensity = NearDensityKernel(0, uniform.H);

    float sqrdH = uniform.H * uniform.H;
    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                if (OPID == id) continue;
                float3 offset = particles[OPID].nextPosition - particle.nextPosition;
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
    particles[id] = particle;
}

kernel void CALCULATE_PRESSURE_VISCOSITY(device Particle *particles [[buffer(1)]],
                                         constant uint *DENSE_TABLE [[buffer(3)]],
                                         constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                                         constant Uniform &uniform [[buffer(10)]],
                                         uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];

    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, 2 * uniform.H);

    float3 pressureForce = float3(0, 0, 0);
    float3 viscosityForce = float3(0, 0, 0);
    float sqrdH = uniform.H * uniform.H;


    uint NEIGHBOURING_CELLS[27];


    for (int CELLID = 0; CELLID < 27; CELLID++) {
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];
        NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.PARTICLECOUNT);
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                uint OPID = DENSE_TABLE[START_INDEX + NEIGHBOUR_ID];
                if (OPID == id) continue;


                float3 offset = particles[OPID].nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                if (sqrdDist > sqrdH) continue;

                float dist = sqrt(sqrdDist);
                float3 dir = dist == 0 ? float3(0, 1, 0) : offset/dist;
                
                float sharedPressure = (particle.pressure + particles[OPID].pressure) / 2;
                float sharedNearPressure = (particle.nearPressure + particles[OPID].nearPressure) / 2;

                pressureForce += dir * sharedPressure * DensityDerivative(dist, uniform.H) / particles[OPID].density;
                pressureForce += dir * sharedNearPressure * NearDensityDerivative(dist, uniform.H) / particles[OPID].nearDensity;

                viscosityForce += (particles[OPID].velocity - particle.velocity) * uniform.VISCOSITY * SmoothingKernelPoly6(dist, uniform.H);

                
            }
        }
    }
    particle.velocity += (pressureForce / particle.density + viscosityForce) * updateDeltaTime;
    particles[id] = particle;
}

kernel void PREDICTION(device Particle *particles [[buffer(1)]],
                            constant Uniform &uniform [[buffer(10)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    particle.velocity = particle.velocity + float3(0, -9.81, 0) * updateDeltaTime;
    particle.nextPosition = particle.position + particle.velocity * 1/120;
    particles[id] = particle;
}

kernel void updateParticles(device Particle *particles [[buffer(1)]],
                            constant uint *DENSE_TABLE [[buffer(3)]],
                            constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                            constant Uniform &uniform [[buffer(10)]],
                            constant Stats &stats [[buffer(11)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    int3 CELL_COORDINATES = CELL_COORDS(particles[id].position, 2 * uniform.H);
    int CELL_HASH = NEW_HASH_NORMALIZED(CELL_COORDINATES ,uniform.PARTICLECOUNT);
    uint RANDOM_STATE = CELL_HASH;
    particle.color = (uniform.VISUAL == 0) * uniform.COLOR;
    particle.color += (uniform.VISUAL == 1) * CalculateDensityVisualization(particle.density, uniform.TARGET_DENSITY, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 2) * CalculatePressureVisualization(particle.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 3) * CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 4) * float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    particle.position += particle.velocity * updateDeltaTime;


    if (particle.position.y <= 0) {
        particle.position.y = 0;
        particle.velocity.y *= -1 * uniform.DUMPING_FACTOR;
    }
    else if (particle.position.y >= uniform.BOUNDING_BOX.y) {
        particle.position.y = uniform.BOUNDING_BOX.y;
        particle.velocity.y *= -1 * uniform.DUMPING_FACTOR;
    }
    if (particle.position.x > uniform.BOUNDING_BOX.x + uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY))) {
        particle.position.x = uniform.BOUNDING_BOX.x + uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY));
        particle.velocity.x *= -1 * uniform.DUMPING_FACTOR;
    } else if (particle.position.x <
               -uniform.BOUNDING_BOX.x - uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY))) {
        particle.position.x = -uniform.BOUNDING_BOX.x - uniform.AMPLITUDE * abs(sin(uniform.time * PI * 2 * uniform.FREQUENCY));
        particle.velocity.x *= -1 * uniform.DUMPING_FACTOR;
    }
    if (particle.position.z > uniform.BOUNDING_BOX.z) {
        particle.position.z = uniform.BOUNDING_BOX.z;
        particle.velocity.z *= -1 * uniform.DUMPING_FACTOR;
    } else if (particle.position.z < -uniform.BOUNDING_BOX.z) {
        particle.position.z = -uniform.BOUNDING_BOX.z;
        particle.velocity.z *= -1 * uniform.DUMPING_FACTOR;
    }

    particles[id] = particle;
}
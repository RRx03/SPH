#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "Kernels.metal"
#include "Maths.metal"
#include "Renderer.metal"
#include "SpatialHashing.metal"

#define PI M_PI_F

using namespace metal;

// Kernel function to initialize particles
kernel void initParticles(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]] // Thread position in grid
) {
    // Generate a random state based on the thread id and time
    uint randomState = id+uint(uniform.time*1000);

    // Calculate the initial position of the particle
    float3 position =
        float3(uniform.originBOUNDING_BOX.x + uniform.BOUNDING_BOX.x * random(&randomState), 
               uniform.originBOUNDING_BOX.y + uniform.BOUNDING_BOX.y * random(&randomState),
               uniform.originBOUNDING_BOX.z + uniform.BOUNDING_BOX.z * random(&randomState));

    // Initialize the particle's position, next position, velocity, and color
    particles[id].position = position;
    particles[id].nextPosition = position;
    particles[id].velocity = float3(0, 0, 0);
    particles[id].color = uniform.COLOR;
}

// Kernel function to calculate densities and pressures for each particle
kernel void CALCULATE_DENSITIES(
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Buffer of start indices
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Buffer of sorted particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]]) // Thread position in grid
{
    // Get the particle at the current thread position
    Particle particle = SORTED_PARTICLES[id];

    // Calculate the cell coordinates for the particle's next position and the origin
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);

    // Initialize the particle's density and near density
    particle.density = DensityKernel(0, uniform.H);
    particle.nearDensity = NearDensityKernel(0, uniform.H);

    // Calculate squared smoothing length
    float sqrdH = uniform.H * uniform.H;

    // Initialize array to store neighbouring cells
    uint NEIGHBOURING_CELLS[27];

    // Loop over all neighbouring cells
    for (int CELLID = 0; CELLID < 27; CELLID++) {
        // Calculate the coordinates of the neighbouring cell
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        // If Z-index sorting is enabled, calculate the true cell coordinates and get the Z-curve key
        // Otherwise, calculate the new hash normalized
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }

        // Get the start index and count of neighbours for the current neighbouring cell
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        // If the start index is less than the particle count, loop over all neighbours
        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                // Get the other particle
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];

                // If the other particle is the current particle, skip this iteration
                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;

                // Calculate the offset and squared distance between the particles
                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                // If the squared distance is greater than the squared smoothing length, skip this iteration
                if (sqrdDist > sqrdH) continue;

                // Calculate the distance between the particles
                float dist = sqrt(sqrdDist);

                // Update the particle's density and near density
                particle.density += DensityKernel(dist, uniform.H);
                particle.nearDensity += NearDensityKernel(dist, uniform.H);
            }
        }
    }

    // Calculate the particle's pressure and near pressure
    particle.pressure = (particle.density - uniform.TARGET_DENSITY) * uniform.GAZ_CONSTANT;
    particle.nearPressure = uniform.NEAR_GAZ_CONSTANT * particle.nearDensity;

    // Store the updated particle back in the sorted particles buffer
    SORTED_PARTICLES[id] = particle;
}

// Kernel function to calculate pressure and viscosity forces
kernel void CALCULATE_PRESSURE_VISCOSITY(
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Buffer of start indices
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Buffer of sorted particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]] // Thread position in grid
) {
    // Get the particle at the current thread position
    Particle particle = SORTED_PARTICLES[id];

    // Calculate the update delta time
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Calculate the cell coordinates for the particle's next position and the origin
    int3 CELL_COORDINATES = CELL_COORDS(particle.nextPosition, uniform.H);
    int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);

    // Initialize pressure and viscosity forces
    float3 pressureForce = float3(0, 0, 0);
    float3 viscosityForce = float3(0, 0, 0);

    // Calculate squared smoothing length
    float sqrdH = uniform.H * uniform.H;

    // Initialize array to store neighbouring cells
    uint NEIGHBOURING_CELLS[27];

    // Loop over all neighbouring cells
    for (int CELLID = 0; CELLID < 27; CELLID++) {
        // Calculate the coordinates of the neighbouring cell
        int3 NEIGHBOURING_CELLS_COORDS = CELL_COORDINATES + NEIGHBOURS[CELLID];

        // If Z-index sorting is enabled, calculate the true cell coordinates and get the Z-curve key
        // Otherwise, calculate the new hash normalized
        if (uniform.ZINDEXSORT){
            int3 true_NEIGHBOURING_CELLS_COORDS = true_CELL_COORDS(NEIGHBOURING_CELLS_COORDS, origin_CELL_COORDINATES, uniform.H);
            NEIGHBOURING_CELLS[CELLID] = ZCURVE_key(true_NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }
        else{
            NEIGHBOURING_CELLS[CELLID] = NEW_HASH_NORMALIZED(NEIGHBOURING_CELLS_COORDS, uniform.TABLE_SIZE);
        }

        // Get the start index and count of neighbours for the current neighbouring cell
        int START_INDEX = START_INDICES[NEIGHBOURING_CELLS[CELLID]].START_INDEX;
        int NEIGHBOURS_COUNT = START_INDICES[NEIGHBOURING_CELLS[CELLID]].COUNT;

        // If the start index is less than the particle count, loop over all neighbours
        if (uint(START_INDEX) < uniform.PARTICLECOUNT) {
            for (int NEIGHBOUR_ID = 0; NEIGHBOUR_ID < NEIGHBOURS_COUNT; NEIGHBOUR_ID++) {
                // Get the other particle
                Particle otherParticle = SORTED_PARTICLES[START_INDEX + NEIGHBOUR_ID];

                // If the other particle is the current particle, skip this iteration
                if (uint(START_INDEX + NEIGHBOUR_ID) == id) continue;

                // Calculate the offset and squared distance between the particles
                float3 offset = otherParticle.nextPosition - particle.nextPosition;
                float sqrdDist = dot(offset, offset);

                // If the squared distance is greater than the squared smoothing length, skip this iteration
                if (sqrdDist > sqrdH) continue;

                // Calculate the distance and direction between the particles
                float dist = sqrt(sqrdDist);
                float3 dir = dist == 0 ? float3(0, 1, 0) : offset/dist;

                // Calculate the shared pressure and near pressure
                float sharedPressure = (particle.pressure + otherParticle.pressure) / (2*otherParticle.density);
                float sharedNearPressure = (particle.nearPressure + otherParticle.nearPressure) / (2*otherParticle.nearDensity);

                // Update the pressure force
                pressureForce += dir * sharedPressure * DensityDerivative(dist, uniform.H);
                pressureForce += dir * sharedNearPressure * NearDensityDerivative(dist, uniform.H);

                // Update the viscosity force
                viscosityForce += (otherParticle.velocity - particle.velocity) * uniform.VISCOSITY * SmoothingKernelPoly6(dist, uniform.H);
            }
        }
    }

    // Update the particle's velocity and store it back in the sorted particles buffer
    particle.velocity += (pressureForce / particle.density + viscosityForce/particle.density) * updateDeltaTime;
    SORTED_PARTICLES[id] = particle;
}

// Kernel function to predict the next position of each particle
kernel void PREDICTION(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    uint id [[thread_position_in_grid]]) // Thread position in grid
{
    // Get the particle at the current thread position
    Particle particle = particles[id];

    // Calculate the update delta time
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Update the particle's velocity by adding the acceleration due to gravity
    particle.velocity += float3(0, -9.81, 0) * updateDeltaTime;

    // Predict the particle's next position using the updated velocity
    particle.nextPosition = particle.position + particle.velocity * uniform.dt/2;

    // Store the updated particle back in the particles buffer
    particles[id] = particle;
}
// Kernel function to update the state of each particle
kernel void updateParticles(
    device Particle *particles [[buffer(1)]], // Buffer of particles
    constant START_INDICES_STRUCT *START_INDICES [[buffer(4)]], // Start indices
    device Particle *SORTED_PARTICLES [[buffer(5)]], // Sorted particles
    constant Uniform &uniform [[buffer(10)]], // Uniform buffer
    constant Stats &stats [[buffer(11)]], // Statistics
    uint SerializedID [[thread_position_in_grid]]) // Thread position in grid
{
    // Get the particle ID
    uint id = SerializedID;

    // Calculate the memory layout
    float memLayout = float(id)/float(uniform.PARTICLECOUNT);

    // Get the particle at the current thread position
    Particle particle = SORTED_PARTICLES[id];

    // Calculate the update delta time
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;

    // Calculate the cell coordinates for the particle's position
    int3 CELL_COORDINATES = CELL_COORDS(particle.position, uniform.H);

    // Calculate the key for the particle
    uint KEY;
    if (uniform.ZINDEXSORT){            
        int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
        int3 true_CELL_COORDINATES = true_CELL_COORDS(CELL_COORDINATES, origin_CELL_COORDINATES, uniform.H);
        KEY = ZCURVE_key(true_CELL_COORDINATES, uniform.TABLE_SIZE);
    }
    else{
        KEY = NEW_HASH_NORMALIZED(CELL_COORDINATES, uniform.TABLE_SIZE);
    }
    
    // Set the random state to the key
    uint RANDOM_STATE = KEY;

    // Calculate the particle's color based on the visualization mode
    particle.color = (uniform.VISUAL == 0) * uniform.COLOR;
    particle.color += (uniform.VISUAL == 1) * CalculateDensityVisualization(particle.density, uniform.TARGET_DENSITY, stats.MAX_GLOBAL_DENSITY, stats.MIN_GLOBAL_DENSITY, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 2) * CalculatePressureVisualization(particle.pressure, stats.MAX_GLOBAL_PRESSURE, stats.MIN_GLOBAL_PRESSURE, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 3) * CalculateSpeedVisualization(length(particle.velocity), stats.MAX_GLOBAL_SPEED, uniform.THRESHOLD);
    particle.color += (uniform.VISUAL == 4) * float3(random(&RANDOM_STATE), random(&RANDOM_STATE), random(&RANDOM_STATE));
    particle.color += (uniform.VISUAL == 5) * float3(1, 1-memLayout, 1-memLayout);

    // Update the particle's position
    particle.position += particle.velocity * updateDeltaTime;

    // Handle collisions with the bounding box
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
        float difference = abs(particle.velocity.x - uniform.velBOUNDING_BOX.x) *(dot(particle.velocity, particle.velocity) < 0);
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

    // Store the updated particle back in the sorted particles buffer
    SORTED_PARTICLES[id] = particle;

    // Store the updated particle back in the particles buffer
    particles[id] = particle;
}
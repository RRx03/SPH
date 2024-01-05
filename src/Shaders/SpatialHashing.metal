#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


#define PI M_PI_F

using namespace metal;

kernel void RESET_TABLES(device uint *TABLE_ARRAY [[buffer(2)]],
                         device uint *DENSE_TABLE [[buffer(3)]],
                         device START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                         constant Uniform &uniform [[buffer(10)]],
                         constant Stats &stats [[buffer(11)]],
                         uint id [[thread_position_in_grid]])
{
    TABLE_ARRAY[id] = 0;
    TABLE_ARRAY[id + 1] = 0;
    DENSE_TABLE[id] = 0;
    START_INDICES[id].START_INDEX = uniform.PARTICLECOUNT;
    START_INDICES[id].COUNT = 0;
}

kernel void INIT_TABLES(constant Particle *PARTICLES [[buffer(1)]],
                        device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                        constant Uniform &uniform [[buffer(10)]],
                        constant Stats &stats [[buffer(11)]],
                        uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CELL_COORDS(PARTICLES[particleID].position, uniform.H);
    uint hashValue = NEW_HASH_NORMALIZED(cellCoords, uniform.PARTICLECOUNT);
    atomic_fetch_add_explicit(&TABLE_ARRAY + hashValue, 1, memory_order_relaxed);
}

kernel void ASSIGN_DENSE_TABLE(constant Particle *PARTICLES [[buffer(1)]],
                               device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                               device atomic_uint &DENSE_TABLE [[buffer(3)]],
                               constant Uniform &uniform [[buffer(10)]],
                               constant Stats &stats [[buffer(11)]],
                               uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CELL_COORDS(PARTICLES[particleID].position, uniform.H);
    uint hashValue = NEW_HASH_NORMALIZED(cellCoords, uniform.PARTICLECOUNT);

    uint id = atomic_fetch_add_explicit(&TABLE_ARRAY + hashValue, -1, memory_order_relaxed);
    id -= 1;

    atomic_fetch_add_explicit(&DENSE_TABLE + id, particleID, memory_order_relaxed);
}

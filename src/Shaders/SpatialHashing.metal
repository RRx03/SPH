#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


#define PI M_PI_F

using namespace metal;

int3 true_CELL_COORDS(int3 position, int3 originePosition, float h)
{ 
    return int3(position-originePosition);
}

uint ZCURVE_key(int3 trueCoords, uint m){
    unsigned long x = trueCoords.x;
    unsigned long y = trueCoords.y;
    unsigned long z = trueCoords.z;
    unsigned long z_KEY = 0;
    for (unsigned long i = 0; i < sizeof(unsigned long); i++) {
        unsigned long mask = 1 << i;
        unsigned long xbit = (x & mask) >> i;
        unsigned long ybit = (y & mask) >> i;
        unsigned long zbit = (z & mask) >> i;

        if (x >> i == 0 && y >> i == 0 && z >> i == 0) {
            break;
        }
        z_KEY |= xbit << (3 * i) | zbit << (3 * i + 1) | ybit << (3 * i + 2);

    }
    return z_KEY%m;

} 

kernel void RESET_TABLES(device uint *TABLE_ARRAY [[buffer(2)]],
                         device START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                         constant Uniform &uniform [[buffer(10)]],
                         constant Stats &stats [[buffer(11)]],
                         uint id [[thread_position_in_grid]])
{
    TABLE_ARRAY[id] = 0;
    TABLE_ARRAY[id + 1] = 0;
    START_INDICES[id].START_INDEX = uniform.PARTICLECOUNT;
    START_INDICES[id].COUNT = 0;
}

kernel void INIT_TABLES(constant Particle *PARTICLES [[buffer(1)]],
                        device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                        constant Uniform &uniform [[buffer(10)]],
                        constant Stats &stats [[buffer(11)]],
                        uint particleID [[thread_position_in_grid]])
{
    int3 CELL_COORDINATES = CELL_COORDS(PARTICLES[particleID].position, uniform.H);
    uint KEY;
    if (uniform.ZINDEXSORT){            
        int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
        int3 true_CELL_COORDINATES = true_CELL_COORDS(CELL_COORDINATES, origin_CELL_COORDINATES, uniform.H);
        KEY = ZCURVE_key(true_CELL_COORDINATES, uniform.PARTICLECOUNT);
    }
    else{
        KEY = NEW_HASH_NORMALIZED(CELL_COORDINATES, uniform.PARTICLECOUNT);
    }
    
    atomic_fetch_add_explicit(&TABLE_ARRAY + KEY, 1, memory_order_relaxed);
}

kernel void ASSIGN_DENSE_TABLE(constant Particle *PARTICLES [[buffer(1)]],
                               device atomic_uint &TABLE_ARRAY [[buffer(2)]],
                               device Particle *SORTED_PARTICLES [[buffer(5)]],
                               constant Uniform &uniform [[buffer(10)]],
                               constant Stats &stats [[buffer(11)]],
                               uint particleID [[thread_position_in_grid]])
{
    int3 CELL_COORDINATES = CELL_COORDS(PARTICLES[particleID].position, uniform.H);
    uint KEY;
    if (uniform.ZINDEXSORT){            
        int3 origin_CELL_COORDINATES = CELL_COORDS(uniform.originBOUNDING_BOX, uniform.H);
        int3 true_CELL_COORDINATES = true_CELL_COORDS(CELL_COORDINATES, origin_CELL_COORDINATES, uniform.H);
        KEY = ZCURVE_key(true_CELL_COORDINATES, uniform.PARTICLECOUNT);
    }
    else{
        KEY = NEW_HASH_NORMALIZED(CELL_COORDINATES, uniform.PARTICLECOUNT);
    }


    uint id = atomic_fetch_add_explicit(&TABLE_ARRAY + KEY, -1, memory_order_relaxed);
    id -= 1;

    SORTED_PARTICLES[id] = PARTICLES[particleID];
}

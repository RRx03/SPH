

#include <metal_stdlib>
#include <metal_atomic>
#include <simd/simd.h>
#include "../Shared.h"


using namespace metal;

using namespace metal;

int3 CellCoords(float3 pos, float CELL_SIZE){
    return int3(pos/CELL_SIZE);
}
uint hash(int3 CellCoords, uint tableSize){
    
    int h = (CellCoords.x*92837111)^(CellCoords.y*689287499)^(CellCoords.z*283923481);
    return uint(abs(h) % tableSize);

}


kernel void initTable(device atomic_int &table [[buffer(0)]],
                    constant float3 *positions [[buffer(1)]],
                    constant Params &params [[buffer(10)]],
                    uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CellCoords(positions[particleID], params.cellSIZE);
    uint hashValue = hash(cellCoords, params.SIZE);
    atomic_fetch_add_explicit(&table+hashValue, 1, memory_order_relaxed);
}


kernel void assignDenseTable(device atomic_int &table [[buffer(0)]],
                    constant float3 *positions [[buffer(1)]],
                    device atomic_int &denseTable [[buffer(2)]],
                    constant Params &params [[buffer(10)]],
                    uint particleID [[thread_position_in_grid]])
{
    int3 cellCoords = CellCoords(positions[particleID], params.cellSIZE);
    uint hashValue = hash(cellCoords, params.SIZE);
        
    uint id = atomic_fetch_add_explicit(&table+hashValue, -1, memory_order_relaxed);
    id -= 1;

    atomic_fetch_add_explicit(&denseTable+id, particleID, memory_order_relaxed);
}

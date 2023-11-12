
#include <simd/simd.h>
#include <metal_stdlib>
#include <metal_atomic>
#include <simd/simd.h>
#include "../Shared.h"


using namespace metal;


kernel void InitParticles(device Particle *particles [[buffer(0)]], uint id [[thread_position_in_grid]]){

    Particle p = particles[id];
    p.position = float3(1, 2, 3);
    particles[id] = p;

}

kernel void Main(){

}
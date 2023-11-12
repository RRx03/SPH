
#include <simd/simd.h>
#include "../common.h"

using namespace metal;

struct VertexInput {
    float3 position [[attribute(VertexAttributePosition)]];
    half4 color [[attribute(VertexAttributeColor)]];
};

struct ShaderInOut {
    float4 position [[position]];
    half4  color;
};

vertex ShaderInOut vert(VertexInput in [[stage_in]],
	   constant FrameUniforms& uniforms [[buffer(FrameUniformBuffer)]]) {
    ShaderInOut out;
    float4 pos4 = float4(in.position, 1.0);
    out.position = uniforms.projectionViewModel * pos4;
    out.color = in.color / 255.0;
    return out;
}

fragment half4 frag(ShaderInOut in [[stage_in]]) {
    return in.color;
}
/*

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

}*/
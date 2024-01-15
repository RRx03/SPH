#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


#define PI M_PI_F

using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float3 normal;
    float3 color;
};

vertex RasterizerData vertexShader(const VertexIn vertices [[stage_in]],
                                   constant Particle *particles [[buffer(1)]],
                                   constant Uniform &uniform [[buffer(10)]],
                                   uint instance_id [[instance_id]])
{
    RasterizerData out;
    Particle particle = particles[instance_id];
    out.position = uniform.projectionMatrix * uniform.viewMatrix * translationMatrix(particle.position) *
                   float4(vertices.position.xyz, 1);
    out.color = particle.color;
    out.normal = vertices.normal;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    float3 LIGHT = float3(0, -1, -1) * Q_rsqrt(dot(float3(0, -1, 1), float3(0, -1, 1)));
    float ISO = max(0.1, dot(in.normal, -LIGHT));
    // return in.normal.xyzz * 0.5 + 0.5;
    return float4(in.color*ISO, 1);
}

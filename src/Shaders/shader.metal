#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


using namespace metal;


constexpr float Q_rsqrt(float number)
{
    // static_assert(numeric_limits<float>::is_iec559, "Must Be IEEE754"); // (enable only on IEEE 754)
    float const y = as_type<float>(0x5f3759df - (as_type<uint32_t>(number) >> 1));
    return y * (1.5f - (number * 0.5f * y * y));
}

float random(thread uint *state, uint offset = 2345678)
{
    *state = *state * (*state + offset * 2) * (*state + offset * 3456) * (*state + 567890) + offset; //A revoir avec Hash function
    return *state / 4294967295.0;
}

float4x4 translationMatrix(float3 translation)
{
    return float4x4(float4(1.0, 0.0, 0., 0.), float4(0., 1., 0., 0.), float4(0., 0., 1., 0.),
                    float4(translation.x, translation.y, translation.z, 1.));
}

float4x4 projectionMatrixV2(float FOV, float aspect, float near, float far)
{
    float yScale = 1.0 / tan(FOV * 0.5);
    float xScale = yScale / aspect;
    float zRange = far - near;
    float zScale = -(far + near) / zRange;
    float wzScale = -2.0 * far * near / zRange;
    return float4x4(float4(xScale, 0.0, 0.0, 0.0), float4(0.0, yScale, 0.0, 0.0), float4(0.0, 0.0, zScale, -1.0),
                    float4(0.0, 0.0, wzScale, 0.0));
}


struct VertexIn {
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float3 normal;
    float3 color;
};


using namespace metal;
vertex RasterizerData vertexShader(const VertexIn vertices [[stage_in]],
                                    constant Particle *particles [[buffer(1)]],
                                   constant Uniform &uniform [[buffer(10)]],
                                   uint instance_id [[instance_id]])
{
    RasterizerData out;
    Particle particle = particles[instance_id];
    out.position = uniform.projectionMatrix * uniform.viewMatrix * translationMatrix(particle.position) * float4(vertices.position.xyz, 1);
    out.color = float3(1, 1, 1);
    out.normal = vertices.normal;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    float3 LIGHT = float3(0, -1, -1) * Q_rsqrt(dot(float3(0, -1, 1), float3(0, -1, 1)));
    float ISO = max(0.1, dot(in.normal, -LIGHT));
    return float4(in.color * ISO, 1);
}



kernel void initParticles(device Particle *particles [[buffer(1)]], constant Uniform &uniform [[buffer(10)]], uint id [[thread_position_in_grid]]) {
    uint randomState = id;
    float3 position = float3(random(&randomState) * 2 - 1, random(&randomState) * 2 - 1, random(&randomState) * 2 - 1);
    particles[id].position = position;
    particles[id].velocity = float3(0, 0, 0);

}


kernel void updateParticles(device Particle *particles [[buffer(1)]], constant Uniform &uniform [[buffer(10)]], uint id [[thread_position_in_grid]]) {
    uint randomState = id;
    float3 position = float3(random(&randomState) * 2 - 1, random(&randomState) * 2 - 1, random(&randomState) * 2 - 1);
    particles[id].position = position;
    particles[id].velocity = float3(0, 0, 0);

}
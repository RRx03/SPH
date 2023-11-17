#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


using namespace metal;


constexpr float Q_rsqrt(float number)
{
    //static_assert(numeric_limits<float>::is_iec559, "Must Be IEEE754"); // (enable only on IEEE 754)
    float const y = as_type<float>(0x5f3759df - (as_type<uint32_t>(number) >> 1));
    return y * (1.5f - (number * 0.5f * y * y));
}

float4x4 translationMatrix(float3 translation)
{
    return float4x4(float4(1.0, 0.0, 0., 0.), float4(0., 1., 0., 0.), float4(0., 0., 1., 0.), float4(translation.x, translation.y, translation.z, 1.));
}

float4x4 projectionMatrixV2(float FOV, float aspect, float near, float far)
{
    float yScale = 1.0 / tan(FOV * 0.5);
    float xScale = yScale / aspect;
    float zRange = far - near;
    float zScale = -(far + near) / zRange;
    float wzScale = -2.0 * far * near / zRange;
    return float4x4(float4(xScale, 0.0, 0.0, 0.0),
                    float4(0.0, yScale, 0.0, 0.0),
                    float4(0.0, 0.0, zScale, -1.0),
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
vertex RasterizerData vertexShader(
                                    const VertexIn vertices [[stage_in]], 
                                    uint instance_id [[instance_id]])
{
    RasterizerData out;
    out.position = projectionMatrixV2(70, WIDTH/HEIGHT, 0.1, 100)*translationMatrix(float3(0,0,-2))*float4(vertices.position.xyz, 1);
    out.color = float3(1, 1, 1);
    out.normal = vertices.normal;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{   
    float3 LIGHT = float3(0, -1, -1)*Q_rsqrt(dot(float3(0, -1, 1), float3(0, -1, 1)));
    float ISO = max(0.1, dot(in.normal, -LIGHT));
    return float4(in.color * ISO, 1);
}
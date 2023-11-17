#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"



struct VertexIn {
    float4 position [[attribute(0)]];
    float3 normals [[attribute(1)]];
};



struct RasterizerData {
    float4 position [[position]];
    float4 color;
};


using namespace metal;
vertex RasterizerData vertexShader(
                                    const VertexIn vertices [[stage_in]], 
                                    uint instance_id [[instance_id]])
{
    RasterizerData out;
    out.position = vertices.position+0.5*instance_id;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    return float4(1.0, 1.0, 1.0, 1.0);
}
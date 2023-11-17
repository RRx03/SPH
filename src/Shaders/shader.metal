#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"

struct RasterizerData {
    float4 position [[position]];
    float4 color;
};
struct VertexIn {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};


using namespace metal;
vertex RasterizerData vertexShader(constant VertexIn *vertices [[buffer(1)]], uint vertexID [[vertex_id]])
{
    RasterizerData out;
    out.position = vector_float4(vertices[vertexID].position.xy, 0.0, 1.0);
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    return float4(1.0, 1.0, 1.0, 1.0);
}
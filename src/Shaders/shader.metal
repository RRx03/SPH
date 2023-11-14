#include <simd/simd.h>
#include <metal_stdlib>
#include <metal_atomic>
#include <simd/simd.h>
#include "../Shared.h"

struct RasterizerData {
    float4 position [[position]];
    float4 color;
};

using namespace metal;
vertex RasterizerData vertexShader( constant Vertex *vertices [[buffer(1)]],
                                    uint vertexID [[vertex_id]])
{
    RasterizerData out;
    out.position = vector_float4(vertices[vertexID].position.x, vertices[vertexID].position.y, 0.0, 1.0);
    out.color = vertices[vertexID].color;
    return out;

}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    return in.color;
}
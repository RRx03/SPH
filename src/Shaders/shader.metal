#include <simd/simd.h>
#include <metal_atomic>
#include <metal_stdlib>
#include "../Shared.h"


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

constexpr float Q_rsqrt(float number)
{
    // static_assert(numeric_limits<float>::is_iec559, "Must Be IEEE754"); // (enable only on IEEE 754)
    float const y = as_type<float>(0x5f3759df - (as_type<uint32_t>(number) >> 1));
    return y * (1.5f - (number * 0.5f * y * y));
}

float random(thread uint *state, uint offset = 2345678)
{
    *state = *state * (*state + offset * 2) * (*state + offset * 3456) * (*state + 567890) +
             offset; // A revoir avec Hash function
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
int3 CELL_COORDS(float3 pos, float CELL_SIZE){
    return int3(pos/CELL_SIZE); // CELL_SIZE = 2*H
}
uint HASH(int3 CELL_COORDS, uint tableSize){
    int h = (CELL_COORDS.x*92837111)^(CELL_COORDS.y*689287499)^(CELL_COORDS.z*283923481);
    return uint(abs(h) % tableSize);

}

constant const int3 NEIGHBOURS[27] = {
    int3(-1, -1, -1),
    int3(0, -1, -1),
    int3(1, -1, -1),
    int3(-1, -1, 0),
    int3(0, -1, 0),
    int3(1, -1, 0),
    int3(-1, -1, 1),
    int3(0, -1, 1),
    int3(1, -1, 1),
    int3(-1, 0, -1),
    int3(0, 0, -1),
    int3(1, 0, -1),
    int3(-1, 0, 0),
    int3(0, 0, 0),
    int3(1, 0, 0),
    int3(-1, 0, 1),
    int3(0, 0, 1),
    int3(1, 0, 1),
    int3(-1, 1, -1),
    int3(0, 1, -1),
    int3(1, 1, -1),
    int3(-1, 1, 0),
    int3(0, 1, 0),
    int3(1, 1, 0),
    int3(-1, 1, 1),
    int3(0, 1, 1),
    int3(1, 1, 1),
    
    
};




using namespace metal;
vertex RasterizerData vertexShader(const VertexIn vertices [[stage_in]],
                                   constant Particle *particles [[buffer(1)]],
                                   constant Uniform &uniform [[buffer(10)]],
                                   uint instance_id [[instance_id]])
{
    RasterizerData out;
    Particle particle = particles[instance_id];
    out.position = uniform.projectionMatrix * uniform.viewMatrix * translationMatrix(particle.position) *
                   float4(vertices.position.xyz, 1);
    out.color = uniform.COLOR;
    out.normal = vertices.normal;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]])
{
    float3 LIGHT = float3(0, -1, -1) * Q_rsqrt(dot(float3(0, -1, 1), float3(0, -1, 1)));
    float ISO = max(0.1, dot(in.normal, -LIGHT));
    return float4(in.color * ISO, 1);
}


kernel void initParticles(device Particle *particles [[buffer(1)]],
                          constant Uniform &uniform [[buffer(10)]],
                          uint id [[thread_position_in_grid]])
{
    uint randomState = id;
    float3 position = float3(3*(random(&randomState)-0.5), random(&randomState)*3+3, 3*(random(&randomState)-0.5));
    particles[id].position = position;

    particles[id].velocity = float3(0, 0, 0);
    particles[id].acceleration = float3(0, 0, 0);

}


kernel void updateParticles(device Particle *particles [[buffer(1)]],
                            constant Uniform &uniform [[buffer(10)]],
                            uint id [[thread_position_in_grid]])
{
    Particle particle = particles[id];
    float3 FORCES = float3(0, -9.81*uniform.MASS, 0);
    float updateDeltaTime = uniform.dt / uniform.SUBSTEPS;
    for (uint subStepId = 0; subStepId < uniform.SUBSTEPS; ++subStepId) {
        particle.acceleration = FORCES / uniform.MASS;

        //Implementation lourde.

        particle.velocity += particle.acceleration * updateDeltaTime;
        particle.position += particle.velocity * updateDeltaTime;

        if(particle.position.y <= uniform.RADIUS){
            particle.position.y = uniform.RADIUS;
            particle.velocity.y = -particle.velocity.y*0.9;

        }
    }
    particles[id] = particle;
}

kernel void RESET_TABLES(   device uint *TABLE_ARRAY [[buffer(2)]],
                            device uint *DENSE_TABLE [[buffer(3)]],
                            device START_INDICES_STRUCT *START_INDICES [[buffer(4)]],
                            constant Uniform &uniform [[buffer(10)]],
                            uint id [[thread_position_in_grid]]){
    TABLE_ARRAY[id] = 0;
    DENSE_TABLE[id] = 0;
    START_INDICES[id].START_INDEX = uniform.PARTICLECOUNT;
    START_INDICES[id].COUNT = 0;
}
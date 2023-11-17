#include <simd/matrix_types.h>
#import <simd/simd.h>
#include <simd/vector_types.h>

#define WIDTH 800
#define HEIGHT 800
#define BUFFER_COUNT 3
#define ShaderLib01 @"shader"

struct Uniform {
    float dt;
    unsigned int PARTICLECOUNT;
    float RADIUS;
    float H;
    float MASS;
    simd_float3 COLOR;
    simd_float4x4 projectionMatrix;
    simd_float4x4 viewMatrix;
};

struct Particle {
    simd_float3 position;
    simd_float3 oldPosition;
    simd_float3 velocity;
    simd_float3 acceleration;
};
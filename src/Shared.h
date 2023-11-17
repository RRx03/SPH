#import <simd/simd.h>
#include <simd/vector_types.h>

#define WIDTH 800
#define HEIGHT 800
#define BUFFER_COUNT 3
#define ShaderLib01 @"shader"

struct Uniform {
    unsigned int SIZE;
    float cellSIZE;
};

struct Particle {
    simd_float3 position;
    simd_float3 oldPosition;
    simd_float3 velocity;
    simd_float3 acceleration;
};
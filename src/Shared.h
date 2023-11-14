#import <simd/simd.h>
#include <simd/vector_types.h>

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

typedef struct {
    simd_float2 position;
    simd_float4 color;
} Vertex;

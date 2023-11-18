#import <simd/matrix_types.h>
#import <simd/simd.h>
#import <simd/vector_types.h>

#define WIDTH 800
#define HEIGHT 800
#define BUFFER_COUNT 1
#define SUBSTEPSCOUNT 8
#define VERTEXDEFINITION 10
#define CAMERAPOSITION 0, 0, -10

#define ShaderLib01 @"shader"

struct Uniform {
    float dt;
    unsigned int PARTICLECOUNT;
    float RADIUS;
    float H;
    float MASS;
    unsigned int SUBSTEPS;
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
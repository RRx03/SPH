#import <simd/matrix_types.h>
#import <simd/simd.h>
#import <simd/vector_types.h>


#define PI 3.14159265358979323846


#define WIDTH 800
#define HEIGHT 800
#define BUFFER_COUNT 1
#define SUBSTEPSCOUNT 1
#define VERTEXDEFINITION 10
#define CAMERAPOSITION 0, -3, -10


#define ShaderLib01 @"shader"

struct Uniform {
    simd_float4x4 projectionMatrix;
    simd_float4x4 viewMatrix;
    float dt;
    unsigned int SUBSTEPS;
    unsigned int PARTICLECOUNT;
    simd_float3 COLOR;
    float RADIUS;
    float H;
    float MASS;

    float REST_DENSITY;
    float GAZ_CONSTANT;
    float NEAR_GAZ_CONSTANT;

    float VISCOSITY;

    float DUMPING_FACTOR;
    simd_float3 BOUNDING_BOX;
};
struct Stats {
    float MAX_GLOBAL_DENSITY;
    float MIN_GLOBAL_DENSITY;
    float MAX_GLOBAL_PRESSURE;
    float MIN_GLOBAL_PRESSURE;
    float MAX_GLOBAL_SPEED;
    float MIN_GLOBAL_SPEED;
};


struct Particle {
    simd_float3 position;
    simd_float3 oldPosition;
    simd_float3 nextPosition;
    simd_float3 velocity;
    simd_float3 acceleration;
    simd_float3 forces;
    float density;
    float nearDensity;
    float pressure;
    float nearPressure;
    simd_float3 color;
};

struct START_INDICES_STRUCT {
    unsigned int START_INDEX;
    unsigned int COUNT;
};

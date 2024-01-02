#import <Foundation/Foundation.h>
#import <simd/simd.h>
struct SETTINGS {
    float dt;
    unsigned int MAXPARTICLECOUNT;
    unsigned int PARTICLECOUNT;
    simd_float3 COLOR;
    float RADIUS;
    float H;
    float MASS;
    float TARGET_DENSITY;
    float GAZ_CONSTANT;
    float NEAR_GAZ_CONSTANT;
    float DUMPING_FACTOR;
    float VISCOSITY;
    float FREQUENCY;
    float AMPLITUDE;
    simd_float3 BOUNDING_BOX;

    float SECURITY;
    float RESET;
    int VISUAL;
    float THRESHOLD;
};


/*
Optimisation :
-O0 a changer en -O2
FrameBufferOnly a revoir.
*/
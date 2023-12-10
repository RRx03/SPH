#import <Foundation/Foundation.h>
#import <simd/simd.h>
struct SETTINGS {
    unsigned int PARTICLECOUNT;
    simd_float3 COLOR;
    float RADIUS;
    float H;
    float MASS;
    float REST_DENSITY;
    float GAS_CONSTANT;
    simd_float3 BOUNDING_BOX;
};


/*
Optimisation :
-O0 a changer en -O2
FrameBufferOnly a revoir.
*/
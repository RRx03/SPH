#import <Foundation/Foundation.h>
#import <simd/simd.h>
struct SETTINGS {
    unsigned int PARTICLECOUNT;
    float RADIUS;
    float H;
    float MASS;
    simd_float3 COLOR;
};


/*
Optimisation :
-O0 a changer en -O2
FrameBufferOnly a revoir.
*/
#import <Foundation/Foundation.h>
struct ParticleSettings {
    unsigned int particleCount;
};

#define WIDTH 800
#define HEIGHT 800
#define BUFFER_COUNT 3
#define ShaderLib01 @"shader"
/*
Optimisation :
-O0 a changer en -O2
FrameBufferOnly a revoir.
*/
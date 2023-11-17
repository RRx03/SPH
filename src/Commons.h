#ifndef COMMONS_H
#define COMMONS_H


#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <ModelIO/ModelIO.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/objc.h>
#import <simd/matrix.h>
#import <simd/simd.h>
#import <simd/types.h>
#import <simd/vector.h>
#import <simd/vector_make.h>
#import <sys/_types/_null.h>
#import <unistd.h>

#import "Settings.h"
#import "Shared.h"

extern struct Engine engine;
extern struct ParticleSettings particleSettings;

void createApp();
void setup(MTKView *view);
void draw(MTKView *view);
simd_int3 CellCoords(simd_float3 pos, float CELL_SIZE);
uint hash(simd_int3 CellCoords, uint tableSize);


@interface ComputePSO : NSObject
@property (retain, readwrite, nonatomic) id<MTLComputePipelineState> computePSO;
// clang-format off
- (void)setUpPSO:(id<MTLDevice>)device :(id<MTLLibrary>)library :(NSString *)kernelName;
// clang-format on
@end

struct Buffer {
    id<MTLBuffer> buffer;
    uint count;
    uint offset;
};


struct Engine {
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLLibrary> library;
    id<MTLRenderPipelineState> RPSO01;
    id<MTLDepthStencilState> DepthSO;
    dispatch_semaphore_t Semaphore;
    struct Buffer *particleBuffer[BUFFER_COUNT];
    id<MTLCommandBuffer> commandRenderBuffer[BUFFER_COUNT]; // They are both the same but one of them only for rendering
    id<MTLCommandBuffer> commandComputeBuffer[BUFFER_COUNT]; // and the other only for computing.
};

void initEngine();

@interface View : MTKView
@end

#endif

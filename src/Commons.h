#ifndef COMMONS_H
#define COMMONS_H


#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/objc.h>
#import <simd/matrix.h>
#import <simd/simd.h>
#import <simd/types.h>
#import <simd/vector_make.h>
#import <sys/_types/_null.h>
#import <unistd.h>
#import "Settings.h"
#import "Shared.h"


void initSettings();
void initParticles();
void initMetal();
simd_int3 CellCoords(simd_float3 pos, float CELL_SIZE);
uint hash(simd_int3 CellCoords, uint tableSize);

@interface ComputePSO : NSObject
@property (retain, readwrite, nonatomic) id<MTLComputePipelineState> computePSO;
// clang-format off
- (void)setUpPSO:(id<MTLDevice>)device :(NSString *)libName :(NSString *)kernelName;
// clang-format on
@end
@interface View : MTKView
@property (retain, readwrite, nonatomic) id<MTLDevice> MTLDevice;
@property (retain, readwrite, nonatomic) id<MTLCommandQueue> commandQueue;
@property (retain, readwrite, nonatomic) id<MTLLibrary> library;
@property (retain, readwrite, nonatomic) ComputePSO *CPSO1;
@property (retain, readwrite, nonatomic) ComputePSO *CPSO2;
@property (retain, readwrite, nonatomic) id<MTLRenderPipelineState> RenderPSO;
@property (retain, readwrite, nonatomic) id<MTLDepthStencilState> DepthSO;
@property (retain, readwrite, nonatomic) dispatch_semaphore_t Semaphore;
@property (retain, readwrite, nonatomic) id<MTLBuffer> Buffer;

@end

#endif
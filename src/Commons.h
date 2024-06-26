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

#import "Settings/Settings.h"
#import "Shared.h"

extern struct Engine engine;
extern struct Uniform uniform;
extern struct Stats stats;

void createApp();
void setup(MTKView *view);
void draw(MTKView *view);
simd_int3 CellCoords(simd_float3 pos, float CELL_SIZE);
uint hash(simd_int3 CellCoords, uint tableSize);
matrix_float4x4 projectionMatrix(float FOV, float aspect, float near, float far);
matrix_float4x4 translation(simd_float3 vec);
matrix_float4x4 rotationX(float angle);
matrix_float4x4 rotationZ(float angle);
void initParticles();
void updatedt();
void RESET_TABLES();
void RENDER(MTKView *view);
void UPDATE_PARTICLES();
void INIT_TABLES();
void ASSIGN_DENSE_TABLE();
void CALCULATE_DATA();
void SPATIAL_HASH();
void READJSONSETTINGS();
void initUniform();
void initBuffers();
void PREDICT();
void initCapture();
void startCapture();
void stopCapture();
void FrameRate();


@interface ComputePSO : NSObject
@property (retain, readwrite, nonatomic) id<MTLComputePipelineState> computePSO;
// clang-format off
- (void)setUpPSO:(id<MTLDevice>)device :(id<MTLLibrary>)library :(NSString *)kernelName;
// clang-format on
@end


struct Engine {
    NSDate *start;
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLLibrary> library;
    id<MTLDepthStencilState> DepthSO;
    id<MTLRenderPipelineState> RPSO01;
    id<MTLComputePipelineState> CPSOinitParticles;
    id<MTLComputePipelineState> CPSOupdateParticles;
    id<MTLComputePipelineState> CPSOresetTables;
    id<MTLComputePipelineState> CPSOinitTables;
    id<MTLComputePipelineState> CPSOassignDenseTables;
    id<MTLComputePipelineState> CPSOcalculateDensities;
    id<MTLComputePipelineState> CPSOcalculatePressureViscosity;
    id<MTLComputePipelineState> CPSOprediciton;
    id<MTLComputePipelineState> CPSOStartIndex;

    id<MTLCaptureScope> Scope;


    dispatch_semaphore_t Semaphore;
    MTKMesh *mesh;
    uint bufferIndex;
    id<MTLBuffer> particleBuffer;

    id<MTLCommandBuffer> commandRenderBuffer[BUFFER_COUNT];
    id<MTLCommandBuffer> commandComputeBuffer[BUFFER_COUNT];
    id<MTLBuffer> TABLE_ARRAY;
    id<MTLBuffer> START_INDICES;

    id<MTLBuffer> START_INDEX;
    id<MTLBuffer> START_COUNT;
    id<MTLBuffer> sortedParticleBuffer;
};

void initEngine();

@interface View : MTKView
@end

#endif

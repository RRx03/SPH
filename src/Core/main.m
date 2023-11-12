#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <simd/matrix.h>
#import <simd/simd.h>
#include <simd/vector_make.h>
#import "../Commons.h"
#import "../common.h"

@interface View : MTKView
@property (retain, readwrite, nonatomic) id<MTLDevice> _device;
@property (retain, readwrite, nonatomic) id<MTLCommandQueue> commandQueue;
@property (retain, readwrite, nonatomic) id<MTLLibrary> library;
@property (readwrite, nonatomic) struct ComputePSO *CPSO1;
@property (readwrite, nonatomic) struct ComputePSO *CPSO2;
@property (retain, readwrite, nonatomic) id<MTLRenderPipelineState> RenderPSO;
@property (retain, readwrite, nonatomic) id<MTLDepthStencilState> DepthSO;
@property (retain, readwrite, nonatomic) dispatch_semaphore_t Semaphore;
@property (retain, readwrite, nonatomic) id<MTLBuffer> Buffer;
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];

        NSMenu *bar = [NSMenu new];
        NSMenuItem *barItem = [NSMenuItem new];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [bar addItem:barItem];
        [barItem setSubmenu:menu];
        [menu addItem:quit];
        NSApp.mainMenu = bar;

        NSRect frame = NSMakeRect(0, 0, 500, 500);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window cascadeTopLeftFromPoint:NSMakePoint(20, 20)];
        window.title = [[NSProcessInfo processInfo] processName];
        [window makeKeyAndOrderFront:nil];

        View *view = [[View alloc] initWithFrame:frame];
        window.contentView = view;

        [NSApp run];
    }
    return 0;
}
@implementation View

- (id)initWithFrame:(CGRect)inFrame
{
    self._device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:self._device];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         @"shader"];
    NSURL *libraryURL = [NSURL URLWithString:path];

    self.library = [self._device newLibraryWithURL:libraryURL error:&error];

    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    self.DepthSO = [self._device newDepthStencilStateWithDescriptor:depthDesc];

    _commandQueue = [self._device newCommandQueue];
}

- (void)drawRect:(CGRect)rect
{
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];

    // [encoder setViewport:(MTLViewport){0.0, 0.0, self.drawableSize.width, self.drawableSize.height, 0.0, 1.0}];
    // [encoder setDepthStencilState:self.DepthSO];
    // [encoder setRenderPipelineState:self.RenderPSO];
    [encoder endEncoding];

    // [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    //   dispatch_semaphore_signal(semaphore);
    // }];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];

    [super drawRect:rect];
}

@end


/*#include <Foundation/Foundation.h>
#include <unistd.h>
#import "../Commons.h"
#import "../Settings.h"
#import "../Shared.h"



id<MTLDevice> device;
id<MTLCommandQueue> commandQueue;

ComputePSO *CPSO1;
ComputePSO *CPSO2;

id<MTLBuffer> particlesBuffer;
id<MTLBuffer> table;
id<MTLBuffer> denseTable;

struct ParticleSettings particleSettings;
struct Uniform uniform;


int main(int argc, const char *argv[])
{
    initSettings();
    initMetal();


    initParticles();
    return 0;
}


void initSettings()
{
    particleSettings.particleCount = 10000;
}

void initParticles()
{
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];

    [computeEncoder setComputePipelineState:CPSO1.computePSO];
    [computeEncoder setBuffer:particlesBuffer offset:0 atIndex:0];

    unsigned int maxThreadsPerThreadgroup = CPSO1.computePSO.maxTotalThreadsPerThreadgroup;
    maxThreadsPerThreadgroup =
        (particleSettings.particleCount > maxThreadsPerThreadgroup) * maxThreadsPerThreadgroup +
        (particleSettings.particleCount <= maxThreadsPerThreadgroup) * particleSettings.particleCount;
    MTLSize threadsPerGroup = MTLSizeMake(maxThreadsPerThreadgroup, 1, 1);
    MTLSize numThreadgroups = MTLSizeMake((particleSettings.particleCount + 63) / 64, 1, 1);
    [computeEncoder dispatchThreadgroups:numThreadgroups threadsPerThreadgroup:threadsPerGroup];
    [computeEncoder endEncoding];

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    struct Particle *particlesPtr = (struct Particle *)particlesBuffer.contents;
    for (int i = 0; i < particleSettings.particleCount; i++) {
        // printf("%f %f %f\n", particlesPtr[i].position[0], particlesPtr[i].position[1], particlesPtr[i].position[2]);
    }
}

void initMetal()
{
    device = MTLCreateSystemDefaultDevice();
    commandQueue = [device newCommandQueue];

    CPSO1 = [[ComputePSO alloc] init];
    CPSO2 = [[ComputePSO alloc] init];
    [CPSO1 setUpPSO:device:@"shader":@"InitParticles"];
    [CPSO2 setUpPSO:device:@"shader":@"Main"];

    particlesBuffer = [device newBufferWithLength:particleSettings.particleCount * sizeof(struct Particle)
                                          options:MTLResourceStorageModeShared];

    // NSLog(@"Device: %@", device);
    //  NSLog(@"PSO1: %@", CPSO1.computePSO);
    //  NSLog(@"PSO2: %@", CPSO2.computePSO);
}

simd_int3 CellCoords(simd_float3 pos, float CELL_SIZE)
{
    return simd_make_int3(pos[0] / CELL_SIZE, pos[1] / CELL_SIZE, pos[2] / CELL_SIZE);
}

uint hash(simd_int3 CellCoords, uint tableSize)
{
    int h = (CellCoords[0] * 92837111) ^ (CellCoords[1] * 689287499) ^ (CellCoords[2] * 283923481);
    return (uint)(abs(h) % tableSize);
}
*/
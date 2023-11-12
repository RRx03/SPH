#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <simd/matrix.h>
#import <simd/simd.h>
#include <simd/vector_make.h>
#import "../common.h"

@interface HelloMetalView : MTKView
@end

int main(int argc, const char *argv[])
{
    printf("Hello, Metal!\n");
    @autoreleasepool {
        // Application.
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];

        // Menu.
        NSMenu *bar = [NSMenu new];
        NSMenuItem *barItem = [NSMenuItem new];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [bar addItem:barItem];
        [barItem setSubmenu:menu];
        [menu addItem:quit];
        NSApp.mainMenu = bar;

        // Window.
        NSRect frame = NSMakeRect(0, 0, 256, 256);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window cascadeTopLeftFromPoint:NSMakePoint(20, 20)];
        window.title = [[NSProcessInfo processInfo] processName];
        [window makeKeyAndOrderFront:nil];

        // Custom MTKView.
        HelloMetalView *view = [[HelloMetalView alloc] initWithFrame:frame];
        window.contentView = view;

        // Run.
        [NSApp run];
    }
    return 0;
}

// Vertex structure on CPU memory.
struct Vertex {
    float position[3];
    unsigned char color[4];
};

// For pipeline executing.
const int uniformBufferCount = 3;

// The main view.
@implementation HelloMetalView {
    id<MTLLibrary> _library;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthState;
    dispatch_semaphore_t _semaphore;
    id<MTLBuffer> _uniformBuffers[uniformBufferCount];
    id<MTLBuffer> _vertexBuffer;
    int uniformBufferIndex;
    long frame;
}

- (id)initWithFrame:(CGRect)inFrame
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:device];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    // Set view settings.
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    // Load shaders.
    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         @"shader"];
    NSURL *libraryURL = [NSURL URLWithString:path];

    _library = [self.device newLibraryWithURL:libraryURL error:&error];

    if (!_library) {
        NSLog(@"Failed to load library. error %@", error);
        exit(0);
    }
    id<MTLFunction> vertFunc = [_library newFunctionWithName:@"vert"];
    id<MTLFunction> fragFunc = [_library newFunctionWithName:@"frag"];

    // Create depth state.
    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    _depthState = [self.device newDepthStencilStateWithDescriptor:depthDesc];

    // Create vertex descriptor.
    MTLVertexDescriptor *vertDesc = [MTLVertexDescriptor new];
    vertDesc.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    vertDesc.attributes[VertexAttributePosition].offset = 0;
    vertDesc.attributes[VertexAttributePosition].bufferIndex = MeshVertexBuffer;
    vertDesc.attributes[VertexAttributeColor].format = MTLVertexFormatUChar4;
    vertDesc.attributes[VertexAttributeColor].offset = sizeof(float) * 3;
    vertDesc.attributes[VertexAttributeColor].bufferIndex = MeshVertexBuffer;
    vertDesc.layouts[MeshVertexBuffer].stride = sizeof(struct Vertex);
    vertDesc.layouts[MeshVertexBuffer].stepRate = 1;
    vertDesc.layouts[MeshVertexBuffer].stepFunction = MTLVertexStepFunctionPerVertex;

    // Create pipeline state.
    MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
    pipelineDesc.rasterSampleCount = self.sampleCount;
    pipelineDesc.vertexFunction = vertFunc;
    pipelineDesc.fragmentFunction = fragFunc;
    pipelineDesc.vertexDescriptor = vertDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineDesc.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
    pipelineDesc.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
    _pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state, error %@", error);
        exit(0);
    }

    // Create vertices.
    struct Vertex verts[] = {
        {{0, 0.5, 0}, {255, 0, 0, 255}},
        {{-0.5, -0.5, 0}, {0, 255, 0, 255}},
        {{0.5, -0.5, 0}, {0, 0, 255, 255}},
    };
    _vertexBuffer = [self.device newBufferWithBytes:verts length:sizeof(verts) options:MTLResourceStorageModePrivate];

    // Create uniform buffers.
    for (int i = 0; i < uniformBufferCount; i++) {
        _uniformBuffers[i] = [self.device newBufferWithLength:sizeof(struct FrameUniforms)
                                                      options:MTLResourceCPUCacheModeWriteCombined];
    }
    frame = 0;

    // Create semaphore for each uniform buffer.
    _semaphore = dispatch_semaphore_create(uniformBufferCount);
    uniformBufferIndex = 0;

    // Create command queue
    _commandQueue = [self.device newCommandQueue];
}

- (void)drawRect:(CGRect)rect
{
    // Wait for an available uniform buffer.
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);

    // Animation.
    frame++;
    float rad = frame * 0.01f;
    simd_float4x4 rot = matrix_identity_float4x4;

    // Update the current uniform buffer.
    uniformBufferIndex = (uniformBufferIndex + 1) % uniformBufferCount;
    struct FrameUniforms *uniforms = (struct FrameUniforms *)[_uniformBuffers[uniformBufferIndex] contents];
    uniforms->projectionViewModel = rot;

    // Create a command buffer.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // Encode render command.
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];
    [encoder setViewport:(MTLViewport){0.0, 0.0, self.drawableSize.width, self.drawableSize.height, 0.0, 1.0}];
    [encoder setDepthStencilState:_depthState];
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBuffer:_uniformBuffers[uniformBufferIndex] offset:0 atIndex:FrameUniformBuffer];
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:MeshVertexBuffer];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];

    // Set callback for semaphore.
    __block dispatch_semaphore_t semaphore = _semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
      dispatch_semaphore_signal(semaphore);
    }];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];

    // Draw children.
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
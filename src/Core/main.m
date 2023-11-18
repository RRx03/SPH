#include <Foundation/Foundation.h>
#include <simd/vector_make.h>
#include <simd/vector_types.h>
#include <stdbool.h>
#import "../Commons.h"

struct SETTINGS SETTINGS;
struct Engine engine;
struct Uniform uniform;

struct SETTINGS initSettings()
{
    struct SETTINGS settings;
    settings.PARTICLECOUNT = 10000;
    settings.RADIUS = 0.1;
    settings.H = 0.1;
    settings.MASS = 1;
    settings.COLOR = simd_make_float3(1.0, 1.0, 1.0);
    return settings;
}

int main(int argc, const char *argv[])
{
    createApp();
    return 0;
}

void setup(MTKView *view)
{
    SETTINGS = initSettings();


    view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    view.framebufferOnly = YES;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         ShaderLib01];
    NSURL *libraryURL = [NSURL URLWithString:path];

    engine.start = [NSDate date];
    engine.commandQueue = [engine.device newCommandQueue];
    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    engine.DepthSO = [engine.device newDepthStencilStateWithDescriptor:depthDesc];

    MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:engine.device];

    MDLMesh *mdlMesh =
        [[MDLMesh alloc] initSphereWithExtent:simd_make_float3(SETTINGS.RADIUS, SETTINGS.RADIUS, SETTINGS.RADIUS)
                                     segments:simd_make_uint2(VERTEXDEFINITION, VERTEXDEFINITION)
                                inwardNormals:false
                                 geometryType:MDLGeometryTypeTriangles
                                    allocator:allocator];
    engine.mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:engine.device error:nil];
    engine.library = [engine.device newLibraryWithURL:libraryURL error:&error];
    engine.CPSOinitParticles =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"initParticles"]
                                                     error:&error];

    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.vertexFunction = [engine.library newFunctionWithName:@"vertexShader"];
    renderPipelineDescriptor.fragmentFunction = [engine.library newFunctionWithName:@"fragmentShader"];
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(engine.mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    uniform.projectionMatrix = projectionMatrix(70, (float)WIDTH / (float)HEIGHT, 0.1, 100);
    uniform.viewMatrix = translation(simd_make_float3(CAMERAPOSITION));
    uniform.PARTICLECOUNT = SETTINGS.PARTICLECOUNT;
    uniform.RADIUS = SETTINGS.RADIUS;
    uniform.H = SETTINGS.H;
    uniform.MASS = SETTINGS.MASS;
    uniform.COLOR = SETTINGS.COLOR;
    engine.particleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.PARTICLECOUNT
                                                       options:MTLResourceStorageModeShared];
    engine.bufferIndex = 0;
    initParticles();
}

void draw(MTKView *view)
{
    updatedt();

    // MARK: - Render
    engine.commandRenderBuffer[0] = [engine.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    id<MTLRenderCommandEncoder> renderEncoder =
        [engine.commandRenderBuffer[0] renderCommandEncoderWithDescriptor:(renderPassDescriptor)];

    [renderEncoder setDepthStencilState:engine.DepthSO];
    [renderEncoder setRenderPipelineState:engine.RPSO01];

    [renderEncoder setVertexBuffer:engine.mesh.vertexBuffers[0].buffer offset:0 atIndex:0];
    [renderEncoder setVertexBuffer:engine.particleBuffer offset:0 atIndex:1];

    MTKSubmesh *submesh = engine.mesh.submeshes[0];
    [renderEncoder setVertexBytes:&uniform length:sizeof(struct Uniform) atIndex:(10)];

    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:submesh.indexCount
                               indexType:submesh.indexType
                             indexBuffer:submesh.indexBuffer.buffer
                       indexBufferOffset:submesh.indexBuffer.offset
                           instanceCount:SETTINGS.PARTICLECOUNT];

    [renderEncoder endEncoding];
    [engine.commandRenderBuffer[0] presentDrawable:view.currentDrawable];
    [engine.commandRenderBuffer[0] commit];
    [engine.commandRenderBuffer[0] waitUntilCompleted];
}


void initParticles()
{
    engine.commandRenderBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandRenderBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOinitParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandRenderBuffer[0] commit];
    [engine.commandRenderBuffer[0] waitUntilCompleted];
}

void updatedt()
{
    NSTimeInterval timeInterval = [engine.start timeIntervalSinceNow];
    uniform.dt = -timeInterval;
    engine.start = [NSDate date];
}
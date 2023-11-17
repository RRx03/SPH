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
    engine.commandQueue = [engine.device newCommandQueue];
    view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    view.framebufferOnly = YES;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    engine.DepthSO = [engine.device newDepthStencilStateWithDescriptor:depthDesc];


    engine.commandQueue = [engine.device newCommandQueue];

    MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:engine.device];

    MDLMesh *mdlMesh = [[MDLMesh alloc] initSphereWithExtent:simd_make_float3(0.5, 0.5, 0.5)
                                                    segments:simd_make_uint2(100, 100)
                                               inwardNormals:false
                                                geometryType:MDLGeometryTypeTriangles
                                                   allocator:allocator];
    engine.mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:engine.device error:nil];

    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         ShaderLib01];
    NSURL *libraryURL = [NSURL URLWithString:path];
    engine.library = [engine.device newLibraryWithURL:libraryURL error:&error];

    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.vertexFunction = [engine.library newFunctionWithName:@"vertexShader"];
    renderPipelineDescriptor.fragmentFunction = [engine.library newFunctionWithName:@"fragmentShader"];
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(engine.mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    uniform.projectionMatrix = projectionMatrix(70, (float)WIDTH / (float)HEIGHT, 0.1, 100);
    uniform.viewMatrix = translation(simd_make_float3(0, 0, -2));
    uniform.PARTICLECOUNT = SETTINGS.PARTICLECOUNT;
    uniform.RADIUS = SETTINGS.RADIUS;
    uniform.H = SETTINGS.H;
    uniform.MASS = SETTINGS.MASS;
    uniform.COLOR = SETTINGS.COLOR;
}

void draw(MTKView *view)
{
    id<MTLCommandBuffer> commandBuffer = [engine.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:(renderPassDescriptor)];

    [renderEncoder setDepthStencilState:engine.DepthSO];
    [renderEncoder setRenderPipelineState:engine.RPSO01];

    [renderEncoder setVertexBuffer:engine.mesh.vertexBuffers[0].buffer offset:0 atIndex:0];
    MTKSubmesh *submesh = engine.mesh.submeshes[0];
    [renderEncoder setVertexBytes:&uniform length:sizeof(struct Uniform) atIndex:(10)];

    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:submesh.indexCount
                               indexType:submesh.indexType
                             indexBuffer:submesh.indexBuffer.buffer
                       indexBufferOffset:submesh.indexBuffer.offset
                           instanceCount:1];

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
}
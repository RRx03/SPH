#include <simd/vector_make.h>
#include <simd/vector_types.h>
#include <stdbool.h>
#import "../Commons.h"

struct ParticleSettings particleSettings;
struct Engine engine;

MTKMesh *mesh;

int main(int argc, const char *argv[])
{
    createApp();
    return 0;
}

void setup(MTKView *view)
{
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
    mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:engine.device error:nil];

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
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];
}

void draw(MTKView *view)
{
    id<MTLCommandBuffer> commandBuffer = [engine.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:(renderPassDescriptor)];

    [renderEncoder setRenderPipelineState:engine.RPSO01];

    [renderEncoder setVertexBuffer:mesh.vertexBuffers[0].buffer offset:0 atIndex:0];
    MTKSubmesh *submesh = mesh.submeshes[0];


    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:submesh.indexCount
                               indexType:submesh.indexType
                             indexBuffer:submesh.indexBuffer.buffer
                       indexBufferOffset:submesh.indexBuffer.offset
                           instanceCount:3];

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
}
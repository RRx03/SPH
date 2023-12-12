#include <Foundation/Foundation.h>
#include <simd/vector_make.h>
#include <simd/vector_types.h>
#include <stdbool.h>
#include <stdio.h>
#import "../Commons.h"

struct SETTINGS SETTINGS;
struct Engine engine;
struct Uniform uniform;
struct Stats stats;


struct SETTINGS
initSettings() // AJOUTER CONTROLE INPUT CLAVIER ET FENETRE DE SETTINGS, ET BOUGERR LA BOUNDING BOX + CAMERA
{
    struct SETTINGS settings;
    settings.dt = 1 / 60.0;
    settings.PARTICLECOUNT = 10000;
    settings.RADIUS = 0.08;
    settings.H = 0.35;
    settings.MASS = 1;

    settings.REST_DENSITY = 100;
    settings.GAZ_CONSTANT = 15;
    settings.NEAR_GAZ_CONSTANT = 10;
    settings.VISCOSITY = 0.05;


    settings.DUMPING_FACTOR = 0.95;
    settings.BOUNDING_BOX = simd_make_float3(3, 3.0, 3.0);
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
    engine.CPSOupdateParticles =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"updateParticles"]
                                                     error:&error];
    engine.CPSOresetTables =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"RESET_TABLES"]
                                                     error:&error];
    engine.CPSOinitTables =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"INIT_TABLES"]
                                                     error:&error];
    engine.CPSOassignDenseTables =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"ASSIGN_DENSE_TABLE"]
                                                     error:&error];
    engine.CPSOcalculateDensities =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"CALCULATE_DENSITIES"]
                                                     error:&error];

    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.vertexFunction = [engine.library newFunctionWithName:@"vertexShader"];
    renderPipelineDescriptor.fragmentFunction = [engine.library newFunctionWithName:@"fragmentShader"];
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(engine.mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    engine.TABLE_ARRAY = [engine.device newBufferWithLength:sizeof(uint) * SETTINGS.PARTICLECOUNT + 1
                                                    options:MTLResourceStorageModeShared];
    engine.DENSE_TABLE = [engine.device newBufferWithLength:sizeof(uint) * SETTINGS.PARTICLECOUNT
                                                    options:MTLResourceStorageModeShared];
    engine.START_INDICES =
        [engine.device newBufferWithLength:sizeof(struct START_INDICES_STRUCT) * SETTINGS.PARTICLECOUNT
                                   options:MTLResourceStorageModeShared];

    uniform.projectionMatrix = projectionMatrix(70, (float)WIDTH / (float)HEIGHT, 0.1, 100);
    uniform.viewMatrix = translation(simd_make_float3(CAMERAPOSITION));
    uniform.PARTICLECOUNT = SETTINGS.PARTICLECOUNT;
    uniform.RADIUS = SETTINGS.RADIUS;
    uniform.H = SETTINGS.H;
    uniform.MASS = SETTINGS.MASS;
    uniform.COLOR = SETTINGS.COLOR;
    uniform.REST_DENSITY = SETTINGS.REST_DENSITY;
    uniform.GAZ_CONSTANT = SETTINGS.GAZ_CONSTANT;
    uniform.NEAR_GAZ_CONSTANT = SETTINGS.NEAR_GAZ_CONSTANT;
    uniform.BOUNDING_BOX = SETTINGS.BOUNDING_BOX;
    uniform.DUMPING_FACTOR = SETTINGS.DUMPING_FACTOR;
    uniform.VISCOSITY = SETTINGS.VISCOSITY;
    uniform.SUBSTEPS = SUBSTEPSCOUNT;
    uniform.dt = SETTINGS.dt;
    engine.particleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.PARTICLECOUNT
                                                       options:MTLResourceStorageModeShared];
    engine.bufferIndex = 0;
    initParticles();
}

void draw(MTKView *view)
{
    if (SETTINGS.dt == 0) {
        updatedt();
    } else {
        uniform.dt = SETTINGS.dt;
    }

    // MARK: - Render

    RENDER(view);

    // MARK: - Update Tables

    CALCULATE_DENSITIES();

    RESET_TABLES();

    INIT_TABLES();

    int *tablePtr = (int *)engine.TABLE_ARRAY.contents;
    struct Particle *particlePtr = (struct Particle *)engine.particleBuffer.contents;

    int partialSum = 0;
    stats.MAX_GLOBAL_DENSITY = 0;
    stats.MIN_GLOBAL_DENSITY = particlePtr[0].density;

    stats.MAX_GLOBAL_PRESSURE = 0;
    stats.MIN_GLOBAL_PRESSURE = particlePtr[0].pressure;

    stats.MAX_GLOBAL_SPEED = 0;
    stats.MIN_GLOBAL_SPEED = simd_length(particlePtr[0].velocity);

    for (int tableID = 0; tableID < SETTINGS.PARTICLECOUNT; tableID++) {
        partialSum += tablePtr[tableID];
        tablePtr[tableID] = partialSum;
        if (stats.MAX_GLOBAL_DENSITY < particlePtr[tableID].density) {
            stats.MAX_GLOBAL_DENSITY = particlePtr[tableID].density;
        }
        if (stats.MIN_GLOBAL_DENSITY > particlePtr[tableID].density) {
            stats.MIN_GLOBAL_DENSITY = particlePtr[tableID].density;
        }
        if (stats.MAX_GLOBAL_PRESSURE < particlePtr[tableID].pressure) {
            stats.MAX_GLOBAL_PRESSURE = particlePtr[tableID].pressure;
        }
        if (stats.MIN_GLOBAL_PRESSURE > particlePtr[tableID].pressure) {
            stats.MIN_GLOBAL_PRESSURE = particlePtr[tableID].pressure;
        }
        if (stats.MAX_GLOBAL_SPEED < simd_length(particlePtr[tableID].velocity)) {
            stats.MAX_GLOBAL_SPEED = simd_length(particlePtr[tableID].velocity);
        }
        if (stats.MIN_GLOBAL_SPEED > simd_length(particlePtr[tableID].velocity)) {
            stats.MIN_GLOBAL_SPEED = simd_length(particlePtr[tableID].velocity);
        }

        // printf("%f\n", particlePtr[tableID].density);
        // printf("%f\n", particlePtr[tableID].pressure);
    }
    // printf("\n");

    tablePtr[SETTINGS.PARTICLECOUNT] = partialSum;


    ASSIGN_DENSE_TABLE();


    struct START_INDICES_STRUCT *startIndices = (struct START_INDICES_STRUCT *)engine.START_INDICES.contents;
    tablePtr = (int *)engine.TABLE_ARRAY.contents;
    int previousValue = tablePtr[SETTINGS.PARTICLECOUNT];
    for (int reverseID = SETTINGS.PARTICLECOUNT - 1; reverseID >= 0; reverseID--) {
        if (tablePtr[reverseID] != previousValue) {
            startIndices[reverseID].START_INDEX = tablePtr[reverseID];
            startIndices[reverseID].COUNT = previousValue - tablePtr[reverseID];
        }
        previousValue = tablePtr[reverseID];
    }
    tablePtr[SETTINGS.PARTICLECOUNT] = partialSum;

    // int sum = 0;
    // for (int i = 0; i < SETTINGS.PARTICLECOUNT; i++) {
    //     printf("%d\n", startIndices[i].START_INDEX);
    //     sum += startIndices[i].COUNT;
    // }
    // printf("%d\n", sum);
    // printf("\n");

    // MARK:
    //     -Compute

    UPDATE_PARTICLES();

    // MARK: - RESET
}


void initParticles()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOinitParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}


void RENDER(MTKView *view)
{
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
    [renderEncoder setVertexBytes:&stats length:sizeof(struct Stats) atIndex:(11)];


    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:submesh.indexCount
                               indexType:submesh.indexType
                             indexBuffer:submesh.indexBuffer.buffer
                       indexBufferOffset:submesh.indexBuffer.offset
                           instanceCount:SETTINGS.PARTICLECOUNT];

    [renderEncoder endEncoding];
    [engine.commandRenderBuffer[0] presentDrawable:view.currentDrawable];
    [engine.commandRenderBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}


void UPDATE_PARTICLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOupdateParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void CALCULATE_DENSITIES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOcalculateDensities];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void RESET_TABLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOresetTables];
    [computeEncoder setBuffer:engine.TABLE_ARRAY offset:0 atIndex:2];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void INIT_TABLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOinitTables];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.TABLE_ARRAY offset:0 atIndex:2];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void ASSIGN_DENSE_TABLE()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOassignDenseTables];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.TABLE_ARRAY offset:0 atIndex:2];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void updatedt()
{
    NSTimeInterval timeInterval = [engine.start timeIntervalSinceNow];
    uniform.dt = -timeInterval;
    engine.start = [NSDate date];
}
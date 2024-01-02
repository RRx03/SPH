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


struct SETTINGS initSettings()
{
    struct SETTINGS settings;
    settings.dt = 1 / 60.0;
    settings.MAXPARTICLECOUNT = 10000;
    settings.PARTICLECOUNT = 8000;
    settings.MASS = 1;

    settings.RADIUS = 0.2;
    settings.H = 1;
    settings.TARGET_DENSITY = 0;
    settings.GAZ_CONSTANT = 0;
    settings.NEAR_GAZ_CONSTANT = 0;
    settings.VISCOSITY = 0;
    settings.DUMPING_FACTOR = 0;

    settings.BOUNDING_BOX = simd_make_float3(6, 9.0, 6.0);
    settings.COLOR = simd_make_float3(1.0, 1.0, 1.0);


    settings.SECURITY = 0;
    settings.RESET = 0;
    settings.VISUAL = 0;
    settings.THRESHOLD = 0;

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
    engine.CPSOcalculatePressureViscosity = [engine.device
        newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"CALCULATE_PRESSURE_VISCOSITY"]
                                      error:&error];
    engine.CPSOprediciton =
        [engine.device newComputePipelineStateWithFunction:[engine.library newFunctionWithName:@"PREDICTION"]
                                                     error:&error];


    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.vertexFunction = [engine.library newFunctionWithName:@"vertexShader"];
    renderPipelineDescriptor.fragmentFunction = [engine.library newFunctionWithName:@"fragmentShader"];
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(engine.mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    initBuffers();
    initUniform();
    initParticles();
}

void initUniform()
{
    uniform.projectionMatrix = projectionMatrix(70, (float)WIDTH / (float)HEIGHT, 0.1, 100);
    uniform.viewMatrix = translation(simd_make_float3(CAMERAPOSITION));
    uniform.PARTICLECOUNT = SETTINGS.PARTICLECOUNT;
    uniform.RADIUS = SETTINGS.RADIUS;
    uniform.H = SETTINGS.H;
    uniform.MASS = SETTINGS.MASS;
    uniform.COLOR = SETTINGS.COLOR;
    uniform.GAZ_CONSTANT = SETTINGS.GAZ_CONSTANT;
    uniform.NEAR_GAZ_CONSTANT = SETTINGS.NEAR_GAZ_CONSTANT;
    uniform.BOUNDING_BOX = SETTINGS.BOUNDING_BOX;
    uniform.DUMPING_FACTOR = SETTINGS.DUMPING_FACTOR;
    uniform.VISCOSITY = SETTINGS.VISCOSITY;
    uniform.SUBSTEPS = SUBSTEPSCOUNT;
    uniform.dt = SETTINGS.dt;
    uniform.time = 0;
    uniform.FREQUENCY = 0;
    uniform.AMPLITUDE = 0;
    uniform.THRESHOLD = SETTINGS.THRESHOLD;
    uniform.VISUAL = SETTINGS.VISUAL;
    uniform.TARGET_DENSITY = SETTINGS.TARGET_DENSITY;
}

void initBuffers()
{
    engine.TABLE_ARRAY = [engine.device newBufferWithLength:sizeof(uint) * SETTINGS.MAXPARTICLECOUNT + 1
                                                    options:MTLResourceStorageModeShared];
    engine.DENSE_TABLE = [engine.device newBufferWithLength:sizeof(uint) * SETTINGS.MAXPARTICLECOUNT
                                                    options:MTLResourceStorageModeShared];
    engine.START_INDICES =
        [engine.device newBufferWithLength:sizeof(struct START_INDICES_STRUCT) * SETTINGS.MAXPARTICLECOUNT
                                   options:MTLResourceStorageModeShared];
    engine.particleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.MAXPARTICLECOUNT
                                                       options:MTLResourceStorageModeShared];
    engine.SECparticleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.MAXPARTICLECOUNT
                                                          options:MTLResourceStorageModeShared];

    engine.bufferIndex = 0;
}

void initParticles()
{
    stats.MAX_GLOBAL_SPEED_EVER = 0;

    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOinitParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.SECparticleBuffer offset:0 atIndex:9];

    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];

    memcpy(engine.particleBuffer.contents, engine.SECparticleBuffer.contents,
           sizeof(struct Particle) * SETTINGS.PARTICLECOUNT);
}

void draw(MTKView *view)
{
    READJSONSETTINGS();

    for (int subStep = 0; subStep < SUBSTEPSCOUNT; subStep++) {
        PREDICT();

        memcpy(engine.particleBuffer.contents, engine.SECparticleBuffer.contents,
               sizeof(struct Particle) * SETTINGS.PARTICLECOUNT);

        SPATIAL_HASH();

        CALCULATE_DATA();

        UPDATE_PARTICLES();

        memcpy(engine.particleBuffer.contents, engine.SECparticleBuffer.contents,
               sizeof(struct Particle) * SETTINGS.PARTICLECOUNT);
    }

    RENDER(view);
}

void RENDER(MTKView *view)
{
    [engine.commandComputeBuffer[1] waitUntilCompleted];
    engine.commandRenderBuffer[1] = [engine.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    id<MTLRenderCommandEncoder> renderEncoder =
        [engine.commandRenderBuffer[1] renderCommandEncoderWithDescriptor:(renderPassDescriptor)];

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
    [engine.commandRenderBuffer[1] presentDrawable:view.currentDrawable];
    [engine.commandRenderBuffer[1] commit];
}

void SPATIAL_HASH()
{
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
        if (stats.MAX_GLOBAL_SPEED_EVER < simd_length(particlePtr[tableID].velocity)) {
            stats.MAX_GLOBAL_SPEED_EVER = simd_length(particlePtr[tableID].velocity);
        }

        // printf("%f\n", particlePtr[0].position.x);
        // printf("%f\n", particlePtr[tableID].viscosityForce.x);
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
}

void UPDATE_PARTICLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOupdateParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.SECparticleBuffer offset:0 atIndex:9];

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

void PREDICT()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOprediciton];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.SECparticleBuffer offset:0 atIndex:9];

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

void CALCULATE_DATA()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOcalculateDensities];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.SECparticleBuffer offset:0 atIndex:9];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];

    memcpy(engine.particleBuffer.contents, engine.SECparticleBuffer.contents,
           sizeof(struct Particle) * SETTINGS.PARTICLECOUNT);

    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOcalculatePressureViscosity];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.SECparticleBuffer offset:0 atIndex:9];
    [computeEncoder setBuffer:engine.DENSE_TABLE offset:0 atIndex:3];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];

    memcpy(engine.particleBuffer.contents, engine.SECparticleBuffer.contents,
           sizeof(struct Particle) * SETTINGS.PARTICLECOUNT);
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

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.MAXPARTICLECOUNT, 1, 1)
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

void READJSONSETTINGS()
{
    NSString *path =
        [NSString stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Settings/settings.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];

    if ([[dict objectForKey:@"SECURITY"] floatValue] != SETTINGS.SECURITY) {
        if ([[dict objectForKey:@"RADIUS"] floatValue] != uniform.RADIUS) {
            uniform.RADIUS = [[dict objectForKey:@"RADIUS"] floatValue];
            SETTINGS.RADIUS = uniform.RADIUS;
            MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:engine.device];

            MDLMesh *mdlMesh =
                [[MDLMesh alloc] initSphereWithExtent:simd_make_float3(uniform.RADIUS, uniform.RADIUS, uniform.RADIUS)
                                             segments:simd_make_uint2(VERTEXDEFINITION, VERTEXDEFINITION)
                                        inwardNormals:false
                                         geometryType:MDLGeometryTypeTriangles
                                            allocator:allocator];
            engine.mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:engine.device error:nil];
        }


        uniform.H = [[dict objectForKey:@"H"] floatValue];
        SETTINGS.H = uniform.H;

        uniform.TARGET_DENSITY = [[dict objectForKey:@"TARGET_DENSITY"] floatValue];
        SETTINGS.TARGET_DENSITY = uniform.TARGET_DENSITY;

        uniform.GAZ_CONSTANT = [[dict objectForKey:@"GAZ_CONSTANT"] floatValue];
        SETTINGS.GAZ_CONSTANT = uniform.GAZ_CONSTANT;

        uniform.NEAR_GAZ_CONSTANT = [[dict objectForKey:@"NEAR_GAZ_CONSTANT"] floatValue];
        SETTINGS.NEAR_GAZ_CONSTANT = uniform.NEAR_GAZ_CONSTANT;

        uniform.VISCOSITY = [[dict objectForKey:@"VISCOSITY"] floatValue];
        SETTINGS.VISCOSITY = uniform.VISCOSITY;

        uniform.DUMPING_FACTOR = [[dict objectForKey:@"DUMPING_FACTOR"] floatValue];
        SETTINGS.DUMPING_FACTOR = uniform.DUMPING_FACTOR;

        uniform.FREQUENCY = [[dict objectForKey:@"FREQUENCY"] floatValue];
        SETTINGS.FREQUENCY = uniform.FREQUENCY;

        uniform.AMPLITUDE = [[dict objectForKey:@"AMPLITUDE"] floatValue];
        SETTINGS.AMPLITUDE = uniform.AMPLITUDE;

        uniform.VISUAL = [[dict objectForKey:@"VISUAL"] integerValue];
        SETTINGS.VISUAL = uniform.VISUAL;

        uniform.THRESHOLD = [[dict objectForKey:@"THRESHOLD"] floatValue];
        SETTINGS.THRESHOLD = uniform.THRESHOLD;

        SETTINGS.SECURITY = [[dict objectForKey:@"SECURITY"] integerValue];

        if ([[dict objectForKey:@"PARTICLECOUNT"] integerValue] != SETTINGS.PARTICLECOUNT &&
            [[dict objectForKey:@"PARTICLECOUNT"] integerValue] <= SETTINGS.MAXPARTICLECOUNT) {
            SETTINGS.PARTICLECOUNT = [[dict objectForKey:@"PARTICLECOUNT"] integerValue];
            SETTINGS.RESET = [[dict objectForKey:@"RESET"] floatValue];
            initParticles();
        }
        if ([[dict objectForKey:@"RESET"] floatValue] != SETTINGS.RESET) {
            SETTINGS.RESET = [[dict objectForKey:@"RESET"] floatValue];
            initParticles();
        }
    }
    if ([[dict objectForKey:@"PAUSE"] integerValue] == 1) {
        uniform.dt = 0;
    } else {
        if (SETTINGS.dt == 0) {
            updatedt();
        } else {
            uniform.dt = SETTINGS.dt;
        }
        uniform.time += uniform.dt;
    }
}
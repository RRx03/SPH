#include <Foundation/Foundation.h>
#include <Metal/Metal.h>
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
    settings.MAXPARTICLECOUNT = 40000;
    settings.TABLE_SIZE = 80000;

    settings.MASS = 1;

    settings.ZINDEXSORT = false;

    settings.BOUNDING_BOX = simd_make_float3(8, 12.0, 6.0);
    settings.originBOUNDING_BOX = simd_make_float3(-4, 0, -3);
    settings.CAMERAPOSITION = simd_make_float3(0, 5, 20);


    settings.COLOR = simd_make_float3(1.0, 1.0, 1.0);

    settings.SECURITY = 0;
    settings.RESET = 0;
    settings.VISUAL = 0;
    settings.THRESHOLD = 0;
    settings.SUBSTEPS = 1;

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
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;


    NSError *error = nil;
    NSString *relativePath = [NSString stringWithFormat:@"./src/Shaders/build/%@.metallib", ShaderLib01];
    NSString *completePath = [NSURL fileURLWithPath:relativePath].path;
    NSURL *libraryURL = [NSURL URLWithString:completePath];

    engine.start = [NSDate date];
    engine.commandQueue = [engine.device newCommandQueue];
    engine.commandQueue.label = @"Command Queue";

    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
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
    renderPipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(engine.mesh.vertexDescriptor);

    engine.RPSO01 = [engine.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    READJSONSETTINGS();
    initUniform();

    initBuffers();
    initParticles();
    // initCapture();
}

void initUniform()
{
    uniform.projectionMatrix = projectionMatrix(70, (float)WIDTH / (float)HEIGHT, 0.1, 100);
    uniform.viewMatrix = translation(-(SETTINGS.CAMERAPOSITION));
    uniform.CAMERAPOSITION = SETTINGS.CAMERAPOSITION;
    uniform.PARTICLECOUNT = SETTINGS.PARTICLECOUNT;
    uniform.RADIUS = SETTINGS.RADIUS;
    uniform.H = SETTINGS.H;
    uniform.MASS = SETTINGS.MASS;
    uniform.COLOR = SETTINGS.COLOR;
    uniform.GAZ_CONSTANT = SETTINGS.GAZ_CONSTANT;
    uniform.NEAR_GAZ_CONSTANT = SETTINGS.NEAR_GAZ_CONSTANT;
    uniform.BOUNDING_BOX = SETTINGS.BOUNDING_BOX + simd_make_float3(1, 0, 0) * uniform.XOFFSET;
    uniform.oldBOUNDING_BOX = SETTINGS.BOUNDING_BOX + simd_make_float3(1, 0, 0) * uniform.XOFFSET;
    uniform.originBOUNDING_BOX = SETTINGS.originBOUNDING_BOX;
    uniform.DUMPING_FACTOR = SETTINGS.DUMPING_FACTOR;
    uniform.VISCOSITY = SETTINGS.VISCOSITY;
    uniform.SUBSTEPS = SETTINGS.SUBSTEPS;
    uniform.dt = SETTINGS.dt;
    uniform.time = 0;
    uniform.THRESHOLD = SETTINGS.THRESHOLD;
    uniform.VISUAL = SETTINGS.VISUAL;
    uniform.TARGET_DENSITY = SETTINGS.TARGET_DENSITY;
    uniform.frame = 0;
    uniform.velBOUNDING_BOX = simd_make_float3(0, 0, 0);
    uniform.ZINDEXSORT = SETTINGS.ZINDEXSORT;
    uniform.TABLE_SIZE = fmax(SETTINGS.TABLE_SIZE, SETTINGS.PARTICLECOUNT);
    SETTINGS.TABLE_SIZE = uniform.TABLE_SIZE;
}

void initBuffers()
{
    engine.TABLE_ARRAY = [engine.device newBufferWithLength:sizeof(uint) * uniform.TABLE_SIZE + 1
                                                    options:MTLResourceStorageModeShared];
    engine.TABLE_ARRAY.label = @"Table Array";

    engine.START_INDICES = [engine.device newBufferWithLength:sizeof(struct START_INDICES_STRUCT) * uniform.TABLE_SIZE
                                                      options:MTLResourceStorageModeShared];
    engine.START_INDICES.label = @"Start Indices";
    engine.particleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.MAXPARTICLECOUNT
                                                       options:MTLResourceStorageModeShared];
    engine.particleBuffer.label = @"Particle Buffer";

    engine.sortedParticleBuffer = [engine.device newBufferWithLength:sizeof(struct Particle) * SETTINGS.MAXPARTICLECOUNT
                                                             options:MTLResourceStorageModeShared];
    engine.sortedParticleBuffer.label = @"Sorted Particle Buffer";

    engine.bufferIndex = 0;
}

void initParticles()
{
    stats.MAX_GLOBAL_SPEED_EVER = 0;

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

void draw(MTKView *view)
{
    READJSONSETTINGS();

    uniform.BOUNDING_BOX.x = SETTINGS.BOUNDING_BOX.x +
                             uniform.AMPLITUDE * sin(uniform.FREQUENCY * 2 * 3.14 * uniform.time) + uniform.XOFFSET;
    uniform.velBOUNDING_BOX = (uniform.BOUNDING_BOX - uniform.oldBOUNDING_BOX) * uniform.SUBSTEPS / uniform.dt;

    for (int subStep = 0; subStep < SETTINGS.SUBSTEPS; subStep++) {
        PREDICT();

        SPATIAL_HASH();

        CALCULATE_DATA(); // A Optimiser

        UPDATE_PARTICLES();

        uniform.time += uniform.dt / SETTINGS.SUBSTEPS;
    }

    RENDER(view);

    uniform.frame++;

    if (uniform.frame == 10) {
        stopCapture();
    }

    uniform.oldBOUNDING_BOX = uniform.BOUNDING_BOX;
}

void RENDER(MTKView *view)
{
    engine.commandRenderBuffer[1] = [engine.commandQueue commandBuffer];
    engine.commandRenderBuffer[1].label = @"Render Buffer";
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

    for (int tableID = 0; tableID < SETTINGS.TABLE_SIZE; tableID++) {
        partialSum += tablePtr[tableID];
        tablePtr[tableID] = partialSum;
        if (uniform.VISUAL != 0 && tableID < SETTINGS.PARTICLECOUNT) {
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
        }
    }


    tablePtr[SETTINGS.TABLE_SIZE] = partialSum;


    ASSIGN_DENSE_TABLE();


    struct START_INDICES_STRUCT *startIndices = (struct START_INDICES_STRUCT *)engine.START_INDICES.contents;
    tablePtr = (int *)engine.TABLE_ARRAY.contents;
    int previousValue = tablePtr[SETTINGS.TABLE_SIZE];
    for (int reverseID = SETTINGS.TABLE_SIZE - 1; reverseID >= 0; reverseID--) {
        if (tablePtr[reverseID] != previousValue) {
            startIndices[reverseID].START_INDEX = tablePtr[reverseID];
            startIndices[reverseID].COUNT = previousValue - tablePtr[reverseID];
        }
        previousValue = tablePtr[reverseID];
    }
    tablePtr[SETTINGS.TABLE_SIZE] = partialSum;
}

void RESET_TABLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    engine.commandComputeBuffer[0].label = @"Reset Tables";
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOresetTables];
    [computeEncoder setBuffer:engine.TABLE_ARRAY offset:0 atIndex:2];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];
    [computeEncoder setBytes:&stats length:sizeof(struct Stats) atIndex:11];

    [computeEncoder dispatchThreads:MTLSizeMake(uniform.TABLE_SIZE, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void INIT_TABLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    engine.commandComputeBuffer[0].label = @"Init Tables";
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
    engine.commandComputeBuffer[0].label = @"Assign Dense Table";
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOassignDenseTables];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBuffer:engine.TABLE_ARRAY offset:0 atIndex:2];
    [computeEncoder setBuffer:engine.sortedParticleBuffer offset:0 atIndex:5];
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
    engine.commandComputeBuffer[0].label = @"Predict";
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOprediciton];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];
    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}

void CALCULATE_DATA()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    engine.commandComputeBuffer[0].label = @"Calculate Density";
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOcalculateDensities];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBuffer:engine.sortedParticleBuffer offset:0 atIndex:5];

    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];


    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    engine.commandComputeBuffer[0].label = @"Calculate Pressure Viscosity";
    computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOcalculatePressureViscosity];
    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBuffer:engine.sortedParticleBuffer offset:0 atIndex:5];

    [computeEncoder setBytes:&uniform length:sizeof(struct Uniform) atIndex:10];

    [computeEncoder dispatchThreads:MTLSizeMake(SETTINGS.PARTICLECOUNT, 1, 1)
              threadsPerThreadgroup:MTLSizeMake(engine.CPSOinitParticles.maxTotalThreadsPerThreadgroup, 1, 1)];
    [computeEncoder endEncoding];
    [engine.commandComputeBuffer[0] commit];
    [engine.commandComputeBuffer[0] waitUntilCompleted];
}


void UPDATE_PARTICLES()
{
    engine.commandComputeBuffer[0] = [engine.commandQueue commandBuffer];
    engine.commandComputeBuffer[0].label = @"Update Particles";
    id<MTLComputeCommandEncoder> computeEncoder = [engine.commandComputeBuffer[0] computeCommandEncoder];

    [computeEncoder setComputePipelineState:engine.CPSOupdateParticles];
    [computeEncoder setBuffer:engine.particleBuffer offset:0 atIndex:1];

    [computeEncoder setBuffer:engine.START_INDICES offset:0 atIndex:4];
    [computeEncoder setBuffer:engine.sortedParticleBuffer offset:0 atIndex:5];

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
    NSError *error = nil;
    NSString *relativePath = [NSString stringWithFormat:@"src/Settings/settings.json"];
    NSString *completePath = [NSURL fileURLWithPath:relativePath].path;
    NSData *data = [NSData dataWithContentsOfFile:completePath];
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

        uniform.XOFFSET = [[dict objectForKey:@"XOFFSET"] floatValue];

        // uniform.SUBSTEPS = [[dict objectForKey:@"SUBSTEPS"] integerValue];

        // uniform.ZINDEXSORT = [[dict objectForKey:@"ZINDEXSORT"] integerValue];

        uniform.CAMERAPOSITION = simd_make_float3([[dict objectForKey:@"CAMERAPOSITION"][0] floatValue],
                                                  [[dict objectForKey:@"CAMERAPOSITION"][1] floatValue],
                                                  [[dict objectForKey:@"CAMERAPOSITION"][2] floatValue]);
        SETTINGS.CAMERAPOSITION = uniform.CAMERAPOSITION;
        uniform.viewMatrix = translation(-(SETTINGS.CAMERAPOSITION));


        // uniform.BOUNDING_BOX = simd_make_float3([[dict objectForKey:@"BOUNDING_BOX"][0] floatValue],
        //                                         [[dict objectForKey:@"BOUNDING_BOX"][1] floatValue],
        //                                         [[dict objectForKey:@"BOUNDING_BOX"][2] floatValue]);

        // uniform.originBOUNDING_BOX = simd_make_float3([[dict objectForKey:@"originBOUNDING_BOX"][0] floatValue],
        //                                               [[dict objectForKey:@"originBOUNDING_BOX"][1] floatValue],
        //                                               [[dict objectForKey:@"originBOUNDING_BOX"][2] floatValue]);


        SETTINGS.SECURITY = [[dict objectForKey:@"SECURITY"] integerValue];

        if ([[dict objectForKey:@"PARTICLECOUNT"] integerValue] != SETTINGS.PARTICLECOUNT &&
            [[dict objectForKey:@"PARTICLECOUNT"] integerValue] <= SETTINGS.MAXPARTICLECOUNT) {
            uniform.PARTICLECOUNT = [[dict objectForKey:@"PARTICLECOUNT"] integerValue];
            SETTINGS.PARTICLECOUNT = uniform.PARTICLECOUNT;
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

void initCapture()
{
    MTLCaptureManager *captureManager = MTLCaptureManager.sharedCaptureManager;
    engine.Scope = [captureManager newCaptureScopeWithDevice:engine.device];
    [engine.Scope setLabel:@"Engine Scope"];

    assert([captureManager supportsDestination:(MTLCaptureDestination)MTLCaptureDestinationGPUTraceDocument]);
    NSError *error = nil;
    NSDate *date = [NSDate date];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"hh-mm-ss";
    NSString *dateString = [formatter stringFromDate:date];
    NSString *relativePath = [NSString stringWithFormat:@"./analysis/%@.gputrace", dateString];
    NSURL *TraceURL = [NSURL fileURLWithPath:relativePath];
    MTLCaptureDescriptor *captureDescriptor = [MTLCaptureDescriptor new];
    captureDescriptor.captureObject = engine.Scope;
    captureDescriptor.outputURL = TraceURL;
    captureDescriptor.destination = MTLCaptureDestinationGPUTraceDocument;

    if (![captureManager startCaptureWithDescriptor:captureDescriptor error:&error]) {
        NSLog(@"Failed to start capture: %@, %@", error, TraceURL);
    }
    startCapture();
}
void startCapture()
{
    [engine.Scope beginScope];
    NSLog(@"Capture Started");
}
void stopCapture()
{
    [engine.Scope endScope];
    NSLog(@"Capture stopped");
}

#include <Foundation/Foundation.h>
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
    // NSLog(@"PSO1: %@", CPSO1.computePSO);
    // NSLog(@"PSO2: %@", CPSO2.computePSO);
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

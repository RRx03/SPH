#include <Foundation/Foundation.h>
#include <unistd.h>
#import "../Commons.h"
#import "../Settings.h"
#import "../Shared.h"


id<MTLDevice> device;
id<MTLCommandQueue> commandQueue;

ComputePSO *CPSO1;
ComputePSO *CPSO2;


struct Particle *particles;
id<MTLBuffer> particlesBuffer = NULL;
id<MTLBuffer> table = NULL;
id<MTLBuffer> denseTable = NULL;

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
    particles = (struct Particle *)malloc(sizeof(struct Particle) * particleSettings.particleCount);

    for (int i = 0; i < particleSettings.particleCount; i++) {
        particles[i].position = simd_make_float3(0.0, 0.0, 0.0);
    }
}

void initMetal()
{
    device = MTLCreateSystemDefaultDevice();
    commandQueue = [device newCommandQueue];

    CPSO1 = [[ComputePSO alloc] init];
    CPSO2 = [[ComputePSO alloc] init];
    [CPSO1 setUpPSO:device:@"shader":@"Main"];
    [CPSO2 setUpPSO:device:@"shader":@"Main2"];

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

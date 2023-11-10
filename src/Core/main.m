#import "../Commons.h"
#import "../Shared.h"
#include <unistd.h>

id<MTLDevice> device;
id<MTLCommandQueue> commandQueue;
id<MTLComputePipelineState> pipelineState01;
id<MTLComputePipelineState> pipelineState02;

id<MTLLibrary> library;

const int ParticleCount = 1000000;
const float radiusH = 0.01f;

static simd_float3 particles[ParticleCount];
id<MTLBuffer> particlesBuffer = NULL;
id<MTLBuffer> table = NULL;
id<MTLBuffer> denseTable = NULL;

struct Params params;

void initMetal();

int main(int argc, const char *argv[]) {
  initMetal();
  return 0;
}

void initMetal() {
  device = MTLCreateSystemDefaultDevice();
  commandQueue = [device newCommandQueue];
  NSURL *libraryURL =
      [NSURL URLWithString:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/"
                           @"SPH/src/Shaders/build/shader.metallib"];

  NSError *libraryError = nil;

  library = [device newLibraryWithURL:libraryURL error:&libraryError];
  NSLog(@"Lib: %@", library);
  id<MTLFunction> kernelMain = [library newFunctionWithName:@"initTable"];
  id<MTLFunction> kernelSecond =
      [library newFunctionWithName:@"assignDenseTable"];

  pipelineState01 = [device newComputePipelineStateWithFunction:kernelMain
                                                          error:nil];
  pipelineState02 = [device newComputePipelineStateWithFunction:kernelSecond
                                                          error:nil];

  NSLog(@"Device: %@", device);
}

simd_int3 CellCoords(simd_float3 pos, float CELL_SIZE) {
  return simd_make_int3(pos[0] / CELL_SIZE, pos[1] / CELL_SIZE,
                        pos[2] / CELL_SIZE);
}
uint hash(simd_int3 CellCoords, uint tableSize) {

  int h = (CellCoords[0] * 92837111) ^ (CellCoords[1] * 689287499) ^
          (CellCoords[2] * 283923481);
  return (uint)(abs(h) % tableSize);
}

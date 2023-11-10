#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

id<MTLDevice> device;
id<MTLCommandQueue> commandQueue;
id<MTLRenderPipelineState> pipelineState01;
id<MTLRenderPipelineState> pipelineState02;

id<MTLLibrary> library;

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
                           @"SPH/src/Shaders/shader.metal"];

  NSError *libraryError = nil;

  library = [device newLibraryWithURL:libraryURL error:&libraryError];
  id<MTLFunction> kernelMain = [library newFunctionWithName:@"Main"];
  id<MTLFunction> kernelSecond = [library newFunctionWithName:@"Second"];

  NSLog(@"Device: %@", device);
}
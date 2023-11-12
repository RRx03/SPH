
#import "../Commons.h"

@implementation ComputePSO

@synthesize computePSO;

- (id)init
{
    self.computePSO = nil;
    return self;
}
// clang-format off
- (void)setUpPSO:(id<MTLDevice>)device :(NSString *)libName :(NSString *)kernelName
// clang-format on

{
    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         libName];
    NSURL *libraryURL = [NSURL URLWithString:path];

    id<MTLLibrary> library = [device newLibraryWithURL:libraryURL error:&error];

    if (!library) {
        NSLog(@"Lib: %@", library);
    }
    id<MTLFunction> kernelFunction = [library newFunctionWithName:kernelName];
    if (!kernelFunction) {
        NSLog(@"Failed to create kernel function: %@", error);
    }
    self.computePSO = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    if (!self.computePSO) {
        NSLog(@"Failed to create compute pipeline state: %@", error);
    }
}
@end


@implementation View

- (id)initWithFrame:(CGRect)inFrame
{
    self.MTLDevice = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:self.MTLDevice];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.commandQueue = [self.MTLDevice newCommandQueue];

    self.CPSO1 = [[ComputePSO alloc] init];
    self.CPSO2 = [[ComputePSO alloc] init];
    [self.CPSO1 setUpPSO:self.MTLDevice:@"shader":@"InitParticles"];
    [self.CPSO2 setUpPSO:self.MTLDevice:@"shader":@"Main"];

    // NSLog(@"Device: %@", self.MTLDevice);
    // NSLog(@"PSO1: %@", self.CPSO1.computePSO);
    //  NSLog(@"PSO2: %@", CPSO2.computePSO);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    self.Buffer = [self.MTLDevice newBufferWithLength:100 * sizeof(struct Particle)
                                              options:MTLResourceStorageModeShared];


    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    self.DepthSO = [self.MTLDevice newDepthStencilStateWithDescriptor:depthDesc];

    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

    _commandQueue = [self.MTLDevice newCommandQueue];
}

- (void)drawRect:(CGRect)rect
{
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];

    [computeEncoder setComputePipelineState:self.CPSO1.computePSO];
    [computeEncoder setBuffer:self.Buffer offset:0 atIndex:0];

    unsigned int maxThreadsPerThreadgroup = self.CPSO1.computePSO.maxTotalThreadsPerThreadgroup;
    maxThreadsPerThreadgroup =
        (100 > maxThreadsPerThreadgroup) * maxThreadsPerThreadgroup + (100 <= maxThreadsPerThreadgroup) * 100;
    MTLSize threadsPerGroup = MTLSizeMake(maxThreadsPerThreadgroup, 1, 1);
    MTLSize numThreadgroups = MTLSizeMake(100, 1, 1);
    [computeEncoder dispatchThreadgroups:numThreadgroups threadsPerThreadgroup:threadsPerGroup];
    [computeEncoder endEncoding];

    // struct Particle *particlesPtr = (struct Particle *)self.Buffer.contents;
    // for (int i = 0; i < 100; i++) {
    //     printf("%f %f %f\n", particlesPtr[i].position[0], particlesPtr[i].position[1], particlesPtr[i].position[2]);
    // }

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:(self.currentRenderPassDescriptor)];

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    [super drawRect:rect];
}

@end
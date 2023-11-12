
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

    NSError *error = nil;
    NSString *path = [NSString
        stringWithFormat:@"/Users/romanroux/Documents/CPGE/TIPE/FinalVersion/SPH/src/Shaders/build/%@.metallib",
                         @"shader"];
    NSURL *libraryURL = [NSURL URLWithString:path];

    self.library = [self.MTLDevice newLibraryWithURL:libraryURL error:&error];

    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    self.DepthSO = [self.MTLDevice newDepthStencilStateWithDescriptor:depthDesc];

    _commandQueue = [self.MTLDevice newCommandQueue];
}

- (void)drawRect:(CGRect)rect
{
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];

    // [encoder setViewport:(MTLViewport){0.0, 0.0, self.drawableSize.width, self.drawableSize.height, 0.0, 1.0}];
    // [encoder setDepthStencilState:self.DepthSO];
    // [encoder setRenderPipelineState:self.RenderPSO];
    [encoder endEncoding];

    // [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    //   dispatch_semaphore_signal(semaphore);
    // }];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];

    [super drawRect:rect];
}

@end
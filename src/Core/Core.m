#import "../Commons.h"


@implementation View

- (id)initWithFrame:(CGRect)inFrame
{
    engine.device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:inFrame device:engine.device];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    engine.commandQueue = [engine.device newCommandQueue];
    self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    self.framebufferOnly = YES;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;

    engine.CPSO1 = [[ComputePSO alloc] init];
    engine.CPSO2 = [[ComputePSO alloc] init];
    [engine.CPSO1 setUpPSO:engine.device:@"shader":@"InitParticles"];
    [engine.CPSO2 setUpPSO:engine.device:@"shader":@"Main"];

    // NSLog(@"Device: %@", engine.device);
    // NSLog(@"PSO1: %@", engine.CPSO1.computePSO);
    // NSLog(@"PSO2: %@", engine.CPSO2.computePSO);
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    MTLDepthStencilDescriptor *depthDesc = [MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled = YES;
    engine.DepthSO = [engine.device newDepthStencilStateWithDescriptor:depthDesc];

    engine.commandQueue = [engine.device newCommandQueue];
}

- (void)drawRect:(CGRect)rect
{
    id<MTLCommandBuffer> commandBuffer = [engine.commandQueue commandBuffer];

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:(self.currentRenderPassDescriptor)];

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:self.currentDrawable];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];


    [super drawRect:rect];
}

@end
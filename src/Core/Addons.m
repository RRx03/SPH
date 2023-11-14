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

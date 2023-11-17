#include <simd/matrix.h>
#include <simd/matrix_types.h>
#include <simd/types.h>
#import "../Commons.h"

@implementation ComputePSO

@synthesize computePSO;

- (id)init
{
    self.computePSO = nil;
    return self;
}
// clang-format off
- (void)setUpPSO:(id<MTLDevice>)device :(id<MTLLibrary>)library :(NSString *)kernelName
// clang-format on

{
    NSError *error = nil;
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


void createApp()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];

        NSMenu *bar = [NSMenu new];
        NSMenuItem *barItem = [NSMenuItem new];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        NSMenuItem *quitW = [[NSMenuItem alloc] initWithTitle:@"Close Window"
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"w"];

        [bar addItem:barItem];
        [barItem setSubmenu:menu];
        [menu addItem:quit];
        [menu addItem:quitW];

        NSApp.mainMenu = bar;


        NSRect frame = NSMakeRect(400, 200, WIDTH, HEIGHT);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window cascadeTopLeftFromPoint:NSMakePoint(0, 0)];
        window.title = [[NSProcessInfo processInfo] processName];
        [window makeKeyAndOrderFront:nil];

        View *view = [[View alloc] initWithFrame:frame];
        window.contentView = view;

        [NSApp run];
    }
}


matrix_float4x4 projectionMatrix(float FOV, float aspect, float near, float far)
{
    float yScale = 1.0 / tan(FOV * 0.5);
    float xScale = yScale / aspect;
    float zRange = far - near;
    float zScale = -(far + near) / zRange;
    float wzScale = -2.0 * far * near / zRange;
    matrix_float4x4 MAT;
    MAT = simd_matrix(simd_make_float4(xScale, 0.0, 0.0, 0.0), simd_make_float4(0.0, yScale, 0.0, 0.0),
                      simd_make_float4(0.0, 0.0, zScale, -1.0), simd_make_float4(0.0, 0.0, wzScale, 0.0));
    return MAT;
}

matrix_float4x4 translation(simd_float3 vec)
{
    matrix_float4x4 matrix = matrix_identity_float4x4;
    matrix.columns[3].x = vec.x;
    matrix.columns[3].y = vec.y;
    matrix.columns[3].z = vec.z;
    return matrix;
}
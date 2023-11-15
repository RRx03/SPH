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
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
    setup(self);
}

- (void)drawRect:(CGRect)rect
{
    draw(self);
    [super drawRect:rect];
}

@end
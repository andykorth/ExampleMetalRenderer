/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of our cross-platform view controller
*/

#import "AAPLViewController.h"
#import "MetalEngine-Swift.h"
#import "MetalRendererView.h"

@implementation AAPLViewController
{
    MetalRendererView *_view;
    MetalRenderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Set the view to use the default device
    _view = (MetalRendererView *)self.view;
    _view.device = MTLCreateSystemDefaultDevice();

    if(!_view.device)
    {
        NSLog(@"Metal is not supported on this device");
        return;
    }

    _renderer = [[MetalRenderer alloc ] initWithView:_view error:nil];

    if(!_renderer)
    {
        NSLog(@"Renderer failed initialization");
        return;
    }

    // Initialize our renderer with the view size
    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];
	_view->renderer = _renderer;
	_view.delegate = _view;

   // _view.delegate = _renderer;
}



@end

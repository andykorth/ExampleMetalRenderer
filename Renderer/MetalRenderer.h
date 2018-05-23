
@import MetalKit;

// Our platform independent render class
@interface MetalRenderer : NSObject<MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

@end

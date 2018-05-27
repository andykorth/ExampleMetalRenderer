//
//  MetalRendererView.h
//  MetalEngine-macOS
//
//  Created by Andy Korth on 5/26/18.
//  Copyright © 2018 Apple. All rights reserved.
//

#import <MetalKit/MetalKit.h>
#import "MetalEngine-Swift.h"

@interface MetalRendererView : MTKView <MTKViewDelegate>
{
	@public
	MetalRenderer *renderer;
}

@end

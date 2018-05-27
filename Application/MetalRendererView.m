//
//  MetalRendererView.m
//  MetalEngine-macOS
//
//  Created by Andy Korth on 5/26/18.
//  Copyright © 2018 Apple. All rights reserved.
//

#import "MetalRendererView.h"

@implementation MetalRendererView


- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
	[renderer drawInMTKView:self];

}

- (void)mouseDragged:(NSEvent *)theEvent {
	[renderer mouseX: [theEvent deltaX] mouseY: [theEvent deltaY]];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size{
	[renderer mtkView:self drawableSizeWillChange:size];
}

@end

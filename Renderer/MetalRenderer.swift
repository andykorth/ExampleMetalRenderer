//
//  MetalRenderer.swift
//  MetalEngine-macOS
//
//  Created by Andy Korth on 5/23/18.
//  Copyright © 2018 Andy Korth. All rights reserved.
//

import Foundation
import MetalKit

// this seems naughty, but it is quite convenient
extension String: Error {}

class MetalRenderer: NSObject, MTKViewDelegate{
	
	// The device (aka GPU) we're using to render
	var device : MTLDevice
	var pipelineState : MTLRenderPipelineState
	var commandQueue : MTLCommandQueue
	var viewportSize : vector_uint2
	var mesh : MDLMesh
	
	init(view : MTKView) throws {
		// perform some initialization here
		device = view.device!
		viewportSize = vector_uint2(0, 0)
		
		// Load all the shader files with a .metal file extension in the project
		let default📚 = device.newDefaultLibrary()!
		
		// Load the vertex and fragment function from the library
		let vertexFunction = default📚.makeFunction(name: "vertexShader")
		let fragmentFunction = default📚.makeFunction(name: "fragmentShader")
		
		// Configure a pipeline descriptor that is used to create a pipeline state
		let pipelineDesc : MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor.init()
		pipelineDesc.vertexFunction = vertexFunction;
		pipelineDesc.fragmentFunction = fragmentFunction;
		pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;

		do{
			try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
		}catch{
			// Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
			//  If the Metal API validation is enabled, we can find out more information about what
			//  went wrong.  (Metal API validation is enabled by default when a debug build is run
			//  from Xcode)
			throw "Failed to created pipeline state, error \(error)";
			
		}
		
		// Create the command queue
		commandQueue = device.makeCommandQueue()
		
		// Load the .OBJ file
		guard let url = Bundle.main.url(forResource: "capsule", withExtension: "obj") else {
			fatalError("Failed to find model file.")
		}
		
		let asset = MDLAsset.init(url: url)
		guard let mesh = asset.object(at: 0) as? MDLMesh else {
			fatalError("Failed to get mesh from asset.")
		}
		print("Vertex count: \(mesh.vertexCount)")
		self.mesh = mesh
		
		super.init()
	}
	
	func draw(in view: MTKView) {
		
		let meshes = try MTKMesh.newMeshes(from: asset, device: device!, sourceMeshes: nil)
		
		
		let vertices : [Vertex] = []
		
//		let vertices = [
//			Vertex(position: float3(100, -100, 0) , color: float4(1, 0, 0, 1)),
//			Vertex(position: float3(100, 100, 0)  , color: float4(0, 1, 0, 1)),
//			Vertex(position: float3(-100, 100, 0) , color: float4(0, 0, 1, 1)),
//			Vertex(position: float3(-100, -100, 0), color: float4(0, 0, 0, 1))
//		]
		
		// Create a new command buffer for each render pass to the current drawable
		let buffer = commandQueue.makeCommandBuffer()
		buffer.label = "Andy-Commands"
		
		// Obtain a renderPassDescriptor generated from the view's drawable textures
		let renderPassDescriptor = view.currentRenderPassDescriptor;
		
		if(renderPassDescriptor != nil)
		{
			// Create a render command encoder so we can render into something
			let renderEncoder : MTLRenderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
			renderEncoder.label = "AndyRenderEncoder";
			
			// Set the region of the drawable to which we'll draw.
			renderEncoder.setViewport(MTLViewport.init(originX: 0, originY: 0, width: Double(viewportSize.x), height: Double(viewportSize.y), znear: -1, zfar: 1))
			renderEncoder.setRenderPipelineState(pipelineState)
			
			// We call -[MTLRenderCommandEncoder setVertexBytes:length:atIndex:] to send data from our
			//   Application ObjC code here to our Metal 'vertexShader' function
			// This call has 3 arguments
			//   1) A pointer to the memory we want to pass to our shader
			//   2) The memory size of the data we want passed down
			//   3) An integer index which corresponds to the index of the buffer attribute qualifier
			//      of the argument in our 'vertexShader' function
			
			// You send a pointer to the `triangleVertices` array also and indicate its size
			// The `BufferArgumentIndexVertices` enum value corresponds to the `vertexArray`
			// argument in the `vertexShader` function because its buffer attribute also uses
			// the `BufferArgumentIndexVertices` enum value for its index
			let pos = MemoryLayout<Vertex>.stride * vertices.count;
			renderEncoder.setVertexBytes(vertices, length: pos, at: Int(BufferArgumentIndexVertices.rawValue) )
			
			// You send a pointer to `_viewportSize` and also indicate its size
			// The `BufferArgumentIndexViewportSize` enum value corresponds to the
			// `viewportSizePointer` argument in the `vertexShader` function because its
			//  buffer attribute also uses the `BufferArgumentIndexViewportSize` enum value
			//  for its index
			renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<vector_uint2>.stride, at: Int(BufferArgumentIndexViewportSize.rawValue))
			
			renderEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: vertices.count)
			renderEncoder.endEncoding()
			
			// Schedule a present once the framebuffer is complete using the current drawable
			buffer.present(view.currentDrawable!)
		}
		
		// Finalize rendering here & push the command buffer to the GPU
		buffer.commit()
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		// Save the size of the drawable as we'll pass these
		//   values to our vertex shader when we draw
		viewportSize.x = UInt32(size.width)
		viewportSize.y = UInt32(size.height)
	}
	
	
}

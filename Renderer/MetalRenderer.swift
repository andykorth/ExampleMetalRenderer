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
	var mesh : MTKMesh
	var view : MTKView
	
	// better place to put this?
	let depthStencilState : MTLDepthStencilState
	
	// input:
	var scrollX : Float = 0
	var scrollY : Float = 0
	var zoom : Float = 0
	
	init(view : MTKView) throws {

		
		// perform some initialization here
		device = view.device!
		viewportSize = vector_uint2(0, 0)
		
		view.clearColor = MTLClearColorMake(0.5, 0.5, 1, 1)
		view.colorPixelFormat = .bgra8Unorm
		view.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
		self.view = view;
		
		let descriptor = MTLDepthStencilDescriptor()
		descriptor.depthCompareFunction = MTLCompareFunction.less
		descriptor.isDepthWriteEnabled = true
		
		depthStencilState = device.makeDepthStencilState(descriptor: descriptor)

		// Load all the shader files with a .metal file extension in the project
		let default📚 = device.newDefaultLibrary()!
		
		// Load the vertex and fragment function from the library
		let vertexFunction = default📚.makeFunction(name: "vertexShader")
		let fragmentFunction = default📚.makeFunction(name: "fragmentShader")
		
		// sometimes you need a vertex descriptor:
		// --- "Vertex function has input attributes but no vertex descriptor was set"
		let vertexDescriptor = MTLVertexDescriptor()
		vertexDescriptor.attributes[0].offset = 0
		vertexDescriptor.attributes[0].format = MTLVertexFormat.float3 // position
		vertexDescriptor.attributes[1].offset = 12
		vertexDescriptor.attributes[1].format = MTLVertexFormat.uchar4 // color
		vertexDescriptor.attributes[2].offset = 16
		vertexDescriptor.attributes[2].format = MTLVertexFormat.half2 // texture
		vertexDescriptor.attributes[3].offset = 20
		vertexDescriptor.attributes[3].format = MTLVertexFormat.float // occlusion
		vertexDescriptor.layouts[0].stride = 24
		
		// Configure a pipeline descriptor that is used to create a pipeline state
		let pipelineDesc : MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor.init()
		pipelineDesc.vertexDescriptor = vertexDescriptor
		pipelineDesc.vertexFunction = vertexFunction
		pipelineDesc.fragmentFunction = fragmentFunction
		pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
		
		pipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
		pipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat

		do{
			try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
		}catch{
			// Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
			//  If the Metal API validation is enabled, we can find out more information about what
			//  went wrong.  (Metal API validation is enabled by default when a debug build is run
			//  from Xcode)
			print("Failed to created pipeline state, error \(error)")
			fatalError("Failed to created pipeline state, error \(error)")
		}
		
		// Create the command queue
		commandQueue = device.makeCommandQueue()
		
		print("Loading obj file...")
		let testMesh : ObjMesh = ObjMesh.init(objName: "Turntable", device: device)
		self.mesh = testMesh.meshes.first!

		print("Vertex count: \(mesh.vertexCount)")
		
		super.init()
		
	}
	
	func mouseDragged(theEvent : NSEvent) {
		mouseX(Float(theEvent.deltaX), mouseY: Float(theEvent.deltaY))
	}
	
	func mouseX(_ dx : Float, mouseY dy : Float){
		//print("mouse moved: \(dx), \(dy)")
		
		scrollX = (scrollX + dx)//.truncatingRemainder(dividingBy: 360.0)
		scrollY = (scrollY + dy)//.truncatingRemainder(dividingBy: 360.0)
	}
	
	func setupUniforms(renderEncoder : MTLRenderCommandEncoder){
		
		// Set the region of the drawable to which we'll draw.
		renderEncoder.setViewport(MTLViewport.init(originX: 0, originY: 0, width: Double(viewportSize.x), height: Double(viewportSize.y), znear: -1, zfar: 1))
		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setDepthStencilState(depthStencilState)
		renderEncoder.setCullMode(.back)
		renderEncoder.setFrontFacing(.counterClockwise)
		
		let scaled = scalingMatrix(1)
		let rotated = matrix_multiply( rotationMatrix(scrollY / -100.0, float3(1, 0, 0)),
			rotationMatrix(scrollX / -100.0, float3(0, 1, 0)) )
		let translated = translationMatrix(float3(0, 0, 0))
		let modelMatrix = matrix_multiply(matrix_multiply(translated, rotated), scaled)
		let cameraPosition = float3(0, -5, -25 + zoom)
		let viewMatrix = translationMatrix(cameraPosition)
		let aspect = Float(viewportSize.x / viewportSize.y)
		let projMatrix = projectionMatrix(0.1, far: 200, aspect: aspect, fovy: 1)
		let modelViewProjectionMatrix = matrix_multiply(projMatrix, matrix_multiply(viewMatrix, modelMatrix))
		
		// fill uniform buffer:
		let uniformsBuffer = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.size, options: [])
		
		let mvpMatrix = Uniforms(modelViewProjectionMatrix: modelViewProjectionMatrix)
		uniformsBuffer.contents().storeBytes(of: mvpMatrix, toByteOffset: 0, as: Uniforms.self)
		
		renderEncoder.setVertexBuffer(uniformsBuffer, offset: 0, at: Int(BufferArgumentIndexUniforms.rawValue))

	}

	func draw(in view: MTKView) {
		
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
			
			self.setupUniforms(renderEncoder: renderEncoder)
			
			// step 4: set up Metal rendering and drawing of meshes
			
			let vertexBuffer = mesh.vertexBuffers[0]
			renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, at: Int(BufferArgumentIndexVertices.rawValue))
			
			for submesh in mesh.submeshes {
				renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
			}
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

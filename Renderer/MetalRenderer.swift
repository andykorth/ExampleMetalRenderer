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

public extension Float {
	/// Returns a random floating point number between 0.0 and 1.0, inclusive.
	public static var random: Float {
		return Float(arc4random()) / 0xFFFFFFFF
	}
}
	
class MetalRenderer: NSObject, MTKViewDelegate{
	
	// The device (aka GPU) we're using to render
	var device : MTLDevice
	var commandQueue : MTLCommandQueue
	var viewportSize : vector_uint2
	var view : MTKView
	var objMesh : ObjMesh
	var cubemapTex : MTLTexture!
	private let default📚 : MTLLibrary
	
	var vertexDescriptor : MTLVertexDescriptor
	
	// better place to put this?
	let depthStencilState : MTLDepthStencilState
	
	// input:
	var scrollX = 0.0
	var scrollY = 0.0
	var zoom : Float = 0
	
	let startTime : CFAbsoluteTime

	init(view : MTKView) throws {
		startTime = CFAbsoluteTimeGetCurrent()

		
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
		default📚 = device.newDefaultLibrary()!
		
		// sometimes you need a vertex descriptor:
		// --- "Vertex function has input attributes but no vertex descriptor was set"
		vertexDescriptor = MTLVertexDescriptor()
		vertexDescriptor.attributes[0].offset = 0
		vertexDescriptor.attributes[0].format = MTLVertexFormat.float3 // position
		vertexDescriptor.attributes[1].offset = 12
		vertexDescriptor.attributes[1].format = MTLVertexFormat.float3 // normal
		vertexDescriptor.attributes[2].offset = 12+12
		vertexDescriptor.attributes[2].format = MTLVertexFormat.uchar4 // color
		vertexDescriptor.attributes[3].offset = 16+12
		vertexDescriptor.attributes[3].format = MTLVertexFormat.half2 // texture
		vertexDescriptor.attributes[4].offset = 20+12
		vertexDescriptor.attributes[4].format = MTLVertexFormat.float // occlusion
		vertexDescriptor.layouts[0].stride = 24+12
		
		// Create the command queue
		commandQueue = device.makeCommandQueue()
		
		print("Loading obj file...")
		objMesh = ObjMesh.init(objName: "Turntable", vd: vertexDescriptor, device: device)
		objMesh.addTexture(name: "moped_d", index: 0, forSubmesh: 10)
		objMesh.addTexture(name: "moped_s", index: 1, forSubmesh: 10)
		objMesh.addTexture(name: "moped_glow", index: 2, forSubmesh: 10)

		objMesh.addTexture(name: "turntable_d", index: 0, forSubmesh: 9)
		objMesh.addTexture(name: "turntable_s", index: 1, forSubmesh: 9)
		objMesh.addTexture(name: "turntable_n", index: 2, forSubmesh: 9)
		
		print("Vertex count: \(objMesh.mesh.vertexCount)")
		super.init()

		print("Loading cubemaps...")
		cubemapTex = loadCubemapTexture(name: "miramar")
	}
	
	func createPipelineState(vertex v : String, fragment frag : String) -> MTLRenderPipelineState {
		return createPipelineState(vertex: v, fragment: frag, vertexDescriptor: self.vertexDescriptor)
	}
	
	func createPipelineState(vertex v : String, fragment frag : String, vertexDescriptor vertexDesc : MTLVertexDescriptor ) -> MTLRenderPipelineState {
		let vertexFunction = default📚.makeFunction(name: v)
		let fragmentFunction = default📚.makeFunction(name: frag)
		
		 // Configure a pipeline descriptor that is used to create a pipeline state
		 let pipelineDesc : MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor.init()
		 pipelineDesc.vertexDescriptor = vertexDesc
		 pipelineDesc.vertexFunction = vertexFunction
		 pipelineDesc.fragmentFunction = fragmentFunction
		 pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
		
		 pipelineDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
		 pipelineDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
		
		 do{
			return try device.makeRenderPipelineState(descriptor: pipelineDesc)
		 }catch{
			// Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
			//  If the Metal API validation is enabled, we can find out more information about what
			//  went wrong.  (Metal API validation is enabled by default when a debug build is run
			//  from Xcode)
			print("Failed to created pipeline state, error \(error)")
			fatalError("Failed to created pipeline state, error \(error)")
		}
	}
	
	func mouseDragged(theEvent : NSEvent) {
		mouseX(Double(theEvent.deltaX), mouseY: Double(theEvent.deltaY))
	}
	
	func mouseX(_ dx : Double, mouseY dy : Double){
		//print("mouse moved: \(dx), \(dy)")
		
		scrollX = (scrollX + dx)//.truncatingRemainder(dividingBy: 360.0)
		scrollY = (scrollY + dy)//.truncatingRemainder(dividingBy: 360.0)
	}
	
	func setupUniforms(renderCommands : MTLRenderCommandEncoder){
		
		// Set the region of the drawable to which we'll draw.
		renderCommands.setViewport(MTLViewport.init(originX: 0, originY: 0, width: Double(viewportSize.x), height: Double(viewportSize.y), znear: -1, zfar: 1))
		
		renderCommands.setDepthStencilState(depthStencilState)
		renderCommands.setCullMode(.back)
		renderCommands.setFrontFacing(.counterClockwise)
		
		let scaled = scalingMatrix(1)
		let rotated = matrix_multiply( rotationMatrix( Float(scrollY / -100.0), float3(1, 0, 0)),
			rotationMatrix(  Float(scrollX / -100.0), float3(0, 1, 0)) )
		let translated = translationMatrix(float3(0, 0, 0))
		let modelMatrix = matrix_multiply(matrix_multiply(translated, rotated), scaled)
		let cameraPosition = float3(0, -5, -25 + zoom)
		let viewMatrix = translationMatrix(cameraPosition)
		let aspect = Float(viewportSize.x / viewportSize.y)
		let projMatrix = projectionMatrix(0.1, far: 200, aspect: aspect, fovy: Float(Double.pi / 3.0))
	
		let modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
		let modelViewProjectionMatrix = matrix_multiply(projMatrix, modelViewMatrix)
		let modelViewProjectionIMatrix = matrix_invert(modelViewProjectionMatrix)
		let normalMatrix = matrix_transpose(matrix_invert(modelViewMatrix));
		
		// fill uniform buffer:
		let uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: [])
		
		let t = (CFAbsoluteTimeGetCurrent() - startTime) // todo need monotonic time.
		
		let s = sin (t / .pi);
		let c = cos (t / .pi);
		//Vector3 v = new Vector3 (s, Math.Abs (c * 0.2f) + 0.1f, 0f);
		var lightDir : vector_float4 = vector_float4(Float(s), 0.3, Float(c), 0);
		lightDir = normalize(lightDir)
		
		var eyeDir = vector_float4( Float(cos(scrollX * Double.pi / 2.0) * sin(scrollY * Double.pi / 2.0)),
									Float(cos(scrollY * Double.pi / 2.0)),
									Float(sin(scrollX * Double.pi / 2.0) * sin(-scrollY * Double.pi / 2.0)),
									1) // * cameraPos.z;
		eyeDir = normalize(eyeDir)

		let uniforms = Uniforms(
			MVP_Matrix: modelViewProjectionMatrix,
			MVP_i_Matrix: modelViewProjectionIMatrix,
			MV_Matrix: modelViewMatrix,
			normal_Matrix: normalMatrix,
			lightDirection: lightDir,
			timeUniform: vector_float4(Float(t), Float(t), Float(t), Float(t)),
			sinTime: vector_float4(Float(sin(t)), Float(sin(t*2)), Float(sin(t*4)), Float(sin(t*8))),
			cosTime: vector_float4(Float(cos(t)), Float(cos(t*2)), Float(cos(t*4)), Float(cos(t*8))),
			rand01: vector_float4(Float.random, Float.random, Float.random, Float.random),
			mainTextureSize: vector_float4(),
			eyeDirection: eyeDir
		)
		
		uniformsBuffer.contents().storeBytes(of: uniforms, toByteOffset: 0, as: Uniforms.self)
		
		// Want to send this data to both vertex and fragment shaders.
		renderCommands.setVertexBuffer(uniformsBuffer, offset: 0, at: Int(BufferArgumentIndexUniforms.rawValue))
		renderCommands.setFragmentBuffer(uniformsBuffer, offset: 0, at: Int(BufferArgumentIndexUniforms.rawValue))
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
			let renderCommands : MTLRenderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
			renderCommands.label = "AndyRenderEncoder";
			
			renderCommands.pushDebugGroup(":) Setup Uniforms")
			self.setupUniforms(renderCommands: renderCommands)
			renderCommands.popDebugGroup()

			renderCommands.pushDebugGroup(":) Draw Skybox")
			self.drawSkybox(renderCommands)
			renderCommands.popDebugGroup()
			
			// reset the stencil state to depth testing on.
			renderCommands.setDepthStencilState(depthStencilState)
			
			let vertexBuffer = objMesh.mesh.vertexBuffers[0]
			renderCommands.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, at: Int(BufferArgumentIndexVertices.rawValue))
			
			for (submeshIndex, submesh) in  objMesh.mesh.submeshes.enumerated() {
				renderCommands.pushDebugGroup(":) Draw Submesh \(submeshIndex) named: \(submesh.name)")

//				let submesh = objMesh.mesh.submeshes[submeshIndex]
				// bind the appropriate textures for the submeshes:
				
				if let submeshArray = objMesh.textures[submeshIndex] {
					// now val is not nil and the Optional has been unwrapped, so use it
					for i in 0 ... submeshArray.count {
						renderCommands.setFragmentTexture(submeshArray[i], at: i)
					}
				}
				
				if(submeshIndex == 10){
					// main moped mesh:
					renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: "fragEyeNormals"))
				}else if(submeshIndex == 9){
					// mesh for turntable
					renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: "fragEyeNormals"))
				}else{
					// mirrors, headlights, etc.
					renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: "fragEyeNormals"))
				}

				renderCommands.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
				renderCommands.popDebugGroup()
			}
			renderCommands.endEncoding()
			
			// Schedule a present once the framebuffer is complete using the current drawable
			buffer.present(view.currentDrawable!)
		}
		
		// Finalize rendering here & push the command buffer to the GPU
		buffer.commit()
	}
	
	func drawSkybox(_ renderCommands : MTLRenderCommandEncoder){
		
		let skyVD = MTLVertexDescriptor()

		// disable depth write:
		do {
			let descriptor = MTLDepthStencilDescriptor()
			descriptor.depthCompareFunction = MTLCompareFunction.always
			descriptor.isDepthWriteEnabled = false
			
			let depthStencilState = device.makeDepthStencilState(descriptor: descriptor)
			renderCommands.setDepthStencilState(depthStencilState)
		}

		renderCommands.setFragmentTexture(self.cubemapTex!, at: 0)
		
		renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexSkybox", fragment: "fragSkybox", vertexDescriptor: skyVD))
		renderCommands.setVertexBuffer(nil, offset: 0, at: Int(BufferArgumentIndexVertices.rawValue))
		renderCommands.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4)
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		// Save the size of the drawable as we'll pass these
		//   values to our vertex shader when we draw
		viewportSize.x = UInt32(size.width)
		viewportSize.y = UInt32(size.height)
	}
	
	func loadCubemapTexture(name texturePrefix : String) -> MTLTexture {

		let loader = MTKTextureLoader(device: device)
		let bytesPP = 4
		let size = 1024
		let ROW_BYTES = bytesPP * size
		let IMAGE_BYTES = ROW_BYTES * size

		do {
			let cubemapDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: MTLPixelFormat.bgra8Unorm, size: size, mipmapped: false)
			let cubemap = device.makeTexture(descriptor: cubemapDesc)
			
			let textureLoaderOptions: [String: NSObject]
			textureLoaderOptions = [MTKTextureLoaderOptionSRGB : NSString(string: "MTKTextureLoaderOptionSRGB") ]
			
			let region : MTLRegion = MTLRegion.init(origin: MTLOrigin.init(x: 0, y: 0, z: 0),
													size: MTLSize.init(width: size, height: size, depth: 1))
			
			for (slice) in 0 ... 5
			{
				var postfix : String = "invalidSlice"
				if(slice == 0) { postfix = "xPos" }
				if(slice == 1) { postfix = "xNeg" }
				if(slice == 2) { postfix = "yPos" }
				if(slice == 3) { postfix = "yNeg" }
				if(slice == 4) { postfix = "zPos" }
				if(slice == 5) { postfix = "zNeg" }
				
				if let file = Bundle.main.path(forResource: "\(texturePrefix)_\(postfix)", ofType: "png") {
				    let url = URL(fileURLWithPath: file)
					let data = try Data(contentsOf: url)
					print("Loading texture: \(url)")
					
					let texture = try loader.newTexture(with: data, options: textureLoaderOptions )
					
					var bunchaData = [UInt8](repeating: 0, count: Int(IMAGE_BYTES))
					
					texture.getBytes(&bunchaData, bytesPerRow: ROW_BYTES, from: region, mipmapLevel: 0)
					
					cubemap.replace(region: region, mipmapLevel: 0, slice: slice, withBytes: bunchaData, bytesPerRow: bytesPP * size, bytesPerImage: bytesPP * size * size)
				}else{
					print("Missing file: \(texturePrefix)_\(postfix)")
				}
				
			}
			return cubemap
		}
		catch let error {
			fatalError("\(error)")
		}
		
	}
}

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
	private let default📚 : MTLLibrary
	
	let view : MTKView
	var viewport = MTLViewport()
	let offscreenPixelFormat = MTLPixelFormat.rgba16Float
	var offscreenBuffer : MTLTexture?
	let offscreenAttachment = MTLRenderPassColorAttachmentDescriptor()
	let offscreenPassDesc = MTLRenderPassDescriptor()
	let blitState : MTLRenderPipelineState
	let depthStencilState : MTLDepthStencilState
	let depthDisabledState : MTLDepthStencilState
	
	let objMesh : ObjMesh
	var cubemapTex : MTLTexture
	var selectedShader = "fragPureReflection"
	
	var vertexDesc : MTLVertexDescriptor
	
	// input:
	var scrollX = 0.0
	var scrollY = 0.0
	var zoom : Float = 0
	
	init(view : MTKView) throws {
		// perform some initialization here
		device = view.device!
		commandQueue = device.makeCommandQueue()
		
		// Load all the shader files with a .metal file extension in the project
		default📚 = device.newDefaultLibrary()!
		
		view.clearColor = MTLClearColorMake(0.5, 0.5, 1, 1)
		view.colorPixelFormat = .bgra8Unorm
		view.depthStencilPixelFormat = .depth32Float_stencil8
		self.view = view;
		
		offscreenAttachment.loadAction = .clear
		offscreenAttachment.storeAction = .store
		offscreenAttachment.clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 0)
		
		do {
			let blitDesc = MTLRenderPipelineDescriptor()
			blitDesc.vertexDescriptor = MTLVertexDescriptor()
			blitDesc.vertexFunction = default📚.makeFunction(name: "vertBlit")
			blitDesc.fragmentFunction = default📚.makeFunction(name: "fragBlit")
			blitDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
			blitDesc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
			blitDesc.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
			try blitState = device.makeRenderPipelineState(descriptor: blitDesc)
		} catch {
			fatalError("Failed to created pipeline state, error \(error)")
		}
		
		do {
			let desc = MTLDepthStencilDescriptor()
			desc.depthCompareFunction = .less
			desc.isDepthWriteEnabled = true
			depthStencilState = device.makeDepthStencilState(descriptor: desc)
		}
		
		do {
			let desc = MTLDepthStencilDescriptor()
			desc.depthCompareFunction = .always
			desc.isDepthWriteEnabled = false
			depthDisabledState = device.makeDepthStencilState(descriptor: desc)
		}

		cubemapTex = MetalRenderer.loadCubemapTexture(device: device, name: "miramar")
		
		// sometimes you need a vertex descriptor:
		// --- "Vertex function has input attributes but no vertex descriptor was set"
		vertexDesc = MTLVertexDescriptor()
		let attribs = vertexDesc.attributes
		attribs[0].offset = 0
		attribs[0].format = .float3 // position
		attribs[1].offset = 12
		attribs[1].format = .float3 // normal
		attribs[2].offset = 12+12
		attribs[2].format = .uchar4 // color
		attribs[3].offset = 16+12
		attribs[3].format = .half2 // texture
		attribs[4].offset = 20+12
		attribs[4].format = .float // occlusion
		vertexDesc.layouts[0].stride = 24+12
		
		print("Loading obj file...")
		objMesh = ObjMesh(objName: "Turntable", vd: vertexDesc, device: device)
		print("Vertex count: \(objMesh.mesh.vertexCount)")
				
		print("Loading other textures...")
		objMesh.addTexture(name: "turntable_d", index: 0, forSubmesh: 9)
		objMesh.addTexture(name: "turntable_s", index: 1, forSubmesh: 9)
		objMesh.addTexture(name: "turntable_n", index: 2, forSubmesh: 9)
		objMesh.addCubemapTexture(cubemapTex, index: 3, forSubmesh: 9)
		
		objMesh.addTexture(name: "moped_d", index: 0, forSubmesh: 10)
		objMesh.addTexture(name: "moped_s", index: 1, forSubmesh: 10)
		objMesh.addTexture(name: "moped_glow", index: 2, forSubmesh: 10)
		objMesh.addCubemapTexture(cubemapTex, index: 3, forSubmesh: 10)
		
		super.init()
	}
	
	func createPipelineState(vertex v : String, fragment frag : String) -> MTLRenderPipelineState {
		return createPipelineState(vertex: v, fragment: frag, vertexDescriptor: vertexDesc)
	}
	
	func createPipelineState(vertex v : String, fragment frag : String, vertexDescriptor vertexDesc : MTLVertexDescriptor ) -> MTLRenderPipelineState {
		let vertexFunction = default📚.makeFunction(name: v)
		var fragmentFunction = default📚.makeFunction(name: frag)
		
//		withUnsafePointer(to: &fragmentFunction) {
//			print(" frag \(frag) value \(fragmentFunction) has address: \($0)")
//		}
	
		
		 // Configure a pipeline descriptor that is used to create a pipeline state
		 let pipelineDesc = MTLRenderPipelineDescriptor()
		 pipelineDesc.vertexDescriptor = vertexDesc
		 pipelineDesc.vertexFunction = vertexFunction
		 pipelineDesc.fragmentFunction = fragmentFunction
		 pipelineDesc.colorAttachments[0].pixelFormat = offscreenPixelFormat
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
	
	func keyDown(theEvent : NSEvent) {
		print("Key down: \(theEvent.keyCode)")
		
		if let chars : String = theEvent.characters {
			let charVal = Int(UnicodeScalar(chars)!.value)

			let a = Int(UnicodeScalar("a").value)
			let z = Int(UnicodeScalar("z").value)

			let arr = ["fragRed", "fragUV", "fragDiffuse", "fragVertexNormals", "fragDiffuseLighting", "fragDiffuseAndSpecular", "fragEyeNormals", "fragEyeReflectionVector", "fragPureReflection", "fragDiffuseSpecularReflection"]

			if charVal >= a && charVal <= z {
				
				let index = charVal - a
				if(index < arr.count){
					print("Switch shader to: \(index)  -  \(arr[index])")
					selectedShader = arr[index]
				}
			}
		}
	}
	
	func mouseDragged(theEvent : NSEvent) {
		mouseX(Double(theEvent.deltaX), mouseY: Double(theEvent.deltaY))
	}
	
	func mouseX(_ dx : Double, mouseY dy : Double){
		//print("mouse moved: \(dx), \(dy)")
		scrollX = scrollX + dx * 0.004 // in radians
		scrollY = scrollY + dy * 0.004
	}
	
	func setupUniforms(renderCommands : MTLRenderCommandEncoder){
		renderCommands.setViewport(viewport)
		renderCommands.setDepthStencilState(depthStencilState)
		renderCommands.setCullMode(.back)
		renderCommands.setFrontFacing(.counterClockwise)
		
		// scroll x and y in radians.
		let rotated = matrix_multiply( rotationMatrix( Float(-scrollY), float3(1, 0, 0)),
			rotationMatrix(  Float(-scrollX), float3(0, 1, 0)) )
		let translated = translationMatrix(float3(0, 0, 0))
		let modelMatrix = matrix_multiply(translated, rotated)
		let cameraPosition = float3(0, -5, -25 + zoom)
		let viewMatrix = translationMatrix(cameraPosition)
		let aspect = Float(viewport.width / viewport.height)
		let projMatrix = projectionMatrix(0.1, far: 200, aspect: aspect, fovy: Float(Double.pi / 3.0))
	
		let modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix)
		let modelViewProjectionMatrix = matrix_multiply(projMatrix, modelViewMatrix)

		var normalMatrix = matrix_transpose(matrix_invert(modelViewMatrix));
		// normal matrix should be a 3x3, so we'll omit the translation.
		normalMatrix[0, 3] = 0
		normalMatrix[1, 3] = 0
		normalMatrix[2, 3] = 0
		normalMatrix[3, 3] = 0

		normalMatrix[3, 0] = 0
		normalMatrix[3, 1] = 0
		normalMatrix[3, 2] = 0

		// fill uniform buffer:
		let uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: [])
		
		let t = CACurrentMediaTime()
		
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
			MVP_i_Matrix: matrix_invert(modelViewProjectionMatrix),
			MV_Matrix: modelViewMatrix,
			MV_i_Matrix: matrix_invert(modelViewMatrix),
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
		
		let viewDesc = view.currentRenderPassDescriptor!
		offscreenAttachment.texture = offscreenBuffer
		offscreenPassDesc.colorAttachments[0] = offscreenAttachment
		offscreenPassDesc.depthAttachment = viewDesc.depthAttachment
		offscreenPassDesc.stencilAttachment = viewDesc.stencilAttachment
		
		// Create a render command encoder so we can render into something
		let renderCommands : MTLRenderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: offscreenPassDesc)
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
				renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: selectedShader))
			}else if(submeshIndex == 9){
				// mesh for turntable
				renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: selectedShader))
			}else{
				// mirrors, headlights, etc.
				renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexShader", fragment: "fragRed"))
			}

			renderCommands.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
			renderCommands.popDebugGroup()
		}
		renderCommands.endEncoding()
		
		let blit = buffer.makeRenderCommandEncoder(descriptor: viewDesc)
		blit.setFragmentTexture(offscreenBuffer, at: 0)
		blit.setRenderPipelineState(blitState)
		blit.setVertexBuffer(nil, offset: 0, at: Int(BufferArgumentIndexVertices.rawValue))
		blit.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4);
		blit.endEncoding()
		
		buffer.present(view.currentDrawable!)
		buffer.commit()
	}
	
	func drawSkybox(_ renderCommands : MTLRenderCommandEncoder){
		let skyVD = MTLVertexDescriptor()

		renderCommands.setDepthStencilState(depthDisabledState)
		renderCommands.setFragmentTexture(self.cubemapTex, at: 0)
		
		renderCommands.setRenderPipelineState(createPipelineState(vertex: "vertexSkybox", fragment: "fragSkybox", vertexDescriptor: skyVD))
		renderCommands.setVertexBuffer(nil, offset: 0, at: Int(BufferArgumentIndexVertices.rawValue))
		renderCommands.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		viewport = MTLViewport(originX: 0, originY: 0, width: Double(size.width), height: Double(size.height), znear: -1, zfar: 1)
		
		let offscreenBufferDesc = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: offscreenPixelFormat,
			width:Int(size.width),
			height:Int(size.height),
			mipmapped: false
		)
		
		offscreenBufferDesc.usage = [.shaderRead, .renderTarget]
		offscreenBuffer = device.makeTexture(descriptor:offscreenBufferDesc)
	}
	
	static func loadCubemapTexture(device : MTLDevice, name texturePrefix : String) -> MTLTexture {
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
			
			let region : MTLRegion = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
													size: MTLSize(width: size, height: size, depth: 1))
			
			for slice in 0 ... 5 {
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
				} else {
					print("Missing file: \(texturePrefix)_\(postfix)")
				}
				
			}
			
			return cubemap
		} catch let error {
			fatalError("\(error)")
		}
	}
}

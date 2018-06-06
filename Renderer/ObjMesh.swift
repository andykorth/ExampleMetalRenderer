//
//  ObjMesh.swift
//  MetalEngine-macOS
//
//  Created by Andy Korth on 5/24/18.
//  Copyright © 2018 Andy Korth. All rights reserved.
//

import Foundation
import ModelIO
import MetalKit

class ObjMesh {
	
	var meshes: [MTKMesh]
	let vertexDescriptor : MTLVertexDescriptor
	var loader : MTKTextureLoader
	// submesh then texture index
	var textures: [Int : [Int: MTLTexture]]
	
	var mesh : MTKMesh {
		get{
			return meshes.first!
		}
	}
	
	init(objName : String, vd : MTLVertexDescriptor, device : MTLDevice) {
		
		vertexDescriptor = vd
		
		let desc = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
		var attribute = desc.attributes[0] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributePosition
		attribute = desc.attributes[1] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeNormal
		attribute = desc.attributes[2] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeColor
		attribute = desc.attributes[3] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeTextureCoordinate
		attribute = desc.attributes[4] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeOcclusionValue
		let mtkBufferAllocator = MTKMeshBufferAllocator(device: device)
		guard let url = Bundle.main.url(forResource: objName, withExtension: "obj") else {
			fatalError("Resource not found.")
		}
		print("Load asset from url : \(url)")
		
		let asset = MDLAsset(url: url, vertexDescriptor: desc, bufferAllocator: mtkBufferAllocator)
		
		// step 3: set up MetalKit mesh and submesh objects
		loader = MTKTextureLoader(device: device)
		
		guard let mesh = asset.object(at: 0) as? MDLMesh else {
			fatalError("Mesh not found.")
		}
//		mesh.generateAmbientOcclusionVertexColors(withQuality: 1, attenuationFactor: 0.98, objectsToConsider: [mesh], vertexAttributeNamed: MDLVertexAttributeOcclusionValue)
		print("Generating mesh from : \(asset) was \(mesh)")
		do {
			meshes = try MTKMesh.newMeshes(from: asset, device: device, sourceMeshes: nil)
		}
		catch let error {
			fatalError("\(error)")
		}
		
		let submeshes = meshes.first!.submeshes
		for i in 0..<submeshes.count {
			print("     Submesh \(i) was named \(submeshes[i].name)")
		}
		
		textures = [0: [Int:MTLTexture]()]
	}
	
	func addTexture(name objName : String, index texIndex : Int, forSubmesh submesh : Int){
		guard let file = Bundle.main.path(forResource: objName, ofType: "png") else {
			fatalError("Resource not found.")
		}
		
		do {
			let data = try Data(contentsOf: URL(fileURLWithPath: file))
			
			let textureLoaderOptions: [String: NSObject]
			textureLoaderOptions = [MTKTextureLoaderOptionSRGB : NSString(string: "MTKTextureLoaderOptionSRGB") ]

			let texture = try loader.newTexture(with: data, options: textureLoaderOptions )
			if textures[submesh] == nil{
				textures[submesh] = [Int : MTLTexture]()
			}
			textures[submesh]![texIndex] = texture;
		}
		catch let error {
			fatalError("\(error)")
		}
		
	}
}

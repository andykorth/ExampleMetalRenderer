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
	let vertexDescriptor = MTLVertexDescriptor()
	
	init(objName : String, device : MTLDevice) {
		
		// step 2: set up the asset initialization
		
		let desc = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
		var attribute = desc.attributes[0] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributePosition
		attribute = desc.attributes[1] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeColor
		attribute = desc.attributes[2] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeTextureCoordinate
		attribute = desc.attributes[3] as! MDLVertexAttribute
		attribute.name = MDLVertexAttributeOcclusionValue
		let mtkBufferAllocator = MTKMeshBufferAllocator(device: device)
		guard let url = Bundle.main.url(forResource: objName, withExtension: "obj") else {
			fatalError("Resource not found.")
		}
		let asset = MDLAsset(url: url, vertexDescriptor: desc, bufferAllocator: mtkBufferAllocator)
		
		//        let url1 = URL(string: "/Users/YourUsername/Desktop/exported.obj")
		//        try! asset.export(to: url1!)
		
		//let loader = MTKTextureLoader(device: device)
//		guard let file = Bundle.main.path(forResource: objName, ofType: "png") else {
//			fatalError("Resource not found.")
//		}
		/*
		do {
			let data = try Data(contentsOf: URL(fileURLWithPath: file))
			//texture = try loader.newTexture(with: data, options: nil)
		}
		catch let error {
			fatalError("\(error)")
		}
		*/
		
		// step 3: set up MetalKit mesh and submesh objects
		
		guard let mesh = asset.object(at: 0) as? MDLMesh else {
			fatalError("Mesh not found.")
		}
		mesh.generateAmbientOcclusionVertexColors(withQuality: 1, attenuationFactor: 0.98, objectsToConsider: [mesh], vertexAttributeNamed: MDLVertexAttributeOcclusionValue)
		do {
			meshes = try MTKMesh.newMeshes(from: asset, device: device, sourceMeshes: nil)
		}
		catch let error {
			fatalError("\(error)")
		}
	}
}

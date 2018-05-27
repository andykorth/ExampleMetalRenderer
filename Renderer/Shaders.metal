
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

// define some types only in here, can't share them :(

struct VertexIn {
	float4 position [[attribute(0)]];
	float4 color [[attribute(1)]];
	float2 texCoords [[attribute(2)]];
	float occlusion [[attribute(3)]];
};

struct VertexOut {
	float4 position [[position]];
	float4 color;
	float2 texCoords;
	float occlusion;
};

struct Uniforms {
	float4x4 modelViewProjectionMatrix;
};


// Vertex shader outputs and fragment shader inputs
typedef struct
{
    // The [[position]] attribute of this member indicates that this value is the clip space
    // position of the vertex when this structure is returned from the vertex function
    float4 clipSpacePosition [[position]];

    // Since this member does not have a special attribute, the rasterizer interpolates
    // its value with the values of the other triangle vertices and then passes
    // the interpolated value to the fragment shader for each fragment in the triangle
    float4 color;

} RasterizerData;

vertex VertexOut vertexShader(const VertexIn vertices [[stage_in]],
							 constant Uniforms &uniforms [[buffer(1)]],
							 uint vertexId [[vertex_id]])
{
	float4x4 mvpMatrix = uniforms.modelViewProjectionMatrix;
	float4 position = vertices.position;
	
	VertexOut out;
	out.position = mvpMatrix * position;
	out.color = float4(1);
	out.texCoords = vertices.texCoords;
	out.occlusion = vertices.occlusion;
	
	return out;
}

fragment half4 fragmentShader(VertexOut fragments [[stage_in]],
							 texture2d<float> textures [[texture(0)]])
{
	float4 baseColor = fragments.color;
	float4 occlusion = fragments.occlusion;
	constexpr sampler samplers;
	float4 texture = textures.sample(samplers, fragments.texCoords);
//	return half4(occlusion.r, occlusion.g, occlusion.b, 1); //half4(fragments.texCoords.x, fragments.texCoords.y, 0, 1);
	//return half4(baseColor.r, baseColor.g, baseColor.b, 1);
	//return half4(baseColor * occlusion * texture);
	return half4(fragments.texCoords.x, fragments.texCoords.y, 0, 1);
}

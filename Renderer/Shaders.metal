
#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

// define some types only in here, can't share them :(

struct VertexIn {
	float4 position [[attribute(0)]];
	float4 normals [[attribute(1)]];
	float4 color [[attribute(2)]];
	float2 texCoords [[attribute(3)]];
	float occlusion [[attribute(4)]];
};

struct VertexOut {
	float4 position [[position]];
	float4 normals;
	float4 color;
	float2 texCoords;
	float occlusion;
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
	out.normals = vertices.normals;
	
	return out;
}

fragment half4 fragUV(VertexOut fragments [[stage_in]] ) {
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	return half4(uv.x, uv.y, 0, 1);
}

fragment half4 fragVertexNormals(VertexOut fragments [[stage_in]],
								 constant Uniforms &uniforms [[buffer(1)]] )
{
	float2 n = fragments.normals.xy;
	return half4(n.x, n.y, uniforms.sinTime.x, 1);
}
	
fragment half4 fragDiffuse(VertexOut fragments [[stage_in]],
						   texture2d<float> diffuseTex [[texture(0)]]
						   )
{
	constexpr sampler linearSampler(s_address::repeat,
									t_address::repeat,
									mip_filter::linear,
									mag_filter::linear,
									min_filter::linear);
	
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	float4 diffuse = diffuseTex.sample(linearSampler, uv);
	return half4(diffuse);
}

fragment half4 frag(VertexOut fragments [[stage_in]],
							  texture2d<float> diffuseTex [[texture(0)]],
							  texture2d<float> specularTex [[texture(1)]],
							  texture2d<float> glowTex [[texture(2)]]
							  )
{
	float4 baseColor = fragments.color;
	float4 occlusion = fragments.occlusion;
	constexpr sampler linearSampler(s_address::repeat,
									t_address::repeat,
									mip_filter::linear,
									mag_filter::linear,
									min_filter::linear);
	
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	float4 diffuse = diffuseTex.sample(linearSampler, uv);
	float4 spec = specularTex.sample(linearSampler, uv);
	float4 glow = glowTex.sample(linearSampler, uv);
//	return half4(occlusion.r, occlusion.g, occlusion.b, 1); //half4(fragments.texCoords.x, fragments.texCoords.y, 0, 1);
	//return half4(baseColor.r, baseColor.g, baseColor.b, 1);
	//return half4(baseColor * occlusion * texture);
//	return half4(fragments.texCoords.x, fragments.texCoords.y, 0, 1);
	//return half4(glow.r, glow.g, glow.b, 1);

	//return half4(spec.a, spec.a, spec.a, 1);
	return half4(diffuse);// + half4(fragments.texCoords.x, fragments.texCoords.y, 0, 1);
}

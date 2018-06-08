
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
	float3 worldNormal;
	float4 color;
	float2 texCoords;
	float occlusion;
	float3 viewNormal;
	float3 reflectDir;
};

constexpr sampler linearSampler(s_address::repeat,
								t_address::repeat,
								mip_filter::linear,
								mag_filter::linear,
								min_filter::linear);

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
	float4x4 mvpMatrix = uniforms.MVP_Matrix;
	
	float4 position = vertices.position;
	float3 normal = uniforms.normal_Matrix * float3(vertices.normals);
	
	VertexOut out;
	out.position = mvpMatrix * position;
	out.color = float4(1);
	out.texCoords = vertices.texCoords;
	out.occlusion = vertices.occlusion;
	out.worldNormal = vertices.normals.xyz;
	out.viewNormal = normal;
	
	float3 incident = (uniforms.MV_Matrix * float4(position.xyz, 1)).xyz;
	float3 surfaceNormal = normalize(normal);

	out.reflectDir = (uniforms.MV_i_Matrix * float4(reflect( incident, surfaceNormal ), 0) ).xyz;
	return out;
}

fragment half4 fragRed(VertexOut fragments [[stage_in]] ) {
	return half4(1, 0, 0, 1);
}

fragment half4 fragUV(VertexOut fragments [[stage_in]] ) {
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	return half4(uv.x, uv.y, 0, 1);
}

fragment half4 fragVertexNormals(VertexOut fragments [[stage_in]],
								 constant Uniforms &uniforms [[buffer(1)]] )
{
	float3 n = fragments.worldNormal.xyz;
	return half4(n.x, n.y, n.z, 1);
}

fragment half4 fragEyeNormals(VertexOut fragments [[stage_in]],
							  constant Uniforms &uniforms [[buffer(1)]] )
{
	float3 n = normalize(fragments.viewNormal.xyz);
	return half4(n.x, n.y, n.z, 1);
}

fragment half4 fragEyeReflectionVector(VertexOut fragments [[stage_in]],
								 constant Uniforms &uniforms [[buffer(1)]],
								 texturecube<float> cubemapSky [[texture(3)]] )
{
	float3 n = normalize(fragments.reflectDir);
	return half4(n.x, n.y, n.z, 1);
}

fragment half4 fragPureReflection(VertexOut fragments [[stage_in]],
								  constant Uniforms &uniforms [[buffer(1)]],
								  texturecube<float> cubemapSky [[texture(3)]] )
{
	float3 n = normalize(fragments.reflectDir);
	return half4(cubemapSky.sample(linearSampler, n));
}


fragment half4 fragDiffuse(VertexOut fragments [[stage_in]],
						   texture2d<float> diffuseTex [[texture(0)]] )
{
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	float4 diffuse = diffuseTex.sample(linearSampler, uv);
	return half4(diffuse);
}

fragment half4 fragDiffuseLighting(VertexOut fragments [[stage_in]],
								   texture2d<float> diffuseTex [[texture(0)]],
								   constant Uniforms &uniforms [[buffer(1)]] )
{
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	float3 lightDir = uniforms.lightDirection.xyz;
	float normalLightDot = dot(lightDir, fragments.worldNormal.xyz);
	
	float dot_product = max(normalLightDot, 0.0);
	float4 diffuse = float4(dot_product, dot_product, dot_product, 1.0) * diffuseTex.sample(linearSampler, uv);
	return half4(diffuse);
}

fragment half4 fragDiffuseAndSpecular(VertexOut fragments [[stage_in]],
									  texture2d<float> diffuseTex [[texture(0)]],
									  texture2d<float> specularTex [[texture(1)]],
																	constant Uniforms &uniforms [[buffer(1)]] )
{
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	// renormalize because interpolated normals can get a bit off
	float3 normal = normalize(fragments.worldNormal.xyz);
	
	float3 lightDir = normalize(uniforms.lightDirection.xyz);
	float normalLightDot = dot(lightDir, fragments.worldNormal.xyz);
	
	float dot_product = max(normalLightDot, 0.0) / 1.5 + 0.33; // add some ambient light
	float4 diffuse = float4(dot_product, dot_product, dot_product, 1.0) * diffuseTex.sample(linearSampler, uv);

	float4 specularReflection = float4(0, 0, 0, 1);
	if(normalLightDot >= 0.0){ // make sure the light isn't on the wrong side
		float attenuation = 2;
		float4 specularColor =	specularTex.sample(linearSampler, uv);
		specularReflection = attenuation * specularColor.a * specularColor * pow(max(0.0, dot(reflect(-lightDir, normalize(normal)), normalize(uniforms.eyeDirection.xyz))), 10.0 );
		specularReflection.a = 1.0;
	}
	float4 color = 0.8 * diffuse + specularReflection;
	
	return half4(color);
}



fragment half4 fragDiffuseSpecularReflection(VertexOut fragments [[stage_in]],
									  texture2d<float> diffuseTex [[texture(0)]],
									  texture2d<float> specularTex [[texture(1)]],
											 texturecube<float> cubemapSky [[texture(3)]],
									  constant Uniforms &uniforms [[buffer(1)]] )
{
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	// renormalize because interpolated normals can get a bit off
	float3 normal = normalize(fragments.worldNormal.xyz);
	
	float3 lightDir = normalize(uniforms.lightDirection.xyz);
	float normalLightDot = dot(lightDir, fragments.worldNormal.xyz);
	
	float dot_product = max(normalLightDot, 0.0) / 1.5 + 0.33; // add some ambient light
	float4 diffuse = float4(dot_product, dot_product, dot_product, 1.0) * diffuseTex.sample(linearSampler, uv);
	
	float4 specularReflection = float4(0, 0, 0, 1);
	
	float4 specularColor =	specularTex.sample(linearSampler, uv);
	
	if(normalLightDot >= 0.0){ // make sure the light isn't on the wrong side
		float attenuation = 2;
		specularReflection = attenuation * specularColor.a * specularColor * pow(max(0.0, dot(reflect(-lightDir, normalize(normal)), normalize(uniforms.eyeDirection.xyz))), 10.0 );
		specularReflection.a = 1.0;
	}
	
	float3 n = normalize(fragments.reflectDir);
	float4 reflection = cubemapSky.sample(linearSampler, n);

	float reflectivity = pow(specularColor.a, 3) * 0.4; //looks about right. asphalt, tires, seat shouldn't reflect much.
	
	float4 color = 0.8 * diffuse + specularReflection + reflection * reflectivity;

//	return half4(reflectivity, reflectivity, reflectivity, 1);
	return half4(color);
}

fragment half4 fragDiffuseImageLighting(VertexOut fragments [[stage_in]],
											texture2d<float> diffuseTex [[texture(0)]],
											texture2d<float> specularTex [[texture(1)]],
											texturecube<float> cubemapSky [[texture(3)]],
											texturecube<float> cubemapSpec [[texture(4)]],
											texturecube<float> cubemapDiffuse [[texture(5)]],
											constant Uniforms &uniforms [[buffer(1)]] )
{
	float2 uv = fragments.texCoords;
	uv.y = 1 - uv.y;
	
	float3 n = normalize(fragments.reflectDir);
	// renormalize because interpolated normals can get a bit off
	float3 normal = normalize(fragments.worldNormal.xyz);
	
	float4 light = cubemapDiffuse.sample(linearSampler, n);
	float4 diffuse = light * diffuseTex.sample(linearSampler, uv);

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


struct SkyboxVertexOut {
	float4 position [[position]];
	float4 uv;
	float3 eyeDirection;
	
};

vertex SkyboxVertexOut vertexSkybox(uint vertexId [[vertex_id]],
									constant Uniforms &uniforms [[buffer(1)]],
									texturecube<float> cubemapSky [[texture(0)]]
									)
{
	const float depth = 1/400.0; // depth testing is off while you draw this I hope.
	const float4 arr[] = {
		float4(-1, -1, depth, 1),
		float4(1, -1, depth, 1),
		float4(-1, 1, depth, 1),
		float4(1, 1, depth, 1),
	};
	SkyboxVertexOut out;
	out.position = arr[vertexId];
	out.uv = arr[vertexId];
	float4 pos = float4(out.position.x, out.position.y, out.position.z, 0);
	
	float4 nearPlane = uniforms.MVP_i_Matrix * float4(pos.x, pos.y, 0, 1);
	float4 farPlane = uniforms.MVP_i_Matrix * float4(pos.x, pos.y, 1, 1);
	nearPlane /= nearPlane.w;
	farPlane /= farPlane.w;

	out.eyeDirection = (farPlane -nearPlane ).xyz;
	
	return out;
}

fragment half4 fragSkybox(SkyboxVertexOut in [[stage_in]],
						  constant Uniforms &uniforms [[buffer(1)]],
						  texturecube<float> cubemapSky [[texture(0)]]
						  ) {
	
	return half4(cubemapSky.sample(linearSampler, in.eyeDirection ));
}

struct blitVary {
	float4 position [[position]];
	float2 uv;
};

vertex blitVary vertBlit(
	uint vertexId [[vertex_id]]
){
	const float4 clip_quad[] = {
		{-1, -1, 0, 1},
		{ 1, -1, 0, 1},
		{-1,  1, 0, 1},
		{ 1,  1, 0, 1},
	};
	
	float4 pos = clip_quad[vertexId];
	
	blitVary out;
	out.position = pos;
	out.uv = 0.5*pos.xy + 0.5;
	
	out.position.y = -out.position.y;
	return out;
}

fragment half4 fragBlit(
	blitVary IN [[stage_in]],
	texture2d<half> texture [[texture(0)]]
){
	return texture.sample(linearSampler, IN.uv);
}


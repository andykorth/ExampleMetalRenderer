#pragma once

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum BufferArgumentIndex
{
    BufferArgumentIndexVertices     = 0,
    BufferArgumentIndexUniforms     = 1,
} BufferArgumentIndex;

struct Uniforms {
	matrix_float4x4 MVP_Matrix;
	matrix_float4x4 MVP_i_Matrix;
	matrix_float4x4 MV_Matrix;
	matrix_float4x4 MV_i_Matrix;
	matrix_float4x4 normal_Matrix; // http://www.lighthouse3d.com/tutorials/glsl-12-tutorial/the-normal-matrix/

	vector_float4 lightDirection;
	vector_float4 timeUniform;
	vector_float4 sinTime;
	vector_float4 cosTime;
	vector_float4 rand01;
	vector_float4 mainTextureSize;
	vector_float4 eyeDirection;
};

struct Vertex {
	vector_float4 position;
	vector_float4 color;
};

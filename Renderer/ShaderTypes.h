
#ifndef AAPLShaderTypes_h
#define AAPLShaderTypes_h

#include <simd/simd.h>

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum BufferArgumentIndex
{
    BufferArgumentIndexVertices     = 0,
    BufferArgumentIndexUniforms     = 1,
} BufferArgumentIndex;


#endif /* AAPLShaderTypes_h */

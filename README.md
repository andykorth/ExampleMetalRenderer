# ExampleMetalRenderer
An image-based renderer made using Metal. I made this to learn Metal and Swift at the same time, while also learning how image-based lighting works.

This work was presented at a Twin Cities, MN Apple developer group on July 2018.

* Written in Swift
* MetalKit for rendering
* ModelIO for importing models
* simd.h for math that lines up with metal-provided types
* Keep the example small:

Special Thanks:
Marmoset Skyshop for the artwork
Scott Lembcke for general advice and help

```
kortham@Turing ~/projects/MetalEngine/Renderer$ wc -l *
      81 MathUtils.swift
       5 MetalEngine-macOS-Bridging-Header.h
     422 MetalRenderer.swift
      99 ObjMesh.swift
     349 Shaders.metal
      32 ShaderTypes.h
     988 total
```


#version 460 core

// Sparse-strip coverage shader (Track B). One canvas.drawVertices call
// draws every strip quad of a flush batch; this shader turns each fragment
// into a coverage scalar and BlendMode.modulate multiplies it with the
// quad's per-vertex color (M0 verified byte-accuracy of the whole chain on
// both backends, and that the shader is evaluated in TEXCOORD space).
//
// Texcoord contract (see strip_batch.dart):
//   u: global alpha-texel index - interpolates alphaOffset .. alphaOffset+w
//      left to right across a mixed strip. Fragment centers land at
//      index + 0.5, so floor(u) is the exact column texel index. The atlas
//      is row-major by that index: texel t sits at (mod(t, atlasW),
//      floor(t / atlasW)).
//   v: local strip row - [0,4) for mixed strips (floor(v) = scanline 0..3
//      selecting the R/G/B/A coverage channel via the step-mask dot, the
//      SkSL-safe replacement for bit ops), [4,8) for solid strips
//      (coverage 1, sampled texel ignored; solid quads carry u in [0,w) so
//      the dead sample still lands inside the atlas).
//
// Keep inside the SkSL subset: no loops, no bit ops, no texelFetch
// (texelFetch aborts impellerc's GLES2 stage).

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uAtlasSize; // alpha atlas size in texels
// Chunk texcoord origin: u interpolates CHUNK-RELATIVE texel indices so a
// draw's texcoord bounds stay small enough for Impeller's shader-snapshot
// texture (it evaluates this shader over the texcoord bounds and samples
// the result); uBase adds the chunk's global offset back.
uniform float uBase;
uniform sampler2D uAtlas;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy; // texcoord space per the M0 probe
  float solid = step(4.0, uv.y);
  float t = floor(uv.x) + uBase;
  float ax = mod(t, uAtlasSize.x);
  float ay = floor(t / uAtlasSize.x);
  vec4 texel = texture(uAtlas, (vec2(ax, ay) + 0.5) / uAtlasSize);
  float row = floor(uv.y) - 4.0 * solid; // scanline 0..3 within the strip
  vec4 mask = vec4(step(abs(row - 0.0), 0.5), step(abs(row - 1.0), 0.5),
                   step(abs(row - 2.0), 0.5), step(abs(row - 3.0), 0.5));
  float cov = mix(dot(texel, mask), 1.0, solid);
  // Premultiplied white x coverage; vertex colors supply the paint color
  // through BlendMode.modulate.
  fragColor = vec4(cov);
}

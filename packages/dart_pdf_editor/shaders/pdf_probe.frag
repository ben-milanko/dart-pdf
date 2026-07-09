#version 460 core

// M0 feasibility probe for strip rendering (see doc/dev-log).
// Answers, per backend:
//   mode 0 - which coordinate space a runtime effect is evaluated in when
//            drawn through canvas.drawVertices (positions vs texcoords).
//   mode 1 - whether nearest-sampled texture() at half-texel centers reads
//            exact texels from an rgba8888 data texture.
//   mode 2 - RGBA channel select via a step-mask dot product (the SkSL-safe
//            replacement for bit ops the strip shader will use).
// Keep this inside the SkSL subset: no dynamic loop bounds, no bit ops,
// no texelFetch (texelFetch also aborts impellerc's GLES2 stage).

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uTexSize; // data texture size in texels
uniform vec2 uMode;    // x: probe mode 0/1/2, y: channel row for mode 2
uniform sampler2D uData;

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  if (uMode.x < 0.5) {
    // Echo the evaluation-space coordinate into R/G.
    fragColor = vec4(p.x / 255.0, p.y / 255.0, 0.0, 1.0);
  } else if (uMode.x < 1.5) {
    // Exact-texel read addressed by the evaluation-space coordinate.
    vec2 ij = floor(p);
    fragColor = texture(uData, (ij + 0.5) / uTexSize);
  } else {
    // Channel select: row 0..3 picks R/G/B/A as a coverage scalar.
    vec2 ij = floor(p);
    vec4 texel = texture(uData, (ij + 0.5) / uTexSize);
    float row = uMode.y;
    vec4 mask = vec4(step(abs(row - 0.0), 0.5), step(abs(row - 1.0), 0.5),
                     step(abs(row - 2.0), 0.5), step(abs(row - 3.0), 0.5));
    float cov = dot(texel, mask);
    fragColor = vec4(cov, cov, cov, 1.0);
  }
}

// Sparse-strip coverage: premultiplied per-vertex color scaled by a CPU
// rasterized coverage byte fetched from the alpha atlas.
//
// The atlas is an RGBA8 texture where each texel packs one 1x4 px coverage
// column (R = strip row 0 .. A = row 3), the vello_hybrid layout. The
// interpolated global texel index is floored and converted to atlas x/y
// with the atlas size uniform; nearest sampling makes the read exact on
// every backend (texelFetch breaks impellerc's GLES2 stage). The channel
// is selected with a step-mask dot - SkSL-portable, no bitwise ops, no
// dynamic indexing.
//
// Solid strips arrive with y_flags in [4, 8): coverage is 1 and the fetch
// result is ignored (the sample still executes - uniform control flow).
uniform FragInfo {
  vec2 atlas_size; // alpha texture size in texels
}
frag_info;

uniform sampler2D alpha_tex;

in float v_texel;
in float v_yflags;
in vec4 v_color;

out vec4 frag_color;

void main() {
  float solid = step(4.0, v_yflags);
  float row = floor(v_yflags - 4.0 * solid); // RGBA channel 0..3
  float texel = floor(v_texel);
  float ty = floor(texel / frag_info.atlas_size.x);
  float tx = texel - ty * frag_info.atlas_size.x;
  vec2 uv = (vec2(tx, ty) + 0.5) / frag_info.atlas_size;
  vec4 t = texture(alpha_tex, uv);
  // One-hot channel mask from step() differences: row 0 -> R, 3 -> A.
  vec4 lo = step(vec4(-0.5, 0.5, 1.5, 2.5), vec4(row));
  vec4 hi = step(vec4(0.5, 1.5, 2.5, 3.5), vec4(row));
  float coverage = mix(dot(t, lo - hi), 1.0, solid);
  frag_color = v_color * coverage;
}

// Samples a premultiplied RGBA texture.
//
// Image mode (stencil_mode = 0): texture color scaled by the tint's alpha
// (the PDF fill alpha). Stencil-mask mode (stencil_mode = 1): the tint color
// (a premultiplied fill color) painted through the texture's alpha channel,
// per §8.9.6.2 /ImageMask semantics.
uniform FragInfo {
  vec4 tint;
  float stencil_mode;
}
frag_info;

uniform sampler2D tex;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 t = texture(tex, v_uv);
  vec4 image_color = t * frag_info.tint.a;
  vec4 mask_color = frag_info.tint * t.a;
  frag_color = mix(image_color, mask_color, frag_info.stencil_mode);
}

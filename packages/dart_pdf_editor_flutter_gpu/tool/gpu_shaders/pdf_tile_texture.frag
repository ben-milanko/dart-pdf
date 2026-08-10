uniform FragInfo {
  vec4 tint;
  float stencil_mode;
}
frag_info;

uniform sampler2D tex;
in vec2 v_uv;
out vec4 frag_color;

void main() {
  vec4 sample_color = texture(tex, v_uv);
  vec4 image_color = sample_color * frag_info.tint.a;
  vec4 mask_color = frag_info.tint * sample_color.a;
  frag_color = mix(image_color, mask_color, frag_info.stencil_mode);
}

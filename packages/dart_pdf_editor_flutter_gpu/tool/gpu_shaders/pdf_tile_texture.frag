uniform sampler2D tex;
in vec2 v_uv;
in vec4 v_tint;
in float v_stencil_mode;
out vec4 frag_color;

void main() {
  vec4 sample_color = texture(tex, v_uv);
  vec4 image_color = sample_color * v_tint.a;
  vec4 mask_color = v_tint * sample_color.a;
  frag_color = mix(image_color, mask_color, v_stencil_mode);
}

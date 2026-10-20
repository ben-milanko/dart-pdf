uniform MaskInfo {
  mat4 page_to_mask;
  vec4 content_tint;
  vec4 mask_tint;
  vec4 modes;
  vec4 transfer;
  vec4 mask_clip;
}
mask_info;

uniform sampler2D content_tex;
uniform sampler2D mask_tex;
in vec2 v_uv;
in vec2 v_page;
out vec4 frag_color;

void main() {
  vec4 content_sample = texture(content_tex, v_uv);
  vec4 normal_content = content_sample * mask_info.content_tint.a;
  vec4 stencil_content = mask_info.content_tint * content_sample.a;
  vec4 content_color = mix(
    normal_content,
    stencil_content,
    mask_info.modes.x
  );

  vec2 mask_uv_pdf =
    (mask_info.page_to_mask * vec4(v_page, 0.0, 1.0)).xy;
  bool in_uv = mask_uv_pdf.x >= 0.0 && mask_uv_pdf.x <= 1.0 &&
               mask_uv_pdf.y >= 0.0 && mask_uv_pdf.y <= 1.0;
  bool in_clip = v_page.x >= mask_info.mask_clip.x &&
                 v_page.y >= mask_info.mask_clip.y &&
                 v_page.x <= mask_info.mask_clip.z &&
                 v_page.y <= mask_info.mask_clip.w;
  float mask_value = mask_info.modes.w;
  if (in_uv && in_clip) {
    vec4 mask_sample = texture(mask_tex, vec2(mask_uv_pdf.x, 1.0-mask_uv_pdf.y));
    vec4 normal_mask = mask_sample * mask_info.mask_tint.a;
    vec4 stencil_mask = mask_info.mask_tint * mask_sample.a;
    vec4 mask_color = mix(normal_mask, stencil_mask, mask_info.modes.y);
    float alpha_value = mask_color.a;
    float luminosity_value = dot(mask_color.rgb, vec3(0.2126, 0.7152, 0.0722));
    mask_value = mix(alpha_value, luminosity_value, mask_info.modes.z);
  }
  mask_value = clamp(
    mask_value * mask_info.transfer.x + mask_info.transfer.y,
    0.0,
    1.0
  );
  frag_color = content_color * mask_value;
}

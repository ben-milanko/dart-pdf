uniform VertInfo {
  mat4 mvp;
}
vert_info;

in vec2 position;
in vec2 uv;
in vec4 tint;
in float stencil_mode;
out vec2 v_uv;
out vec4 v_tint;
out float v_stencil_mode;

void main() {
  v_uv = uv;
  v_tint = tint;
  v_stencil_mode = stencil_mode;
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}

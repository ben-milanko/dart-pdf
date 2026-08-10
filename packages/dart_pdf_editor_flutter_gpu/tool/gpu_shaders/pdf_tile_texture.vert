uniform VertInfo {
  mat4 mvp;
}
vert_info;

in vec2 position;
in vec2 uv;
out vec2 v_uv;

void main() {
  v_uv = uv;
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}

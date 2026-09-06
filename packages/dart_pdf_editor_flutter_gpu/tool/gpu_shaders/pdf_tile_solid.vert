uniform VertInfo {
  mat4 mvp;
}
vert_info;

in vec2 position;
in vec4 color;
out vec4 v_color;

void main() {
  v_color = color;
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}

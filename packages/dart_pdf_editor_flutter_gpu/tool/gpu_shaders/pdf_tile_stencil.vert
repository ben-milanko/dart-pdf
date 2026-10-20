uniform VertInfo {
  mat4 mvp;
}
vert_info;

in vec2 position;

void main() {
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}

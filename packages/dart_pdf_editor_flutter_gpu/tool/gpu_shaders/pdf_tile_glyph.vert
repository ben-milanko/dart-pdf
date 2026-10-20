uniform VertInfo {
  mat4 mvp;
}
vert_info;

in vec2 position;
in vec2 em_position;
in float slot;
in vec4 color;
out vec2 v_em;
out float v_slot;
out vec4 v_color;

void main() {
  v_em = em_position;
  v_slot = slot;
  v_color = color;
  gl_Position = vert_info.mvp * vec4(position, 0.0, 1.0);
}

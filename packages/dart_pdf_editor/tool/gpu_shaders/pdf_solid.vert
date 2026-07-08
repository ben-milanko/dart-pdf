// Solid geometry (batched fills/strokes/meshes/covers): NDC positions with
// premultiplied per-vertex color.
in vec2 position;
in vec4 color;

out vec4 v_color;

void main() {
  v_color = color;
  gl_Position = vec4(position, 0.0, 1.0);
}

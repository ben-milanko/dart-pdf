// Gradient fills: NDC positions plus the same vertex mapped into gradient
// space on the CPU (affine, so interpolation across the triangle is exact).
in vec2 position;
in vec2 grad_coord;

out vec2 v_coord;

void main() {
  v_coord = grad_coord;
  gl_Position = vec4(position, 0.0, 1.0);
}

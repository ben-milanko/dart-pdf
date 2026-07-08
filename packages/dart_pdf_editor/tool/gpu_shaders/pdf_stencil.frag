// Stencil-only pass: color writes are disabled via a zero/one blend
// equation, so the output value is irrelevant.
out vec4 frag_color;

void main() {
  frag_color = vec4(0.0);
}

// Axial (PDF type 2) and two-circle radial (type 3) gradients, evaluated in
// gradient space with the color ramp in a 256x1 premultiplied LUT texture.
//
// packed uniforms:
//   points  = x0, y0, x1, y1 (axial endpoints / radial circle centers)
//   params  = r0, r1, is_radial, alpha
//   extend  = extend_start, extend_end, unused, unused
uniform GradInfo {
  vec4 points;
  vec4 params;
  vec4 extend;
}
grad_info;

uniform sampler2D lut;

in vec2 v_coord;

out vec4 frag_color;

void main() {
  vec2 p0 = grad_info.points.xy;
  vec2 p1 = grad_info.points.zw;
  float t = 0.0;
  float valid = 1.0;
  if (grad_info.params.z > 0.5) {
    // Two-circle radial: find the largest s where the interpolated circle
    // c(s) = mix(p0, p1, s), r(s) = mix(r0, r1, s) passes through the pixel.
    float r0 = grad_info.params.x;
    float dr = grad_info.params.y - r0;
    vec2 d = p1 - p0;
    vec2 f = v_coord - p0;
    float a = dot(d, d) - dr * dr;
    float b = -2.0 * (dot(f, d) + r0 * dr);
    float c = dot(f, f) - r0 * r0;
    float s = 0.0;
    if (abs(a) < 1e-9) {
      if (abs(b) < 1e-9) {
        valid = 0.0;
      } else {
        s = -c / b;
      }
    } else {
      float disc = b * b - 4.0 * a * c;
      if (disc < 0.0) {
        valid = 0.0;
      } else {
        float sq = sqrt(disc);
        float s1 = (-b + sq) / (2.0 * a);
        float s2 = (-b - sq) / (2.0 * a);
        s = max(s1, s2);
        if (r0 + s * dr < 0.0) {
          s = min(s1, s2);
        }
        if (r0 + s * dr < 0.0) {
          valid = 0.0;
        }
      }
    }
    t = s;
  } else {
    vec2 d = p1 - p0;
    t = dot(v_coord - p0, d) / max(dot(d, d), 1e-12);
  }
  // /Extend false paints nothing past that end of the ramp.
  if (t < 0.0 && grad_info.extend.x < 0.5) {
    valid = 0.0;
  }
  if (t > 1.0 && grad_info.extend.y < 0.5) {
    valid = 0.0;
  }
  vec4 color = texture(lut, vec2(clamp(t, 0.0, 1.0), 0.5));
  frag_color = color * grad_info.params.w * valid;
}

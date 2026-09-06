uniform GlyphInfo {
  vec2 atlas_size;
}
glyph_info;

uniform sampler2D glyph_atlas;
in vec2 v_em;
in float v_slot;
in vec4 v_color;
out vec4 frag_color;

vec2 read_pair(float t) {
  float x = mod(t, glyph_info.atlas_size.x);
  float y = floor(t / glyph_info.atlas_size.x);
  vec4 texel = texture(
    glyph_atlas,
    (vec2(x, y) + 0.5) / glyph_info.atlas_size
  );
  return floor(vec2(
    dot(texel.rg, vec2(255.0, 65280.0)),
    dot(texel.ba, vec2(255.0, 65280.0))
  ) + 0.5);
}

vec2 read_em(float t) {
  return (read_pair(t) - 32768.0) / 8192.0;
}

void main() {
  float slot = floor(v_slot + 0.5);
  vec2 base_pair = read_pair(slot * 4.0);
  float base = base_pair.x + base_pair.y * 65536.0;
  vec2 y_band = (read_pair(slot * 4.0 + 1.0) - 32768.0) / 8192.0;
  vec2 x_band = (read_pair(slot * 4.0 + 2.0) - 32768.0) / 8192.0;
  float band_count = read_pair(base).x;

  // v_em is affine across each glyph quad. Inverting its screen-space
  // derivatives recovers device pixels per em for the current tile LoD, so
  // one retained curve atlas remains sharp at every zoom and rotation.
  vec2 em_dx = dFdx(v_em);
  vec2 em_dy = dFdy(v_em);
  float determinant = em_dx.x * em_dy.y - em_dx.y * em_dy.x;
  float inverse_det = 1.0 / max(abs(determinant), 1e-12);
  float px_per_em_x = length(vec2(em_dy.y, -em_dx.y)) * inverse_det;
  float px_per_em_y = length(vec2(-em_dy.x, em_dx.x)) * inverse_det;

  float h_band = clamp(
    floor((v_em.y - y_band.x) / y_band.y),
    0.0,
    band_count - 1.0
  );
  vec2 h_table = read_pair(base + 1.0 + h_band);
  float coverage_h = 0.0;
  for (int i = 0; i < 16; i++) {
    if (float(i) >= h_table.y) break;
    float curve_t = base + read_pair(base + h_table.x + float(i)).x;
    vec2 p0 = read_em(curve_t);
    vec2 pc = read_em(curve_t + 1.0);
    vec2 p1 = read_em(curve_t + 2.0);
    float e0 = p0.y - v_em.y;
    float ec = pc.y - v_em.y;
    float e1 = p1.y - v_em.y;
    bool s0 = e0 > 0.0;
    bool s1 = e1 > 0.0;
    float a = e0 - 2.0 * ec + e1;
    float b = 2.0 * (ec - e0);
    float discriminant = b * b - 4.0 * a * e0;
    float root = sqrt(max(discriminant, 0.0));
    float q = -0.5 * (b + (b >= 0.0 ? root : -root));
    float ta = abs(a) > 1e-12 ? q / a : 2.0;
    float tb = abs(q) > 1e-12 ? e0 / q : 2.0;
    if (s0 != s1) {
      float t = (tb >= 0.0 && tb <= 1.0) ? tb : ta;
      t = clamp(t, 0.0, 1.0);
      float mt = 1.0 - t;
      float x = mt * mt * p0.x + 2.0 * mt * t * pc.x + t * t * p1.x;
      float weight = clamp(
        (x - v_em.x) * px_per_em_x + 0.5,
        0.0,
        1.0
      );
      coverage_h += s1 ? weight : -weight;
    } else if (discriminant > 0.0 &&
        ta > 0.0 && ta < 1.0 && tb > 0.0 && tb < 1.0) {
      float t0 = min(ta, tb);
      float t1 = max(ta, tb);
      float mt0 = 1.0 - t0;
      float mt1 = 1.0 - t1;
      float x0 = mt0 * mt0 * p0.x +
        2.0 * mt0 * t0 * pc.x + t0 * t0 * p1.x;
      float x1 = mt1 * mt1 * p0.x +
        2.0 * mt1 * t1 * pc.x + t1 * t1 * p1.x;
      float w0 = clamp((x0 - v_em.x) * px_per_em_x + 0.5, 0.0, 1.0);
      float w1 = clamp((x1 - v_em.x) * px_per_em_x + 0.5, 0.0, 1.0);
      coverage_h += s0 ? (w1 - w0) : (w0 - w1);
    }
  }

  float v_band = clamp(
    floor((v_em.x - x_band.x) / x_band.y),
    0.0,
    band_count - 1.0
  );
  vec2 v_table = read_pair(base + 1.0 + band_count + v_band);
  float coverage_v = 0.0;
  for (int i = 0; i < 16; i++) {
    if (float(i) >= v_table.y) break;
    float curve_t = base + read_pair(base + v_table.x + float(i)).x;
    vec2 p0 = read_em(curve_t);
    vec2 pc = read_em(curve_t + 1.0);
    vec2 p1 = read_em(curve_t + 2.0);
    float e0 = p0.x - v_em.x;
    float ec = pc.x - v_em.x;
    float e1 = p1.x - v_em.x;
    bool s0 = e0 > 0.0;
    bool s1 = e1 > 0.0;
    float a = e0 - 2.0 * ec + e1;
    float b = 2.0 * (ec - e0);
    float discriminant = b * b - 4.0 * a * e0;
    float root = sqrt(max(discriminant, 0.0));
    float q = -0.5 * (b + (b >= 0.0 ? root : -root));
    float ta = abs(a) > 1e-12 ? q / a : 2.0;
    float tb = abs(q) > 1e-12 ? e0 / q : 2.0;
    if (s0 != s1) {
      float t = (tb >= 0.0 && tb <= 1.0) ? tb : ta;
      t = clamp(t, 0.0, 1.0);
      float mt = 1.0 - t;
      float y = mt * mt * p0.y + 2.0 * mt * t * pc.y + t * t * p1.y;
      float weight = clamp(
        (y - v_em.y) * px_per_em_y + 0.5,
        0.0,
        1.0
      );
      coverage_v += s1 ? -weight : weight;
    } else if (discriminant > 0.0 &&
        ta > 0.0 && ta < 1.0 && tb > 0.0 && tb < 1.0) {
      float t0 = min(ta, tb);
      float t1 = max(ta, tb);
      float mt0 = 1.0 - t0;
      float mt1 = 1.0 - t1;
      float y0 = mt0 * mt0 * p0.y +
        2.0 * mt0 * t0 * pc.y + t0 * t0 * p1.y;
      float y1 = mt1 * mt1 * p0.y +
        2.0 * mt1 * t1 * pc.y + t1 * t1 * p1.y;
      float w0 = clamp((y0 - v_em.y) * px_per_em_y + 0.5, 0.0, 1.0);
      float w1 = clamp((y1 - v_em.y) * px_per_em_y + 0.5, 0.0, 1.0);
      coverage_v += s0 ? (w0 - w1) : (w1 - w0);
    }
  }

  float coverage = (
    min(abs(coverage_h), 1.0) + min(abs(coverage_v), 1.0)
  ) * 0.5;
  frag_color = v_color * coverage;
}

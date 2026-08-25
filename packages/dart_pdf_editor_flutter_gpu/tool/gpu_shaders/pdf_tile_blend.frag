uniform BlendInfo {
  vec4 modes;
}
blend_info;

uniform sampler2D backdrop_tex;
uniform sampler2D source_tex;
in vec2 v_uv;
out vec4 frag_color;

float soft_light(float cb, float cs) {
  if (cs <= 0.5) {
    return cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb);
  }
  float d = cb <= 0.25
    ? ((16.0 * cb - 12.0) * cb + 4.0) * cb
    : sqrt(cb);
  return cb + (2.0 * cs - 1.0) * (d - cb);
}

float luminosity(vec3 color) {
  return dot(color, vec3(0.3, 0.59, 0.11));
}

float saturation(vec3 color) {
  return max(max(color.r, color.g), color.b) -
    min(min(color.r, color.g), color.b);
}

vec3 clip_color(vec3 color) {
  float lum = luminosity(color);
  float low = min(min(color.r, color.g), color.b);
  float high = max(max(color.r, color.g), color.b);
  if (low < 0.0) {
    color = vec3(lum) + (color - vec3(lum)) * lum / (lum - low);
  }
  if (high > 1.0) {
    color = vec3(lum) +
      (color - vec3(lum)) * (1.0 - lum) / (high - lum);
  }
  return color;
}

vec3 set_luminosity(vec3 color, float lum) {
  return clip_color(color + vec3(lum - luminosity(color)));
}

vec3 set_saturation(vec3 color, float sat) {
  float low = min(min(color.r, color.g), color.b);
  float high = max(max(color.r, color.g), color.b);
  if (high <= low) {
    return vec3(0.0);
  }
  return (color - vec3(low)) * sat / (high - low);
}

vec3 separable_blend(vec3 cb, vec3 cs, int mode) {
  if (mode == 3) {
    return mix(
      2.0 * cb * cs,
      1.0 - 2.0 * (1.0 - cb) * (1.0 - cs),
      step(vec3(0.5), cb)
    );
  }
  if (mode == 4) return min(cb, cs);
  if (mode == 5) return max(cb, cs);
  if (mode == 6) {
    vec3 value = min(vec3(1.0), cb / max(vec3(1e-7), 1.0 - cs));
    return mix(value, vec3(1.0), step(vec3(1.0), cs));
  }
  if (mode == 7) {
    vec3 value = 1.0 - min(
      vec3(1.0),
      (1.0 - cb) / max(vec3(1e-7), cs)
    );
    return value * step(vec3(1e-7), cs);
  }
  if (mode == 8) {
    return mix(
      2.0 * cb * cs,
      1.0 - 2.0 * (1.0 - cb) * (1.0 - cs),
      step(vec3(0.5), cs)
    );
  }
  if (mode == 9) {
    return vec3(
      soft_light(cb.r, cs.r),
      soft_light(cb.g, cs.g),
      soft_light(cb.b, cs.b)
    );
  }
  if (mode == 10) return abs(cb - cs);
  return cb + cs - 2.0 * cb * cs;
}

vec3 blend(vec3 cb, vec3 cs, int mode) {
  if (mode <= 11) return separable_blend(cb, cs, mode);
  if (mode == 12) {
    return set_luminosity(
      set_saturation(cs, saturation(cb)),
      luminosity(cb)
    );
  }
  if (mode == 13) {
    return set_luminosity(
      set_saturation(cb, saturation(cs)),
      luminosity(cb)
    );
  }
  if (mode == 14) return set_luminosity(cs, luminosity(cb));
  return set_luminosity(cb, luminosity(cs));
}

void main() {
  vec4 backdrop = texture(backdrop_tex, v_uv);
  vec4 source = texture(source_tex, v_uv);
  float ab = backdrop.a;
  float as = source.a;
  vec3 cb = ab > 0.0 ? backdrop.rgb / ab : vec3(0.0);
  vec3 cs = as > 0.0 ? source.rgb / as : vec3(0.0);
  vec3 blended = blend(cb, cs, int(floor(blend_info.modes.x + 0.5)));
  frag_color = vec4(
    (1.0 - as) * backdrop.rgb +
      (1.0 - ab) * source.rgb +
      as * ab * blended,
    as + ab - as * ab
  );
}

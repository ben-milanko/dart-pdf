uniform BlendInfo {
  vec4 mode;
}
blend_info;

uniform sampler2D destination_tex;
uniform sampler2D source_tex;
in vec2 v_uv;
out vec4 frag_color;

float luminosity(vec3 color) {
  return dot(color, vec3(0.3, 0.59, 0.11));
}

vec3 clip_color(vec3 color) {
  float lum = luminosity(color);
  float minimum = min(min(color.r, color.g), color.b);
  float maximum = max(max(color.r, color.g), color.b);
  if (minimum < 0.0) {
    color = lum + (color - lum) * lum / max(lum - minimum, 1e-6);
  }
  if (maximum > 1.0) {
    color = lum +
      (color - lum) * (1.0 - lum) / max(maximum - lum, 1e-6);
  }
  return color;
}

vec3 set_luminosity(vec3 color, float target) {
  return clip_color(color + target - luminosity(color));
}

float saturation(vec3 color) {
  return max(max(color.r, color.g), color.b) -
    min(min(color.r, color.g), color.b);
}

vec3 set_saturation(vec3 color, float target) {
  float minimum = min(min(color.r, color.g), color.b);
  float maximum = max(max(color.r, color.g), color.b);
  return minimum < maximum
    ? (color - minimum) * target / (maximum - minimum)
    : vec3(0.0);
}

vec3 screen(vec3 backdrop, vec3 source) {
  return backdrop + source - backdrop * source;
}

vec3 hard_light(vec3 backdrop, vec3 source) {
  return mix(
    2.0 * source * backdrop,
    screen(backdrop, 2.0 * source - 1.0),
    step(vec3(0.5), source)
  );
}

vec3 color_dodge(vec3 backdrop, vec3 source) {
  vec3 result = min(vec3(1.0), backdrop / max(vec3(1e-6), 1.0 - source));
  result = mix(result, vec3(0.0), lessThan(backdrop, vec3(1e-6)));
  return mix(result, vec3(1.0), lessThan(1.0 - source, vec3(1e-6)));
}

vec3 color_burn(vec3 backdrop, vec3 source) {
  vec3 result = 1.0 -
    min(vec3(1.0), (1.0 - backdrop) / max(source, vec3(1e-6)));
  result = mix(result, vec3(1.0), lessThan(1.0 - backdrop, vec3(1e-6)));
  return mix(result, vec3(0.0), lessThan(source, vec3(1e-6)));
}

vec3 soft_light(vec3 backdrop, vec3 source) {
  vec3 curve = mix(
    ((16.0 * backdrop - 12.0) * backdrop + 4.0) * backdrop,
    sqrt(backdrop),
    step(vec3(0.25), backdrop)
  );
  return mix(
    backdrop - (1.0 - 2.0 * source) * backdrop * (1.0 - backdrop),
    backdrop + (2.0 * source - 1.0) * (curve - backdrop),
    step(vec3(0.5), source)
  );
}

vec3 blend(vec3 backdrop, vec3 source, int mode) {
  if (mode == 1) return backdrop * source;
  if (mode == 2) return screen(backdrop, source);
  if (mode == 3) return hard_light(source, backdrop);
  if (mode == 4) return min(backdrop, source);
  if (mode == 5) return max(backdrop, source);
  if (mode == 6) return color_dodge(backdrop, source);
  if (mode == 7) return color_burn(backdrop, source);
  if (mode == 8) return hard_light(backdrop, source);
  if (mode == 9) return soft_light(backdrop, source);
  if (mode == 10) return abs(backdrop - source);
  if (mode == 11) return backdrop + source - 2.0 * backdrop * source;
  if (mode == 12) {
    return set_luminosity(
      set_saturation(source, saturation(backdrop)),
      luminosity(backdrop)
    );
  }
  if (mode == 13) {
    return set_luminosity(
      set_saturation(backdrop, saturation(source)),
      luminosity(backdrop)
    );
  }
  if (mode == 14) return set_luminosity(source, luminosity(backdrop));
  if (mode == 15) return set_luminosity(backdrop, luminosity(source));
  return source;
}

void main() {
  vec4 destination = texture(destination_tex, v_uv);
  if (blend_info.mode.x < 0.0) {
    frag_color = destination;
    return;
  }

  vec4 source_sample = texture(source_tex, v_uv);
  float destination_alpha = clamp(destination.a, 0.0, 1.0);
  float source_alpha = clamp(source_sample.a, 0.0, 1.0);
  vec3 backdrop = destination_alpha > 1e-6
    ? destination.rgb / destination_alpha
    : vec3(0.0);
  vec3 source = source_alpha > 1e-6
    ? source_sample.rgb / source_alpha
    : vec3(0.0);
  vec3 blended = blend(
    clamp(backdrop, 0.0, 1.0),
    clamp(source, 0.0, 1.0),
    int(blend_info.mode.x + 0.5)
  );

  float overlap_alpha = source_alpha * destination_alpha;
  vec4 blended_source =
    vec4(blended * overlap_alpha, overlap_alpha) +
    source_sample * (1.0 - destination_alpha);
  frag_color = blended_source + destination * (1.0 - blended_source.a);
}

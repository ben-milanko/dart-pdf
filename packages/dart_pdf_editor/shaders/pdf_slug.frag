#version 460 core

// Slug-style glyph shader (B3): evaluates glyph coverage directly from
// quadratic outlines packed in an rgba8888 curve atlas
// (pdf_graphics/raster curve_quads.dart - see its header for the stream
// layout and the AA formula; the Dart glyphCoverageAA is the reference
// this shader mirrors step for step).
//
// Per-glyph data arrives through the two texcoord floats alone (vertex
// colors are not readable in a runtime effect - they only modulate the
// output): glyphs occupy virtual slot cells stacked along v with constant
// stride uCellH, in DEVICE-PIXEL texcoord units (slug_batch.dart explains
// why - Impeller evaluates this effect on an integer texcoord-unit grid):
//   u = 2 + (emX - minX) * S       S = record-time device px per em
//   v = slot * uCellH + 2 + (emY - minY) * S
// so slot = floor(v / uCellH) and the em position inverts through the
// slot's directory entry. A 4-texel directory entry per slot at the atlas
// start supplies the glyph's stream base, band geometry, and S:
//   dir 0: (baseLo, baseHi)   raw u16 pair, base = lo + hi * 65536
//   dir 1: (minY, bandHeight) fixed-point em
//   dir 2: (minX, bandWidth)  fixed-point em
//   dir 3: (sx, sy)           px/em * 16, raw u16
//
// SkSL subset: constant-bound loops (MAX_CURVES_PER_BAND = 16) with early
// break, no bit ops (16-bit LE pairs decode via dot products on the
// 0..255-scaled channels), no texelFetch (half-texel-centered texture()
// reads, M0-verified byte-exact).

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uAtlasSize; // curve atlas size in texels
uniform vec2 uDebug;     // x > 0.5: dump diagnostics (y = mode parameter)
uniform float uCellH;    // slot cell stride along v, texcoord units
uniform sampler2D uAtlas;

out vec4 fragColor;

// Reads texel [t] as two 16-bit little-endian unsigned values. Every
// encoded value is an integer u16, but the sampler normalizes bytes to
// [0,1] and the *255 rescale double-rounds: 7/255*255 can come back as
// 7.0000003, which breaks exact comparisons (a loop `i >= count` break
// that never fires walks past the band list into garbage refs - the bug
// that cost the first B3 session). floor(+0.5) restores exact integers.
vec2 readPair(float t) {
  float ax = mod(t, uAtlasSize.x);
  float ay = floor(t / uAtlasSize.x);
  vec4 texel = texture(uAtlas, (vec2(ax, ay) + 0.5) / uAtlasSize);
  return floor(vec2(dot(texel.rg, vec2(255.0, 65280.0)),
                    dot(texel.ba, vec2(255.0, 65280.0))) + 0.5);
}

// Fixed-point pair -> em coordinates.
vec2 readEm(float t) {
  return (readPair(t) - 32768.0) / 8192.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy; // texcoord space (M0)
  if (uDebug.x > 3.5) {
    // raw varying dump: u, v/8, fract(v)
    fragColor = vec4(clamp(uv.x, 0.0, 1.0), clamp(uv.y / 8.0, 0.0, 1.0),
        fract(uv.y), 1.0);
    return;
  }
  float slot = floor(uv.y / uCellH);

  vec2 dir0 = readPair(slot * 4.0);
  float base = dir0.x + dir0.y * 65536.0;
  vec2 dir1 = (readPair(slot * 4.0 + 1.0) - 32768.0) / 8192.0; // minY, bandH
  vec2 dir2 = (readPair(slot * 4.0 + 2.0) - 32768.0) / 8192.0; // minX, bandW
  vec2 dir3 = readPair(slot * 4.0 + 3.0) / 16.0;               // sx, sy

  // invert the device-pixel texcoord mapping back to em space
  float emX = dir2.x + (uv.x - 2.0) / dir3.x;
  float emY = dir1.x + (uv.y - slot * uCellH - 2.0) / dir3.y;

  float bandCount = readPair(base).x;

  // Crossing counts/signs come from strict endpoint comparisons - never
  // root-in-range tests - so joints (shared, fixed-point-identical
  // endpoints) count exactly once. Mirrors _rayCrossings in
  // curve_quads.dart.

  // horizontal ray (+x): crossings of Y(t) = emY weighted by px distance
  float hb = clamp(floor((emY - dir1.x) / dir1.y), 0.0, bandCount - 1.0);
  vec2 hTable = readPair(base + 1.0 + hb); // list offset (relative), count
  float covH = 0.0;
  float dbgD = 0.0;
  float dbgE0 = 0.0;
  float dbgE1 = 0.0;
  for (int i = 0; i < 16; i++) {
    if (float(i) >= hTable.y) break;
    float curveT = base + readPair(base + hTable.x + float(i)).x;
    vec2 p0 = readEm(curveT);
    vec2 pc = readEm(curveT + 1.0);
    vec2 p1 = readEm(curveT + 2.0);
    float e0 = p0.y - emY;
    float e1 = p1.y - emY;
    bool s0 = e0 > 0.0;
    bool s1 = e1 > 0.0;
    float a = e0 - 2.0 * (pc.y - emY) + e1;
    float b = 2.0 * ((pc.y - emY) - e0);
    // stable roots (see curve_quads.dart _rayCrossings): q never cancels,
    // small root = e0/q, large root = q/a
    float sq = sqrt(max(b * b - 4.0 * a * e0, 0.0));
    float qq = -0.5 * (b + (b >= 0.0 ? sq : -sq));
    float tA = abs(a) > 1e-12 ? qq / a : 2.0;
    float tB = abs(qq) > 1e-12 ? e0 / qq : 2.0;
    float d = 0.0;
    if (s0 != s1) {
      float t = (tB >= 0.0 && tB <= 1.0) ? tB : tA;
      t = clamp(t, 0.0, 1.0);
      float mt = 1.0 - t;
      float xt = mt * mt * p0.x + 2.0 * mt * t * pc.x + t * t * p1.x;
      float w = clamp((xt - emX) * dir3.x + 0.5, 0.0, 1.0);
      d = s1 ? w : -w;
    } else if (b * b - 4.0 * a * e0 > 0.0 &&
        tA > 0.0 && tA < 1.0 && tB > 0.0 && tB < 1.0) {
      float tMin = min(tA, tB);
      float tMax = max(tA, tB);
      float mtA = 1.0 - tMin;
      float xA = mtA * mtA * p0.x + 2.0 * mtA * tMin * pc.x + tMin * tMin * p1.x;
      float mtB = 1.0 - tMax;
      float xB = mtB * mtB * p0.x + 2.0 * mtB * tMax * pc.x + tMax * tMax * p1.x;
      float wMin = clamp((xA - emX) * dir3.x + 0.5, 0.0, 1.0);
      float wMax = clamp((xB - emX) * dir3.x + 0.5, 0.0, 1.0);
      d = s0 ? (wMax - wMin) : (wMin - wMax);
    }
    covH += d;
    if (uDebug.x > 2.5 && abs(float(i) - uDebug.y) < 0.5) {
      dbgD = d;
      dbgE0 = e0;
      dbgE1 = e1;
    }
  }

  // vertical ray (+y): crossings of X(t) = emX, sign(-X'(t)) convention
  float vb = clamp(floor((emX - dir2.x) / dir2.y), 0.0, bandCount - 1.0);
  vec2 vTable = readPair(base + 1.0 + bandCount + vb);
  float covV = 0.0;
  for (int i = 0; i < 16; i++) {
    if (float(i) >= vTable.y) break;
    float curveT = base + readPair(base + vTable.x + float(i)).x;
    vec2 p0 = readEm(curveT);
    vec2 pc = readEm(curveT + 1.0);
    vec2 p1 = readEm(curveT + 2.0);
    float e0 = p0.x - emX;
    float e1 = p1.x - emX;
    bool s0 = e0 > 0.0;
    bool s1 = e1 > 0.0;
    float a = e0 - 2.0 * (pc.x - emX) + e1;
    float b = 2.0 * ((pc.x - emX) - e0);
    float sq = sqrt(max(b * b - 4.0 * a * e0, 0.0));
    float qq = -0.5 * (b + (b >= 0.0 ? sq : -sq));
    float tA = abs(a) > 1e-12 ? qq / a : 2.0;
    float tB = abs(qq) > 1e-12 ? e0 / qq : 2.0;
    if (s0 != s1) {
      float t = (tB >= 0.0 && tB <= 1.0) ? tB : tA;
      t = clamp(t, 0.0, 1.0);
      float mt = 1.0 - t;
      float yt = mt * mt * p0.y + 2.0 * mt * t * pc.y + t * t * p1.y;
      float w = clamp((yt - emY) * dir3.y + 0.5, 0.0, 1.0);
      covV += s1 ? -w : w;
    } else if (b * b - 4.0 * a * e0 > 0.0 &&
        tA > 0.0 && tA < 1.0 && tB > 0.0 && tB < 1.0) {
      float tMin = min(tA, tB);
      float tMax = max(tA, tB);
      float mtA = 1.0 - tMin;
      float yA = mtA * mtA * p0.y + 2.0 * mtA * tMin * pc.y + tMin * tMin * p1.y;
      float mtB = 1.0 - tMax;
      float yB = mtB * mtB * p0.y + 2.0 * mtB * tMax * pc.y + tMax * tMax * p1.y;
      float wMin = clamp((yA - emY) * dir3.y + 0.5, 0.0, 1.0);
      float wMax = clamp((yB - emY) * dir3.y + 0.5, 0.0, 1.0);
      covV += s0 ? (wMin - wMax) : (wMax - wMin);
    }
  }

  if (uDebug.x > 2.5) {
    // per-curve H diagnostics for curve index uDebug.y
    fragColor = vec4(dbgD * 0.25 + 0.5, dbgE0 * 0.25 + 0.5,
        dbgE1 * 0.25 + 0.5, 1.0);
    return;
  }
  if (uDebug.x > 1.5) {
    // ray sums: |covH|, |covV|, signed covH
    fragColor = vec4(clamp(abs(covH), 0.0, 1.0), clamp(abs(covV), 0.0, 1.0),
        clamp(covH * 0.25 + 0.5, 0.0, 1.0), 1.0);
    return;
  }
  if (uDebug.x > 0.5) {
    fragColor = vec4(hb / 8.0, hTable.y / 16.0, emY / 4.0 + 0.5, 1.0);
    return;
  }
  float cov = (min(abs(covH), 1.0) + min(abs(covV), 1.0)) * 0.5;
  // premultiplied white x coverage; tint rides per-vertex colors through
  // BlendMode.modulate, exactly like pdf_strips.frag
  fragColor = vec4(cov);
}

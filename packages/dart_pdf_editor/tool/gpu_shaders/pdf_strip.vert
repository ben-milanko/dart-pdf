// Sparse-strip quads (vello_hybrid-style CPU coverage rasterization).
//
// Each strip is one axis-aligned quad, `width` px wide and 4 px tall, drawn
// in painter's order with alpha blending - no stencil, no MSAA. Positions
// arrive in device pixels (y-down) and are mapped to NDC here via the
// viewport uniform, so the CPU side can copy the strip generator's u16
// coordinates straight into the vertex buffer.
//
// texel_index is the *global* index into the alpha atlas (each atlas texel
// holds one 1x4 px coverage column in its RGBA channels). The left edge of
// the quad carries the strip's alphaOffset and the right edge alphaOffset +
// width, so plain linear interpolation lands each fragment on its own
// column; the fragment stage floors it and converts to atlas x/y.
//
// y_flags carries the strip-local row: 0 at the strip's top edge, 4 at its
// bottom, so fragments interpolate to row 0..4 and floor() picks the RGBA
// channel. Solid strips (coverage 1 everywhere, no alpha data) add +4.0:
// the fragment stage reads y_flags >= 4 as "skip the fetch".
uniform VertInfo {
  vec2 viewport; // render-target size in device px
}
vert_info;

in vec2 position;     // device px, y-down
in float texel_index; // global alpha-atlas texel index (column)
in float y_flags;     // strip-local row 0..4; +4.0 flags a solid strip
in vec4 color;        // premultiplied RGBA

out float v_texel;
out float v_yflags;
out vec4 v_color;

void main() {
  v_texel = texel_index;
  v_yflags = y_flags;
  v_color = color;
  gl_Position = vec4(2.0 * position.x / vert_info.viewport.x - 1.0,
                     1.0 - 2.0 * position.y / vert_info.viewport.y, 0.0, 1.0);
}

import 'dart:math' as math;

/// Forward-extrapolates a short speculative "lead" beyond the last sampled
/// point of an in-progress ink stroke, to mask the input+render latency
/// between the pen tip and the painted line — the pure-geometry analogue of
/// PencilKit's predicted touches (which read the OS's hardware predictor).
/// Display only: the returned points are drawn ahead of the stroke but never
/// enter the committed /InkList.
///
/// [points] are the recent stroke samples in page space, oldest → newest.
/// The lead starts from the last two samples' velocity, bends along the last
/// three samples' curvature (the polyline's acceleration, scaled by
/// [curvatureDamping]), and advances by [gain] times the last segment
/// ([gain] 1.0 ≈ one more sample). [steps] predicted points are returned,
/// each capped at [maxLeadFactor] times the last segment so a noisy
/// acceleration estimate can't fling the line off the tip.
///
/// Returns an empty list — no prediction — when extrapolation would be
/// unstable:
///   * fewer than two samples (no velocity to extend),
///   * a near-stationary pen (last segment shorter than [minSegment]), where
///     prediction only adds jitter, or
///   * a sharp direction reversal (the pen turned more than [maxTurn]
///     radians), where forward extrapolation would shoot past the cusp.
List<(double, double)> pdfPredictStrokeLead(
  List<(double, double)> points, {
  int steps = 1,
  double gain = 0.9,
  double curvatureDamping = 0.5,
  double minSegment = 0.75,
  double maxLeadFactor = 1.6,
  double maxTurn = 2.0, // radians, ~115°
}) {
  if (points.length < 2 || steps < 1) return const [];
  final (px, py) = points[points.length - 1];
  final (qx, qy) = points[points.length - 2];
  var vx = px - qx;
  var vy = py - qy;
  final speed = math.sqrt(vx * vx + vy * vy);
  if (speed < minSegment) return const [];

  // curvature from the last three samples — the change in velocity, so the
  // lead follows an arc rather than flying off the last segment's tangent
  var ax = 0.0, ay = 0.0;
  if (points.length >= 3) {
    final (rx, ry) = points[points.length - 3];
    final pvx = qx - rx; // the previous segment's velocity
    final pvy = qy - ry;
    final pspeed = math.sqrt(pvx * pvx + pvy * pvy);
    if (pspeed >= minSegment) {
      // a reversal or hard corner: don't predict across the cusp
      final cosTurn = (vx * pvx + vy * pvy) / (speed * pspeed);
      if (math.acos(cosTurn.clamp(-1.0, 1.0)) > maxTurn) return const [];
      ax = vx - pvx;
      ay = vy - pvy;
    }
  }

  final cap = speed * maxLeadFactor;
  final lead = <(double, double)>[];
  var cx = px, cy = py;
  for (var k = 0; k < steps; k++) {
    var dx = vx * gain + 0.5 * ax * gain * gain * curvatureDamping;
    var dy = vy * gain + 0.5 * ay * gain * gain * curvatureDamping;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > cap && len > 0) {
      final s = cap / len;
      dx *= s;
      dy *= s;
    }
    cx += dx;
    cy += dy;
    lead.add((cx, cy));
    // carry the bent velocity forward so multi-step leads keep curving
    vx += ax * curvatureDamping;
    vy += ay * curvatureDamping;
  }
  return lead;
}

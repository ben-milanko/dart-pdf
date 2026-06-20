// Turns raw device/window captures into App Store / Play Store marketing
// screenshots: each capture is dropped onto a brand gradient canvas with a
// headline and subtitle, framed with rounded corners and a soft shadow, and
// rendered at an exact store dimension.
//
// The whole composition is one SVG (gradient + text + the capture embedded as
// a base64 <image> with a rounded clip and a blurred drop shadow) rendered to
// PNG with `rsvg-convert -w <W> -h <H>` — no per-pixel work in Dart, crisp
// type from a real system font.
//
// Usage (tool/screenshots.sh drives this after each capture run):
//   dart run tool/compose_marketing.dart \
//     --in  doc/screenshots/<target>/<platform> \
//     --out doc/marketing/<target>/<platform> \
//     --orientation landscape|portrait \
//     --width 1440 --height 900 \
//     --target app|example
//
// Requires `rsvg-convert` on PATH (brew install librsvg).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Headline + subtitle per screenshot, keyed `<target>/<basename>` (the raw
/// PNG name without its extension). Edit these freely — they're the only
/// marketing copy in the pipeline.
const _captions = <String, (String, String)>{
  // The standalone DartPDF app.
  'app/01-welcome': ('DartPDF', 'A native PDF editor'),
  'app/02-editor': ('Edit PDFs', 'Tabs, panels, and the full toolset'),
  'app/03-dark': ('Light and dark themes', 'Follows your system theme'),

  // The dart_pdf_editor example showcase.
  'example/01-document': ('Open any PDF', 'Rendered in pure Dart, on every platform'),
  'example/02-graphics': ('Graphics', 'Gradients, shadings, and transparency'),
  'example/03-annotations': ('Annotations', 'Highlights, ink, notes, stamps, and forms'),
  'example/04-markup': ('Markup tools', 'Draw, add shapes, and sign on the page'),
  'example/05-reader': ('Reading view', 'Reflows text to fit the screen'),
};

/// An optional hand-drawn markup flourish per screenshot, keyed
/// `<target>/<basename>` (same scheme as [_captions]). Each builder is handed
/// the device-frame rect (its on-canvas left/top/width/height after scaling)
/// and the canvas orientation, and returns SVG drawn *over* the capture —
/// deliberately allowed to run past the frame edge into the gradient, the way a
/// reviewer's pen overshoots the page. Only the standalone-app shots are marked
/// up. Geometry is in frame fractions (values outside 0..1 fall beyond the
/// frame), and is orientation-aware: the wide landscape window has room around
/// it for a ring, while the near-full-bleed phone reads better with a linear
/// mark that simply exits an edge.
final _annotations = <String, _Flourish>{
  // Hero: a wide "windscreen wiper" ink sweep fanning out from a pivot just
  // past the bottom-right corner, its streaks running off the frame.
  'app/01-welcome': _Flourish((f, portrait) => _wiperStreaks(
        f.x(portrait ? 1.04 : 1.10), f.y(portrait ? 1.04 : 1.12),
        rInner: f.diag(portrait ? 0.14 : 0.16),
        rOuter: f.diag(portrait ? 0.52 : 0.66),
        aStartDeg: 190,
        aEndDeg: 244,
        sweeps: 4,
        weight: f.min(portrait ? 0.013 : 0.017),
      )),
  // Editor: a highlighter swipe across a content row that runs off the right
  // edge of the frame.
  'app/02-editor': _Flourish((f, portrait) => _highlight(
        f.x(0.40), f.y(portrait ? 0.40 : 0.42), f.x(1.10),
        f.y(portrait ? 0.40 : 0.42),
        weight: f.h(portrait ? 0.022 : 0.05),
      )),
  // Dark: an ink underline that sweeps out past the left edge of the frame.
  'app/03-dark': _Flourish((f, portrait) => _underline(
        f.x(0.52), f.y(portrait ? 0.30 : 0.28), f.x(-0.08),
        f.y(portrait ? 0.30 : 0.28),
        weight: f.min(portrait ? 0.015 : 0.019),
      )),
};

/// The brand "ink" colour for drawn-on markup — a confident marker red-orange
/// that reads cleanly over both the screenshot and the blue gradient.
const _inkColor = '#FF5A47';

/// Wraps a flourish builder so it can sit in a `const`-free map. [build] takes
/// the resolved device-frame rect and the canvas orientation, and returns an
/// SVG fragment.
class _Flourish {
  const _Flourish(this.build);
  final String Function(_FrameRect frame, bool portrait) build;
}

/// The on-canvas rect of the embedded capture, with helpers to place marks in
/// frame-fraction coordinates (values outside 0..1 fall beyond the frame).
class _FrameRect {
  const _FrameRect(this.left, this.top, this.width, this.height);
  final double left, top, width, height;

  /// X at fraction [fx] across the frame (0 = left edge, 1 = right edge).
  double x(double fx) => left + width * fx;

  /// Y at fraction [fy] down the frame.
  double y(double fy) => top + height * fy;

  /// A length as a fraction of the frame width.
  double fw(double f) => width * f;

  /// A length as a fraction of the frame height.
  double h(double f) => height * f;

  /// A length as a fraction of the frame height (alias of [h], for radii).
  double fh(double f) => height * f;

  /// A length as a fraction of the frame's smaller side (for round marks and
  /// stroke weights, so they read the same thickness in either orientation).
  double min(double f) => (width < height ? width : height) * f;

  /// A length as a fraction of the frame diagonal (for marks that span the
  /// frame, like the wiper sweep).
  double diag(double f) => sqrt(width * width + height * height) * f;
}

/// A translucent highlighter swipe (thick round-capped stroke) from
/// ([x1],[y1]) to ([x2],[y2]).
String _highlight(double x1, double y1, double x2, double y2,
    {required double weight, String color = '#FFD23F', double opacity = 0.5}) {
  return '<line x1="${x1.toStringAsFixed(1)}" y1="${y1.toStringAsFixed(1)}" '
      'x2="${x2.toStringAsFixed(1)}" y2="${y2.toStringAsFixed(1)}" '
      'stroke="$color" stroke-opacity="$opacity" stroke-width="$weight" '
      'stroke-linecap="round"/>';
}

/// A hand-drawn "windscreen wiper" sweep: one continuous stroke that fans back
/// and forth across an angular range about a pivot at ([pivotX],[pivotY]),
/// spiralling out from [rInner] to [rOuter] so each pass lays down a wide
/// curved streak. [sweeps] is the number of passes across the range (a
/// back-and-forth is two), [aStartDeg]/[aEndDeg] the swing limits.
String _wiperStreaks(double pivotX, double pivotY,
    {required double rInner,
    required double rOuter,
    required double aStartDeg,
    required double aEndDeg,
    required double sweeps,
    required double weight,
    String color = _inkColor}) {
  final a0 = aStartDeg * pi / 180, a1 = aEndDeg * pi / 180;
  const steps = 280;
  final pts = <String>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final r = rInner + (rOuter - rInner) * t;
    // Cosine swing: the blade eases a0→a1→a0… across `sweeps` passes, so the
    // turnarounds are rounded rather than sharp cusps.
    final phase = t * sweeps;
    final frac = 0.5 - 0.5 * cos(phase * pi);
    final a = a0 + (a1 - a0) * frac;
    final x = pivotX + r * cos(a), y = pivotY + r * sin(a);
    pts.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
  }
  final d = 'M${pts.first} ${pts.skip(1).map((p) => 'L$p').join(' ')}';
  return '<path d="$d" fill="none" stroke="$color" stroke-width="$weight" '
      'stroke-linecap="round" stroke-linejoin="round" stroke-opacity="0.92"/>';
}

/// A hand-drawn ink underline: a single round-capped stroke with a gentle bow,
/// from ([x1],[y1]) to ([x2],[y2]).
String _underline(double x1, double y1, double x2, double y2,
    {required double weight, String color = _inkColor}) {
  // A slight downward bow at the midpoint reads as a pen stroke, not a ruler.
  final mx = (x1 + x2) / 2, my = (y1 + y2) / 2 + weight * 1.6;
  return '<path d="M${x1.toStringAsFixed(1)},${y1.toStringAsFixed(1)} '
      'Q${mx.toStringAsFixed(1)},${my.toStringAsFixed(1)} '
      '${x2.toStringAsFixed(1)},${y2.toStringAsFixed(1)}" '
      'fill="none" stroke="$color" stroke-width="$weight" '
      'stroke-linecap="round" stroke-opacity="0.92"/>';
}

void main(List<String> argv) async {
  final args = _parseArgs(argv);
  final inDir = Directory(args['in']!);
  final outDir = Directory(args['out']!)..createSync(recursive: true);
  final orientation = args['orientation'] ?? 'landscape';
  final width = int.parse(args['width'] ?? (orientation == 'portrait' ? '1320' : '1440'));
  final height = int.parse(args['height'] ?? (orientation == 'portrait' ? '2868' : '900'));
  final target = args['target'] ?? inDir.parent.uri.pathSegments
      .where((s) => s.isNotEmpty)
      .last; // <target>/<platform>

  if (!inDir.existsSync()) {
    stderr.writeln('[compose] no input dir: ${inDir.path}');
    exit(1);
  }
  if (!await _has('rsvg-convert')) {
    stderr.writeln('[compose] rsvg-convert not found (brew install librsvg).');
    exit(1);
  }

  final shots = inDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (shots.isEmpty) {
    stderr.writeln('[compose] no PNGs in ${inDir.path}');
    exit(1);
  }

  var made = 0;
  for (final shot in shots) {
    final base = shot.uri.pathSegments.last.replaceAll('.png', '');
    final caption = _captions['$target/$base'] ?? (_titleCase(base), '');
    final svg = _composeSvg(
      shotBytes: shot.readAsBytesSync(),
      width: width,
      height: height,
      portrait: orientation == 'portrait',
      headline: caption.$1,
      subtitle: caption.$2,
      flourish: _annotations['$target/$base'],
    );
    final tmp = File('${outDir.path}/.$base.svg')..writeAsStringSync(svg);
    final out = '${outDir.path}/$base.png';
    final r = await Process.run('rsvg-convert', [
      '-w', '$width', '-h', '$height',
      '-o', out, tmp.path,
    ]);
    tmp.deleteSync();
    if (r.exitCode != 0) {
      stderr.writeln('[compose] $base failed: ${r.stderr}');
    } else {
      stdout.writeln('[compose] $out  (${width}x$height)');
      made++;
    }
  }
  stdout.writeln('[compose] $made marketing image(s) → ${outDir.path}/');
  if (made == 0) exit(1);
}

/// Builds the marketing SVG for one capture. The capture is scaled to fit a
/// content box (sized per orientation), centred horizontally, with a blurred
/// shadow behind it and a rounded clip in front; the headline/subtitle sit
/// above it.
String _composeSvg({
  required List<int> shotBytes,
  required int width,
  required int height,
  required bool portrait,
  required String headline,
  required String subtitle,
  _Flourish? flourish,
}) {
  final (sw, sh) = _pngSize(shotBytes);
  final b64 = base64Encode(shotBytes);
  final w = width.toDouble(), h = height.toDouble();

  // Type sizes scale with the canvas; portrait is narrower so it keys off
  // width, landscape off height.
  final unit = portrait ? w : h;
  final headSize = unit * (portrait ? 0.066 : 0.060);
  final subSize = unit * (portrait ? 0.040 : 0.034);
  final cornerRadius = (portrait ? w : h) * 0.028;

  // Text block near the top, then the capture fills the rest.
  final headY = h * (portrait ? 0.085 : 0.135);
  final subY = headY + headSize * 1.15;
  final contentTop = h * (portrait ? 0.20 : 0.28);
  final contentBottom = h * (portrait ? 0.97 : 0.93);
  // Side margins: portrait hugs the edges (a phone fills the width), landscape
  // leaves more air around the window.
  final sideMargin = w * (portrait ? 0.07 : 0.09);

  final boxW = w - sideMargin * 2;
  final boxH = contentBottom - contentTop;
  final scale = (boxW / sw).clamp(0.0, boxH / sh);
  final dw = sw * scale, dh = sh * scale;
  final dx = (w - dw) / 2;
  // Portrait anchors the device to the top of the content box (phone peeks off
  // the bottom edge); landscape centres the window in the box.
  final dy = portrait ? contentTop : contentTop + (boxH - dh) / 2;

  final shadowDy = h * 0.012;
  final blur = (portrait ? w : h) * 0.012;

  final head = _esc(headline);
  final sub = _esc(subtitle);

  // Drawn-on markup, painted last so it sits over the capture (and may spill
  // past the frame into the gradient).
  final marks = flourish?.build(_FrameRect(dx, dy, dw, dh), portrait) ?? '';

  return '''
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height"
     viewBox="0 0 $width $height">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"   stop-color="#0A1B3D"/>
      <stop offset="0.5" stop-color="#123E92"/>
      <stop offset="1"   stop-color="#1AA0E0"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.0" r="0.9">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="shot">
      <rect x="$dx" y="$dy" width="$dw" height="$dh" rx="$cornerRadius" ry="$cornerRadius"/>
    </clipPath>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="$blur"/>
    </filter>
  </defs>

  <rect width="$width" height="$height" fill="url(#bg)"/>
  <rect width="$width" height="$height" fill="url(#glow)"/>

  <text x="${w / 2}" y="$headY" fill="#FFFFFF" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-weight="700" font-size="$headSize">$head</text>
  ${sub.isEmpty ? '' : '''
  <text x="${w / 2}" y="$subY" fill="#FFFFFF" fill-opacity="0.82" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-weight="400" font-size="$subSize">$sub</text>'''}

  <rect x="$dx" y="${dy + shadowDy}" width="$dw" height="$dh" rx="$cornerRadius" ry="$cornerRadius"
        fill="#000000" fill-opacity="0.38" filter="url(#soft)"/>
  <image x="$dx" y="$dy" width="$dw" height="$dh" clip-path="url(#shot)"
         preserveAspectRatio="none"
         xlink:href="data:image/png;base64,$b64"
         xmlns:xlink="http://www.w3.org/1999/xlink"/>
  <rect x="$dx" y="$dy" width="$dw" height="$dh" rx="$cornerRadius" ry="$cornerRadius"
        fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2"/>
  $marks
</svg>''';
}

/// Reads width/height from a PNG's IHDR (bytes 16–23, big-endian).
(int, int) _pngSize(List<int> b) {
  int u32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (u32(16), u32(20));
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _titleCase(String name) => name
    .replaceAll(RegExp(r'^\d+-'), '')
    .split(RegExp(r'[-_]'))
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      final key = argv[i].substring(2);
      final val = (i + 1 < argv.length && !argv[i + 1].startsWith('--'))
          ? argv[++i]
          : 'true';
      out[key] = val;
    }
  }
  return out;
}

Future<bool> _has(String cmd) async {
  try {
    final r = await Process.run('command', ['-v', cmd], runInShell: true);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

// M0 feasibility probes for shader-driven strip rendering.
//
// Verifies, on whatever backend `flutter test` is hosting (software Skia by
// default, Impeller with --enable-impeller), the platform behaviors the strip
// renderer depends on:
//   1. which coordinate space a FragmentShader Paint is evaluated in when
//      drawn via canvas.drawVertices with textureCoordinates,
//   2. exact texel reads from an rgba8888 data texture via nearest-sampled
//      texture() at half-texel centers,
//   3. RGBA channel select with a step-mask dot (SkSL-safe),
//   4. BlendMode.modulate combining vertex colors with shader coverage,
//   5. the mutate-uniforms -> draw -> mutate pattern inside one picture.
//
// The tests PASS for either coordinate-space answer (texcoord or position);
// the answer itself is printed as `PROBE:` lines and recorded in the dev-log.
// They FAIL only when a dependency is genuinely broken (garbage coordinates,
// inexact texel reads, wrong channel math).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const int _texSize = 64;

/// Texel pattern: rows 0..31 are opaque (A=255) with R=i, G=j,
/// B=(7i+13j)%256; rows 32..63 vary every channel including alpha.
List<int> _texel(int i, int j) {
  if (j < 32) return [i, j, (7 * i + 13 * j) % 256, 255];
  return [(5 * i) % 256, (11 * j) % 256, (i + 2 * j) % 256, (9 * i + 3 * j) % 256];
}

Future<ui.Image> _makeDataTexture() {
  final pixels = Uint8List(_texSize * _texSize * 4);
  for (var j = 0; j < _texSize; j++) {
    for (var i = 0; i < _texSize; i++) {
      final t = _texel(i, j);
      final o = (j * _texSize + i) * 4;
      pixels[o] = t[0];
      pixels[o + 1] = t[1];
      pixels[o + 2] = t[2];
      pixels[o + 3] = t[3];
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, _texSize, _texSize, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

Future<ui.FragmentProgram> _loadProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset('shaders/pdf_probe.frag');
  } catch (_) {
    return ui.FragmentProgram.fromAsset(
        'packages/dart_pdf_editor/shaders/pdf_probe.frag');
  }
}

ui.Vertices _quad(ui.Rect pos, ui.Rect tex, {int? color}) {
  final positions = Float32List.fromList([
    pos.left, pos.top, pos.right, pos.top, //
    pos.left, pos.bottom, pos.right, pos.bottom,
  ]);
  final texs = Float32List.fromList([
    tex.left, tex.top, tex.right, tex.top, //
    tex.left, tex.bottom, tex.right, tex.bottom,
  ]);
  final indices = Uint16List.fromList([0, 1, 2, 1, 3, 2]);
  return ui.Vertices.raw(ui.VertexMode.triangles, positions,
      textureCoordinates: texs,
      colors: color == null ? null : Int32List.fromList(List.filled(4, color)),
      indices: indices);
}

Future<Uint8List> _renderToBytes(
    void Function(ui.Canvas) draw, int w, int h) async {
  final rec = ui.PictureRecorder();
  draw(ui.Canvas(rec));
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  pic.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

int _px(Uint8List bytes, int w, int x, int y, int c) =>
    bytes[(y * w + x) * 4 + c];

void main() {
  late ui.FragmentProgram program;
  late ui.Image dataTexture;
  // 'texcoord' | 'position', decided by the first probe and asserted
  // consistent by the rest.
  late String space;

  ui.FragmentShader _shader(double mode, {double row = 0}) {
    final s = program.fragmentShader();
    s.setFloat(0, _texSize.toDouble());
    s.setFloat(1, _texSize.toDouble());
    s.setFloat(2, mode);
    s.setFloat(3, row);
    s.setImageSampler(0, dataTexture);
    return s;
  }

  // Expected texel under the detected space for a quad drawn with
  // pos origin (0,0) and tex origin (tx,ty).
  List<int> _expect(int x, int y, int tx, int ty) =>
      space == 'texcoord' ? _texel(x + tx, y + ty) : _texel(x, y);

  setUpAll(() async {
    program = await _loadProgram();
    dataTexture = await _makeDataTexture();
  });

  testWidgets('probe: coordinate space of drawVertices + FragmentShader',
      (tester) async {
    await tester.runAsync(() async {
      final shader = _shader(0);
      final bytes = await _renderToBytes((canvas) {
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(0, 0, 32, 32),
                const ui.Rect.fromLTRB(100, 60, 132, 92)),
            ui.BlendMode.srcOver,
            ui.Paint()..shader = shader);
      }, 32, 32);

      String classify(int x, int y) {
        final r = _px(bytes, 32, x, y, 0);
        final g = _px(bytes, 32, x, y, 1);
        bool near(int v, num want) => (v - want).abs() <= 1.5;
        if (near(r, x + 100.5) && near(g, y + 60.5)) return 'texcoord';
        if (near(r, x + 0.5) && near(g, y + 0.5)) return 'position';
        return 'unknown(r=$r g=$g at $x,$y)';
      }

      final a = classify(4, 4);
      final b = classify(20, 12);
      expect(a, anyOf('texcoord', 'position'),
          reason: 'shader evaluated in unrecognized space: $a');
      expect(b, a, reason: 'inconsistent interpolation across the quad');
      space = a;
      // ignore: avoid_print
      print('PROBE: drawVertices+FragmentShader evaluation space = $space');
    });
  });

  testWidgets('probe: exact texel reads (identity mapping)', (tester) async {
    await tester.runAsync(() async {
      final shader = _shader(1);
      final bytes = await _renderToBytes((canvas) {
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(0, 0, 32, 32),
                const ui.Rect.fromLTRB(0, 0, 32, 32)),
            ui.BlendMode.srcOver,
            ui.Paint()..shader = shader);
      }, 32, 32);

      for (final p in const [(0, 0), (5, 9), (31, 31), (17, 3), (30, 1)]) {
        final want = _texel(p.$1, p.$2);
        for (var c = 0; c < 4; c++) {
          expect((_px(bytes, 32, p.$1, p.$2, c) - want[c]).abs(),
              lessThanOrEqualTo(1),
              reason: 'texel ${p.$1},${p.$2} channel $c: '
                  'got ${_px(bytes, 32, p.$1, p.$2, c)} want ${want[c]}');
        }
      }
      // ignore: avoid_print
      print('PROBE: exact texel reads via texture()+half-texel centers = OK');
    });
  });

  testWidgets('probe: texcoord-offset texel reads follow detected space',
      (tester) async {
    await tester.runAsync(() async {
      final shader = _shader(1);
      final bytes = await _renderToBytes((canvas) {
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(0, 0, 32, 32),
                const ui.Rect.fromLTRB(16, 8, 48, 40)),
            ui.BlendMode.srcOver,
            ui.Paint()..shader = shader);
      }, 32, 32);

      for (final p in const [(2, 3), (10, 20), (15, 15)]) {
        final want = _expect(p.$1, p.$2, 16, 8);
        // Rows >= 32 in the texture have varying alpha; the raw framebuffer
        // holds premultiplied values there, so only assert opaque texels.
        if (want[3] != 255) continue;
        for (var c = 0; c < 3; c++) {
          expect((_px(bytes, 32, p.$1, p.$2, c) - want[c]).abs(),
              lessThanOrEqualTo(1),
              reason: 'offset texel ${p.$1},${p.$2} channel $c');
        }
      }
      // ignore: avoid_print
      print('PROBE: offset texcoords consistent with $space space = OK');
    });
  });

  testWidgets('probe: RGBA channel select via step-mask dot', (tester) async {
    await tester.runAsync(() async {
      for (var row = 0; row < 4; row++) {
        final shader = _shader(2, row: row.toDouble());
        final bytes = await _renderToBytes((canvas) {
          canvas.drawVertices(
              _quad(const ui.Rect.fromLTRB(0, 0, 16, 16),
                  const ui.Rect.fromLTRB(8, 40, 24, 56)),
              ui.BlendMode.srcOver,
              ui.Paint()..shader = shader);
        }, 16, 16);
        for (final p in const [(1, 2), (7, 11), (14, 5)]) {
          final texel = _expect(p.$1, p.$2, 8, 40);
          expect((_px(bytes, 16, p.$1, p.$2, 0) - texel[row]).abs(),
              lessThanOrEqualTo(1),
              reason: 'channel $row at ${p.$1},${p.$2}: '
                  'got ${_px(bytes, 16, p.$1, p.$2, 0)} want ${texel[row]}');
        }
      }
      // ignore: avoid_print
      print('PROBE: step-mask channel select = OK');
    });
  });

  testWidgets('probe: BlendMode.modulate vertex color x shader coverage',
      (tester) async {
    await tester.runAsync(() async {
      // Coverage = R channel of opaque texels (row < 32 => R = i).
      final shader = _shader(2, row: 0);
      const color = 0xFFC84020; // ARGB: a=255 r=200 g=64 b=32
      final bytes = await _renderToBytes((canvas) {
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(0, 0, 32, 32),
                const ui.Rect.fromLTRB(0, 0, 32, 32), color: color),
            ui.BlendMode.modulate,
            ui.Paint()..shader = shader);
      }, 32, 32);

      for (final p in const [(4, 4), (16, 8), (31, 30)]) {
        final cov = _texel(p.$1, p.$2)[0] / 255.0;
        final want = [200 * cov, 64 * cov, 32 * cov];
        for (var c = 0; c < 3; c++) {
          expect((_px(bytes, 32, p.$1, p.$2, c) - want[c]).abs(),
              lessThanOrEqualTo(2.0),
              reason: 'modulate channel $c at ${p.$1},${p.$2}: '
                  'got ${_px(bytes, 32, p.$1, p.$2, c)} want ${want[c]}');
        }
      }
      // ignore: avoid_print
      print('PROBE: modulate vertex-color x coverage = OK');
    });
  });

  testWidgets('probe: uniform mutation between draws in one picture',
      (tester) async {
    await tester.runAsync(() async {
      // One shader instance: draw channel R at x<16, mutate to channel G,
      // draw at x>=16. Both draws must reflect their own uniform values.
      final shader = _shader(2, row: 0);
      final bytes = await _renderToBytes((canvas) {
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(0, 0, 16, 16),
                const ui.Rect.fromLTRB(0, 0, 16, 16)),
            ui.BlendMode.srcOver,
            ui.Paint()..shader = shader);
        shader.setFloat(3, 1); // row -> G
        canvas.drawVertices(
            _quad(const ui.Rect.fromLTRB(16, 0, 32, 16),
                const ui.Rect.fromLTRB(0, 0, 16, 16)),
            ui.BlendMode.srcOver,
            ui.Paint()..shader = shader);
      }, 32, 16);

      // Left half: coverage = R = i. Right half: coverage = G = j.
      expect((_px(bytes, 32, 9, 4, 0) - 9).abs(), lessThanOrEqualTo(1),
          reason: 'first draw should use pre-mutation uniforms');
      expect((_px(bytes, 32, 25, 4, 0) - 4).abs(), lessThanOrEqualTo(1),
          reason: 'second draw should use post-mutation uniforms');
      // ignore: avoid_print
      print('PROBE: per-draw uniform snapshot = OK');
    });
  });
}

// Pins the Linux runners to Skia (#912).
//
// On Linux, Flutter turns Impeller on by default and runs it on OpenGL. There
// Impeller gets MSAA only from an OpenGL ES 3 context or
// GL_EXT_multisampled_render_to_texture2, which most desktop GL drivers don't
// give it, and it has no other antialiasing for arbitrary paths. Embedded PDF
// text is drawn as glyph outline paths, so every page came out with 1-bit
// edges and missing hairlines. The switch lives in native runner code no Dart
// test can run, so this test checks the runner sources directly: if a
// template regeneration or a runner refactor drops the call, it fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final call = RegExp(
    r'fl_dart_project_set_enable_impeller\(\s*project\s*,\s*([^;]*)\);',
  );

  test('the DartPDF Linux runner renders with Skia unless opted in', () {
    final source = File('linux/runner/my_application.cc').readAsStringSync();
    final match = call.firstMatch(source);
    expect(match, isNotNull,
        reason: 'the runner must choose the renderer explicitly (#912)');
    // Impeller stays opt-in: only the diagnostic environment switch enables it.
    expect(
      match!.group(1),
      contains('g_getenv("DARTPDF_IMPELLER")'),
    );
    // The project must be configured before any engine is created from it.
    expect(match.start, lessThan(source.indexOf('fl_engine_new_headless')));
    expect(match.start, lessThan(source.indexOf('fl_view_new(project)')));
  });

  test('the example Linux runner renders with Skia', () {
    final source = File(
      '../packages/dart_pdf_editor/example/linux/runner/my_application.cc',
    ).readAsStringSync();
    final match = call.firstMatch(source);
    expect(match, isNotNull,
        reason: 'the example runner must choose the renderer explicitly');
    expect(match!.group(1)!.trim(), 'FALSE');
    expect(match.start, lessThan(source.indexOf('fl_view_new(project)')));
  });
}

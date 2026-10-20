// The grab/grabbing cursors have no native Win32 handle, so Flutter's Windows
// embedder falls them back to the plain arrow - the "drag to pan" affordance
// vanishes. platform_cursors substitutes the four-way move cursor there and
// keeps the real grab cursor everywhere else.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/src/platform_cursors.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows substitutes the move cursor for grab/grabbing', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(grabCursor, SystemMouseCursors.move);
    expect(grabbingCursor, SystemMouseCursors.move);
  });

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.fuchsia,
  ]) {
    test('$platform renders the native grab/grabbing cursor', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(grabCursor, SystemMouseCursors.grab);
      expect(grabbingCursor, SystemMouseCursors.grabbing);
    });
  }
}

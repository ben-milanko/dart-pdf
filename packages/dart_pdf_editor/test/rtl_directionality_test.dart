import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the RTL sweep: chrome uses direction-relative geometry
/// (`EdgeInsetsDirectional` / `AlignmentDirectional`) so it mirrors under an
/// RTL `Directionality`, while page-space geometry stays physical.
void main() {
  Future<EdgeInsetsGeometry> captureToastMargin(
    WidgetTester tester, {
    required Size size,
  }) async {
    late EdgeInsetsGeometry margin;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) {
            margin = pdfFloatingToastMargin(context);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    return margin;
  }

  group('pdfFloatingToastMargin', () {
    testWidgets('wide window: pill hugs the trailing edge in both directions',
        (tester) async {
      // 1000px wide, default pill 360 → start inset 1000-360-24 = 616.
      final margin = await captureToastMargin(tester, size: const Size(1000, 800));

      expect(margin, isA<EdgeInsetsDirectional>());

      final ltr = margin.resolve(TextDirection.ltr);
      // LTR: hugs the physical right (small right inset, large left inset).
      expect(ltr.right, 24);
      expect(ltr.left, 616);
      expect(ltr.bottom, 96);

      final rtl = margin.resolve(TextDirection.rtl);
      // RTL: mirrored — hugs the physical left instead.
      expect(rtl.left, 24);
      expect(rtl.right, 616);
      expect(rtl.bottom, 96);
    });

    testWidgets('narrow window: symmetric gutter, direction-independent',
        (tester) async {
      final margin = await captureToastMargin(tester, size: const Size(400, 800));

      final ltr = margin.resolve(TextDirection.ltr);
      final rtl = margin.resolve(TextDirection.rtl);
      expect(ltr.left, 16);
      expect(ltr.right, 16);
      // Nothing to mirror when both sides match.
      expect(rtl.left, ltr.left);
      expect(rtl.right, ltr.right);
    });
  });

  test('directional chrome icons mirror automatically under RTL', () {
    // The sweep relies on Material shipping these glyphs with
    // matchTextDirection baked into the IconData, so the plain Icon widget
    // flips them under an RTL Directionality with no per-site handling. Guard
    // that assumption against a future icon-set change.
    expect(Icons.undo.matchTextDirection, isTrue);
    expect(Icons.redo.matchTextDirection, isTrue);
    expect(Icons.chevron_right.matchTextDirection, isTrue);
  });
}

// The image-export dialog and filename helper (image_export.dart). The
// rasterize + platform save are exercised through editor_screen elsewhere;
// here we cover the pure pieces: the dialog's returned options and the
// suggested-filename builder.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/image_export.dart';

void main() {
  group('imageExportFileName', () {
    test('drops a trailing .pdf and appends the page + extension', () {
      expect(imageExportFileName('Report.pdf', 3, ImageExportFormat.png),
          'Report-p3.png');
      expect(imageExportFileName('Report.PDF', 1, ImageExportFormat.jpeg),
          'Report-p1.jpg');
    });

    test('keeps a name without a .pdf extension', () {
      expect(imageExportFileName('scan', 2, ImageExportFormat.png),
          'scan-p2.png');
    });

    test('falls back to a stem for an empty title', () {
      expect(imageExportFileName('   ', 5, ImageExportFormat.png),
          'page-p5.png');
    });
  });

  group('showImageExportDialog', () {
    testWidgets('returns PNG @ 150 dpi by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageExportDialog(context).then((r) {
                expect(r, isNotNull);
                expect(r!.format, ImageExportFormat.png);
                expect(r.dpi, 150);
              }),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-image-confirm')));
      await tester.pumpAndSettle();
    });

    testWidgets('honours a JPEG + dpi selection', (tester) async {
      ImageExportOptions? captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showImageExportDialog(context).then((r) => captured = r),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('JPEG'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-image-dpi')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('300 dpi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-image-confirm')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.format, ImageExportFormat.jpeg);
      expect(captured!.dpi, 300);
    });

    testWidgets('returns null on cancel', (tester) async {
      ImageExportOptions? captured;
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageExportDialog(context).then((r) {
                captured = r;
                done = true;
              }),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(captured, isNull);
    });
  });
}

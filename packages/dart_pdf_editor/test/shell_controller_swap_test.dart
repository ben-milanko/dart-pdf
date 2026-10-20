// PdfEditorView and PdfReader own a viewer controller until the host hands
// in its own. Swapping either the bytes or the controller under a live view
// whose pages have rendered must leave the view bound to the new controller,
// and must not touch the replaced one after it is disposed - the old viewer's
// pages let go of it only as the frame finishes.

import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settlePages(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget editor(Uint8List bytes, PdfViewerController? viewer) => MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
              bytes: bytes, viewerController: viewer, onSave: (_) {}),
        ),
      );
  Widget reader(Uint8List bytes, PdfViewerController? viewer) => MaterialApp(
        home: Scaffold(body: PdfReader(bytes: bytes, controller: viewer)),
      );

  for (final (name, shell) in [
    ('PdfEditorView', editor),
    ('PdfReader', reader)
  ]) {
    group(name, () {
      testWidgets('swapping bytes after pages render, then unmount',
          (tester) async {
        await tester.pumpWidget(shell(buildMultiPagePdf(3), null));
        await settlePages(tester);
        expect(find.byType(PdfPageView), findsWidgets);
        await tester.pumpWidget(shell(buildMultiPagePdf(2), null));
        await settlePages(tester);
        expect(find.byType(PdfPageView), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        await settlePages(tester);
      });

      testWidgets('an owned controller replaced by the host is let go cleanly',
          (tester) async {
        final host = PdfViewerController();
        addTearDown(host.dispose);
        final bytes = buildMultiPagePdf(3);
        await tester.pumpWidget(shell(bytes, null));
        await settlePages(tester);
        // used to assert: the shell disposed its own controller while the
        // viewer's pages still notified it
        await tester.pumpWidget(shell(bytes, host));
        await settlePages(tester);
        expect(host.pageCount, 3, reason: 'the viewer drives the new one');
        await tester.pumpWidget(const SizedBox());
        await settlePages(tester);
      });

      testWidgets('one host controller replaced by another rebinds the viewer',
          (tester) async {
        final a = PdfViewerController();
        final b = PdfViewerController();
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        final bytes = buildMultiPagePdf(3);
        await tester.pumpWidget(shell(bytes, a));
        await settlePages(tester);
        expect(a.pageCount, 3);
        await tester.pumpWidget(shell(bytes, b));
        await settlePages(tester);
        expect(b.pageCount, 3, reason: 'b was left unbound before');
        await tester.pumpWidget(shell(bytes, null));
        await settlePages(tester);
        await tester.pumpWidget(const SizedBox());
        await settlePages(tester);
      });
    });
  }
}

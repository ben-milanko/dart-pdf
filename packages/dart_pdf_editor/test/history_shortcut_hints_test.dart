import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [390.0, 900.0]) {
    testWidgets('history hints match platform and keyboard at width $width',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final editing = PdfEditingController(buildClassicPdf());
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        editing.addRectangle(0, const PdfRect(30, 30, 80, 80));
        final apple = defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS;
        Future<void> pump(bool keyboard) async {
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) =>
                PdfKeyboardAvailability(connected: keyboard, child: child!),
            home: Scaffold(
                body: Align(
              alignment: Alignment.bottomCenter,
              child: PdfEditingToolbar(
                  controller: editing, viewerController: viewer),
            )),
          ));
          await tester.pump();
        }

        String? tip(String key) =>
            tester.widget<IconButton>(find.byKey(ValueKey(key))).tooltip;
        await pump(true);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tip('pdf-undo'), apple ? 'Undo (⌘Z)' : 'Undo (Ctrl+Z)');
        expect(tip('pdf-redo'), apple ? 'Redo (⇧⌘Z)' : 'Redo (Ctrl+Shift+Z)');
        await tester.tap(find.byKey(const ValueKey('pdf-undo')));
        await tester.pump();
        expect(editing.canRedo, isTrue);
        await tester.tap(find.byKey(const ValueKey('pdf-redo')));
        await tester.pump();
        expect(editing.document.page(0).annotations.single.subtype, 'Square');
        await pump(false);
        expect(tip('pdf-undo'), 'Undo');
        expect(tip('pdf-redo'), 'Redo');
      } finally {
        semantics.dispose();
      }
    },
        variant: const TargetPlatformVariant({
          TargetPlatform.linux,
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.iOS,
        }));
  }
}

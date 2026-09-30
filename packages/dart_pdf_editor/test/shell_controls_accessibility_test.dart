import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor/src/shell_chrome.dart';

void main() {
  for (final scale in [1.0, 1.3, 1.31, 2.0, 3.0]) {
    testWidgets('compact controls preserve labels and actions at $scale text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      const libraryKey = ValueKey('fixture-annotation-library');
      const disabledKey = ValueKey('fixture-disabled');
      const libraryLabel = 'Annotation library';
      var libraryCalls = 0;
      var disabledCalls = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: PdfShellBar(
            leading: const [],
            trailing: const [],
            compactControls: [
              PdfShellControlItem(
                key: libraryKey,
                icon: Icons.collections_bookmark_outlined,
                label: libraryLabel,
                selected: true,
                group: PdfShellControlGroup.panels,
                onPressed: () => libraryCalls++,
              ),
              PdfShellControlItem(
                key: disabledKey,
                icon: Icons.block,
                label: 'Unavailable action',
                enabled: false,
                group: PdfShellControlGroup.panels,
                onPressed: () => disabledCalls++,
              ),
            ],
          ),
        ),
      ));
      final controls = find.byKey(const ValueKey('pdf-shell-controls'));
      expect(controls, findsOneWidget);
      await tester.tap(controls);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final library = find.byKey(libraryKey);
      final disabled = find.byKey(disabledKey);
      if (scale > 1.3) {
        expect(find.byType(GridView), findsNothing);
        expect(find.byType(ListTile), findsNWidgets(2));
        await tester.ensureVisible(library);
        await tester.pumpAndSettle();
        final text = find.descendant(of: library, matching: find.byType(Text));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textScaler.scale(11), closeTo(11 * scale, 0.001));
        for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: libraryLabel.length))) {
          expect(box.right, lessThanOrEqualTo(paragraph.size.width + 1));
          expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 1));
        }
      } else {
        expect(find.byType(GridView), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
      }
      await tester.ensureVisible(disabled);
      await tester.pumpAndSettle();
      await tester.tap(disabled);
      await tester.pumpAndSettle();
      expect(disabledCalls, 0);
      expect(find.byKey(libraryKey), findsOneWidget);
      await tester.ensureVisible(library);
      await tester.pumpAndSettle();
      await tester.tap(library);
      await tester.pumpAndSettle();
      expect(libraryCalls, 1);
      expect(find.byKey(libraryKey), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-controls')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

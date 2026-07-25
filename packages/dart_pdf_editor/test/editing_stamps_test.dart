import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List _png = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGUlEQVR4nGP4z8DwHwgb'
    'WBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

String appearanceText(PdfEditingController editing) {
  final annotation = editing.document.page(0).annotations.single;
  return latin1.decode(
      editing.document.cos.decodeStreamData(annotation.normalAppearance!));
}

dynamic overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(
            of: find.byType(EditingPageOverlay),
            matching: find.byType(CustomPaint))
        .first)
    .painter;

/// The overlay's hover-cursor layer - the pen dot, eraser ring, count/stamp
/// previews and rotate glyph, which read live state and repaint without a
/// rebuild. Read through a dynamic cast (the painter class is private).
dynamic cursorPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .firstWhere(
        (painter) => painter.runtimeType.toString() == '_HoverCursorPainter');

(int r, int g, int b, int a) pixelAt(ByteData pixels, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (
    pixels.getUint8(i),
    pixels.getUint8(i + 1),
    pixels.getUint8(i + 2),
    pixels.getUint8(i + 3)
  );
}

Future<({ByteData pixels, int width, int height})> captureBoundary(
    WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await tester.runAsync(() => boundary.toImage()) as ui.Image;
  final pixels = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba)) as ByteData;
  final result = (pixels: pixels, width: image.width, height: image.height);
  image.dispose();
  return result;
}

void main() {
  group('PdfCustomStamp', () {
    test('round-trips through JSON; junk decodes to null', () {
      const stamp = PdfCustomStamp(text: 'APPROVED', color: 0xC03030);
      expect(PdfCustomStamp.decode(stamp.encode()), stamp);
      expect(PdfCustomStamp.decode('not json'), isNull);
      expect(PdfCustomStamp.decode('{"text": "X"}'), isNull);
    });

    test('round-trips editable templates through JSON', () {
      final template = PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.text(
            x: 12,
            y: 14,
            width: 180,
            height: 30,
            text: 'APPROVED',
            color: 0xC03030,
            font: PdfStandardFont.timesBold,
          ),
          PdfStampTemplateComponent.ellipse(
            x: 74,
            y: 48,
            width: 30,
            height: 30,
            color: 0x2E7D32,
            fillColor: 0xE8F5E9,
            strokeWidth: 1.5,
          ),
          PdfStampTemplateComponent.image(
            x: 190,
            y: 16,
            width: 28,
            height: 28,
            imageBytes: _png,
          ),
          PdfStampTemplateComponent.signature(
            x: 36,
            y: 58,
            width: 168,
            height: 24,
            strokes: const [
              [(0.0, 0.8), (0.5, 0.2), (1.0, 0.7)],
            ],
            pressures: const [
              [0.0, 0.5, 1.0],
            ],
            color: 0x1A3E8C,
            strokeWidth: 2.4,
          ),
        ],
      );
      final stamp = PdfCustomStamp(
        text: 'APPROVED',
        color: 0xC03030,
        template: template,
        type: 'Approval',
        tags: const ['audit', 'tested'],
      );
      final decoded = PdfCustomStamp.decode(stamp.encode());
      expect(decoded, stamp);
      final decodedStamp = decoded!;
      expect(decodedStamp.type, 'Approval');
      expect(decodedStamp.hasTag('AUDIT'), isTrue);
      expect(decodedStamp.template, template);
      expect(decodedStamp.template!.components.length, 4);
      expect(decodedStamp.template!.components.first.font,
          PdfStandardFont.timesBold);
      final circle = decodedStamp.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.ellipse);
      expect(circle.width, circle.height);
      expect(circle.fillColor, 0xE8F5E9);
      final image = decodedStamp.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.image);
      expect(image.imageBytes, _png);
      final signature = decodedStamp.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.signature);
      expect(signature.strokes.single.last, (1.0, 0.7));
      expect(signature.pressures.single!.last, 1.0);

      final noPressure = PdfStampTemplateComponent.signature(
        x: 0,
        y: 0,
        width: 80,
        height: 24,
        strokes: const [
          [(0.0, 0.5), (1.0, 0.5)],
        ],
        color: 0x000000,
      );
      expect(
          PdfStampTemplateComponent.fromJson(noPressure.toJson()), noPressure);
      expect(
          () => PdfStampTemplateComponent.signature(
                x: 0,
                y: 0,
                width: 80,
                height: 24,
                strokes: const [
                  [(0.0, 0.5), (1.0, 0.5)],
                ],
                pressures: const [
                  [0.5],
                ],
                color: 0x000000,
              ),
          throwsArgumentError);
    });

    test('resolves template placeholders without mutating the saved template',
        () {
      expect(
          pdfResolveStampTemplateText(
              'Issued {{ Date }} by {{username}} for {{missing}}',
              {'date': '2026-07-04', 'username': 'Ben'}),
          'Issued 2026-07-04 by Ben for {{missing}}');

      final template = PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.text(
            x: 12,
            y: 30,
            width: 216,
            height: 36,
            text: '{{project}}',
            color: 0x1A3E8C,
          ),
        ],
      );
      final resolved = template.resolveText({'project': 'AMT-SP'});
      expect(resolved.components.single.text, 'AMT-SP');
      expect(template.components.single.text, '{{project}}');
    });

    test('persists through PdfEditingPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final template = PdfStampTemplate.text('PAID', 0xEF6C00);
      final paid =
          PdfCustomStamp(text: 'PAID', color: 0xEF6C00, template: template);
      final a = PdfEditingPreferences();
      await a.ready;
      a.customStamps = [
        const PdfCustomStamp(text: 'APPROVED', color: 0xC03030),
        paid,
      ];
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.customStamps, [
        const PdfCustomStamp(text: 'APPROVED', color: 0xC03030),
        paid,
      ]);
      expect(b.customStamps.last.template, template);

      a.customStamps = const [];
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.customStamps, isEmpty);
    });
  });

  group('custom stamps on the controller', () {
    const approved = PdfCustomStamp(text: 'APPROVED', color: 0x2E7D32);
    const draft = PdfCustomStamp(text: 'DRAFT', color: 0x1A3E8C);

    test('save, remove, and active-stamp bookkeeping', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing
        ..saveCustomStamp(approved)
        ..saveCustomStamp(draft);
      expect(editing.customStamps, [approved, draft]);

      editing.activeStamp = draft;
      editing.removeCustomStamp(draft);
      expect(editing.customStamps, [approved]);
      // deleting the active stamp falls back to the classic flow
      expect(editing.activeStamp, isNull);
    });

    test('replace keeps saved stamp metadata and the active selection', () {
      const paid = PdfCustomStamp(
        text: 'PAID',
        color: 0xC03030,
        type: 'Approval',
        tags: ['audit'],
      );
      const reviewed = PdfCustomStamp(
        text: 'REVIEWED',
        color: 0x2E7D32,
        type: 'Approval',
        tags: ['audit'],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..saveCustomStamp(paid)
        ..activeStamp = paid;
      addTearDown(editing.dispose);

      expect(editing.replaceCustomStamp(paid, reviewed), isTrue);
      expect(editing.savedCustomStamps, [reviewed]);
      expect(editing.activeStamp, reviewed);
      expect(editing.replaceCustomStamp(draft, reviewed), isFalse);
    });

    test('combines host-supplied stamps with saved stamps', () {
      const audit = PdfCustomStamp(
        text: 'AUDIT',
        color: 0x1A3E8C,
        type: 'Audit',
        tags: ['external'],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..providedCustomStamps = const [audit]
        ..saveCustomStamp(approved);

      expect(editing.customStamps, [audit, approved]);
      expect(editing.savedCustomStamps, [approved]);
      expect(editing.isSavedCustomStamp(audit), isFalse);
      expect(editing.isSavedCustomStamp(approved), isTrue);

      editing.activeStamp = audit;
      editing.providedCustomStamps = const [];
      expect(editing.activeStamp, isNull);
      expect(editing.customStamps, [approved]);
    });

    test('placeStamp writes custom stamp metadata onto text stamps', () {
      const audit = PdfCustomStamp(
        text: 'AUDIT',
        color: 0x1A3E8C,
        type: 'Audit',
        tags: ['external', 'field'],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = audit;

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.stampType, 'Audit');
      expect(stamp.stampTags, ['external', 'field']);
    });

    test('placeStamp centers an auto-sized Stamp annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = approved;
      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'APPROVED');
      expect(stamp.color, 0x2E7D32);
      expect(stamp.rect.height, moreOrLessEquals(40));
      expect((stamp.rect.left + stamp.rect.right) / 2, moreOrLessEquals(300));
      expect((stamp.rect.bottom + stamp.rect.top) / 2, moreOrLessEquals(400));
      // wide enough for the caption, not absurdly so
      expect(stamp.rect.width, greaterThan(80));
      expect(stamp.rect.width, lessThan(250));
    });

    test('placeStamp compiles editable templates into one Stamp annotation',
        () {
      final template = PdfStampTemplate.text('REVIEWED', 0x1A3E8C);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
            text: 'REVIEWED', color: 0x1A3E8C, template: template);
      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'REVIEWED');
      expect(stamp.rect.height, moreOrLessEquals(96));
      expect(stamp.rect.width, moreOrLessEquals(240));
      final content = appearanceText(editing);
      expect(content, contains('(REVIEWED) Tj'));
    });

    test('placeStamp uses a template stamp size, not just its aspect ratio',
        () {
      PdfStampTemplate square(double size) => PdfStampTemplate(
            width: size,
            height: size,
            components: [
              PdfStampTemplateComponent.rectangle(
                x: 0,
                y: 0,
                width: size,
                height: size,
                color: 0x2E7D32,
                strokeWidth: 2,
              ),
            ],
          );

      final small = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
          text: 'SMALL',
          color: 0x2E7D32,
          template: square(220),
        );
      final large = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
          text: 'LARGE',
          color: 0x2E7D32,
          template: square(400),
        );

      expect(small.placeStamp(0, 300, 400), isTrue);
      expect(large.placeStamp(0, 300, 400), isTrue);

      expect(small.document.page(0).annotations.single.rect.width,
          moreOrLessEquals(220));
      expect(small.document.page(0).annotations.single.rect.height,
          moreOrLessEquals(220));
      expect(large.document.page(0).annotations.single.rect.width,
          moreOrLessEquals(400));
      expect(large.document.page(0).annotations.single.rect.height,
          moreOrLessEquals(400));
    });

    test('placeStamp compiles circle components into the appearance', () {
      final template = PdfStampTemplate(
        width: 100,
        height: 100,
        components: [
          PdfStampTemplateComponent.ellipse(
            x: 20,
            y: 20,
            width: 60,
            height: 60,
            color: 0x2E7D32,
            strokeWidth: 3,
          ),
        ],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
          text: 'Circle',
          color: 0x2E7D32,
          template: template,
        );

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'Circle');
      expect(stamp.rect.width, moreOrLessEquals(stamp.rect.height));
      final content = appearanceText(editing);
      expect(content, contains(' c'));
      expect(content, contains('S'));
    });

    test('placeStamp resolves built-in and custom template fields', () {
      final template = PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.text(
            x: 8,
            y: 30,
            width: 224,
            height: 36,
            text: '{{date}} {{time}} {{username}} {{project}}',
            color: 0x1A3E8C,
            fontSize: 22,
          ),
        ],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.author = 'Comment Author'
        ..stampTemplateClock = (() => DateTime(2026, 7, 4, 9, 5))
        ..stampTemplateValues = {
          'username': 'Ben',
          'project': 'AMT-SP',
        }
        ..activeStamp = PdfCustomStamp(
          text: 'Issued {{date}} for {{project}}',
          color: 0x1A3E8C,
          template: template,
        );

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.contents, 'Issued 2026-07-04 for AMT-SP');
      expect(appearanceText(editing),
          contains('(2026-07-04 09:05 Ben AMT-SP) Tj'));
    });

    test('placeStamp uses the selected date and time formats', () {
      SharedPreferences.setMockInitialValues({});
      final template = PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.text(
            x: 8,
            y: 30,
            width: 224,
            height: 36,
            text: '{{date}} {{time}}',
            color: 0x1A3E8C,
            fontSize: 22,
          ),
        ],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..stampTemplateClock = (() => DateTime(2026, 7, 4, 9, 5, 6))
        ..preferences.stampDateFormat = PdfStampDateFormat.monthNameDayYear
        ..preferences.stampTimeFormat = PdfStampTimeFormat.twelveHourSeconds
        ..activeStamp = PdfCustomStamp(
          text: '{{datetime}}',
          color: 0x1A3E8C,
          template: template,
        );

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.contents, 'Jul 4, 2026 9:05:06 AM');
      expect(appearanceText(editing), contains('(Jul 4, 2026 9:05:06 AM) Tj'));
    });

    test('placeStamp compiles template fonts and images into the appearance',
        () {
      final template = PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.image(
            x: 16,
            y: 18,
            width: 42,
            height: 42,
            imageBytes: _png,
          ),
          PdfStampTemplateComponent.text(
            x: 64,
            y: 30,
            width: 160,
            height: 28,
            text: 'TESTED',
            color: 0x1A3E8C,
            font: PdfStandardFont.timesBold,
          ),
        ],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
          text: 'TESTED',
          color: 0x1A3E8C,
          template: template,
          type: 'Tested',
          tags: const ['qa'],
        );

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.stampType, 'Tested');
      expect(stamp.stampTags, ['qa']);
      final content = appearanceText(editing);
      expect(content, contains('/Img0 Do'));
      expect(content, contains('/TimesBold'));
      expect(content, contains('(TESTED) Tj'));
    });

    test('placeStamp compiles hand signatures into the appearance', () {
      final template = PdfStampTemplate(
        width: 200,
        height: 80,
        components: [
          PdfStampTemplateComponent.signature(
            x: 20,
            y: 20,
            width: 160,
            height: 40,
            strokes: const [
              [(0.0, 0.8), (0.5, 0.2), (1.0, 0.7)],
            ],
            pressures: const [
              [0.0, 0.5, 1.0],
            ],
            color: 0x1A3E8C,
            strokeWidth: 3,
          ),
        ],
      );
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = PdfCustomStamp(
          text: 'Signed',
          color: 0x1A3E8C,
          template: template,
        );

      expect(editing.placeStamp(0, 300, 400), isTrue);

      final appearance = appearanceText(editing);
      expect(appearance, contains('0.102 0.243 0.549 RG'));
      expect(appearance, contains('1 J'));
      expect(appearance, contains('2.1 w'));
      expect(appearance, contains('3.9 w'));
      expect(appearance, contains(' c'));
      expect(editing.document.page(0).annotations.single.contents, 'Signed');
    });

    test('clamps so the whole stamp stays on the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = approved;
      final box = editing.document.page(0).cropBox;
      expect(editing.placeStamp(0, box.right, box.top), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.rect.right, lessThanOrEqualTo(box.right + 0.01));
      expect(stamp.rect.top, lessThanOrEqualTo(box.top + 0.01));
    });

    test('changing colour keeps and recolours the active saved stamp', () {
      SharedPreferences.setMockInitialValues({});
      final template = PdfStampTemplate.text('PAID', 0xC03030);
      final paid =
          PdfCustomStamp(text: 'PAID', color: 0xC03030, template: template);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..saveCustomStamp(paid)
        ..activeStamp = paid
        ..tool = PdfEditTool.stamp;
      addTearDown(editing.dispose);

      editing.color = const Color(0xFF43A047);

      final active = editing.activeStamp;
      expect(active, isNotNull);
      expect(active!.text, 'PAID');
      expect(active.color, 0x43A047);
      expect(editing.savedCustomStamps.single, active);
      expect(
          active.template!.components
              .where((c) => c.type != PdfStampTemplateComponentType.image)
              .map((c) => c.color),
          everyElement(0x43A047));

      editing.finishColorPick(const Color(0xFF1E88E5));
      expect(editing.activeStamp!.text, 'PAID');
      expect(editing.activeStamp!.color, 0x1E88E5);
      expect(editing.savedCustomStamps.single, editing.activeStamp);

      expect(editing.placeStamp(0, 300, 400), isTrue);
      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.contents, 'PAID');
      expect(stamp.color, 0x1E88E5);
      expect(appearanceText(editing), contains('(PAID) Tj'));
    });

    test('without an active stamp nothing happens', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.placeStamp(0, 300, 400), isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });

    test('placeTextStamp drops a default-sized stamp without an active stamp',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF1565C0);
      expect(editing.placeTextStamp(0, 300, 400, 'REVIEWED'), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'REVIEWED');
      // no colour given, so it follows the selected toolbar colour
      expect(stamp.color, 0x1565C0);
      expect(stamp.rect.height, moreOrLessEquals(40));
      expect((stamp.rect.left + stamp.rect.right) / 2, moreOrLessEquals(300));
      expect((stamp.rect.bottom + stamp.rect.top) / 2, moreOrLessEquals(400));
    });

    test('placeTextStamp on a rotated page uses visual orientation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF1565C0);
      addTearDown(editing.dispose);
      expect(editing.rotatePages([0], 90), isTrue);
      expect(editing.placeTextStamp(0, 300, 400, 'REVIEWED'), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.rect.width, moreOrLessEquals(40));
      expect(stamp.rect.height, greaterThan(80));
      final content = appearanceText(editing);
      expect(content, contains('0 1 -1 0'));
      expect(content, contains('(REVIEWED) Tj'));
    });
  });

  group('stamp tool in the viewer', () {
    testWidgets('create a stamp in the picker, then tap to place it',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      // the Stamp tool lives in the Insert group's strip
      final insertChip = find.byKey(const ValueKey('pdf-group-insert'));
      await tester.scrollUntilVisible(insertChip, 80,
          scrollable: dockScrollable);
      await tester.tap(insertChip);
      await tester.pump();
      await tester.scrollUntilVisible(find.byTooltip('Stamp (S)'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Stamp (S)'));
      await tester.pumpAndSettle();
      expect(editing.tool, PdfEditTool.stamp);
      expect(
          find.byKey(const ValueKey('pdf-stamp-menu-preview')), findsOneWidget);
      expect(find.byTooltip('Custom stamps…'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-menu-manage')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfStampPickerDialog), findsOneWidget);

      await tester.tap(find.text('New stamp…'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-stamp-text')), 'PAID');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // saving selects the new stamp and closes both dialogs
      expect(find.byType(PdfStampPickerDialog), findsNothing);
      expect(editing.customStamps.single.text, 'PAID');
      expect(editing.customStamps.single.template, isNotNull);
      expect(editing.activeStamp, editing.customStamps.single);

      // tap the page; the double-tap recognizer holds taps ~300ms
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'PAID');
      expect(appearanceText(editing), contains('(PAID) Tj'));
    });

    testWidgets('stamp tool popup selects custom stamps', (tester) async {
      const audit = PdfCustomStamp(
        text: 'AUDIT',
        color: 0x1A3E8C,
        type: 'Audit',
        tags: ['external'],
      );
      const paid = PdfCustomStamp(text: 'PAID', color: 0x2E7D32);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..providedCustomStamps = const [audit]
        ..saveCustomStamp(paid);
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('pdf-group-insert')), 80,
          scrollable: dockScrollable);
      await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
      await tester.pump();
      await tester.scrollUntilVisible(find.byTooltip('Stamp (S)'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Stamp (S)'));
      await tester.pumpAndSettle();

      expect(editing.tool, PdfEditTool.stamp);
      expect(
          find.byKey(const ValueKey('pdf-stamp-menu-preview')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-stamp-menu-classic')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-stamp-menu-custom-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-stamp-menu-custom-1')),
          findsOneWidget);
      expect(find.text('AUDIT'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-menu-custom-1')));
      await tester.pumpAndSettle();

      expect(editing.activeStamp, paid);
      expect(
          find.byKey(const ValueKey('pdf-stamp-menu-preview')), findsNothing);
      expect(find.byTooltip('Custom stamps…'), findsNothing);
    });

    testWidgets('stamp taps paint a preview before the PDF edit commits',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      const stamp = PdfCustomStamp(text: 'APPROVED', color: 0x2E7D32);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = stamp
        ..tool = PdfEditTool.stamp;
      addTearDown(editing.dispose);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
                rasterCurrent: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      await tester.tapAt(origin + local(240, 420),
          kind: PointerDeviceKind.mouse);

      // The tap handler has installed the preview and yielded until the next
      // frame, so no synchronous save has blocked the visual response.
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.pump();
      final after = overlayPainter(tester).afterStamp;
      expect(after, isNotNull);
      expect(after.text, 'APPROVED');
      expect(after.color, const Color(0xFF2E7D32));

      await tester.pump();
      expect(editing.document.page(0).annotations.single.contents, 'APPROVED');
    });

    testWidgets('stamp hover previews the active stamp without committing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final template = PdfStampTemplate.text('PAID', 0x2E7D32);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp =
            PdfCustomStamp(text: 'PAID', color: 0x2E7D32, template: template)
        ..tool = PdfEditTool.stamp;
      addTearDown(editing.dispose);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
                rasterCurrent: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: origin + local(250, 430));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(origin + local(300, 400));
      await tester.pump();

      expect(editing.document.page(0).annotations, isEmpty);
      final preview = cursorPainter(tester).stampPreview;
      expect(preview, isNotNull);
      expect(preview.text, 'PAID');
      expect(preview.template, isNotNull);
      expect(preview.rect.center.dx, moreOrLessEquals(local(300, 400).dx));
      expect(preview.rect.center.dy, moreOrLessEquals(local(300, 400).dy));
      expect(preview.rect.width, moreOrLessEquals(template.width * 0.5));
      expect(preview.rect.height, moreOrLessEquals(template.height * 0.5));

      await mouse.moveTo(origin + const Offset(-20, -20));
      await tester.pump();
      expect(cursorPainter(tester).stampPreview, isNull);
    });

    testWidgets('stamp hover previews a TEXT placeholder without an active stamp',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.stamp;
      addTearDown(editing.dispose);
      expect(editing.activeStamp, isNull);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
                rasterCurrent: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: origin + local(250, 430));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(origin + local(300, 400));
      await tester.pump();

      // hovering shows the placeholder; nothing is committed until a click
      // prompts for the real caption.
      expect(editing.document.page(0).annotations, isEmpty);
      final preview = cursorPainter(tester).stampPreview;
      expect(preview, isNotNull);
      expect(preview.text, 'TEXT');
      expect(preview.rect.center.dx, moreOrLessEquals(local(300, 400).dx));
      expect(preview.rect.center.dy, moreOrLessEquals(local(300, 400).dy));

      await mouse.moveTo(origin + const Offset(-20, -20));
      await tester.pump();
      expect(cursorPainter(tester).stampPreview, isNull);
    });

    testWidgets('adding a stamp keeps existing annotations painted',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFFE53935)
        ..preferences.strokeWidth = 12
        ..addRectangle(0, const PdfRect(120, 650, 180, 720));
      addTearDown(editing.dispose);
      const boundaryKey = ValueKey('annotation-layer-capture');

      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 306,
              height: 396,
              child: ListenableBuilder(
                listenable: editing,
                builder: (context, _) => PdfViewer(
                  initialFit: PdfViewerFit.width,
                  document: editing.document,
                  editing: editing,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final boundaryOrigin = tester.getTopLeft(find.byKey(boundaryKey));
      final pageRect = tester.getRect(find.byType(RawImage).first);
      Offset samplePoint(double x, double y) {
        final page = editing.document.page(0);
        final box = page.cropBox;
        return pageRect.topLeft -
            boundaryOrigin +
            Offset((x - box.left) * pageRect.width / box.width,
                (box.top - y) * pageRect.height / box.height);
      }

      final sample = samplePoint(123, 685);
      var capture = await captureBoundary(tester, boundaryKey);
      var (r, g, b, _) = pixelAt(
          capture.pixels, capture.width, sample.dx.round(), sample.dy.round());
      expect(r, greaterThan(180));
      expect(g, lessThan(100));
      expect(b, lessThan(100));

      editing.placeTextStamp(0, 300, 400, 'NEW');
      await tester.pump();

      capture = await captureBoundary(tester, boundaryKey);
      (r, g, b, _) = pixelAt(
          capture.pixels, capture.width, sample.dx.round(), sample.dy.round());
      expect(r, greaterThan(180),
          reason: 'the existing annotation layer must stay up while the '
              'new revision records its annotation appearances');
      expect(g, lessThan(100));
      expect(b, lessThan(100));
    });

    testWidgets('template stamp taps paint the template before the PDF commit',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final template = PdfStampTemplate.text('PAID', 0x2E7D32);
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp =
            PdfCustomStamp(text: 'PAID', color: 0x2E7D32, template: template)
        ..tool = PdfEditTool.stamp;
      addTearDown(editing.dispose);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
                rasterCurrent: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      await tester.tapAt(origin + local(240, 420),
          kind: PointerDeviceKind.mouse);

      expect(editing.document.page(0).annotations, isEmpty);

      await tester.pump();
      final after = overlayPainter(tester).afterStamp;
      expect(after, isNotNull);
      expect(after.text, 'PAID');
      expect(after.template, template);
      expect(after.color, const Color(0xFF2E7D32));

      await tester.pump();
      expect(editing.document.page(0).annotations.single.contents, 'PAID');
    });

    testWidgets('the stamp editor previews the stamp above the text field',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final preview = find.byKey(const ValueKey('pdf-stamp-template-canvas'));
      final textField = find.byKey(const ValueKey('pdf-stamp-text'));
      final widthField = find.byKey(const ValueKey('pdf-stamp-width'));
      final heightField = find.byKey(const ValueKey('pdf-stamp-height'));
      expect(preview, findsOneWidget);
      expect(tester.getBottomLeft(preview).dy,
          lessThan(tester.getTopLeft(textField).dy));

      await tester.enterText(widthField, '400');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(heightField, '400');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(textField, 'PAID');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.text, 'PAID');
      expect(saved!.template, isNotNull);
      expect(saved!.template!.width, 400);
      expect(saved!.template!.height, 400);
      expect(
          saved!.template!.components
              .where((c) =>
                  c.type == PdfStampTemplateComponentType.text &&
                  c.text == 'PAID')
              .length,
          1);
    });

    testWidgets('stamp editor can pick a custom color', (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-color-custom')));
      await tester.pumpAndSettle();
      final hexField = find.byKey(const ValueKey('pdf-color-hex'));
      await tester.enterText(hexField, '7B1FA2');
      await tester.pump();
      expect(tester.widget<TextField>(hexField).controller!.text, '7B1FA2');
      await tester.tap(find.widgetWithText(FilledButton, 'OK').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      final text = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.text);
      expect(text.color, 0x7B1FA2);
    });

    testWidgets('stamp editor inserts template fields into text components',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context,
                    fields: const ['date', 'project']);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-field-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-stamp-field-date')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final text = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.text);
      expect(text.text, contains('{{date}}'));
    });

    testWidgets('stamp editor changes size, font, and adds image components',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context,
                    imagePicker: (_) async => _png);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('pdf-stamp-width')), '300');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-stamp-height')), '120');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-font-menu')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('pdf-stamp-font-courierBold')));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const ValueKey('pdf-stamp-add-image')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-stamp-add-image')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final template = saved!.template!;
      expect(template.width, 300);
      expect(template.height, 120);
      final text = template.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.text);
      expect(text.font, PdfStandardFont.courierBold);
      expect(
          template.components
              .where((c) =>
                  c.type == PdfStampTemplateComponentType.image &&
                  c.imageBytes != null)
              .length,
          1);
    });

    testWidgets('stamp editor adds circle components', (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const ValueKey('pdf-stamp-add-circle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-stamp-add-circle')));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final circle = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.ellipse);
      expect(circle.width, circle.height);
      expect(circle.width, greaterThan(16));
      expect(circle.color, 0xC03030);
    });

    testWidgets('stamp editor adds hand signature components', (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const ValueKey('pdf-stamp-add-signature')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-stamp-add-signature')));
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('pdf-signature-pad'));
      await tester.timedDrag(
          pad, const Offset(90, 24), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final signature = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.signature);
      expect(signature.strokes, hasLength(1));
      expect(signature.strokes.single.length, greaterThanOrEqualTo(2));
      expect(signature.color, 0x000000);
      expect(signature.width, greaterThan(0));
      expect(signature.height, greaterThan(0));
    });

    testWidgets('stamp editor components can be moved and resized',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('pdf-stamp-template-canvas'));
      final rect = tester.getRect(canvas);
      final scale = rect.width / 240;
      final origin = rect.topLeft;
      final move = await tester.startGesture(
          origin + Offset(120 * scale, 48 * scale),
          kind: PointerDeviceKind.mouse);
      await move.moveBy(const Offset(18, 12));
      await move.up();
      await tester.pump();
      final resize = await tester.startGesture(
          origin + Offset(232 * scale, 75 * scale),
          kind: PointerDeviceKind.mouse);
      await resize.moveBy(const Offset(24, 12));
      await resize.up();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final text = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.text);
      expect(text.x, greaterThan(20));
      expect(text.y, greaterThan(30));
      expect(text.width, greaterThan(200));
      expect(text.height, greaterThan(36));
    });

    testWidgets('stamp editor resizes from any corner with a forgiving target',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('pdf-stamp-template-canvas'));
      final rect = tester.getRect(canvas);
      final scale = rect.width / 240;
      final origin = rect.topLeft;
      // The default text component's top-left corner is at (20, 30). Grab it a
      // few logical pixels off-center - the old single bottom-right handle
      // could not do this, and the generous hit radius forgives the miss - then
      // drag up and left so that corner (and only that corner) follows.
      final resize = await tester.startGesture(
          origin + Offset(20 * scale + 5, 30 * scale + 5),
          kind: PointerDeviceKind.mouse);
      await resize.moveBy(const Offset(-16, -10));
      await resize.up();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final text = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.text);
      // Top-left corner moved out, so the origin shrank and the box grew.
      expect(text.x, lessThan(20));
      expect(text.y, lessThan(30));
      expect(text.width, greaterThan(200));
      expect(text.height, greaterThan(36));
    });

    testWidgets('stamp editor taps to reselect the component being sized',
        (tester) async {
      PdfCustomStamp? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                saved = await showPdfStampEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final canvas = find.byKey(const ValueKey('pdf-stamp-template-canvas'));
      final rect = tester.getRect(canvas);
      final scale = rect.width / 240;
      final origin = rect.topLeft;
      // Tap the empty strip above the components to clear the initial text
      // selection, then press-drag there: with nothing selected the canvas has
      // no handles, so the gesture is a no-op instead of resizing.
      await tester.tapAt(origin + Offset(2 * scale, 2 * scale));
      await tester.pump();
      final empty = await tester.startGesture(origin + Offset(2 * scale, 2 * scale),
          kind: PointerDeviceKind.mouse);
      await empty.moveBy(const Offset(6, 6));
      await empty.up();
      await tester.pump();

      // Tap the border rectangle - below the caption - to select it, then drag
      // its bottom-right corner outward to grow it.
      await tester.tapAt(origin + Offset(120 * scale, 22 * scale));
      await tester.pump();
      final resize = await tester.startGesture(
          origin + Offset(234 * scale, 80 * scale),
          kind: PointerDeviceKind.mouse);
      await resize.moveBy(const Offset(8, 6));
      await resize.up();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final border = saved!.template!.components
          .firstWhere((c) => c.type == PdfStampTemplateComponentType.rectangle);
      expect(border.width, greaterThan(228));
      expect(border.height, greaterThan(64));
    });

    testWidgets('the picker lists and deletes saved stamps', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      const paid = PdfCustomStamp(text: 'PAID', color: 0xC03030);
      editing
        ..saveCustomStamp(paid)
        ..activeStamp = paid;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(context, controller: editing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfStampPreview), findsOneWidget);

      await tester.tap(find.byTooltip('Delete stamp'));
      await tester.pumpAndSettle();
      expect(editing.customStamps, isEmpty);
      expect(find.byType(PdfStampPreview), findsNothing);
    });

    testWidgets('the picker edits saved stamps', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final paid = PdfCustomStamp(
        text: 'PAID',
        color: 0xC03030,
        template: PdfStampTemplate.text('PAID', 0xC03030),
        type: 'Approval',
        tags: const ['audit'],
      );
      editing
        ..saveCustomStamp(paid)
        ..activeStamp = paid;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(context, controller: editing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit stamp'));
      await tester.pumpAndSettle();
      expect(find.text('Edit stamp'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-stamp-text')), 'REVIEWED');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfStampPickerDialog), findsOneWidget);
      expect(editing.savedCustomStamps.single.text, 'REVIEWED');
      expect(editing.savedCustomStamps.single.type, 'Approval');
      expect(editing.savedCustomStamps.single.tags, ['audit']);
      expect(editing.activeStamp, editing.savedCustomStamps.single);
      expect(find.byType(PdfStampPreview), findsOneWidget);
    });

    testWidgets('the picker imports and exports saved stamps', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      const paid = PdfCustomStamp(text: 'PAID', color: 0xC03030);
      const audit = PdfCustomStamp(
        text: 'AUDIT',
        color: 0x1A3E8C,
        type: 'Audit',
        tags: ['external'],
      );
      editing.saveCustomStamp(paid);

      List<PdfCustomStamp>? exported;
      var importCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(
                context,
                controller: editing,
                onExportStamps: (context, stamps) async {
                  exported = stamps;
                },
                onImportStamps: (context) async {
                  importCalls++;
                  return const [audit, paid];
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-export')));
      await tester.pump();
      expect(exported, [paid]);

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-import')));
      await tester.pump();
      expect(importCalls, 1);
      expect(editing.savedCustomStamps, [paid, audit]);
      expect(editing.activeStamp, audit);
    });

    testWidgets('the picker disables export with no saved stamps',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(
                context,
                controller: editing,
                onExportStamps: (context, stamps) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final export = tester
          .widget<TextButton>(find.byKey(const ValueKey('pdf-stamp-export')));
      expect(export.onPressed, isNull);
    });

    testWidgets('the picker changes date and time formats', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..stampTemplateClock = (() => DateTime(2026, 7, 6, 17, 5, 6));
      addTearDown(editing.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(context, controller: editing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('2026-07-06'), findsOneWidget);
      expect(find.text('17:05 (24 hr)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-date-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('06/07/2026').last);
      await tester.pumpAndSettle();
      expect(editing.preferences.stampDateFormat, PdfStampDateFormat.dayMonthYear);

      await tester.tap(find.byKey(const ValueKey('pdf-stamp-time-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17:05:06 (24 hr)').last);
      await tester.pumpAndSettle();
      expect(editing.preferences.stampTimeFormat, PdfStampTimeFormat.twentyFourHourSeconds);
    });

    testWidgets('the picker lists app-supplied stamps without delete controls',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..providedCustomStamps = const [
          PdfCustomStamp(
            text: 'AUDIT',
            color: 0x1A3E8C,
            type: 'Audit',
            tags: ['external'],
          ),
        ];
      addTearDown(editing.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(context, controller: editing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfStampPreview), findsOneWidget);
      expect(find.text('Audit · external'), findsOneWidget);
      expect(find.byTooltip('Edit stamp'), findsNothing);
      expect(find.byTooltip('Delete stamp'), findsNothing);
    });
  });

  group('localized stamp date/time formatting', () {
    setUpAll(initializeDateFormatting);

    final noon = DateTime(2026, 7, 4, 9, 5, 6);

    test('defaults to English when no locale is given', () {
      // Backward compatibility: hosts that never register the localization
      // delegate (localeName == null) keep the bundled English shapes.
      expect(PdfStampDateFormat.monthNameDayYear.format(noon), 'Jul 4, 2026');
      expect(PdfStampDateFormat.dayMonthNameYear.format(noon), '4 Jul 2026');
      expect(PdfStampTimeFormat.twelveHour.format(noon), '9:05 AM');
    });

    test('localizes the spelled-out month name', () {
      expect(
        PdfStampDateFormat.monthNameDayYear.format(noon, localeName: 'ja'),
        contains('7月'),
      );
      expect(
        PdfStampDateFormat.dayMonthNameYear.format(noon, localeName: 'ja'),
        contains('7月'),
      );
      // English stays English even through the intl path.
      expect(
        PdfStampDateFormat.monthNameDayYear.format(noon, localeName: 'en'),
        'Jul 4, 2026',
      );
    });

    test('numeric date shapes stay ASCII regardless of locale', () {
      // iso is a fixed technical format; the slash shapes carry no month name.
      expect(
        PdfStampDateFormat.iso.format(noon, localeName: 'ja'),
        '2026-07-04',
      );
      expect(
        PdfStampDateFormat.dayMonthYear.format(noon, localeName: 'ar'),
        '04/07/2026',
      );
    });

    test('localizes the AM/PM marker on 12-hour times', () {
      final morning = PdfStampTimeFormat.twelveHour
          .format(DateTime(2026, 7, 4, 9, 5), localeName: 'ja');
      expect(morning, startsWith('9:05 '));
      expect(morning, isNot(contains('AM')));
      expect(morning, contains('午前'));
      // 24-hour shapes carry no marker and are locale-independent.
      expect(
        PdfStampTimeFormat.twentyFourHour.format(noon, localeName: 'ja'),
        '09:05',
      );
    });

    test('falls back to English for an unknown locale instead of throwing', () {
      expect(
        () => PdfStampDateFormat.monthNameDayYear
            .format(noon, localeName: 'zzz-not-a-locale'),
        returnsNormally,
      );
      expect(
        PdfStampDateFormat.monthNameDayYear
            .format(noon, localeName: 'zzz-not-a-locale'),
        'Jul 4, 2026',
      );
    });

    test('controller resolves stamp fields through its uiLocale', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..stampTemplateClock = (() => noon)
        ..preferences.stampDateFormat = PdfStampDateFormat.monthNameDayYear
        ..uiLocale = const ui.Locale('ja');
      addTearDown(editing.dispose);

      expect(editing.resolvedStampTemplateValues['date'], contains('7月'));

      // Clearing the override falls back to English (no persisted preference).
      editing.uiLocale = null;
      expect(editing.resolvedStampTemplateValues['date'], 'Jul 4, 2026');
    });
  });
}

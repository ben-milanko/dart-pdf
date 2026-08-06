import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart'
    show CupertinoTextSelectionToolbar, CupertinoTextSelectionToolbarButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_form_layer.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Form fields fill in directly in reading / default mode - no editing
/// tool armed - both in the editor (an [editing] controller) and in the
/// read-only reader (a standalone [PdfViewer.formController]).
void main() {
  // 800px viewport over a 612pt page, fit to width (the same math the
  // form-tool tests use, so field view coords line up)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  /// A single tap; touch taps resolve only after the double-tap timeout.
  Future<void> tap(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(milliseconds: 300));

  /// Pumps a viewer with an editing controller but no tool armed (the
  /// editor's default mode), or - when [asReader] - only a
  /// [formController], the way the read-only reader drives it.
  Future<PdfEditingController> pumpViewer(
    WidgetTester tester, {
    bool asReader = false,
    bool interactiveForms = true,
    PdfEditTool? tool,
    double? zoom,
    PdfAnnotationTapHandler? onAnnotationTap,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final session = PdfEditingController(buildAcroFormPdf());
    final viewer = PdfViewerController();
    addTearDown(session.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: session.document,
            controller: viewer,
            editing: asReader ? null : session,
            formController: asReader ? session : null,
            interactiveForms: interactiveForms,
            onAnnotationTap: onAnnotationTap,
          ),
        ),
      ),
    ));
    if (tool != null) session.tool = tool;
    await tester.pump();
    if (zoom != null) {
      viewer.setZoom(zoom);
      await tester.pump();
    }
    return session;
  }

  group('interactive forms in default / reader mode', () {
    testWidgets('text field fills with no tool armed (editor default mode)',
        (tester) async {
      final session = await pumpViewer(tester);
      // no tool armed: the form layer mounts on its own
      expect(session.tool, isNull);

      await tap(tester, view(186, 712));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);
      expect(session.isEditingText, isTrue);
      expect(tester.widget<TextField>(editor).controller!.text, 'prefilled');

      await tester.enterText(editor, 'Jane');
      await tap(tester, view(450, 620)); // outside the field: commit

      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(session.isEditingText, isFalse);
      expect(session.acroForm!.fieldNamed('name')!.value, 'Jane');
      await settle(tester);
    });

    testWidgets('text field fills in the reader (formController, no editing)',
        (tester) async {
      final session = await pumpViewer(tester, asReader: true);

      await tap(tester, view(186, 712));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);
      await tester.enterText(editor, 'Reader');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(session.acroForm!.fieldNamed('name')!.value, 'Reader');
      await settle(tester);
    });

    testWidgets('text field cursor counter-scales while zoomed',
        (tester) async {
      final session = await pumpViewer(tester, zoom: 2 * scale);

      await tap(tester, view(186, 712));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);
      final field = tester.widget<TextField>(editor);
      expect(field.cursorWidth, closeTo(1, 0.01));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(session.isEditingText, isFalse);
      await settle(tester);
    });

    testWidgets('the long-press selection menu lands on a zoomed field',
        (tester) async {
      // Above 100% the field sits under the viewer's zoom transform, which
      // Flutter's selection toolbar inherits through its
      // CompositedTransformFollower - it used to throw the menu hundreds of
      // pixels off the field (off-screen on a phone), so a long press in a
      // zoomed field looked dead. See editing_text_menu.dart.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'pasteable'};
        }
        if (call.method == 'Clipboard.hasStrings') {
          return <String, dynamic>{'value': true};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      // the reader's own inline editor (no editing controller), zoomed
      // enough that the transform, not the layout, carries the zoom
      await pumpViewer(tester, asReader: true, zoom: 1.5 * scale);
      // the multi-line 'address' field, which stays mid-viewport at 1.5x
      await tap(tester, const Offset(164, 147));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);

      // type first: an empty field parks its caret at the left edge, which
      // this zoom has pushed off-screen, and a menu clamped by the screen
      // edge can't say anything about where it was anchored
      await tester.enterText(editor, 'address line one');
      await tester.pump();
      final field = tester.getRect(editor);
      final press = Offset(250, field.top + 20);
      final gesture =
          await tester.startGesture(press, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final buttons = find.descendant(
          of: find.byType(CupertinoTextSelectionToolbar),
          matching: find.byType(CupertinoTextSelectionToolbarButton));
      expect(buttons, findsWidgets);
      final menu = List.generate(buttons.evaluate().length, (i) => i)
          .map((i) => tester.getRect(buttons.at(i)))
          .reduce((a, b) => a.expandToInclude(b));
      final anchor = tester
          .state<EditableTextState>(find.byType(EditableText))
          .contextMenuAnchors
          .primaryAnchor;
      // centred on the anchor the framework measured (within the menu's own
      // padding), above it, and on screen
      expect(menu.center.dx, closeTo(anchor.dx, 12), reason: 'menu $menu');
      expect(menu.bottom, lessThan(anchor.dy));
      final screen =
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(screen.contains(menu.topLeft), isTrue, reason: 'menu $menu');
      expect(screen.contains(menu.bottomRight), isTrue, reason: 'menu $menu');

      debugDefaultTargetPlatformOverride = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await settle(tester);
    });

    testWidgets('check box and radio toggle on a plain tap', (tester) async {
      final session = await pumpViewer(tester);

      await tap(tester, view(82, 550)); // the agree check box
      expect(session.acroForm!.fieldNamed('agree')!.isChecked, isTrue);
      await tap(tester, view(82, 550));
      expect(session.acroForm!.fieldNamed('agree')!.isChecked, isFalse);

      await tap(tester, view(130, 510)); // the /Blue radio kid
      expect(session.acroForm!.fieldNamed('color')!.value, 'Blue');
      await settle(tester);
    });

    testWidgets('onAnnotationTap fires for form field widgets', (tester) async {
      final taps = <PdfAnnotationTapDetails>[];
      final session = await pumpViewer(tester, onAnnotationTap: taps.add);

      await tap(tester, view(82, 550)); // the agree check box

      expect(taps, hasLength(1));
      expect(taps.single.pageIndex, 0);
      expect(taps.single.annotation.subtype, 'Widget');
      expect(taps.single.pagePoint.dx, closeTo(82, 0.5));
      expect(taps.single.pagePoint.dy, closeTo(550, 0.5));
      expect(session.acroForm!.fieldNamed('agree')!.isChecked, isTrue);
      await settle(tester);
    });

    testWidgets('drop-down opens a menu and sets the picked option',
        (tester) async {
      final session = await pumpViewer(tester);

      await tap(tester, view(136, 472)); // the size combo box
      await tester.pumpAndSettle(); // the menu's opening animation
      expect(find.byKey(const ValueKey('pdf-form-option-L')), findsOneWidget);

      await tester.tap(find.text('Large'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.acroForm!.fieldNamed('size')!.value, 'L',
          reason: 'the export value is stored');
      await settle(tester);
    });

    testWidgets('read-only fields take no edit', (tester) async {
      final session = await pumpViewer(tester);
      await tap(tester, view(136, 432)); // the read-only serial field
      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(session.isModified, isFalse);
      await settle(tester);
    });

    testWidgets('Escape cancels the inline editor without committing',
        (tester) async {
      final session = await pumpViewer(tester);
      await tap(tester, view(186, 712));
      expect(
          find.byKey(const ValueKey('pdf-form-text-editor')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-form-text-editor')), 'discard me');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(session.acroForm!.fieldNamed('name')!.value, 'prefilled',
          reason: 'cancel keeps the original value');
      expect(session.isModified, isFalse);
      await settle(tester);
    });

    testWidgets('interactiveForms: false leaves fields untouched',
        (tester) async {
      final session = await pumpViewer(tester, interactiveForms: false);
      await tap(tester, view(82, 550)); // would toggle the check box
      expect(session.acroForm!.fieldNamed('agree')!.isChecked, isFalse);
      expect(session.isModified, isFalse);
      await settle(tester);
    });

    testWidgets('a drawing tool suppresses the form layer', (tester) async {
      // with the ink tool armed the page belongs to drawing, not filling:
      // the form layer leaves the tree entirely (a tap there would draw)
      await pumpViewer(tester, tool: PdfEditTool.ink);
      expect(find.byType(FormInteractionLayer), findsNothing);
    });

    testWidgets('the select tool keeps the form layer active', (tester) async {
      final session = await pumpViewer(tester, tool: PdfEditTool.select);
      expect(find.byType(FormInteractionLayer), findsWidgets);
      await tap(tester, view(82, 550));
      expect(session.acroForm!.fieldNamed('agree')!.isChecked, isTrue);
      await settle(tester);
    });
  });

  group('PdfReader form fill', () {
    testWidgets('mounts the form layer and fills, off with fillForms: false',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReader(
            bytes: buildAcroFormPdf(),
            features: const PdfReaderFeatures(headerBar: false),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // the interactive form layer is present in a plain reader
      expect(find.byType(FormInteractionLayer), findsWidgets);
    });

    testWidgets('fillForms: false removes the form layer', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReader(
            bytes: buildAcroFormPdf(),
            features:
                const PdfReaderFeatures(headerBar: false, fillForms: false),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FormInteractionLayer), findsNothing);
    });
  });
}

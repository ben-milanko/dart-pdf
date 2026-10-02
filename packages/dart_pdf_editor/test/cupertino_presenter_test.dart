// PdfCupertinoPresenter (package:dart_pdf_editor/cupertino.dart) under a
// CupertinoApp with no MaterialApp anywhere: every presenter method, driven
// through the editor's own entry points, shows Cupertino UI (or, for colour,
// font and signature, the stock picker on a Cupertino route) and hands its
// answer back to the editor.
//
// Each test runs once for iOS and once for macOS, one platform per test
// (TargetPlatformVariant.only): a fallback ThemeData is cached in a static,
// so a multi-platform variant can pass on the wrong platform's theme.
//
// A recording subclass notes every method it is asked; the last test of
// each group checks that the group drove all of them (run the whole file).

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dart_pdf_editor/cupertino.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show AdaptiveTextSelectionToolbar;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_host.dart';

/// Every [PdfEditorPresenter] method.
const _methods = {
  'dialog',
  'sheet',
  'menu',
  'notice',
  'actionBar',
  'readout',
  'text',
  'styledText',
  'confirm',
  'link',
  'color',
  'font',
  'formChoice',
  'measurementScale',
  'measurementInput',
  'pageRange',
  'splitRanges',
  'signature',
};

/// The Cupertino presenter, noting each method it is asked.
class _Recording extends PdfCupertinoPresenter {
  const _Recording();

  static final calls = <String>{};

  @override
  Future<T?> dialog<T>(BuildContext context, PdfDialogRequest<T> request) {
    calls.add('dialog');
    return super.dialog(context, request);
  }

  @override
  Future<T?> sheet<T>(BuildContext context, PdfSheetRequest<T> request) {
    calls.add('sheet');
    return super.sheet(context, request);
  }

  @override
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) {
    calls.add('menu');
    return super.menu(context, request);
  }

  @override
  bool notice(BuildContext context, PdfEditorNotice notice) {
    calls.add('notice');
    return super.notice(context, notice);
  }

  @override
  Widget actionBar(BuildContext context, PdfActionBarRequest request) {
    calls.add('actionBar');
    return super.actionBar(context, request);
  }

  @override
  Widget readout(BuildContext context, PdfReadoutRequest request) {
    calls.add('readout');
    return super.readout(context, request);
  }

  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) {
    calls.add('text');
    return super.text(context, request);
  }

  @override
  Future<PdfStyledTextEdit?> styledText(
      BuildContext context, PdfStyledTextRequest request) {
    calls.add('styledText');
    return super.styledText(context, request);
  }

  @override
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) {
    calls.add('confirm');
    return super.confirm(context, request);
  }

  @override
  Future<PdfLinkTarget?> link(BuildContext context, PdfLinkRequest request) {
    calls.add('link');
    return super.link(context, request);
  }

  @override
  Future<PdfColorResult?> color(BuildContext context, PdfColorRequest request) {
    calls.add('color');
    return super.color(context, request);
  }

  @override
  Future<PdfFontChoice?> font(BuildContext context, PdfFontRequest request) {
    calls.add('font');
    return super.font(context, request);
  }

  @override
  Future<List<String>?> formChoice(
      BuildContext context, PdfFormChoiceRequest request) {
    calls.add('formChoice');
    return super.formChoice(context, request);
  }

  @override
  Future<PdfMeasurementScale?> measurementScale(
      BuildContext context, PdfMeasurementScaleRequest request) {
    calls.add('measurementScale');
    return super.measurementScale(context, request);
  }

  @override
  Future<PdfMeasurementInput?> measurementInput(
      BuildContext context, PdfMeasurementInputRequest request) {
    calls.add('measurementInput');
    return super.measurementInput(context, request);
  }

  @override
  Future<({int start, int end})?> pageRange(
      BuildContext context, PdfPageRangeRequest request) {
    calls.add('pageRange');
    return super.pageRange(context, request);
  }

  @override
  Future<List<PdfPageRange>?> splitRanges(
      BuildContext context, PdfSplitRangesRequest request) {
    calls.add('splitRanges');
    return super.splitRanges(context, request);
  }

  @override
  Future<PdfInkSignature?> signature(
      BuildContext context, PdfSignatureRequest request) {
    calls.add('signature');
    return super.signature(context, request);
  }
}

// 800×600 view, fit-width: a 612pt page at x 0
const _scale = 800 / 612;
Offset _view(double x, double y) => Offset(x * _scale, (792 - y) * _scale);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    group(platform.name, () {
      setUpAll(_Recording.calls.clear);
      _suite(platform);
      testWidgets('drove every presenter method', (tester) async {
        expect(_Recording.calls, _methods);
      }, variant: TargetPlatformVariant.only(platform));
    });
  }
}

void _suite(TargetPlatform platform) {
  final variant = TargetPlatformVariant.only(platform);
  const presenter = _Recording();

  /// Mounts [child] under a CupertinoApp (no Material anywhere).
  Future<void> pump(WidgetTester tester, Widget child,
          {Size size = const Size(800, 600)}) =>
      pumpPdfHost(tester, child, host: PdfTestHost.cupertino, size: size);

  /// A viewer editing [editing] with the presenter.
  Widget viewer(PdfEditingController editing, PdfViewerController viewer) =>
      ListenableBuilder(
        listenable: editing,
        builder: (context, _) => PdfViewer(
          initialFit: PdfViewerFit.width,
          document: editing.document,
          controller: viewer,
          editing: editing,
          presenter: presenter,
        ),
      );

  (PdfEditingController, PdfViewerController) controllers(Uint8List bytes) {
    final editing = PdfEditingController(bytes);
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    return (editing, viewer);
  }

  /// The route [finder]'s widget is on.
  ModalRoute<Object?>? routeOf(WidgetTester tester, Finder finder) =>
      ModalRoute.of(tester.element(finder));

  Future<void> clearNotices(WidgetTester tester) async {
    // let any toast time out (its timer must not outlive the test)
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  testWidgets('menu is an action sheet; link is an alert with a URL field',
      (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(tester, viewer(editing, controller));
    expectPdfHostPlatform(tester);

    await tester.tapAt(_view(100, 720),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-cupertino-menu')), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    final link = find.byKey(const ValueKey('pdf-text-menu-link'));
    expect(tester.widget(link), isA<CupertinoActionSheetAction>());
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-cupertino-link')), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(routeOf(tester, find.byType(CupertinoAlertDialog)),
        isA<CupertinoDialogRoute<PdfLinkTarget>>());
    await tester.enterText(
        find.byKey(const ValueKey('pdf-link-url')), 'https://example.com');
    await tester.tap(find.byKey(const ValueKey('pdf-link-ok')));
    await tester.pumpAndSettle();

    final links = editing.document
        .page(0)
        .annotations
        .where((a) => a.subtype == 'Link')
        .toList();
    expect(links, hasLength(1));
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('the link prompt targets a page through the segmented control',
      (tester) async {
    late BuildContext context;
    await pump(tester, Builder(builder: (c) {
      context = c;
      return const SizedBox.expand();
    }));
    final answer = presenter.link(
        context, const PdfLinkRequest(pageCount: 5, currentPage: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-link-kind-page')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoTextField>(
                find.byKey(const ValueKey('pdf-link-page')))
            .controller!
            .text,
        '2');
    await tester.enterText(find.byKey(const ValueKey('pdf-link-page')), '9');
    await tester.tap(find.byKey(const ValueKey('pdf-link-ok')));
    await tester.pumpAndSettle();
    expect((await answer)?.page, 4, reason: 'clamped to the last page');
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('flatten notices as a Cupertino toast whose Undo reverts it',
      (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    editing.addRectangle(0, const PdfRect(100, 650, 250, 750));
    final commands =
        PdfEditorCommands(controller: editing, viewerController: controller);
    addTearDown(commands.dispose);
    late BuildContext context;
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: Builder(builder: (c) {
            context = c;
            return const SizedBox.expand();
          }),
        ));

    commands.flatten(context);
    await tester.pump();
    expect(editing.document.page(0).annotations, isEmpty);
    expect(find.byKey(const ValueKey('pdf-cupertino-toast')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-toast-undo')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-cupertino-toast')), findsNothing);
    expect(editing.document.page(0).annotations, hasLength(1));

    // replaceCurrent: a second notice takes the first one's place; one with
    // showClose offers a close button
    presenter.notice(context, const PdfEditorNotice('one'));
    presenter.notice(context, const PdfEditorNotice('two', showClose: true));
    await tester.pump();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-toast-close')));
    await tester.pump();
    expect(find.text('two'), findsNothing);
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('applying redactions confirms in a destructive alert',
      (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: Column(children: [
            const Expanded(child: SizedBox.expand()),
            PdfMaterialHost(
              child: ListenableBuilder(
                listenable: editing,
                builder: (context, _) => PdfEditingToolbar(
                    controller: editing, viewerController: controller),
              ),
            ),
          ]),
        ));
    editing
      ..tool = PdfEditTool.redact
      ..addRedaction(0, const PdfRect(60, 715, 200, 748));
    await tester.pump();
    final apply = find.byKey(const ValueKey('pdf-apply-redactions'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final alert = find.byKey(const ValueKey('pdf-redaction-confirm'));
    expect(tester.widget(alert), isA<CupertinoAlertDialog>());
    final confirm = find.byKey(const ValueKey('pdf-redaction-confirm-apply'));
    expect(tester.widget<CupertinoDialogAction>(confirm).isDestructiveAction,
        isTrue);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(editing.hasRedactionMarks, isFalse);
    expect(find.byKey(const ValueKey('pdf-cupertino-toast')), findsOneWidget);
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets(
      'the annotation library renames in a Cupertino text prompt with the '
      'Cupertino text menu', (tester) async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    final box = editing.saveSelectedAnnotation('Reusable box')!;
    editing.groupSavedAnnotation(box, 'Review');
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: PdfMaterialHost(
            child: SizedBox(
              width: 360,
              child: PdfAnnotationLibraryPanel(
                  controller: editing, resizable: false),
            ),
          ),
        ));
    await tester.tap(find
        .byKey(const ValueKey('pdf-annotation-library-group-rename-Review')));
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-text-prompt'))),
        isA<CupertinoAlertDialog>());
    final field = find.byKey(const ValueKey('pdf-text-prompt-field'));
    expect(tester.widget(field), isA<CupertinoTextField>());
    await tester.enterText(field, 'Renamed');
    await tester.pump();

    // the field's context menu is Cupertino, never Material
    if (platform == TargetPlatform.macOS) {
      await tester.tapAt(tester.getCenter(field),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    } else {
      await tester.longPress(field);
    }
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('pdf-cupertino-text-menu')), findsOneWidget);
    expect(find.byType(CupertinoAdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    expectNoHostErrors(tester);
    // dismiss the menu, then submit
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-text-prompt-ok')));
    await tester.pumpAndSettle();
    expect(editing.savedAnnotations.single.group, 'Renamed');
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('Enter submits a Cupertino prompt', (tester) async {
    late BuildContext context;
    await pump(tester, Builder(builder: (c) {
      context = c;
      return const SizedBox.expand();
    }));
    final answer = presenter.text(context,
        const PdfTextRequest(title: 'Note', initial: 'a', multiline: true));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-text-prompt-field')), 'line');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await answer, 'line');
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets(
      'the stamp editor opens on a Cupertino route; its colour and '
      'signature prompts keep the stock pickers', (tester) async {
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: Builder(
            builder: (context) => Center(
              child: CupertinoButton(
                onPressed: () => showPdfStampEditor(context),
                child: const Text('open'),
              ),
            ),
          ),
        ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final editor = find.byType(PdfStampEditorDialog);
    expect(editor, findsOneWidget);
    expect(routeOf(tester, editor), isA<CupertinoDialogRoute<Object?>>());

    await tester.tap(find.byKey(const ValueKey('pdf-stamp-color-custom')));
    await tester.pumpAndSettle();
    final cancelColour = find.byKey(const ValueKey('pdf-color-picker-cancel'));
    expect(cancelColour, findsOneWidget);
    expect(routeOf(tester, cancelColour), isA<CupertinoDialogRoute<Object?>>());
    await tester.tap(cancelColour);
    await tester.pumpAndSettle();

    final signature = find.byKey(const ValueKey('pdf-stamp-add-signature'));
    await tester.ensureVisible(signature);
    await tester.tap(signature);
    await tester.pumpAndSettle();
    expect(find.byType(PdfSignatureDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-signature-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(PdfSignatureDialog), findsNothing);
    expect(editor, findsOneWidget);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets(
      'Edit text & style is a Cupertino alert; its font row opens the stock '
      'font picker', (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: Column(children: [
            const Expanded(child: SizedBox.expand()),
            PdfMaterialHost(
              child: ListenableBuilder(
                listenable: editing,
                builder: (context, _) => PdfEditingToolbar(
                    controller: editing, viewerController: controller),
              ),
            ),
          ]),
        ));
    editing.tool = PdfEditTool.content;
    final element = editing
        .elementsOn(0)
        .elements
        .firstWhere((e) => e.kind == PdfElementKind.text);
    final b = element.bounds!;
    expect(
        editing.selectElementAt(
            0, (b.left + b.right) / 2, (b.bottom + b.top) / 2),
        isTrue);
    await tester.pump();
    final edit = find.byKey(const ValueKey('pdf-style-element-text'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(
        tester.widget(find.byKey(const ValueKey('pdf-cupertino-styled-text'))),
        isA<CupertinoAlertDialog>());
    expect(find.byType(CupertinoSlider), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-styled-font')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-font-std-serif')).last);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('pdf-styled-font')),
            matching: find.text('Serif')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-styled-bold')));
    await tester.tap(find.byKey(const ValueKey('pdf-styled-fill-0')));
    await tester.enterText(
        find.byKey(const ValueKey('pdf-styled-text-field')), 'Edited');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-styled-ok')));
    await tester.pumpAndSettle();

    expect(
        editing.elementsOn(0).elements.map((e) => e.text), contains('Edited'));
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('a single-select choice is a picker; Done sets the value',
      (tester) async {
    final (editing, controller) = controllers(buildListBoxFormPdf());
    await pump(tester, viewer(editing, controller));
    await tester.tapAt(_view(172, 452)); // the size combo (S M L, /V M)
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('pdf-cupertino-choice-picker'));
    expect(tester.widget(picker), isA<CupertinoPicker>());
    expect(find.byKey(const ValueKey('pdf-form-option-L')), findsOneWidget);
    await tester.drag(picker, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-choice-done')));
    await tester.pumpAndSettle();
    expect(editing.acroForm!.fieldNamed('size')!.value, 'L');
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('a multi-select choice is a checklist; Done sets the selection',
      (tester) async {
    final (editing, controller) = controllers(buildListBoxFormPdf());
    await pump(tester, viewer(editing, controller));
    await tester.tapAt(_view(172, 650)); // the toppings list box
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final pep = find.byKey(const ValueKey('pdf-form-option-pep'));
    expect(tester.widget(pep), isA<CupertinoListTile>());
    await tester.tap(pep);
    await tester.tap(find.byKey(const ValueKey('pdf-form-option-Ham')));
    await tester.pump();
    // nothing changes until Done
    expect(editing.acroForm!.fieldNamed('toppings')!.values, ['Ham', 'Olives']);
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-choice-done')));
    await tester.pumpAndSettle();
    expect(editing.acroForm!.fieldNamed('toppings')!.values, ['pep', 'Olives']);

    // Cancel leaves it alone
    await tester.tapAt(_view(172, 650));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-form-option-Cheese')));
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-choice-cancel')));
    await tester.pumpAndSettle();
    expect(editing.acroForm!.fieldNamed('toppings')!.values, ['pep', 'Olives']);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets(
      'arming a measure tool asks for the scale in a Cupertino alert; the '
      'unit is an action sheet', (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(
        tester,
        PdfEditorScope(
          presenter: presenter,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: PdfMaterialHost(
              child: PdfEditingToolbar(
                  controller: editing, viewerController: controller),
            ),
          ),
        ),
        size: const Size(1400, 900));
    await tester.tap(find.byKey(const ValueKey('pdf-group-measure')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-tool-measureDistance')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-cupertino-scale'))),
        isA<CupertinoAlertDialog>());
    await tester.tap(find.byKey(const ValueKey('pdf-scale-unit')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-cupertino-unit-m')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-scale-value')), '2');
    await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
    await tester.pumpAndSettle();

    final scale = editing.preferences.measurementScale!;
    expect(scale.unitLabel, 'm');
    expect(editing.tool, PdfEditTool.measureDistance);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('drawing a calibration segment asks its length', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(tester, viewer(editing, controller));
    editing.tool = PdfEditTool.calibrate;
    await tester.pump();
    final from = _view(100, 700);
    final to = _view(300, 700);
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await gesture.moveTo(to);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-cupertino-calibrate'))),
        isA<CupertinoAlertDialog>());
    await tester.enterText(
        find.byKey(const ValueKey('pdf-calibrate-value')), '50');
    await tester.tap(find.byKey(const ValueKey('pdf-calibrate-apply')));
    await tester.pumpAndSettle();
    final scale = editing.preferences.measurementScale!;
    expect(scale.unitLabel, 'ft');
    // 200pt drawn = 50 ft
    expect(scale.unitsPerPoint, closeTo(50 / 200, 1e-6));
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('closing a volume footprint asks its depth', (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    editing.preferences.measurementScale = PdfMeasurementScale(
        unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: 1);
    await pump(tester, viewer(editing, controller));
    editing.tool = PdfEditTool.measureVolume;
    await tester.pump();
    Future<void> click(Offset at) async {
      final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await g.up();
      await tester.pump();
    }

    await click(_view(400, 500));
    await click(_view(472, 500));
    await click(_view(472, 572));
    await click(_view(400, 572));
    await tester.tapAt(_view(400, 572));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(_view(400, 572));
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-cupertino-depth'))),
        isA<CupertinoAlertDialog>());
    await tester.enterText(find.byKey(const ValueKey('pdf-depth-value')), '2');
    await tester.tap(find.byKey(const ValueKey('pdf-depth-apply')));
    await tester.pumpAndSettle();
    expect(
        editing.document.page(0).annotations.where((a) => a.subtype != 'Link'),
        isNotEmpty);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('Export pages asks for the range in a Cupertino alert',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(4));
    addTearDown(editing.dispose);
    Uint8List? exported;
    await pump(
        tester,
        PdfEditorView(
          controller: editing,
          presenter: presenter,
          onExportPages: (bytes) => exported = bytes,
        ),
        size: const Size(1000, 800));
    expectPdfHostPlatform(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-export-pages')));
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-page-range-dialog'))),
        isA<CupertinoAlertDialog>());
    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-range-from')), '3');
    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-range-to')), '2');
    await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
    await tester.pump();
    expect(find.text('The last page must not be before the first.'),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-page-range-to')), '4');
    await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
    await tester.pumpAndSettle();
    expect(exported, isNotNull);
    expect(PdfDocument.open(exported!).pageCount, 2);
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('Split asks for the ranges in a Cupertino alert', (tester) async {
    List<Uint8List>? parts;
    await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(4),
          presenter: presenter,
          onSplitPages: (p) => parts = p,
        ),
        size: const Size(1000, 800));
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-split-pages')));
    await tester.pumpAndSettle();

    expect(tester.widget(find.byKey(const ValueKey('pdf-split-dialog'))),
        isA<CupertinoAlertDialog>());
    await tester.enterText(find.byKey(const ValueKey('pdf-split-ranges')), '9');
    await tester.tap(find.byKey(const ValueKey('pdf-split-confirm')));
    await tester.pump();
    expect(find.textContaining('Use pages 1–4'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-split-ranges')), '1-2, 4');
    await tester.tap(find.byKey(const ValueKey('pdf-split-confirm')));
    await tester.pumpAndSettle();
    expect(parts, hasLength(2));
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('the compact controls sheet is a Cupertino modal popup',
      (tester) async {
    await pump(tester,
        PdfEditorView(bytes: buildMultiPagePdf(2), presenter: presenter),
        size: const Size(600, 800));
    await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('pdf-cupertino-sheet'));
    expect(sheet, findsOneWidget);
    expect(routeOf(tester, sheet), isA<CupertinoModalPopupRoute<Object?>>());
    expect(
        find.descendant(
            of: sheet,
            matching: find.byKey(const ValueKey('pdf-shell-view-options'))),
        findsOneWidget);
    // the barrier dismisses it
    await tester.tapAt(const Offset(300, 20));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('a touch selection gets the Cupertino action bar',
      (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(tester, viewer(editing, controller));
    editing
      ..addRectangle(0, const PdfRect(150, 450, 300, 550))
      ..tool = PdfEditTool.select;
    await tester.pump();
    await tester.tapAt(_view(225, 500));
    await tester.pump(const Duration(milliseconds: 400));

    final bar = find
        .byKey(const ValueKey('pdf-cupertino-action-bar-annotationSelection'));
    expect(bar, findsOneWidget);
    final delete = find.byKey(const ValueKey('pdf-selection-chip-delete'));
    expect(find.descendant(of: bar, matching: delete), findsOneWidget);
    expect(tester.widget(delete), isA<CupertinoButton>());
    await tester.tap(delete);
    // the viewer's double-tap recognizer holds the arena until its timeout
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.document.page(0).annotations, isEmpty);
    await clearNotices(tester);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('a touch text selection gets the labelled Cupertino bar',
      (tester) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await pump(
        tester,
        PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(1)),
          controller: controller,
          presenter: presenter,
        ));
    final gesture = await tester.startGesture(_view(100, 720));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final bar =
        find.byKey(const ValueKey('pdf-cupertino-action-bar-textSelection'));
    expect(bar, findsOneWidget);
    expect(
        find.descendant(
            of: bar,
            matching:
                find.byKey(const ValueKey('pdf-text-selection-chip-copy'))),
        findsOneWidget);
    expect(
        find.descendant(of: bar, matching: find.text('Copy')), findsOneWidget);
    expectNoHostErrors(tester);
  }, variant: variant);

  testWidgets('a style change draws the Cupertino readout', (tester) async {
    final (editing, controller) = controllers(buildMultiPagePdf(1));
    await pump(tester, viewer(editing, controller));
    editing
      ..tool = PdfEditTool.rectangle
      ..preferences.strokeWidth = 4
      ..preferences.opacity = 0.5;
    await tester.pump();
    final gesture = await tester.startGesture(_view(150, 600));
    await gesture.moveTo(_view(300, 450));
    await tester.pump();
    final readout = find.byKey(const ValueKey('pdf-cupertino-readout'));
    expect(readout, findsOneWidget);
    expect(find.descendant(of: readout, matching: find.text('4 pt · 50%')),
        findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expectNoHostErrors(tester);
  }, variant: variant);
}

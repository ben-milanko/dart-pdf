import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PdfEditorPresenter: every stock entry point - nested ones included - asks
// the presenter of the nearest PdfEditorScope instead of opening stock UI.

// 800×600 viewport, fit-width: 612pt page → view scale
const _scale = 800 / 612;
Offset _viewPoint(double x, double y) => Offset(x * _scale, (792 - y) * _scale);

/// Records each call and answers it without showing anything.
class _RecordingPresenter extends PdfEditorPresenter {
  final calls = <String>[];
  final notices = <PdfEditorNotice>[];
  PdfMeasurementScaleRequest? scaleRequest;
  PdfColorRequest? colorRequest;
  PdfFontRequest? fontRequest;
  PdfTextRequest? textRequest;

  /// The key of the menu entry [menu] picks.
  Key? pick;

  @override
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) async {
    calls.add('menu');
    for (final entry in request.entries) {
      if (entry is PdfMenuItem<T> && entry.key == pick) return entry.value;
    }
    return null;
  }

  @override
  bool notice(BuildContext context, PdfEditorNotice notice) {
    calls.add('notice');
    notices.add(notice);
    return true;
  }

  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) async {
    calls.add('text');
    textRequest = request;
    return 'Renamed';
  }

  @override
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) async {
    calls.add('confirm');
    return true;
  }

  @override
  Future<PdfLinkTarget?> link(
      BuildContext context, PdfLinkRequest request) async {
    calls.add('link');
    return const PdfLinkTarget.uri('https://example.com');
  }

  @override
  Future<PdfColorResult?> color(
      BuildContext context, PdfColorRequest request) async {
    calls.add('color');
    colorRequest = request;
    return const PdfColorResult.picked(Color(0xFFE53935));
  }

  @override
  Future<PdfFontChoice?> font(
      BuildContext context, PdfFontRequest request) async {
    calls.add('font');
    fontRequest = request;
    return request.entries
        .firstWhere((e) => e.key == const ValueKey('pdf-font-std-serif'))
        .choice;
  }

  @override
  Future<PdfMeasurementScale?> measurementScale(
      BuildContext context, PdfMeasurementScaleRequest request) async {
    calls.add('measurementScale');
    scaleRequest = request;
    return const PdfMeasurementScale(unitsPerPoint: 1, unitLabel: 'ft');
  }

  @override
  Future<PdfInkSignature?> signature(
      BuildContext context, PdfSignatureRequest request) async {
    calls.add('signature');
    return null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('of() falls back to the stock presenter outside any scope',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    expect(PdfEditorPresenter.of(context).runtimeType, PdfEditorPresenter);
  });

  testWidgets(
      'showPdfDialog carries the scope into the route, no Material '
      'localizations needed', (tester) async {
    final presenter = _RecordingPresenter();
    PdfEditorPresenter? inDialog;
    late BuildContext opener;
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          pageBuilder: (context, _, __) => builder(context)),
      home: PdfEditorScope(
        presenter: presenter,
        child: Builder(builder: (context) {
          opener = context;
          return const SizedBox();
        }),
      ),
    ));
    showPdfDialog<void>(
      context: opener,
      builder: (context) {
        inDialog = PdfEditorPresenter.of(context);
        return const SizedBox();
      },
    );
    await tester.pumpAndSettle();
    expect(inDialog, same(presenter));
    expect(
        tester.getSemantics(find.byType(ModalBarrier).last).label, 'Dismiss');
  });

  testWidgets('flatten raises a notice whose Undo reverts it', (tester) async {
    final presenter = _RecordingPresenter();
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 650, 250, 750));
    final viewer = PdfViewerController();
    final commands =
        PdfEditorCommands(controller: editing, viewerController: viewer);
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    addTearDown(commands.dispose);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorScope(
          presenter: presenter,
          child: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          }),
        ),
      ),
    ));

    commands.flatten(context);
    expect(presenter.calls, ['notice']);
    expect(find.text(presenter.notices.single.message), findsNothing);
    expect(editing.document.page(0).annotations, isEmpty);
    final undo = presenter.notices.single.onUndo;
    expect(undo, isNotNull);
    undo!();
    expect(editing.document.page(0).annotations, hasLength(1));
  });

  testWidgets('arming a measure tool asks the presenter for the scale',
      (tester) async {
    wide(tester);
    final presenter = _RecordingPresenter();
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    // a scope above the app reaches every route the editor opens
    await tester.pumpWidget(PdfEditorScope(
      presenter: presenter,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfEditingToolbar(
                controller: editing, viewerController: viewer),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('pdf-group-measure')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-tool-measureDistance')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(presenter.calls, ['measurementScale']);
    expect(find.byType(PdfScaleDialog), findsNothing);
    expect(editing.preferences.measurementScale?.unitLabel, 'ft');
    expect(editing.tool, PdfEditTool.measureDistance);

    // Calibrate's hint is a notice too
    presenter.scaleRequest!.onCalibrate!();
    expect(editing.tool, PdfEditTool.calibrate);
    expect(presenter.calls.last, 'notice');
  });

  testWidgets('applying redactions confirms, then notices, via the presenter',
      (tester) async {
    wide(tester);
    final presenter = _RecordingPresenter();
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: PdfEditorScope(
        presenter: presenter,
        child: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfEditingToolbar(
                controller: editing, viewerController: viewer),
          ),
        ),
      ),
    ));
    editing
      ..tool = PdfEditTool.redact
      ..addRedaction(0, const PdfRect(60, 715, 200, 748));
    await tester.pump();
    final apply = find.byKey(const ValueKey('pdf-apply-redactions'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(presenter.calls, ['confirm', 'notice']);
    expect(find.byKey(const ValueKey('pdf-redaction-confirm')), findsNothing);
    expect(editing.hasRedactionMarks, isFalse);
  });

  testWidgets('the stamp editor nests its colour and signature prompts',
      (tester) async {
    final presenter = _RecordingPresenter();
    await tester.pumpWidget(MaterialApp(
      home: PdfEditorScope(
        presenter: presenter,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPdfStampEditor(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfStampEditorDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-stamp-color-custom')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('pdf-stamp-add-signature')));
    await tester.tap(find.byKey(const ValueKey('pdf-stamp-add-signature')));
    await tester.pumpAndSettle();

    expect(presenter.calls, ['color', 'signature']);
    expect(presenter.colorRequest!.allowSampleFromPage, isFalse);
    expect(find.byType(PdfSignatureDialog), findsNothing);
  });

  testWidgets('the annotation library renames through the presenter',
      (tester) async {
    final presenter = _RecordingPresenter();
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    final box = editing.saveSelectedAnnotation('Reusable box')!;
    editing.groupSavedAnnotation(box, 'Review');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorScope(
          presenter: presenter,
          child: SizedBox(
            width: 360,
            child: PdfAnnotationLibraryPanel(
                controller: editing, resizable: false),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find
        .byKey(const ValueKey('pdf-annotation-library-group-rename-Review')));
    await tester.pumpAndSettle();

    expect(presenter.calls, ['text']);
    expect(presenter.textRequest!.initial, 'Review');
    expect(editing.savedAnnotations.single.group, 'Renamed');
  });

  testWidgets('the font menu asks the presenter and applies its choice',
      (tester) async {
    final presenter = _RecordingPresenter();
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: PdfEditorScope(
        presenter: presenter,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showPdfFontMenu(context: context, controller: editing),
            child: const Text('fonts'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fonts'));
    await tester.pumpAndSettle();

    expect(presenter.calls, ['font']);
    expect(
        presenter.fontRequest!.entries.map((e) => e.choice),
        contains(isA<PdfStandardFontChoice>()
            .having((c) => c.family, 'family', PdfStandardFontFamily.mono)));
    expect(editing.fontFamily.family, PdfStandardFontFamily.serif);
  });

  testWidgets('the text menu and its Add link go through PdfViewer.presenter',
      (tester) async {
    final presenter = _RecordingPresenter()
      ..pick = const ValueKey('pdf-text-menu-link');
    final viewer = PdfViewerController();
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(viewer.dispose);
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            controller: viewer,
            editing: editing,
            presenter: presenter,
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tapAt(_viewPoint(100, 720),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(presenter.calls, ['menu', 'link']);
    expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
    final link = editing.document
        .page(0)
        .annotations
        .where((a) => a.subtype == 'Link')
        .toList();
    expect(link, hasLength(1));
  });

  testWidgets('a textPrompt argument takes precedence over the presenter',
      (tester) async {
    final presenter = _RecordingPresenter();
    final asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          bytes: buildMultiPagePdf(1),
          presenter: presenter,
          textPrompt: (context,
              {required title, initial = '', multiline = false}) async {
            asked.add(title);
            return 'from the prompt';
          },
        ),
      ),
    ));
    await tester.pump();

    final context = tester.element(find.byType(PdfViewer));
    final answer = await PdfEditorPresenter.of(context)
        .text(context, const PdfTextRequest(title: 'Name'));
    expect(answer, 'from the prompt');
    expect(asked, ['Name']);
    // ...and the rest still goes to the presenter
    PdfEditorPresenter.of(context)
        .notice(context, const PdfEditorNotice('hello'));
    expect(presenter.calls, ['notice']);
  });
}

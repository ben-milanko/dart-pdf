// The stock editor under any host: a CupertinoApp or a bare WidgetsApp gets
// the same working chrome as a MaterialApp - pages, menus, dialogs, sheets,
// notices, dropdowns, form fields and the text fields' own context menus
// (which build in the root overlay, outside the editor) - with no
// FlutterError and no error widget.

import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_host.dart';

// 1000px viewport, fit-width: 612pt page -> view scale
const _scale = 1000 / 612;
Offset _view(double x, double y) => Offset(x * _scale, (792 - y) * _scale);

final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

const _nonMaterialHosts = [PdfTestHost.cupertino, PdfTestHost.widgets];

/// The platforms whose text-field menus differ: Material, Cupertino, and
/// the desktop toolbar opened by a right-click.
final _menuPlatforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
});

bool get _desktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

Widget _viewer(PdfEditingController editing, PdfViewerController viewer) =>
    ListenableBuilder(
      listenable: editing,
      builder: (context, _) => PdfViewer(
        initialFit: PdfViewerFit.width,
        document: editing.document,
        controller: viewer,
        editing: editing,
      ),
    );

/// Opens the context menu of the text field [field] the way the platform
/// does: a right-click on desktop, a long-press on touch.
Future<void> _openFieldMenu(WidgetTester tester, Finder field) async {
  if (_desktop) {
    await tester.tap(field,
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  } else {
    await tester.longPress(field);
  }
  await tester.pumpAndSettle();
}

/// Lets notices time out: a SnackBar starts its timer only once it has
/// animated in, so one long pump is not enough.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final host in PdfTestHost.values) {
    group('under ${host.name}', () {
      testWidgets('PdfViewer opens and scrolls', (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(3));
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);
        expectPdfHostPlatform(tester);

        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(PdfViewer), const Offset(0, -700));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(viewer.currentPage, greaterThan(0));
        expectNoHostErrors(tester);
      });

      testWidgets(
          'page text: right-click menu, Add link prompt, and its text '
          "field's own context menu", (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(1));
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);
        expectPdfHostPlatform(tester);

        await tester.tapAt(_view(100, 720),
            kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pdf-text-menu-link')));
        await tester.pumpAndSettle();

        final url = find.byKey(const ValueKey('pdf-link-url'));
        expect(url, findsOneWidget);
        await tester.enterText(url, 'https://example.com');
        await tester.pump();
        await _openFieldMenu(tester, url);
        expect(find.byKey(const ValueKey('pdf-text-context-menu')),
            findsOneWidget);
        expectNoHostErrors(tester);

        // dismiss the field menu, then apply the link
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        final links = editing.document
            .page(0)
            .annotations
            .where((a) => a.subtype == 'Link');
        expect(links, hasLength(1));
        expectNoHostErrors(tester);
      }, variant: _menuPlatforms);

      testWidgets('form text and choice fields fill', (tester) async {
        final editing = PdfEditingController(buildAcroFormPdf());
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);

        await tester.tapAt(_view(186, 712));
        await tester.pump(const Duration(milliseconds: 400));
        final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
        expect(editor, findsOneWidget);
        await tester.enterText(editor, 'Jane');
        await _openFieldMenu(tester, editor);
        expect(find.byKey(const ValueKey('pdf-text-context-menu')),
            findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Escape may have closed the field editor along with its menu
        if (editor.evaluate().isNotEmpty) {
          await tester.enterText(editor, 'Jane');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle(const Duration(milliseconds: 400));
          expect(editing.acroForm!.fieldNamed('name')!.value, 'Jane');
        }

        await tester.tapAt(_view(136, 472)); // the combo box
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        await tester.tap(find.text('Large').last);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        expect(editing.acroForm!.fieldNamed('size')!.value, 'L');
        expectNoHostErrors(tester);
      }, variant: _menuPlatforms);

      testWidgets('a dropdown inside a stock dialog', (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(1));
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);

        PdfMeasurementScale? scale;
        showPdfScaleDialog(pdfEditorContext(tester)).then((s) => scale = s);
        await tester.pumpAndSettle();
        final unit = find.byKey(const ValueKey('pdf-scale-unit'));

        await tester.tap(unit);
        await tester.pumpAndSettle();
        await tester.tap(find.text('mi').last);
        await tester.pumpAndSettle();
        expect(tester.widget<PdfDropdown<String>>(unit).value, 'mi');

        await tester.enterText(
            find.byKey(const ValueKey('pdf-scale-value')), '2');
        await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
        await tester.pumpAndSettle();
        expect(scale?.unitLabel, 'mi');
        expectNoHostErrors(tester);
      });

      testWidgets('a sheet, and a notice with Undo', (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(1));
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);
        final context = pdfEditorContext(tester);
        final presenter = PdfEditorPresenter.of(context);

        String? picked;
        presenter
            .sheet<String>(
                context,
                PdfSheetRequest(
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TextField(
                          key: ValueKey('sheet-field'),
                          contextMenuBuilder: pdfTextContextMenu),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop('done'),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ))
            .then((v) => picked = v);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sheet-field')), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(picked, 'done');

        var undone = 0;
        expect(
            presenter.notice(
                context,
                PdfEditorNotice('Flattened',
                    kind: PdfNoticeKind.success,
                    onUndo: () => undone++,
                    key: const ValueKey('test-notice'))),
            isTrue,
            reason: 'a notice is shown under every host');
        await tester.pumpAndSettle();
        expect(find.text('Flattened'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await _drain(tester);
        expect(undone, 1);
        expect(find.text('Flattened'), findsNothing);

        // an un-acted notice goes away on its own
        presenter.notice(context, const PdfEditorNotice('Saved'));
        await tester.pump();
        expect(find.text('Saved'), findsOneWidget);
        await _drain(tester);
        expect(find.text('Saved'), findsNothing);
        expectNoHostErrors(tester);
      });

      testWidgets('image crop chrome', (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(1));
        final viewer = PdfViewerController();
        addTearDown(editing.dispose);
        addTearDown(viewer.dispose);
        expect(
            editing.addImageInRect(0, const PdfRect(150, 520, 350, 700), _png),
            isTrue);
        await pumpPdfHost(tester, _viewer(editing, viewer), host: host);
        editing.beginImageCrop();
        await tester.pump();
        expect(find.byKey(const ValueKey('pdf-crop-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pdf-crop-cancel')));
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        expect(editing.isCroppingImage, isFalse);
        expectNoHostErrors(tester);
      });

      testWidgets('PdfEditorView, PdfReader and PdfComparisonView build',
          (tester) async {
        final bytes = buildMultiPagePdf(2);
        await pumpPdfHost(tester, PdfEditorView(bytes: bytes), host: host);
        await tester.pumpAndSettle();
        expectPdfHostPlatform(tester);
        expectNoHostErrors(tester);

        await pumpPdfHost(tester, PdfReader(bytes: bytes), host: host);
        await tester.pumpAndSettle();
        expectNoHostErrors(tester);

        await pumpPdfHost(
            tester,
            PdfComparisonView(
              before: bytes,
              after: buildMultiPagePdf(3),
            ),
            host: host);
        await tester.pumpAndSettle();
        expectNoHostErrors(tester);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  for (final host in _nonMaterialHosts) {
    testWidgets('a stock dialog opened from outside the editor (${host.name})',
        (tester) async {
      late BuildContext root;
      await pumpPdfHost(tester, Builder(builder: (context) {
        root = context;
        return const SizedBox.expand();
      }), host: host);
      String? answer;
      showPdfTextPrompt(root, title: 'Name', initial: 'hello world')
          .then((v) => answer = v);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('pdf-text-prompt-field'));
      expect(field, findsOneWidget);
      await _openFieldMenu(tester, field);
      expect(
          find.byKey(const ValueKey('pdf-text-context-menu')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Ada');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(answer, 'Ada');
      expectNoHostErrors(tester);
    }, variant: _menuPlatforms);
  }

  testWidgets('a Material host gets no extra theme, localizations or surface',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpPdfHost(tester, _viewer(editing, viewer),
        host: PdfTestHost.material);
    // the wrapper builds the editor content directly: no Theme, no
    // Localizations, no Material in between
    final hostElement = tester.element(find.byType(PdfMaterialHost).first);
    Element? child;
    hostElement.visitChildren((c) => child = c);
    expect(child!.widget, isA<Builder>());
    expect(Theme.of(pdfEditorContext(tester)), same(Theme.of(hostElement)));
    expectNoHostErrors(tester);
  });
}

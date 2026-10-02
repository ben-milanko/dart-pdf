// The editor under a host still on the legacy package:flutter/material.dart
// MaterialApp (6.0 moved the library to material_ui, whose Theme,
// localizations and ScaffoldMessenger are other types). The bridge
// (lib/src/legacy/legacy_host_bridge.dart) must carry the host's theme into
// the chrome - its exact primary colour and dark mode - and its notices onto
// the host's messenger, and every route-built surface (dialogs, text-field
// context menus, dropdowns, sheets) must work without a FlutterError.
//
// This file deliberately imports the legacy library: it is the host here.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/shell_chrome.dart' show PdfShellBar;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_host.dart';

const _seed = Color(0xFF00897B);

legacy.ThemeData _hostTheme(Brightness brightness) => legacy.ThemeData(
      platform: defaultTargetPlatform,
      colorScheme: legacy.ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
        // an exact primary, not a tonal one: the bridge must not re-seed
        primary: const Color(0xFF00BFA5),
      ),
    );

/// The platforms whose text-field menus differ.
final _menuPlatforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
});

bool get _desktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  Widget Function(Widget child)? around,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(legacy.MaterialApp(
    theme: _hostTheme(brightness),
    home: legacy.Scaffold(body: around == null ? child : around(child)),
  ));
  await tester.pump();
}

Future<void> _openFieldMenu(WidgetTester tester, Finder field) async {
  if (_desktop) {
    await tester.tap(field,
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  } else {
    await tester.longPress(field);
  }
  await tester.pumpAndSettle();
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      "the host's primary colour and dark brightness reach the editor chrome",
      (tester) async {
    await _pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
    await tester.pumpAndSettle();
    final host = _hostTheme(Brightness.dark).colorScheme;

    final chrome = Theme.of(tester.element(find.byType(PdfShellBar)));
    expect(chrome.brightness, Brightness.dark);
    expect(chrome.colorScheme.primary, host.primary);
    expect(chrome.colorScheme.surfaceContainerLow, host.surfaceContainerLow);
    expect(chrome.colorScheme.onSurface, host.onSurface);
    expect(chrome.platform, defaultTargetPlatform);

    // and the header is actually painted with it
    final bar = tester.widget<Material>(find
        .descendant(
            of: find.byType(PdfShellBar), matching: find.byType(Material))
        .first);
    expect(bar.color, host.surfaceContainerLow);
    expectNoHostErrors(tester);
  });

  testWidgets('a host theme change rebuilds the chrome', (tester) async {
    await _pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
    await tester.pumpAndSettle();
    final save = find.byType(PdfShellBar);
    expect(Theme.of(tester.element(save)).brightness, Brightness.dark);

    await _pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)),
        brightness: Brightness.light);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(save)).brightness, Brightness.light);
    expect(Theme.of(tester.element(save)).colorScheme.primary,
        _hostTheme(Brightness.light).colorScheme.primary);
    expectNoHostErrors(tester);
  });

  testWidgets("the host's IconTheme survives the bridged Theme",
      (tester) async {
    const hostIcons = IconThemeData(color: Color(0xFFFF6D00), size: 21);
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await _pump(
      tester,
      PdfViewer(document: editing.document, editing: editing),
      around: (child) => IconTheme(data: hostIcons, child: child),
    );
    final inner = IconTheme.of(pdfEditorContext(tester));
    expect(inner.color, hostIcons.color);
    expect(inner.size, hostIcons.size);
    expectNoHostErrors(tester);
  });

  // The host's default IconTheme colour is the legacy library's
  // kDefaultIconDarkColor/kDefaultIconLightColor object, and material_ui's
  // IconButton tests for its own by identity: untranslated, it read as a
  // custom colour and drew every toolbar button in it, selected or not.
  for (final brightness in Brightness.values) {
    testWidgets(
        'the selected tool keeps its tint under the host default IconTheme '
        '(${brightness.name})', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await _pump(tester, PdfEditorView(controller: editing),
          brightness: brightness);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pumpAndSettle();
      expect(editing.tool, PdfEditTool.rectangle);

      Color? iconColor(String key) => IconTheme.of(tester.element(find
              .descendant(
                  of: find.byKey(ValueKey(key)), matching: find.byType(Icon))
              .first))
          .color;
      final host = _hostTheme(brightness).colorScheme;
      expect(iconColor('pdf-tool-rectangle'), host.primary);
      expect(iconColor('pdf-tool-ellipse'), host.onSurfaceVariant);
      expectNoHostErrors(tester);
    });
  }

  testWidgets('PdfEditorThemeData colour tokens win over the legacy host',
      (tester) async {
    const red = Color(0xFFC62828);
    await _pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          theme: const PdfEditorThemeData(
              primary: red, brightness: Brightness.light),
        ));
    await tester.pumpAndSettle();
    final chrome = Theme.of(tester.element(find.byType(PdfShellBar)));
    expect(chrome.colorScheme.primary, red);
    expect(chrome.brightness, Brightness.light);
    expectNoHostErrors(tester);
  });

  testWidgets(
      'a stock dialog from the editor: its text field, its context menu, '
      'Enter to submit', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await _pump(
        tester, PdfViewer(document: editing.document, editing: editing));

    String? answer;
    showPdfTextPrompt(pdfEditorContext(tester), title: 'Name', initial: 'hi')
        .then((v) => answer = v);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('pdf-text-prompt-field'));
    expect(field, findsOneWidget);
    // the dialog is themed like the host, not material_ui's light fallback
    expect(Theme.of(tester.element(field)).brightness, Brightness.dark);
    expect(Theme.of(tester.element(field)).colorScheme.primary,
        _hostTheme(Brightness.dark).colorScheme.primary);

    await _openFieldMenu(tester, field);
    expect(find.byKey(const ValueKey('pdf-text-context-menu')), findsOneWidget);
    expectNoHostErrors(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.enterText(field, 'Ada');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer, 'Ada');
    expectNoHostErrors(tester);
  }, variant: _menuPlatforms);

  testWidgets('a stock dialog opened from host code outside the editor',
      (tester) async {
    late BuildContext root;
    await _pump(tester, Builder(builder: (context) {
      root = context;
      return const SizedBox.expand();
    }));
    String? answer;
    showPdfTextPrompt(root, title: 'Name').then((v) => answer = v);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('pdf-text-prompt-field'));
    expect(Theme.of(tester.element(field)).brightness, Brightness.dark);
    await _openFieldMenu(tester, field);
    expect(find.byKey(const ValueKey('pdf-text-context-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Grace');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer, 'Grace');
    expectNoHostErrors(tester);
  }, variant: _menuPlatforms);

  testWidgets('a dropdown inside a stock dialog', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await _pump(
        tester, PdfViewer(document: editing.document, editing: editing));

    PdfMeasurementScale? scale;
    showPdfScaleDialog(pdfEditorContext(tester)).then((s) => scale = s);
    await tester.pumpAndSettle();
    final unit = find.byKey(const ValueKey('pdf-scale-unit'));
    await tester.tap(unit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('mi').last);
    await tester.pumpAndSettle();
    expect(tester.widget<PdfDropdown<String>>(unit).value, 'mi');
    await tester.enterText(find.byKey(const ValueKey('pdf-scale-value')), '2');
    await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
    await tester.pumpAndSettle();
    expect(scale?.unitLabel, 'mi');
    expectNoHostErrors(tester);
  });

  testWidgets(
      "a sheet, and notices with Undo on the host's legacy ScaffoldMessenger",
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await _pump(
        tester, PdfViewer(document: editing.document, editing: editing));
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
    final sheetField = find.byKey(const ValueKey('sheet-field'));
    expect(Theme.of(tester.element(sheetField)).brightness, Brightness.dark);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, 'done');

    var undone = 0;
    expect(
        presenter.notice(
            context,
            PdfEditorNotice('Flattened',
                onUndo: () => undone++, key: const ValueKey('test-notice'))),
        isTrue);
    await tester.pumpAndSettle();
    // the host's own (legacy) SnackBar, not the overlay toast
    expect(find.byType(legacy.SnackBar), findsOneWidget);
    expect(find.text('Flattened'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await _drain(tester);
    expect(undone, 1);
    expect(find.text('Flattened'), findsNothing);
    expectNoHostErrors(tester);
  });

  testWidgets('PdfEditorView, PdfReader and PdfComparisonView build',
      (tester) async {
    final bytes = buildMultiPagePdf(2);
    await _pump(tester, PdfEditorView(bytes: bytes));
    await tester.pumpAndSettle();
    expectPdfHostPlatform(tester);
    expectNoHostErrors(tester);

    await _pump(tester, PdfReader(bytes: bytes));
    await tester.pumpAndSettle();
    expectNoHostErrors(tester);

    await _pump(
        tester, PdfComparisonView(before: bytes, after: buildMultiPagePdf(3)));
    await tester.pumpAndSettle();
    expectNoHostErrors(tester);
  });
}

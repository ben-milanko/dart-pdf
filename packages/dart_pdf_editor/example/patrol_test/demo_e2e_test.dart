import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:pdf_document/pdf_document.dart' show PdfFormField;
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _preferencePrefix = 'dart_pdf_editor.editing.';
const _buildCommit = String.fromEnvironment('PDF_BUILD_COMMIT');
const _testPreferences = <String, Object>{
  '${_preferencePrefix}locale': 'en',
  '${_preferencePrefix}showAnnotations': true,
  '${_preferencePrefix}showThumbnailSidebar': false,
  '${_preferencePrefix}showBookmarkSidebar': false,
  '${_preferencePrefix}showAnnotationSidebar': false,
  '${_preferencePrefix}showPropertiesPanel': false,
  '${_preferencePrefix}showSearchResultsPanel': false,
  '${_preferencePrefix}showReflowView': false,
  '${_preferencePrefix}showThumbnailView': false,
  // Native Patrol runs tests in a randomized order. Do not let one journey's
  // saved page/zoom become the next journey's starting point.
  '${_preferencePrefix}documentViewports': '[]',
};

void main() {
  // Patrol owns this test entry point, so the example app's main() does not
  // run. Mirror its optional-asset registration so the browser journey
  // exercises the production render worker instead of silently falling back
  // to main-thread interpretation.
  registerBundledEditorAssets();
  // CI builds the example's self-hosted worker before Patrol. Native backends
  // ignore this web-only URL and continue to use isolates.
  pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';

  // Stamp the shared perf logger here as well as in lib/main.dart so CI
  // artifacts can always be attributed to the exact revision under test.
  if (_buildCommit.isNotEmpty) {
    PdfPerfLog.buildTag = 'commit=$_buildCommit';
  }

  patrolTest('launches the demo and exercises PDF actions and overlays',
      ($) async {
    final demo = await _DemoHarness.open($);
    try {
      expect($(PdfViewer), findsOneWidget);
      expect($(const ValueKey('pdf-page-number-field')), findsOneWidget);
      expect($(const ValueKey('pdf-search-field')), findsOneWidget);
      expect(demo.viewer.pageCount, 6);

      // Exercise Patrol's out-of-process bridge as well as Flutter finders.
      // Native automation is not implemented on macOS.
      if ($.isAndroid || $.isIOS) {
        expect(await $.platform.mobile.getOsVersion(), greaterThan(0));
      } else if ($.isWeb) {
        expect(await $.platform.web.getCurrentPageUrl(), isNotEmpty);
      }

      await demo.waitFor(
        () => demo.viewerText('0').evaluate().isNotEmpty,
        attempts: 80,
      );
      expect(demo.viewerText('0'), findsWidgets);
      expect(demo.viewerText('1'), findsNothing);
      await demo.tapPdfPoint(176, 618); // Increment the counter.
      expect(demo.viewerText('1'), findsWidgets);

      await demo.tapPdfPoint(176, 558); // Show a message.
      await $.pump(const Duration(milliseconds: 250));
      expect($('Hello from the PDF'), findsOneWidget);

      await demo.tapPdfPoint(176, 498); // Go to the widgets page.
      await demo.waitFor(() => demo.viewer.currentPage == 1);
      // currentPage changes as the destination enters the viewport; let the
      // remaining scroll animation place its live overlay before tapping it.
      await $.pump(const Duration(milliseconds: 350));
      expect($(Switch), findsOneWidget);
      expect($.tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await $.tester.tap(find.byType(Switch));
      await $.pump(const Duration(milliseconds: 400));
      expect($.tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await $.tester.enterText(
        find.byKey(const ValueKey('demo-note')),
        'Patrol reached the live overlay',
      );
      expect($('Patrol reached the live overlay'), findsOneWidget);
    } finally {
      await demo.close();
    }
  });

  patrolTest('navigates, searches, and switches reader and editor modes',
      ($) async {
    final demo = await _DemoHarness.open($);
    try {
      await demo.goToPage(4);
      expect(demo.viewer.currentPage, 3);

      final search = find.byKey(const ValueKey('pdf-search-field'));
      await $.tester.enterText(search, 'Annotations & forms');
      await $.tester.testTextInput.receiveAction(TextInputAction.search);
      await demo.waitFor(
        () => !demo.viewer.isSearching && demo.viewer.matchCount > 0,
      );
      expect(demo.viewer.query, 'Annotations & forms');
      expect(demo.viewer.matchCount, greaterThan(0));
      expect(
        demo.viewer.searchResults.any((result) => result.match.pageIndex == 5),
        isTrue,
      );

      await $.tester.tap(find.byKey(const ValueKey('pdf-search-clear')));
      await $.pump();
      expect(demo.viewer.query, isEmpty);
      expect(demo.viewer.matchCount, 0);
      await demo.goToPage(6);

      await demo.chooseAppMenuItem(
        'Switch to read-only',
        key: 'dartpdf-read-only-toggle',
      );
      await demo.waitForFinder(find.byType(PdfReader));
      expect($(PdfEditorView), findsNothing);
      expect(demo.viewer.currentPage, 5,
          reason: 'mode switches preserve the reading position');

      await demo.chooseAppMenuItem(
        'Switch to edit mode',
        key: 'dartpdf-read-only-toggle',
      );
      await demo.waitForFinder(find.byType(PdfEditorView));
      expect($(PdfReader), findsNothing);
      expect(demo.viewer.currentPage, 5);
    } finally {
      await demo.close();
    }
  });

  patrolTest('creates annotations and drives undo, redo, delete, and ink',
      ($) async {
    final demo = await _DemoHarness.open($);
    try {
      final before = demo.annotationCount(0);
      await demo.armTool(group: 'shapes', tool: PdfEditTool.rectangle);
      expect(demo.editing.tool, PdfEditTool.rectangle);

      final page = demo.pageRect;
      final start =
          page.topLeft + Offset(page.width * 0.28, page.height * 0.34);
      final end = start + Offset(page.width * 0.20, page.height * 0.10);
      final gesture = await $.tester.startGesture(start);
      await gesture.moveTo(Offset.lerp(start, end, 0.45)!);
      await $.pump();
      await gesture.moveTo(end);
      await $.pump();
      await gesture.up();
      await demo.waitFor(
        () => demo.annotationCount(0) == before + 1,
        reason: 'the rectangle gesture should commit one annotation',
      );
      expect(demo.editing.canUndo, isTrue);

      await demo.tapToolbarAction('pdf-undo');
      await demo.waitFor(
        () => demo.annotationCount(0) == before,
        reason: 'Undo should remove the new rectangle',
      );
      expect(demo.editing.canRedo, isTrue);

      await demo.tapToolbarAction('pdf-redo');
      await demo.waitFor(
        () => demo.annotationCount(0) == before + 1,
        reason: 'Redo should restore the rectangle',
      );

      final center = Offset.lerp(start, end, 0.5)!;
      await demo.armTool(group: 'select', tool: PdfEditTool.select);
      await $.tester.tapAt(center);
      await $.pump(const Duration(milliseconds: 400));
      expect(demo.editing.hasAnnotationSelection, isTrue);

      await demo.tapToolbarTooltip('Delete annotation');
      await demo.waitFor(
        () => demo.annotationCount(0) == before,
        reason: 'Delete should remove the selected rectangle',
      );

      await demo.armTool(group: 'draw', tool: PdfEditTool.ink);
      final inkStart =
          page.topLeft + Offset(page.width * 0.25, page.height * 0.56);
      final ink = await $.tester.startGesture(inkStart);
      await ink.moveBy(Offset(page.width * 0.08, page.height * 0.025));
      await $.pump();
      await ink.moveBy(Offset(page.width * 0.10, -page.height * 0.04));
      await $.pump();
      await ink.up();
      await $.pump(const Duration(seconds: 1));
      await demo.waitFor(
        () => demo.annotationCount(0) == before + 1,
        reason: 'the ink stroke should auto-commit',
      );
      expect(
        demo.editing.pageAt(0).annotations.any((a) => a.subtype == 'Ink'),
        isTrue,
      );
    } finally {
      await demo.close();
    }
  });

  patrolTest('creates and edits a text note through the annotation UI',
      ($) async {
    final demo = await _DemoHarness.open($);
    try {
      final before = demo.annotationCount(0);
      await demo.armTool(group: 'insert', tool: PdfEditTool.note);

      final position = demo.pageRect.topLeft +
          Offset(demo.pageRect.width * 0.48, demo.pageRect.height * 0.40);
      await $.tester.tapAt(position);
      await $.pump(const Duration(milliseconds: 400));
      expect($(AlertDialog), findsOneWidget);

      await $.tester.enterText(
        find.byType(TextField).last,
        'First Patrol note',
      );
      await $.tester.tap(find.text('OK'));
      await $.pump();
      await $.pump(const Duration(milliseconds: 350));
      await demo.waitFor(() => demo.annotationCount(0) == before + 1);

      final scale = demo.pageRect.width / 612;
      await demo.armTool(group: 'select', tool: PdfEditTool.select);
      await $.tester.tapAt(position + Offset(10 * scale, 10 * scale));
      await $.pump(const Duration(milliseconds: 400));
      expect(demo.editing.hasAnnotationSelection, isTrue);

      await demo.tapToolbarTooltip('Edit annotation text');
      await $.pump();
      expect(
          find.widgetWithText(TextField, 'First Patrol note'), findsOneWidget);
      await $.tester.enterText(
        find.byType(TextField).last,
        'Revised Patrol note',
      );
      await $.tester.tap(find.text('OK'));
      await $.pump(const Duration(milliseconds: 400));

      expect(
        demo.editing.pageAt(0).annotations.any(
              (a) => a.subtype == 'Text' && a.contents == 'Revised Patrol note',
            ),
        isTrue,
      );
    } finally {
      await demo.close();
    }
  });

  patrolTest('fills text, checkbox, radio, and choice form fields', ($) async {
    final demo = await _DemoHarness.open($);
    try {
      await demo.goToPage(6);
      await demo.armTool(group: 'edit', tool: PdfEditTool.form);
      expect(demo.editing.tool, PdfEditTool.form);
      // Form mode itself is exercised above. Fill the widgets through the
      // reader interaction layer, which is how end users normally complete
      // an existing form and avoids leaving a compact tools sheet over it.
      demo.editing.tool = null;
      await $.pump();

      PdfFormField field(String name) =>
          demo.editing.acroForm!.fields.firstWhere((f) => f.name == name);

      await demo.tapFormField('name');
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);
      await $.tester.enterText(editor, 'Grace Hopper');
      await $.tester.testTextInput.receiveAction(TextInputAction.done);
      await $.pump(const Duration(milliseconds: 400));
      await demo.waitFor(
        () => field('name').value == 'Grace Hopper',
        reason: 'the text-field revision should finish before validation',
      );
      expect(field('name').value, 'Grace Hopper');

      expect(field('newsletter').isChecked, isTrue);
      await demo.tapFormFieldUntil(
        'newsletter',
        () => !field('newsletter').isChecked,
        reason: 'the checkbox revision should finish before validation',
      );
      expect(field('newsletter').isChecked, isFalse);

      expect(field('color').value, 'Blue');
      await demo.tapFormFieldUntil(
        'color',
        () => field('color').value == 'Red',
        reason: 'the radio revision should finish before validation',
      );
      expect(field('color').value, 'Red');

      expect(field('favorite').value, 'Green');
      await demo.tapFormField('favorite');
      await $.pump(const Duration(milliseconds: 250));
      expect($('Blue'), findsOneWidget);
      await $.tester.tap(find.text('Blue'));
      await $.pump(const Duration(milliseconds: 400));
      await demo.waitFor(
        () => field('favorite').value == 'Blue',
        reason: 'the choice revision should finish before validation',
      );
      expect(field('favorite').value, 'Blue');
    } finally {
      await demo.close();
    }
  });
}

class _DemoHarness {
  _DemoHarness(this.$);

  final PatrolIntegrationTester $;

  WidgetTester get tester => $.tester;

  PdfEditorView get editorView =>
      tester.widget<PdfEditorView>(find.byType(PdfEditorView));

  PdfEditingController get editing => editorView.controller!;

  PdfViewerController get viewer {
    final editor = find.byType(PdfEditorView);
    if (editor.evaluate().isNotEmpty) {
      return tester.widget<PdfEditorView>(editor).viewerController!;
    }
    return tester.widget<PdfReader>(find.byType(PdfReader)).controller!;
  }

  Rect get pageRect {
    final page = find.byWidgetPredicate(
      (widget) =>
          widget is PdfPageView && widget.previewIndex == viewer.currentPage,
    );
    return tester.getRect(page);
  }

  Finder viewerText(String value) => find.descendant(
        of: find.byType(PdfViewer),
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == value,
        ),
      );

  int annotationCount(int page) => editing.pageAt(page).annotations.length;

  static Future<_DemoHarness> open(PatrolIntegrationTester $) async {
    await _configurePreferences();
    final demo = _DemoHarness($);
    await $.pumpWidget(const ViewerApp());
    await demo.waitForFinder(find.byType(PdfViewer), attempts: 80);
    expect($(PdfViewer), findsOneWidget);
    expect($(PdfEditorView), findsOneWidget);
    return demo;
  }

  Future<void> close() async {
    await $.pumpWidget(const SizedBox());
    await $.pump(const Duration(milliseconds: 50));
  }

  Future<void> waitFor(
    bool Function() predicate, {
    int attempts = 60,
    String? reason,
  }) async {
    for (var i = 0; i < attempts && !predicate(); i++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(predicate(), isTrue, reason: reason);
  }

  Future<void> waitForFinder(Finder finder, {int attempts = 40}) async {
    for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
      await $.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  Offset pdfPoint(double x, double y) {
    final page = pageRect;
    final scale = page.width / 612;
    return page.topLeft + Offset(x * scale, (792 - y) * scale);
  }

  Future<void> tapPdfPoint(double x, double y) async {
    await tester.tapAt(pdfPoint(x, y));
    await $.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapFormField(String name, {int widgetIndex = 0}) async {
    final field = editing.acroForm?.fieldNamed(name);
    final rect = field?.widgetRect(widgetIndex);
    final page = field?.widgetPageIndex(widgetIndex) ?? -1;
    expect(field, isNotNull, reason: '$name should be an AcroForm field');
    expect(rect, isNotNull, reason: '$name widget $widgetIndex needs a rect');
    expect(page, greaterThanOrEqualTo(0),
        reason: '$name widget $widgetIndex should be on a page');

    // The compact editing dock floats over the bottom of the page. Lower
    // fields (notably the radio buttons on the showcase page) can otherwise
    // be present in the tree while their tap target is covered by the dock on
    // a short Android viewport. Frame the widget before tapping it, just as a
    // user would scroll the field into view.
    final target = find.byKey(
      ValueKey(
        'pdf-form-field-$page-$name-$widgetIndex',
      ),
    );
    final hitTarget = target.hitTestable();
    // On a loaded-down Android emulator the viewer's zoom animation can
    // advance more slowly than its scroll animation. Do not tap a stale
    // target that is still under the floating editing dock: that activates
    // the dock and leaves its modal sheet covering the retry. Re-frame until
    // Flutter confirms that the live form widget owns its centre point.
    for (var attempt = 0;
        attempt < 3 && hitTarget.evaluate().isEmpty;
        attempt++) {
      await viewer.showRect(page, rect!);
      await $.pump(const Duration(milliseconds: 350));
      await waitForFinder(target);
      for (var i = 0; i < 10 && hitTarget.evaluate().isEmpty; i++) {
        await $.pump(const Duration(milliseconds: 100));
      }
    }
    expect(
      hitTarget,
      findsOneWidget,
      reason: '$name widget $widgetIndex should be visible and unobscured',
    );
    await tester.tap(hitTarget);
    await $.pump(const Duration(milliseconds: 400));
  }

  /// Taps a button-like form widget, retrying one physical tap when a slow
  /// Android emulator loses the first gesture during a page/raster handoff.
  ///
  /// This does not fall back to the controller API: both attempts still go
  /// through the live overlay, so the journey continues to validate the real
  /// reader interaction path. Text and choice fields use [tapFormField]
  /// directly because a successful first tap opens stateful chrome.
  Future<void> tapFormFieldUntil(
    String name,
    bool Function() changed, {
    required String reason,
    int widgetIndex = 0,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await tapFormField(name, widgetIndex: widgetIndex);
      for (var i = 0; i < 20 && !changed(); i++) {
        await $.pump(const Duration(milliseconds: 100));
      }
      if (changed()) return;
    }
    expect(changed(), isTrue, reason: reason);
  }

  Future<void> goToPage(int pageNumber) async {
    final field = find.byKey(const ValueKey('pdf-page-number-field'));
    await tester.enterText(field, '$pageNumber');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(() => viewer.currentPage == pageNumber - 1);
  }

  Future<void> chooseAppMenuItem(String label, {String? key}) async {
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await $.pump();
    final item = key == null ? find.text(label) : find.byKey(ValueKey(key));
    await tester.ensureVisible(item);
    if (key == null) {
      await tester.tap(item);
    } else {
      await $(ValueKey(key)).tap();
    }
    await $.pump(const Duration(milliseconds: 350));
  }

  Future<void> armTool({
    required String group,
    required PdfEditTool tool,
  }) async {
    // Some one-shot tools return to Select after they commit. Opening the
    // Select group in that state toggles Select off, so preserve the already
    // satisfied state instead of driving the toolbar again.
    if (editing.tool == tool) return;

    final toolButton = find.byKey(ValueKey('pdf-tool-${tool.name}'));
    final mobileHandle = find.byKey(const ValueKey('pdf-tools-handle'));
    if (mobileHandle.evaluate().isNotEmpty) {
      await tester.tap(mobileHandle);
      await $.pump(const Duration(milliseconds: 250));
      final groupTab = find.byKey(ValueKey('pdf-group-tab-$group'));
      await tester.ensureVisible(groupTab);
      await tester.tap(groupTab);
      await $.pump(const Duration(milliseconds: 250));
      // Select is the mobile sheet's only single-option group, so tapping its
      // group tab now arms it directly and closes the sheet. Multi-tool groups
      // still expose their tiles below.
      if (editing.tool == tool) return;
      expect(toolButton, findsOneWidget,
          reason: '$tool should be available in the $group tool group');
      await tester.ensureVisible(toolButton);
      await tester.tap(toolButton);
      await $.pump();
      // Mobile keeps the tools sheet open to expose the active settings.
      // Tap its modal barrier so the armed tool can reach the page.
      final logicalWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(logicalWidth / 2, 8));
      await $.pump(const Duration(milliseconds: 300));
      return;
    }

    final chip = find.byKey(ValueKey('pdf-group-$group'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await $.pump();
    if (editing.tool == tool) return;
    for (var i = 0; i < 20 && toolButton.evaluate().isEmpty; i++) {
      await $.pump(const Duration(milliseconds: 50));
    }
    expect(toolButton, findsOneWidget);
    await tester.ensureVisible(toolButton);
    await tester.tap(toolButton);
    await $.pump();
  }

  Future<void> tapToolbarAction(String key) async {
    await $.pump();
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    expect(
      tester.widget<IconButton>(button).onPressed,
      isNotNull,
      reason: '$key should be enabled before it is tapped',
    );
    await $(ValueKey(key)).tap();
    await $.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapToolbarTooltip(String label) async {
    final button = _tooltipStartingWith(label);
    await tester.ensureVisible(button);
    await tester.tap(button.first);
    await $.pump(const Duration(milliseconds: 400));
  }

  Finder _tooltipStartingWith(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message == label ||
                (widget.message?.startsWith('$label (') ?? false)),
      );
}

Future<void> _configurePreferences() async {
  final preferences = await SharedPreferences.getInstance();
  final previous = <String, ({bool present, Object? value})>{
    for (final key in _testPreferences.keys)
      key: (present: preferences.containsKey(key), value: preferences.get(key)),
  };

  for (final entry in _testPreferences.entries) {
    switch (entry.value) {
      case final bool value:
        await preferences.setBool(entry.key, value);
      case final String value:
        await preferences.setString(entry.key, value);
    }
  }

  addTearDown(() async {
    for (final entry in previous.entries) {
      final saved = entry.value;
      if (!saved.present) {
        await preferences.remove(entry.key);
        continue;
      }
      switch (saved.value) {
        case final bool value:
          await preferences.setBool(entry.key, value);
        case final String value:
          await preferences.setString(entry.key, value);
        case final int value:
          await preferences.setInt(entry.key, value);
        case final double value:
          await preferences.setDouble(entry.key, value);
        case final List<String> value:
          await preferences.setStringList(entry.key, value);
      }
    }
  });
}

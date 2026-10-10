// Self-driving build of the DartPDF app for App Store app previews (the
// storefront video). Apple requires previews to be screen captures of the app
// itself (App Review Guideline 2.3.4), so this is the real app - the same
// EditorScreen the store build ships - operated by a scripted "hand": every
// step is a real touch delivered through the gesture pipeline
// (GestureBinding.handlePointerEvent) onto the app's own controls, found by
// their widget keys. A fingertip dot is painted over the app so viewers can
// follow the touches, as in a screen recording with touches shown.
//
// The host records the device screen while this runs. Markers on stdout tell
// it what is happening:
//
//   @@PREVIEW_READY@@            the app is up (start recording)
//   @@PREVIEW@@ start WxH@dpr    the tour is about to begin (start the clip)
//   @@PREVIEW@@ caption <id>     a chapter begins (tool/preview/compose_preview.py
//                                titles it)
//   @@PREVIEW@@ sfx <type> [s]   a sound cue (soundtrack.py voice, duration)
//   @@PREVIEW@@ end              the tour is over (end the clip)
//   @@PREVIEW_DONE@@             the host can stop recording and quit
//
// Each marker ends in `@<ms>` of tour time, which is frame time: once the tour
// starts, every frame the app draws is exactly 1/30 s later than the last
// (_FrameClock), and carries its number in a strip along the bottom edge. The
// composer places each captured frame by that number, so however slowly the
// simulator draws, the cut is smooth and every marker lands on its frame.
//
// tool/preview/record_ios.py drives it on the iOS simulator (and
// tool/preview/record_web.cjs in headless Chromium, for drafts); or by hand:
//
//   fvm flutter run -d <device> -t tool/preview_main.dart
//
// Like tool/screenshots_main.dart it starts from an empty preferences store so
// a developer's saved settings never leak into the recording.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart' show materialThemeMode;
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/keyboard_availability.dart';
import 'package:dart_pdf_editor_app/l10n/app_delegates.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_editor_app/window_support.dart';

import 'preview_capture.dart';
import 'preview_document.dart';

/// Milliseconds to wait for the document to open, render and extract its text
/// (the highlighter snaps to it) before the tour starts.
const _warmupMs = int.fromEnvironment('PREVIEW_WARMUP_MS', defaultValue: 20000);

/// Prints the keyed controls on screen at each step, for adapting the tour to
/// a new layout: `--dart-define=PREVIEW_PROBE=true`.
const _probe = bool.fromEnvironment('PREVIEW_PROBE');

/// Saves every tour frame as a PNG (record_ios.py turns this on):
/// `--dart-define=PREVIEW_CAPTURE=true`.
const _capture = bool.fromEnvironment('PREVIEW_CAPTURE');

Future<void> main() async {
  enableDartPdfWindowing();
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledEditorAssets();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  runDartPdfApp(const AppPreviewTour());
}

class AppPreviewTour extends StatefulWidget {
  const AppPreviewTour({super.key});

  @override
  State<AppPreviewTour> createState() => _AppPreviewTourState();
}

class _AppPreviewTourState extends State<AppPreviewTour> {
  final _prefs = PdfEditingPreferences();
  final _finger = _Finger();
  final _screen = GlobalKey();
  late final _doc = (bytes: buildPreviewPdf(), title: 'Website proposal.pdf');

  @override
  void initState() {
    super.initState();
    // A clean reading layout: the page fills the phone and the panels stay
    // shut until the tour opens one.
    _prefs.showThumbnailSidebar = false;
    unawaited(_run());
  }

  @override
  void dispose() {
    _prefs.dispose();
    _finger.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    // The host starts recording here, so the warm-up is already on tape.
    debugPrint('@@PREVIEW_READY@@');
    await Future<void>.delayed(const Duration(milliseconds: _warmupMs));
    if (_capture) {
      final dir = await prepareFrameDirectory();
      if (dir != null) {
        debugPrint('@@PREVIEW_FRAMES@@ $dir');
        _time.capture = (frame) => _captureFrame(dir, frame);
      }
    }
    final hand = _Hand(_finger);
    try {
      await _Tour(hand).play();
    } catch (error, stack) {
      debugPrint('@@PREVIEW@@ error $error');
      debugPrint('$stack');
    }
    debugPrint('@@PREVIEW_DONE@@');
  }

  /// Writes the frame just drawn - the app, the fingertip and the frame
  /// stamp, pixel for pixel what the screen shows below the system's status
  /// bar and home indicator - as a PNG.
  Future<void> _captureFrame(String dir, int frame) async {
    final boundary =
        _screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await writeFrame(dir, frame, png!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _screen,
      child: _shell(context),
    );
  }

  Widget _shell(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        ListenableBuilder(
          listenable: _prefs,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'DartPDF',
            builder: (context, child) => KeyboardAvailability(child: child!),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme:
                ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.indigo,
              brightness: Brightness.dark,
              useMaterial3: true,
            ),
            themeMode: materialThemeMode(_prefs.themePreference),
            home: EditorScreen(
              prefs: _prefs,
              initialDocument: _doc,
              ownsApplicationSession: false,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _FingerPainter(_finger)),
          ),
        ),
        // The frame number, cropped off by the composer.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _StampPainter(_time.stamp)),
          ),
        ),
      ]),
    );
  }
}

/// The storyboard. Each chapter announces its caption, then works the app.
class _Tour {
  _Tour(this.hand) {
    hand.onMove = _trackHand;
  }
  final _Hand hand;

  int _lastHandMs = -1000;
  bool _handShown = false;
  bool _handDown = false;

  /// Logs the fingertip (normalised, ~20 Hz; a trailing `d` while it
  /// touches) so the composer can frame each punch-in around what the finger
  /// does; `hand off` when it lifts away.
  void _trackHand(Offset? p, bool down) {
    if (!_time.running) return;
    if (p == null) {
      if (_handShown) _mark('hand off');
      _handShown = false;
      return;
    }
    final now = _time.elapsed.inMilliseconds;
    if (_handShown && down == _handDown && now - _lastHandMs < 50) return;
    _lastHandMs = now;
    _handShown = true;
    _handDown = down;
    final screen = _screenSize;
    _mark('hand ${(p.dx / screen.width).toStringAsFixed(4)} '
        '${(p.dy / screen.height).toStringAsFixed(4)}${down ? ' d' : ''}');
  }

  /// Switches to frame time and opens the clip. From here every frame is
  /// exactly one frame period of tour time (see [_FrameClock]).
  void _start() {
    _time.start();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = _screenSize;
    final dpr = view.devicePixelRatio;
    _mark('start ${size.width.round()}x${size.height.round()}@$dpr pad '
        '${(view.padding.top / dpr).round()},${(view.padding.bottom / dpr).round()}');
  }

  void _mark(String line) {
    // Nothing before the clip starts is heard or titled.
    if (!_time.running) return;
    debugPrint('@@PREVIEW@@ $line @${_time.elapsed.inMilliseconds}');
  }

  void _caption(String id) => _mark('caption $id');

  /// A sound cue, [delayMs] ahead of now when the gesture it belongs to
  /// lands after a hold.
  void _sfx(String type, [double? seconds, int delayMs = 0]) {
    if (!_time.running) return;
    final at = _time.elapsed.inMilliseconds + delayMs;
    debugPrint('@@PREVIEW@@ sfx $type'
        '${seconds == null ? '' : ' ${seconds.toStringAsFixed(2)}'} @$at');
  }

  /// Asks the composer to punch in [zoom]x on [center] (global logical
  /// coordinates), easing there unless [now].
  void _focus(Offset center, double zoom, {bool now = false}) {
    final screen = _screenSize;
    _mark('focus ${(center.dx / screen.width).toStringAsFixed(4)} '
        '${(center.dy / screen.height).toStringAsFixed(4)} '
        '${zoom.toStringAsFixed(2)}${now ? ' now' : ''}');
  }

  /// Eases the punch-in back out to the whole screen.
  void _unfocus() => _mark('focus off');

  /// Page [page]'s on-screen rect. The page is drawn by whichever of these
  /// is current (the editing layer collapses while a tool arms), so take the
  /// laid-out ones and remember the last good answer.
  Rect _page(int page) {
    final pages = <Rect>{
      for (final key in const [
        'pdf-editing-layer',
        'pdf-page-direct-picture',
        'pdf-page-slug-picture',
      ])
        ..._rectsOf(key).where((r) => r.width > 100 && r.height > 100),
    }.toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    if (pages.isNotEmpty) _lastPage = pages[math.min(page, pages.length - 1)];
    return _lastPage ?? (throw StateError('no page on screen'));
  }

  Rect? _lastPage;

  /// A PDF-space point on the top page on screen, in global coordinates.
  Offset _at(double x, double y) {
    final r = _page(0);
    return Offset(
      r.left + x / PreviewLayout.pageWidth * r.width,
      r.top +
          (PreviewLayout.pageHeight - y) / PreviewLayout.pageHeight * r.height,
    );
  }

  /// Opens the Tools sheet, switches to [group]'s tab and picks [key], then
  /// makes sure the sheet is out of the way (tool tiles leave it open).
  /// [color] picks that swatch from the sheet's palette first.
  Future<void> _chooseTool(String group, String key, {Color? color}) async {
    await hand.tap(await _waitFor('pdf-tools-handle'));
    _sfx('click');
    await _pause(350);
    await hand.tap(await _waitFor('pdf-group-tab-$group'));
    _sfx('tick');
    await _pause(300);
    // A one-tool group (Select) arms its tool from the tab and closes.
    if (_rectsOf('pdf-group-tab-$group').isEmpty) return;
    await hand.tap(await _waitFor(key));
    _sfx('tick');
    await _pause(300);
    if (color != null) {
      await hand.tap(await _waitForWidget(
          (w) => w is Container && _isSwatch(w.decoration, color)));
      _sfx('tick');
      await _pause(250);
    }
    // Markup tiles close the sheet themselves; give it time to slide away
    // before deciding to dismiss it through the scrim above it. Tool tiles
    // leave it up, so don't wait for those.
    for (var i = 0;
        key.startsWith('pdf-markup-') &&
            i < 8 &&
            _rectsOf('pdf-group-tab-$group').isNotEmpty;
        i++) {
      await _pause(60);
    }
    if (_rectsOf('pdf-group-tab-$group').isNotEmpty) {
      debugPrint('PREVIEW dismissing the tool sheet');
      await hand.tap(const Offset(24, 140));
      await _pause(350);
    }
  }

  Future<void> play() async {
    _probeKeys('initial');
    // Off camera: arm the yellow highlighter so the clip opens on an edit
    // already happening - viewers give a listing a few seconds at most.
    await _chooseTool('markup', 'pdf-markup-highlight');
    await hand.tap(await _waitFor('pdf-mobile-swatch-1'));
    hand.hide();
    await _pause(600);

    _start();

    // 1. Highlight a sentence - the clip opens punched in on it.
    _caption('highlight');
    final y = PreviewLayout.highlightBaseline + 4;
    _focus(
        _at((PreviewLayout.highlightFrom + PreviewLayout.highlightTo) / 2, y),
        1.75,
        now: true);
    await _pause(200);
    _sfx('highlight', 0.7, 560);
    await _edit(
        'the highlight',
        // On touch a drag scrolls; text selection is a long press on a word
        // that then extends by words as the finger moves - so press, hold,
        // and sweep, as a person would.
        () => hand.longPressDrag(
              _at(PreviewLayout.highlightFrom + 6, y),
              _at(PreviewLayout.highlightTo, y),
              const Duration(milliseconds: 650),
            ));
    await _pause(450);
    _unfocus();

    // 2. Fill the form field.
    _caption('fill');
    await _chooseTool('select', 'pdf-tool-select');
    final field = PreviewLayout.clientField;
    final fieldCenter =
        _at((field.left + field.right) / 2, (field.bottom + field.top) / 2);
    _focus(fieldCenter + const Offset(-40, 0), 1.85);
    // Typing is scripted, so take the system keyboard out of the loop: on
    // the phone it would slide up over the field (and the frame stamps).
    TextInput.setInputControl(null);
    await hand.tap(fieldCenter);
    _sfx('click');
    await _pause(250);
    _probeKeys('form field');
    await _type(PreviewLayout.clientName);
    await _pause(150);
    // Pull back first: the commit tap lands off to the side, and the locked
    // shot is framed around what the finger does while it is up.
    _unfocus();
    await _edit('the form fill', () => hand.tap(_at(540, 260)));
    TextInput.restorePlatformInputControl();
    await _pause(300);

    // 3. Organize: the page grid, then fling the appendix ahead of the budget.
    _caption('organize');
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await hand.tap(await _waitFor('pdf-shell-page-grid-toggle'));
    _sfx('swoosh', 0.6);
    await _pause(450);
    _probeKeys('page grid');
    await _edit('the page move', () => _reorder(from: 2, before: 1));
    // Hold on the new order: the grid swaps the pages in a single frame, so
    // the result needs a beat on screen to read as a move.
    hand.hide();
    await _pause(1200);
    _unfocus();
    await _pause(300);
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await hand.tap(await _waitFor('pdf-shell-view-mode-pages'));
    _sfx('swoosh', 0.5);
    await _pause(400);

    // 4. Sign: draw a signature on the signature pad, then drop it on the
    // signature line.
    _caption('sign');
    final pad = await _openSignaturePad();
    _focus(pad.center, 1.35);
    await _pause(250);
    // The pad starts in the last tool colour (the highlighter's yellow).
    await hand.tap(await _waitFor('pdf-signature-ink-1a3e8c'));
    _sfx('tick');
    await _pause(200);
    final strokes = _signature(pad.deflate(pad.shortestSide * 0.14));
    _sfx('pen', 1.0, 120);
    await hand.drag(strokes.first, const Duration(milliseconds: 1000),
        curve: Curves.easeInOutSine);
    _sfx('pen', 0.35, 120);
    await hand.drag(strokes.last, const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic);
    await _pause(250);
    await hand.tap(await _waitFor('pdf-signature-done'));
    _sfx('click');
    _unfocus();
    await _closeToolSheet('insert');
    await _pause(200);
    // Placed centred on the tap, so aim a little above the line.
    final line = _at(
        (PreviewLayout.signatureFrom + PreviewLayout.signatureTo) / 2,
        PreviewLayout.signatureLineY + 16);
    _focus(line, 1.8);
    await _pause(500);
    await _edit('the signature', () => hand.tap(line));
    _sfx('thunk');
    hand.hide();
    await _pause(700);
    // Pull back so the closing (poster) frame shows every edit on the page.
    _unfocus();
    await _pause(250);

    // The end frame: every edit on one page (also the poster frame).
    _caption('done');
    _sfx('ding');
    await _pause(1900);
    _mark('end');
    debugPrint('PREVIEW frame clock: ${_time.timeouts} frames counted '
        'without a raster report');
  }

  /// A slanted cursive signature fitted into [box] (global coordinates), as
  /// two pen strokes: joined loops of uneven height and width (a capital,
  /// then lower-case letters with two ascenders), then an underline flourish.
  List<List<Offset>> _signature(Rect box) {
    const letters = [
      (34.0, 16.0), (11.0, 9.0), (8.0, 8.0), (20.0, 10.0), (8.0, 7.0), //
      (10.0, 9.0), (26.0, 11.0), (8.0, 8.0), (7.0, 10.0),
    ];
    // Drawn y-up, then fitted into [box] (y-down) keeping its proportions.
    final name = <Offset>[];
    var x = 16.0;
    for (final (height, width) in letters) {
      for (var k = 0; k <= 18; k++) {
        final t = k / 18 * 2 * math.pi;
        final y = height * (1 - math.cos(t)) / 2;
        name.add(Offset(
            x + width * k / 18 - width * 0.45 * math.sin(t) + 0.3 * y, y));
      }
      x += width;
    }
    final end = x;
    final flourish = [
      for (var i = 0; i <= 26; i++)
        Offset(
            end + 6 - i / 26 * (end - 4), -9 - math.sin(i / 26 * math.pi) * 4),
    ];
    final all = [...name, ...flourish];
    final left = all.map((p) => p.dx).reduce(math.min);
    final right = all.map((p) => p.dx).reduce(math.max);
    final bottom = all.map((p) => p.dy).reduce(math.min);
    final top = all.map((p) => p.dy).reduce(math.max);
    final scale =
        math.min(box.width / (right - left), box.height / (top - bottom));
    final origin = box.center -
        Offset((right - left) * scale / 2, -(top - bottom) * scale / 2);
    Offset fit(Offset p) =>
        origin + Offset((p.dx - left) * scale, -(p.dy - bottom) * scale);
    return [name.map(fit).toList(), flourish.map(fit).toList()];
  }

  /// Opens Tools > Insert > Signature, which (with no signature saved yet)
  /// opens the signature pad; returns the pad's rect.
  Future<Rect> _openSignaturePad() async {
    await hand.tap(await _waitFor('pdf-tools-handle'));
    _sfx('click');
    await _pause(350);
    // The tab row scrolls sideways and Insert starts off the right edge:
    // swipe it into view, as a person would.
    await _waitFor('pdf-group-tab-markup');
    if (_rectsOf('pdf-group-tab-insert').isEmpty) {
      final row = _rectsOf('pdf-group-tab-markup').first;
      final width = _screenSize.width;
      await hand.drag([
        Offset(width * 0.85, row.center.dy),
        Offset(width * 0.3, row.center.dy),
      ], const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      await _pause(300);
    }
    await hand.tap(await _waitFor('pdf-group-tab-insert'));
    _sfx('tick');
    await _pause(300);
    _probeKeys('insert tools');
    await hand.tap(await _waitFor('pdf-tool-signature'));
    _sfx('tick');
    await _waitFor('pdf-signature-pad');
    return _rectsOf('pdf-signature-pad').first;
  }

  /// Dismisses the Tools sheet if a tool tile left it open (through the
  /// scrim above it), once the pad dialog is gone.
  Future<void> _closeToolSheet(String group) async {
    for (var i = 0; i < 30 && _rectsOf('pdf-signature-pad').isNotEmpty; i++) {
      await _pause(60);
    }
    await _pause(250);
    if (_rectsOf('pdf-group-tab-$group').isNotEmpty) {
      await hand.tap(const Offset(24, 140));
      await _pause(350);
    }
  }

  Future<void> _type(String text) async {
    // The inline editor opens a beat after the tap; wait for it.
    EditableTextState? editable;
    for (var i = 0; i < 50 && editable == null; i++) {
      editable = _editableText();
      if (editable == null) await _pause(60);
    }
    if (editable == null) throw StateError('the form editor never opened');
    if (!editable.widget.focusNode.hasFocus) {
      editable.widget.focusNode.requestFocus();
      await _pause(60);
    }
    _sfx('typing', text.length * 0.06);
    for (var i = 1; i <= text.length; i++) {
      final value = text.substring(0, i);
      editable.userUpdateTextEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
        SelectionChangedCause.keyboard,
      );
      await _pause(60);
    }
    // The field must show what was typed before it is committed.
    await _pause(60);
    if (editable.textEditingValue.text != text) {
      throw StateError('the form field shows '
          '"${editable.textEditingValue.text}", not "$text"');
    }
  }

  /// Long-presses grid cell [from] and flings it just ahead of [before],
  /// punched in on the two cells.
  Future<void> _reorder({required int from, required int before}) async {
    final source = _rectsOf('pdf-thumbnail-grid-cell-$from').first;
    final target = _rectsOf('pdf-thumbnail-grid-cell-$before').first;
    final drop = Offset(target.left + 6, target.center.dy);
    _focus(Offset.lerp(source.center, drop, 0.5)!, 1.3);
    _sfx('lift', null, 560);
    _sfx('swoosh', 0.4, 600);
    await hand.fling(source.center, drop);
    _sfx('thunk');
  }

  /// Waits for [key] to be on screen and settled (sheets slide in, so a
  /// rect must hold still across two polls before it is tapped).
  Future<Offset> _waitFor(String key) async {
    Rect? last;
    for (var i = 0; i < 100; i++) {
      final r = _rectsOf(key).firstOrNull;
      if (r != null && r == last) return r.center;
      last = r;
      await _pause(60);
    }
    _probeKeys('missing $key');
    throw StateError('$key never appeared');
  }

  /// The open tab's edit session.
  PdfEditingController get _session {
    PdfEditingController? found;
    void visit(Element e) {
      final w = e.widget;
      if (w is PdfEditorView && w.controller != null) found ??= w.controller;
      if (found == null) e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found ?? (throw StateError('no edit session'));
  }

  /// Runs [step] and fails the take unless it committed an edit: a preview
  /// that silently misses its highlight must not reach the store.
  Future<void> _edit(String what, Future<void> Function() step) async {
    final before = _session.revisionId;
    await step();
    for (var i = 0; i < 40 && _session.revisionId == before; i++) {
      await _pause(50);
    }
    if (_session.revisionId == before) throw StateError('$what did not land');
  }

  /// Like [_waitFor], for an unkeyed widget matching [test].
  Future<Offset> _waitForWidget(bool Function(Widget) test) async {
    Rect? last;
    for (var i = 0; i < 100; i++) {
      final r = _rectsWhere((_) => true, widget: test).firstOrNull;
      if (r != null && r == last) return r.center;
      last = r;
      await _pause(60);
    }
    throw StateError('widget never appeared');
  }

  static bool _isSwatch(Decoration? d, Color color) =>
      d is BoxDecoration &&
      d.shape == BoxShape.circle &&
      d.color?.toARGB32() == color.toARGB32();

  /// The form field's inline editor (keyed `pdf-form-text-editor`).
  EditableTextState? _editableText() {
    EditableTextState? found;
    void visit(Element e, bool inside) {
      if (found != null) return;
      final k = e.widget.key;
      inside = inside ||
          (k is ValueKey<String> && k.value == 'pdf-form-text-editor');
      if (inside && e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren((c) => visit(c, inside));
    }

    WidgetsBinding.instance.rootElement?.visitChildren((c) => visit(c, false));
    return found;
  }

  void _probeKeys(String step) {
    if (!_probe) return;
    debugPrint('PROBE --- $step');
    void visit(Element e) {
      final k = e.widget.key;
      final ro = e.renderObject;
      if (k is ValueKey && ro is RenderBox && ro.hasSize && ro.attached) {
        final o = ro.localToGlobal(Offset.zero);
        debugPrint('PROBE ${k.value} ${o.dx.round()},${o.dy.round()} '
            '${ro.size.width.round()}x${ro.size.height.round()}');
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

Size get _screenSize {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
}

Future<void> _pause(int ms) => _time.wait(Duration(milliseconds: ms));

/// The tour's clock.
final _time = _FrameClock();

/// Frame time: once [start]ed, every frame the app draws is stamped exactly
/// one [period] after the last, for the app's animations (the engine's frame
/// timestamp is replaced) and for the tour's own pauses and motion alike.
///
/// The simulator only runs debug builds, and on a CI runner those stall:
/// typing into a field or picking up a page thumbnail can hold the UI thread
/// for a second or two. Timed by the wall clock, a stall is a freeze and a
/// jump in the recording. Timed by frames, the app's world stands still while
/// it catches up, so the recording loses nothing - it just takes longer. Each
/// frame paints its number ([stamp]) along the bottom edge, and the composer
/// places every captured frame by it.
///
/// A frame counts only once the last counted one has been rasterised (the
/// engine's [FrameTiming] report names its frame number) and then on screen
/// for [minInterval] of wall-clock time. The UI thread can run well ahead of
/// a debug build's raster thread, and the engine then never shows the frames
/// in between; and `simctl io recordVideo` keeps up with about 16 fps on a CI
/// runner, so record_ios.py sets `PREVIEW_FRAME_MS=100`. This also keeps tour
/// time from running ahead of the real timers the gesture recognisers use (a
/// long press is 500 ms of real time). A frame that comes sooner redraws the
/// same instant and keeps its number.
class _FrameClock {
  static const fps = 30;
  static const period = Duration(microseconds: 1000000 ~/ fps);
  static const minInterval = Duration(
      milliseconds: int.fromEnvironment('PREVIEW_FRAME_MS', defaultValue: 34));

  /// How long to wait for the engine to report a counted frame rasterised
  /// before counting the next one anyway.
  static const rasterTimeout = Duration(seconds: 2);

  /// The number of the frame being drawn, null before the tour.
  final stamp = ValueNotifier<int?>(null);

  final _real = Stopwatch()..start();
  final _sinceCounted = Stopwatch();
  final _onScreen = Stopwatch();
  final _waiting = <(int, Completer<void>)>[];
  bool _running = false;
  int _frame = 0;
  Duration _engineBase = Duration.zero;
  Duration _realBase = Duration.zero;
  Timer? _tick;

  /// The engine frame number of the last counted frame until the engine
  /// reports it (or a later frame) rasterised.
  int? _awaitingRaster;
  int _timeouts = 0;

  bool get running => _running;

  /// Tour time: frames drawn since [start], times [period].
  Duration get elapsed => period * _frame;

  /// A monotonic timestamp for pointer events and motion, wall-clock until
  /// [start] and frame time after.
  Duration get now => _running ? _realBase + elapsed : _real.elapsed;

  /// Counted frames that went out without a raster report.
  int get timeouts => _timeouts;

  /// Saves a counted frame once it is drawn; the next frame waits for it.
  Future<void> Function(int frame)? capture;
  bool _capturing = false;

  /// Whether the next frame may count: the last one has been on screen for
  /// [minInterval] (rasterised, as the engine reports it), or the report is
  /// overdue.
  bool get _ready {
    if (_capturing) return false;
    if (!_sinceCounted.isRunning) return true;
    if (_sinceCounted.elapsed < minInterval) return false;
    if (_awaitingRaster == null) return _onScreen.elapsed >= minInterval;
    if (_sinceCounted.elapsed < rasterTimeout) return false;
    _timeouts++;
    return true;
  }

  void start() {
    final binding = SchedulerBinding.instance;
    final dispatcher = binding.platformDispatcher;
    final FrameCallback begin = dispatcher.onBeginFrame!;
    final VoidCallback draw = dispatcher.onDrawFrame!;
    _engineBase = binding.currentSystemFrameTimeStamp;
    _realBase = _real.elapsed;
    _running = true;
    binding.addTimingsCallback(_onTimings);
    dispatcher.onBeginFrame = (_) {
      // A frame that may not count yet redraws the current instant.
      if (!_ready) {
        begin(_engineBase + period * _frame);
        return;
      }
      _sinceCounted
        ..reset()
        ..start();
      final number = dispatcher.frameData.frameNumber;
      // Without frame numbers (the web), only the interval paces frames.
      _awaitingRaster = number < 0 ? null : number;
      if (_awaitingRaster == null) {
        _onScreen
          ..reset()
          ..start();
      }
      stamp.value = _frame;
      begin(_engineBase + period * (_frame + 1));
      _counted = true;
    };
    dispatcher.onDrawFrame = () {
      draw();
      if (!_counted) return _keepDrawing();
      _counted = false;
      final save = capture;
      if (save != null) {
        _capturing = true;
        save(_frame).whenComplete(() {
          _capturing = false;
          _keepDrawing();
        });
      }
      _frame++;
      _waiting.removeWhere((w) {
        if (w.$1 > _frame) return false;
        w.$2.complete();
        return true;
      });
      _keepDrawing();
    };
    binding.scheduleFrame();
  }

  /// Whether the frame in flight is a counted one.
  bool _counted = false;

  void _onTimings(List<FrameTiming> timings) {
    final awaiting = _awaitingRaster;
    if (awaiting == null) return;
    // The counted frame, or a later redraw of the same instant, is on screen.
    if (timings.any((t) => t.frameNumber >= awaiting)) {
      _awaitingRaster = null;
      _onScreen
        ..reset()
        ..start();
      _keepDrawing();
    }
  }

  /// Asks for the next frame once the last counted one has been on screen
  /// for [minInterval], so the clock ticks even while nothing moves. While
  /// a raster report is pending, it only checks back at the timeout.
  void _keepDrawing() {
    _tick?.cancel();
    final due = _awaitingRaster != null
        ? rasterTimeout - _sinceCounted.elapsed
        : minInterval - _onScreen.elapsed;
    _tick = Timer(due.isNegative ? Duration.zero : due,
        SchedulerBinding.instance.scheduleFrame);
  }

  /// Completes after [d] of tour time (wall-clock time before [start]).
  Future<void> wait(Duration d) {
    if (!_running) return Future<void>.delayed(d);
    final frames =
        math.max(1, (d.inMicroseconds / period.inMicroseconds).ceil());
    final done = Completer<void>();
    _waiting.add((_frame + frames, done));
    return done.future;
  }

  /// Completes when the next frame has been drawn.
  Future<void> nextFrame() => wait(period);
}

/// Paints [stamp] along the bottom edge: 16 cells across the screen, 4
/// logical pixels tall - white, black (the composer's references), 13 bits of
/// frame number (least significant first) and their parity.
class _StampPainter extends CustomPainter {
  _StampPainter(this.stamp) : super(repaint: stamp);
  final ValueNotifier<int?> stamp;

  static const height = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = stamp.value;
    if (n == null) return;
    var parity = 0;
    final cells = <bool>[true, false];
    for (var i = 0; i < 13; i++) {
      final bit = (n >> i) & 1 == 1;
      if (bit) parity ^= 1;
      cells.add(bit);
    }
    cells.add(parity == 1);
    final w = size.width / cells.length;
    final top = size.height - height;
    for (var i = 0; i < cells.length; i++) {
      canvas.drawRect(
          Rect.fromLTWH(i * w, top, w + 0.5, height),
          Paint()
            ..color =
                cells[i] ? const Color(0xFFFFFFFF) : const Color(0xFF000000));
    }
  }

  @override
  bool shouldRepaint(_StampPainter old) => false;
}

List<Rect> _rectsOf(String key) =>
    _rectsWhere((k) => k is ValueKey<String> && k.value == key);

/// Global rects of the visible, laid-out widgets whose key matches [test],
/// optionally only those inside the widget keyed [under].
List<Rect> _rectsWhere(bool Function(Key key) test,
    {String? under, bool Function(Widget)? widget}) {
  final out = <Rect>[];
  final screen = Offset.zero &
      (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
          WidgetsBinding
              .instance.platformDispatcher.views.first.devicePixelRatio);
  void visit(Element e, bool inside) {
    final k = e.widget.key;
    inside = inside || (k is ValueKey<String> && k.value == under);
    if (inside && (widget != null ? widget(e.widget) : k != null && test(k))) {
      final ro = e.renderObject;
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        final rect = ro.localToGlobal(Offset.zero) & ro.size;
        if (rect.overlaps(screen)) out.add(rect);
      }
    }
    e.visitChildren((c) => visit(c, inside));
  }

  WidgetsBinding.instance.rootElement
      ?.visitChildren((c) => visit(c, under == null));
  return out;
}

/// The on-screen fingertip, plus the ripple a tap leaves behind.
class _Finger extends ChangeNotifier {
  Offset? position;
  bool down = false;

  /// Where the last tap landed and how far its ripple has spread (0..1).
  Offset? rippleAt;
  double ripple = 1;

  void update(Offset? p, {required bool down}) {
    position = p;
    this.down = down;
    notifyListeners();
  }

  void setRipple(Offset at, double t) {
    rippleAt = at;
    ripple = t;
    notifyListeners();
  }
}

class _FingerPainter extends CustomPainter {
  _FingerPainter(this.finger) : super(repaint: finger);
  final _Finger finger;

  @override
  void paint(Canvas canvas, Size size) {
    final at = finger.rippleAt;
    if (at != null && finger.ripple < 1) {
      final t = Curves.easeOutCubic.transform(finger.ripple);
      canvas.drawCircle(
          at,
          20 + 26 * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - t) + 0.5
            ..color = Color.fromRGBO(255, 255, 255, 0.85 * (1 - t)));
    }
    final p = finger.position;
    if (p == null) return;
    final r = finger.down ? 17.0 : 22.0;
    canvas
      ..drawCircle(
          p,
          r + 2,
          Paint()
            ..color = const Color(0x33000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4))
      ..drawCircle(
          p,
          r,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, finger.down ? 0.8 : 0.55))
      ..drawCircle(
          p,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0x55000000));
  }

  @override
  bool shouldRepaint(_FingerPainter old) => false;
}

/// Runs [step] once a frame with eased progress 0..1 over [duration] of tour
/// time (frame time, see [_FrameClock]).
Future<void> _animate(Duration duration, void Function(double t) step,
    {Curve curve = Curves.easeInOutCubic}) async {
  final start = _time.now;
  final total = duration.inMicroseconds;
  while (true) {
    final u = total == 0 ? 1.0 : (_time.now - start).inMicroseconds / total;
    step(curve.transform(u.clamp(0.0, 1.0)));
    if (u >= 1) return;
    await _time.nextFrame();
  }
}

/// A quadratic Bézier from [a] to [b] that bows sideways by [bow] of its
/// length - a hand moves in arcs, not rulers.
Offset _arc(Offset a, Offset b, double t, {double bow = 0.16}) {
  final d = b - a;
  final normal = Offset(-d.dy, d.dx);
  final control = Offset.lerp(a, b, 0.5)! + normal * bow;
  final u = 1 - t;
  return a * (u * u) + control * (2 * u * t) + b * (t * t);
}

/// Delivers real touch events through the gesture pipeline.
class _Hand {
  _Hand(this.finger);
  final _Finger finger;

  int _pointer = 1000;
  Offset _rest = Offset.zero;
  bool _shown = false;

  Duration get _now => _time.now;

  /// Told where the fingertip is (null when lifted away) and whether it
  /// touches, so the composer can frame the punch-ins around it.
  void Function(Offset? position, bool down)? onMove;

  void _move(Offset? p, {required bool down}) {
    finger.update(p, down: down);
    onMove?.call(p, down);
  }

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  /// Swings the (lifted) fingertip to [to] on an arc, quicker for short hops.
  Future<void> _approach(Offset to) async {
    if (!_shown) {
      _rest = to + const Offset(60, 140);
      _shown = true;
    }
    final from = _rest;
    final ms = (140 + (to - from).distance * 0.45).clamp(140, 360).round();
    await _animate(Duration(milliseconds: ms),
        (t) => _move(_arc(from, to, t), down: false));
    _rest = to;
  }

  /// Lifts the fingertip off screen; the next touch swings in again.
  void hide() {
    _move(null, down: false);
    _shown = false;
  }

  void _rippleAt(Offset at) => unawaited(_animate(
      const Duration(milliseconds: 420), (t) => finger.setRipple(at, t),
      curve: Curves.linear));

  Future<void> tap(Offset at) async {
    await _approach(at);
    final pointer = ++_pointer;
    _move(at, down: true);
    _rippleAt(at);
    _send(PointerDownEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    // Real time, not tour time: the recognisers time a press by the wall
    // clock, and on the simulator 70 ms of tour time can take most of a
    // second - long enough to read as a long press.
    await Future<void>.delayed(const Duration(milliseconds: 70));
    _send(PointerUpEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    _move(at, down: false);
    await _pause(90);
  }

  /// Presses at [path]'s start, optionally holds, then traces [path] over
  /// [duration] (by arc length, eased by [curve]) and lifts.
  Future<void> drag(List<Offset> path, Duration duration,
      {Duration hold = Duration.zero,
      Duration settle = const Duration(milliseconds: 50),
      Curve curve = Curves.easeInOutCubic}) async {
    await _approach(path.first);
    final pointer = ++_pointer;
    var last = path.first;
    _move(last, down: true);
    _rippleAt(last);
    _send(PointerDownEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    if (hold > Duration.zero) await _time.wait(hold);
    final lengths = <double>[0];
    for (var i = 1; i < path.length; i++) {
      lengths.add(lengths.last + (path[i] - path[i - 1]).distance);
    }
    final total = lengths.last;
    var segment = 1;
    await _animate(duration, (t) {
      final s = t * total;
      while (segment < path.length - 1 && lengths[segment] < s) {
        segment++;
      }
      final a = path[segment - 1], b = path[segment];
      final span = lengths[segment] - lengths[segment - 1];
      final local = span == 0 ? 1.0 : (s - lengths[segment - 1]) / span;
      final p = Offset.lerp(a, b, local.clamp(0.0, 1.0))!;
      if (p == last) return;
      _send(PointerMoveEvent(
          pointer: pointer,
          position: p,
          delta: p - last,
          kind: PointerDeviceKind.touch,
          timeStamp: _now));
      _move(p, down: true);
      last = p;
    }, curve: curve);
    await _time.wait(settle);
    _send(PointerUpEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    _move(last, down: false);
    _rest = last;
  }

  /// Press, hold past the long-press threshold (500 ms), then sweep.
  Future<void> longPressDrag(Offset from, Offset to, Duration duration) =>
      drag([from, to], duration, hold: const Duration(milliseconds: 560));

  /// Picks something up and throws it to [to]: hold past the long-press
  /// threshold, a quick arcing flick that overshoots a little, then a settle
  /// back onto the target before letting go.
  Future<void> fling(Offset from, Offset to) {
    final dir = to - from;
    final unit = dir / math.max(dir.distance, 1);
    final overshoot = to + unit * 14;
    final path = <Offset>[
      for (var i = 0; i <= 24; i++) _arc(from, overshoot, i / 24, bow: 0.22),
      to,
    ];
    return drag(path, const Duration(milliseconds: 520),
        hold: const Duration(milliseconds: 560),
        settle: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic);
  }
}

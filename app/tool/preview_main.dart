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
//   @@PREVIEW@@ start            the tour is about to begin (start the clip)
//   @@PREVIEW@@ caption <id>     a chapter begins (tool/preview/compose_preview.py
//                                titles it)
//   @@PREVIEW@@ sfx <type> [s]   a sound cue (soundtrack.py voice, duration)
//   @@PREVIEW@@ end              the tour is over (end the clip)
//   @@PREVIEW_DONE@@             the host can stop recording and quit
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

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart' show materialThemeMode;
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/keyboard_availability.dart';
import 'package:dart_pdf_editor_app/l10n/app_delegates.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_editor_app/window_support.dart';

import 'preview_document.dart';

/// Milliseconds to wait for the document to open, render and extract its text
/// (the highlighter snaps to it) before the tour starts.
const _warmupMs = int.fromEnvironment('PREVIEW_WARMUP_MS', defaultValue: 8000);

/// Prints the keyed controls on screen at each step, for adapting the tour to
/// a new layout: `--dart-define=PREVIEW_PROBE=true`.
const _probe = bool.fromEnvironment('PREVIEW_PROBE');

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
    final hand = _Hand(_finger);
    try {
      await _Tour(hand).play();
    } catch (error, stack) {
      debugPrint('@@PREVIEW@@ error $error');
      debugPrint('$stack');
    }
    debugPrint('@@PREVIEW_DONE@@');
  }

  @override
  Widget build(BuildContext context) {
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
      ]),
    );
  }
}

/// The storyboard. Each chapter announces its caption, then works the app.
class _Tour {
  _Tour(this.hand);
  final _Hand hand;

  final _clock = Stopwatch();

  void _mark(String line) {
    // Nothing before the clip starts is heard or titled.
    if (!_clock.isRunning) return;
    debugPrint('@@PREVIEW@@ $line @${_clock.elapsedMilliseconds}');
  }

  void _caption(String id) => _mark('caption $id');
  void _sfx(String type, [double? seconds]) => _mark(
      'sfx $type${seconds == null ? '' : ' ${seconds.toStringAsFixed(2)}'}');

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
    await _pause(550);
    await hand.tap(await _waitFor('pdf-group-tab-$group'));
    _sfx('tick');
    await _pause(400);
    // A one-tool group (Select) arms its tool from the tab and closes.
    if (_rectsOf('pdf-group-tab-$group').isEmpty) return;
    await hand.tap(await _waitFor(key));
    _sfx('tick');
    await _pause(450);
    if (color != null) {
      await hand.tap(await _waitForWidget(
          (w) => w is Container && _isSwatch(w.decoration, color)));
      _sfx('tick');
      await _pause(350);
    }
    // Some tiles close the sheet themselves; give it time to slide away
    // before deciding to dismiss it through the scrim above it.
    for (var i = 0;
        i < 15 && _rectsOf('pdf-group-tab-$group').isNotEmpty;
        i++) {
      await _pause(60);
    }
    if (_rectsOf('pdf-group-tab-$group').isNotEmpty) {
      debugPrint('PREVIEW dismissing the tool sheet');
      await hand.tap(const Offset(24, 140));
      await _pause(450);
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

    _clock.start();
    _mark('start');

    // 1. Highlight a sentence.
    _caption('highlight');
    final y = PreviewLayout.highlightBaseline + 4;
    await _pause(250);
    _sfx('highlight', 0.8);
    await _edit(
        'the highlight',
        () => hand.drag([
              _at(PreviewLayout.highlightFrom, y),
              _at(PreviewLayout.highlightTo, y),
            ], const Duration(milliseconds: 800)));
    await _pause(900);

    // 2. Fill the form field.
    _caption('fill');
    await _chooseTool('select', 'pdf-tool-select');
    final field = PreviewLayout.clientField;
    await hand.tap(
        _at((field.left + field.right) / 2, (field.bottom + field.top) / 2));
    _sfx('click');
    await _pause(500);
    _probeKeys('form field');
    await _type(PreviewLayout.clientName);
    await _pause(400);
    await _edit('the form fill', () => hand.tap(_at(540, 260)));
    await _pause(700);

    // 3. Organize: the page grid, then drag the appendix ahead of the budget.
    _caption('organize');
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await hand.tap(await _waitFor('pdf-shell-page-grid-toggle'));
    _sfx('swoosh', 0.6);
    await _pause(1000);
    _probeKeys('page grid');
    await _edit('the page move', () => _reorder(from: 2, before: 1));
    await _pause(1100);
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await hand.tap(await _waitFor('pdf-shell-view-mode-pages'));
    _sfx('swoosh', 0.5);
    await _pause(900);

    // 4. Sign with a finger on the signature line.
    _caption('sign');
    await _chooseTool('draw', 'pdf-tool-ink', color: _signatureInk);
    _probeKeys('ink tool');
    _sfx('pen', 1.3);
    await _edit('the signature',
        () => hand.drag(_signature(), const Duration(milliseconds: 1500)));
    hand.hide();
    await _pause(600);

    // The end frame: every edit on one page (also the poster frame).
    _caption('done');
    _sfx('ding');
    await _pause(2600);
    _mark('end');
  }

  /// A slanted cursive signature over the signature line, in global
  /// coordinates: joined loops of uneven height and width (a capital, then
  /// lower-case letters with two ascenders) and an underline flourish.
  List<Offset> _signature() {
    const base = PreviewLayout.signatureLineY + 4;
    const letters = [
      (34.0, 16.0), (11.0, 9.0), (8.0, 8.0), (20.0, 10.0), (8.0, 7.0), //
      (10.0, 9.0), (26.0, 11.0), (8.0, 8.0), (7.0, 10.0),
    ];
    final points = <Offset>[];
    var x = PreviewLayout.signatureFrom + 16;
    for (final (height, width) in letters) {
      for (var k = 0; k <= 18; k++) {
        final t = k / 18 * 2 * math.pi;
        final y = height * (1 - math.cos(t)) / 2;
        points.add(_at(
            x + width * k / 18 - width * 0.45 * math.sin(t) + 0.3 * y,
            base + y));
      }
      x += width;
    }
    final end = x;
    for (var i = 1; i <= 26; i++) {
      final t = i / 26;
      points.add(_at(end + 6 - t * (end - PreviewLayout.signatureFrom - 4),
          base - 5 - math.sin(t * math.pi) * 4));
    }
    return points;
  }

  Future<void> _type(String text) async {
    final editable = _editableText();
    if (editable == null) {
      _mark('error no text field');
      return;
    }
    _sfx('typing', text.length * 0.085);
    for (var i = 1; i <= text.length; i++) {
      final value = text.substring(0, i);
      editable.userUpdateTextEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
        SelectionChangedCause.keyboard,
      );
      await _pause(85);
    }
  }

  /// Long-presses grid cell [from] and drops it just ahead of [before].
  Future<void> _reorder({required int from, required int before}) async {
    final source = _rectsOf('pdf-thumbnail-grid-cell-$from').first;
    final target = _rectsOf('pdf-thumbnail-grid-cell-$before').first;
    _sfx('lift');
    await hand.longPressDrag(
      source.center,
      Offset(target.left + 6, target.center.dy),
      const Duration(milliseconds: 1000),
    );
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

  EditableTextState? _editableText() {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        final state = e.state as EditableTextState;
        if (state.widget.focusNode.hasFocus) found = state;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
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

/// The toolbar palette's blue, for the signature.
const _signatureInk = Color(0xFF1E88E5);

Future<void> _pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

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

/// The on-screen fingertip.
class _Finger extends ChangeNotifier {
  Offset? position;
  bool down = false;

  void update(Offset? p, {required bool down}) {
    position = p;
    this.down = down;
    notifyListeners();
  }
}

class _FingerPainter extends CustomPainter {
  _FingerPainter(this.finger) : super(repaint: finger);
  final _Finger finger;

  @override
  void paint(Canvas canvas, Size size) {
    final p = finger.position;
    if (p == null) return;
    final r = finger.down ? 19.0 : 22.0;
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
            ..color = Color.fromRGBO(255, 255, 255, finger.down ? 0.75 : 0.55))
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

/// Delivers real touch events through the gesture pipeline.
class _Hand {
  _Hand(this.finger);
  final _Finger finger;

  int _pointer = 1000;
  final _clock = Stopwatch()..start();
  Offset _rest = Offset.zero;
  bool _shown = false;

  Duration get _now => _clock.elapsed;

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  /// Glides the (lifted) fingertip to [to] so taps don't teleport.
  Future<void> _approach(Offset to) async {
    if (!_shown) {
      _rest = to + const Offset(40, 90);
      _shown = true;
    }
    const steps = 14;
    final from = _rest;
    for (var i = 1; i <= steps; i++) {
      final t = Curves.easeInOut.transform(i / steps);
      finger.update(Offset.lerp(from, to, t), down: false);
      await _pause(16);
    }
    _rest = to;
  }

  /// Lifts the fingertip off screen; the next touch glides in again.
  void hide() {
    finger.update(null, down: false);
    _shown = false;
  }

  Future<void> tap(Offset at) async {
    await _approach(at);
    final pointer = ++_pointer;
    finger.update(at, down: true);
    _send(PointerDownEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    await _pause(90);
    _send(PointerUpEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    finger.update(at, down: false);
    await _pause(120);
  }

  Future<void> drag(List<Offset> path, Duration duration,
      {Duration hold = Duration.zero}) async {
    await _approach(path.first);
    final pointer = ++_pointer;
    var last = path.first;
    finger.update(last, down: true);
    _send(PointerDownEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    if (hold > Duration.zero) await Future<void>.delayed(hold);
    // Resample the polyline by arc length at ~60 Hz.
    final lengths = <double>[0];
    for (var i = 1; i < path.length; i++) {
      lengths.add(lengths.last + (path[i] - path[i - 1]).distance);
    }
    final total = lengths.last;
    final frames = math.max(2, duration.inMilliseconds ~/ 16);
    var segment = 1;
    for (var f = 1; f <= frames; f++) {
      final s = Curves.easeInOut.transform(f / frames) * total;
      while (segment < path.length - 1 && lengths[segment] < s) {
        segment++;
      }
      final a = path[segment - 1], b = path[segment];
      final span = lengths[segment] - lengths[segment - 1];
      final local = span == 0 ? 1.0 : (s - lengths[segment - 1]) / span;
      final p = Offset.lerp(a, b, local.clamp(0.0, 1.0))!;
      _send(PointerMoveEvent(
          pointer: pointer,
          position: p,
          delta: p - last,
          kind: PointerDeviceKind.touch,
          timeStamp: _now));
      finger.update(p, down: true);
      last = p;
      await _pause(16);
    }
    await _pause(60);
    _send(PointerUpEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    finger.update(last, down: false);
    _rest = last;
  }

  /// Press, hold past the long-press threshold, then drag.
  Future<void> longPressDrag(Offset from, Offset to, Duration duration) =>
      drag([from, to], duration, hold: const Duration(milliseconds: 650));
}

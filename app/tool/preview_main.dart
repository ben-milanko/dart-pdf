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
import 'package:flutter/services.dart';
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
const _warmupMs = int.fromEnvironment('PREVIEW_WARMUP_MS', defaultValue: 12000);

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

  /// A sound cue, [delayMs] ahead of now when the gesture it belongs to
  /// lands after a hold.
  void _sfx(String type, [double? seconds, int delayMs = 0]) {
    if (!_clock.isRunning) return;
    final at = _clock.elapsedMilliseconds + delayMs;
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

    _clock.start();
    _mark('start');

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
    await hand.tap(fieldCenter);
    _sfx('click');
    // Typing is scripted, so the soft keyboard would only cover the shot.
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    await _pause(250);
    _probeKeys('form field');
    await _type(PreviewLayout.clientName);
    await _pause(150);
    await _edit('the form fill', () => hand.tap(_at(540, 260)));
    _unfocus();
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
    await _pause(550);
    _unfocus();
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await hand.tap(await _waitFor('pdf-shell-view-mode-pages'));
    _sfx('swoosh', 0.5);
    await _pause(400);

    // 4. Sign with a finger on the signature line.
    _caption('sign');
    await _chooseTool('draw', 'pdf-tool-ink', color: _signatureInk);
    _probeKeys('ink tool');
    _focus(
        _at((PreviewLayout.signatureFrom + PreviewLayout.signatureTo) / 2 - 20,
            PreviewLayout.signatureLineY + 14),
        1.8);
    await _pause(250);
    _sfx('pen', 1.15, 200);
    await _edit(
        'the signature',
        () => hand.drag(_signature(), const Duration(milliseconds: 1150),
            curve: Curves.easeInOutSine));
    hand.hide();
    await _pause(250);
    // Pull back so the closing (poster) frame shows every edit on the page.
    _unfocus();
    await _pause(250);

    // The end frame: every edit on one page (also the poster frame).
    _caption('done');
    _sfx('ding');
    await _pause(1900);
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

Size get _screenSize {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
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

/// Runs [step] with eased progress 0..1 over [duration] of wall-clock time.
///
/// Motion is timed by the clock, not by counting frames: a debug build on the
/// simulator draws slowly, and frame-counted motion stretched to match.
Future<void> _animate(Duration duration, void Function(double t) step,
    {Curve curve = Curves.easeInOutCubic}) async {
  final clock = Stopwatch()..start();
  final total = duration.inMicroseconds;
  while (true) {
    final u = total == 0 ? 1.0 : clock.elapsedMicroseconds / total;
    step(curve.transform(u.clamp(0.0, 1.0)));
    if (u >= 1) return;
    await _pause(8);
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
  final _clock = Stopwatch()..start();
  Offset _rest = Offset.zero;
  bool _shown = false;

  Duration get _now => _clock.elapsed;

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
        (t) => finger.update(_arc(from, to, t), down: false));
    _rest = to;
  }

  /// Lifts the fingertip off screen; the next touch swings in again.
  void hide() {
    finger.update(null, down: false);
    _shown = false;
  }

  void _rippleAt(Offset at) => unawaited(_animate(
      const Duration(milliseconds: 420), (t) => finger.setRipple(at, t),
      curve: Curves.linear));

  Future<void> tap(Offset at) async {
    await _approach(at);
    final pointer = ++_pointer;
    finger.update(at, down: true);
    _rippleAt(at);
    _send(PointerDownEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    await _pause(70);
    _send(PointerUpEvent(
        pointer: pointer,
        position: at,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    finger.update(at, down: false);
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
    finger.update(last, down: true);
    _rippleAt(last);
    _send(PointerDownEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    if (hold > Duration.zero) await Future<void>.delayed(hold);
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
      finger.update(p, down: true);
      last = p;
    }, curve: curve);
    await Future<void>.delayed(settle);
    _send(PointerUpEvent(
        pointer: pointer,
        position: last,
        kind: PointerDeviceKind.touch,
        timeStamp: _now));
    finger.update(last, down: false);
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

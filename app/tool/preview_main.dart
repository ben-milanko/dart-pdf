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
//   @@PREVIEW@@ start            the tour is about to begin (start the clip)
//   @@PREVIEW@@ caption <id>     a chapter begins (compose_preview.py titles it)
//   @@PREVIEW@@ sfx <type> [s]   a sound cue (soundtrack.py voice, duration)
//   @@PREVIEW@@ end              the tour is over (end the clip)
//   @@PREVIEW_DONE@@             the host can stop recording and quit
//
// tool/preview/record_preview.sh drives it on the iOS simulator; or by hand:
//
//   fvm flutter run -d <device> --release -t tool/preview_main.dart
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

/// Seconds to wait for the document to open and render before the tour starts.
const _warmupMs = int.fromEnvironment('PREVIEW_WARMUP_MS', defaultValue: 4000);

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

  void _mark(String line) =>
      debugPrint('@@PREVIEW@@ $line @${_clock.elapsedMilliseconds}');

  void _caption(String id) => _mark('caption $id');
  void _sfx(String type, [double? seconds]) => _mark(
      'sfx $type${seconds == null ? '' : ' ${seconds.toStringAsFixed(2)}'}');

  /// Page [page]'s on-screen rect, from its editing layer.
  Rect _page(int page) {
    final layers = _rectsOf('pdf-editing-layer')
      ..sort((a, b) => a.top.compareTo(b.top));
    if (layers.isEmpty) throw StateError('no page on screen');
    return layers[math.min(page, layers.length - 1)];
  }

  /// A PDF-space point on the top page on screen, in global coordinates.
  Offset _at(double x, double y) {
    final r = _page(0);
    return Offset(
      r.left + x / PreviewLayout.pageWidth * r.width,
      r.top +
          (PreviewLayout.pageHeight - y) / PreviewLayout.pageHeight * r.height,
    );
  }

  Future<void> _chooseTool(String key) async {
    await hand.tap(await _waitFor('pdf-tools-handle'));
    _sfx('click');
    await _pause(650);
    await hand.tap(await _waitFor(key));
    _sfx('tick');
    await _pause(500);
  }

  Future<void> play() async {
    _probeKeys('initial');
    _clock.start();
    _mark('start');

    // 1. Open: the document is already open; a short read of the page.
    _caption('open');
    _sfx('shimmer', 2.0);
    await _pause(1700);

    // 2. Highlight a sentence with the highlighter.
    _caption('highlight');
    await _chooseTool('pdf-markup-highlight');
    _probeKeys('highlight tool');
    _sfx('highlight', 0.8);
    final y = PreviewLayout.highlightBaseline + 4;
    await hand.drag([
      _at(PreviewLayout.highlightFrom, y),
      _at(PreviewLayout.highlightTo, y),
    ], const Duration(milliseconds: 800));
    await _pause(900);

    // 3. Fill the form field.
    _caption('fill');
    await _chooseTool('pdf-tool-select');
    final field = PreviewLayout.clientField;
    await hand.tap(
        _at((field.left + field.right) / 2, (field.bottom + field.top) / 2));
    _sfx('click');
    await _pause(500);
    _probeKeys('form field');
    await _type(PreviewLayout.clientName);
    await _pause(400);
    await hand.tap(_at(540, 260));
    await _pause(700);

    // 4. Sign with a finger on the signature line.
    _caption('sign');
    await _chooseTool('pdf-tool-ink');
    _sfx('pen', 1.1);
    await hand.drag(
      _signature(),
      const Duration(milliseconds: 1300),
    );
    await _pause(1100);

    // 5. Reorder: open the pages panel and drag the appendix up front.
    _caption('organize');
    await _openPages();
    _probeKeys('pages');
    await _reorder(from: 2, to: 0);
    await _pause(1300);

    _caption('done');
    _sfx('ding');
    await _pause(2200);
    _mark('end');
  }

  /// A cursive-ish signature over the signature line, in global coordinates.
  List<Offset> _signature() {
    final base = PreviewLayout.signatureLineY + 6;
    const x0 = PreviewLayout.signatureFrom + 12;
    final points = <Offset>[];
    for (var i = 0; i <= 90; i++) {
      final t = i / 90;
      final x = x0 + t * 190;
      final loops = math.sin(t * math.pi * 7) * 9 * (1 - 0.4 * t);
      final lift = math.sin(t * math.pi) * 8;
      points.add(
          _at(x + math.cos(t * math.pi * 7) * 5, base + 10 + loops + lift));
    }
    // A flourish underline back to the left.
    for (var i = 0; i <= 24; i++) {
      final t = i / 24;
      points.add(_at(x0 + 200 - t * 170, base - 2 - math.sin(t * math.pi) * 3));
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

  Future<void> _openPages() async {
    await hand.tap(await _waitFor('pdf-shell-controls'));
    _sfx('click');
    await _pause(700);
    _probeKeys('controls menu');
    final entry = _rectsOf('pdf-command-panel-pages').firstOrNull ??
        _rectsOf('panel-pages').firstOrNull;
    if (entry == null) throw StateError('no Pages entry in the menu');
    await hand.tap(entry.center);
    _sfx('swoosh', 0.6);
    await _pause(1200);
  }

  Future<void> _reorder({required int from, required int to}) async {
    await _waitFor('pdf-thumbnail-list');
    Rect tile(int index) => _rectsWhere(
          (k) => k is ValueKey<int> && k.value == index,
          under: 'pdf-thumbnail-list',
        ).first;
    // Scroll the strip so the dragged tile is reachable, then lift it.
    final source = tile(from);
    final target = tile(to);
    _sfx('lift');
    await hand.longPressDrag(
      source.center,
      Offset(target.center.dx, target.top + 8),
      const Duration(milliseconds: 1100),
    );
    _sfx('thunk');
  }

  Future<Offset> _waitFor(String key) async {
    for (var i = 0; i < 100; i++) {
      final r = _rectsOf(key).firstOrNull;
      if (r != null) return r.center;
      await _pause(50);
    }
    throw StateError('$key never appeared');
  }

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

Future<void> _pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

List<Rect> _rectsOf(String key) =>
    _rectsWhere((k) => k is ValueKey<String> && k.value == key);

/// Global rects of the visible, laid-out widgets whose key matches [test],
/// optionally only those inside the widget keyed [under].
List<Rect> _rectsWhere(bool Function(Key key) test, {String? under}) {
  final out = <Rect>[];
  final screen = Offset.zero &
      (WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
          WidgetsBinding
              .instance.platformDispatcher.views.first.devicePixelRatio);
  void visit(Element e, bool inside) {
    final k = e.widget.key;
    inside = inside || (k is ValueKey<String> && k.value == under);
    if (inside && k != null && test(k)) {
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

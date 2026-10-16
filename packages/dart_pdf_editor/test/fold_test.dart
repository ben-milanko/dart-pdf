import 'dart:ui';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/shell_chrome.dart' show PdfShellPanelLayout;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// The iPhone Duo inner display in points, and a hinge down its middle.
const _inner = Size(951, 669);

DisplayFeature _fold(Rect bounds,
        {DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
        DisplayFeatureType type = DisplayFeatureType.fold}) =>
    DisplayFeature(bounds: bounds, type: type, state: state);

final _bookCrease = _fold(const Rect.fromLTWH(475, 0, 0, 669));
final _tabletopCrease = _fold(const Rect.fromLTWH(0, 330, 951, 0));

void main() {
  group('pdfSeparatingFold', () {
    test('a half-open vertical crease splits side by side', () {
      final fold = pdfSeparatingFold([_bookCrease], _inner);
      expect(fold?.direction, Axis.horizontal);
      expect(fold?.bounds, _bookCrease.bounds);
    });

    test('a half-open horizontal crease splits top and bottom', () {
      expect(pdfSeparatingFold([_tabletopCrease], _inner)?.direction,
          Axis.vertical);
    });

    test('a flat, gapless fold is one surface', () {
      final flat = _fold(const Rect.fromLTWH(475, 0, 0, 669),
          state: DisplayFeatureState.postureFlat);
      expect(pdfSeparatingFold([flat], _inner), isNull);
    });

    test('a hinge with a physical gap separates even when flat', () {
      final hinge = _fold(const Rect.fromLTWH(470, 0, 12, 669),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat);
      expect(pdfSeparatingFold([hinge], _inner)?.direction, Axis.horizontal);
    });

    test('cutouts and partial features never split the window', () {
      final cutout = DisplayFeature(
          bounds: const Rect.fromLTWH(400, 0, 150, 30),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown);
      final partial = _fold(const Rect.fromLTWH(475, 100, 0, 200));
      expect(pdfSeparatingFold([cutout, partial], _inner), isNull);
    });
  });

  group('pdfFoldInsets', () {
    final book = pdfSeparatingFold([_bookCrease], _inner)!;
    final tabletop = pdfSeparatingFold([_tabletopCrease], _inner)!;

    test('keeps the wider side of a vertical crease', () {
      // a 200pt panel on the left: the viewer spans 200..951, so the right
      // pane (475..951) is the wider one
      expect(pdfFoldInsets(book, const Rect.fromLTRB(200, 0, 951, 669)),
          const EdgeInsets.only(left: 275));
      // a panel on the right instead: the left pane wins
      expect(pdfFoldInsets(book, const Rect.fromLTRB(0, 0, 751, 669)),
          const EdgeInsets.only(right: 276));
    });

    test('a tie goes to the leading side', () {
      const rect = Rect.fromLTRB(0, 0, 950, 669);
      expect(pdfFoldInsets(book, rect), const EdgeInsets.only(right: 475));
      expect(pdfFoldInsets(book, rect, textDirection: TextDirection.rtl),
          const EdgeInsets.only(left: 475));
    });

    test('keeps the upper side of a tabletop fold', () {
      // under a 56pt header: the content sits from 56 down to the crease
      expect(pdfFoldInsets(tabletop, const Rect.fromLTRB(0, 56, 951, 669)),
          const EdgeInsets.only(bottom: 339));
      // wholly below the crease: nothing to move
      expect(pdfFoldInsets(tabletop, const Rect.fromLTRB(0, 400, 951, 669)),
          EdgeInsets.zero);
    });

    test('a fold outside the rect leaves it alone', () {
      expect(pdfFoldInsets(book, const Rect.fromLTRB(500, 0, 951, 669)),
          EdgeInsets.zero);
    });
  });

  void useInnerDisplay(WidgetTester tester, List<DisplayFeature> features) {
    tester.view.physicalSize = _inner;
    tester.view.devicePixelRatio = 1;
    tester.view.displayFeatures = features;
    addTearDown(tester.view.reset);
  }

  testWidgets(
      'the shell keeps the viewer out of the crease, and keeps its '
      'state through a posture change', (tester) async {
    useInnerDisplay(tester, [_bookCrease]);
    final viewerKey = GlobalKey<_ProbeState>();
    Widget shell() => MaterialApp(
          home: PdfShellPanelLayout(
            leadingPanels: const [SizedBox(width: 200)],
            viewer: _Probe(key: viewerKey),
          ),
        );
    await tester.pumpWidget(shell());
    await tester.pump(); // the post-frame origin measurement
    final state = viewerKey.currentState;

    var rect = tester.getRect(find.byKey(viewerKey));
    expect(rect.left, 475, reason: 'the viewer moves to the right pane');
    expect(rect.right, 951);

    // unfold flat: the inner display is one surface again
    tester.view.displayFeatures = [
      _fold(_bookCrease.bounds, state: DisplayFeatureState.postureFlat),
    ];
    await tester.pump();
    await tester.pump();
    rect = tester.getRect(find.byKey(viewerKey));
    expect(rect.left, 200);
    expect(rect.right, 951);
    expect(viewerKey.currentState, same(state),
        reason: 'a posture change must not remount the viewer');
  });

  testWidgets('a tabletop fold keeps the viewer on the upper half',
      (tester) async {
    useInnerDisplay(tester, [_tabletopCrease]);
    await tester.pumpWidget(const MaterialApp(
      home: PdfShellPanelLayout(viewer: _Probe()),
    ));
    await tester.pump();
    final rect = tester.getRect(find.byType(_Probe));
    expect(rect.top, 0);
    expect(rect.bottom, 330);
  });

  testWidgets('toasts stay on the trailing pane of a book crease',
      (tester) async {
    useInnerDisplay(tester, [_bookCrease]);
    late EdgeInsetsGeometry margin;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        margin = pdfFloatingToastMargin(context, pill: 600);
        return const SizedBox();
      }),
    ));
    final resolved = margin.resolve(TextDirection.ltr);
    expect(resolved.left, greaterThanOrEqualTo(475 + 24));
    expect(resolved.right, 24);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

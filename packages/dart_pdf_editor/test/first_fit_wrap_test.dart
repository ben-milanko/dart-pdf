import 'package:dart_pdf_editor/src/editing/first_fit_wrap.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// FirstFitWrap: each child goes into the first run with room for it, so a
// short child back-fills the gap a long one left when it wrapped.
void main() {
  Widget box(int i, double main, {double cross = 40}) => SizedBox(
        key: ValueKey(i),
        width: main,
        height: cross,
      );

  Future<void> pump(WidgetTester tester, Axis direction, List<Widget> children,
      {double extent = 800}) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.rtl, // physical order whatever the locale
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: direction == Axis.horizontal ? extent : null,
          height: direction == Axis.vertical ? extent : null,
          child: FirstFitWrap(direction: direction, children: children),
        ),
      ),
    ));
  }

  Rect rect(WidgetTester tester, int i) =>
      tester.getRect(find.byKey(ValueKey(i)));

  testWidgets('a later child back-fills an earlier run', (tester) async {
    // in order these need three rows: [300 300] [500] [150]... first-fit
    // puts 150 beside the first two
    await pump(tester, Axis.horizontal, [
      box(0, 300),
      box(1, 300),
      box(2, 500),
      box(3, 150),
    ]);
    expect(rect(tester, 0).topLeft, Offset.zero);
    expect(rect(tester, 1).topLeft, const Offset(300, 0));
    expect(rect(tester, 2).topLeft, const Offset(0, 40));
    expect(rect(tester, 3).topLeft, const Offset(600, 0));
    expect(tester.getSize(find.byType(FirstFitWrap)).height, 80);
  });

  testWidgets('runs are as thick as their thickest child, centred across',
      (tester) async {
    await pump(tester, Axis.horizontal, [
      box(0, 500, cross: 40),
      box(1, 500, cross: 60),
      box(2, 200, cross: 20),
    ]);
    // run 0: 0 and 2 (40 thick); run 1: 1 (60 thick)
    expect(rect(tester, 2).topLeft, const Offset(500, 10));
    expect(rect(tester, 1).topLeft, const Offset(0, 40));
    expect(tester.getSize(find.byType(FirstFitWrap)).height, 100);
  });

  testWidgets('a child longer than the run gets one of its own, capped',
      (tester) async {
    await pump(tester, Axis.horizontal, [
      box(0, 100),
      SizedBox(
          key: const ValueKey(1),
          height: 40,
          child:
              const OverflowBox(maxWidth: 2000, child: SizedBox(width: 2000))),
      box(2, 100),
    ]);
    expect(rect(tester, 1).top, 40);
    expect(rect(tester, 2).topLeft, const Offset(100, 0));
  });

  testWidgets('vertical runs are rail columns', (tester) async {
    // the test window is 600px tall
    Widget tall(int i, double main, {double cross = 40}) =>
        SizedBox(key: ValueKey(i), width: cross, height: main);
    await pump(
        tester,
        Axis.vertical,
        [
          tall(0, 200),
          tall(1, 200),
          tall(2, 400, cross: 48),
          tall(3, 150),
        ],
        extent: 600);
    expect(rect(tester, 1).topLeft, const Offset(0, 200));
    expect(rect(tester, 2).topLeft, const Offset(40, 0));
    expect(rect(tester, 3).topLeft, const Offset(0, 400));
    expect(tester.getSize(find.byType(FirstFitWrap)).width, 88);
  });

  testWidgets('dry layout and intrinsics agree with the packing',
      (tester) async {
    await pump(tester, Axis.horizontal, [
      box(0, 300),
      box(1, 300),
      box(2, 500),
      box(3, 150),
    ]);
    final wrap =
        tester.renderObject<RenderFirstFitWrap>(find.byType(FirstFitWrap));
    // laid out: two 40px runs, the widest 750 (300 + 300 + 150)
    expect(wrap.getDryLayout(const BoxConstraints(maxWidth: 800)),
        const Size(750, 80));
    expect(wrap.getMaxIntrinsicWidth(double.infinity), 1250);
    expect(wrap.getMinIntrinsicWidth(double.infinity), 500);
    expect(wrap.getMinIntrinsicHeight(800), 80);
    expect(wrap.getMaxIntrinsicHeight(800), 80);
    // narrower: one child a run
    expect(wrap.getMinIntrinsicHeight(500), 120);
  });

  testWidgets('vertical intrinsics mirror the horizontal ones', (tester) async {
    Widget tall(int i, double main) =>
        SizedBox(key: ValueKey(i), width: 40, height: main);
    await pump(
        tester, Axis.vertical, [tall(0, 200), tall(1, 200), tall(2, 400)],
        extent: 600);
    final wrap =
        tester.renderObject<RenderFirstFitWrap>(find.byType(FirstFitWrap));
    expect(wrap.getMaxIntrinsicHeight(double.infinity), 800);
    expect(wrap.getMinIntrinsicHeight(double.infinity), 400);
    expect(wrap.getMinIntrinsicWidth(600), 80);
    expect(wrap.getMaxIntrinsicWidth(600), 80);
    expect(wrap.getDryLayout(const BoxConstraints(maxHeight: 600)),
        const Size(80, 400));
  });

  testWidgets('a direction change relays out', (tester) async {
    await pump(tester, Axis.horizontal, [box(0, 300), box(1, 300)]);
    expect(rect(tester, 1).topLeft, const Offset(300, 0));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 600,
          child: FirstFitWrap(
              direction: Axis.vertical,
              children: [box(0, 40, cross: 200), box(1, 40, cross: 200)]),
        ),
      ),
    ));
    expect(rect(tester, 1).topLeft, const Offset(0, 200));
  });
}

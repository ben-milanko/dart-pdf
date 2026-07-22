import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required PdfPanelDock dock,
    bool bottomSheet = false,
    ValueChanged<double>? onPersistWidth,
    VoidCallback? onClose,
    PdfSidebarPanelContentBuilder? builder,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 500,
            child: Align(
              alignment: Alignment.topLeft,
              child: PdfSidebarPanelFrame(
                width: 240,
                minWidth: 180,
                maxWidth: 320,
                persistedWidth: null,
                onPersistWidth: onPersistWidth,
                dock: dock,
                resizable: true,
                bottomSheet: bottomSheet,
                gripKey: const ValueKey('frame-grip'),
                onClose: onClose,
                builder: builder ??
                    (context, geometry) => ColoredBox(
                          key: const ValueKey('frame-content'),
                          color: Colors.white,
                          child: geometry.closeButton(
                                key: const ValueKey('frame-close'),
                              ) ??
                              const SizedBox.expand(),
                        ),
              ),
            ),
          ),
        ),
      );

  testWidgets('dock geometry covers both sides and scrollbar clearance',
      (tester) async {
    late PdfSidebarPanelGeometry geometry;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(host(
      dock: PdfPanelDock.left,
      builder: (context, value) {
        geometry = value;
        return value.withScrollbar(
          scroll: scroll,
          thumbKey: const ValueKey('frame-scrollbar'),
          child: const SizedBox.expand(),
        );
      },
    ));
    expect(geometry.gripOnRight, isTrue);
    expect(geometry.scrollbarInset, PdfSidebarResizeGrip.width);
    expect(geometry.scrollbarClearance,
        PdfScrollbar.hitExtent + PdfSidebarResizeGrip.width);
    expect(find.byType(PdfScrollbar), findsOneWidget);
    final leftGrip = tester.getCenter(find.byKey(const ValueKey('frame-grip')));
    expect(leftGrip.dx, closeTo(236, 0.1));

    await tester.pumpWidget(host(
      dock: PdfPanelDock.right,
      builder: (context, value) {
        geometry = value;
        return const SizedBox.expand();
      },
    ));
    expect(geometry.gripOnLeft, isTrue);
    expect(geometry.scrollbarInset, 0);
    final rightGrip =
        tester.getCenter(find.byKey(const ValueKey('frame-grip')));
    expect(rightGrip.dx, closeTo(4, 0.1));
  });

  testWidgets('grip clamps width and persists once at drag end',
      (tester) async {
    var writes = 0;
    double? persisted;
    await tester.pumpWidget(host(
      dock: PdfPanelDock.left,
      onPersistWidth: (value) {
        writes++;
        persisted = value;
      },
    ));

    final grip = find.byKey(const ValueKey('frame-grip'));
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(writes, 0);
    await gesture.up();
    await tester.pump();

    expect(writes, 1);
    expect(persisted, closeTo(300, 1));
    expect(tester.getSize(find.byType(PdfSidebarPanelFrame)).width,
        closeTo(300, 1));
  });

  testWidgets('close is docked-only and bottom sheet bypasses fixed width',
      (tester) async {
    var closes = 0;
    await tester.pumpWidget(host(
      dock: PdfPanelDock.left,
      onClose: () => closes++,
    ));
    await tester.tap(find.byKey(const ValueKey('frame-close')));
    expect(closes, 1);
    expect(find.byKey(const ValueKey('frame-grip')), findsOneWidget);

    await tester.pumpWidget(host(
      dock: PdfPanelDock.left,
      bottomSheet: true,
      onClose: () => closes++,
    ));
    expect(find.byKey(const ValueKey('frame-close')), findsNothing);
    expect(find.byKey(const ValueKey('frame-grip')), findsNothing);
    expect(
        tester.getSize(find.byKey(const ValueKey('frame-content'))).width, 400);
  });
}

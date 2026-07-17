import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer_example/scroll_indicator_demo.dart';
import 'package:pdf_viewer_example/demo_document.dart';

void main() {
  testWidgets('demo replaces the stock bar with a working page scrubber',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ScrollIndicatorDemoScreen(bytes: buildDemoPdf()),
    ));
    await tester.pump();

    // the custom scrubber is up and the stock scrollbar thumb is gone
    expect(find.byKey(const ValueKey('demo-page-scrubber')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-scrollbar-thumb')), findsNothing);

    // the live-metrics readout populates once layout settles (the builder
    // stashes metrics via a post-frame setState, so pump to flush it)
    await tester.pump();
    expect(find.textContaining('page:'), findsOneWidget);

    // dragging the scrubber scrolls the document (verified on the underlying
    // scroll position, which the scrubber drives via jumpToNormalized)
    final scroll =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels, moreOrLessEquals(0, epsilon: 0.5));
    await tester.drag(find.byKey(const ValueKey('demo-page-scrubber')),
        const Offset(0, 400));
    await tester.pump();
    expect(scroll.pixels, greaterThan(0));

    // the readout catches up on the next frame (post-frame setState)
    await tester.pump();
    expect(find.textContaining('position:  0.000'), findsNothing);

    // drain the viewer's settle/motion-hold timers before teardown
    await tester.pumpAndSettle();
  });
}

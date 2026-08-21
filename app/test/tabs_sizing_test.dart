import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

/// Chrome-style tab sizing: tabs share the strip equally and shrink as more
/// open, and closing while the pointer is over the strip holds the surviving
/// tabs' width until the pointer leaves.
void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  // A realistic desktop width so a handful of tabs sit in the shrinking regime
  // (below the max width) rather than filling the default 800px surface.
  void setDesktopSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('openFile', {'name': name, 'bytes': buildClassicPdf()}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  // The tab's coloured Material (nearest Material ancestor of its title); its
  // width tracks the per-tab layout width.
  Finder tabRoot(String name) =>
      find.ancestor(of: tabTitle(name), matching: find.byType(Material)).first;

  double tabWidth(WidgetTester tester, String name) =>
      tester.getSize(tabRoot(name)).width;

  Finder closeFor(String name) =>
      find.descendant(of: tabRoot(name), matching: find.byTooltip('Close tab'));

  testWidgets('tabs shrink to share the strip as more open', (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'a.pdf');
    await openTab(tester, 'b.pdf');
    await tester.pumpAndSettle();
    final wideWidth = tabWidth(tester, 'a.pdf');

    for (var i = 0; i < 6; i++) {
      await openTab(tester, 'x$i.pdf');
    }
    await tester.pumpAndSettle();
    final narrowWidth = tabWidth(tester, 'a.pdf');

    // Eight tabs each get a narrower slice than two did.
    expect(narrowWidth, lessThan(wideWidth));
    // And two tabs don't stretch past the Chrome-style max.
    expect(wideWidth, lessThanOrEqualTo(240));
  });

  testWidgets('closing over the strip holds width, then grows on exit',
      (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    for (var i = 0; i < 8; i++) {
      await openTab(tester, 't$i.pdf');
    }
    await tester.pumpAndSettle();

    final before = tabWidth(tester, 't0.pdf');

    // Park a mouse over the far-left tab so the strip reads as hovered while we
    // close a middle tab.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tabTitle('t0.pdf')));
    await tester.pump();

    await tester.tap(closeFor('t3.pdf'));
    await tester.pump();
    await tester.pump();

    // t3 is gone but the survivors stayed pinned - t0 hasn't grown yet.
    expect(tabTitle('t3.pdf'), findsNothing);
    expect(tabWidth(tester, 't0.pdf'), closeTo(before, 0.5));

    // Move the pointer off the strip: the hold releases and the tabs grow.
    await mouse.moveTo(const Offset(700, 700));
    await tester.pumpAndSettle();
    expect(tabWidth(tester, 't0.pdf'), greaterThan(before + 1));

    await mouse.removePointer();
  });

  testWidgets('tab strip stays inside the AppBar while the window narrows',
      (tester) async {
    setDesktopSize(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    for (var i = 0; i < 8; i++) {
      await openTab(tester, 't$i.pdf');
    }
    await tester.pumpAndSettle();

    // The tab list fills all available title space at this width. Narrowing
    // the window starts its resize animation from the old, wider constraint;
    // that intermediate width must still be clamped to the new AppBar width.
    tester.view.physicalSize = const Size(1390, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

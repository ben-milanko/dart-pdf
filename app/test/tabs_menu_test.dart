import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    // The mock store is process-global; reset it so a prior test's persisted
    // preferences never leak into this one.
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> setMobileSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // A realistic desktop width: with Chrome-style tab sizing a handful of tabs
  // cap at their max width and leave slack for the trailing controls, rather
  // than filling the whole 800px default test surface.
  void setDesktopSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Delivers a PDF to the running app the way the OS would (a warm-start
  // "open with"), opening it in a new tab.
  Future<void> openTab(
    WidgetTester tester,
    String name, {
    String? path,
    List<int>? bytes,
  }) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('openFile', {
        'name': name,
        'bytes': bytes ?? buildClassicPdf(),
        if (path != null) 'path': path,
      }),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The tab title within the strip (scoped to the tab-strip ReorderableListView
  // so it never matches the AppBar's active-document title nor the thumbnail
  // sidebar's own reorderable list in the body).
  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(name),
      );

  // Right-clicks the tab labelled [name] to open its context menu.
  Future<void> rightClickTab(WidgetTester tester, String name) async {
    final gesture = await tester.startGesture(
      tester.getCenter(tabTitle(name)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> openTabs(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'alpha.pdf');
    await openTab(tester, 'beta.pdf');
    await openTab(tester, 'gamma.pdf');
  }

  // Opens the desktop tabs preview grid (grid_view button in the tab strip).
  Future<void> openTabsGrid(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('desktop-tabs-button')));
    await tester.pumpAndSettle();
  }

  // The grid tile whose title is [name] (scoped to the preview grid).
  Finder gridTile(String name) => find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('desktop-tabs-grid')),
          matching: find.text(name),
        ),
        matching: find.byKey(const ValueKey('mobile-tab-tile')),
      );

  // Right-clicks the grid tile labelled [name] to open its context menu.
  Future<void> rightClickGridTile(WidgetTester tester, String name) async {
    final gesture = await tester.startGesture(
      tester.getCenter(gridTile(name)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('incoming file shows an opening indicator', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(
      MethodCall('openFile', {'name': 'slow.pdf', 'bytes': buildClassicPdf()}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      IncomingFileService.channelName,
      message,
      (_) {},
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Opening slow.pdf…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tabTitle('slow.pdf'), findsOneWidget);
  });

  testWidgets('compact tabs open as a preview grid bottom sheet',
      (tester) async {
    await setMobileSize(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'alpha.pdf');
    await openTab(tester, 'beta.pdf');

    expect(find.byKey(const ValueKey('tab-strip')), findsNothing);
    expect(find.byKey(const ValueKey('mobile-tabs-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-tabs-count')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-tabs-button')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-app-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-shell-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile-tabs-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-tabs-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-tab-tile')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('mobile-tab-preview')), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-tabs-grid')),
        matching: find.text('alpha.pdf'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-tabs-grid')),
        matching: find.text('beta.pdf'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-tabs-open')), findsOneWidget);
  });

  testWidgets('desktop tab strip opens the preview grid in a dialog',
      (tester) async {
    setDesktopSize(tester);
    await openTabs(tester);

    final button = find.byKey(const ValueKey('desktop-tabs-button'));
    final addButton = find.byKey(const ValueKey('desktop-tab-add-button'));
    expect(button, findsOneWidget);
    expect(addButton, findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs-spacer')), findsOneWidget);
    expect(
      tester.getCenter(button).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const ValueKey('tab-strip'))).dx,
      ),
    );
    expect(tester.getCenter(button).dx - tester.getCenter(addButton).dx,
        greaterThan(40));

    await tester.tap(button);
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey('desktop-tabs-grid'));
    expect(find.byKey(const ValueKey('desktop-tabs-dialog')), findsOneWidget);
    expect(grid, findsOneWidget);
    expect(
      find.descendant(
        of: grid,
        matching: find.byKey(const ValueKey('mobile-tab-tile')),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: grid,
        matching: find.byKey(const ValueKey('mobile-tab-preview')),
      ),
      findsNWidgets(3),
    );
    expect(find.byKey(const ValueKey('desktop-tabs-open')), findsOneWidget);

    await tester.tap(
      find.descendant(of: grid, matching: find.text('alpha.pdf')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-tabs-dialog')), findsNothing);
    expect(tester.widget<Text>(tabTitle('alpha.pdf')).style?.fontWeight,
        FontWeight.w600);
  });

  testWidgets('tab thumbnails preserve each first page aspect ratio',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'portrait.pdf');
    // The replacement is byte-for-byte the same length, so the fixture's xref
    // offsets stay valid while its first page becomes landscape.
    final landscape = ascii(
      String.fromCharCodes(buildClassicPdf()).replaceFirst(
        '/MediaBox [0 0 612 792]',
        '/MediaBox [0 0 792 612]',
      ),
    );
    await openTab(tester, 'landscape.pdf', bytes: landscape);

    await tester.tap(find.byKey(const ValueKey('desktop-tabs-button')));
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey('desktop-tabs-grid'));
    Finder previewFor(String title) {
      final tile = find.ancestor(
        of: find.descendant(of: grid, matching: find.text(title)),
        matching: find.byKey(const ValueKey('mobile-tab-tile')),
      );
      return find.descendant(
        of: tile,
        matching: find.byKey(const ValueKey('mobile-tab-preview')),
      );
    }

    expect(tester.getSize(previewFor('portrait.pdf')).aspectRatio,
        closeTo(612 / 792, 0.001));
    expect(tester.getSize(previewFor('landscape.pdf')).aspectRatio,
        closeTo(792 / 612, 0.001));
  });

  testWidgets('tab grid resumes thumbnail rendering after a fast fling',
      (tester) async {
    await setMobileSize(tester);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    // More than two viewportfuls ensures the last tab's preview is first
    // constructed while the grid is moving, rather than before the fling.
    for (var i = 0; i < 20; i++) {
      await openTab(tester, 'tab-$i.pdf');
    }

    await tester.tap(find.byKey(const ValueKey('mobile-tabs-button')));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('mobile-tabs-grid'));
    final scrollable = find
        .descendant(
          of: grid,
          matching: find.byType(Scrollable),
        )
        .first;
    Finder tile(String title) => find.ancestor(
          of: find.descendant(of: grid, matching: find.text(title)),
          matching: find.byKey(const ValueKey('mobile-tab-tile')),
        );
    expect(tester.widget<GridView>(grid).scrollCacheExtent, isNotNull);
    expect(tile('tab-19.pdf'), findsNothing);

    // Keep plenty of content below the fling so it retains a high ballistic
    // velocity while fresh rows are being constructed.
    await tester.fling(grid, const Offset(0, -300), 5000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final lastTile = tile('tab-19.pdf');
    expect(lastTile, findsOneWidget);
    expect(
      find.descendant(
        of: lastTile,
        matching: find.byKey(const ValueKey('mobile-tab-preview-image')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hovering an inactive desktop tab shows its page preview',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(
      tester,
      'alpha.pdf',
      bytes: PdfBlankDocument.create(pageSize: PdfPageSize.letter.landscape),
    );
    await openTab(tester, 'beta.pdf');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(tabTitle('alpha.pdf')));
    await tester.pump(const Duration(milliseconds: 399));
    expect(find.byKey(const ValueKey('tab-hover-preview')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('tab-hover-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tab-hover-preview-thumbnail')),
      findsOneWidget,
    );
    final thumbnailSize = tester.getSize(
      find.byKey(const ValueKey('tab-hover-preview-thumbnail')),
    );
    expect(thumbnailSize.width / thumbnailSize.height, closeTo(792 / 612, .01));
    expect(
      tester.widget<Text>(
        find.byKey(const ValueKey('tab-hover-preview-title')),
      ).data,
      'alpha.pdf',
    );
    expect(
      tester.widget<Text>(
        find.byKey(const ValueKey('tab-hover-preview-page')),
      ).data,
      'Page 1',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('tab-hover-preview-image')),
      findsOneWidget,
    );

    // beta is active, so moving to it dismisses alpha's card and does not
    // replace it with a redundant preview of the document already on screen.
    await mouse.moveTo(tester.getCenter(tabTitle('beta.pdf')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('tab-hover-preview')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('right-click opens the tab context menu', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');

    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-others')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-right')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-all')), findsOneWidget);
  });

  testWidgets('right-click on a grid tile opens the tab context menu',
      (tester) async {
    await openTabs(tester);
    await openTabsGrid(tester);

    await rightClickGridTile(tester, 'beta.pdf');

    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-others')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-right')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-menu-close-all')), findsOneWidget);
  });

  testWidgets('grid tile Close others leaves only the clicked tab, grid open',
      (tester) async {
    await openTabs(tester);
    await openTabsGrid(tester);

    await rightClickGridTile(tester, 'beta.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-others')));
    await tester.pumpAndSettle();

    // The grid stays open and refreshes to the single surviving tab.
    expect(find.byKey(const ValueKey('desktop-tabs-grid')), findsOneWidget);
    expect(gridTile('beta.pdf'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-tabs-grid')),
        matching: find.byKey(const ValueKey('mobile-tab-tile')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('grid tile Close all empties the grid and dismisses the dialog',
      (tester) async {
    await openTabs(tester);
    await openTabsGrid(tester);

    await rightClickGridTile(tester, 'alpha.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-tabs-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('tab-strip')), findsNothing);
  });

  testWidgets(
      'right-click offers opening the source folder for file-backed tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'alpha.pdf', path: '/Users/ben/Documents/alpha.pdf');

    await rightClickTab(tester, 'alpha.pdf');

    expect(find.byKey(const ValueKey('tab-menu-open-folder')), findsOneWidget);
    expect(find.text('Open in Finder'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('right-click hides folder action for memory-only tabs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await openTab(tester, 'alpha.pdf');

    await rightClickTab(tester, 'alpha.pdf');

    expect(find.byKey(const ValueKey('tab-menu-open-folder')), findsNothing);
    expect(find.byKey(const ValueKey('tab-menu-close')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Close others leaves only the clicked tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-others')));
    await tester.pumpAndSettle();

    expect(tabTitle('alpha.pdf'), findsNothing);
    expect(tabTitle('gamma.pdf'), findsNothing);
    expect(tabTitle('beta.pdf'), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsOneWidget);
  });

  testWidgets('Close tabs to the right keeps the clicked tab and its left',
      (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'beta.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-right')));
    await tester.pumpAndSettle();

    expect(tabTitle('alpha.pdf'), findsOneWidget);
    expect(tabTitle('beta.pdf'), findsOneWidget);
    expect(tabTitle('gamma.pdf'), findsNothing);
  });

  testWidgets('Close right is disabled on the rightmost tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'gamma.pdf');

    final item = tester.widget<PopupMenuItem<dynamic>>(
      find.byKey(const ValueKey('tab-menu-close-right')),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('Close all removes every tab', (tester) async {
    await openTabs(tester);

    await rightClickTab(tester, 'alpha.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close-all')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tab-strip')), findsNothing);
    expect(find.byTooltip('Close tab'), findsNothing);
  });

  testWidgets('Close on the active tab activates a surviving neighbour',
      (tester) async {
    await openTabs(tester);
    // gamma is active (last opened).

    await rightClickTab(tester, 'gamma.pdf');
    await tester.tap(find.byKey(const ValueKey('tab-menu-close')));
    await tester.pumpAndSettle();

    expect(tabTitle('gamma.pdf'), findsNothing);
    // beta is now the rightmost survivor and becomes active.
    expect(tester.widget<Text>(tabTitle('beta.pdf')).style?.fontWeight,
        FontWeight.w600);
  });

  testWidgets('re-opening the same file focuses its tab instead of duplicating',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await openTab(tester, 'alpha.pdf', path: '/docs/alpha.pdf');
    await openTab(tester, 'beta.pdf', path: '/docs/beta.pdf');
    // beta was opened last, so it is the active tab.
    expect(tester.widget<Text>(tabTitle('beta.pdf')).style?.fontWeight,
        FontWeight.w600);

    // The OS hands us alpha a second time (another "open with" of the same
    // file, e.g. via the single-instance forwarder or both launch-arg and
    // getInitialFile delivery on cold start).
    await openTab(tester, 'alpha.pdf', path: '/docs/alpha.pdf');

    // No duplicate tab, and alpha is now focused rather than re-loaded.
    expect(tabTitle('alpha.pdf'), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsNWidgets(2));
    expect(tester.widget<Text>(tabTitle('alpha.pdf')).style?.fontWeight,
        FontWeight.w600);
    expect(tester.widget<Text>(tabTitle('beta.pdf')).style?.fontWeight,
        FontWeight.normal);
  });
}

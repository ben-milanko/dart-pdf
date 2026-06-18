import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:pdf_viewer_example/recent_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Uint8List doc(int seed) =>
      Uint8List.fromList(List.generate(64, (i) => (seed * 31 + i) & 0xff));

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
  }

  testWidgets('app menu lists seeded recent files and a clear action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));
    await seed.record('beta.pdf', doc(2));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    // let the app's own recents store load the seeded manifest
    await tester.pump();
    await tester.pump();

    await openMenu(tester);
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.text('alpha.pdf'), findsOneWidget);
    expect(find.text('beta.pdf'), findsOneWidget);
    expect(find.text('Clear recent files'), findsOneWidget);
    // the menu also offers a direct open entry
    expect(find.text('Open a PDF…'), findsOneWidget);
  });

  testWidgets('clearing recent files removes the section', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    await tester.pump();
    await tester.pump();

    await openMenu(tester);
    await tester.tap(find.text('Clear recent files'));
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(find.text('Recent files'), findsNothing);
    expect(find.text('alpha.pdf'), findsNothing);
  });

  testWidgets('with no recents the menu shows no Recent files section',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ViewerApp(cacheStore: PdfMemoryCacheStore()));
    await tester.pump();

    await openMenu(tester);
    expect(find.text('Recent files'), findsNothing);
    expect(find.text('Clear recent files'), findsNothing);
  });
}

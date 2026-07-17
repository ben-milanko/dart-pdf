// The "Open from a URL…" flow: it drives PdfDocument.openSource over a
// PdfByteSource, so the example exercises the async byte-source API. The
// remoteByteSourceFactory seam swaps the real HTTP source for an in-memory
// one, so the test touches no network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_viewer_example/demo_document.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    // Restore the production factory so one test can't leak into another.
    remoteByteSourceFactory = (uri) => PdfHttpByteSource(uri);
  });

  testWidgets('opens a document from a URL via the byte-source API',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final demo = buildDemoPdf();
    Uri? requested;
    remoteByteSourceFactory = (uri) {
      requested = uri;
      return PdfBytesByteSource(demo);
    };

    await tester.pumpWidget(const ViewerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open from a URL…').last);
    await tester.pumpAndSettle();

    // The dialog is prefilled with the sample URL; confirm it.
    expect(find.byKey(const ValueKey('open-url-field')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-url-confirm')));
    await tester.pumpAndSettle();

    // The source was built from the entered URL and a viewer is now showing.
    expect(requested, isNotNull);
    expect(requested!.host, 'raw.githubusercontent.com');
    expect(find.byType(PdfViewer), findsOneWidget);
  });

  testWidgets('a malformed URL surfaces an error tab, no network call',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var built = false;
    remoteByteSourceFactory = (uri) {
      built = true;
      return PdfBytesByteSource(buildDemoPdf());
    };

    await tester.pumpWidget(const ViewerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open from a URL…').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('open-url-field')), 'not a url');
    await tester.tap(find.byKey(const ValueKey('open-url-confirm')));
    await tester.pumpAndSettle();

    expect(built, isFalse); // never reached the source factory
    expect(find.textContaining('Not a valid URL'), findsOneWidget);
  });
}

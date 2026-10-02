// Mounts editor widgets under the kinds of app a host may use, so tests can
// prove the stock chrome works under each (see test/any_host_test.dart).

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app a test host is built from.
enum PdfTestHost {
  /// `MaterialApp` + `Scaffold` (the control: everything the chrome needs is
  /// there already).
  material,

  /// `CupertinoApp` + `CupertinoPageScaffold`: Cupertino localizations and
  /// theme only.
  cupertino,

  /// A bare `WidgetsApp`: no Material or Cupertino anything.
  widgets,
}

/// Pumps [child] as the home of a [host] app and returns once it is built.
///
/// The platform is explicit: the host is built for [defaultTargetPlatform]
/// (run the test under `TargetPlatformVariant.only(...)` to pick one) - a
/// Material host gets `ThemeData(platform:)` - and [expectPdfHostPlatform]
/// checks that the editor's theme agrees. That guards the false pass a
/// fallback theme would give: `Theme.of` without a `Theme` above returns a
/// `ThemeData` cached in a static on first use, carrying whatever platform
/// the isolate's first lookup saw, so an iOS variant can silently run with
/// an Android theme.
Future<void> pumpPdfHost(
  WidgetTester tester,
  Widget child, {
  required PdfTestHost host,
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // unmount before the caller's controllers are disposed (tear-downs run
  // last-registered first, and callers create their controllers first)
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(pdfHostApp(child, host: host));
  await tester.pump();
}

/// The app [pumpPdfHost] mounts.
Widget pdfHostApp(Widget child, {required PdfTestHost host}) => switch (host) {
      PdfTestHost.material => MaterialApp(
          theme: ThemeData(platform: defaultTargetPlatform),
          home: Scaffold(body: child),
        ),
      PdfTestHost.cupertino => CupertinoApp(
          home: CupertinoPageScaffold(child: child),
        ),
      PdfTestHost.widgets => WidgetsApp(
          color: const Color(0xFF1565C0),
          pageRouteBuilder:
              <T>(RouteSettings settings, WidgetBuilder builder) =>
                  PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, __) => builder(context),
          ),
          home: child,
        ),
    };

/// A context inside the editor's host wrapper (below the first
/// [PdfMaterialHost]): what the editor's own chrome builds in.
BuildContext pdfEditorContext(WidgetTester tester) => tester.element(find
    .descendant(
        of: find.byType(PdfMaterialHost), matching: find.byType(Builder))
    .first);

/// Checks that the editor's chrome sees a theme for the platform under test
/// (not a cached fallback theme for another one).
void expectPdfHostPlatform(WidgetTester tester) {
  expect(Theme.of(pdfEditorContext(tester)).platform, defaultTargetPlatform,
      reason: 'the editor must build with a theme for the platform under '
          'test, not a cached fallback');
}

/// No FlutterError was reported and no error widget is on screen.
void expectNoHostErrors(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
}

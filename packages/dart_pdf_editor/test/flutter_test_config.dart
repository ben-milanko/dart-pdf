import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfPageView, PdfViewer;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file in this package (a Flutter test convention).
///
/// Many editor tests build a [PdfEditingController], which loads
/// [PdfEditingPreferences] from `shared_preferences` asynchronously. With no
/// mock registered the plugin call fails with `MissingPluginException`, and
/// because it can land after a synchronous test body has already finished it
/// surfaces as a flaky "failed after test completion". Registering a default
/// empty mock store here gives every test an in-memory backing so that never
/// happens; individual tests may still call [SharedPreferences.setMockInitialValues]
/// to seed their own values.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // Keep the deterministic, isolate-free on-thread render path for the suite:
  // the owned default worker (#396) would otherwise spawn a real isolate per
  // viewer and turn synchronous render assertions async. Tests that exercise the
  // default worker re-enable it (see default_worker_test.dart).
  PdfViewer.debugAutoRenderWorkerEnabled = false;
  // Production command warming is intentionally asynchronous and
  // low-priority. Keep unrelated widget tests deterministic; focused warming
  // tests opt back in with explicit values and restore them afterwards.
  PdfViewer.speculativePageWarmRadius = 0;
  PdfViewer.speculativeHeavyPageWarmCount = 0;
  PdfPageView.directPicturePresentation = false;
  PdfPageView.prioritizeBoundedFinalPicture = false;
  await _registerBundledDejaVu();
  await testMain();
}

var _dejaVuRegistered = false;

/// Registers the bundled DejaVu Sans face with the engine for the whole test
/// suite.
///
/// DejaVu now ships in `dart_pdf_editor_assets`, which this package's tests
/// don't depend on, so Flutter's test asset bundle no longer auto-registers it.
/// Render/parity tests rely on it as the default text fallback (see
/// `CanvasPdfDevice`'s fallback list - Arabic/Cyrillic/Greek and copied
/// presentation forms) and would otherwise paint tofu, so load the moved file
/// and register it under both the bare family the runner used when this package
/// was the root app and the new package-qualified family the fallback list now
/// names. Best-effort: a missing file just leaves the fallback unregistered.
Future<void> _registerBundledDejaVu() async {
  if (_dejaVuRegistered) return;
  _dejaVuRegistered = true;
  final file = File('../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf');
  if (!file.existsSync()) return;
  final bytes = ByteData.sublistView(file.readAsBytesSync());
  for (final family in const [
    'DejaVu Sans',
    'packages/dart_pdf_editor_assets/DejaVu Sans',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
}

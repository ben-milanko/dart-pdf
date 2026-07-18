// Devtools options persist across app restarts: every panel change writes
// the whole option set to SharedPreferences, and restoreOptions applies it
// over the platform defaults at startup.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Reset the globals the options touch so tests stay independent.
    AppDevTools.instance.setDeepZoomMode(AppDevTools.modePatch);
    pdfDebugPaintDetailBounds.value = false;
    pdfDebugShowRenderWindow.value = false;
    AppDevTools.instance.showPerformanceOverlay.value = false;
    PdfPerfLog.enabled = false;
    pdfRenderWorkerPoolSize = defaultPdfRenderWorkerPoolSize;
  });

  test('options round-trip through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final tools = AppDevTools.instance;

    tools.setDeepZoomMode(AppDevTools.modeBatched);
    pdfDebugPaintDetailBounds.value = true;
    pdfDebugShowRenderWindow.value = true;
    pdfRenderWorkerPoolSize = 5;
    await tools.persistOptions();

    // "Restart": globals back to defaults, then restore.
    tools.setDeepZoomMode(AppDevTools.modePatch);
    pdfDebugPaintDetailBounds.value = false;
    pdfDebugShowRenderWindow.value = false;
    pdfRenderWorkerPoolSize = 3;
    await tools.restoreOptions();

    expect(tools.deepZoomMode, AppDevTools.modeBatched);
    expect(PdfPageView.tileStoreDetail, isTrue);
    expect(PdfPageView.debugTileStoreOverride!.batchRasters, isTrue);
    expect(pdfDebugPaintDetailBounds.value, isTrue);
    expect(pdfDebugShowRenderWindow.value, isTrue);
    expect(pdfRenderWorkerPoolSize, 5);
  });

  test('restore with nothing persisted leaves the defaults alone', () async {
    SharedPreferences.setMockInitialValues({});
    pdfRenderWorkerPoolSize = 3;
    await AppDevTools.instance.restoreOptions();
    expect(AppDevTools.instance.deepZoomMode, AppDevTools.modePatch);
    expect(pdfRenderWorkerPoolSize, 3);
  });

  test('a corrupt payload is logged, not thrown', () async {
    SharedPreferences.setMockInitialValues(
        {'flutter.devtools.options': '{not json'});
    await AppDevTools.instance.restoreOptions();
    expect(
      AppDevTools.instance.log.any(
          (e) => e.message.contains('devtools options restore failed')),
      isTrue,
    );
  });
}

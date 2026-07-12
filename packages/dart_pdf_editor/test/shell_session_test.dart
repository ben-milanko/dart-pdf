import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/shell_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('document key rekeys viewport memory without restarting the worker', () {
    final bytes = buildMultiPagePdf(1);
    final lifecycle = PdfShellSessionLifecycle(
      bytes: bytes,
      controller: null,
      preferences: null,
      viewerController: null,
      performance: null,
      documentId: 'document-a',
    );
    addTearDown(lifecycle.dispose);
    final session = lifecycle.session;
    final generations = lifecycle.debugWorkerGenerations;

    final update = lifecycle.update(
      bytes: bytes,
      controller: null,
      preferences: null,
      viewerController: null,
      performanceController: null,
      documentId: 'document-b',
    );

    expect(update.sessionChanged, isFalse);
    expect(update.documentKeyChanged, isTrue);
    expect(identical(lifecycle.session, session), isTrue);
    expect(lifecycle.documentKey, 'document-b');
    expect(lifecycle.debugWorkerGenerations, generations);
  });

  test('byte swap opens once and starts exactly one worker generation', () {
    final first = buildMultiPagePdf(1);
    final second = buildMultiPagePdf(2);
    final lifecycle = PdfShellSessionLifecycle(
      bytes: first,
      controller: null,
      preferences: null,
      viewerController: null,
      performance: null,
      documentId: null,
    );
    addTearDown(lifecycle.dispose);
    final oldSession = lifecycle.session;
    final generations = lifecycle.debugWorkerGenerations;

    final update = lifecycle.update(
      bytes: second,
      controller: null,
      preferences: null,
      viewerController: null,
      performanceController: null,
      documentId: null,
    );

    expect(update.sessionChanged, isTrue);
    expect(identical(lifecycle.session, oldSession), isFalse);
    expect(lifecycle.session.document.pageCount, 2);
    expect(lifecycle.debugWorkerGenerations, generations + 1);
  });

  test('form fill or editor revision restarts the worker once', () {
    final lifecycle = PdfShellSessionLifecycle(
      bytes: buildAcroFormPdf(),
      controller: null,
      preferences: null,
      viewerController: null,
      performance: null,
      documentId: 'revision-test',
    );
    addTearDown(lifecycle.dispose);
    final generations = lifecycle.debugWorkerGenerations;

    expect(lifecycle.session.setFormFieldText('name', 'Jane'), isTrue);
    expect(lifecycle.debugWorkerGenerations, generations + 1);
    lifecycle.session.undo();
    expect(lifecycle.debugWorkerGenerations, generations + 2);
    lifecycle.session.addRectangle(0, const PdfRect(10, 10, 40, 40));
    expect(lifecycle.debugWorkerGenerations, generations + 3);
  });

  test('external resources remain caller-owned', () {
    final controller = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    final performance = PdfPerformanceController();
    final preferences = controller.preferences;
    final lifecycle = PdfShellSessionLifecycle(
      bytes: null,
      controller: controller,
      preferences: null,
      viewerController: viewer,
      performance: performance,
      documentId: 'external',
    );

    expect(lifecycle.debugOwnsSession, isFalse);
    expect(lifecycle.debugOwnsPreferences, isFalse);
    expect(lifecycle.debugOwnsViewer, isFalse);
    expect(lifecycle.debugOwnsPerformance, isFalse);
    lifecycle.dispose();

    expect(() => controller.addRectangle(0, const PdfRect(10, 10, 40, 40)),
        returnsNormally);
    expect(
        () => preferences.pageColor = const Color(0xFFEEEEEE), returnsNormally);
    expect(() => viewer.addListener(() {}), returnsNormally);
    expect(
        () => performance.configureDocument(
            pageCount: 1, documentBytes: controller.bytes.length),
        returnsNormally);

    controller.dispose();
    viewer.dispose();
    performance.dispose();
  });

  test('owned resource policy is explicit', () async {
    final lifecycle = PdfShellSessionLifecycle(
      bytes: buildMultiPagePdf(1),
      controller: null,
      preferences: null,
      viewerController: null,
      performance: null,
      documentId: null,
    );
    expect(lifecycle.debugOwnsSession, isTrue);
    expect(lifecycle.debugOwnsPreferences, isTrue);
    // Lazy owned resources become owned on first access.
    lifecycle.viewer;
    lifecycle.performance;
    expect(lifecycle.debugOwnsViewer, isTrue);
    expect(lifecycle.debugOwnsPerformance, isTrue);
    await lifecycle.preferences.ready;
    lifecycle.dispose();
  });
}

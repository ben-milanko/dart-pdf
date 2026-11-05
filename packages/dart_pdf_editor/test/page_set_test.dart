// The viewer's page set across revision swaps as pure values: which path a
// change takes (incremental, keyed, full), the invalidation it hands every
// cache and warm loop, and how old pages remap. No widgets - fixture
// documents edited through a real PdfEditingController.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/page_set.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PdfEditingController editingOf(int pages) {
    final editing = PdfEditingController(buildMultiPagePdf(pages));
    addTearDown(editing.dispose);
    return editing;
  }

  PdfPageSet loadOf(PdfEditingController editing) => PdfPageSet.load(
        editing.document,
        contentStamp: editing.pageContentRenderStamp,
      );

  PdfPageSetChange revise(PdfPageSet set, PdfEditingController editing) =>
      set.reconcile(
        editing.document,
        sameLineage: true,
        impact: editing.lastRevisionImpact,
        contentStamp: editing.pageContentRenderStamp,
      );

  group('load', () {
    test('reads geometry and stable references per page', () {
      final set = PdfPageSet.load(
          PdfDocument.open(buildMultiPagePdf(3, width: 400, height: 800)));
      expect(set.length, 3);
      expect(set.aspects, everyElement(closeTo(2, 1e-9)));
      expect(set.pointWidths, everyElement(400));
      expect(set.maxPointWidth, 400);
      expect(set.maxPointHeight, 800);
      expect(set.refs.toSet(), hasLength(3), reason: 'distinct leaf objects');
      expect(set.epoch, 0);
    });

    test('folds the view rotation into the geometry', () {
      final set = PdfPageSet.load(
          PdfDocument.open(buildMultiPagePdf(2, width: 400, height: 800)),
          viewRotation: 90);
      expect(set.aspects, everyElement(closeTo(0.5, 1e-9)));
      expect(set.pointWidths, everyElement(800));
      expect(set.maxPointHeight, 400);
    });
  });

  group('incremental', () {
    test('an annotation edit re-wraps only its page', () {
      final editing = editingOf(12);
      final before = loadOf(editing);
      editing.addRectangle(7, const PdfRect(100, 100, 200, 200));

      final wasEnabled = PdfPerfLog.enabled;
      PdfPerfLog.enabled = true;
      addTearDown(() => PdfPerfLog.enabled = wasEnabled);
      PdfPerf.reset();
      final change = revise(before, editing);
      final perf = PdfPerf.snapshot();
      PdfPerfLog.enabled = wasEnabled;

      expect(change.mode, PdfPageReconciliationMode.incremental);
      expect(change.fallbackReason, isNull);
      expect(change.dirtyPages, {7});
      expect(change.geometryPages, 0);
      expect(change.walkedPageTree, isFalse);
      expect(perf.phaseCalls[PdfPerfPhase.pageTreeWalk.index], 0,
          reason: 'a dirty-page reconcile must not walk the page tree');
      final next = change.next;
      expect(next.document, same(editing.document));
      expect(next.pages[0], same(before.pages[0]),
          reason: 'a clean page keeps its identity');
      expect(next.pages[7], isNot(same(before.pages[7])),
          reason: 'the dirty page is fenced by a new wrapper');
      expect(next.pages[7].annotations, hasLength(1));
      expect(change.epochMoved, isFalse);
      expect(change.namespaceMoved, isFalse);

      final invalidation = change.invalidation;
      expect(invalidation.annotationPages, {7});
      expect(invalidation.textPages, isEmpty,
          reason: 'an annotation leaves the base content alone');
      expect(invalidation.rasterPages, isEmpty);
      expect(invalidation.warmPages, {7});
      expect(invalidation.previews, PdfPagePreviewFate.rebind);
      expect(invalidation.previewChanged, isEmpty);
      expect(invalidation.primePreviews, isFalse);
      expect(invalidation.retiredTileNamespace, isNull);
      expect(invalidation.viewport, PdfViewportCarry.keep);
      expect(change.remapPage(5), 5);

      // a second edit to the same page resolves the latest dictionary
      editing.addRectangle(7, const PdfRect(220, 220, 280, 280));
      final again = revise(next, editing);
      expect(again.mode, PdfPageReconciliationMode.incremental);
      expect(again.next.pages[0], same(before.pages[0]));
      expect(again.next.pages[7], isNot(same(next.pages[7])));
      expect(again.next.pages[7].annotations, hasLength(2));
    });

    test('a page rotation carries the viewport across new geometry', () {
      final editing = editingOf(4);
      final before = loadOf(editing);
      editing.rotatePages([1], 90);

      final change = revise(before, editing);
      expect(change.mode, PdfPageReconciliationMode.incremental);
      expect(change.dirtyPages, {1});
      expect(change.geometryPages, 1);
      expect(change.next.aspects[1], closeTo(612 / 792, 1e-9));
      expect(change.next.pointWidths[1], 792);
      expect(change.next.maxPointWidth, 792);
      expect(change.invalidation.viewport, PdfViewportCarry.remap);
      expect(change.invalidation.placeViewportNow, isFalse);
      expect(change.epochMoved, isFalse,
          reason: 'rotation changes geometry, not the page-slot lineage');
      expect(change.remapPage(2), 2);
    });

    test('an unknown impact falls back to a full reload', () {
      final editing = editingOf(3);
      final before = loadOf(editing);
      editing.addRectangle(0, const PdfRect(10, 10, 20, 20));
      final change = before.reconcile(editing.document,
          sameLineage: true, impact: PdfEditImpact.unknown);
      expect(change.mode, PdfPageReconciliationMode.fullReload);
      expect(change.fallbackReason, 'unknown-impact-pages');
      expect(change.invalidation.previews, PdfPagePreviewFate.rebind,
          reason: 'same geometry and order: previews rebind');
      expect(change.epochMoved, isFalse);
    });
  });

  group('keyed', () {
    test('a reorder moves state by stable reference', () {
      final editing = editingOf(4);
      final before = loadOf(editing);
      editing.movePage(0, 1);

      final change = revise(before, editing);
      expect(change.mode, PdfPageReconciliationMode.keyedStructure);
      expect(change.dirtyPages, isEmpty);
      expect(change.walkedPageTree, isTrue);
      expect(change.newIndexForOld, [1, 0, 2, 3]);
      expect(change.remapPage(0), 1);
      expect(change.remapPage(1), 0);
      expect(change.next.refs[1], before.refs[0]);
      expect(change.epochMoved, isFalse);
      expect(change.namespaceMoved, isFalse,
          reason: 'keyed page States survive under the same namespace');

      final invalidation = change.invalidation;
      expect(invalidation.retiredTileNamespace, same(before.tileNamespace),
          reason: 'slot-keyed tiles are dropped');
      expect(invalidation.previews, PdfPagePreviewFate.reorder);
      expect(invalidation.rasterPages, isEmpty);
      expect(invalidation.warmPages, isNull,
          reason: 'every wrapper is new, so every warm attempt is dead');
      expect(invalidation.textPages, isNull);
      expect(invalidation.viewport, PdfViewportCarry.remap);
      expect(invalidation.placeViewportNow, isTrue);
      final viewport = change.remapViewport(
          const PdfViewport(page: 0, top: 0.25, left: 0.1, zoom: 2));
      expect(viewport.page, 1, reason: 'the reading position follows its page');
      expect(viewport.top, 0.25);
      expect(viewport.left, 0.1);
      expect(viewport.zoom, 2);

      // undo opens a fresh COS graph and is still a keyed reorder back
      editing.undo();
      final undone = revise(change.next, editing);
      expect(undone.mode, PdfPageReconciliationMode.keyedStructure);
      expect(undone.newIndexForOld, [1, 0, 2, 3]);
      expect(undone.next.refs, before.refs);
    });
  });

  group('full reload', () {
    test('an insert is a new slot lineage that remaps by reference', () {
      final editing = editingOf(3);
      final before = loadOf(editing);
      editing.insertPagesFromBytes(buildMultiPagePdf(1), at: 0);

      final change = revise(before, editing);
      expect(change.mode, PdfPageReconciliationMode.fullReload);
      expect(change.fallbackReason, 'page-structure-changed');
      expect(change.next.length, 4);
      expect(change.dirtyPages, isNull);
      expect(change.epochMoved, isTrue);
      expect(change.namespaceMoved, isTrue);
      expect(
          change.invalidation.retiredTileNamespace, same(before.tileNamespace));
      expect(change.invalidation.previews, PdfPagePreviewFate.clear);
      expect(change.invalidation.primePreviews, isTrue);
      expect(change.invalidation.rasterPages, isNull);
      expect(change.invalidation.warmPages, isNull);
      expect(change.invalidation.viewport, PdfViewportCarry.remap);
      expect(change.invalidation.placeViewportNow, isFalse);
      expect([for (var i = 0; i < 3; i++) change.remapPage(i)], [1, 2, 3],
          reason: 'each old page follows its reference past the insert');
    });

    test('a delete maps the lost page to the one now at its index', () {
      final editing = editingOf(3);
      final before = loadOf(editing);
      editing.removePage(1);

      final change = revise(before, editing);
      expect(change.mode, PdfPageReconciliationMode.fullReload);
      expect(change.next.length, 2);
      expect([for (var i = 0; i < 3; i++) change.remapPage(i)], [0, 1, 1]);
      expect(change.epochMoved, isTrue);
    });

    test('undo to a fresh COS keeps previews and the lineage', () {
      final editing = editingOf(3);
      editing.addRectangle(1, const PdfRect(10, 10, 50, 50));
      final before = loadOf(editing);
      editing.undo();

      final change = revise(before, editing);
      expect(change.mode, PdfPageReconciliationMode.fullReload);
      expect(change.fallbackReason, 'different-cos');
      expect(change.invalidation.previews, PdfPagePreviewFate.rebind);
      expect(change.invalidation.viewport, PdfViewportCarry.keep);
      expect(change.invalidation.warmPages, isNull);
      expect(change.epochMoved, isFalse);
      expect(change.namespaceMoved, isFalse);
      expect(change.next.pages[1].annotations, isEmpty);
    });

    test('a changed content stamp drops only that preview on rebind', () {
      final document = PdfDocument.open(buildMultiPagePdf(4));
      final before = PdfPageSet.load(document);
      final change = before.reconcile(PdfDocument.open(document.cos.bytes),
          sameLineage: true, contentStamp: (i) => i == 2 ? 5 : 0);
      expect(change.fallbackReason, 'no-revision-impact');
      expect(change.invalidation.previews, PdfPagePreviewFate.rebind);
      expect(change.invalidation.previewChanged, {2});
      expect(change.next.contentStamps, [0, 0, 5, 0]);
    });

    test('an unrelated document of the same geometry keeps the viewport', () {
      final before = PdfPageSet.load(PdfDocument.open(buildMultiPagePdf(3)));
      final change = before.reconcile(PdfDocument.open(buildMultiPagePdf(3)),
          sameLineage: false);
      expect(change.fallbackReason, 'unrelated-document-swap');
      expect(change.sameLineage, isFalse);
      expect(change.namespaceMoved, isTrue);
      expect(
          change.invalidation.retiredTileNamespace, same(before.tileNamespace));
      expect(change.invalidation.previews, PdfPagePreviewFate.clear,
          reason: 'geometry alone is not identity');
      expect(change.invalidation.viewport, PdfViewportCarry.keep);
    });

    test('an unrelated document with other page sizes resets the viewport', () {
      final before = PdfPageSet.load(PdfDocument.open(buildMultiPagePdf(3)));
      // same aspect, half the size: the layout's fit reference moves
      final change = before.reconcile(
          PdfDocument.open(buildMultiPagePdf(3, width: 306, height: 396)),
          sameLineage: false);
      expect(change.invalidation.viewport, PdfViewportCarry.reset);
    });
  });

  group('view changes', () {
    test('a view rotation re-lays every page and stales every raster', () {
      final document = PdfDocument.open(buildMultiPagePdf(2));
      final before = PdfPageSet.load(document);
      final change = before.rotated(90);
      expect(change.documentChanged, isFalse);
      expect(change.next.viewRotation, 90);
      expect(change.next.pages[0], same(before.pages[0]));
      expect(change.next.pages[1], same(before.pages[1]));
      expect(change.next.aspects, everyElement(closeTo(612 / 792, 1e-9)));
      expect(change.next.maxPointWidth, 792);
      expect(change.epochMoved, isFalse);
      expect(change.namespaceMoved, isFalse);
      final invalidation = change.invalidation;
      expect(invalidation.textPages, isEmpty);
      expect(invalidation.annotationPages, isEmpty);
      expect(invalidation.rasterPages, isNull);
      expect(invalidation.warmPages, isNull);
      expect(invalidation.previews, PdfPagePreviewFate.clear);
      expect(invalidation.primePreviews, isTrue);
      expect(invalidation.viewport, PdfViewportCarry.keep);
    });

    test('a repaint keeps the set and stales every raster', () {
      final before = PdfPageSet.load(PdfDocument.open(buildMultiPagePdf(2)));
      final change = before.repainted();
      expect(change.next, same(before));
      expect(change.documentChanged, isFalse);
      expect(change.invalidation.rasterPages, isNull);
      expect(change.invalidation.warmPages, isNull);
      expect(change.invalidation.previews, PdfPagePreviewFate.clear);
    });

    test('a later revision keeps the rotation the set was built at', () {
      final editing = editingOf(3);
      final rotated = loadOf(editing).rotated(90).next;
      editing.addRectangle(0, const PdfRect(10, 10, 20, 20));
      final change = revise(rotated, editing);
      expect(change.next.viewRotation, 90);
      expect(change.next.aspects[0], closeTo(612 / 792, 1e-9));
      expect(change.geometryPages, 0);
    });
  });
}

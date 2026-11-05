import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosDictionary, CosReference;
import 'package:pdf_document/pdf_document.dart';

import 'viewport.dart';

/// How the viewer reconciled its page presentation across a document change.
enum PdfPageReconciliationMode {
  /// Only pages named by the edit impact were re-wrapped.
  incremental,

  /// Stable page identities were used to reconcile a structural change.
  keyedStructure,

  /// The complete page list and its presentation state were rebuilt.
  fullReload,
}

/// A page's stable identity across incremental revisions: its indirect
/// object number and generation.
typedef PdfPageRef = (int, int);

/// The display rotation of [page] under [viewRotation]: its own /Rotate plus
/// the view's, normalised to 0/90/180/270.
int pdfEffectiveRotation(PdfPage page, int viewRotation) =>
    ((page.rotation + viewRotation) % 360 + 360) % 360;

/// [page]'s displayed height / width after /Rotate and [viewRotation].
double pdfPageAspect(PdfPage page, int viewRotation) {
  final box = page.cropBox;
  return switch (pdfEffectiveRotation(page, viewRotation)) {
    90 || 270 => box.width / math.max(1e-6, box.height),
    _ => box.height / math.max(1e-6, box.width),
  };
}

/// [page]'s displayed width in PDF points after /Rotate and [viewRotation].
double pdfPagePointWidth(PdfPage page, int viewRotation) {
  final box = page.cropBox;
  return switch (pdfEffectiveRotation(page, viewRotation)) {
    90 || 270 => math.max(1e-6, box.height),
    _ => math.max(1e-6, box.width),
  };
}

/// The stable identity of [page]. Structural edits rewrite the page tree but
/// keep every surviving leaf's indirect object number; inserted pages get new
/// numbers. Read when pages load: an incremental edit evicts the reverse-cache
/// entry for every rewritten page before the viewer hears of it, so asking an
/// old [PdfPage] during the swap would return null and make an annotation
/// edit look like a reorder.
PdfPageRef? pdfPageReferenceKey(PdfPage page) {
  final ref = page.document.cos.referenceTo(page.dict);
  return ref == null ? null : (ref.objectNumber, ref.generation);
}

bool _close(double a, double b) => (a - b).abs() <= 1e-6;

/// The viewer's pages as one value: the document they came from, a wrapper
/// and stable reference per page, the layout geometry under a view rotation,
/// the content stamps the cached previews reflect, and the presentation
/// lineage (slot [epoch] and process-wide [tileNamespace]).
///
/// A set never changes. Moving to another revision, rotation or paint is a
/// [PdfPageSetChange] - see [reconcile], [rotated] and [repainted] - that
/// carries the next set and the one [PdfPageInvalidation] every cache and
/// warm loop applies.
@immutable
class PdfPageSet {
  PdfPageSet._({
    required this.document,
    required List<PdfPage> pages,
    required List<PdfPageRef?> refs,
    required List<double> aspects,
    required List<double> pointWidths,
    required List<int> contentStamps,
    required this.viewRotation,
    required this.epoch,
    required this.tileNamespace,
    (double, double)? maxSize,
  })  : pages = List<PdfPage>.unmodifiable(pages),
        refs = List<PdfPageRef?>.unmodifiable(refs),
        aspects = List<double>.unmodifiable(aspects),
        pointWidths = List<double>.unmodifiable(pointWidths),
        contentStamps = List<int>.unmodifiable(contentStamps) {
    final (width, height) = maxSize ?? _maxSize(this.aspects, this.pointWidths);
    maxPointWidth = width;
    maxPointHeight = height;
  }

  /// Reads every page of [document] - a full page-tree walk.
  factory PdfPageSet.load(
    PdfDocument document, {
    int viewRotation = 0,
    int epoch = 0,
    Object? tileNamespace,
    int Function(int index)? contentStamp,
  }) {
    final pages = document.pages;
    return PdfPageSet._(
      document: document,
      pages: pages,
      refs: [for (final page in pages) pdfPageReferenceKey(page)],
      aspects: [for (final page in pages) pdfPageAspect(page, viewRotation)],
      pointWidths: [
        for (final page in pages) pdfPagePointWidth(page, viewRotation)
      ],
      contentStamps: [
        for (var i = 0; i < pages.length; i++) contentStamp?.call(i) ?? 0
      ],
      viewRotation: viewRotation,
      epoch: epoch,
      tileNamespace: tileNamespace ?? Object(),
    );
  }

  final PdfDocument document;
  final List<PdfPage> pages;
  final List<PdfPageRef?> refs;

  /// Height / width per page, after /Rotate and [viewRotation].
  final List<double> aspects;

  /// Displayed width per page in PDF points.
  final List<double> pointWidths;

  /// The widest page's point width and the tallest page's point height - the
  /// fit references for the vertical and horizontal layouts.
  late final double maxPointWidth;
  late final double maxPointHeight;

  /// Each page's content stamp as of the previews the viewer holds (0 outside
  /// an editing session).
  final List<int> contentStamps;

  final int viewRotation;

  /// The page-slot lineage: advances when pages shift under their slots, so a
  /// slot-reused page view drops the raster of the page that used to be there.
  final int epoch;

  /// The process-wide tile-cache boundary for this lineage.
  final Object tileNamespace;

  int get length => pages.length;
  bool get isEmpty => pages.isEmpty;

  static (double, double) _maxSize(List<double> aspects, List<double> widths) {
    var width = 0.0;
    var height = 0.0;
    for (var i = 0; i < widths.length; i++) {
      width = math.max(width, widths[i]);
      height = math.max(height, aspects[i] * widths[i]);
    }
    return (width, height);
  }

  /// Whether [other] lays out exactly like this set: same page count, aspect
  /// and point width per page.
  bool sameGeometryAs(PdfPageSet other) {
    if (other.length != length) return false;
    for (var i = 0; i < length; i++) {
      if (!_close(aspects[i], other.aspects[i]) ||
          !_close(pointWidths[i], other.pointWidths[i])) {
        return false;
      }
    }
    return true;
  }

  PdfPageSet _with({
    PdfDocument? document,
    List<PdfPage>? pages,
    List<PdfPageRef?>? refs,
    List<double>? aspects,
    List<double>? pointWidths,
    List<int>? contentStamps,
    int? viewRotation,
    bool keepMaxSize = false,
  }) =>
      PdfPageSet._(
        document: document ?? this.document,
        pages: pages ?? this.pages,
        refs: refs ?? this.refs,
        aspects: aspects ?? this.aspects,
        pointWidths: pointWidths ?? this.pointWidths,
        contentStamps: contentStamps ?? this.contentStamps,
        viewRotation: viewRotation ?? this.viewRotation,
        epoch: epoch,
        tileNamespace: tileNamespace,
        maxSize: keepMaxSize ? (maxPointWidth, maxPointHeight) : null,
      );

  /// The change from this set to [next]'s pages.
  ///
  /// [sameLineage] says [next] is a revision of this set's document (an edit,
  /// undo, form fill) rather than an unrelated file. A revision with a known
  /// [impact] tries, in order, the incremental path (only the dirty pages are
  /// re-wrapped; no page-tree walk) and the keyed path (a pure reorder matched
  /// by stable reference); anything else is a full reload. [contentStamp]
  /// reads the editing controller's per-page content stamp.
  PdfPageSetChange reconcile(
    PdfDocument next, {
    required bool sameLineage,
    PdfEditImpact? impact,
    int Function(int index)? contentStamp,
  }) {
    if (!sameLineage) {
      return _fullReload(next,
          sameLineage: false,
          reason: 'unrelated-document-swap',
          contentStamp: contentStamp);
    }
    final String reason;
    if (impact == null) {
      reason = 'no-revision-impact';
    } else if (impact.pageStructureChanged) {
      if (!impact.pageOrderOnly) {
        reason = 'page-structure-changed';
      } else if (impact.visualPages?.isEmpty != true ||
          impact.contentPages?.isEmpty != true ||
          impact.annotationPages?.isEmpty != true) {
        reason = 'page-order-mixed-impact';
      } else {
        final keyed = _keyed(next, contentStamp);
        if (keyed is PdfPageSetChange) return keyed;
        reason = keyed as String;
      }
    } else {
      final incremental = _incremental(next, impact, contentStamp);
      if (incremental is PdfPageSetChange) return incremental;
      reason = incremental as String;
    }
    return _fullReload(next,
        sameLineage: true, reason: reason, contentStamp: contentStamp);
  }

  /// Either the incremental change or why it does not apply.
  Object _incremental(
    PdfDocument next,
    PdfEditImpact impact,
    int Function(int index)? contentStamp,
  ) {
    if (!identical(document.cos, next.cos)) return 'different-cos';
    final visualPages = impact.visualPages;
    final contentPages = impact.contentPages;
    final annotationPages = impact.annotationPages;
    if (visualPages == null ||
        contentPages == null ||
        annotationPages == null) {
      return 'unknown-impact-pages';
    }
    final dirty = <int>{...visualPages, ...contentPages, ...annotationPages};
    if (dirty.any((page) => page < 0 || page >= length)) {
      return 'invalid-dirty-page';
    }
    final pages = List<PdfPage>.of(this.pages);
    final aspects = List<double>.of(this.aspects);
    final pointWidths = List<double>.of(this.pointWidths);
    var geometryPages = 0;
    for (final index in dirty) {
      final key = refs[index];
      if (key == null) return 'missing-stable-page-reference';
      final resolved = next.cos.resolve(CosReference(key.$1, key.$2));
      if (resolved is! CosDictionary) return 'unresolved-page';
      // Geometry is read only for pages the transaction dirtied: most
      // revisions change pixels, not the page box. A rotation or crop change
      // updates its one record; later pages' offsets derive from it at layout.
      final page = pages[index].forIncrementalRevision(next, resolved);
      final aspect = pdfPageAspect(page, viewRotation);
      final width = pdfPagePointWidth(page, viewRotation);
      if (!_close(aspect, aspects[index]) ||
          !_close(width, pointWidths[index])) {
        geometryPages++;
      }
      pages[index] = page;
      aspects[index] = aspect;
      pointWidths[index] = width;
    }
    final stamps = List<int>.of(contentStamps);
    for (final page in contentPages) {
      stamps[page] = contentStamp?.call(page) ?? 0;
    }
    final changedContent = Set<int>.unmodifiable(contentPages);
    return PdfPageSetChange._(
      previous: this,
      next: _with(
        document: next,
        pages: pages,
        aspects: aspects,
        pointWidths: pointWidths,
        contentStamps: stamps,
        keepMaxSize: geometryPages == 0,
      ),
      mode: PdfPageReconciliationMode.incremental,
      dirtyPages: Set<int>.unmodifiable(dirty),
      geometryPages: geometryPages,
      walkedPageTree: false,
      invalidation: PdfPageInvalidation._(
        textPages: changedContent,
        annotationPages: Set<int>.unmodifiable(annotationPages),
        rasterPages: changedContent,
        warmPages: Set<int>.unmodifiable(dirty),
        previews:
            dirty.isEmpty ? PdfPagePreviewFate.bind : PdfPagePreviewFate.rebind,
        previewChanged: changedContent,
        viewport:
            geometryPages > 0 ? PdfViewportCarry.remap : PdfViewportCarry.keep,
      ),
    );
  }

  /// Either the keyed reorder change or why it does not apply.
  Object _keyed(PdfDocument next, int Function(int index)? contentStamp) {
    final nextPages = next.pages;
    final count = nextPages.length;
    if (count != length) return 'page-order-count-changed';
    final oldIndexByRef = <PdfPageRef, int>{};
    for (var i = 0; i < length; i++) {
      final ref = refs[i];
      if (ref == null) return 'missing-stable-page-reference';
      if (oldIndexByRef.containsKey(ref)) {
        return 'duplicate-stable-page-reference';
      }
      oldIndexByRef[ref] = i;
    }
    // The one unavoidable structural cost: walk the new tree to verify its
    // leaf identities and order. The presentation itself is moved, not rebuilt.
    final refsOut = <PdfPageRef>[];
    final oldIndexForNew = <int>[];
    for (final page in nextPages) {
      final ref = pdfPageReferenceKey(page);
      if (ref == null) return 'missing-new-page-reference';
      final oldIndex = oldIndexByRef[ref];
      if (oldIndex == null) return 'page-order-identity-changed';
      if (!_close(pdfPageAspect(page, viewRotation), aspects[oldIndex]) ||
          !_close(
              pdfPagePointWidth(page, viewRotation), pointWidths[oldIndex])) {
        return 'page-order-geometry-changed';
      }
      refsOut.add(ref);
      oldIndexForNew.add(oldIndex);
    }
    if (oldIndexForNew.toSet().length != count) {
      return 'page-order-not-a-permutation';
    }
    final newIndexForOld = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      newIndexForOld[oldIndexForNew[i]] = i;
    }
    return PdfPageSetChange._(
      previous: this,
      next: _with(
        document: next,
        pages: nextPages,
        refs: refsOut,
        aspects: [for (final old in oldIndexForNew) aspects[old]],
        pointWidths: [for (final old in oldIndexForNew) pointWidths[old]],
        contentStamps: [
          for (var i = 0; i < count; i++) contentStamp?.call(i) ?? 0
        ],
        keepMaxSize: true,
      ),
      mode: PdfPageReconciliationMode.keyedStructure,
      dirtyPages: const <int>{},
      geometryPages: 0,
      walkedPageTree: true,
      newIndexForOld: List<int>.unmodifiable(newIndexForOld),
      invalidation: PdfPageInvalidation._(
        // these carry their page index and document wrapper; cheap next to
        // rendering, and undo opens a fresh COS graph
        textPages: null,
        annotationPages: null,
        rasterPages: const <int>{},
        // every wrapper is new, so every identity-keyed attempt is dead
        warmPages: null,
        previews: PdfPagePreviewFate.reorder,
        // tiles are keyed by slot: drop them, keep the namespace (and with it
        // the keyed page States)
        retiredTileNamespace: tileNamespace,
        viewport: PdfViewportCarry.remap,
        placeViewportNow: true,
      ),
    );
  }

  PdfPageSetChange _fullReload(
    PdfDocument next, {
    required bool sameLineage,
    required String reason,
    int Function(int index)? contentStamp,
  }) {
    final loaded = PdfPageSet.load(next,
        viewRotation: viewRotation,
        epoch: epoch,
        tileNamespace: tileNamespace,
        contentStamp: contentStamp);
    final sameGeometry = sameGeometryAs(loaded);
    var orderChanged = false;
    if (sameLineage) {
      if (loaded.length != length) {
        orderChanged = true;
      } else {
        for (var i = 0; i < length && !orderChanged; i++) {
          orderChanged = refs[i] != loaded.refs[i];
        }
      }
    }
    // Only a revision keeps its previews, rebound to the new wrappers; a
    // page whose content stamp advanced (a redaction burn) drops its own.
    // Geometry alone is not identity: two unrelated same-sized files must
    // not share previews.
    final canRebind = sameLineage && sameGeometry && !orderChanged;
    // An unrelated file's namespace can never be reached again, and a
    // structural revision is a new slot lineage: retire the namespace so
    // late tile completions stay unreachable.
    final newNamespace = !sameLineage || orderChanged;
    final PdfViewportCarry viewport;
    if (sameLineage && !isEmpty && (!sameGeometry || orderChanged)) {
      viewport = PdfViewportCarry.remap;
    } else if (!sameGeometry) {
      viewport = PdfViewportCarry.reset;
    } else {
      viewport = PdfViewportCarry.keep;
    }
    final nextSet = PdfPageSet._(
      document: next,
      pages: loaded.pages,
      refs: loaded.refs,
      aspects: loaded.aspects,
      pointWidths: loaded.pointWidths,
      contentStamps: loaded.contentStamps,
      viewRotation: viewRotation,
      epoch: canRebind ? epoch : epoch + 1,
      tileNamespace: newNamespace ? Object() : tileNamespace,
      maxSize: (loaded.maxPointWidth, loaded.maxPointHeight),
    );
    return PdfPageSetChange._(
      previous: this,
      next: nextSet,
      mode: PdfPageReconciliationMode.fullReload,
      fallbackReason: reason,
      sameLineage: sameLineage,
      dirtyPages: null,
      geometryPages: nextSet.length,
      walkedPageTree: true,
      invalidation: PdfPageInvalidation._(
        textPages: null,
        annotationPages: null,
        rasterPages: null,
        warmPages: null,
        previews:
            canRebind ? PdfPagePreviewFate.rebind : PdfPagePreviewFate.clear,
        previewChanged: canRebind
            ? {
                for (var i = 0; i < length; i++)
                  if (contentStamps[i] != nextSet.contentStamps[i]) i,
              }
            : const <int>{},
        retiredTileNamespace: newNamespace ? tileNamespace : null,
        viewport: viewport,
      ),
    );
  }

  /// The change to [viewRotation]: every page's geometry and raster
  /// signature move, the pages themselves do not.
  PdfPageSetChange rotated(int viewRotation) => PdfPageSetChange._(
        previous: this,
        next: _with(
          viewRotation: viewRotation,
          aspects: [
            for (final page in pages) pdfPageAspect(page, viewRotation)
          ],
          pointWidths: [
            for (final page in pages) pdfPagePointWidth(page, viewRotation)
          ],
        ),
        invalidation: PdfPageInvalidation._repaint,
      );

  /// The change to a new paper colour or annotation visibility: baked into
  /// every preview and raster signature, so every one is stale.
  PdfPageSetChange repainted() => PdfPageSetChange._(
        previous: this,
        next: this,
        invalidation: PdfPageInvalidation._repaint,
      );
}

/// What becomes of the preview cache across a change.
enum PdfPagePreviewFate {
  /// Bind the (identical) pages; nothing is dropped.
  bind,

  /// Rebind in place, dropping [PdfPageInvalidation.previewChanged].
  rebind,

  /// Move every entry along [PdfPageSetChange.newIndexForOld].
  reorder,

  /// Drop everything and re-prime from disk.
  clear,
}

/// What becomes of the reading position across a change.
enum PdfViewportCarry {
  /// Nothing moved under it.
  keep,

  /// Capture it against the old set, then place it on the remapped page.
  remap,

  /// A different file: back to the top at a fresh fit.
  reset,
}

/// What one [PdfPageSetChange] invalidates. Page sets are by index in the
/// *next* set unless noted; null means every page.
@immutable
class PdfPageInvalidation {
  const PdfPageInvalidation._({
    required this.textPages,
    required this.annotationPages,
    required this.rasterPages,
    required this.warmPages,
    required this.previews,
    this.previewChanged = const <int>{},
    this.retiredTileNamespace,
    this.viewport = PdfViewportCarry.keep,
    this.placeViewportNow = false,
  });

  static const _repaint = PdfPageInvalidation._(
    textPages: <int>{},
    annotationPages: <int>{},
    rasterPages: null,
    warmPages: null,
    previews: PdfPagePreviewFate.clear,
  );

  /// Pages whose extracted text is stale.
  final Set<int>? textPages;

  /// Pages whose annotation, visible-annotation and form-field caches are
  /// stale.
  final Set<int>? annotationPages;

  /// Pages whose painted raster no longer shows the page. Readiness of the
  /// rest carries over (through [PdfPageSetChange.newIndexForOld] on a
  /// reorder).
  final Set<int>? rasterPages;

  /// Pages - by index in the *previous* set - whose background-warm attempts
  /// are stale: their wrapper was replaced or everything they would render
  /// changed. Null resets every lane, including the once-per-document heavy
  /// command warm.
  final Set<int>? warmPages;

  final PdfPagePreviewFate previews;

  /// For [PdfPagePreviewFate.rebind]: pages whose preview is stale.
  final Set<int> previewChanged;

  /// A tile namespace whose tiles are all stale. It is the previous set's;
  /// the next set carries a fresh one unless the keyed States must survive.
  final Object? retiredTileNamespace;

  final PdfViewportCarry viewport;

  /// The remapped viewport must be placed before the next layout (a reorder
  /// keeps the exact extent, and deferring would let the lazy list collect a
  /// long-moved page between its old and new slots).
  final bool placeViewportNow;

  /// Whether the disk-backed previews must be re-primed.
  bool get primePreviews => previews == PdfPagePreviewFate.clear;
}

/// One move of the viewer's page set: the next set, how it was reached, and
/// what it invalidates.
@immutable
class PdfPageSetChange {
  const PdfPageSetChange._({
    required this.previous,
    required this.next,
    required this.invalidation,
    this.mode,
    this.fallbackReason,
    this.sameLineage = true,
    this.dirtyPages = const <int>{},
    this.geometryPages = 0,
    this.walkedPageTree = false,
    this.newIndexForOld,
  });

  final PdfPageSet previous;
  final PdfPageSet next;
  final PdfPageInvalidation invalidation;

  /// How a document change was reconciled; null for a rotation or repaint,
  /// which keep the document.
  final PdfPageReconciliationMode? mode;

  /// Why a revision fell back to [PdfPageReconciliationMode.fullReload].
  final String? fallbackReason;

  /// False when the next document is unrelated to the previous one.
  final bool sameLineage;

  /// Pages whose wrapper was replaced; null when the change has no
  /// trustworthy dirty-page boundary.
  final Set<int>? dirtyPages;

  /// Pages whose geometry was (re)computed and differed, or every page on a
  /// full reload.
  final int geometryPages;
  final bool walkedPageTree;

  /// For a reorder: each old page's index in [next].
  final List<int>? newIndexForOld;

  bool get documentChanged => mode != null;
  bool get epochMoved => next.epoch != previous.epoch;
  bool get namespaceMoved =>
      !identical(next.tileNamespace, previous.tileNamespace);

  /// [viewport], captured against [previous], as it reads in [next]: the
  /// same fractions and zoom on the page it was on, wherever that page went.
  PdfViewport remapViewport(PdfViewport viewport) => PdfViewport(
        page: remapPage(viewport.page),
        top: viewport.top,
        left: viewport.left,
        zoom: viewport.zoom,
      );

  /// Where old page [oldIndex] is in [next]: moved with a reorder, matched by
  /// stable reference across a full revision, otherwise the same index. A
  /// deleted page maps to the page now at its index (the following one), or
  /// the last page.
  int remapPage(int oldIndex) {
    final count = next.length;
    if (count == 0) return 0;
    final moved = newIndexForOld;
    if (moved != null && oldIndex >= 0 && oldIndex < moved.length) {
      return moved[oldIndex];
    }
    if (mode == PdfPageReconciliationMode.fullReload &&
        sameLineage &&
        oldIndex >= 0 &&
        oldIndex < previous.length) {
      final ref = previous.refs[oldIndex];
      if (ref != null) {
        final matched = next.refs.indexOf(ref);
        if (matched >= 0) return matched;
      }
    }
    return oldIndex.clamp(0, count - 1);
  }
}

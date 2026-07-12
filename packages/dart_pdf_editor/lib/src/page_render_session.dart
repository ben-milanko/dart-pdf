import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_scheduler.dart';

/// The page and viewport state that determines what pixels a page view needs.
///
/// Adapter choices (local rendering, a worker, caches, and retained scenes)
/// deliberately do not participate in this identity. They may change how a
/// request is fulfilled, but not which result is current.
@immutable
class PdfPageRenderIntent {
  const PdfPageRenderIntent({
    required this.page,
    required this.pageIndex,
    required this.pageEpoch,
    required this.contentStamp,
    required this.destructiveStamp,
    required this.trustContentStamp,
    required this.rotation,
    required this.pageColor,
    required this.showAnnotations,
    required this.scale,
    required this.settleGeneration,
  });

  final PdfPage page;
  final int pageIndex;
  final int pageEpoch;
  final int contentStamp;
  final int destructiveStamp;
  final bool trustContentStamp;
  final int? rotation;
  final Color pageColor;
  final bool showAnnotations;
  final double scale;
  final int settleGeneration;
}

/// Actions required when a page render session receives a new intent.
@immutable
class PdfPageRenderTransition {
  const PdfPageRenderTransition({
    required this.dropBaseRaster,
    required this.dropPreview,
    required this.dropPicture,
    required this.dropDetail,
    required this.scheduleRender,
  });

  static const none = PdfPageRenderTransition(
    dropBaseRaster: false,
    dropPreview: false,
    dropPicture: false,
    dropDetail: false,
    scheduleRender: false,
  );

  final bool dropBaseRaster;
  final bool dropPreview;
  final bool dropPicture;
  final bool dropDetail;
  final bool scheduleRender;
}

/// Owns page-render identity, invalidation, scheduling, and result freshness.
///
/// The rendering implementations remain separate adapters. This session is
/// intentionally a small synchronous control plane around them, so it adds no
/// work inside command replay, rasterization, or pixel transfer loops.
class PdfPageRenderSession {
  PdfPageRenderSession(PdfPageRenderIntent intent) : _intent = intent;

  PdfPageRenderIntent _intent;
  int _fullGeneration = 0;
  int _detailGeneration = 0;
  bool _holdPending = false;
  bool _disposed = false;

  PdfPageRenderIntent get intent => _intent;

  /// Computes the invalidation outcome and rejects all older async results
  /// before the adapters are asked to produce replacement pixels.
  PdfPageRenderTransition update(PdfPageRenderIntent next) {
    final old = _intent;
    _intent = next;

    final blanked = old.pageEpoch != next.pageEpoch ||
        old.destructiveStamp != next.destructiveStamp;
    final contentChanged = old.contentStamp != next.contentStamp;
    final pageIdentityChanged = !identical(old.page, next.page);
    final nonContentVisualChanged =
        (pageIdentityChanged && !next.trustContentStamp) ||
            old.trustContentStamp != next.trustContentStamp ||
            old.rotation != next.rotation ||
            old.pageColor != next.pageColor ||
            old.showAnnotations != next.showAnnotations;
    final visualChanged = contentChanged || nonContentVisualChanged;
    final viewportChanged = old.scale != next.scale ||
        old.settleGeneration != next.settleGeneration;
    final pageSlotChanged = old.pageIndex != next.pageIndex;
    final schedule = blanked || visualChanged || viewportChanged;

    // A slot change alone is not a render trigger: structural edits carry a
    // page epoch, while reorder reconciliation may merely move the same
    // already-current page state. It does invalidate in-flight results so a
    // worker response cannot be accepted into the recycled slot.
    if (schedule || pageSlotChanged) {
      invalidateFull();
      invalidateDetail();
    }
    if (!schedule) return PdfPageRenderTransition.none;

    return PdfPageRenderTransition(
      dropBaseRaster: blanked,
      dropPreview: blanked,
      dropPicture: blanked || visualChanged,
      // Additive annotation edits keep the existing sharp detail until the
      // fresh patch arrives; destructive/display changes cannot safely do so.
      dropDetail: blanked || nonContentVisualChanged,
      scheduleRender: true,
    );
  }

  int beginFull() => ++_fullGeneration;
  void invalidateFull() => _fullGeneration++;

  int beginDetail() => ++_detailGeneration;
  void invalidateDetail() => _detailGeneration++;

  bool acceptsFull(int generation, int pageIndex) =>
      !_disposed &&
      generation == _fullGeneration &&
      pageIndex == _intent.pageIndex;

  bool acceptsDetail(int generation) =>
      !_disposed && generation == _detailGeneration;

  bool matchesPage(int pageIndex) =>
      !_disposed && pageIndex == _intent.pageIndex;

  bool get hasPendingHold => _holdPending;

  bool releaseHold() {
    if (!_holdPending) return false;
    _holdPending = false;
    return true;
  }

  bool paused({
    required PdfPageRenderScheduler? scheduler,
    required ValueListenable<bool>? hold,
  }) =>
      scheduler?.holding ?? (hold?.value ?? false);

  /// Routes a render through the shared scheduler, or through the standalone
  /// widget's hold fallback when no scheduler adapter is supplied.
  Future<void> request({
    required Object owner,
    required bool hasPicture,
    required PdfPageRenderScheduler? scheduler,
    required ValueListenable<bool>? hold,
    required Future<void> Function() render,
  }) async {
    if (_disposed) return;
    if (scheduler != null) {
      scheduler.request(owner, _intent.pageIndex, render);
      return;
    }
    if (!hasPicture && (hold?.value ?? false)) {
      _holdPending = true;
      return;
    }
    await render();
  }

  void dispose() {
    _disposed = true;
    _holdPending = false;
    invalidateFull();
    invalidateDetail();
  }
}

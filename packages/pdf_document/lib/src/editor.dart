import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';

import 'annotation.dart';
import 'comments.dart';
import 'content_elements.dart';
import 'content_writer.dart';
import 'document.dart';
import 'font_embedder.dart';
import 'form.dart';
import 'image.dart';
import 'matrix_geometry.dart';
import 'measure.dart';
import 'outline.dart';
import 'pades.dart';
import 'page.dart';
import 'page_labels.dart';
import 'rect.dart';
import 'signing_identity.dart';
import 'simple_font.dart';
import 'stamp_template.dart';
import 'struct_tree.dart';
import 'takeoff.dart';
import 'content_run_rewriter.dart';
import 'text_box_appearance.dart';
import 'type0_font.dart';
import 'xmp.dart';

part 'annotation_clipboard.dart';
part 'annotation_editor.dart';
part 'annotation_sync.dart';
part 'comment_editor.dart';
part 'attachment_editor.dart';
part 'content_editor.dart';
part 'color_processing.dart';
part 'content_editor_type0.dart';
part 'content_reflow.dart';
part 'header_footer.dart';
part 'outline_editor.dart';
part 'page_labels_editor.dart';
part 'page_annotation_list.dart';
part 'redaction.dart';
part 'form_admin.dart';
part 'form_editor.dart';
part 'form_styling.dart';
part 'ocr_editor.dart';
part 'pades_editor.dart';
part 'page_editor.dart';
part 'signature_editor.dart';
part 'struct_tree_editor.dart';
part 'vector_snapshot.dart';

/// The observable consequences of one [PdfEditor] mutation session.
///
/// A null page set means every page; an empty set means no pages. Keeping
/// visual, base-content, and annotation-sync effects separate lets hosts
/// invalidate exactly what changed without understanding the PDF operation
/// that produced it.
class PdfEditImpact {
  const PdfEditImpact._({
    required this.visualPages,
    required this.contentPages,
    required this.annotationPages,
    required this.pageStructureChanged,
    required this.destructive,
  });

  /// No observable document change.
  static const none = PdfEditImpact._(
    visualPages: <int>{},
    contentPages: <int>{},
    annotationPages: <int>{},
    pageStructureChanged: false,
    destructive: false,
  );

  /// Conservative fallback for a mutation that has not reported its impact.
  static const unknown = PdfEditImpact._(
    visualPages: null,
    contentPages: null,
    annotationPages: null,
    pageStructureChanged: false,
    destructive: false,
  );

  /// Creates the legacy impact shape used by older
  /// `PdfEditingController.apply(pages:, contentPages:)` callers.
  factory PdfEditImpact.legacy({
    Iterable<int>? pages,
    Iterable<int>? contentPages,
  }) {
    final visual = pages == null ? null : Set<int>.unmodifiable(pages);
    final content =
        contentPages == null ? visual : Set<int>.unmodifiable(contentPages);
    // The old controller used an empty render set to mean "diff annotation
    // metadata across the document". Preserve that behavior for legacy
    // callers; editor-reported impact can name the exact annotation pages.
    final annotations = visual != null && visual.isEmpty ? null : visual;
    return PdfEditImpact._(
      visualPages: visual,
      contentPages: content,
      annotationPages: annotations,
      pageStructureChanged: false,
      destructive: false,
    );
  }

  /// Reconstructs a reported impact after an asynchronous editor mutation.
  factory PdfEditImpact.reported({
    required Iterable<int>? visualPages,
    required Iterable<int>? contentPages,
    required Iterable<int>? annotationPages,
    bool pageStructureChanged = false,
    bool destructive = false,
  }) =>
      PdfEditImpact._(
        visualPages:
            visualPages == null ? null : Set<int>.unmodifiable(visualPages),
        contentPages:
            contentPages == null ? null : Set<int>.unmodifiable(contentPages),
        annotationPages: annotationPages == null
            ? null
            : Set<int>.unmodifiable(annotationPages),
        pageStructureChanged: pageStructureChanged,
        destructive: destructive,
      );

  /// Pages whose visible rendering changed; null means every page.
  final Set<int>? visualPages;

  /// Pages whose base page-content raster changed; null means every page.
  final Set<int>? contentPages;

  /// Pages whose syncable annotations changed; null means every page.
  final Set<int>? annotationPages;

  /// Whether page indices/geometry may have shifted across the document.
  final bool pageStructureChanged;

  /// Whether existing page content was irreversibly removed.
  final bool destructive;
}

class _PdfEditImpactBuilder {
  bool known = false;
  Set<int>? visualPages = <int>{};
  Set<int>? contentPages = <int>{};
  Set<int>? annotationPages = <int>{};
  bool pageStructureChanged = false;
  bool destructive = false;

  Set<int>? _merge(Set<int>? current, Iterable<int>? next) {
    if (current == null || next == null) return null;
    current.addAll(next);
    return current;
  }

  void add({
    Iterable<int>? visual = const <int>[],
    Iterable<int>? content = const <int>[],
    Iterable<int>? annotations = const <int>[],
    bool structure = false,
    bool removesContent = false,
  }) {
    known = true;
    visualPages = _merge(visualPages, visual);
    contentPages = _merge(contentPages, content);
    annotationPages = _merge(annotationPages, annotations);
    pageStructureChanged |= structure;
    destructive |= removesContent;
  }

  PdfEditImpact build({required bool hasChanges}) {
    if (!hasChanges) return PdfEditImpact.none;
    if (!known) return PdfEditImpact.unknown;
    return PdfEditImpact._(
      visualPages:
          visualPages == null ? null : Set<int>.unmodifiable(visualPages!),
      contentPages:
          contentPages == null ? null : Set<int>.unmodifiable(contentPages!),
      annotationPages: annotationPages == null
          ? null
          : Set<int>.unmodifiable(annotationPages!),
      pageStructureChanged: pageStructureChanged,
      destructive: destructive,
    );
  }
}

/// High-level editing session over a [PdfDocument].
///
/// Edits accumulate and [save] appends them as one incremental update, so
/// the original file content - including any digital signatures - survives.
class PdfEditor {
  PdfEditor(this.document) : _updater = CosIncrementalUpdater(document.cos);

  final PdfDocument document;
  final CosIncrementalUpdater _updater;
  final _impact = _PdfEditImpactBuilder();

  /// Pages whose original content this session already wrapped in q/Q.
  final Set<CosDictionary> _wrappedPages = {};

  /// Session-time open/closed intent for outline items, keyed by object
  /// number. Lets a childless item remember the state it was created with
  /// until it gains children (whose /Count then records the sign). Reopened
  /// documents fall back to the /Count sign - see [PdfOutlineEditing].
  final Map<int, bool> _outlineOpenOverride = {};

  /// The document-default measurement scale, set by
  /// [PdfAnnotationEditing.setMeasurementScale]; [PdfAnnotationEditing.addMeasurement]
  /// uses it when no per-annotation override is given.
  PdfMeasure? _defaultMeasure;

  bool get hasChanges => _updater.hasChanges;

  /// The rendering, sync, and structural consequences reported by the
  /// mutations staged in this editor session.
  ///
  /// Uninstrumented mutations conservatively return [PdfEditImpact.unknown]
  /// when they staged changes, preserving correctness while making missing
  /// locality visible to tests and diagnostics.
  PdfEditImpact get impact => _impact.build(hasChanges: hasChanges);

  void _markMetadata({Iterable<int> annotationPages = const <int>[]}) =>
      _impact.add(annotations: annotationPages);

  void _markVisual(Iterable<int>? pages) => _impact.add(visual: pages);

  void _markAnnotations(Iterable<int> pages, {bool visual = true}) =>
      _impact.add(visual: visual ? pages : const <int>[], annotations: pages);

  void _markContent(Iterable<int> pages) =>
      _impact.add(visual: pages, content: pages);

  void _markStructure() => _impact.add(
        visual: null,
        content: null,
        annotations: null,
        structure: true,
      );

  void _markDestructive([Iterable<int>? pages]) => _impact.add(
        visual: pages,
        content: pages,
        annotations: pages,
        removesContent: true,
      );

  /// Updates document information entries. Null leaves an entry unchanged.
  void setInfo({
    String? title,
    String? author,
    String? subject,
    String? keywords,
    String? creator,
    String? producer,
  }) {
    final cos = document.cos;
    final existingRef = cos.trailer['Info'];
    final existing = cos.resolve(existingRef);
    final dict = existing is CosDictionary
        ? CosDictionary({...existing.entries})
        : CosDictionary();

    void put(String key, String? value) {
      if (value != null) dict[key] = CosString.fromText(value);
    }

    put('Title', title);
    put('Author', author);
    put('Subject', subject);
    put('Keywords', keywords);
    put('Creator', creator);
    put('Producer', producer);

    if (existing is CosDictionary && existingRef is CosReference) {
      _updater.replaceObject(existingRef.objectNumber, dict);
    } else {
      _updater.setTrailerEntry('Info', _updater.addObject(dict));
    }
    _markMetadata();
  }

  /// Adds [degrees] (a multiple of 90) to the page's display rotation.
  void rotatePage(int index, int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(degrees, 'degrees', 'must be a multiple of 90');
    }
    final page = document.page(index);
    final next = (page.rotation + degrees) % 360;
    page.dict['Rotate'] = CosInteger(next < 0 ? next + 360 : next);
    _updater.markChanged(page.dict);
    _regenerateFormAppearancesOnPage(index);
    _markContent([index]);
  }

  /// The full bytes of the edited file (original + incremental update).
  Uint8List save() => _updater.save();

  /// Only the bytes to append to the source document to form the edited file
  /// (see [CosIncrementalUpdater.saveTail]).
  ///
  /// For a caller that already holds the source bytes and keeps revisions as
  /// prefixes of one buffer, this avoids re-materialising the whole file per
  /// save. The bytes are only valid appended directly to the document this
  /// editor was built over.
  Uint8List saveTail() => _updater.saveTail();

  /// Rewrites the document as a compacted PDF and returns the result plus a
  /// before/after report - the lossless structural pass of the file-size
  /// optimiser (#368).
  ///
  /// The rewrite drops the dead objects that incremental edits accumulate,
  /// packs objects into compressed object streams, and re-deflates streams
  /// that were stored uncompressed - all lossless for rendered output.
  /// Pending unsaved edits are included. Because it is a from-scratch file
  /// (no `/Prev`), it does not preserve prior-revision history and it
  /// invalidates any existing signature - hence an explicit action, not part
  /// of [save].
  ///
  /// If the compacted file would not be smaller (an already object-stream
  /// document, or one small enough that framing dominates), the current bytes
  /// are returned unchanged and [PdfCompressionResult.compacted] is false.
  /// Throws if the document is encrypted (decrypt it first).
  PdfCompressionResult compress({int deflateLevel = 9}) {
    final current =
        _updater.hasChanges ? _updater.save() : document.cos.bytes;
    final snapshot =
        _updater.hasChanges ? PdfDocument.open(current).cos : document.cos;
    final result =
        CosCompactor(snapshot, deflateLevel: deflateLevel).run();
    final smaller = result.bytes.length < current.length;
    return PdfCompressionResult(
      bytes: smaller ? result.bytes : Uint8List.fromList(current),
      bytesBefore: current.length,
      bytesAfter: smaller ? result.bytes.length : current.length,
      objectsBefore: result.objectsBefore,
      objectsAfter: result.objectsAfter,
      streamsDeflated: result.streamsDeflated,
      compacted: smaller,
    );
  }
}

/// The outcome of [PdfEditor.compress]: the (possibly rewritten) bytes and a
/// before/after accounting hosts can surface as "saved N%".
class PdfCompressionResult {
  const PdfCompressionResult({
    required this.bytes,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.objectsBefore,
    required this.objectsAfter,
    required this.streamsDeflated,
    required this.compacted,
  });

  /// The file to keep: the compacted bytes when smaller, otherwise a copy of
  /// the input unchanged.
  final Uint8List bytes;
  final int bytesBefore;
  final int bytesAfter;

  /// Object slots the source cross-reference declared, versus live objects
  /// written to the compacted file.
  final int objectsBefore;
  final int objectsAfter;

  /// Previously uncompressed streams that were re-deflated.
  final int streamsDeflated;

  /// Whether the compacted output was actually smaller and was kept.
  final bool compacted;

  /// Bytes removed (0 when the input was kept).
  int get bytesSaved => bytesBefore - bytesAfter;

  /// Fraction of the original size removed, in `[0, 1)`.
  double get ratio => bytesBefore == 0 ? 0 : bytesSaved / bytesBefore;
}

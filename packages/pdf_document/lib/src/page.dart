import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';
import 'measure.dart';
import 'rect.dart';

/// A single page, resolving inheritable attributes (§7.7.3.4) on access.
///
/// The values carried here are the ones inherited from **ancestors only**;
/// the page's own `/Resources`, `/MediaBox`, `/CropBox`, and `/Rotate` are
/// read from [dict] every time, so they always reflect the live dictionary.
///
/// That distinction is load-bearing. [PdfEditor] mutates page dictionaries in
/// place (`page.dict['Rotate'] = ...` then `markChanged`), so a page that
/// snapshotted its merged values at construction reported pre-edit state for
/// the rest of its life. That was survivable only because
/// [PdfDocument.page] built a fresh instance per call - which in turn made
/// [annotations]' cache unreachable. Reading through to [dict] removes the
/// hazard instead of trading one for the other (#418).
///
/// Inherited values change only on structural edits to the page tree, which
/// already go through [PdfDocument.invalidatePageCache].
class PdfPage {
  PdfPage({
    required this.document,
    required this.dict,
    CosDictionary? inheritedResources,
    CosArray? inheritedMediaBox,
    CosArray? inheritedCropBox,
    int? inheritedRotate,
  })  : _inheritedResources = inheritedResources,
        _inheritedMediaBox = inheritedMediaBox,
        _inheritedCropBox = inheritedCropBox,
        _inheritedRotate = inheritedRotate;

  final PdfDocument document;
  final CosDictionary dict;
  final CosDictionary? _inheritedResources;
  final CosArray? _inheritedMediaBox;
  final CosArray? _inheritedCropBox;
  final int? _inheritedRotate;

  /// Re-wraps this page for a newer incremental revision of the same COS
  /// document, preserving the inherited attributes resolved from its
  /// unchanged page-tree path.
  ///
  /// [dict] must be the current dictionary resolved for this page's stable
  /// indirect reference. This is intentionally narrower than constructing an
  /// arbitrary page: a structural page-tree edit must perform a fresh walk so
  /// inherited values are resolved from the new ancestry.
  PdfPage forIncrementalRevision(PdfDocument document, CosDictionary dict) {
    if (!identical(this.document.cos, document.cos)) {
      throw ArgumentError('incremental page revision must share the COS graph');
    }
    return PdfPage(
      document: document,
      dict: dict,
      inheritedResources: _inheritedResources,
      inheritedMediaBox: _inheritedMediaBox,
      inheritedCropBox: _inheritedCropBox,
      inheritedRotate: _inheritedRotate,
    );
  }

  /// This page's own entry for [key], or the value inherited from its
  /// ancestors when the page does not carry one.
  T? _own<T extends CosObject>(String key, T? inherited) {
    final value = document.cos.resolve(dict[key]);
    return value is T ? value : inherited;
  }

  CosArray? get _mediaBoxArray => _own<CosArray>('MediaBox', _inheritedMediaBox);
  CosArray? get _cropBoxArray => _own<CosArray>('CropBox', _inheritedCropBox);

  /// US Letter, the conventional fallback for broken pages with no MediaBox
  /// anywhere on their tree path.
  static const PdfRect _letter = PdfRect(0, 0, 612, 792);

  PdfRect get mediaBox {
    final box = _toRect(_mediaBoxArray);
    return _hasArea(box) ? box! : _letter;
  }

  PdfRect get cropBox {
    final media = mediaBox;
    final crop = _toRect(_cropBoxArray);
    if (!_hasArea(crop)) return media;
    final clipped = crop!.intersect(media);
    return _hasArea(clipped) ? clipped : media;
  }

  /// Clockwise display rotation: always 0, 90, 180, or 270.
  int get rotation {
    final own = document.cos.resolve(dict['Rotate']);
    final rotate = own is CosInteger ? own.value : _inheritedRotate;
    final r = (rotate ?? 0) % 360;
    final positive = r < 0 ? r + 360 : r;
    return positive - positive % 90;
  }

  CosDictionary get resources =>
      _own<CosDictionary>('Resources', _inheritedResources) ?? CosDictionary();

  List<PdfAnnotation>? _annotations;
  CosObject? _annotationsSource;
  int _annotationsCount = -1;

  /// The page's annotations (/Annots), parsed lazily and cached.
  ///
  /// Page instances are cached ([PdfDocument.page]), so this cache now
  /// outlives edits and has to notice them. It is keyed on the identity of
  /// the resolved /Annots array plus its length, which covers how the editors
  /// actually mutate it: replacing the array, and adding or removing entries
  /// in place.
  ///
  /// Editing an existing annotation's properties needs no invalidation -
  /// [PdfAnnotation] reads through to its own dictionary, and that dictionary
  /// is mutated in place - so a same-array, same-length change is correctly
  /// treated as a hit. A wholesale item *substitution* that preserved both
  /// identity and length would be missed; nothing does that today.
  List<PdfAnnotation> get annotations {
    final raw = document.cos.resolve(dict['Annots']);
    final count = raw is CosArray ? raw.items.length : -1;
    final cached = _annotations;
    if (cached != null &&
        identical(raw, _annotationsSource) &&
        count == _annotationsCount) {
      return cached;
    }
    _annotationsSource = raw;
    _annotationsCount = count;
    return _annotations = raw is! CosArray
        ? const <PdfAnnotation>[]
        : <PdfAnnotation>[
            for (final item in raw.items)
              if (document.cos.resolve(item) case final CosDictionary d)
                PdfAnnotation.fromDict(document, d),
          ];
  }

  /// The page's measurement scale, read from its first /VP viewport's
  /// /Measure dictionary (§12.9). This is the document-borne, portable
  /// drawing scale - written by `PdfEditor.setPageMeasurementScale` - so a
  /// reopened or shared file keeps its calibration without relying on an
  /// app-side preference. Null when the page declares no viewport scale.
  PdfMeasure? get measure {
    final vp = document.cos.resolve(dict['VP']);
    if (vp is! CosArray) return null;
    for (final item in vp.items) {
      final viewport = document.cos.resolve(item);
      if (viewport is! CosDictionary) continue;
      final m = PdfMeasure.fromDict(document, viewport['Measure']);
      if (m != null) return m;
    }
    return null;
  }

  /// The page's content streams, decoded and concatenated.
  /// Total raw (still-encoded) size of the page's content streams, summed
  /// without decoding them. A cheap O(streams) proxy for how expensive
  /// interpreting/extracting this page will be - a normal page is a few KB, a
  /// dense CAD sheet is megabytes - so callers can gate synchronous work
  /// (e.g. hover-cursor text extraction) on it without paying a decode.
  int get rawContentLength {
    final contents = document.cos.resolve(dict['Contents']);
    if (contents is CosStream) return contents.rawBytes.length;
    var total = 0;
    if (contents is CosArray) {
      for (final item in contents.items) {
        final stream = document.cos.resolve(item);
        if (stream is CosStream) total += stream.rawBytes.length;
      }
    }
    return total;
  }

  Uint8List contentBytes() {
    final contents = document.cos.resolve(dict['Contents']);
    final streams = <CosStream>[];
    if (contents is CosStream) streams.add(contents);
    if (contents is CosArray) {
      for (final item in contents.items) {
        final stream = document.cos.resolve(item);
        if (stream is CosStream) streams.add(stream);
      }
    }
    final out = BytesBuilder();
    for (final stream in streams) {
      // streams in a /Contents array form one logical stream; the separator
      // keeps tokens from adjacent streams apart
      final Uint8List data;
      try {
        data = document.cos.decodeStreamData(stream);
      } on Exception {
        // a content stream whose filters reject the payload renders as
        // empty rather than failing the whole page (corrupt real-world
        // files; the rest of the /Contents array still draws)
        continue;
      }
      if (out.isNotEmpty) out.addByte(0x0A);
      out.add(data);
    }
    return out.takeBytes();
  }

  PdfRect? _toRect(CosArray? array) {
    if (array == null || array.length < 4) return null;
    final values = <double>[];
    for (var i = 0; i < 4; i++) {
      final n = document.cos.resolve(array[i]);
      if (n is CosInteger) {
        values.add(n.value.toDouble());
      } else if (n is CosReal) {
        values.add(n.value);
      } else {
        return null;
      }
    }
    return PdfRect.normalized(values[0], values[1], values[2], values[3]);
  }

  bool _hasArea(PdfRect? rect) =>
      rect != null && rect.width > 0 && rect.height > 0;
}

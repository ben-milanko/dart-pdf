import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';
import 'rect.dart';

/// A single page, with inheritable attributes already resolved.
class PdfPage {
  PdfPage({
    required this.document,
    required this.dict,
    CosDictionary? resources,
    CosArray? mediaBoxArray,
    CosArray? cropBoxArray,
    int? rotate,
  })  : _resources = resources,
        _mediaBoxArray = mediaBoxArray,
        _cropBoxArray = cropBoxArray,
        _rotate = rotate;

  final PdfDocument document;
  final CosDictionary dict;
  final CosDictionary? _resources;
  final CosArray? _mediaBoxArray;
  final CosArray? _cropBoxArray;
  final int? _rotate;

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
    final r = (_rotate ?? 0) % 360;
    final positive = r < 0 ? r + 360 : r;
    return positive - positive % 90;
  }

  CosDictionary get resources => _resources ?? CosDictionary();

  List<PdfAnnotation>? _annotations;

  /// The page's annotations (/Annots), parsed lazily and cached.
  List<PdfAnnotation> get annotations => _annotations ??= () {
        final raw = document.cos.resolve(dict['Annots']);
        if (raw is! CosArray) return const <PdfAnnotation>[];
        return <PdfAnnotation>[
          for (final item in raw.items)
            if (document.cos.resolve(item) case final CosDictionary d)
              PdfAnnotation.fromDict(document, d),
        ];
      }();

  /// The page's content streams, decoded and concatenated.
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

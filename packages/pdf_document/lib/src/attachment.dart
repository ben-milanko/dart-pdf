import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// Reads embedded files (attachments) from a document: both the
/// document-level `/Names → /EmbeddedFiles` name tree (§7.11.4) and
/// `/FileAttachment` annotations (§12.5.6.15).
class PdfAttachments {
  const PdfAttachments(this.embeddedFiles, this.fileAttachments);

  /// Files registered in the catalog's `/EmbeddedFiles` name tree, in
  /// name order.
  final List<PdfEmbeddedFile> embeddedFiles;

  /// Files carried by `/FileAttachment` annotations, in page order.
  final List<PdfEmbeddedFile> fileAttachments;

  /// Every embedded file the document carries, name-tree entries first.
  List<PdfEmbeddedFile> get all => [...embeddedFiles, ...fileAttachments];

  static PdfAttachments of(PdfDocument document) {
    final cos = document.cos;
    final embedded = <PdfEmbeddedFile>[];
    final names = cos.resolve(document.catalog['Names']);
    if (names is CosDictionary) {
      final tree = cos.resolve(names['EmbeddedFiles']);
      if (tree is CosDictionary) {
        final pairs = <(String, CosObject?)>[];
        _walkNameTree(cos, tree, pairs, <CosDictionary>{});
        for (final (name, spec) in pairs) {
          final file = PdfEmbeddedFile._fromFilespec(document, spec, name);
          if (file != null) embedded.add(file);
        }
      }
    }

    final attachments = <PdfEmbeddedFile>[];
    for (var i = 0; i < document.pageCount; i++) {
      final annots = cos.resolve(document.page(i).dict['Annots']);
      if (annots is! CosArray) continue;
      for (final item in annots.items) {
        final annot = cos.resolve(item);
        if (annot is! CosDictionary) continue;
        final subtype = cos.resolve(annot['Subtype']);
        if (subtype is! CosName || subtype.value != 'FileAttachment') continue;
        final file = PdfEmbeddedFile._fromFilespec(document, annot['FS'], null);
        if (file != null) attachments.add(file);
      }
    }
    return PdfAttachments(embedded, attachments);
  }

  /// Collects every `name → value` pair of a name tree, walking /Kids.
  /// Lenient (and order-preserving): real files often misorder /Limits.
  static void _walkNameTree(CosDocument cos, CosDictionary node,
      List<(String, CosObject?)> out, Set<CosDictionary> visited) {
    if (!visited.add(node)) return;
    final entries = cos.resolve(node['Names']);
    if (entries is CosArray) {
      for (var i = 0; i + 1 < entries.length; i += 2) {
        final key = cos.resolve(entries[i]);
        if (key is CosString) out.add((key.text, entries[i + 1]));
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        final child = cos.resolve(kid);
        if (child is CosDictionary) _walkNameTree(cos, child, out, visited);
      }
    }
  }
}

/// One embedded file: its names, metadata, and (lazily decoded) bytes.
class PdfEmbeddedFile {
  PdfEmbeddedFile._({
    required PdfDocument document,
    required CosStream? stream,
    required this.name,
    required this.fileName,
    required this.description,
    required this.mimeType,
    required this.size,
    required this.creationDate,
    required this.modificationDate,
    required this.checksum,
  })  : _document = document,
        _stream = stream;

  final PdfDocument _document;
  final CosStream? _stream;

  /// The name-tree key, when this came from `/EmbeddedFiles`; otherwise the
  /// file name.
  final String name;

  /// The `/F`/`/UF` file name, or null.
  final String? fileName;

  /// The `/Desc` description, or null.
  final String? description;

  /// The embedded stream's `/Subtype` MIME type (e.g. `application/pdf`),
  /// or null.
  final String? mimeType;

  /// The uncompressed size from `/Params /Size`, or null when absent.
  final int? size;

  final DateTime? creationDate;
  final DateTime? modificationDate;

  /// The `/Params /CheckSum` (16-byte MD5), or null.
  final Uint8List? checksum;

  /// Whether the file actually carries a byte stream.
  bool get hasBytes => _stream != null;

  /// The decoded file bytes, or an empty list when the filespec has no
  /// embedded stream.
  Uint8List bytes() {
    final stream = _stream;
    if (stream == null) return Uint8List(0);
    return _document.cos.decodeStreamData(stream);
  }

  static PdfEmbeddedFile? _fromFilespec(
      PdfDocument document, CosObject? raw, String? treeName) {
    final cos = document.cos;
    final spec = cos.resolve(raw);
    if (spec is! CosDictionary) return null;

    String? str(String key) {
      final v = cos.resolve(spec[key]);
      return v is CosString ? v.text : null;
    }

    final fileName = str('UF') ?? str('F');
    final description = str('Desc');

    CosStream? stream;
    final ef = cos.resolve(spec['EF']);
    if (ef is CosDictionary) {
      final uf = cos.resolve(ef['UF']);
      final f = cos.resolve(ef['F']);
      if (uf is CosStream) {
        stream = uf;
      } else if (f is CosStream) {
        stream = f;
      }
    }

    String? mime;
    int? size;
    DateTime? creation;
    DateTime? mod;
    Uint8List? checksum;
    if (stream != null) {
      final subtype = cos.resolve(stream.dictionary['Subtype']);
      if (subtype is CosName) mime = subtype.value;
      final params = cos.resolve(stream.dictionary['Params']);
      if (params is CosDictionary) {
        final s = cos.resolve(params['Size']);
        if (s is CosInteger) size = s.value;
        creation = _parseDate(cos.resolve(params['CreationDate']));
        mod = _parseDate(cos.resolve(params['ModDate']));
        final cs = cos.resolve(params['CheckSum']);
        if (cs is CosString) checksum = Uint8List.fromList(cs.bytes);
      }
    }

    return PdfEmbeddedFile._(
      document: document,
      stream: stream,
      name: treeName ?? fileName ?? '',
      fileName: fileName,
      description: description,
      mimeType: mime,
      size: size,
      creationDate: creation,
      modificationDate: mod,
      checksum: checksum,
    );
  }

  /// Parses a PDF date string `D:YYYYMMDDHHmmSS±HH'mm'` (§7.9.4). Lenient: a
  /// truncated date keeps the fields it has. A `Z` (or absent) zone is read
  /// as UTC; a numeric offset is applied so the result is the same instant.
  static DateTime? _parseDate(CosObject? value) {
    if (value is! CosString) return null;
    var s = value.text;
    if (s.startsWith('D:')) s = s.substring(2);
    if (s.length < 4) return null;
    int field(int start, int len, int fallback) {
      if (start + len > s.length) return fallback;
      return int.tryParse(s.substring(start, start + len)) ?? fallback;
    }

    final utc = DateTime.utc(
      field(0, 4, 1970),
      field(4, 2, 1),
      field(6, 2, 1),
      field(8, 2, 0),
      field(10, 2, 0),
      field(12, 2, 0),
    );
    // an offset zone (e.g. +05'00') shifts back to UTC for the same instant
    if (s.length > 14 && (s[14] == '+' || s[14] == '-')) {
      final sign = s[14] == '-' ? 1 : -1;
      final oh = field(15, 2, 0);
      final om = s.length >= 19 ? field(18, 2, 0) : 0;
      return utc.add(Duration(minutes: sign * (oh * 60 + om)));
    }
    return utc;
  }
}

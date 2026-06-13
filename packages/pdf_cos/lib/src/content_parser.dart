import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// One content-stream instruction: operands followed by an operator.
class ContentOperation {
  ContentOperation(this.operator, this.operands);

  final String operator;
  final List<CosObject> operands;

  @override
  String toString() =>
      operands.isEmpty ? operator : '${operands.join(' ')} $operator';
}

/// Parses a page content stream into a flat list of operations.
///
/// An inline image (`BI ... ID ... EI`) is surfaced as a single `BI`
/// operation whose operands are the image dictionary and the raw image data
/// as a [CosString].
class ContentStreamParser {
  ContentStreamParser._();

  static List<ContentOperation> parse(Uint8List content) {
    final operations = <ContentOperation>[];
    final parser = CosParser(content);
    final operands = <CosObject>[];
    while (true) {
      final t = parser.peekToken();
      if (t.type == CosTokenType.eof) break;
      if (t.type == CosTokenType.arrayOpen) {
        operands.add(_parseLenientArray(parser));
        continue;
      }
      if (t.type != CosTokenType.keyword) {
        operands.add(parser.parseObject());
        continue;
      }
      switch (t.textValue) {
        // true/false/null are operands, not operators
        case 'true' || 'false' || 'null':
          operands.add(parser.parseObject());
        case 'BI':
          operations.add(_parseInlineImage(parser));
          operands.clear();
        default:
          parser.nextToken();
          operations.add(ContentOperation(t.textValue, List.of(operands)));
          operands.clear();
      }
    }
    return operations;
  }

  /// Parses an array operand, dropping stray operators found inside it.
  /// Real-world generators emit junk like `[(a) 0.0 Tc -250.0 (b)] TJ`;
  /// a strict parse would abort the whole page on the `Tc`.
  static CosArray _parseLenientArray(CosParser parser) {
    parser.nextToken(); // [
    final items = <CosObject>[];
    while (true) {
      final t = parser.peekToken();
      switch (t.type) {
        case CosTokenType.arrayClose:
          parser.nextToken();
          return CosArray(items);
        case CosTokenType.eof:
          return CosArray(items); // unterminated — keep what parsed
        case CosTokenType.arrayOpen:
          items.add(_parseLenientArray(parser));
        case CosTokenType.keyword:
          if (t.textValue == 'true' ||
              t.textValue == 'false' ||
              t.textValue == 'null') {
            items.add(parser.parseObject());
          } else {
            parser.nextToken(); // stray operator — drop it
          }
        default:
          items.add(parser.parseObject());
      }
    }
  }

  static ContentOperation _parseInlineImage(CosParser parser) {
    parser.nextToken(); // BI
    final dict = CosDictionary();
    while (true) {
      final t = parser.peekToken();
      if (t.isKeyword('ID')) break;
      if (t.type == CosTokenType.eof) {
        throw CosParseException('unterminated inline image', t.offset);
      }
      if (t.type != CosTokenType.name) {
        throw CosParseException(
            'expected name in inline image dictionary, found $t', t.offset);
      }
      parser.nextToken();
      dict[t.textValue] = parser.parseObject();
    }
    final idToken = parser.nextToken(); // ID

    // Exactly one whitespace byte separates ID from the data (§8.9.7).
    final bytes = parser.bytes;
    final dataStart =
        _skipInlineImageDataSeparator(bytes, idToken.offset + 'ID'.length);
    final p = _inlineImageEnd(bytes, dataStart, dict);
    var dataEnd = p;
    while (dataEnd > dataStart && CosLexer.isWhitespace(bytes[dataEnd - 1])) {
      dataEnd--;
    }
    final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    parser.seek(p + 'EI'.length);
    return ContentOperation('BI', [dict, CosString(data)]);
  }

  static int _inlineImageEnd(
      Uint8List bytes, int dataStart, CosDictionary dict) {
    if (_hasDctFilter(dict)) {
      final jpegEnd = _jpegEnd(bytes, dataStart);
      if (jpegEnd != null) {
        final marker = _nextEiAfter(bytes, jpegEnd);
        if (marker != null) return marker;
      }
    }

    var p = dataStart;
    while (true) {
      final marker = _eiAt(bytes, dataStart, p);
      if (marker != null) return marker;
      if (p + 'EI'.length > bytes.length) {
        throw CosParseException('unterminated inline image data', dataStart);
      }
      p++;
    }
  }

  static int _skipInlineImageDataSeparator(Uint8List bytes, int offset) {
    if (offset >= bytes.length || !CosLexer.isWhitespace(bytes[offset])) {
      return offset;
    }
    if (bytes[offset] == 0x0D &&
        offset + 1 < bytes.length &&
        bytes[offset + 1] == 0x0A) {
      return offset + 2;
    }
    return offset + 1;
  }

  static bool _hasDctFilter(CosDictionary dict) {
    final filter = dict['Filter'] ?? dict['F'];
    bool isDct(CosObject? object) =>
        object is CosName &&
        (object.value == 'DCTDecode' || object.value == 'DCT');
    if (isDct(filter)) return true;
    if (filter is CosArray) {
      for (final item in filter.items) {
        if (isDct(item)) return true;
      }
    }
    return false;
  }

  static int? _jpegEnd(Uint8List bytes, int start) {
    for (var p = start; p + 1 < bytes.length; p++) {
      if (bytes[p] == 0xFF && bytes[p + 1] == 0xD9) return p + 2;
    }
    return null;
  }

  static int? _nextEiAfter(Uint8List bytes, int offset) {
    var p = offset;
    while (p < bytes.length && CosLexer.isWhitespace(bytes[p])) {
      p++;
    }
    return _eiAt(bytes, offset, p);
  }

  static int? _eiAt(Uint8List bytes, int dataStart, int p) {
    if (p + 'EI'.length > bytes.length) return null;
    if (bytes[p] != 0x45 || bytes[p + 1] != 0x49) return null;
    final beforeOk = p == dataStart || CosLexer.isWhitespace(bytes[p - 1]);
    final afterPos = p + 'EI'.length;
    final afterOk =
        afterPos >= bytes.length || CosLexer.isWhitespace(bytes[afterPos]);
    return beforeOk && afterOk ? p : null;
  }
}

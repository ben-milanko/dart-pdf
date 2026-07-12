import 'dart:convert';
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

/// Serializes parsed content-stream operations back to PDF content syntax.
///
/// This is intentionally narrower than [CosSerializer]: a content stream is a
/// flat sequence of operands followed by an operator, with inline images
/// encoded by the special `BI ... ID ... EI` form instead of ordinary COS
/// object syntax.
class ContentStreamSerializer {
  ContentStreamSerializer._();

  /// Serializes [operations], one operation per line.
  static Uint8List serialize(Iterable<ContentOperation> operations) {
    final out = BytesBuilder();
    for (final operation in operations) {
      writeOperation(operation, out);
    }
    return out.takeBytes();
  }

  /// Serializes one [operation] into [out].
  static void writeOperation(ContentOperation operation, BytesBuilder out) {
    if (operation.operator == 'BI') {
      _writeInlineImage(operation, out);
      return;
    }

    for (final operand in operation.operands) {
      out
        ..add(CosSerializer.serialize(operand))
        ..addByte(0x20);
    }
    out.add(latin1.encode('${operation.operator}\n'));
  }

  static void _writeInlineImage(ContentOperation operation, BytesBuilder out) {
    if (operation.operands.length < 2 ||
        operation.operands[0] is! CosDictionary ||
        operation.operands[1] is! CosString) {
      throw ArgumentError.value(operation, 'operation',
          'BI operation must contain a dictionary and raw image data');
    }

    out.add(latin1.encode('BI'));
    final dict = operation.operands[0] as CosDictionary;
    dict.entries.forEach((key, value) {
      out
        ..add(latin1.encode(' /$key '))
        ..add(CosSerializer.serialize(value));
    });
    out.add(latin1.encode(' ID\n'));
    out.add((operation.operands[1] as CosString).bytes);
    out.add(latin1.encode('\nEI\n'));
  }
}

/// Parses a page content stream into a flat list of operations.
///
/// An inline image (`BI ... ID ... EI`) is surfaced as a single `BI`
/// operation whose operands are the image dictionary and the raw image data
/// as a [CosString].
class ContentStreamParser {
  ContentStreamParser._();

  /// Shared immutable [CosInteger]s for the small values that saturate a
  /// content stream - text/graphics-state modes, glyph indices, colour
  /// components, small coordinates. Content streams are integer-dense, and
  /// a [CosInteger] is an immutable value object, so handing out one shared
  /// instance per small value spares millions of allocations on heavy (CAD)
  /// pages without changing any observable behaviour (equality is by value).
  static final List<CosInteger> _smallInts =
      List<CosInteger>.generate(258, (i) => CosInteger(i - 1));

  static CosObject _intObject(int value) =>
      (value >= -1 && value <= 256) ? _smallInts[value + 1] : CosInteger(value);

  /// Opens [content] as an incremental operation cursor.
  ///
  /// Unlike [parse], the cursor does not retain operations after the caller
  /// consumes them. This is useful for one-pass interpreters of very dense
  /// streams, while callers that need replay or editing should keep using the
  /// materialized list returned by [parse].
  static ContentOperationCursor cursor(Uint8List content,
          {int? operationLimit}) =>
      ContentOperationCursor._(content, operationLimit: operationLimit);

  static List<ContentOperation> parse(Uint8List content,
      {int? operationLimit}) {
    // Drive the lexer directly rather than through [CosParser]: a content
    // stream is a flat token stream (no indirect references, so none of
    // parseObject's `N G R` lookahead applies), and on a 10 MB CAD page the
    // peek/lookahead-list traffic and the per-operation operand copy
    // dominate. Pulling tokens straight from the lexer and handing each
    // finished operation its own operand list (no copy, no clear) roughly
    // halves the parse.
    final operations = <ContentOperation>[];
    final reader = cursor(content, operationLimit: operationLimit);
    ContentOperation? operation;
    while ((operation = reader.nextOperation()) != null) {
      operations.add(operation!);
    }
    return operations;
  }

  /// Parses one operand object from [first] (already consumed). Mirrors
  /// [CosParser.parseObject] for the object kinds that appear in content
  /// streams - no indirect references, no streams.
  static CosObject _parseObject(CosLexer lexer, CosToken first) {
    switch (first.type) {
      case CosTokenType.integer:
        return _intObject(first.intValue);
      case CosTokenType.real:
        return CosReal(first.realValue);
      case CosTokenType.string:
        return CosString(first.bytesValue);
      case CosTokenType.hexString:
        return CosString(first.bytesValue, isHex: true);
      case CosTokenType.name:
        return CosName(first.textValue);
      case CosTokenType.arrayOpen:
        return _parseLenientArray(lexer);
      case CosTokenType.dictOpen:
        return _parseDictionary(lexer);
      case CosTokenType.keyword:
        switch (first.textValue) {
          case 'true':
            return const CosBoolean(true);
          case 'false':
            return const CosBoolean(false);
          case 'null':
            return CosNull.instance;
        }
        throw CosParseException(
            'unexpected keyword "${first.textValue}"', first.offset);
      case CosTokenType.eof:
        throw CosParseException('unexpected end of input', first.offset);
      case CosTokenType.arrayClose:
      case CosTokenType.dictClose:
        throw CosParseException('unexpected token $first', first.offset);
    }
  }

  /// Parses an array operand (the `[` already consumed), dropping stray
  /// operators found inside it. Real-world generators emit junk like
  /// `[(a) 0.0 Tc -250.0 (b)] TJ`; a strict parse would abort the whole page
  /// on the `Tc`.
  static CosArray _parseLenientArray(CosLexer lexer) {
    final items = <CosObject>[];
    while (true) {
      final t = lexer.nextToken();
      switch (t.type) {
        case CosTokenType.arrayClose:
          return CosArray(items);
        case CosTokenType.eof:
          return CosArray(items); // unterminated - keep what parsed
        case CosTokenType.integer:
          items.add(_intObject(t.intValue));
        case CosTokenType.real:
          items.add(CosReal(t.realValue));
        case CosTokenType.keyword:
          if (t.textValue == 'true' ||
              t.textValue == 'false' ||
              t.textValue == 'null') {
            items.add(_parseObject(lexer, t));
          }
        // else: stray operator - drop it
        default:
          items.add(_parseObject(lexer, t));
      }
    }
  }

  /// Parses a dictionary operand (the `<<` already consumed). Content-stream
  /// dictionaries are property lists for marked content (`BDC`/`DP`); they
  /// never carry a stream.
  static CosDictionary _parseDictionary(CosLexer lexer) {
    final dict = CosDictionary();
    while (true) {
      final t = lexer.nextToken();
      if (t.type == CosTokenType.dictClose) return dict;
      if (t.type == CosTokenType.eof) {
        throw CosParseException('unterminated dictionary', t.offset);
      }
      if (t.type != CosTokenType.name) {
        throw CosParseException(
            'expected name as dictionary key, found $t', t.offset);
      }
      dict[t.textValue] = _parseObject(lexer, lexer.nextToken());
    }
  }

  static ContentOperation _parseInlineImage(CosLexer lexer) {
    // `BI` already consumed.
    final dict = CosDictionary();
    CosToken idToken;
    while (true) {
      final t = lexer.nextToken();
      if (t.isKeyword('ID')) {
        idToken = t;
        break;
      }
      if (t.type == CosTokenType.eof) {
        throw CosParseException('unterminated inline image', t.offset);
      }
      if (t.type != CosTokenType.name) {
        throw CosParseException(
            'expected name in inline image dictionary, found $t', t.offset);
      }
      dict[t.textValue] = _parseObject(lexer, lexer.nextToken());
    }

    // Exactly one whitespace byte separates ID from the data (§8.9.7).
    final bytes = lexer.bytes;
    final dataStart =
        _skipInlineImageDataSeparator(bytes, idToken.offset + 'ID'.length);
    final p = _inlineImageEnd(bytes, dataStart, dict);
    var dataEnd = p;
    while (dataEnd > dataStart && CosLexer.isWhitespace(bytes[dataEnd - 1])) {
      dataEnd--;
    }
    final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    lexer.position = p + 'EI'.length;
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

/// Incremental reader for a flat PDF content stream.
///
/// Each call to [nextOperation] returns ownership of that operation's operand
/// list. Once the caller drops the returned operation, no page-sized parsed
/// representation remains live. Obtain a cursor with
/// [ContentStreamParser.cursor].
class ContentOperationCursor {
  ContentOperationCursor._(Uint8List content, {this.operationLimit})
      : _lexer = CosLexer(content),
        _finished = operationLimit != null && operationLimit <= 0;

  /// Maximum operations this cursor will emit, or null for the whole stream.
  final int? operationLimit;

  final CosLexer _lexer;
  var _operands = <CosObject>[];
  var _operationCount = 0;
  bool _finished;

  /// Number of operations emitted so far.
  int get operationCount => _operationCount;

  /// Whether EOF or [operationLimit] has been reached.
  bool get isFinished => _finished;

  /// Parses and returns the next operation, or null at the end of the stream.
  ContentOperation? nextOperation() {
    if (_finished) return null;
    while (true) {
      final token = _lexer.nextToken();
      switch (token.type) {
        case CosTokenType.eof:
          _finished = true;
          return null;
        case CosTokenType.integer:
          _operands.add(ContentStreamParser._intObject(token.intValue));
        case CosTokenType.real:
          _operands.add(CosReal(token.realValue));
        case CosTokenType.keyword:
          final keyword = token.textValue;
          switch (keyword) {
            case 'true':
              _operands.add(const CosBoolean(true));
              continue;
            case 'false':
              _operands.add(const CosBoolean(false));
              continue;
            case 'null':
              _operands.add(CosNull.instance);
              continue;
            case 'BI':
              final operation = ContentStreamParser._parseInlineImage(_lexer);
              // Match the materialized parser's lenient boundary behavior:
              // junk operands before BI do not leak into the following op.
              _operands = <CosObject>[];
              return _emit(operation);
            default:
              final operation = ContentOperation(keyword, _operands);
              _operands = <CosObject>[];
              return _emit(operation);
          }
        default:
          _operands.add(ContentStreamParser._parseObject(_lexer, token));
      }
    }
  }

  ContentOperation _emit(ContentOperation operation) {
    _operationCount++;
    if (operationLimit != null && _operationCount >= operationLimit!) {
      _finished = true;
    }
    return operation;
  }
}

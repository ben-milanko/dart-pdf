import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'perf/perf.dart';

/// One content-stream instruction: operands followed by an operator.
class ContentOperation {
  ContentOperation(this.operator, List<CosObject> operands)
      : _operands = operands,
        numberOperands = null;

  ContentOperation._numbers(this.operator, this.numberOperands)
      : _operands = null;

  final String operator;

  List<CosObject>? _operands;

  /// Primitive numeric operands supplied by the incremental parser.
  ///
  /// Content streams are overwhelmingly numeric. Keeping a number-dense
  /// instruction in `num` form lets the graphics interpreter consume CAD path
  /// coordinates without allocating a [CosInteger]/[CosReal] wrapper for every
  /// token. General COS consumers keep using [operands], which materializes the
  /// exact object types lazily when required (serialization and editing retain
  /// their established behavior).
  final List<num>? numberOperands;

  List<CosObject> get operands => _operands ??= <CosObject>[
        for (final value in numberOperands!)
          ContentStreamParser._numberObject(value),
      ];

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

  /// The COS object a number operand of a content operation materializes as:
  /// an int becomes a (shared) [CosInteger], anything else a [CosReal].
  ///
  /// On the web an integral double *is* an int, so there `12.0` materializes
  /// as `CosInteger(12)` and `-0.0` as the shared `CosInteger(0)`; on the VM
  /// a real token stays a [CosReal]. Every path that materializes an
  /// operation's own operands - [ContentOperation.operands] and the cursor,
  /// whether the number comes before or after a non-number operand - goes
  /// through this one rule, so a token serializes the same (`12` or `12.0`)
  /// wherever it sits. Array and dictionary elements are parsed as COS objects
  /// and keep their token's type.
  static CosObject _numberObject(num value) =>
      value is int ? _intObject(value) : CosReal(value.toDouble());

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
    final t0 = PdfPerf.begin();
    final operations = <ContentOperation>[];
    final reader = cursor(content, operationLimit: operationLimit);
    ContentOperation? operation;
    while ((operation = reader.nextOperation()) != null) {
      operations.add(operation!);
    }
    PdfPerf.end(PdfPerfPhase.contentTokenize, t0);
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
///
/// [nextOperation] is [nextOperator] followed by [takeOperation]. A one-pass
/// interpreter can call the two halves itself and, when [pendingIsNumeric],
/// read a number-only operator straight from [numbers] by its
/// [operatorCode] - no [ContentOperation], no operand list and no boxed
/// double per operand. That is most of a vector-dense page: a CAD stream is
/// overwhelmingly `m`/`l`/`c`/`re` with number operands.
class ContentOperationCursor {
  ContentOperationCursor._(Uint8List content, {this.operationLimit})
      : _lexer = CosLexer(content),
        _contentLength = content.length,
        _finished = operationLimit != null && operationLimit <= 0;

  /// Maximum operations this cursor will emit, or null for the whole stream.
  final int? operationLimit;

  final CosLexer _lexer;
  final CosTokenBuffer _tokenBuffer = CosTokenBuffer();
  final int _contentLength;

  // The pending operator's number operands, unboxed. [_kinds] records how
  // each one materializes so [takeOperation] stays exact: a real, an int
  // that a double holds exactly, or an int beyond 2^53 held in [_bigInts].
  Float64List _numbers = Float64List(8);
  Uint8List _kinds = Uint8List(8);
  int _numberCount = 0;
  Map<int, int>? _bigInts;
  static const int _real = 0, _exactInt = 1, _bigInt = 2;
  static const int _maxExactInt = 9007199254740992; // 2^53

  // Set once an operand that is not a number arrives; from then on every
  // operand of the pending operator is a COS object.
  List<CosObject>? _objectOperands;
  // A pending inline image, already fully parsed.
  ContentOperation? _pendingInlineImage;
  String _pendingOperator = '';
  int _pendingCode = -1;
  bool _taken = false; // debug builds only: one takeOperation per operator
  var _operationCount = 0;
  bool _finished;
  bool _perfReported = false;

  /// Flushes the ops/bytes this cursor tokenized into PdfPerf, once. The
  /// cursor is the ONE tokenizer both parse() and the interpreter drive, and
  /// [_operationCount] already exists for [operationLimit] - so the hot loop
  /// pays nothing new; only stream end reaches this.
  void _reportPerf() {
    if (_perfReported || !PdfPerf.enabled) return;
    _perfReported = true;
    PdfPerf.add(PdfPerfCount.contentOps, _operationCount);
    PdfPerf.add(PdfPerfCount.contentBytes, _contentLength);
  }

  /// Number of operations emitted so far.
  int get operationCount => _operationCount;

  /// Whether EOF or [operationLimit] has been reached.
  bool get isFinished => _finished;

  /// The pending operator's operands when [pendingIsNumeric]: entries
  /// `[0, numberCount)`, as doubles.
  ///
  /// A borrowed view, valid only until the next [nextOperator] or
  /// [nextOperation] call.
  Float64List get numbers => _numbers;

  /// How many entries of [numbers] belong to the pending operator.
  int get numberCount => _numberCount;

  /// Whether every operand of the pending operator is a number (there may be
  /// none), so [numbers] holds them all.
  bool get pendingIsNumeric =>
      _objectOperands == null && _pendingInlineImage == null;

  /// The pending operator's [CosTokenBuffer.keywordCode]: its bytes packed
  /// little-endian for an operator of at most three bytes, else -1.
  int get operatorCode => _pendingCode;

  /// Parses and returns the next operation, or null at the end of the stream.
  ContentOperation? nextOperation() =>
      nextOperator() == null ? null : takeOperation();

  /// Scans to the next operator and returns it, or null at the end of the
  /// stream, leaving its operands pending: read them from [numbers] when
  /// [pendingIsNumeric], or call [takeOperation] (at most once) for the
  /// operation. Counts toward [operationLimit] like [nextOperation].
  String? nextOperator() {
    if (_finished) return null;
    _numberCount = 0;
    _objectOperands = null;
    _pendingInlineImage = null;
    if (_bigInts != null) _bigInts = null;
    assert(() {
      _taken = false;
      return true;
    }());
    final buffer = _tokenBuffer;
    while (true) {
      _lexer.nextToken(buffer);
      switch (buffer.type) {
        case CosTokenType.eof:
          _finished = true;
          _reportPerf();
          return null;
        case CosTokenType.integer:
          _addInt(buffer.intValue);
        case CosTokenType.real:
          _addReal(buffer.realValue);
        case CosTokenType.keyword:
          final keyword = buffer.textValue;
          final code = buffer.keywordCode;
          // Every keyword of at most three bytes except BI is an operator
          // (true/false/null are longer): skip the string switch for them.
          if (code != -1 && code != 0x4942) return _pend(keyword, code);
          switch (keyword) {
            case 'true':
              _addObject(const CosBoolean(true));
              continue;
            case 'false':
              _addObject(const CosBoolean(false));
              continue;
            case 'null':
              _addObject(CosNull.instance);
              continue;
            case 'BI':
              final operation = ContentStreamParser._parseInlineImage(_lexer);
              // Match the materialized parser's lenient boundary behavior:
              // junk operands before BI do not leak into the following op.
              _numberCount = 0;
              _objectOperands = null;
              _pendingInlineImage = operation;
              return _pend(keyword, code);
            default:
              return _pend(keyword, code);
          }
        default:
          _addObject(ContentStreamParser._parseObject(_lexer, buffer));
      }
    }
  }

  /// Materializes the operation [nextOperator] left pending.
  ContentOperation takeOperation() {
    assert(() {
      if (_taken) {
        throw StateError('takeOperation called twice for one operator');
      }
      _taken = true;
      return true;
    }());
    final inlineImage = _pendingInlineImage;
    if (inlineImage != null) return inlineImage;
    final objects = _objectOperands;
    if (objects != null) return ContentOperation(_pendingOperator, objects);
    final count = _numberCount;
    if (count == 0) {
      return ContentOperation(_pendingOperator, const <CosObject>[]);
    }
    return ContentOperation._numbers(
        _pendingOperator, <num>[for (var i = 0; i < count; i++) _numberAt(i)]);
  }

  String _pend(String operator, int code) {
    _pendingOperator = operator;
    _pendingCode = code;
    _operationCount++;
    if (operationLimit != null && _operationCount >= operationLimit!) {
      _finished = true;
      _reportPerf();
    }
    return operator;
  }

  num _numberAt(int i) => switch (_kinds[i]) {
        _real => _numbers[i],
        // On the web an int already is a double, and handing the stored value
        // back as-is keeps a `-0` operand's sign exactly as the lexer made it.
        _exactInt => _isWeb ? _numbers[i] : _numbers[i].toInt(),
        _ => _bigInts![i]!,
      };

  static const bool _isWeb = identical(0, 0.0);

  void _addInt(int value) {
    final objects = _objectOperands;
    if (objects != null) {
      objects.add(ContentStreamParser._intObject(value));
      return;
    }
    if (_numberCount == _numbers.length) _grow();
    final i = _numberCount++;
    _numbers[i] = value.toDouble();
    if (value > _maxExactInt || value < -_maxExactInt) {
      (_bigInts ??= <int, int>{})[i] = value;
      _kinds[i] = _bigInt;
    } else {
      _kinds[i] = _exactInt;
    }
  }

  void _addReal(double value) {
    final objects = _objectOperands;
    if (objects != null) {
      // Not `CosReal(value)`: on the web an integral real is an int and
      // materializes as a CosInteger (see [ContentStreamParser._numberObject]).
      objects.add(ContentStreamParser._numberObject(value));
      return;
    }
    if (_numberCount == _numbers.length) _grow();
    final i = _numberCount++;
    _numbers[i] = value;
    _kinds[i] = _real;
  }

  void _addObject(CosObject value) {
    var objects = _objectOperands;
    if (objects == null) {
      objects = _objectOperands = <CosObject>[
        for (var i = 0; i < _numberCount; i++)
          ContentStreamParser._numberObject(_numberAt(i)),
      ];
      _numberCount = 0;
    }
    objects.add(value);
  }

  void _grow() {
    final length = _numbers.length * 2;
    _numbers = Float64List(length)..setRange(0, _numberCount, _numbers);
    _kinds = Uint8List(length)..setRange(0, _numberCount, _kinds);
  }
}

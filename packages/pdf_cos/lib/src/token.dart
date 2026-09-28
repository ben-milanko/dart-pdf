import 'dart:typed_data';

enum CosTokenType {
  integer,
  real,
  string,
  hexString,
  name,
  arrayOpen,
  arrayClose,
  dictOpen,
  dictClose,
  keyword,
  eof,
}

class CosToken {
  const CosToken(this.type, this.offset, [this.value]);

  final CosTokenType type;

  /// Byte offset where the token starts.
  final int offset;

  /// `int`, `double`, `String` (names and keywords) or `Uint8List` (strings).
  final Object? value;

  int get intValue => value as int;
  double get realValue => value as double;
  String get textValue => value as String;
  Uint8List get bytesValue => value as Uint8List;

  bool isKeyword(String keyword) =>
      type == CosTokenType.keyword && value == keyword;

  @override
  String toString() =>
      'CosToken(${type.name}${value == null ? '' : ' $value'} @$offset)';
}

/// Mutable token storage for allocation-sensitive streaming parsers.
///
/// [CosLexer.nextToken] creates the ordinary immutable [CosToken] by default.
/// A consumer that reads one token completely before requesting the next can
/// pass this buffer explicitly and reuse it. Retaining a returned token while
/// reusing the same buffer is invalid by construction, so materializing parsers
/// should keep using the default path.
class CosTokenBuffer extends CosToken {
  CosTokenBuffer() : super(CosTokenType.eof, 0);

  CosTokenType _bufferType = CosTokenType.eof;
  int _bufferOffset = 0;
  Object? _bufferValue;
  // A real stored by [setReal] lives here unboxed (with [_bufferValue] null):
  // a CAD content stream is mostly real coordinates, and boxing each one only
  // for the consumer to unbox it again is an allocation per token.
  double _real = 0;
  int _keywordCode = -1;

  @override
  CosTokenType get type => _bufferType;

  @override
  int get offset => _bufferOffset;

  @override
  Object? get value => _bufferType == CosTokenType.real && _bufferValue == null
      ? _real
      : _bufferValue;

  @override
  double get realValue =>
      _bufferType == CosTokenType.real && _bufferValue == null
          ? _real
          : _bufferValue as double;

  /// The keyword's bytes packed little-endian into one int (`re` is
  /// `0x6572`) when this is a keyword token of at most three bytes, else -1.
  ///
  /// This is the code [CosLexer] already computes to intern the keyword, so a
  /// content interpreter can dispatch an operator on an int instead of
  /// comparing strings. It is -1 for every other token, for longer keywords
  /// and for the `{` / `}` tokens, so a stale code can never describe the
  /// current token.
  int get keywordCode => _keywordCode;

  void setToken(CosTokenType type, int offset, [Object? value]) {
    _bufferType = type;
    _bufferOffset = offset;
    _bufferValue = value;
    _keywordCode = -1;
  }

  /// Stores a real token without boxing [value].
  void setReal(int offset, double value) {
    _bufferType = CosTokenType.real;
    _bufferOffset = offset;
    _bufferValue = null;
    _real = value;
    _keywordCode = -1;
  }

  /// Stores a keyword token of at most three bytes with its packed [code]
  /// (see [keywordCode]).
  void setKeyword(int offset, String keyword, int code) {
    _bufferType = CosTokenType.keyword;
    _bufferOffset = offset;
    _bufferValue = keyword;
    _keywordCode = code;
  }
}

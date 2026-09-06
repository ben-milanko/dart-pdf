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

  @override
  CosTokenType get type => _bufferType;

  @override
  int get offset => _bufferOffset;

  @override
  Object? get value => _bufferValue;

  void setToken(CosTokenType type, int offset, [Object? value]) {
    _bufferType = type;
    _bufferOffset = offset;
    _bufferValue = value;
  }
}

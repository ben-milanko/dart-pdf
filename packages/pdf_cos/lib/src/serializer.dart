import 'dart:typed_data';

import 'objects.dart';

/// Serializes COS objects back to PDF syntax.
///
/// This is the building block for the document writer (full rewrites and
/// incremental updates), which will sit on top of it.
class CosSerializer {
  CosSerializer(this._out, {this.preserveRealPrecision = false});

  final BytesBuilder _out;

  /// Keep every parsed double's precision during lossless graph rewrites.
  /// Ordinary authored content retains the historical six-decimal output.
  final bool preserveRealPrecision;

  static const _delimiters = {
    0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25, // delims
  };

  static Uint8List serialize(CosObject object,
      {bool preserveRealPrecision = false}) {
    final out = BytesBuilder();
    CosSerializer(out, preserveRealPrecision: preserveRealPrecision)
        .writeObject(object);
    return out.takeBytes();
  }

  void writeObject(CosObject object) {
    switch (object) {
      case CosNull():
        _writeText('null');
      case CosBoolean(:final value):
        _writeText('$value');
      case CosInteger(:final value):
        _writeText('$value');
      case CosReal(:final value):
        _writeText(
            preserveRealPrecision ? formatRealExact(value) : formatReal(value));
      case CosString string:
        _writeString(string);
      case CosName(:final value):
        _writeName(value);
      case CosArray(:final items):
        _writeText('[');
        for (var i = 0; i < items.length; i++) {
          if (i > 0) _writeText(' ');
          writeObject(items[i]);
        }
        _writeText(']');
      case CosStream stream:
        writeObject(stream.dictionary);
        _writeText('\nstream\n');
        _out.add(stream.rawBytes);
        _writeText('\nendstream');
      case CosDictionary dictionary:
        _writeText('<<');
        dictionary.entries.forEach((key, value) {
          _writeText(' ');
          _writeName(key);
          _writeText(' ');
          writeObject(value);
        });
        _writeText(' >>');
      case CosReference(:final objectNumber, :final generation):
        _writeText('$objectNumber $generation R');
    }
  }

  void writeIndirectObject(CosIndirectObject object) {
    _writeText('${object.objectNumber} ${object.generation} obj\n');
    writeObject(object.object);
    _writeText('\nendobj\n');
  }

  /// PDF reals must not use exponent notation.
  static String formatReal(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return '${value.toInt()}.0';
    }
    var s = value.toStringAsFixed(6);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Round-tripping decimal representation without PDF-illegal exponents.
  /// Small font matrices in particular can carry meaningful digits beyond
  /// six decimal places; rounding those changes every transformed outline.
  static String formatRealExact(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    final text = value.toString();
    final e = text.indexOf('e');
    if (e < 0) return text;
    final sign = text.startsWith('-') ? '-' : '';
    final mantissa = text.substring(sign.length, e);
    final dot = mantissa.indexOf('.');
    final digits = mantissa.replaceAll('.', '');
    final decimal =
        (dot < 0 ? mantissa.length : dot) + int.parse(text.substring(e + 1));
    if (decimal <= 0) return '${sign}0.${'0' * -decimal}$digits';
    if (decimal >= digits.length) {
      return '$sign$digits${'0' * (decimal - digits.length)}.0';
    }
    return '$sign${digits.substring(0, decimal)}.${digits.substring(decimal)}';
  }

  void _writeText(String text) => _out.add(text.codeUnits);

  void _writeString(CosString string) {
    if (string.isHex) {
      _writeText('<');
      for (final b in string.bytes) {
        _writeText(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      _writeText('>');
      return;
    }
    _out.addByte(0x28);
    for (final b in string.bytes) {
      switch (b) {
        case 0x28 || 0x29 || 0x5C:
          _out.addByte(0x5C);
          _out.addByte(b);
        case 0x0A:
          _writeText(r'\n');
        case 0x0D:
          _writeText(r'\r');
        default:
          _out.addByte(b);
      }
    }
    _out.addByte(0x29);
  }

  void _writeName(String name) {
    _writeText('/');
    for (final c in name.codeUnits) {
      final isPlain =
          c > 0x20 && c < 0x7F && c != 0x23 && !_delimiters.contains(c);
      if (isPlain) {
        _out.addByte(c);
      } else {
        _writeText(
            '#${(c & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
  }
}

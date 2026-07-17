import 'dart:convert';
import 'dart:typed_data';

/// Base class for every value in a PDF file's object graph (ISO 32000-1 §7.3).
sealed class CosObject {
  const CosObject();
}

class CosNull extends CosObject {
  const CosNull._();

  static const CosNull instance = CosNull._();

  @override
  String toString() => 'null';
}

class CosBoolean extends CosObject {
  const CosBoolean(this.value);

  final bool value;

  @override
  bool operator ==(Object other) => other is CosBoolean && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

class CosInteger extends CosObject {
  const CosInteger(this.value);

  final int value;

  @override
  bool operator ==(Object other) => other is CosInteger && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

class CosReal extends CosObject {
  const CosReal(this.value);

  final double value;

  @override
  bool operator ==(Object other) => other is CosReal && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// A PDF string is a sequence of bytes, not characters.
class CosString extends CosObject {
  CosString(this.bytes, {this.isHex = false});

  /// Encodes a text string (§7.9.2.2): Latin-1 when every character fits
  /// (an approximation of PDFDocEncoding), otherwise UTF-16BE with a BOM.
  factory CosString.fromText(String text) {
    var latin1Safe = true;
    for (final code in text.codeUnits) {
      if (code > 0xFF) {
        latin1Safe = false;
        break;
      }
    }
    if (latin1Safe) return CosString(Uint8List.fromList(text.codeUnits));
    final codes = text.codeUnits;
    final bytes = Uint8List(2 + codes.length * 2);
    bytes[0] = 0xFE;
    bytes[1] = 0xFF;
    for (var i = 0; i < codes.length; i++) {
      bytes[2 + i * 2] = codes[i] >> 8;
      bytes[3 + i * 2] = codes[i] & 0xFF;
    }
    return CosString(bytes);
  }

  final Uint8List bytes;

  /// Whether the string was written (or should be written) in `<hex>` form.
  final bool isHex;

  /// The characters PDFDocEncoding (§7.9.2 / Annex D.3) places where Latin-1
  /// has C1 control codes or different glyphs. Byte -> Unicode code point.
  /// Every byte not listed here decodes identically under PDFDocEncoding and
  /// Latin-1 (0x00-0x7E ASCII, 0xA1-0xFF Latin-1, and the few undefined slots
  /// 0x7F/0x9F/0xAD which we pass through), so only these need a lookup.
  static const Map<int, int> _pdfDocToUnicode = {
    0x18: 0x02D8, 0x19: 0x02C7, 0x1A: 0x02C6, 0x1B: 0x02D9, // breve..dotaccent
    0x1C: 0x02DD, 0x1D: 0x02DB, 0x1E: 0x02DA, 0x1F: 0x02DC, // hungar..tilde
    0x80: 0x2022, 0x81: 0x2020, 0x82: 0x2021, 0x83: 0x2026, // bullet..ellipsis
    0x84: 0x2014, 0x85: 0x2013, 0x86: 0x0192, 0x87: 0x2044, // emdash,endash..
    0x88: 0x2039, 0x89: 0x203A, 0x8A: 0x2212, 0x8B: 0x2030, //
    0x8C: 0x201E, 0x8D: 0x201C, 0x8E: 0x201D, 0x8F: 0x2018, // quotes
    0x90: 0x2019, 0x91: 0x201A, 0x92: 0x2122, 0x93: 0xFB01, // quote,tm,fi
    0x94: 0xFB02, 0x95: 0x0141, 0x96: 0x0152, 0x97: 0x0160, // fl,Lslash,OE..
    0x98: 0x0178, 0x99: 0x017D, 0x9A: 0x0131, 0x9B: 0x0142, //
    0x9C: 0x0153, 0x9D: 0x0161, 0x9E: 0x017E, 0xA0: 0x20AC, // ..zcaron,Euro
  };

  /// Decodes as text (§7.9.2.2): UTF-16BE or UTF-8 when a BOM is present,
  /// otherwise PDFDocEncoding - Latin-1 for most bytes, but with the
  /// punctuation and accents PDFDocEncoding places where Latin-1 has C1
  /// control codes (e.g. byte 0x85 is an en dash, not U+0085). Decoding those
  /// as raw Latin-1 rendered them as missing-glyph boxes.
  String get text {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codes = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codes.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codes);
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return String.fromCharCodes([
      for (final b in bytes) _pdfDocToUnicode[b] ?? b,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! CosString || other.bytes.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => '($text)';
}

class CosName extends CosObject {
  const CosName(this.value);

  /// The name without its leading slash.
  final String value;

  @override
  bool operator ==(Object other) => other is CosName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '/$value';
}

class CosArray extends CosObject {
  CosArray([List<CosObject>? items]) : items = items ?? [];

  final List<CosObject> items;

  int get length => items.length;

  CosObject operator [](int index) => items[index];

  @override
  String toString() => '[${items.join(' ')}]';
}

class CosDictionary extends CosObject {
  CosDictionary([Map<String, CosObject>? entries]) : entries = entries ?? {};

  /// Keyed by name without the leading slash.
  final Map<String, CosObject> entries;

  CosObject? operator [](String key) => entries[key];

  void operator []=(String key, CosObject value) => entries[key] = value;

  bool containsKey(String key) => entries.containsKey(key);

  /// The /Type entry's name, when present and a name.
  String? get typeName {
    final t = entries['Type'];
    return t is CosName ? t.value : null;
  }

  @override
  String toString() =>
      '<< ${entries.entries.map((e) => '/${e.key} ${e.value}').join(' ')} >>';
}

class CosStream extends CosObject {
  CosStream(this.dictionary, this.rawBytes);

  final CosDictionary dictionary;

  /// The stream payload exactly as stored in the file (still encoded).
  final Uint8List rawBytes;

  /// The indirect object this stream was parsed from, set by the document
  /// when it loads the stream. In an encrypted file this doubles as the
  /// key source (the encryption key derives from the ref) and marks
  /// [rawBytes] as still the file's original payload - the incremental
  /// updater writes such payloads through verbatim rather than
  /// re-encrypting them. Null for streams built in memory (editor output,
  /// re-encrypted copies).
  CosReference? sourceRef;

  @override
  String toString() => 'stream(${rawBytes.length} bytes) $dictionary';
}

/// An indirect reference, e.g. `12 0 R`.
class CosReference extends CosObject {
  const CosReference(this.objectNumber, this.generation);

  final int objectNumber;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is CosReference &&
      other.objectNumber == objectNumber &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(objectNumber, generation);

  @override
  String toString() => '$objectNumber $generation R';
}

/// A numbered object as it appears in the file body: `N G obj ... endobj`.
class CosIndirectObject {
  const CosIndirectObject(this.objectNumber, this.generation, this.object);

  final int objectNumber;
  final int generation;
  final CosObject object;

  @override
  String toString() => '$objectNumber $generation obj $object';
}

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

  /// Decodes as text: UTF-16BE or UTF-8 when a BOM is present, otherwise
  /// Latin-1 as an approximation of PDFDocEncoding.
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
    return latin1.decode(bytes);
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

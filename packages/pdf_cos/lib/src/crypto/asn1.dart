/// Minimal ASN.1 DER reader and writer - just enough for CMS signatures
/// and X.509 certificates. Definite lengths and low-tag-number form only,
/// which is all DER-encoded PKIX structures use.
library;

import 'dart:typed_data';

/// Universal tag numbers this library cares about.
abstract final class DerTag {
  static const integer = 0x02;
  static const bitString = 0x03;
  static const octetString = 0x04;
  static const nullValue = 0x05;
  static const oid = 0x06;
  static const utf8String = 0x0C;
  static const sequence = 0x30;
  static const set = 0x31;
  static const printableString = 0x13;
  static const t61String = 0x14;
  static const ia5String = 0x16;
  static const utcTime = 0x17;
  static const generalizedTime = 0x18;
  static const bmpString = 0x1E;

  /// Context-specific constructed tag [n].
  static int context(int n) => 0xA0 | n;

  /// Context-specific primitive tag [n].
  static int contextPrimitive(int n) => 0x80 | n;
}

/// One parsed DER value: identifier octet, content octets, and the full
/// encoded byte range (needed when a signature is computed over the exact
/// encoding of a sub-structure).
class DerObject {
  DerObject(this.tag, this.content, this.encoded);

  /// Parses a single value that must span [bytes] exactly.
  factory DerObject.parse(Uint8List bytes) {
    final (object, end) = _read(bytes, 0);
    if (end != bytes.length) {
      throw FormatException('trailing bytes after DER value', bytes, end);
    }
    return object;
  }

  /// Parses the first value, ignoring whatever follows it - PDF /Contents
  /// entries pad the DER blob with zeros to their pre-allocated size.
  static DerObject parsePrefix(Uint8List bytes) => _read(bytes, 0).$1;

  /// Parses back-to-back values until [bytes] is exhausted.
  static List<DerObject> parseAll(Uint8List bytes) {
    final out = <DerObject>[];
    var offset = 0;
    while (offset < bytes.length) {
      final (object, end) = _read(bytes, offset);
      out.add(object);
      offset = end;
    }
    return out;
  }

  static (DerObject, int) _read(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) {
      throw FormatException('truncated DER value', bytes, offset);
    }
    final start = offset;
    final tag = bytes[offset++];
    if (tag & 0x1F == 0x1F) {
      throw FormatException('high-tag-number form unsupported', bytes, start);
    }
    var length = bytes[offset++];
    if (length == 0x80) {
      throw FormatException('indefinite length is not DER', bytes, start);
    }
    if (length > 0x80) {
      final count = length & 0x7F;
      if (count > 4 || offset + count > bytes.length) {
        throw FormatException('bad DER length', bytes, start);
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }
    if (offset + length > bytes.length) {
      throw FormatException('DER value overruns input', bytes, start);
    }
    return (
      DerObject(
        tag,
        Uint8List.sublistView(bytes, offset, offset + length),
        Uint8List.sublistView(bytes, start, offset + length),
      ),
      offset + length,
    );
  }

  final int tag;
  final Uint8List content;
  final Uint8List encoded;

  bool get isConstructed => tag & 0x20 != 0;

  List<DerObject>? _children;

  /// Nested values of a constructed type.
  List<DerObject> get children => _children ??= parseAll(content);

  /// INTEGER as a (possibly negative) big integer.
  BigInt get asInteger {
    var value = BigInt.zero;
    for (final byte in content) {
      value = (value << 8) | BigInt.from(byte);
    }
    if (content.isNotEmpty && content[0] >= 0x80) {
      value -= BigInt.one << (content.length * 8);
    }
    return value;
  }

  /// OBJECT IDENTIFIER in dotted-decimal form.
  String get asOid {
    if (content.isEmpty) throw const FormatException('empty OID');
    final parts = <int>[];
    var value = 0;
    for (var i = 0; i < content.length; i++) {
      value = (value << 7) | (content[i] & 0x7F);
      if (content[i] < 0x80) {
        if (parts.isEmpty) {
          parts.addAll([value ~/ 40 > 2 ? 2 : value ~/ 40, 0]);
          parts[1] = value - parts[0] * 40;
        } else {
          parts.add(value);
        }
        value = 0;
      }
    }
    return parts.join('.');
  }

  /// BIT STRING payload, dropping the leading unused-bits octet.
  Uint8List get asBitString {
    if (content.isEmpty) return Uint8List(0);
    return Uint8List.sublistView(content, 1);
  }

  /// Text content of the common string types.
  String get asString => switch (tag) {
        DerTag.bmpString => String.fromCharCodes([
            for (var i = 0; i + 1 < content.length; i += 2)
              (content[i] << 8) | content[i + 1],
          ]),
        _ => String.fromCharCodes(content), // UTF-8 names are rare and
        // almost always ASCII; full decoding can come when needed
      };

  /// UTCTime or GeneralizedTime as UTC.
  DateTime get asTime {
    final text = String.fromCharCodes(content);
    final digits = RegExp(r'^(\d+)').firstMatch(text)?.group(1) ?? '';
    String full;
    if (tag == DerTag.utcTime) {
      // YYMMDDHHMM[SS]: 50..99 → 19xx, else 20xx (RFC 5280)
      final century = int.parse(digits.substring(0, 2)) >= 50 ? '19' : '20';
      full = '$century$digits';
    } else {
      full = digits;
    }
    if (full.length < 12) throw FormatException('bad time', text);
    final second = full.length >= 14 ? int.parse(full.substring(12, 14)) : 0;
    var time = DateTime.utc(
      int.parse(full.substring(0, 4)),
      int.parse(full.substring(4, 6)),
      int.parse(full.substring(6, 8)),
      int.parse(full.substring(8, 10)),
      int.parse(full.substring(10, 12)),
      second,
    );
    final zone = RegExp(r'([+-])(\d{2})(\d{2})$').firstMatch(text);
    if (zone != null) {
      final offset = Duration(
          hours: int.parse(zone.group(2)!),
          minutes: int.parse(zone.group(3)!));
      time = zone.group(1) == '+' ? time.subtract(offset) : time.add(offset);
    }
    return time;
  }
}

// ---------------------------------------------------------------------------
// DER encoding

Uint8List derEncode(int tag, List<int> content) {
  final out = BytesBuilder(copy: false)..addByte(tag);
  final length = content.length;
  if (length < 0x80) {
    out.addByte(length);
  } else {
    final bytes = <int>[];
    var rest = length;
    while (rest > 0) {
      bytes.insert(0, rest & 0xFF);
      rest >>= 8;
    }
    out.addByte(0x80 | bytes.length);
    out.add(bytes);
  }
  out.add(content);
  return out.takeBytes();
}

Uint8List derSequence(List<List<int>> parts) =>
    derEncode(DerTag.sequence, [for (final p in parts) ...p]);

Uint8List derSet(List<List<int>> parts) =>
    derEncode(DerTag.set, [for (final p in parts) ...p]);

/// SET OF with the DER-mandated sort of element encodings.
Uint8List derSetOf(List<Uint8List> parts) {
  final sorted = [...parts]..sort((a, b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) return a[i] - b[i];
      }
      return a.length - b.length;
    });
  return derSet(sorted);
}

Uint8List derInteger(BigInt value) {
  if (value == BigInt.zero) return derEncode(DerTag.integer, const [0]);
  if (value < BigInt.zero) {
    throw ArgumentError('negative integers are not needed here');
  }
  final bytes = <int>[];
  var rest = value;
  while (rest > BigInt.zero) {
    bytes.insert(0, (rest & BigInt.from(0xFF)).toInt());
    rest >>= 8;
  }
  if (bytes[0] >= 0x80) bytes.insert(0, 0); // keep it positive
  return derEncode(DerTag.integer, bytes);
}

Uint8List derOid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final content = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7F];
    var rest = part >> 7;
    while (rest > 0) {
      chunk.insert(0, 0x80 | (rest & 0x7F));
      rest >>= 7;
    }
    content.addAll(chunk);
  }
  return derEncode(DerTag.oid, content);
}

Uint8List derOctetString(List<int> bytes) =>
    derEncode(DerTag.octetString, bytes);

Uint8List derNull() => derEncode(DerTag.nullValue, const []);

Uint8List derUtcTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final text = '${two(t.year % 100)}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  return derEncode(DerTag.utcTime, text.codeUnits);
}

/// GeneralizedTime in the DER canonical form (always UTC, seconds present,
/// no fractional part) - what RFC 5280 §4.1.2.5.2 and RFC 3161 require.
Uint8List derGeneralizedTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final text = '${t.year.toString().padLeft(4, '0')}${two(t.month)}'
      '${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  return derEncode(DerTag.generalizedTime, text.codeUnits);
}

Uint8List derBoolean(bool value) =>
    derEncode(0x01, [value ? 0xFF : 0x00]);

/// ENUMERATED, same content form as INTEGER.
Uint8List derEnumerated(int value) {
  final bytes = <int>[];
  var rest = value;
  if (rest == 0) {
    bytes.add(0);
  } else {
    while (rest > 0) {
      bytes.insert(0, rest & 0xFF);
      rest >>= 8;
    }
    if (bytes[0] >= 0x80) bytes.insert(0, 0);
  }
  return derEncode(0x0A, bytes);
}

/// BIT STRING with no unused trailing bits (the only form PKIX uses here).
Uint8List derBitString(List<int> bytes) =>
    derEncode(DerTag.bitString, [0, ...bytes]);

/// Context-specific constructed value [n] wrapping raw encoded [content].
Uint8List derContext(int n, List<int> content) =>
    derEncode(DerTag.context(n), content);

/// Context-specific primitive value [n] carrying raw [content] octets.
Uint8List derContextPrimitive(int n, List<int> content) =>
    derEncode(DerTag.contextPrimitive(n), content);

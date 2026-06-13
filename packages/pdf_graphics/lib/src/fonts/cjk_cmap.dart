import 'dart:convert';
import 'dart:typed_data';

import '_big5_data.dart';
import '_euc_jp_data.dart';
import '_gbk_data.dart';
import '_shift_jis_data.dart';
import '_uhc_data.dart';

/// Decoder for a predefined CJK CMap used by non-embedded Type0 fonts.
///
/// A full predefined-CMap implementation would map bytes → CID via the Adobe
/// CMap and CID → Unicode via the registry/ordering. For the common
/// non-embedded case the composition collapses to a plain legacy-charset →
/// Unicode decode, which is what these decoders do: split the show-text bytes
/// per the charset codespace and look each multi-byte code up in an embedded
/// table (or, for the `Uni*-UCS2/UTF16` CMaps, read the code as Unicode
/// directly). The renderer has no glyph outlines for these fonts anyway, so it
/// substitutes a system CJK font using the Unicode we return — exactly what
/// PDF.js does in Node.
///
/// Covered families: Shift-JIS (`*-RKSJ-*`, Adobe-Japan1), EUC-JP (`EUC-H/V`,
/// Adobe-Japan1), GBK/GB2312 (`GB*-EUC`, `GBK*`, Adobe-GB1), Big5 (`B5*`,
/// `ETen-B5`, `HKscs-B5`, Adobe-CNS1), Unified Hangul Code / EUC-KR (`KSC*`,
/// Adobe-Korea1), and the Unicode CMaps (`Uni*-UCS2-*`, `Uni*-UTF16-*`).
/// `Identity-H/V` and embedded CMap streams keep the interpreter's two-byte
/// path instead and never reach here. Predefined CMaps that don't collapse to
/// one of these charsets (e.g. `CNS-EUC` / EUC-TW, the JIS X 0212 supplement
/// behind EUC-JP's SS3 prefix) still fall back to that path.
abstract class CjkCmap {
  const CjkCmap();

  /// Splits show-text bytes into character codes per the CMap's codespace.
  List<int> split(Uint8List bytes);

  /// Best-effort Unicode for one character code (empty string when unmapped).
  String unicode(int code);

  /// The decoder for [encodingName], or null when the name is not a handled
  /// predefined CMap (`Identity-H/V`, embedded CMap stream names, and charset
  /// families we don't cover all return null — the caller keeps the two-byte
  /// path).
  static CjkCmap? forName(String? encodingName) {
    if (encodingName == null) return null;
    if (ShiftJisCmap.handles(encodingName)) return const ShiftJisCmap();
    if (EucJpCmap.handles(encodingName)) return const EucJpCmap();
    if (GbkCmap.handles(encodingName)) return const GbkCmap();
    if (Big5Cmap.handles(encodingName)) return const Big5Cmap();
    if (UhcCmap.handles(encodingName)) return const UhcCmap();
    return UnicodeCmap.forName(encodingName);
  }
}

/// Binary search a sorted 4-bytes-per-entry `(u16 code, u16 unicode)` table.
int? _lookup(Uint8List data, int code) {
  var lo = 0;
  var hi = (data.length ~/ 4) - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final off = mid * 4;
    final key = (data[off] << 8) | data[off + 1];
    if (key == code) return (data[off + 2] << 8) | data[off + 3];
    if (key < code) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return null;
}

/// Decoder for the predefined Shift-JIS ("90ms-RKSJ") CMap family used by
/// non-embedded Adobe-Japan1 Type0 fonts.
class ShiftJisCmap extends CjkCmap {
  const ShiftJisCmap();

  static Uint8List? _table;

  /// The packed `(code, unicode)` table, decoded from base64 on first use.
  static Uint8List get _data => _table ??= base64.decode(shiftJisPackedBase64);

  /// True for predefined Shift-JIS CMap names (90ms-RKSJ-H, 90pv-RKSJ-V,
  /// Ext-RKSJ-H, …) — every member carries the `RKSJ` token.
  static bool handles(String? encodingName) =>
      encodingName != null && encodingName.contains('RKSJ');

  /// Splits show-text bytes into character codes per the Shift-JIS codespace:
  /// lead bytes 0x81–0x9F and 0xE0–0xFC consume a trailing byte; everything
  /// else (ASCII, half-width katakana 0xA1–0xDF) is a single byte.
  @override
  List<int> split(Uint8List bytes) {
    final codes = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      final lead = (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC);
      if (lead && i + 1 < bytes.length) {
        codes.add((b << 8) | bytes[++i]);
      } else {
        codes.add(b);
      }
    }
    return codes;
  }

  /// Best-effort Unicode for one Shift-JIS code (empty string when unmapped).
  @override
  String unicode(int code) {
    if (code <= 0xFF) {
      if (code >= 0xA1 && code <= 0xDF) {
        return String.fromCharCode(0xFF61 + (code - 0xA1)); // half-width kana
      }
      return String.fromCharCode(code); // ASCII / single-byte Latin-1
    }
    final u = _lookup(_data, code);
    return u == null ? '' : String.fromCharCode(u);
  }
}

/// Decoder for the predefined EUC-JP ("EUC-H"/"EUC-V") CMaps used by
/// non-embedded Adobe-Japan1 Type0 fonts.
class EucJpCmap extends CjkCmap {
  const EucJpCmap();

  static Uint8List? _table;
  static Uint8List get _data => _table ??= base64.decode(eucJpPackedBase64);

  /// True for the EUC-JP CMap names — exactly `EUC-H` and `EUC-V` (the GB/KSC
  /// `*-EUC-*` names carry their own registry prefix and route elsewhere).
  static bool handles(String? encodingName) =>
      encodingName == 'EUC-H' || encodingName == 'EUC-V';

  /// Splits per the EUC-JP codespace: `0x8E` (SS2) prefixes a half-width kana
  /// byte (two-byte code `0x8Exx`); `0x8F` (SS3) prefixes a JIS X 0212 pair we
  /// don't decode (consumed, mapped to nothing); lead bytes `0xA1–0xFE` consume
  /// a trailing byte; everything else (ASCII) is a single byte.
  @override
  List<int> split(Uint8List bytes) {
    final codes = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x8E && i + 1 < bytes.length) {
        codes.add((b << 8) | bytes[++i]);
      } else if (b == 0x8F && i + 2 < bytes.length) {
        codes.add((b << 8) | bytes[i + 1]); // JIS X 0212 — unmapped
        i += 2;
      } else if (b >= 0xA1 && b <= 0xFE && i + 1 < bytes.length) {
        codes.add((b << 8) | bytes[++i]);
      } else {
        codes.add(b);
      }
    }
    return codes;
  }

  @override
  String unicode(int code) {
    if (code <= 0xFF) return String.fromCharCode(code); // ASCII
    final u = _lookup(_data, code);
    return u == null ? '' : String.fromCharCode(u);
  }
}

/// Shared splitter for the GBK/Big5/UHC families: a lead byte in `0x81–0xFE`
/// consumes one trailing byte (the codecs only define `≥ 0x40` trails, but the
/// table lookup rejects undefined pairs anyway); everything else is one byte.
List<int> _splitDoubleByte(Uint8List bytes) {
  final codes = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
      codes.add((b << 8) | bytes[++i]);
    } else {
      codes.add(b);
    }
  }
  return codes;
}

/// Unicode for a double-byte-charset code via [data]: ASCII passes through,
/// two-byte codes look up the table.
String _doubleByteUnicode(Uint8List data, int code) {
  if (code < 0x80) return String.fromCharCode(code);
  if (code <= 0xFF) return ''; // undefined single byte
  final u = _lookup(data, code);
  return u == null ? '' : String.fromCharCode(u);
}

/// Decoder for the predefined GBK / GB2312 CMaps (`GB*-EUC-*`, `GBK*`,
/// `GBpc-EUC-*`) used by non-embedded Adobe-GB1 Type0 fonts.
class GbkCmap extends CjkCmap {
  const GbkCmap();

  static Uint8List? _table;
  static Uint8List get _data => _table ??= base64.decode(gbkPackedBase64);

  /// True for the GB-registry CMap names: `GB-EUC-*`, `GBpc-EUC-*`, `GBK-EUC-*`,
  /// `GBKp-EUC-*`, `GBK2K-*`, `GBT-EUC-*` (all start with `GB`; the `UniGB-*`
  /// Unicode CMaps start with `Uni` and route to [UnicodeCmap]).
  static bool handles(String? encodingName) =>
      encodingName != null && encodingName.startsWith('GB');

  @override
  List<int> split(Uint8List bytes) => _splitDoubleByte(bytes);

  @override
  String unicode(int code) => _doubleByteUnicode(_data, code);
}

/// Decoder for the predefined Big5 CMaps (`B5*`, `ETen-B5*`, `HKscs-B5*`) used
/// by non-embedded Adobe-CNS1 Type0 fonts.
class Big5Cmap extends CjkCmap {
  const Big5Cmap();

  static Uint8List? _table;
  static Uint8List get _data => _table ??= base64.decode(big5PackedBase64);

  /// True for the Big5-registry CMap names — every member carries the `B5`
  /// token (`B5pc-H`, `ETen-B5-H`, `HKscs-B5-H`, …).
  static bool handles(String? encodingName) =>
      encodingName != null && encodingName.contains('B5');

  @override
  List<int> split(Uint8List bytes) => _splitDoubleByte(bytes);

  @override
  String unicode(int code) => _doubleByteUnicode(_data, code);
}

/// Decoder for the predefined Korean CMaps (`KSC-EUC-*`, `KSCms-UHC-*`,
/// `KSCpc-EUC-*`) used by non-embedded Adobe-Korea1 Type0 fonts. UHC (CP949) is
/// a superset of EUC-KR, so one table serves both.
class UhcCmap extends CjkCmap {
  const UhcCmap();

  static Uint8List? _table;
  static Uint8List get _data => _table ??= base64.decode(uhcPackedBase64);

  /// True for the KSC-registry CMap names (all start with `KSC`; the `UniKS-*`
  /// Unicode CMaps start with `Uni` and route to [UnicodeCmap]).
  static bool handles(String? encodingName) =>
      encodingName != null && encodingName.startsWith('KSC');

  @override
  List<int> split(Uint8List bytes) => _splitDoubleByte(bytes);

  @override
  String unicode(int code) => _doubleByteUnicode(_data, code);
}

/// Decoder for the Unicode CMaps (`UniGB-UCS2-H`, `UniJIS-UTF16-H`, …): the
/// show-text bytes are already Unicode, so no charset table is needed. UCS-2
/// codes are BMP scalars; UTF-16BE codes combine surrogate pairs.
class UnicodeCmap extends CjkCmap {
  const UnicodeCmap({required this.utf16});

  /// Whether to combine UTF-16BE surrogate pairs (`Uni*-UTF16-*`); UCS-2
  /// (`Uni*-UCS2-*`) is plain two-byte big-endian.
  final bool utf16;

  /// The decoder for a `Uni*-UCS2-*` / `Uni*-UTF16-*` CMap name, or null for
  /// other `Uni*` names (UTF-8/UTF-32 variants we don't handle).
  static UnicodeCmap? forName(String? encodingName) {
    if (encodingName == null || !encodingName.startsWith('Uni')) return null;
    if (encodingName.contains('UCS2')) return const UnicodeCmap(utf16: false);
    if (encodingName.contains('UTF16')) return const UnicodeCmap(utf16: true);
    return null;
  }

  @override
  List<int> split(Uint8List bytes) {
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = (bytes[i] << 8) | bytes[i + 1];
      if (utf16 &&
          unit >= 0xD800 &&
          unit <= 0xDBFF &&
          i + 3 < bytes.length) {
        final low = (bytes[i + 2] << 8) | bytes[i + 3];
        if (low >= 0xDC00 && low <= 0xDFFF) {
          codes.add(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
          i += 2;
          continue;
        }
      }
      codes.add(unit);
    }
    return codes;
  }

  @override
  String unicode(int code) =>
      code >= 0xD800 && code <= 0xDFFF ? '' : String.fromCharCode(code);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'font_embedder.dart';

/// One composite (/Type0) font, parsed once from its font dictionary and
/// shared by everything that reads or rewrites its text.
///
/// A /Type0 run draws multi-byte codes rather than one byte per character.
/// For the dominant Identity-H + CIDFontType2 + Identity-CIDToGIDMap shape -
/// what this library emits and most real producers use - a content-stream
/// code *is* a glyph id, its text comes from the font's `/ToUnicode` CMap,
/// and its advance from the descendant CIDFont's `/W` array (or `/DW`).
///
/// This one object replaces four near-identical restatements of that
/// knowledge (extraction's decoder, the editor's rewriter, the reflow
/// adapter, and the loose metric helpers). Two construction contracts:
///
///  * [Type0Font.decode] is *lenient* - it builds the code -> text / code ->
///    width maps for any /Type0 font so extraction can show real text and
///    measure runs, never null.
///  * [Type0Font.forEditing] enforces the *strict* eligibility gate (an
///    embedded, Identity-H, CIDFontType2, Identity-CIDToGIDMap program with a
///    usable `/ToUnicode`) and additionally parses the embedded program so
///    replacements can be re-encoded and new glyphs recorded; it returns null
///    when the font is anything this path can't safely round-trip.
class Type0Font {
  Type0Font._(
    this._cos,
    this.fontDict,
    this.cidFont,
    this.codeToText,
    this._cidWidths,
    this._dw, {
    this.embedded,
    this.serif = false,
    this.mono = false,
  });

  final CosDocument _cos;

  /// The /Type0 font dictionary.
  final CosDictionary fontDict;

  /// The descendant CIDFont dictionary (`/DescendantFonts[0]`).
  final CosDictionary cidFont;

  /// code (a 2-byte content code) -> its Unicode text, from `/ToUnicode`.
  final Map<int, String> codeToText;

  /// code -> advance width (thousandths of an em), from `/W`.
  final Map<int, double> _cidWidths;

  /// The default glyph width `/DW` (1000 when absent, per §9.7.4.3).
  final double _dw;

  /// The parsed embedded program - present only for an editable font
  /// ([forEditing]); null for a decode-only one ([decode]).
  final PdfEmbeddedFont? embedded;

  /// Preferred fallback style, from the descriptor `/Flags` (serif bit 2,
  /// fixed-pitch bit 1, per §9.8.2 Table 121) - used when a replacement
  /// glyph must be drawn in a bundled fallback face.
  final bool serif;
  final bool mono;

  /// New glyphs introduced by replacements in *this* font, gid -> rune,
  /// flushed into `/W` and `/ToUnicode` by [commitFontDict].
  final Map<int, int> _newGlyphs = {};

  /// True when the strict editing gate passed and this font can encode
  /// replacements and record new glyphs.
  bool get canEdit => embedded != null;

  /// True when replacements have introduced glyphs not yet flushed to the
  /// font dictionary.
  bool get isDirty => _newGlyphs.isNotEmpty;

  /// The advance (thousandths of an em) of content code [code].
  double widthOf(int code) => _cidWidths[code] ?? _dw;

  /// Builds a decode-only font for any /Type0 [fontDict]. Never null: a
  /// missing `/ToUnicode` or `/W` just yields empty maps.
  factory Type0Font.decode(CosDocument cos, CosDictionary fontDict) {
    final codeToText = _readToUnicode(cos, fontDict);
    var widths = <int, double>{};
    var dw = 1000.0;
    CosDictionary cidFont = fontDict;
    final desc = cos.resolve(fontDict['DescendantFonts']);
    if (desc is CosArray && desc.items.isNotEmpty) {
      final cid = cos.resolve(desc.items.first);
      if (cid is CosDictionary) {
        cidFont = cid;
        widths = parseCidWidths(cos, cid);
        dw = cidDefaultWidth(cos, cid);
      }
    }
    return Type0Font._(cos, fontDict, cidFont, codeToText, widths, dw);
  }

  /// Builds an editable font, or null when [fontDict] is not the Identity-H /
  /// CIDFontType2 / Identity-CIDToGIDMap composite this path can safely
  /// rewrite (a CFF descendant, a stream `/CIDToGIDMap`, a non-Identity-H
  /// encoding, a missing/garbled embedded program, or an empty `/ToUnicode`
  /// all disqualify it). The eligibility check *is* the construction
  /// contract - a non-null result is a guarantee the font can be edited.
  static Type0Font? forEditing(CosDocument cos, CosDictionary fontDict) {
    try {
      final enc = cos.resolve(fontDict['Encoding']);
      if (enc is! CosName || enc.value != 'Identity-H') return null;
      final desc = cos.resolve(fontDict['DescendantFonts']);
      if (desc is! CosArray || desc.items.isEmpty) return null;
      final cidFont = cos.resolve(desc.items.first);
      if (cidFont is! CosDictionary) return null;
      final sub = cos.resolve(cidFont['Subtype']);
      if (sub is! CosName || sub.value != 'CIDFontType2') return null;
      // CIDToGIDMap must be Identity (a name, or absent -> default Identity);
      // a stream means code != gid and we can't emit glyph ids directly.
      final c2g = cos.resolve(cidFont['CIDToGIDMap']);
      if (c2g is CosStream) return null;
      if (c2g is CosName && c2g.value != 'Identity') return null;
      final embedded = PdfEmbeddedFont.fromFontDict(cos, fontDict, 'F0');
      if (embedded == null) return null;
      final toUni = cos.resolve(fontDict['ToUnicode']);
      if (toUni is! CosStream) return null;
      final codeToText = parseToUnicodeCmap(cos.decodeStreamData(toUni));
      if (codeToText.isEmpty) return null;
      var flags = 0;
      final fd = cos.resolve(cidFont['FontDescriptor']);
      if (fd is CosDictionary) {
        final f = cos.resolve(fd['Flags']);
        if (f is CosInteger) flags = f.value;
      }
      return Type0Font._(
        cos,
        fontDict,
        cidFont,
        codeToText,
        parseCidWidths(cos, cidFont),
        cidDefaultWidth(cos, cidFont),
        embedded: embedded,
        serif: flags & 2 != 0,
        mono: flags & 1 != 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// The glyph id [rune] maps to in the embedded program, or 0 when it has no
  /// glyph for it. Only valid on an editable font.
  int glyphForRune(int rune) => embedded!.glyphForRune(rune);

  /// The advance (thousandths of an em) of glyph [gid] in the embedded
  /// program. Only valid on an editable font.
  double advanceForGlyph(int gid) => embedded!.advanceForGlyph(gid).toDouble();

  /// The advance of [text] in text-space points at [size], from the embedded
  /// program's own metrics. Only valid on an editable font.
  double measure(String text, double size) => embedded!.measure(text, size);

  /// Records glyph [gid] (drawn for [rune]) so its width and Unicode reach
  /// the font's `/W` and `/ToUnicode` at [commitFontDict], and returns the
  /// glyph's advance (thousandths of an em).
  double recordGlyph(int gid, int rune) {
    final w = advanceForGlyph(gid);
    if (!_cidWidths.containsKey(gid) || codeToText[gid] != _stringOf(rune)) {
      _newGlyphs[gid] = rune;
    }
    return _cidWidths[gid] ?? w;
  }

  /// Encodes [text] as an Identity-H hex show string (2-byte glyph ids),
  /// recording each glyph for the `/W` + `/ToUnicode` flush. Returns null
  /// when the embedded program lacks a glyph for any non-space rune - the
  /// caller (paragraph reflow) then bails rather than draw `.notdef`.
  CosString? encodeIdentity(String text) {
    final buffer = <int>[];
    for (final rune in text.runes) {
      final gid = glyphForRune(rune);
      if (rune == 0x20) {
        // a space needs no outline; emit the font's space glyph if it has
        // one, else a zero code so wrapping math still holds.
        buffer
          ..add(gid >> 8)
          ..add(gid & 0xFF);
        if (gid != 0) recordGlyph(gid, rune);
        continue;
      }
      if (gid == 0) return null; // the font can't draw it
      buffer
        ..add(gid >> 8)
        ..add(gid & 0xFF);
      recordGlyph(gid, rune);
    }
    return CosString(Uint8List.fromList(buffer), isHex: true);
  }

  /// The bundled fallback in [fallbacks] that can draw every rune in [runes],
  /// preferring a family that matches this font's serif/monospace style.
  PdfEmbeddedFont? pickFallback(
      List<int> runes, List<PdfEmbeddedFont> fallbacks) {
    bool draws(PdfEmbeddedFont f) => runes.every((r) => f.glyphForRune(r) != 0);
    final candidates = fallbacks.where(draws).toList();
    if (candidates.isEmpty) return null;
    bool isMono(PdfEmbeddedFont f) =>
        f.familyName.toLowerCase().contains('mono');
    bool isSerif(PdfEmbeddedFont f) =>
        f.familyName.toLowerCase().contains('serif') && !isMono(f);
    if (mono) {
      final m = candidates.where(isMono);
      if (m.isNotEmpty) return m.first;
    }
    if (serif) {
      final s = candidates.where(isSerif);
      if (s.isNotEmpty) return s.first;
    }
    final sans = candidates.where((f) => !isSerif(f) && !isMono(f));
    return sans.isNotEmpty ? sans.first : candidates.first;
  }

  /// Writes the recorded new glyphs into the descendant `/W` and a rebuilt
  /// `/ToUnicode`, marking any indirect font dictionaries changed on
  /// [updater]. A no-op when no new glyphs were introduced. Inline (direct)
  /// font dictionaries ride along on the page rewrite the caller performs.
  void commitFontDict(CosIncrementalUpdater updater) {
    if (_newGlyphs.isEmpty) return;
    for (final entry in _newGlyphs.entries) {
      _cidWidths[entry.key] = advanceForGlyph(entry.key);
      codeToText[entry.key] = _stringOf(entry.value);
    }
    final wItems = <CosObject>[];
    final codes = _cidWidths.keys.toList()..sort();
    for (final code in codes) {
      final w = _cidWidths[code]!;
      if (w == _dw) continue;
      wItems
        ..add(CosInteger(code))
        ..add(CosArray([_numberObject(w)]));
    }
    cidFont['W'] = CosArray(wItems);
    fontDict['ToUnicode'] = updater.addObject(_buildToUnicode());
    if (_cos.referenceTo(cidFont) != null) updater.markChanged(cidFont);
    if (_cos.referenceTo(fontDict) != null) updater.markChanged(fontDict);
  }

  CosStream _buildToUnicode() {
    final codes = codeToText.keys.toList()..sort();
    final buf = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) '
          '/Supplement 0 >> def')
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');
    for (var i = 0; i < codes.length; i += 100) {
      final group = codes.sublist(i, (i + 100).clamp(0, codes.length));
      buf.writeln('${group.length} beginbfchar');
      for (final code in group) {
        final src = code.toRadixString(16).padLeft(4, '0');
        buf.writeln('<$src> <${_utf16BeHexOf(codeToText[code]!)}>');
      }
      buf.writeln('endbfchar');
    }
    buf
      ..writeln('endcmap')
      ..writeln('CMapName currentdict /CMap defineresource pop')
      ..writeln('end')
      ..writeln('end');
    final bytes = Uint8List.fromList(latin1.encode(buf.toString()));
    return CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes);
  }

  static String _stringOf(int rune) => String.fromCharCodes([rune]);

  /// UTF-16BE hex of every code unit in [s] (surrogate pairs preserved).
  static String _utf16BeHexOf(String s) {
    final out = StringBuffer();
    for (final unit in s.codeUnits) {
      out.write(unit.toRadixString(16).padLeft(4, '0'));
    }
    return out.toString();
  }

  static Map<int, String> _readToUnicode(
      CosDocument cos, CosDictionary fontDict) {
    final toUni = cos.resolve(fontDict['ToUnicode']);
    return toUni is CosStream
        ? parseToUnicodeCmap(cos.decodeStreamData(toUni))
        : <int, String>{};
  }

  static CosObject _numberObject(double value) {
    final rounded = double.parse(value.toStringAsFixed(3));
    return rounded == rounded.roundToDouble()
        ? CosInteger(rounded.toInt())
        : CosReal(rounded);
  }
}

double _num(CosObject? o) => switch (o) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => 0,
    };

/// Parses a `/ToUnicode` CMap stream's text into a code -> string map,
/// handling both `bfchar` and `bfrange` (single-base and array forms).
Map<int, String> parseToUnicodeCmap(List<int> data) {
  final text = latin1.decode(data, allowInvalid: true);
  final map = <int, String>{};
  final hex = RegExp(r'<([0-9A-Fa-f]+)>');

  for (final block
      in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(text)) {
    final toks = hex.allMatches(block.group(1)!).toList();
    for (var i = 0; i + 1 < toks.length; i += 2) {
      final src = int.parse(toks[i].group(1)!, radix: 16);
      map[src] = _utf16BeToString(toks[i + 1].group(1)!);
    }
  }

  final tokenRe = RegExp(r'<([0-9A-Fa-f]+)>|(\[)|(\])');
  for (final block
      in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(text)) {
    final toks = tokenRe.allMatches(block.group(1)!).toList();
    var i = 0;
    while (i + 1 < toks.length) {
      if (toks[i].group(1) == null || toks[i + 1].group(1) == null) {
        i++;
        continue;
      }
      final lo = int.parse(toks[i].group(1)!, radix: 16);
      final hi = int.parse(toks[i + 1].group(1)!, radix: 16);
      i += 2;
      if (i >= toks.length) break;
      if (toks[i].group(1) != null) {
        // <lo> <hi> <dstBase>: increment the last code unit across the range
        final base = _utf16BeUnits(toks[i].group(1)!);
        for (var c = lo; c <= hi && c - lo < 0x10000; c++) {
          final units = List<int>.of(base);
          if (units.isNotEmpty) units[units.length - 1] += (c - lo);
          map[c] = String.fromCharCodes(units);
        }
        i++;
      } else if (toks[i].group(2) != null) {
        // <lo> <hi> [ <d0> <d1> ... ]
        i++;
        var c = lo;
        while (i < toks.length && toks[i].group(1) != null) {
          map[c++] = _utf16BeToString(toks[i].group(1)!);
          i++;
        }
        if (i < toks.length && toks[i].group(3) != null) i++;
      }
    }
  }
  return map;
}

/// Parses a CIDFont `/W` array into a code -> advance-width map (thousandths
/// of an em), handling both `c [w...]` and `cFirst cLast w` forms.
Map<int, double> parseCidWidths(CosDocument cos, CosDictionary cidFont) {
  final map = <int, double>{};
  final w = cos.resolve(cidFont['W']);
  if (w is! CosArray) return map;
  final items = w.items;
  var i = 0;
  while (i < items.length) {
    final first = cos.resolve(items[i]);
    if (first is! CosInteger || i + 1 >= items.length) {
      i++;
      continue;
    }
    final next = cos.resolve(items[i + 1]);
    if (next is CosArray) {
      var cid = first.value;
      for (final wv in next.items) {
        map[cid++] = _num(cos.resolve(wv));
      }
      i += 2;
    } else if ((next is CosInteger || next is CosReal) && i + 2 < items.length) {
      final last = _num(next).round();
      final width = _num(cos.resolve(items[i + 2]));
      for (var cid = first.value; cid <= last; cid++) {
        map[cid] = width;
      }
      i += 3;
    } else {
      i++;
    }
  }
  return map;
}

/// The CIDFont's default glyph width `/DW` (thousandths of an em; 1000 when
/// absent, per §9.7.4.3).
double cidDefaultWidth(CosDocument cos, CosDictionary cidFont) {
  final dw = cos.resolve(cidFont['DW']);
  return (dw is CosInteger || dw is CosReal) ? _num(dw) : 1000;
}

List<int> _utf16BeUnits(String hexStr) {
  final units = <int>[];
  for (var i = 0; i + 4 <= hexStr.length; i += 4) {
    units.add(int.parse(hexStr.substring(i, i + 4), radix: 16));
  }
  return units;
}

String _utf16BeToString(String hexStr) =>
    String.fromCharCodes(_utf16BeUnits(hexStr));

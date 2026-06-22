import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';

/// Helpers for reading composite (/Type0) font metrics — the `/ToUnicode`
/// CMap (code → text) and the descendant CIDFont's `/W` widths — shared by
/// content-element extraction (to show real text and measure runs) and the
/// Type0 text editor (to match and re-measure replacements).

double _num(CosObject? o) => switch (o) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => 0,
    };

/// Parses a `/ToUnicode` CMap stream's text into a code → string map,
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

/// Parses a CIDFont `/W` array into a code → advance-width map (thousandths
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

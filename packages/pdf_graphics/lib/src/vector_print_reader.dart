/// The reference reader for the vector-print op stream produced by
/// [encodeVectorPrintPage]. It decodes the bytes back into structured ops -
/// exactly the shape the native replayers (`windows/runner/native_print.cpp`
/// GDI, `linux/runner/vector_print.cc` Cairo) consume. Keeping a Dart reader
/// lets the tests assert the stream round-trips faithfully and documents the
/// binary format for the C++ side to mirror.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'vector_print.dart';

/// A decoded vector-print page: its device-point size and the flat op list.
class VectorPrintPage {
  VectorPrintPage(this.widthPt, this.heightPt, this.ops);

  /// Device-point page size (top-left origin, y down). One unit = one PDF
  /// point; the consumer scales by printerDPI/72.
  final double widthPt;
  final double heightPt;
  final List<VectorPrintOp> ops;
}

/// One replayable op.
sealed class VectorPrintOp {
  const VectorPrintOp();
}

class VpSave extends VectorPrintOp {
  const VpSave();
}

class VpRestore extends VectorPrintOp {
  const VpRestore();
}

/// An RGBA colour, 0-255 per channel.
class VpColor {
  const VpColor(this.r, this.g, this.b, this.a);
  final int r, g, b, a;

  @override
  bool operator ==(Object other) =>
      other is VpColor &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'VpColor($r, $g, $b, $a)';
}

/// A path in device points: a flat list of subpath commands.
class VpPath {
  VpPath(this.segments);
  final List<VpSegment> segments;
}

sealed class VpSegment {
  const VpSegment();
}

class VpMove extends VpSegment {
  const VpMove(this.x, this.y);
  final double x, y;
}

class VpLine extends VpSegment {
  const VpLine(this.x, this.y);
  final double x, y;
}

class VpCubic extends VpSegment {
  const VpCubic(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);
  final double x1, y1, x2, y2, x3, y3;
}

class VpClose extends VpSegment {
  const VpClose();
}

class VpFillPath extends VectorPrintOp {
  VpFillPath(this.color, this.evenOdd, this.path);
  final VpColor color;
  final bool evenOdd;
  final VpPath path;
}

class VpStrokePath extends VectorPrintOp {
  VpStrokePath(this.color, this.width, this.cap, this.join, this.miterLimit,
      this.dashes, this.dashPhase, this.path);
  final VpColor color;
  final double width;
  final int cap;
  final int join;
  final double miterLimit;
  final List<double> dashes;
  final double dashPhase;
  final VpPath path;
}

class VpClipPath extends VectorPrintOp {
  VpClipPath(this.evenOdd, this.path);
  final bool evenOdd;
  final VpPath path;
}

class VpText extends VectorPrintOp {
  VpText(this.color, this.bold, this.italic, this.matrix, this.fontSize,
      this.text);
  final VpColor color;
  final bool bold;
  final bool italic;

  /// The 6-element em->device transform [a,b,c,d,e,f].
  final List<double> matrix;
  final double fontSize;
  final String text;
}

class VpImage extends VectorPrintOp {
  VpImage(this.matrix, this.width, this.height, this.rgba);

  /// The 6-element unit-square->device placement transform [a,b,c,d,e,f].
  final List<double> matrix;
  final int width;
  final int height;
  final Uint8List rgba;
}

/// Decodes a vector-print stream. Throws [FormatException] on a bad header or a
/// truncated buffer.
VectorPrintPage decodeVectorPrint(Uint8List bytes) {
  final r = _Reader(bytes);
  for (final expected in kVectorPrintMagic) {
    if (r.u8() != expected) {
      throw const FormatException('not a vector-print stream');
    }
  }
  final width = r.f32();
  final height = r.f32();
  final ops = <VectorPrintOp>[];
  while (!r.atEnd) {
    ops.add(_readOp(r));
  }
  return VectorPrintPage(width, height, ops);
}

VectorPrintOp _readOp(_Reader r) {
  final tag = r.u8();
  switch (tag) {
    case 0x01:
      return const VpSave();
    case 0x02:
      return const VpRestore();
    case 0x10:
      final color = r.rgba();
      final evenOdd = r.u8() == 1;
      return VpFillPath(color, evenOdd, r.path());
    case 0x11:
      final color = r.rgba();
      final width = r.f32();
      final cap = r.u8();
      final join = r.u8();
      final miter = r.f32();
      final dashCount = r.u16();
      final dashes = [for (var i = 0; i < dashCount; i++) r.f32()];
      final dashPhase = r.f32();
      return VpStrokePath(
          color, width, cap, join, miter, dashes, dashPhase, r.path());
    case 0x12:
      final evenOdd = r.u8() == 1;
      return VpClipPath(evenOdd, r.path());
    case 0x20:
      final color = r.rgba();
      final flags = r.u8();
      final matrix = [for (var i = 0; i < 6; i++) r.f32()];
      final fontSize = r.f32();
      // allowMalformed: a >64KB run may have been clipped mid-codepoint by the
      // encoder's length cap; tolerate the fragment rather than throwing.
      final text = utf8.decode(r.take(r.u16()), allowMalformed: true);
      return VpText(
        color,
        flags & kVectorPrintFontBold != 0,
        flags & kVectorPrintFontItalic != 0,
        matrix,
        fontSize,
        text,
      );
    case 0x30:
      final matrix = [for (var i = 0; i < 6; i++) r.f32()];
      final w = r.u32();
      final h = r.u32();
      final rgba = r.take(w * h * 4);
      return VpImage(matrix, w, h, rgba);
    default:
      throw FormatException('unknown vector-print op 0x${tag.toRadixString(16)}');
  }
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);
  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  bool get atEnd => _pos >= _bytes.length;

  /// Guards a read of [n] bytes so a truncated or corrupt stream raises the
  /// documented [FormatException] rather than an out-of-range [RangeError].
  void _need(int n) {
    if (n < 0 || _pos + n > _bytes.length) {
      throw const FormatException('truncated vector-print stream');
    }
  }

  int u8() {
    _need(1);
    return _bytes[_pos++];
  }

  int u16() {
    _need(2);
    final v = _data.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  double f32() {
    _need(4);
    final v = _data.getFloat32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  VpColor rgba() => VpColor(u8(), u8(), u8(), u8());

  Uint8List take(int n) {
    _need(n);
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return out;
  }

  VpPath path() {
    final count = u32();
    final segments = <VpSegment>[];
    for (var i = 0; i < count; i++) {
      switch (u8()) {
        case 0:
          segments.add(VpMove(f32(), f32()));
        case 1:
          segments.add(VpLine(f32(), f32()));
        case 2:
          segments.add(VpCubic(f32(), f32(), f32(), f32(), f32(), f32()));
        case 3:
          segments.add(const VpClose());
        default:
          throw const FormatException('unknown path segment');
      }
    }
    return VpPath(segments);
  }
}

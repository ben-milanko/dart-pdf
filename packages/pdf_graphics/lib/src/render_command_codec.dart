import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'matrix.dart';
import 'mesh.dart';
import 'path.dart';
import 'render_command.dart';
import 'shading.dart';

/// Binary (de)serialization for a recorded [PdfRenderCommand] buffer.
///
/// The record/replay split produces a flat, `dart:ui`-free command list. To
/// move the recording onto another thread (a native isolate, or a Web Worker
/// reached over `postMessage`) the list has to cross a boundary that copies
/// only plain data — not live Dart objects. This codec flattens the buffer to
/// a [Uint8List] and back, byte-identical on round-trip.
///
/// Every command and value type the interpreter emits is a pure value
/// ([PdfPath], [PdfColor], [PdfMatrix], [PdfTextRun] with glyph outlines, …)
/// EXCEPT [PdfImageRequest], whose `stream` is a live [CosStream] (a COS
/// dictionary plus encoded bytes, often with nested references — colour
/// spaces, soft masks). Serializing that faithfully means serializing a slice
/// of the COS object graph, which this cut does not do: [serializeCommands]
/// returns `null` for any buffer that draws an image (including inside a
/// soft-mask group), and the caller renders that page on the owning isolate
/// instead. Image-free pages — the dense vector/text pages that dominate the
/// interpret cost on CAD documents — serialize and offload.
///
/// Format: little notion of versioning beyond a leading byte; the producer and
/// consumer are the same build, shipped together, so a version mismatch is a
/// programming error, asserted on read.
const int _formatVersion = 1;

// Command tags. Stable within a build; order mirrors the sealed hierarchy.
const int _tSave = 0;
const int _tRestore = 1;
const int _tFillPath = 2;
const int _tFillPathGradient = 3;
const int _tFillMesh = 4;
const int _tStrokePath = 5;
const int _tClipPath = 6;
const int _tDrawText = 7;
// tag 8 (drawImage) is reserved but never written — images trigger fallback.
const int _tSetBlendMode = 9;
const int _tBeginGroup = 10;
const int _tEndGroup = 11;
const int _tBeginSoftMasked = 12;
const int _tEndSoftMasked = 13;

/// Thrown internally when an image command is hit; [serializeCommands]
/// catches it and returns `null` so the caller falls back to a local render.
class _UnserializableImage implements Exception {
  const _UnserializableImage();
}

/// Serializes [commands] to bytes, or returns `null` if the buffer draws any
/// image (unsupported in this cut — see the class doc).
Uint8List? serializeCommands(List<PdfRenderCommand> commands) {
  final w = _Writer();
  w.u8(_formatVersion);
  try {
    _writeCommands(w, commands);
  } on _UnserializableImage {
    return null;
  }
  return w.takeBytes();
}

/// Reconstructs the command buffer written by [serializeCommands].
List<PdfRenderCommand> deserializeCommands(Uint8List bytes) {
  final r = _Reader(bytes);
  final version = r.u8();
  assert(version == _formatVersion, 'render command format version mismatch');
  return _readCommands(r);
}

void _writeCommands(_Writer w, List<PdfRenderCommand> commands) {
  w.u32(commands.length);
  for (final command in commands) {
    _writeCommand(w, command);
  }
}

List<PdfRenderCommand> _readCommands(_Reader r) {
  final n = r.u32();
  final out = <PdfRenderCommand>[];
  for (var i = 0; i < n; i++) {
    out.add(_readCommand(r));
  }
  return out;
}

void _writeCommand(_Writer w, PdfRenderCommand command) {
  switch (command) {
    case PdfSaveCommand():
      w.u8(_tSave);
    case PdfRestoreCommand():
      w.u8(_tRestore);
    case PdfFillPathCommand(:final path, :final color, :final rule, :final alpha):
      w.u8(_tFillPath);
      _writePath(w, path);
      _writeColor(w, color);
      w.u8(rule.index);
      w.f64(alpha);
    case PdfFillPathGradientCommand(
        :final path,
        :final rule,
        :final gradient,
        :final alpha
      ):
      w.u8(_tFillPathGradient);
      _writePath(w, path);
      w.u8(rule.index);
      _writeGradient(w, gradient);
      w.f64(alpha);
    case PdfFillMeshCommand(:final mesh, :final alpha):
      w.u8(_tFillMesh);
      _writeMesh(w, mesh);
      w.f64(alpha);
    case PdfStrokePathCommand(
        :final path,
        :final color,
        :final stroke,
        :final alpha
      ):
      w.u8(_tStrokePath);
      _writePath(w, path);
      _writeColor(w, color);
      _writeStroke(w, stroke);
      w.f64(alpha);
    case PdfClipPathCommand(:final path, :final rule):
      w.u8(_tClipPath);
      _writePath(w, path);
      w.u8(rule.index);
    case PdfDrawTextCommand(:final run):
      w.u8(_tDrawText);
      _writeTextRun(w, run);
    case PdfDrawImageCommand():
      throw const _UnserializableImage();
    case PdfSetBlendModeCommand(:final mode):
      w.u8(_tSetBlendMode);
      w.u8(mode.index);
    case PdfBeginGroupCommand(:final alpha, :final knockout):
      w.u8(_tBeginGroup);
      w.f64(alpha);
      w.boolean(knockout);
    case PdfEndGroupCommand():
      w.u8(_tEndGroup);
    case PdfBeginSoftMaskedCommand():
      w.u8(_tBeginSoftMasked);
    case PdfEndSoftMaskedCommand(
        :final luminosity,
        :final backdrop,
        :final maskCommands,
        :final backdropLuminance,
        :final transferScale,
        :final transferOffset
      ):
      w.u8(_tEndSoftMasked);
      w.boolean(luminosity);
      _writeRect(w, backdrop);
      w.f64(backdropLuminance);
      w.f64(transferScale);
      w.f64(transferOffset);
      _writeCommands(w, maskCommands); // nested
  }
}

PdfRenderCommand _readCommand(_Reader r) {
  final tag = r.u8();
  switch (tag) {
    case _tSave:
      return const PdfSaveCommand();
    case _tRestore:
      return const PdfRestoreCommand();
    case _tFillPath:
      final path = _readPath(r);
      final color = _readColor(r);
      final rule = PdfFillRule.values[r.u8()];
      final alpha = r.f64();
      return PdfFillPathCommand(path, color, rule, alpha);
    case _tFillPathGradient:
      final path = _readPath(r);
      final rule = PdfFillRule.values[r.u8()];
      final gradient = _readGradient(r);
      final alpha = r.f64();
      return PdfFillPathGradientCommand(path, rule, gradient, alpha);
    case _tFillMesh:
      final mesh = _readMesh(r);
      final alpha = r.f64();
      return PdfFillMeshCommand(mesh, alpha);
    case _tStrokePath:
      final path = _readPath(r);
      final color = _readColor(r);
      final stroke = _readStroke(r);
      final alpha = r.f64();
      return PdfStrokePathCommand(path, color, stroke, alpha);
    case _tClipPath:
      final path = _readPath(r);
      final rule = PdfFillRule.values[r.u8()];
      return PdfClipPathCommand(path, rule);
    case _tDrawText:
      return PdfDrawTextCommand(_readTextRun(r));
    case _tSetBlendMode:
      return PdfSetBlendModeCommand(PdfBlendMode.values[r.u8()]);
    case _tBeginGroup:
      final alpha = r.f64();
      final knockout = r.boolean();
      return PdfBeginGroupCommand(alpha, knockout: knockout);
    case _tEndGroup:
      return const PdfEndGroupCommand();
    case _tBeginSoftMasked:
      return const PdfBeginSoftMaskedCommand();
    case _tEndSoftMasked:
      final luminosity = r.boolean();
      final backdrop = _readRect(r);
      final backdropLuminance = r.f64();
      final transferScale = r.f64();
      final transferOffset = r.f64();
      final maskCommands = _readCommands(r);
      return PdfEndSoftMaskedCommand(
        luminosity: luminosity,
        backdrop: backdrop,
        maskCommands: maskCommands,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
      );
    default:
      throw StateError('unknown render command tag $tag');
  }
}

// --- value types ---

void _writePath(_Writer w, PdfPath path) {
  w.u32(path.segments.length);
  for (final s in path.segments) {
    switch (s) {
      case PdfMoveTo(:final x, :final y):
        w.u8(0);
        w.f64(x);
        w.f64(y);
      case PdfLineTo(:final x, :final y):
        w.u8(1);
        w.f64(x);
        w.f64(y);
      case PdfCubicTo(:final x1, :final y1, :final x2, :final y2, :final x3, :final y3):
        w.u8(2);
        w.f64(x1);
        w.f64(y1);
        w.f64(x2);
        w.f64(y2);
        w.f64(x3);
        w.f64(y3);
      case PdfClosePath():
        w.u8(3);
    }
  }
}

PdfPath _readPath(_Reader r) {
  final n = r.u32();
  final segments = <PdfPathSegment>[];
  for (var i = 0; i < n; i++) {
    switch (r.u8()) {
      case 0:
        segments.add(PdfMoveTo(r.f64(), r.f64()));
      case 1:
        segments.add(PdfLineTo(r.f64(), r.f64()));
      case 2:
        segments.add(
            PdfCubicTo(r.f64(), r.f64(), r.f64(), r.f64(), r.f64(), r.f64()));
      case 3:
        segments.add(const PdfClosePath());
    }
  }
  return PdfPath(segments);
}

void _writeColor(_Writer w, PdfColor c) {
  w.f64(c.red);
  w.f64(c.green);
  w.f64(c.blue);
}

PdfColor _readColor(_Reader r) => PdfColor(r.f64(), r.f64(), r.f64());

void _writeStroke(_Writer w, PdfStroke s) {
  w.f64(s.width);
  w.u8(s.cap);
  w.u8(s.join);
  w.f64(s.miterLimit);
  w.f64List(s.dashArray);
  w.f64(s.dashPhase);
}

PdfStroke _readStroke(_Reader r) => PdfStroke(
      width: r.f64(),
      cap: r.u8(),
      join: r.u8(),
      miterLimit: r.f64(),
      dashArray: r.f64List(),
      dashPhase: r.f64(),
    );

void _writeMatrix(_Writer w, PdfMatrix m) {
  w.f64(m.a);
  w.f64(m.b);
  w.f64(m.c);
  w.f64(m.d);
  w.f64(m.e);
  w.f64(m.f);
}

PdfMatrix _readMatrix(_Reader r) =>
    PdfMatrix(r.f64(), r.f64(), r.f64(), r.f64(), r.f64(), r.f64());

void _writeRect(_Writer w, PdfRect rect) {
  w.f64(rect.left);
  w.f64(rect.bottom);
  w.f64(rect.right);
  w.f64(rect.top);
}

PdfRect _readRect(_Reader r) => PdfRect(r.f64(), r.f64(), r.f64(), r.f64());

void _writeGradient(_Writer w, PdfGradient g) {
  w.boolean(g.isRadial);
  w.f64List(g.coords);
  w.u32(g.colors.length);
  for (final c in g.colors) {
    _writeColor(w, c);
  }
  w.f64List(g.stops);
  _writeMatrix(w, g.transform);
  w.boolean(g.extendStart);
  w.boolean(g.extendEnd);
}

PdfGradient _readGradient(_Reader r) {
  final isRadial = r.boolean();
  final coords = r.f64List();
  final n = r.u32();
  final colors = <PdfColor>[for (var i = 0; i < n; i++) _readColor(r)];
  final stops = r.f64List();
  final transform = _readMatrix(r);
  final extendStart = r.boolean();
  final extendEnd = r.boolean();
  return PdfGradient(
    isRadial: isRadial,
    coords: coords,
    colors: colors,
    stops: stops,
    transform: transform,
    extendStart: extendStart,
    extendEnd: extendEnd,
  );
}

void _writeMesh(_Writer w, PdfMesh mesh) {
  w.u32(mesh.vertices.length);
  for (final v in mesh.vertices) {
    w.f64(v.x);
    w.f64(v.y);
    _writeColor(w, v.color);
  }
  w.i32List(mesh.triangles);
}

PdfMesh _readMesh(_Reader r) {
  final n = r.u32();
  final vertices = <PdfMeshVertex>[
    for (var i = 0; i < n; i++)
      PdfMeshVertex(r.f64(), r.f64(), _readColor(r)),
  ];
  final triangles = r.i32List();
  return PdfMesh(vertices, triangles);
}

void _writeTextRun(_Writer w, PdfTextRun run) {
  w.str(run.text);
  _writeMatrix(w, run.transform);
  _writeColor(w, run.color);
  w.f64(run.width);
  // gradient?
  if (run.gradient == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    _writeGradient(w, run.gradient!);
  }
  w.strOpt(run.fontName);
  w.f64(run.fontSize);
  // glyphs?
  final glyphs = run.glyphs;
  if (glyphs == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    w.u32(glyphs.length);
    for (final g in glyphs) {
      w.f64(g.offset);
      w.f64(g.offsetY);
      if (g.outline == null) {
        w.boolean(false);
      } else {
        w.boolean(true);
        _writePath(w, g.outline!);
      }
    }
  }
  w.boolean(run.invisible);
  w.boolean(run.fill);
  if (run.strokeColor == null) {
    w.boolean(false);
  } else {
    w.boolean(true);
    _writeColor(w, run.strokeColor!);
  }
  w.f64(run.strokeWidth);
}

PdfTextRun _readTextRun(_Reader r) {
  final text = r.str();
  final transform = _readMatrix(r);
  final color = _readColor(r);
  final width = r.f64();
  final gradient = r.boolean() ? _readGradient(r) : null;
  final fontName = r.strOpt();
  final fontSize = r.f64();
  List<PdfGlyphPlacement>? glyphs;
  if (r.boolean()) {
    final n = r.u32();
    glyphs = <PdfGlyphPlacement>[];
    for (var i = 0; i < n; i++) {
      final offset = r.f64();
      final offsetY = r.f64();
      final outline = r.boolean() ? _readPath(r) : null;
      glyphs.add(
          PdfGlyphPlacement(offset: offset, offsetY: offsetY, outline: outline));
    }
  }
  final invisible = r.boolean();
  final fill = r.boolean();
  final strokeColor = r.boolean() ? _readColor(r) : null;
  final strokeWidth = r.f64();
  return PdfTextRun(
    text: text,
    transform: transform,
    color: color,
    width: width,
    gradient: gradient,
    fontName: fontName,
    fontSize: fontSize,
    glyphs: glyphs,
    invisible: invisible,
    fill: fill,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
  );
}

// --- low-level reader/writer ---

class _Writer {
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xff);

  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v);
    _b.add(d.buffer.asUint8List());
  }

  void i32(int v) {
    final d = ByteData(4)..setInt32(0, v);
    _b.add(d.buffer.asUint8List());
  }

  void f64(double v) {
    final d = ByteData(8)..setFloat64(0, v);
    _b.add(d.buffer.asUint8List());
  }

  void boolean(bool v) => u8(v ? 1 : 0);

  void str(String s) {
    final bytes = utf8.encode(s);
    u32(bytes.length);
    _b.add(bytes);
  }

  void strOpt(String? s) {
    if (s == null) {
      boolean(false);
    } else {
      boolean(true);
      str(s);
    }
  }

  void f64List(List<double> xs) {
    u32(xs.length);
    for (final x in xs) {
      f64(x);
    }
  }

  void i32List(List<int> xs) {
    u32(xs.length);
    for (final x in xs) {
      i32(x);
    }
  }

  Uint8List takeBytes() => _b.toBytes();
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _o = 0;

  int u8() => _data.getUint8(_o++);

  int u32() {
    final v = _data.getUint32(_o);
    _o += 4;
    return v;
  }

  int i32() {
    final v = _data.getInt32(_o);
    _o += 4;
    return v;
  }

  double f64() {
    final v = _data.getFloat64(_o);
    _o += 8;
    return v;
  }

  bool boolean() => u8() == 1;

  String str() {
    final n = u32();
    final s = utf8.decode(Uint8List.sublistView(_bytes, _o, _o + n));
    _o += n;
    return s;
  }

  String? strOpt() => boolean() ? str() : null;

  List<double> f64List() {
    final n = u32();
    return <double>[for (var i = 0; i < n; i++) f64()];
  }

  List<int> i32List() {
    final n = u32();
    return <int>[for (var i = 0; i < n; i++) i32()];
  }
}

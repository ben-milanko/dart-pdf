import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'device.dart';
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';

/// Forwards every [PdfDevice] call to [target] with all page-space geometry
/// translated by ([dx], [dy]).
///
/// This is the replay half of record-once/replay-per-tile (#524): a tiling
/// pattern's cell is interpreted once into a command list, and each tile
/// replays those commands through one of these wrappers instead of
/// re-interpreting the cell content. It works because everything crossing
/// the device boundary is already in page space with the CTM baked in, and
/// a pattern-space step maps through the (affine) pattern matrix to a pure
/// page-space translation per tile.
///
/// Only geometry translates: paths, the [PdfTextRun]/[PdfImageRequest]/
/// [PdfGradient] transforms, mesh vertices, and the soft-mask backdrop box.
/// State calls (blend mode, overprint, groups) pass through untouched.
/// Stroke widths, dash patterns, and alphas are translation-invariant.
class TranslatingPdfDevice implements PdfDevice {
  TranslatingPdfDevice(this.target, this.dx, this.dy);

  final PdfDevice target;
  final double dx;
  final double dy;

  PdfPath _path(PdfPath path) => PdfPath([
        for (final s in path.segments)
          switch (s) {
            PdfMoveTo() => PdfMoveTo(s.x + dx, s.y + dy),
            PdfLineTo() => PdfLineTo(s.x + dx, s.y + dy),
            PdfCubicTo() => PdfCubicTo(s.x1 + dx, s.y1 + dy, s.x2 + dx,
                s.y2 + dy, s.x3 + dx, s.y3 + dy),
            PdfClosePath() => s,
          },
      ]);

  PdfMatrix _matrix(PdfMatrix m) =>
      PdfMatrix(m.a, m.b, m.c, m.d, m.e + dx, m.f + dy);

  PdfGradient _gradient(PdfGradient g) => PdfGradient(
        isRadial: g.isRadial,
        coords: g.coords,
        colors: g.colors,
        stops: g.stops,
        transform: _matrix(g.transform),
        extendStart: g.extendStart,
        extendEnd: g.extendEnd,
      );

  @override
  void save() => target.save();

  @override
  void restore() => target.restore();

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) =>
      target.fillPath(_path(path), color, rule, alpha);

  @override
  void fillPathGradient(
          PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) =>
      target.fillPathGradient(_path(path), rule, _gradient(gradient), alpha);

  @override
  void fillMesh(PdfMesh mesh, double alpha) => target.fillMesh(
      PdfMesh([
        for (final v in mesh.vertices)
          PdfMeshVertex(v.x + dx, v.y + dy, v.color),
      ], mesh.triangles),
      alpha);

  @override
  void strokePath(
          PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      target.strokePath(_path(path), color, stroke, alpha);

  @override
  void clipPath(PdfPath path, PdfFillRule rule) =>
      target.clipPath(_path(path), rule);

  @override
  void drawText(PdfTextRun run) => target.drawText(PdfTextRun(
        text: run.text,
        transform: _matrix(run.transform),
        color: run.color,
        width: run.width,
        gradient: run.gradient == null ? null : _gradient(run.gradient!),
        fontName: run.fontName,
        fontSize: run.fontSize,
        glyphs: run.glyphs,
        invisible: run.invisible,
        fill: run.fill,
        strokeColor: run.strokeColor,
        strokeWidth: run.strokeWidth,
        fillAlpha: run.fillAlpha,
        strokeAlpha: run.strokeAlpha,
        mcid: run.mcid,
        // Em-space, so a page-space translation leaves them alone - but they
        // still have to be carried, or a tiled cell's substituted text loses
        // its spacing and its per-character placement (#649).
        letterSpacing: run.letterSpacing,
        wordSpacing: run.wordSpacing,
        leadingSpace: run.leadingSpace,
        visibleWidth: run.visibleWidth,
        charOffsets: run.charOffsets,
      ));

  @override
  void drawImage(PdfImageRequest request) =>
      target.drawImage(request.withTransform(_matrix(request.transform)));

  @override
  void setBlendMode(PdfBlendMode mode) => target.setBlendMode(mode);

  @override
  void setOverprint(
          {required bool fill, required bool stroke, required int mode}) =>
      target.setOverprint(fill: fill, stroke: stroke, mode: mode);

  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      target.beginGroup(alpha, knockout: knockout);

  @override
  void endGroup() => target.endGroup();

  @override
  void beginSoftMasked() => target.beginSoftMasked();

  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) =>
      target.endSoftMasked(
        luminosity: luminosity,
        backdrop: PdfRect(backdrop.left + dx, backdrop.bottom + dy,
            backdrop.right + dx, backdrop.top + dy),
        drawMask: drawMask,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
      );
}

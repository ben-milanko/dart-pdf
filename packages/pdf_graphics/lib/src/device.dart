import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'matrix.dart';
import 'mesh.dart';
import 'path.dart';
import 'shading.dart';

/// PDF blend modes (§11.3.5). Devices map these to their compositor.
enum PdfBlendMode {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  hue,
  saturation,
  color,
  luminosity,
}

/// One glyph within a [PdfTextRun]: its outline (when the font is embedded
/// and parsed) and its pen offset, both in em units.
class PdfGlyphPlacement {
  const PdfGlyphPlacement({required this.offset, this.outline});

  /// Horizontal pen position within the run, in em units.
  final double offset;

  /// Glyph outline in em units (y-up, origin on the baseline), or null when
  /// the glyph is blank or its outline could not be parsed.
  final PdfPath? outline;
}

/// One run of text from a single show-text operator.
class PdfTextRun {
  const PdfTextRun({
    required this.text,
    required this.transform,
    required this.color,
    required this.width,
    this.gradient,
    this.fontName,
    this.fontSize = 0,
    this.glyphs,
    this.invisible = false,
  });

  /// Render mode 3 (§9.4.3): the run paints nothing but still occupies
  /// its geometry — the OCR text layer of scanned documents. Painting
  /// devices must skip it; text extraction wants it like any other run.
  final bool invisible;

  /// Best-effort Unicode (via ToUnicode CMaps or the font's encoding).
  final String text;

  /// Maps em-space (origin at the baseline start, 1.0 = the font size) to
  /// page space. Includes font size, horizontal scaling, and rise.
  final PdfMatrix transform;

  final PdfColor color;

  /// Shading-pattern fill for this run, already resolved into page space.
  ///
  /// When present, painting devices should use this instead of [color] for
  /// the filled glyph shape. Non-painting consumers can ignore it.
  final PdfGradient? gradient;

  /// Advance width in em units, from the PDF's font metrics. Devices should
  /// scale their substituted font's output to match, so columns line up.
  final double width;

  /// The /BaseFont name, e.g. `ABCDEF+Helvetica-Bold`.
  final String? fontName;

  /// Nominal font size before transformation, for font selection heuristics.
  final double fontSize;

  /// Real glyph outlines from the embedded font, when available. Devices
  /// should prefer these over substituted text rendering.
  final List<PdfGlyphPlacement>? glyphs;

  bool get hasOutlines =>
      glyphs != null && glyphs!.any((g) => g.outline != null);
}

/// An image draw request. Decoding is left to the device, which may have
/// platform codecs (and may need to be async — devices can pre-collect).
class PdfImageRequest {
  const PdfImageRequest({
    required this.stream,
    required this.transform,
    this.alpha = 1,
    this.isStencil = false,
    this.stencilColor = PdfColor.black,
    this.isInline = false,
  });

  final CosStream stream;

  /// True for inline images (`BI .. ID .. EI`). Their [stream] is
  /// synthesized fresh on every interpretation pass, so consumers that
  /// cache decoded pixels must key them by value, not stream identity.
  final bool isInline;

  /// Maps the unit square (image space, y-up) to page space.
  final PdfMatrix transform;

  final double alpha;

  /// True for /ImageMask stencils, which paint [stencilColor] through the
  /// mask instead of carrying their own colors (§8.9.6.2).
  final bool isStencil;

  /// The fill color in effect when a stencil mask is drawn.
  final PdfColor stencilColor;
}

/// Rendering target. The interpreter walks a content stream and emits these
/// callbacks; implementations include the Flutter Canvas device, a
/// text-extraction device, and test recorders.
abstract interface class PdfDevice {
  /// Mirrors `q`. Saved state must include the clip.
  void save();

  /// Mirrors `Q`.
  void restore();

  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha);

  /// Fills with a gradient (axial/radial shading patterns and `sh`).
  /// Non-painting devices can ignore it; simple devices may fall back to
  /// `fillPath` with [PdfGradient.averageColor].
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha);

  /// Paints a Gouraud triangle mesh (mesh shadings, types 4–7). Vertices
  /// arrive in page space. Non-painting devices can ignore it; simple
  /// devices may fall back to [PdfMesh.averageColor].
  void fillMesh(PdfMesh mesh, double alpha);

  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double alpha);

  /// Intersects the current clip with [path].
  void clipPath(PdfPath path, PdfFillRule rule);

  void drawText(PdfTextRun run);

  void drawImage(PdfImageRequest request);

  /// Sets the blend mode for subsequent painting (gs /BM). Non-compositing
  /// devices can ignore it.
  void setBlendMode(PdfBlendMode mode);

  /// Brackets a transparency-group form (§11.6.6) whose composite result
  /// paints at [alpha]. Inside the group, alpha starts over at 1.0; the
  /// group then blends as one object. Non-compositing devices can treat
  /// the pair as a no-op — the group's content still arrives through the
  /// normal callbacks in between.
  ///
  /// When [knockout] is true the group is a knockout group (/K true,
  /// §11.4.5): each top-level element composites with the group's initial
  /// (transparent) backdrop rather than with the elements painted before
  /// it, so a later element replaces an earlier one wherever they overlap
  /// instead of blending over it.
  void beginGroup(double alpha, {bool knockout = false});

  /// Composites the group opened by [beginGroup].
  void endGroup();

  /// Starts capturing painted content that an ExtGState /SMask will mask.
  /// Visual devices open an offscreen layer; others can ignore the pair.
  void beginSoftMasked();

  /// Ends the capture opened by [beginSoftMasked]. [drawMask] paints the
  /// mask group's content through this same device; for luminosity masks
  /// the device converts the result's luminance to alpha over the
  /// [backdrop] box, then composites it into the captured content (dstIn).
  /// Areas the mask group doesn't paint take [backdropLuminance] (the
  /// luminance of the /BC backdrop colour, default black). The mask value
  /// is remapped through the /TR transfer function, linearised here as
  /// `value * transferScale + transferOffset` (identity by default).
  /// Devices that collect content from [drawMask] (e.g. image collectors)
  /// should invoke it even if they do no compositing.
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  });
}

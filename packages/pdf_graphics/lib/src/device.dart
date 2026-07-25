import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'color.dart';
import 'image_pixels.dart';
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
  const PdfGlyphPlacement({
    required this.offset,
    this.offsetY = 0,
    this.outline,
    this.text,
  });

  /// Horizontal pen position within the run, in em units.
  final double offset;

  /// Vertical pen position within the run, in em units. Non-zero only for
  /// vertical writing mode (§9.7.4.3), where glyphs stack downward and each
  /// carries a position-vector offset; 0 for ordinary horizontal text.
  final double offsetY;

  /// Glyph outline in em units (y-up, origin on the baseline), or null when
  /// the glyph is blank or its outline could not be parsed.
  final PdfPath? outline;

  /// Best-effort Unicode mapped from this one PDF character code. A glyph can
  /// map to multiple logical characters through /ToUnicode (for example an
  /// Arabic ligature), so text extraction must preserve this boundary while
  /// converting visual glyph order back to logical order.
  final String? text;
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
    this.fill = true,
    this.strokeColor,
    this.strokeWidth = 0,
    this.letterSpacing = 0,
    this.wordSpacing = 0,
    this.visibleWidth,
    this.leadingSpace = 0,
    this.mcid,
  });

  /// The marked-content id (/MCID) of the innermost tagged marked-content
  /// sequence enclosing this run, or null when the run is untagged. In a
  /// Tagged PDF this ties the run to a structure element (§14.7).
  final int? mcid;

  /// Whether the glyphs are filled (text rendering modes 0/2/4/6). False for
  /// stroke-only modes (1/5) and when a fill that can't be represented (an
  /// unrenderable tiling-pattern fill on a substituted font) is dropped in
  /// favour of the stroke. [color]/[gradient] describe the fill.
  final bool fill;

  /// Stroke colour for text rendering modes that stroke the glyph outline
  /// (1 stroke, 2 fill+stroke, 5/6 the same plus clip); null when the mode
  /// doesn't stroke. Painting devices outline the glyphs in this colour.
  final PdfColor? strokeColor;

  /// Stroke line width in page space (the current line width mapped through
  /// the CTM, like every other stroke); 0 means the thinnest renderable line.
  final double strokeWidth;

  /// Render mode 3 (§9.4.3): the run paints nothing but still occupies
  /// its geometry - the OCR text layer of scanned documents. Painting
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
  /// scale their substituted font's output to match, so columns line up. This
  /// total already includes the character/word spacing described by
  /// [letterSpacing]/[wordSpacing].
  final double width;

  /// Character spacing (Tc, §9.3.2) in em units - the extra advance added after
  /// every glyph. A device substituting a system font should reproduce it as
  /// real tracking so the substitute's own advances match [width] instead of
  /// stretching the glyph shapes to fill it.
  final double letterSpacing;

  /// Word spacing (Tw, §9.3.3) in em units - the extra advance added after each
  /// single-byte space (code 32) on a simple font; 0 for composite (CID) fonts,
  /// which Tw never touches. Like [letterSpacing], a substituting device should
  /// apply it as real spacing so a space carrying a large Tw opens a genuine gap
  /// rather than stretching the surrounding glyphs across it.
  final double wordSpacing;

  /// Advance in em units up to the end of the last non-whitespace glyph -
  /// [width] minus any trailing-whitespace advance. Null means "same as
  /// [width]" (no trailing whitespace, or the emitter didn't distinguish).
  ///
  /// A substituting device stretches its system font to a target width to make
  /// advances line up; that target must be this visible width, because the
  /// layout engines it measures against (e.g. Flutter's [TextPainter]) drop
  /// trailing whitespace from their reported width. Using [width] there would
  /// stretch the visible glyphs to swallow a trailing space's advance - which a
  /// large Tw makes enormous. [width] itself stays whitespace-inclusive so text
  /// extraction still sees the true inter-run gap.
  final double? visibleWidth;

  /// Advance in em units from the run origin to the start of the first
  /// non-whitespace glyph - the leading-whitespace advance (a leading space
  /// carrying a large Tw is a common way tabular content reaches its column).
  /// A substituting device draws its trimmed text shifted right by this much,
  /// because the layout engines it measures against also drop leading
  /// whitespace and would otherwise place the first visible glyph at the origin.
  /// [transform] itself keeps the untrimmed origin, so extraction is unaffected.
  final double leadingSpace;

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
/// platform codecs (and may need to be async - devices can pre-collect).
class PdfImageRequest {
  const PdfImageRequest({
    required this.stream,
    required this.transform,
    this.alpha = 1,
    this.isStencil = false,
    this.stencilColor = PdfColor.black,
    this.isInline = false,
    this.decoded,
  });

  final CosStream stream;

  /// Premultiplied RGBA pixels decoded off-thread by a [PdfRenderWorker] and
  /// carried back with the recorded command, or null when this image is to be
  /// decoded locally (every non-worker render path). When present the
  /// consumer hands these straight to the engine codec instead of running the
  /// pure-Dart decode - the point of the worker's image-decode offload. The
  /// [stream] is still serialized so the decoded pixels cache by content like
  /// every other render path.
  final PdfDecodedPixels? decoded;

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

  /// Sets the overprint state for subsequent painting (gs /OP, /op, /OPM;
  /// PDF §8.6.7). [fill] is nonstroking overprint (/op), [stroke] is stroking
  /// overprint (/OP), and [mode] is the overprint mode (/OPM, 0 or 1).
  ///
  /// Overprint is a subtractive (CMYK/spot colorant) operation: an
  /// overprinting colorant that is not written leaves the underlying colorant
  /// untouched instead of knocking it out. A faithful reproduction needs a
  /// CMYK/spot colorant buffer this RGB compositor does not have; painting
  /// devices approximate the common case (a neutral/dark ink over a coloured
  /// backdrop) with a `darken` (per-channel min) composite while the flag is
  /// set - over a white backdrop that is a no-op, so it only affects ink laid
  /// over ink (issue #502). [mode] is threaded for a future colorant-buffer
  /// path; the RGB approximation cannot act on the OPM-0/1 zero-component
  /// distinction. Non-compositing devices can ignore all three.
  void setOverprint({required bool fill, required bool stroke, required int mode});

  /// Brackets a transparency-group form (§11.6.6) whose composite result
  /// paints at [alpha]. Inside the group, alpha starts over at 1.0; the
  /// group then blends as one object. Non-compositing devices can treat
  /// the pair as a no-op - the group's content still arrives through the
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

import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'color.dart';
import 'icc.dart';

/// Document-level colour conversion state used while rendering PDF device
/// colours.
///
/// A PDF/X output intent describes the process colour space the untagged
/// DeviceCMYK (and K-only DeviceGray) values on the page belong to. Treating
/// those values as a fixed generic CMYK approximation makes an ICCBased object
/// and a DeviceCMYK object that describe the same press colour render
/// differently. The Ghent output-suite source-profile, output-intent and
/// equivalent-gray patches are deliberately constructed around that error.
///
/// This context resolves the first usable `/DestOutputProfile` once per COS
/// revision and uses its device-to-PCS transform for display. Documents with
/// no usable output intent retain the historical device conversions.
class PdfColorContext {
  PdfColorContext._(this.outputProfile);

  /// The document's PDF/X/PDF/A destination profile, when supported.
  final IccProfile? outputProfile;

  final Map<(PdfColor, PdfRenderingIntent), List<double>> _outputCmykCache = {};

  /// Resolves the colour context for [cos]. The cache is revision-aware so an
  /// editor that replaces `/OutputIntents` cannot retain the prior profile.
  static PdfColorContext forDocument(CosDocument cos) {
    final cached = _contexts[cos];
    if (cached != null && cached.revision == cos.revision) {
      return cached.context;
    }
    final context = PdfColorContext._(_outputProfile(cos));
    _contexts[cos] = (revision: cos.revision, context: context);
    return context;
  }

  static final Expando<({int revision, PdfColorContext context})> _contexts =
      Expando<({int revision, PdfColorContext context})>('pdfColorContext');

  /// Converts an untagged process colour through the output condition.
  ///
  /// [intent] is accepted so callers can share their CIE/device conversion
  /// plumbing, but deliberately does not select another output-profile table
  /// here. PDF rendering intent governs conversion *from a CIE-based colour
  /// space*; DeviceCMYK already controls the native process components
  /// directly (PDF 32000-1 §10.3). The colorimetric A2B table is therefore the
  /// stable characterization used to preview those components.
  PdfColor deviceCmyk(double cyan, double magenta, double yellow, double black,
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final profile = outputProfile;
    if (profile != null && profile.channels == 4) {
      return profile.toSrgb([
        cyan.clamp(0.0, 1.0).toDouble(),
        magenta.clamp(0.0, 1.0).toDouble(),
        yellow.clamp(0.0, 1.0).toDouble(),
        black.clamp(0.0, 1.0).toDouble(),
      ], intent: PdfRenderingIntent.relativeColorimetric);
    }
    return PdfColor.cmyk(cyan, magenta, yellow, black);
  }

  /// Converts DeviceGray through the K channel of a CMYK output condition.
  /// PDF gray is additive (0 = black, 1 = white), hence `K = 1 - gray`.
  PdfColor deviceGray(double gray,
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final value = gray.clamp(0.0, 1.0).toDouble();
    final profile = outputProfile;
    if (profile != null && profile.channels == 4) {
      return profile.toSrgb([0, 0, 0, 1 - value],
          intent: PdfRenderingIntent.relativeColorimetric);
    }
    if (profile != null && profile.channels == 1) {
      return profile
          .toSrgb([value], intent: PdfRenderingIntent.relativeColorimetric);
    }
    return PdfColor.gray(value);
  }

  /// Finds the destination-process CMYK that renders closest to [color]
  /// through the document's output profile.
  ///
  /// PDF transparency groups may declare DeviceCMYK as their blending colour
  /// space while their source objects are ICCBased RGB/CMYK. Those source
  /// colours must be converted into the group space *before* blend functions
  /// run. ICC A2B profiles provide the forward transform used for display;
  /// this bounded coordinate search supplies its practical inverse for the
  /// handful of vector colours a page selects. Results are cached per exact
  /// source colour, so repeated paths pay nothing after the first conversion.
  List<double>? outputCmyk(PdfColor color,
      {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) {
    final profile = outputProfile;
    if (profile == null || profile.channels != 4) return null;
    final key = (color, intent);
    final cached = _outputCmykCache[key];
    if (cached != null) return cached;

    double error(List<double> value) {
      final rendered = profile.toSrgb(value, intent: intent);
      final dr = rendered.red - color.red;
      final dg = rendered.green - color.green;
      final db = rendered.blue - color.blue;
      return dr * dr + dg * dg + db * db;
    }

    final k = (1 - math.max(color.red, math.max(color.green, color.blue)))
        .clamp(0.0, 1.0)
        .toDouble();
    List<double> naive() => k >= 1
        ? [0, 0, 0, 1]
        : [
            ((1 - color.red - k) / (1 - k)).clamp(0.0, 1.0).toDouble(),
            ((1 - color.green - k) / (1 - k)).clamp(0.0, 1.0).toDouble(),
            ((1 - color.blue - k) / (1 - k)).clamp(0.0, 1.0).toDouble(),
            k,
          ];
    final starts = <List<double>>[
      naive(),
      [1 - color.red, 1 - color.green, 1 - color.blue, 0],
      [
        0,
        0,
        0,
        1 - (0.3 * color.red + 0.59 * color.green + 0.11 * color.blue),
      ],
    ];
    var best = starts.first;
    var bestError = error(best);
    for (final start in starts.skip(1)) {
      final candidateError = error(start);
      if (candidateError < bestError) {
        best = start;
        bestError = candidateError;
      }
    }
    best = [...best];
    for (final step in const [0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625]) {
      var improved = true;
      while (improved) {
        improved = false;
        for (var channel = 0; channel < 4; channel++) {
          for (final direction in const [-1.0, 1.0]) {
            final candidate = [...best];
            candidate[channel] =
                (candidate[channel] + direction * step).clamp(0.0, 1.0);
            final candidateError = error(candidate);
            if (candidateError + 1e-12 < bestError) {
              best = candidate;
              bestError = candidateError;
              improved = true;
            }
          }
        }
      }
    }
    final result = List<double>.unmodifiable(best);
    _outputCmykCache[key] = result;
    return result;
  }

  /// Converts an ICC source colour directly through the profile-connection
  /// space into the output-condition CMYK, honoring [intent].
  List<double>? iccToOutputCmyk(IccProfile source, List<double> values,
      {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) {
    final destination = outputProfile;
    if (destination == null || destination.channels != 4) return null;
    var pcs = source.toPcs(values, intent: intent);
    if (intent == PdfRenderingIntent.relativeColorimetric) {
      pcs = _blackPointCompensatedPcs(source, destination, pcs);
    }
    final direct = destination.fromPcs(pcs, intent: intent);
    if (direct != null && direct.length >= 4) return direct;
    return outputCmyk(source.toSrgb(values, intent: intent), intent: intent);
  }

  /// Maps the source black/white interval onto the destination interval in
  /// XYZ PCS, the ICC black-point-compensation affine. Relative colorimetric
  /// otherwise maps paper white but leaves a zero source black below the
  /// printable black of a press profile. That mismatch is deliberately made
  /// visible by GWG172 and the four-gray/BPC family.
  static List<double> _blackPointCompensatedPcs(
      IccProfile source, IccProfile destination, List<double> pcs) {
    if (identical(source, destination)) return pcs;
    return _compensateBlackPoints(
        source.sourceBlackPoint(), destination.destinationBlackPoint(), pcs);
  }

  static List<double> _compensateBlackPoints(List<double> sourceBlack,
      List<double> destinationBlack, List<double> pcs) {
    const d50 = [0.9642, 1.0, 0.8249];
    return [
      for (var i = 0; i < 3; i++)
        d50[i] == sourceBlack[i]
            ? pcs[i]
            : destinationBlack[i] +
                (pcs[i] - sourceBlack[i]) *
                    (d50[i] - destinationBlack[i]) /
                    (d50[i] - sourceBlack[i]),
    ];
  }

  /// Colour-manages an ICC source through the document's output condition.
  ///
  /// A source profile's A2B transform alone only reaches the PCS. For PDF/X,
  /// that PCS colour must then pass through the output profile's B2A table
  /// under the selected rendering intent before being previewed. Skipping the
  /// destination leg makes equivalent tagged and DeviceCMYK greens visibly
  /// different (the faint/solid fail markers in GWG130).
  PdfColor iccToSrgb(IccProfile source, List<double> values,
      {PdfRenderingIntent intent = PdfRenderingIntent.perceptual}) {
    final destination = outputProfile;
    if (destination == null || destination.channels != 4) {
      return source.toSrgb(values, intent: intent);
    }
    final cmyk = iccToOutputCmyk(source, values, intent: intent);
    return cmyk == null
        ? source.toSrgb(values, intent: intent)
        : destination.toSrgb(cmyk,
            intent: PdfRenderingIntent.relativeColorimetric);
  }

  /// Converts a D50-adapted CIE PCS colour through the PDF/X output
  /// condition. CalGray, CalRGB and Lab are source colour spaces just like
  /// ICCBased; previewing their sRGB approximation directly bypasses the
  /// OutputIntent and reveals GWG221's change indicator.
  PdfColor pcsToSrgb(List<double> pcs, PdfColor fallback,
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final destination = outputProfile;
    if (destination == null || destination.channels != 4) return fallback;
    final cmyk = pcsToOutputCmyk(pcs, fallback, intent: intent);
    return cmyk == null
        ? fallback
        : destination.toSrgb(cmyk,
            intent: PdfRenderingIntent.relativeColorimetric);
  }

  /// [pcsToSrgb]'s destination-device leg, used as the process-color reading
  /// of a calibrated source inside a DeviceCMYK transparency group.
  List<double>? pcsToOutputCmyk(List<double> pcs, PdfColor fallback,
      {PdfRenderingIntent intent = PdfRenderingIntent.relativeColorimetric}) {
    final destination = outputProfile;
    if (destination == null || destination.channels != 4) return null;
    var managedPcs = pcs;
    if (intent == PdfRenderingIntent.relativeColorimetric) {
      managedPcs = _compensateBlackPoints(
          const [0.0, 0.0, 0.0], destination.destinationBlackPoint(), pcs);
    }
    final direct = destination.fromPcs(managedPcs, intent: intent);
    return direct ?? outputCmyk(fallback, intent: intent);
  }

  static IccProfile? _outputProfile(CosDocument cos) {
    final intents = cos.resolve(cos.catalog['OutputIntents']);
    if (intents is! CosArray) return null;
    for (final item in intents.items) {
      final intent = cos.resolve(item);
      if (intent is! CosDictionary) continue;
      final stream = cos.resolve(intent['DestOutputProfile']);
      if (stream is! CosStream) continue;
      try {
        final profile = IccProfile.parse(cos.decodeStreamData(stream));
        if (profile != null) return profile;
      } on Exception {
        // A broken first intent must not hide a later usable one.
      }
    }
    return null;
  }
}

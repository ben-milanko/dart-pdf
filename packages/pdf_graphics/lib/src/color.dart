/// Interprets raw color components by count: 1 = gray, 3 = RGB, 4 = CMYK.
/// Used for sc/scn operands and shading function outputs.
PdfColor colorFromComponents(List<double> values, [int? count]) {
  final n = count ?? values.length;
  double at(int i) => i < values.length ? values[i].clamp(0, 1).toDouble() : 0;
  return switch (n) {
    1 => PdfColor.gray(at(0)),
    4 => PdfColor.cmyk(at(0), at(1), at(2), at(3)),
    _ => PdfColor(at(0), at(1), at(2)),
  };
}

/// An RGB color with components in 0..1, the renderer's common currency.
/// Device color spaces convert into it; ICC-based spaces approximate for now.
class PdfColor {
  const PdfColor(this.red, this.green, this.blue);

  const PdfColor.gray(double level) : this(level, level, level);

  /// DeviceCMYK → sRGB via the same SWOP-class polynomial pdf.js uses
  /// (`DeviceCmykCS`, a least-squares fit to a US Web Coated profile).
  /// Each output channel is a quadratic in (c, m, y, k); this matches
  /// pdf.js's rendering of process CMYK far more closely than a halftone
  /// or complement model — e.g. `0 0 0 0.89 k` → RGB(69,71,77), not the
  /// halftone (28,28,28). Adopted so corpus/print colour matches the
  /// reference renderer across the board.
  factory PdfColor.cmyk(double cyan, double magenta, double yellow,
      double black) {
    final c = cyan.clamp(0.0, 1.0).toDouble();
    final m = magenta.clamp(0.0, 1.0).toDouble();
    final y = yellow.clamp(0.0, 1.0).toDouble();
    final k = black.clamp(0.0, 1.0).toDouble();

    final r = 255 +
        c * (-4.387332384609988 * c +
            54.48615194189176 * m +
            18.82290502165302 * y +
            212.25662451639585 * k +
            -285.2331026137004) +
        m * (1.7149763477362134 * m +
            -5.6096736904047315 * y +
            -17.873870861415444 * k +
            -5.497006427196366) +
        y * (-2.5217340131683033 * y +
            -21.248923337353073 * k +
            17.5119270841813) +
        k * (-21.86122147463605 * k + -189.48180835922747);

    final g = 255 +
        c * (8.841041422036149 * c +
            60.118027045597366 * m +
            6.871425592049007 * y +
            31.159100130055922 * k +
            -79.2970844816548) +
        m * (-15.310361306967817 * m +
            17.575251261109482 * y +
            131.35250912493976 * k +
            -190.9453302588951) +
        y * (4.444339102852739 * y +
            9.8632861493405 * k +
            -24.86741582555878) +
        k * (-20.737325471181034 * k + -187.80453709719578);

    final b = 255 +
        c * (0.8842522430003296 * c +
            8.078677503112928 * m +
            30.89978309703729 * y +
            -0.23883238689178934 * k +
            -14.183576799673286) +
        m * (10.49593273432072 * m +
            63.02378494754052 * y +
            50.606957656360734 * k +
            -112.23884253719248) +
        y * (0.03296041114873217 * y +
            115.60384449646641 * k +
            -193.58209356861505) +
        k * (-22.33816807309886 * k + -180.12613974708367);

    return PdfColor(
      (r / 255).clamp(0.0, 1.0).toDouble(),
      (g / 255).clamp(0.0, 1.0).toDouble(),
      (b / 255).clamp(0.0, 1.0).toDouble(),
    );
  }

  static const PdfColor black = PdfColor(0, 0, 0);

  final double red;
  final double green;
  final double blue;

  @override
  bool operator ==(Object other) =>
      other is PdfColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'PdfColor($red, $green, $blue)';
}

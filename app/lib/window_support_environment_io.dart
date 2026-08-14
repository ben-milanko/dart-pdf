import 'dart:io';

/// Whether this process explicitly opted into DartPDF's experimental
/// multi-window bootstrap.
///
/// Flutter's own `FLUTTER_WINDOWING` flag controls the framework feature. This
/// separate app flag keeps production builds on the normal runner even if a
/// developer has enabled Flutter's global windowing config locally.
bool get dartPdfWindowingRequested {
  final value = Platform.environment['DARTPDF_EXPERIMENTAL_WINDOWING'];
  return value == '1' || value?.toLowerCase() == 'true';
}

/// CPU sparse-strip rasterization core (vello_hybrid-style): adaptive path
/// flattening, stroke-to-contour expansion, and 4-px strip generation with
/// a column-major RGBA8888 alpha atlas.
///
/// Pure Dart - runs on the VM, on the web, and in worker isolates.
/// Deliberately NOT exported from the main pdf_graphics barrel: this is the
/// substrate for the experimental shader-driven renderers (Track A/B/C),
/// not part of the stable device API.
library;

export 'src/raster/flatten.dart';
export 'src/raster/stroke_contours.dart';
export 'src/raster/strip_generator.dart';

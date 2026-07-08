/// Experimental flutter_gpu render backend.
///
/// Renders pages through Flutter GPU (Impeller's low-level API) instead of
/// recording ui.Canvas pictures - an experiment measuring what a
/// direct-to-GPU rasterizer buys over the Skia/Impeller display-list path.
/// Requires Impeller plus the Flutter GPU manifest flag (`flutter test
/// --enable-impeller --enable-flutter-gpu`, or the FLTEnableFlutterGPU /
/// EnableFlutterGPU platform manifest keys).
///
/// Not part of the supported API surface; see GpuPdfDevice's doc comment
/// for the current fidelity gaps.
library;

export 'src/gpu/gpu_device.dart' show GpuPdfDevice, PdfGpuPipelines;
export 'src/gpu/gpu_geometry.dart';
export 'src/gpu/gpu_renderer.dart';

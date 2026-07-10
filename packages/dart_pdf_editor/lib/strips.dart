/// Sparse-strip shader rendering: [StripPdfDevice] batches solid fills,
/// strokes, and outline text into drawVertices + FragmentShader draws;
/// everything else delegates to the canvas device in painter's order.
/// Not exported from the main dart_pdf_editor barrel - the device wins on
/// GPU backends (Impeller) but loses on software Skia; PdfPageView's zoom
/// router uses it automatically behind a runtime Impeller gate
/// (ui.ImageFilter.isShaderFilterSupported), so hosts only import this for
/// direct/off-label use.
library;

export 'src/strips/strip_batch.dart';
export 'src/strips/strip_device.dart';

/// Sparse-strip shader rendering: [StripPdfDevice] batches solid fills,
/// strokes, and outline text into drawVertices + FragmentShader draws;
/// everything else delegates to the canvas device in painter's order.
/// Not exported from the main dart_pdf_editor barrel - the device wins on
/// GPU backends (Impeller) but loses on software Skia, so hosts opt in.
library;

export 'src/strips/strip_batch.dart';
export 'src/strips/strip_device.dart';

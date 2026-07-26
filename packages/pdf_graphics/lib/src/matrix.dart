// PdfMatrix now lives in pdf_cos so the lower layers (COS geometry, the
// page/annotation model) can share the same affine value type. Re-exported
// here to keep pdf_graphics' public API and internal imports unchanged.
export 'package:pdf_cos/pdf_cos.dart' show PdfMatrix;

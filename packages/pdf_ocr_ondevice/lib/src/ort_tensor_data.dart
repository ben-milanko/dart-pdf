import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// The package exposes tensor data only as nested `List<double>`s
// (`OrtValueTensor.value`); its generated C-API bindings are the only route
// to the buffer itself.
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as ort;

import 'pp_ocr_pipeline.dart' show OcrTensor;

/// Reads a float32 output tensor straight out of ONNX Runtime's buffer - one
/// copy into a [Float32List], or null when [value] is not a float32 tensor
/// (the caller falls back to `OrtValueTensor.value`).
///
/// This is the difference between seconds and minutes per page:
/// `OrtValueTensor.value` builds a nested `List` of boxed doubles, and a
/// PP-OCR recognition output is `[1, T, 18385]` - over a million boxed
/// numbers per text line, which cost ~3x the inference itself.
OcrTensor? readFloatTensor(OrtValue value) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final ptr = value.ptr;
  return using((arena) {
    final infoOut = arena<ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>>();
    OrtStatus.checkOrtStatus(api.GetTensorTypeAndShape.asFunction<
            ort.OrtStatusPtr Function(ffi.Pointer<ort.OrtValue>,
                ffi.Pointer<ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>>)>()(
        ptr, infoOut));
    final info = infoOut.value;
    final List<int> shape;
    try {
      final type = arena<ffi.Int32>();
      OrtStatus.checkOrtStatus(api.GetTensorElementType.asFunction<
          ort.OrtStatusPtr Function(ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>,
              ffi.Pointer<ffi.Int32>)>()(info, type));
      if (type.value !=
          ort.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        return null;
      }
      final rank = arena<ffi.Size>();
      OrtStatus.checkOrtStatus(api.GetDimensionsCount.asFunction<
          ort.OrtStatusPtr Function(ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>,
              ffi.Pointer<ffi.Size>)>()(info, rank));
      final dims = arena<ffi.Int64>(rank.value);
      OrtStatus.checkOrtStatus(api.GetDimensions.asFunction<
          ort.OrtStatusPtr Function(ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>,
              ffi.Pointer<ffi.Int64>, int)>()(info, dims, rank.value));
      shape = [for (var i = 0; i < rank.value; i++) dims[i]];
    } finally {
      api.ReleaseTensorTypeAndShapeInfo.asFunction<
          void Function(ffi.Pointer<ort.OrtTensorTypeAndShapeInfo>)>()(info);
    }
    var count = 1;
    for (final d in shape) {
      count *= d;
    }
    final dataOut = arena<ffi.Pointer<ffi.Void>>();
    OrtStatus.checkOrtStatus(api.GetTensorMutableData.asFunction<
        ort.OrtStatusPtr Function(ffi.Pointer<ort.OrtValue>,
            ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(ptr, dataOut));
    final data = Float32List.fromList(
        dataOut.value.cast<ffi.Float>().asTypedList(count));
    return (data: data, shape: shape);
  });
}

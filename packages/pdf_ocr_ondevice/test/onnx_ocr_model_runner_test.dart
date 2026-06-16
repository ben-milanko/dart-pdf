import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/src/onnx_ocr_model_runner.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('pdf_ocr_onnx_runner_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  File writeFile(String relativePath, List<int> bytes) {
    final file = File('${tempRoot.path}${Platform.pathSeparator}$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  test('keeps ASCII model paths unchanged when staging is forced', () async {
    final det = writeFile('ascii/det.onnx', [1, 2, 3]);
    final rec = writeFile('ascii/rec.onnx', [4, 5, 6]);
    final dict = writeFile('ascii/dict.txt', [97, 10]);

    final paths = await OnnxOcrModelRunner.runtimePathsForTesting(
      detectionModelPath: det.path,
      recognitionModelPath: rec.path,
      dictionaryPath: dict.path,
      forceWindowsStaging: true,
    );

    expect(paths.detection, det.path);
    expect(paths.recognition, rec.path);
    expect(paths.dictionary, dict.path);
  });

  test('stages non-ASCII Windows model paths into an ASCII runtime directory',
      () async {
    final det = writeFile('模型/det.onnx', [1, 2, 3]);
    final rec = writeFile('模型/rec.onnx', [4, 5, 6]);
    final dict = writeFile('模型/dict.txt', [97, 10]);
    final staging =
        Directory('${tempRoot.path}${Platform.pathSeparator}runtime');

    final paths = await OnnxOcrModelRunner.runtimePathsForTesting(
      detectionModelPath: det.path,
      recognitionModelPath: rec.path,
      dictionaryPath: dict.path,
      stagingDirectory: staging,
      forceWindowsStaging: true,
    );

    expect(paths.detection, isNot(det.path));
    expect(paths.recognition, isNot(rec.path));
    expect(paths.dictionary, isNot(dict.path));
    expect(paths.detection.codeUnits.every((unit) => unit <= 0x7f), isTrue);
    expect(paths.recognition.codeUnits.every((unit) => unit <= 0x7f), isTrue);
    expect(paths.dictionary.codeUnits.every((unit) => unit <= 0x7f), isTrue);
    expect(await File(paths.detection).readAsBytes(), [1, 2, 3]);
    expect(await File(paths.recognition).readAsBytes(), [4, 5, 6]);
    expect(await File(paths.dictionary).readAsBytes(), [97, 10]);
  });

  test('rejects a non-ASCII staging directory for Windows runtime copies',
      () async {
    final det = writeFile('模型/det.onnx', [1]);
    final rec = writeFile('模型/rec.onnx', [2]);
    final dict = writeFile('模型/dict.txt', [97, 10]);
    final staging = Directory('${tempRoot.path}${Platform.pathSeparator}缓存');

    await expectLater(
      OnnxOcrModelRunner.runtimePathsForTesting(
        detectionModelPath: det.path,
        recognitionModelPath: rec.path,
        dictionaryPath: dict.path,
        stagingDirectory: staging,
        forceWindowsStaging: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _passwords = {
  'issue6010_1.pdf': 'abc',
  'issue6010_2.pdf': 'æøå',
  'issue15893_reduced.pdf': 'test',
  'bug1782186.pdf': 'Hello',
  'issue3371.pdf': 'ELXRTQWS',
  'encrypted-attachment.pdf': '000000',
};

const _skippedPdfJs = {
  'GHOSTSCRIPT-698804-1-fuzzed.pdf',
  'REDHAT-1531897-0.pdf',
  'poppler-395-0-fuzzed.pdf',
  'poppler-742-0-fuzzed.pdf',
  'poppler-85140-0.pdf',
  'poppler-937-0-fuzzed.pdf',
  'print_protection.pdf',
};

final _corpusReports = <String, Object?>{};

bool _gpuAvailable() {
  try {
    gpu.gpuContext.defaultColorFormat;
    return true;
  } catch (_) {
    return false;
  }
}

Future<Uint8List> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<double> _meanDifference(ui.Image expected, ui.Image actual) async {
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  final a = await _pixels(expected);
  final b = await _pixels(actual);
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference += (a[i] - b[i]).abs();
  }
  return difference / a.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_gpuAvailable()) {
    test('GPU corpus parity', () {},
        skip: 'run with --enable-impeller --enable-flutter-gpu');
    return;
  }

  if (Platform.isMacOS &&
      Platform.environment['GPU_CORPUS_REGISTER_SYSTEM_FONTS'] == '1') {
    setUpAll(_registerMacSystemFonts);
  }

  _corpus(
    'Ghent',
    Directory('../../test_corpora/ghent'),
    recursive: true,
    maxPages: 1 << 20,
  );
  _corpus(
    'PDF.js',
    Directory('../../test_corpora/pdfjs'),
    recursive: false,
    maxPages: 2,
    skipNames: _skippedPdfJs,
  );
}

void _corpus(
  String suite,
  Directory root, {
  required bool recursive,
  required int maxPages,
  Set<String> skipNames = const {},
}) {
  if (!root.existsSync()) {
    test('$suite GPU corpus', () {}, skip: '${root.path} not found');
    return;
  }
  final only = (Platform.environment['GPU_CORPUS_ONLY'] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final files = root
      .listSync(recursive: recursive)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.pdf'))
      .where((file) => !skipNames.contains(file.uri.pathSegments.last))
      .where((file) =>
          only.isEmpty ||
          only.any((part) => file.uri.pathSegments.last.contains(part)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) return;

  var accepted = 0;
  var rejected = 0;
  final rejectionReasons = <String, int>{};
  final missingOutlineFonts = <String, int>{};
  final pages = <Map<String, Object?>>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final prefix = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    final relativeName = (file.path.startsWith(prefix)
            ? file.path.substring(prefix.length)
            : name)
        .replaceAll('\\', '/');
    testWidgets('$suite/$name', (tester) async {
      await tester.runAsync(() async {
        final document = PdfDocument.open(
          file.readAsBytesSync(),
          password: _passwords[name] ?? '',
        );
        final limit = math.min(document.pageCount, maxPages);
        for (var pageIndex = 0; pageIndex < limit; pageIndex++) {
          final scene = await PdfRetainedScene.record(document.page(pageIndex));
          try {
            final backend = FlutterGpuTileRasterBackend(
              analyticText:
                  Platform.environment['GPU_CORPUS_ANALYTIC_TEXT'] != '0',
              systemTextOutlines:
                  Platform.environment['GPU_CORPUS_SYSTEM_TEXT'] == '1',
            );
            final session = backend.createSession(scene);
            if (session == null) {
              rejected++;
              final reason = backend.lastSessionRejection ?? 'unspecified';
              pages.add({
                'id': '$suite/$relativeName page $pageIndex',
                'route': 'canvas-fallback',
                'reason': reason,
              });
              rejectionReasons.update(reason, (count) => count + 1,
                  ifAbsent: () => 1);
              final fonts = <String>{
                for (final command in scene.commands)
                  if (command case PdfDrawTextCommand(:final run))
                    if (!run.invisible && run.glyphs == null)
                      run.fontName ?? '<unnamed>',
              };
              for (final font in fonts) {
                missingOutlineFonts.update(font, (count) => count + 1,
                    ifAbsent: () => 1);
              }
              continue;
            }
            accepted++;
            pages.add({
              'id': '$suite/$relativeName page $pageIndex',
              'route': 'flutter-gpu',
            });
            try {
              final region = Offset.zero & scene.pageSize;
              final ratio = math.min(
                0.75,
                384 / math.max(region.width, region.height),
              );
              final canvas = await scene.rasterizeRegion(
                region,
                pixelRatio: ratio,
              );
              final accelerated = await session.rasterizeRegion(
                region,
                pixelRatio: ratio,
              );
              try {
                final mean = await _meanDifference(canvas, accelerated);
                if (mean >= 16) {
                  await _writeFailure(
                      suite, name, pageIndex, canvas, accelerated, mean);
                }
                expect(mean, lessThan(16),
                    reason: '$suite/$name page $pageIndex: GPU accepted the '
                        'scene, so it must agree with Canvas (mean=$mean)');
              } finally {
                canvas.dispose();
                accelerated.dispose();
              }
            } finally {
              session.dispose();
            }
          } finally {
            scene.dispose();
          }
        }
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('$suite flutter_gpu corpus: accepted=$accepted rejected=$rejected');
    final grouped = rejectionReasons.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    // Keep the grouped surface machine-readable in CI logs without requiring
    // a separate artifact parser. This is the prioritization input for adding
    // exact GPU coverage: frequent conservative fallbacks come first.
    // ignore: avoid_print
    print('$suite flutter_gpu rejection reasons: '
        '${{for (final entry in grouped) entry.key: entry.value}}');
    final fonts = missingOutlineFonts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    // One count per rejected page containing that substituted font, rather
    // than per text run, so a dense drawing title block cannot swamp the
    // prioritization signal.
    // ignore: avoid_print
    print('$suite flutter_gpu missing-outline fonts: '
        '${{for (final entry in fonts) entry.key: entry.value}}');
    pages.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    _corpusReports[suite] = {
      'accepted': accepted,
      'rejected': rejected,
      'pages': pages,
      'rejectionReasons': {
        for (final entry in grouped) entry.key: entry.value,
      },
      'missingOutlineFonts': {
        for (final entry in fonts) entry.key: entry.value,
      },
    };
    _writeCorpusReport();
    expect(accepted + rejected, greaterThan(0));
    // A zero acceptance rate would make the optional backend inert even if
    // all conservative-fallback tests passed.
    expect(accepted, greaterThan(0));
  });
}

void _writeCorpusReport() {
  final path = Platform.environment['GPU_CORPUS_REPORT'];
  if (path == null || path.isEmpty) return;
  final file = File(path);
  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert({
        'schema': 1,
        'suites': _corpusReports,
      })}\n');
}

Future<void> _registerMacSystemFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Helvetica', ['/System/Library/Fonts/Helvetica.ttc']);
  await load('Times New Roman', [
    '/System/Library/Fonts/Supplemental/Times New Roman.ttf',
    '/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf',
    '/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf',
    '/System/Library/Fonts/Supplemental/Times New Roman Bold Italic.ttf',
  ]);
  await load('Courier', [
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/System/Library/Fonts/Supplemental/Courier New Bold.ttf',
    '/System/Library/Fonts/Supplemental/Courier New Italic.ttf',
    '/System/Library/Fonts/Supplemental/Courier New Bold Italic.ttf',
  ]);
  await load('Symbol', ['/System/Library/Fonts/Symbol.ttf']);
  await load('Zapf Dingbats', ['/System/Library/Fonts/ZapfDingbats.ttf']);
  await load(
    'STSong',
    ['/System/Library/Fonts/Supplemental/Songti.ttc'],
  );
  await load(
    'Heiti SC',
    ['/System/Library/Fonts/STHeiti Medium.ttc'],
  );
  await load(
    'Hiragino Sans',
    ['/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc'],
  );
  await load(
    'Hiragino Mincho ProN',
    ['/System/Library/Fonts/ヒラギノ明朝 ProN.ttc'],
  );
}

Future<void> _writeFailure(String suite, String name, int page, ui.Image canvas,
    ui.Image gpuImage, double mean) async {
  final directory = Directory('/tmp/dart_pdf_gpu_failures')
    ..createSync(recursive: true);
  final base = '${suite.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_'
      '${name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}_p$page';
  for (final (label, image) in [('canvas', canvas), ('gpu', gpuImage)]) {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      File('${directory.path}/${base}_$label.png')
          .writeAsBytesSync(data.buffer.asUint8List());
    }
  }
  // ignore: avoid_print
  print('GPU corpus failure images (mean=$mean): '
      '${directory.path}/${base}_*');
}

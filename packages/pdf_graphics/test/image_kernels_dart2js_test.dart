// The web render worker runs the masked-image kernels as dart2js output, and
// dart2js types a local assigned inside a `try` only by its declaration: a
// Uint8List read from one compiles to an interceptor call (J.$index$asx)
// rather than a native typed-array index. That made the exact masked kernel
// 3-8x slower than the path it replaced for a dense soft mask on the web while
// the VM got faster. This compiles a probe at the worker's -O3, unminified so
// functions keep their names, and holds the kernels' sample reads native.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Top-level functions in unminified dart2js output start on a line of their
/// own, four spaces in, and run to the next one.
final _functionStart = RegExp(r'^    ([A-Za-z_$][A-Za-z0-9_$]*)\(.*\) \{$');

String? _functionBody(List<String> lines, String name) {
  final start = lines.indexWhere((l) => l.startsWith('    $name('));
  if (start < 0) return null;
  var end = start + 1;
  while (end < lines.length && !_functionStart.hasMatch(lines[end])) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

int _interceptorIndexes(String body) =>
    RegExp(r'J\.\$index\$asx\(').allMatches(body).length;

void main() {
  late Directory out;
  late List<String> js;

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('image_kernels_dart2js');
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-O3',
      '--no-minify',
      '--no-source-maps',
      '-o',
      '${out.path}/probe.js',
      'test/dart2js/image_kernels_probe.dart',
    ]);
    if (result.exitCode != 0) {
      fail('dart compile js failed (${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    js = File('${out.path}/probe.js').readAsLinesSync();
  });

  tearDownAll(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  test('the check sees a try-assigned sample read as an interceptor call', () {
    final body = _functionBody(js, 'tryAssignedSampleSum');
    expect(body, isNotNull, reason: 'probe function missing from the output');
    expect(_interceptorIndexes(body!), greaterThan(0),
        reason: 'dart2js now indexes a try-assigned Uint8List natively (or '
            'spells the interceptor differently), so the kernel checks below '
            'prove nothing as written - update this test');
  });

  for (final kernel in [
    '_scaledMaskedDirect8Region',
    '_scaledImageMaskRegion'
  ]) {
    test('$kernel reads its samples natively under dart2js', () {
      final body = _functionBody(js, kernel);
      expect(body, isNotNull,
          reason: '$kernel missing from the output (renamed, inlined, or no '
              'longer reachable from the probe)');
      expect(_interceptorIndexes(body!), 0,
          reason: '$kernel indexes a typed array through an interceptor: keep '
              'its sample arrays out of `try`-assigned locals');
      // Positive control: the extracted body is the kernel's sample loop.
      expect(body, contains('data['));
    });
  }
}

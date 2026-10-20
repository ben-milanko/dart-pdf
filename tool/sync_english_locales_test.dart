import 'dart:convert';
import 'dart:io';

import 'sync_english_locales.dart';

void main() {
  void check(String source, String expected, {bool british = true}) {
    final actual = englishMessage(source, british: british);
    if (actual != expected) {
      throw StateError('$source\nExpected: $expected\nActual: $actual');
    }
  }

  for (final pair in englishSpellingPairs.entries) {
    check(pair.key, pair.value);
    check(pair.value, pair.key, british: false);
  }
  check('Color, COLOR, colored; center/centers.',
      'Colour, COLOUR, coloured; centre/centres.');
  check('Resize {size}; recognize {color}; {center, number}.',
      'Resize {size}; recognise {color}; {center, number}.');
  check('{count, plural, =0{No colors} one{Color} other{{count} colors}}',
      '{count, plural, =0{No colours} one{Colour} other{{count} colours}}');
  check(
      '{color, select, gray{Gray} other{{count, plural, offset:1 '
          'one{Color} other{{color} colors}}}}',
      '{color, select, gray{Grey} other{{count, plural, offset:1 '
          'one{Colour} other{{color} colours}}}}');
  check('{center, selectordinal, one{Center} other{Centers}}',
      '{center, selectordinal, one{Centre} other{Centres}}');
  check(
      'Authorization: Bearer; PDF; RGB; PdfColor; colorFormat; size; prize; '
          'perimeter; recognition; cancellation; license; program; dialog.',
      'Authorization: Bearer; PDF; RGB; PdfColor; colorFormat; size; prize; '
          'perimeter; recognition; cancellation; license; program; dialog.');
  _checkBundleDrift();
  print('English spelling and ICU preservation tests passed.');
}

void _checkBundleDrift() {
  final script = File.fromUri(Platform.script)
      .parent
      .uri
      .resolve('sync_english_locales.dart')
      .toFilePath();
  final temp = Directory.systemTemp.createTempSync('english-locales-');
  try {
    for (final bundle in englishBundles) {
      final file = File('${temp.path}/${bundle}_en.arb');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({
        '@@locale': 'en',
        'color': 'Color: {color}',
        'count': '{count, plural, one{Color} other{{count} colors}}',
      }));
    }
    void run(List<String> args, int expectedExit, {String? diagnostic}) {
      final result = Process.runSync(
          Platform.resolvedExecutable, [script, ...args],
          workingDirectory: temp.path);
      if (result.exitCode != expectedExit ||
          (diagnostic != null &&
              !result.stderr.toString().contains(diagnostic))) {
        throw StateError(
            'Locale check: ${result.exitCode}\n${result.stdout}\n${result.stderr}');
      }
    }

    run([], 1, diagnostic: 'missing regional bundle');
    run(['--write'], 0);
    run([], 0);
    final regional = File('${temp.path}/${englishBundles.first}_en_GB.arb');
    regional.writeAsStringSync(
        regional.readAsStringSync().replaceFirst('Colour', 'Color'));
    run([], 1, diagnostic: 'color is out of sync');
    run(['--write'], 0);
    run([], 0);
    final template = File('${temp.path}/${englishBundles.first}_en.arb');
    template.writeAsStringSync(
        template.readAsStringSync().replaceFirst('Color', 'Colour'));
    run([], 1, diagnostic: 'uses a UK/AU spelling');
  } finally {
    temp.deleteSync(recursive: true);
  }
}

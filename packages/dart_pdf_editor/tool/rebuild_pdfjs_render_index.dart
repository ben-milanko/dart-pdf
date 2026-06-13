import 'dart:io';
import 'dart:typed_data';

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// A render passes when at most this fraction of pixels differ from the PDF.js
/// baseline — mirrors `_maxDifferingFraction` in pdfjs_render_test.dart.
const _passThreshold = 0.0005;

void main(List<String> args) {
  final repoRoot = _repoRoot();
  final corpusDir = Directory('${repoRoot.path}/test_corpora/pdfjs');
  final outDir = args.isEmpty
      ? Directory('${corpusDir.path}/_renders')
      : Directory(args.single);
  if (!outDir.existsSync()) {
    stderr.writeln('Render directory not found: ${outDir.path}');
    exitCode = 1;
    return;
  }

  final pdfNamesBySafeName = <String, String>{};
  if (corpusDir.existsSync()) {
    for (final file in corpusDir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.toLowerCase().endsWith('.pdf')) {
        pdfNamesBySafeName[_safeName(name)] = name;
      }
    }
  }

  final renders = <_Render>[];
  final actualPattern = RegExp(r'^(.*)\.p([0-9]+)\.dart\.png$');
  for (final file in outDir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    final match = actualPattern.firstMatch(name);
    if (match == null) continue;
    final baseName = match.group(1)!;
    final page = int.parse(match.group(2)!);
    final prefix = '$baseName.p$page';
    final baseline = File('${outDir.path}/$prefix.baseline.png');
    final diff = File('${outDir.path}/$prefix.diff.png');
    final info = _readPngInfo(file);
    final diffFraction = diff.existsSync() ? _redPixelFraction(diff) : null;
    renders.add(_Render(
      pdfName: pdfNamesBySafeName[baseName] ?? baseName,
      page: page,
      actualName: name,
      baselineName:
          baseline.existsSync() ? baseline.uri.pathSegments.last : null,
      diffName: diff.existsSync() ? diff.uri.pathSegments.last : null,
      differenceFraction: diffFraction,
      width: info.width,
      height: info.height,
    ));
  }
  renders.sort((a, b) {
    final byName = a.pdfName.compareTo(b.pdfName);
    if (byName != 0) return byName;
    return a.page.compareTo(b.page);
  });

  final stats = _passStats(renders);
  File('${outDir.path}/index.html').writeAsStringSync(_indexHtml(renders));
  File('${outDir.path}/README.md')
      .writeAsStringSync(_indexMarkdown(renders, stats));
  stdout.writeln(
      'wrote ${outDir.path}/index.html and README.md (${renders.length} renders)');

  final corpusReadme = File('${corpusDir.path}/README.md');
  if (_patchRenderSummary(corpusReadme, stats)) {
    stdout.writeln('updated render summary in ${corpusReadme.path}');
  }
}

/// Rewrites the `<!-- render-summary:start -->…<!-- render-summary:end -->`
/// span in the corpus README with the current pass count. Returns false (and
/// leaves the file untouched) when the file or markers are absent.
bool _patchRenderSummary(File readme, _PassStats stats) {
  if (!readme.existsSync()) return false;
  final marker = RegExp(
      r'<!-- render-summary:start -->.*?<!-- render-summary:end -->',
      dotAll: true);
  final original = readme.readAsStringSync();
  if (!marker.hasMatch(original)) return false;
  final replacement = '<!-- render-summary:start -->'
      '**${stats.passed} of ${stats.compared} compared pages pass**'
      '<!-- render-summary:end -->';
  final updated = original.replaceAll(marker, replacement);
  if (updated == original) return false;
  readme.writeAsStringSync(updated);
  return true;
}

_PassStats _passStats(List<_Render> renders) {
  var passed = 0;
  var failed = 0;
  for (final render in renders) {
    switch (_passFail(render.differenceFraction)) {
      case _Result.pass:
        passed++;
      case _Result.fail:
        failed++;
      case _Result.na:
        break;
    }
  }
  return _PassStats(passed: passed, failed: failed);
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test_corpora').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'could not find repo root from ${Directory.current.path}');
    }
    dir = parent;
  }
}

String _indexHtml(List<_Render> renders) {
  final html = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<title>PDF.js corpus render comparisons</title>')
    ..writeln('<style>')
    ..writeln(
        'body{font:14px system-ui,sans-serif;margin:24px;background:#f6f7f8;color:#202124}')
    ..writeln('h1{font-size:20px;margin:0 0 6px}')
    ..writeln('p{margin:0 0 16px;color:#5f6368}')
    ..writeln('.results{display:flex;flex-direction:column;gap:16px}')
    ..writeln(
        '.result{margin:0;padding:12px;background:white;border:1px solid #dadce0;border-radius:6px}')
    ..writeln('.meta{margin:0 0 10px;overflow-wrap:anywhere;color:#3c4043}')
    ..writeln(
        '.shots{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;align-items:start}')
    ..writeln('.shot-label{font-size:12px;color:#5f6368;margin:0 0 6px}')
    ..writeln(
        'img{display:block;max-width:100%;height:auto;background:white;border:1px solid #eee}')
    ..writeln(
        '.missing{border:1px dashed #dadce0;color:#80868b;padding:32px 8px;text-align:center;background:#fafafa}')
    ..writeln('@media (max-width: 900px){.shots{grid-template-columns:1fr}}')
    ..writeln('</style>')
    ..writeln('<h1>PDF.js corpus render comparisons</h1>')
    ..writeln(
        '<p>Checked-in visual results: PDF.js baseline, Dart render, and diff.</p>')
    ..writeln('<div class="results">');
  for (final render in renders) {
    html
      ..writeln('<figure class="result">')
      ..writeln(
          '<figcaption class="meta">${_htmlText(render.pdfName)} page ${render.page + 1}<br>${render.width}x${render.height}${_difference(render.differenceFraction)}</figcaption>')
      ..writeln('<div class="shots">')
      ..writeln(_shot('PDF.js baseline', render.baselineName))
      ..writeln(_shot('Dart render', render.actualName))
      ..writeln(_shot('Diff', render.diffName))
      ..writeln('</div>')
      ..writeln('</figure>');
  }
  html
    ..writeln('</div>')
    ..writeln();
  return html.toString();
}

String _indexMarkdown(List<_Render> renders, _PassStats stats) {
  final markdown = StringBuffer()
    ..writeln('# PDF.js Corpus Render Comparisons')
    ..writeln()
    ..writeln(
        'Checked-in visual results for the PDF.js corpus: PDF.js baseline, '
        'Dart render, and diff images. The diff percentage is computed from '
        'the checked-in diff PNGs, where solid red pixels mark channels that '
        'exceeded the comparison tolerance.')
    ..writeln()
    ..writeln('Regenerate this file after adding or removing PNGs with:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
        'fvm dart packages/dart_pdf_editor/tool/rebuild_pdfjs_render_index.dart')
    ..writeln('```')
    ..writeln()
    ..writeln('| PDF | Page | Size | Diff | Result |')
    ..writeln('| --- | ---: | ---: | ---: | :---: |');
  for (final render in renders) {
    markdown.writeln(
        '| ${_mdCell(render.pdfName)} | ${render.page + 1} | ${render.width}x${render.height} | ${_mdDifference(render.differenceFraction)} | ${_passFail(render.differenceFraction).label} |');
  }
  markdown
    ..writeln()
    ..writeln('${stats.passed} of ${stats.compared} compared pages pass '
        '(≤ ${(_passThreshold * 100).toStringAsFixed(3)}% of pixels '
        'differing); ${stats.failed} fail.');
  markdown.writeln();

  markdown
    ..writeln('## Visual Comparisons')
    ..writeln();
  for (final render in renders) {
    markdown
      ..writeln('### ${_mdHeading(render.pdfName)} page ${render.page + 1}')
      ..writeln()
      ..writeln(
          '${render.width}x${render.height}; diff: ${_mdDifference(render.differenceFraction)}')
      ..writeln()
      ..writeln('| PDF.js baseline | Dart render | Diff |')
      ..writeln('| --- | --- | --- |')
      ..writeln(
          '| ${_mdImage(render.baselineName, 'PDF.js baseline')} | ${_mdImage(render.actualName, 'Dart render')} | ${_mdImage(render.diffName, 'Diff')} |')
      ..writeln();
  }
  return markdown.toString();
}

String _shot(String label, String? fileName) {
  if (fileName == null) {
    return '<div><div class="shot-label">$label</div><div class="missing">missing</div></div>';
  }
  final escaped = _htmlAttr(fileName);
  return '<div><div class="shot-label">$label</div><a href="$escaped"><img src="$escaped" loading="lazy"></a></div>';
}

String _difference(double? fraction) {
  if (fraction == null) return '';
  return '<br>${(fraction * 100).toStringAsFixed(3)}% differing pixels';
}

String _mdDifference(double? fraction) {
  if (fraction == null) return 'n/a';
  return '${(fraction * 100).toStringAsFixed(3)}%';
}

_Result _passFail(double? fraction) {
  if (fraction == null) return _Result.na;
  return fraction <= _passThreshold ? _Result.pass : _Result.fail;
}

enum _Result {
  pass('✅ pass'),
  fail('❌ fail'),
  na('—');

  const _Result(this.label);

  final String label;
}

class _PassStats {
  const _PassStats({required this.passed, required this.failed});

  final int passed;
  final int failed;

  int get compared => passed + failed;
}

String _mdImage(String? fileName, String label) {
  if (fileName == null) return 'missing';
  return '[![$label](${_mdUrl(fileName)})](${_mdUrl(fileName)})';
}

String _mdCell(String text) => text.replaceAll('|', r'\|');

String _mdHeading(String text) => text.replaceAll('#', r'\#');

String _mdUrl(String text) => Uri.encodeComponent(text).replaceAll('%2F', '/');

_PngInfo _readPngInfo(File file) {
  final bytes = file.readAsBytesSync();
  _checkPng(bytes, file);
  return _PngInfo(
    width: _uint32(bytes, 16),
    height: _uint32(bytes, 20),
  );
}

double? _redPixelFraction(File file) {
  final bytes = file.readAsBytesSync();
  _checkPng(bytes, file);
  final width = _uint32(bytes, 16);
  final height = _uint32(bytes, 20);
  final bitDepth = bytes[24];
  final colorType = bytes[25];
  final interlace = bytes[28];
  if (bitDepth != 8 || colorType != 6 || interlace != 0) return null;

  final idat = BytesBuilder(copy: false);
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final length = _uint32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) return null;
    if (type == 'IDAT') {
      idat.add(bytes.sublist(dataStart, dataEnd));
    } else if (type == 'IEND') {
      break;
    }
    offset = dataEnd + 4;
  }

  final inflated = ZLibDecoder().convert(idat.takeBytes());
  const bytesPerPixel = 4;
  final stride = width * bytesPerPixel;
  final previous = Uint8List(stride);
  final current = Uint8List(stride);
  var sourceOffset = 0;
  var red = 0;
  for (var y = 0; y < height; y++) {
    if (sourceOffset >= inflated.length) return null;
    final filter = inflated[sourceOffset++];
    if (sourceOffset + stride > inflated.length) return null;
    current.setRange(0, stride, inflated, sourceOffset);
    sourceOffset += stride;
    _unfilter(current, previous, filter, bytesPerPixel);
    for (var x = 0; x < stride; x += bytesPerPixel) {
      if (current[x] == 255 &&
          current[x + 1] == 0 &&
          current[x + 2] == 0 &&
          current[x + 3] == 255) {
        red++;
      }
    }
    previous.setAll(0, current);
  }
  return red / (width * height);
}

void _unfilter(Uint8List row, Uint8List previous, int filter, int bpp) {
  switch (filter) {
    case 0:
      return;
    case 1:
      for (var i = 0; i < row.length; i++) {
        row[i] = (row[i] + (i >= bpp ? row[i - bpp] : 0)) & 0xff;
      }
    case 2:
      for (var i = 0; i < row.length; i++) {
        row[i] = (row[i] + previous[i]) & 0xff;
      }
    case 3:
      for (var i = 0; i < row.length; i++) {
        final left = i >= bpp ? row[i - bpp] : 0;
        final up = previous[i];
        row[i] = (row[i] + ((left + up) >> 1)) & 0xff;
      }
    case 4:
      for (var i = 0; i < row.length; i++) {
        final left = i >= bpp ? row[i - bpp] : 0;
        final up = previous[i];
        final upLeft = i >= bpp ? previous[i - bpp] : 0;
        row[i] = (row[i] + _paeth(left, up, upLeft)) & 0xff;
      }
    default:
      throw FormatException('unsupported PNG filter: $filter');
  }
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

void _checkPng(Uint8List bytes, File file) {
  if (bytes.length < 29) {
    throw FormatException('not a PNG: ${file.path}');
  }
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) {
      throw FormatException('not a PNG: ${file.path}');
    }
  }
}

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

String _safeName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

String _htmlText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _htmlAttr(String text) => _htmlText(text).replaceAll('"', '&quot;');

class _PngInfo {
  const _PngInfo({required this.width, required this.height});

  final int width;
  final int height;
}

class _Render {
  const _Render({
    required this.pdfName,
    required this.page,
    required this.actualName,
    required this.baselineName,
    required this.diffName,
    required this.differenceFraction,
    required this.width,
    required this.height,
  });

  final String pdfName;
  final int page;
  final String actualName;
  final String? baselineName;
  final String? diffName;
  final double? differenceFraction;
  final int width;
  final int height;
}

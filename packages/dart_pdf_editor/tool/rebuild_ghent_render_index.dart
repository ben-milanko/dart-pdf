// Builds the GitHub-viewable gallery of the checked-in Ghent render baselines
// (`test_corpora/ghent/_baselines/README.md`), the Ghent counterpart to
// `rebuild_pdfjs_render_index.dart`.
//
// The two galleries are deliberately NOT the same shape. PDF.js ships reference
// renders, so that page is a three-way baseline/Dart/diff comparison with a
// pass/fail column. Ghent ships no reference renders - our own rasters *are* the
// baselines - so there is nothing to diff against and no pass/fail to report.
// This page is a visual index of what we currently draw for each patch.
//
// Run after adding, removing, or re-accepting baselines:
//   fvm dart packages/dart_pdf_editor/tool/rebuild_ghent_render_index.dart

import 'dart:io';
import 'dart:typed_data';

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

void main(List<String> args) {
  final repoRoot = _repoRoot();
  final corpusDir = Directory('${repoRoot.path}/test_corpora/ghent');
  final baselinesDir = args.isEmpty
      ? Directory('${corpusDir.path}/_baselines')
      : Directory(args.single);
  if (!baselinesDir.existsSync()) {
    stderr.writeln('Baseline directory not found: ${baselinesDir.path}');
    exitCode = 1;
    return;
  }

  final renders = <_Render>[];
  final pattern = RegExp(r'^(.*)\.p([0-9]+)\.png$');
  for (final file in baselinesDir.listSync(recursive: true).whereType<File>()) {
    final relative = file.path
        .substring(baselinesDir.path.length + 1)
        .replaceAll(r'\', '/');
    final name = relative.split('/').last;
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final segments = relative.split('/');
    // Baselines mirror the corpus tree: <category>/<pdf>.p<page>.png. A file
    // sitting directly in _baselines has no category.
    final category =
        segments.length > 1 ? segments.sublist(0, segments.length - 1).join('/') : '';
    final info = _readPngInfo(file);
    renders.add(_Render(
      category: category,
      pdfName: match.group(1)!,
      page: int.parse(match.group(2)!),
      relativePath: relative,
      width: info.width,
      height: info.height,
    ));
  }

  if (renders.isEmpty) {
    stderr.writeln('No baseline PNGs found under ${baselinesDir.path}');
    exitCode = 1;
    return;
  }

  renders.sort((a, b) {
    final byCategory = a.category.compareTo(b.category);
    if (byCategory != 0) return byCategory;
    final byName = a.pdfName.compareTo(b.pdfName);
    if (byName != 0) return byName;
    return a.page.compareTo(b.page);
  });

  File('${baselinesDir.path}/README.md')
      .writeAsStringSync(_indexMarkdown(renders));
  stdout.writeln(
      'wrote ${baselinesDir.path}/README.md (${renders.length} renders)');
}

String _indexMarkdown(List<_Render> renders) {
  final byCategory = <String, List<_Render>>{};
  for (final render in renders) {
    byCategory.putIfAbsent(render.category, () => <_Render>[]).add(render);
  }
  final categories = byCategory.keys.toList()..sort();

  final pdfCount =
      renders.map((r) => '${r.category}/${r.pdfName}').toSet().length;

  final markdown = StringBuffer()
    ..writeln('# Ghent Output Suite Render Gallery')
    ..writeln()
    ..writeln(
        'Every checked-in render baseline for the [Ghent PDF Output Suite '
        'V5.0](https://gwg.org/) corpus in `test_corpora/ghent`, viewable '
        'directly in GitHub. ${renders.length} pages across $pdfCount PDFs, '
        'rasterized at 2x by `dart_pdf_editor/test/ghent_render_test.dart`.')
    ..writeln()
    ..writeln(
        '> **These baselines pin current behaviour, not GWG conformance.** '
        'Unlike the [PDF.js gallery](../../pdfjs/_renders/README.md), there is '
        'no external reference renderer here and therefore no diff and no '
        'pass/fail column - these images *are* the baselines the render test '
        'compares against. A green `ghent_render_test` means "unchanged since '
        'the last accepted render", not "correct".')
    ..writeln('>')
    ..writeln(
        '> Many patches print their own pass criterion on the page, so read '
        'them to judge a render. Known deviations: faithful subtractive '
        'overprint is not implemented (it needs a CMYK/spot colorant buffer), '
        "so the GWG030 \"over CMYK\" patches are a tolerated deviation, and "
        "GWG173's faint \"X\" is a known JBIG2 difference.")
    ..writeln()
    ..writeln('Regenerate this file after adding, removing, or re-accepting '
        'baselines:')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
        'fvm dart packages/dart_pdf_editor/tool/rebuild_ghent_render_index.dart')
    ..writeln('```')
    ..writeln()
    ..writeln(
        'Re-accept baselines deliberately - never blanket-accept. See the '
        'corpus notes in '
        '[`README.md`](../../../README.md#rendering-test-suite).')
    ..writeln();

  markdown
    ..writeln('## Contents')
    ..writeln()
    ..writeln('| Category | Pages |')
    ..writeln('| --- | ---: |');
  for (final category in categories) {
    final label = category.isEmpty ? 'uncategorized' : category;
    markdown.writeln(
        '| [$label](#${_anchor(label)}) | ${byCategory[category]!.length} |');
  }
  markdown.writeln();

  for (final category in categories) {
    final label = category.isEmpty ? 'uncategorized' : category;
    markdown
      ..writeln('## $label')
      ..writeln();
    for (final render in byCategory[category]!) {
      markdown
        ..writeln('### ${_mdHeading(render.pdfName)} page ${render.page + 1}')
        ..writeln()
        ..writeln('${render.width}x${render.height}')
        ..writeln()
        ..writeln(
            '[![${_mdCell(render.pdfName)} page ${render.page + 1}](${_mdUrl(render.relativePath)})](${_mdUrl(render.relativePath)})')
        ..writeln();
    }
  }
  return markdown.toString();
}

/// GitHub's heading anchor: lowercased, non-word characters dropped, spaces to
/// dashes. The category labels here are plain (`1-CMYK`), so this is enough.
String _anchor(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 _-]'), '')
    .replaceAll(' ', '-');

String _mdCell(String text) => text.replaceAll('|', r'\|');

String _mdHeading(String text) => text.replaceAll('#', r'\#');

String _mdUrl(String text) => Uri.encodeComponent(text).replaceAll('%2F', '/');

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

_PngInfo _readPngInfo(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length < 29) {
    throw FormatException('not a PNG: ${file.path}');
  }
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) {
      throw FormatException('not a PNG: ${file.path}');
    }
  }
  return _PngInfo(width: _uint32(bytes, 16), height: _uint32(bytes, 20));
}

int _uint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

class _PngInfo {
  const _PngInfo({required this.width, required this.height});

  final int width;
  final int height;
}

class _Render {
  const _Render({
    required this.category,
    required this.pdfName,
    required this.page,
    required this.relativePath,
    required this.width,
    required this.height,
  });

  final String category;
  final String pdfName;
  final int page;
  final String relativePath;
  final int width;
  final int height;
}

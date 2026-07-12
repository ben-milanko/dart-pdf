import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

const _fixtures = <String>[
  'rotation.pdf',
  'xobject-image.pdf',
  'gradientfill.pdf',
  'tiling_patterns_variations.pdf',
  'glyph_accent.pdf',
  'blendmode.pdf',
  'smaskdim.pdf',
  'knockout_isolated_overlap.pdf',
];

void main() {
  testWidgets('spatial region replay matches diverse PDF.js corpus pages',
      (tester) async {
    final previous = PdfRetainedScene.spatialRegionReplay;
    addTearDown(() => PdfRetainedScene.spatialRegionReplay = previous);
    await tester.runAsync(() async {
      var selective = 0;
      var fallback = 0;
      for (final name in _fixtures) {
        final bytes = File('../../test_corpora/pdfjs/$name').readAsBytesSync();
        final document = PdfDocument.open(Uint8List.fromList(bytes));
        if (document.pageCount == 0) continue;
        final scene = await PdfRetainedScene.record(document.page(0));
        try {
          final size = scene.pageSize;
          final region = Rect.fromLTWH(
            size.width * .2,
            size.height * .2,
            size.width * .6,
            size.height * .6,
          );
          PdfRetainedScene.spatialRegionReplay = false;
          final expected = await scene.rasterizeRegion(region, pixelRatio: 1.5);
          PdfRetainedScene.spatialRegionReplay = true;
          final actual = await scene.rasterizeRegion(region, pixelRatio: 1.5);
          try {
            expect(actual.width, expected.width, reason: name);
            expect(actual.height, expected.height, reason: name);
            expect(
              await _bytes(actual),
              await _bytes(expected),
              reason: '$name region pixels',
            );
          } finally {
            expected.dispose();
            actual.dispose();
          }
          if (scene.debugLastRegionReplayWasSelective) {
            selective++;
          } else {
            fallback++;
          }
        } finally {
          scene.dispose();
        }
      }
      expect(selective, greaterThanOrEqualTo(3));
      expect(fallback, greaterThanOrEqualTo(1),
          reason: 'transparency groups exercise conservative full replay');
    });
  });
}

Future<Uint8List> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

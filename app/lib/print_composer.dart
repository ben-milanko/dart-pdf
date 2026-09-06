import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'print_settings.dart';

/// Number of physical sheets before copies are expanded.
int printSheetCount(PrintSettings settings) {
  final perSheet =
      settings.scaling == PrintScaling.multiple ? settings.pagesPerSheet : 1;
  if (perSheet < 1) throw ArgumentError.value(perSheet, 'pagesPerSheet');
  return (settings.pages.length + perSheet - 1) ~/ perSheet;
}

/// Validates the whole job using page metadata only, so an invalid later
/// sheet can be reported while the print dialog still owns its settings.
/// No content or image streams are decoded.
void validatePrintSettings(PdfDocument document, PrintSettings settings) {
  _validate(document, settings);
  final pages =
      settings.reverse ? settings.pages.reversed.toList() : settings.pages;
  final count =
      settings.scaling == PrintScaling.multiple ? settings.pagesPerSheet : 1;
  final geometry = <int, _SourceGeometry>{};
  for (var i = 0; i < pages.length; i++) {
    final size = geometry.putIfAbsent(pages[i],
        () => _sourceGeometry(document.page(pages[i]), settings.region));
    if (i % count == 0) {
      final (width, height) = _paperSize(size.width, size.height, settings);
      final margin = _margin(settings);
      if (width <= margin * 2 || height <= margin * 2) {
        throw ArgumentError(
            'Margins leave no printable area on sheet ${i ~/ count + 1}.');
      }
    }
  }
}

/// Produces the exact printable sheet geometry as a fresh vector PDF.
///
/// Resources and appearances are copied once per source object; copies only
/// add lightweight page dictionaries. No editor ever touches [document].
/// The result has no interactive annotations: printable appearances have
/// already been painted with print visibility semantics, including NoView.
/// [sheetIndex] selects one sheet before copies, for an inexpensive preview.
Uint8List preparePrintDocument(
  PdfDocument document,
  PrintSettings settings, {
  bool includeCopies = true,
  int? sheetIndex,
}) {
  if (sheetIndex == null) {
    validatePrintSettings(document, settings);
  } else {
    _validate(document, settings);
  }
  final sheetCount = printSheetCount(settings);
  if (sheetIndex != null) {
    RangeError.checkValidIndex(sheetIndex, null, 'sheetIndex', sheetCount);
  }
  final composer = _PrintComposer(document, settings);
  final pages =
      settings.reverse ? settings.pages.reversed.toList() : settings.pages;
  final perSheet =
      settings.scaling == PrintScaling.multiple ? settings.pagesPerSheet : 1;
  final sheets = <CosDictionary>[];
  for (var i = sheetIndex ?? 0;
      i < (sheetIndex == null ? sheetCount : sheetIndex + 1);
      i++) {
    final start = i * perSheet;
    sheets.add(composer.sheet(pages.sublist(
      start,
      math.min(start + perSheet, pages.length),
    )));
  }
  final copies = includeCopies && sheetIndex == null ? settings.copies : 1;
  final ordered = settings.collate
      ? [for (var copy = 0; copy < copies; copy++) ...sheets]
      : [
          for (final sheet in sheets)
            for (var copy = 0; copy < copies; copy++) sheet
        ];
  return composer.finish(ordered);
}

void _validate(PdfDocument document, PrintSettings settings) {
  if (settings.pages.isEmpty) throw ArgumentError('Select at least one page.');
  for (final page in settings.pages) {
    RangeError.checkValidIndex(page, null, 'pages', document.pageCount);
  }
  if (settings.copies < 1 || settings.copies > 999) {
    throw ArgumentError.value(settings.copies, 'copies', 'Use 1–999 copies.');
  }
  if (settings.pagesPerSheet < 1 || settings.pagesPerSheet > 16) {
    throw ArgumentError.value(settings.pagesPerSheet, 'pagesPerSheet');
  }
  if (!settings.customScale.isFinite || settings.customScale <= 0) {
    throw ArgumentError.value(settings.customScale, 'customScale');
  }
  if (!settings.margin.isFinite || settings.margin < 0) {
    throw ArgumentError.value(settings.margin, 'margin');
  }
  if (!settings.offsetX.isFinite || !settings.offsetY.isFinite) {
    throw ArgumentError('Print offsets must be finite.');
  }
  final region = settings.region;
  if (region != null &&
      (settings.pages.length != 1 ||
          ![region.left, region.bottom, region.right, region.top]
              .every((n) => n.isFinite) ||
          region.width <= 0 ||
          region.height <= 0)) {
    throw ArgumentError('Choose a nonempty region on one page.');
  }
}

class _PageArt {
  const _PageArt(this.reference, this.width, this.height);
  final CosReference reference;
  final double width;
  final double height;
}

class _PrintComposer {
  _PrintComposer(this.document, this.settings)
      : builder = CosDocumentBuilder() {
    copier = _ObjectCopier(document.cos, builder);
  }

  final PdfDocument document;
  final PrintSettings settings;
  final CosDocumentBuilder builder;
  late final _ObjectCopier copier;
  final _art = <int, _PageArt>{};

  CosDictionary sheet(List<int> pageIndices) {
    final first = _pageArt(pageIndices.first);
    final (width, height) = _paperSize(first.width, first.height, settings);
    final multiple = settings.scaling == PrintScaling.multiple;
    final margin = _margin(settings);
    final availableWidth = width - margin * 2;
    final availableHeight = height - margin * 2;
    if (availableWidth <= 0 || availableHeight <= 0) {
      throw ArgumentError('Margins leave no printable area on this paper.');
    }
    final (columns, rows) =
        multiple ? _grid(settings.pagesPerSheet, width >= height) : (1, 1);
    final cellWidth = availableWidth / columns;
    final cellHeight = availableHeight / rows;
    final xObjects = CosDictionary();
    final writer = ContentWriter();
    for (var i = 0; i < pageIndices.length; i++) {
      final art = _pageArt(pageIndices[i]);
      final (column, row) = switch (settings.layout) {
        PrintPageLayout.horizontal => (i % columns, i ~/ columns),
        PrintPageLayout.horizontalReverse => (
            columns - 1 - i % columns,
            i ~/ columns
          ),
        PrintPageLayout.vertical => (i ~/ rows, i % rows),
        PrintPageLayout.verticalReverse => (columns - 1 - i ~/ rows, i % rows),
      };
      final left = margin + column * cellWidth;
      final bottom = height - margin - (row + 1) * cellHeight;
      var turns = _fixedQuarterTurns;
      if (settings.rotation == PrintRotation.auto) {
        final normal = math.min(cellWidth / art.width, cellHeight / art.height);
        final rotated =
            math.min(cellWidth / art.height, cellHeight / art.width);
        if (rotated > normal + 1e-9) turns = 1;
      }
      final artWidth = turns.isOdd ? art.height : art.width;
      final artHeight = turns.isOdd ? art.width : art.height;
      final fit = math.min(cellWidth / artWidth, cellHeight / artHeight);
      final scale = switch (settings.scaling) {
        PrintScaling.none => 1.0,
        PrintScaling.custom => settings.customScale / 100,
        PrintScaling.reducePaper ||
        PrintScaling.reduceMargins =>
          math.min(1.0, fit),
        _ => fit,
      };
      final x = left +
          (settings.center ? (cellWidth - artWidth * scale) / 2 : 0) +
          settings.offsetX;
      final y = bottom +
          (settings.center
              ? (cellHeight - artHeight * scale) / 2
              : cellHeight - artHeight * scale) -
          settings.offsetY;
      final transform = _rotate(art.width, art.height, turns)
          .concat(PdfMatrix.scaled(scale, scale))
          .concat(PdfMatrix.translation(x, y));
      xObjects['Page$i'] = art.reference;
      writer
        ..save()
        ..rect(left, bottom, cellWidth, cellHeight)
        ..clip();
      _concat(writer, transform);
      writer
        ..drawXObject('Page$i')
        ..restore();
      if (multiple && settings.printBorder) {
        writer
          ..save()
          ..rect(left, bottom, cellWidth, cellHeight)
          ..clip()
          ..strokeColor(0x000000)
          ..lineWidth(0.5)
          ..rect(x + 0.25, y + 0.25, artWidth * scale - 0.5,
              artHeight * scale - 0.5)
          ..stroke()
          ..restore();
      }
    }
    return CosDictionary({
      'Type': const CosName('Page'),
      'MediaBox': _rect(PdfRect(0, 0, width, height)),
      'Resources': CosDictionary({'XObject': xObjects}),
      'Contents': builder.add(_stream(writer.takeBytes())),
    });
  }

  int get _fixedQuarterTurns => switch (settings.rotation) {
        PrintRotation.clockwise90 => 1,
        PrintRotation.halfTurn => 2,
        PrintRotation.clockwise270 => 3,
        _ => 0,
      };

  _PageArt _pageArt(int index) => _art.putIfAbsent(index, () {
        final page = document.page(index);
        final geometry = _sourceGeometry(page, settings.region);
        final sourceToSheet = geometry.matrix;
        final objects = CosDictionary();
        final writer = ContentWriter()..save();
        _concat(writer, sourceToSheet);
        if (settings.content != PrintContent.markupsOnly) {
          objects['Document'] = _layer(page, documentLayer: true);
          if (settings.dimPageContent) writer.extGState('Dim');
          writer.drawXObject('Document');
        }
        writer.restore();
        if (settings.content != PrintContent.documentOnly) {
          objects['Markups'] = _layer(page, documentLayer: false);
          writer.save();
          _concat(writer, sourceToSheet);
          if (settings.dimMarkups) writer.extGState('Dim');
          writer
            ..drawXObject('Markups')
            ..restore();
        }
        final width = geometry.width;
        final height = geometry.height;
        final normalized = _form(
          PdfRect(0, 0, width, height),
          CosDictionary({
            'XObject': objects,
            'ExtGState': CosDictionary({'Dim': _alpha(0.35)}),
          }),
          writer.takeBytes(),
        );
        return _PageArt(builder.add(normalized), width, height);
      });

  CosReference _layer(PdfPage page, {required bool documentLayer}) {
    final writer = ContentWriter();
    final objects = CosDictionary();
    final properties = CosDictionary();
    if (documentLayer) {
      final content = _form(
        page.cropBox,
        copier.copy(page.resources),
        page.contentBytes(),
      );
      final group = document.cos.resolve(page.dict['Group']);
      if (group is CosDictionary) {
        content.dictionary['Group'] = copier.copy(group);
      }
      objects['Content'] = builder.add(content);
      writer
        ..save()
        ..drawXObject('Content')
        ..restore();
    }
    var ordinal = 0;
    for (final annotation in page.annotations) {
      final isDocument = annotation.subtype == 'Widget';
      if (isDocument != documentLayer ||
          annotation.isHidden ||
          !annotation.isPrint ||
          annotation.subtype == 'Popup' ||
          annotation.isReply ||
          annotation.isStateAnnotation ||
          (annotation.subtype == 'Link' && !settings.printVisibleHyperlinks)) {
        continue;
      }
      final appearance = annotation.normalAppearance;
      if (appearance == null) {
        final optional = _optionalAnnotation(
            writer, properties, annotation, 'Layer${ordinal++}');
        _fallback(writer, annotation);
        if (optional) writer.endMarkedContent();
        continue;
      }
      final bbox = pdfRectFrom(document.cos, appearance.dictionary['BBox']);
      if (bbox == null ||
          bbox.width <= 0 ||
          bbox.height <= 0 ||
          annotation.rect.width <= 0 ||
          annotation.rect.height <= 0) {
        continue;
      }
      final fit = fitFormToRect(
        bbox,
        _matrix(document.cos, appearance.dictionary['Matrix']),
        annotation.rect,
      );
      final name = 'Annotation${ordinal++}';
      objects[name] = copier.copy(appearance);
      writer.save();
      final optional =
          _optionalAnnotation(writer, properties, annotation, name);
      _concat(writer, fit);
      writer.drawXObject(name);
      if (optional) writer.endMarkedContent();
      writer.restore();
    }
    return builder.add(_form(
      page.cropBox,
      CosDictionary({
        'XObject': objects,
        'Properties': properties,
        'ExtGState': CosDictionary({
          'PrintHighlight': CosDictionary({
            ..._alpha(0.35).entries,
            'BM': const CosName('Multiply'),
          }),
        }),
        'Font': CosDictionary({
          'PrintFallback': CosDictionary({
            'Type': const CosName('Font'),
            'Subtype': const CosName('Type1'),
            'BaseFont': const CosName('Helvetica'),
            'Encoding': const CosName('WinAnsiEncoding'),
          }),
          for (final font in PdfStandardFont.values)
            font.resourceName: CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': CosName(font.baseFont),
              'Encoding': const CosName('WinAnsiEncoding'),
            }),
        }),
      }),
      writer.takeBytes(),
      isolate: documentLayer ? settings.dimPageContent : settings.dimMarkups,
    ));
  }

  bool _optionalAnnotation(ContentWriter writer, CosDictionary properties,
      PdfAnnotation annotation, String name) {
    final group = annotation.dict['OC'];
    if (group == null) return false;
    properties[name] = copier.copy(group);
    writer.op('/OC /$name BDC');
    return true;
  }

  // Producers may omit /AP on simple annotations and form widgets. Keep
  // their semantic border/text/ink visible when constructing print content.
  void _fallback(ContentWriter writer, PdfAnnotation annotation) {
    final r = annotation.rect;
    if (r.width <= 0 || r.height <= 0) return;
    final color = annotation.color ?? 0x000000;
    var border = annotation.borderWidth;
    final rawBorder = document.cos.resolve(annotation.dict['Border']);
    if (border == null && rawBorder is CosArray && rawBorder.length >= 3) {
      border = _number(document.cos.resolve(rawBorder[2]), 0);
    }
    final width = border ?? 1;
    writer
      ..save()
      ..strokeColor(color)
      ..fillColor(annotation.interiorColor ?? color)
      ..lineWidth(width);
    switch (annotation.subtype) {
      case 'Link':
        if (annotation.color != null && (border ?? 0) > 0) {
          writer
            ..rect(r.left + width / 2, r.bottom + width / 2, r.width - width,
                r.height - width)
            ..stroke();
        }
      case 'Square' || 'Circle':
        if (annotation.subtype == 'Circle') {
          writer.ellipse((r.left + r.right) / 2, (r.bottom + r.top) / 2,
              r.width / 2, r.height / 2);
        } else {
          writer.rect(r.left, r.bottom, r.width, r.height);
        }
        if (annotation.interiorColor != null) {
          writer.fillAndStroke();
        } else {
          writer.stroke();
        }
      case 'Ink':
        writer.roundLines();
        for (final stroke
            in annotation.inkList ?? const <List<(double, double)>>[]) {
          if (stroke.isEmpty) continue;
          writer.moveTo(stroke.first.$1, stroke.first.$2);
          for (final point in stroke.skip(1)) {
            writer.lineTo(point.$1, point.$2);
          }
          writer.stroke();
        }
      case 'Line' || 'PolyLine' || 'Polygon':
        final line = annotation.line;
        final points = line == null
            ? annotation.vertices ?? const <(double, double)>[]
            : [line.$1, line.$2];
        if (points.isNotEmpty) {
          writer.moveTo(points.first.$1, points.first.$2);
          for (final point in points.skip(1)) {
            writer.lineTo(point.$1, point.$2);
          }
          if (annotation.subtype == 'Polygon') writer.closePath();
          if (annotation.subtype == 'Polygon' &&
              annotation.interiorColor != null) {
            writer.fillAndStroke();
          } else {
            writer.stroke();
          }
        }
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        final raw = document.cos.resolve(annotation.dict['QuadPoints']);
        if (raw is CosArray) {
          for (var i = 0; i + 7 < raw.length; i += 8) {
            final points = [
              for (var n = i; n < i + 8; n += 2)
                (
                  _number(document.cos.resolve(raw[n]), 0),
                  _number(document.cos.resolve(raw[n + 1]), 0)
                )
            ];
            if (annotation.subtype == 'Highlight') {
              writer
                ..extGState('PrintHighlight')
                ..moveTo(points[0].$1, points[0].$2)
                ..lineTo(points[1].$1, points[1].$2)
                ..lineTo(points[3].$1, points[3].$2)
                ..lineTo(points[2].$1, points[2].$2)
                ..closePath()
                ..fill();
            } else {
              final strike = annotation.subtype == 'StrikeOut';
              final from = strike
                  ? (
                      (points[0].$1 + points[2].$1) / 2,
                      (points[0].$2 + points[2].$2) / 2
                    )
                  : points[2];
              final to = strike
                  ? (
                      (points[1].$1 + points[3].$1) / 2,
                      (points[1].$2 + points[3].$2) / 2
                    )
                  : points[3];
              writer
                ..moveTo(from.$1, from.$2)
                ..lineTo(to.$1, to.$2)
                ..stroke();
            }
          }
        }
      case 'FreeText':
        _freeTextFallback(writer, annotation);
      case 'Widget':
        final widget = annotation is PdfWidgetAnnotation ? annotation : null;
        final text = widget?.fieldValue ?? annotation.contents ?? '';
        final size = math.min(12.0, math.max(1.0, r.height - 4));
        writer
          ..rect(r.left, r.bottom, r.width, r.height)
          ..clip()
          ..fillColor(color);
        if (widget?.fieldType == 'Btn') {
          writer
            ..rect(r.left + 0.5, r.bottom + 0.5, r.width - 1, r.height - 1)
            ..stroke();
          if (text.isNotEmpty && text != 'Off') {
            writer
              ..moveTo(r.left + 2, r.bottom + 2)
              ..lineTo(r.right - 2, r.top - 2)
              ..moveTo(r.left + 2, r.top - 2)
              ..lineTo(r.right - 2, r.bottom + 2)
              ..stroke();
          }
        } else if (text.isNotEmpty) {
          writer
            ..beginText()
            ..font('PrintFallback', size)
            ..textAt(r.left + 2, r.top - size - 2)
            ..leading(size * 1.2);
          var first = true;
          for (final line in text.split('\n')) {
            if (!first) writer.nextLine();
            writer.showText(line);
            first = false;
          }
          writer.endText();
        }
    }
    writer.restore();
  }

  void _freeTextFallback(ContentWriter writer, PdfAnnotation annotation) {
    final rect = annotation.calloutBox ?? annotation.rect;
    final style = annotation.freeTextStyle;
    final color = style?.color ?? 0x000000;
    final font = PdfStandardFont.fromName(style?.fontName ?? 'Helv');
    final size = (style?.fontSize ?? 12) > 0 ? style?.fontSize ?? 12 : 12.0;
    if (style?.fillColor case final fill?) {
      writer
        ..fillColor(fill)
        ..rect(rect.left, rect.bottom, rect.width, rect.height)
        ..fill();
    }
    final width = style?.borderWidth ?? 0;
    if (width > 0 && style?.borderColor != null) {
      writer
        ..strokeColor(style!.borderColor!)
        ..lineWidth(width)
        ..rect(rect.left + width / 2, rect.bottom + width / 2,
            rect.width - width, rect.height - width)
        ..stroke();
    }
    final callout = annotation.calloutLine;
    if (callout != null && callout.length >= 2) {
      writer
        ..strokeColor(style?.borderColor ?? color)
        ..moveTo(callout.first.$1, callout.first.$2);
      for (final point in callout.skip(1)) {
        writer.lineTo(point.$1, point.$2);
      }
      writer.stroke();
    }
    writer
      ..rect(rect.left, rect.bottom, rect.width, rect.height)
      ..clip()
      ..fillColor(color);
    final lines = <String>[];
    for (final paragraph in (annotation.contents ?? '').split('\n')) {
      var line = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty &&
            measureStandardText(candidate, size, font: font) > rect.width - 4) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      lines.add(line);
    }
    var y = rect.top - 2 - size * font.ascent;
    for (final line in lines) {
      final measured = measureStandardText(line, size, font: font);
      final x = switch (style?.alignment) {
        PdfTextAlign.center => rect.left + (rect.width - measured) / 2,
        PdfTextAlign.right => rect.right - 2 - measured,
        _ => rect.left + 2,
      };
      writer
        ..beginText()
        ..font(font.resourceName, size)
        ..textAt(x, y)
        ..showText(line)
        ..endText();
      y -= size * (style?.lineSpacing ?? 1.15);
    }
  }

  Uint8List finish(List<CosDictionary> sheets) {
    final pages = CosDictionary({'Type': const CosName('Pages')});
    final parent = builder.add(pages);
    pages['Kids'] = CosArray([
      for (final sheet in sheets)
        builder.add(CosDictionary({...sheet.entries, 'Parent': parent})),
    ]);
    pages['Count'] = CosInteger(sheets.length);
    return builder.build(
        root: builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': parent,
      if (_printOptionalContent() case final properties?)
        'OCProperties': properties,
      if (document.catalog['OutputIntents'] case final intents?)
        'OutputIntents': copier.copy(intents),
      'ViewerPreferences':
          CosDictionary({'PrintScaling': const CosName('None')}),
    })));
  }

  /// Resolve print usage once, then freeze that state for both the app's
  /// screen preview and the native print engine. Leaving /AS in the new
  /// catalog would let native printing switch layers after previewing them.
  CosObject? _printOptionalContent() {
    final cos = document.cos;
    final properties = cos.resolve(document.catalog['OCProperties']);
    if (properties is! CosDictionary) return null;
    final configuration = cos.resolve(properties['D']);
    final config =
        configuration is CosDictionary ? configuration : CosDictionary();
    List<CosDictionary> groups(CosObject? raw) {
      final array = cos.resolve(raw);
      if (array is! CosArray) return [];
      return [
        for (final item in array.items)
          if (cos.resolve(item) case final CosDictionary group) group
      ];
    }

    final base = cos.resolve(config['BaseState']) != const CosName('OFF');
    final states = Map<CosDictionary, bool>.identity();
    for (final group in groups(properties['OCGs'])) {
      states[group] = base;
    }
    for (final group in groups(config['ON'])) {
      states[group] = true;
    }
    for (final group in groups(config['OFF'])) {
      states[group] = false;
    }
    final applications = cos.resolve(config['AS']);
    if (applications is CosArray) {
      for (final application in applications.items) {
        final setting = cos.resolve(application);
        if (setting is! CosDictionary ||
            cos.resolve(setting['Event']) != const CosName('Print')) {
          continue;
        }
        final categories = cos.resolve(setting['Category']);
        if (categories is! CosArray ||
            !categories.items
                .any((value) => cos.resolve(value) == const CosName('Print'))) {
          continue;
        }
        final targets = setting.containsKey('OCGs')
            ? groups(setting['OCGs'])
            : states.keys.toList();
        for (final group in targets) {
          final usage = cos.resolve(group['Usage']);
          if (usage is! CosDictionary) continue;
          final print = cos.resolve(usage['Print']);
          if (print is! CosDictionary) continue;
          final state = cos.resolve(print['PrintState']);
          if (state == const CosName('ON')) states[group] = true;
          if (state == const CosName('OFF')) states[group] = false;
        }
      }
    }
    return CosDictionary({
      'OCGs': CosArray([for (final group in states.keys) copier.copy(group)]),
      'D': CosDictionary({
        'Name': CosString.fromText('Print'),
        'BaseState': const CosName('OFF'),
        'ON': CosArray([
          for (final entry in states.entries)
            if (entry.value) copier.copy(entry.key)
        ]),
        'OFF': CosArray([
          for (final entry in states.entries)
            if (!entry.value) copier.copy(entry.key)
        ]),
      }),
    });
  }
}

(int, int) _grid(int count, bool landscape) {
  var columns = math.sqrt(count).floor();
  var rows = (count / columns).ceil();
  if (landscape) (columns, rows) = (rows, columns);
  return (columns, rows);
}

typedef _SourceGeometry = ({double width, double height, PdfMatrix matrix});

_SourceGeometry _sourceGeometry(PdfPage page, PdfRect? requestedRegion) {
  final box = page.cropBox;
  final sideways = page.rotation == 90 || page.rotation == 270;
  final displayWidth = sideways ? box.height : box.width;
  final displayHeight = sideways ? box.width : box.height;
  final region = (requestedRegion ?? PdfRect(0, 0, displayWidth, displayHeight))
      .intersect(PdfRect(0, 0, displayWidth, displayHeight));
  if (region.width <= 0 || region.height <= 0) {
    throw ArgumentError('The print region does not intersect the page.');
  }
  final unit = _number(page.document.cos.resolve(page.dict['UserUnit']), 1);
  if (!unit.isFinite || unit <= 0 || unit > 75000) {
    throw ArgumentError('The page has an invalid UserUnit.');
  }
  final matrix = PdfMatrix.translation(-box.left, -box.bottom)
      .concat(_rotate(box.width, box.height, page.rotation ~/ 90))
      .concat(
          PdfMatrix.translation(-region.left, -(displayHeight - region.top)))
      .concat(PdfMatrix.scaled(unit, unit));
  return (
    width: region.width * unit,
    height: region.height * unit,
    matrix: matrix
  );
}

(double, double) _paperSize(
    double sourceWidth, double sourceHeight, PrintSettings settings) {
  final quarterTurn = settings.rotation == PrintRotation.clockwise90 ||
      settings.rotation == PrintRotation.clockwise270;
  var (width, height) = settings.paperSize.dimensions ??
      (quarterTurn ? (sourceHeight, sourceWidth) : (sourceWidth, sourceHeight));
  if ((settings.orientation == PrintOrientation.portrait && width > height) ||
      (settings.orientation == PrintOrientation.landscape && width < height)) {
    (width, height) = (height, width);
  }
  return (width, height);
}

double _margin(PrintSettings settings) => switch (settings.scaling) {
      PrintScaling.fitMargins ||
      PrintScaling.reduceMargins ||
      PrintScaling.multiple =>
        settings.margin,
      _ => 0,
    };

PdfMatrix _rotate(double width, double height, int turns) =>
    switch (turns % 4) {
      1 => PdfMatrix(0, -1, 1, 0, 0, width),
      2 => PdfMatrix(-1, 0, 0, -1, width, height),
      3 => PdfMatrix(0, 1, -1, 0, height, 0),
      _ => PdfMatrix.identity,
    };

void _concat(ContentWriter writer, PdfMatrix matrix) => writer.concatMatrix(
    matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f);

CosArray _rect(PdfRect rect) => CosArray([
      CosReal(rect.left),
      CosReal(rect.bottom),
      CosReal(rect.right),
      CosReal(rect.top),
    ]);

CosStream _stream(Uint8List bytes) =>
    CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes);

CosStream _form(PdfRect box, CosObject resources, Uint8List bytes,
        {bool isolate = false}) =>
    CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Form'),
          'BBox': _rect(box),
          'Resources': resources,
          'Length': CosInteger(bytes.length),
          if (isolate)
            'Group': CosDictionary({
              'S': const CosName('Transparency'),
              'I': const CosBoolean(true),
            }),
        }),
        bytes);

CosDictionary _alpha(double value) => CosDictionary({
      'Type': const CosName('ExtGState'),
      'ca': CosReal(value),
      'CA': CosReal(value),
    });

double _number(CosObject? value, double fallback) => switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => fallback,
    };

PdfMatrix _matrix(CosDocument cos, CosObject? value) {
  final row = cos.resolve(value);
  return row is CosArray && row.length >= 6
      ? PdfMatrix.row([
          for (var i = 0; i < 6; i++)
            _number(cos.resolve(row[i]), i == 0 || i == 3 ? 1 : 0),
        ])
      : PdfMatrix.identity;
}

/// Copies only resources reachable from printed content. In particular /P,
/// /Parent and other references into the source page tree cannot drag entire
/// unselected documents into a one-sheet preview. Source stream compression
/// and byte views survive; encrypted payloads are decrypted without decoding.
class _ObjectCopier {
  _ObjectCopier(this.source, this.builder);
  final CosDocument source;
  final CosDocumentBuilder builder;
  final Map<CosObject, CosObject> _copies = Map.identity();
  final _references = <CosReference, CosObject>{};

  CosObject copy(CosObject value) {
    if (value is CosReference) {
      final previous = _references[value];
      if (previous != null) return previous;
      final resolved = source.resolve(value);
      // Resource graphs may contain legal reference cycles. Register the
      // destination dictionary before copying its children.
      return _references[value] = copy(resolved);
    }
    final previous = _copies[value];
    if (previous != null) return previous;
    switch (value) {
      case CosStream stream:
        final filter = source.resolve(stream.dictionary['Filter']);
        final filters = filter is CosArray
            ? filter.items.map(source.resolve).toList()
            : <CosObject>[if (filter is CosName) filter];
        final firstFilter = filters.whereType<CosName>().firstOrNull?.value;
        final bytes = source.isEncrypted
            ? source.decodeStreamData(stream, stopBeforeFilter: firstFilter)
            : stream.rawBytes;
        final output = _stream(bytes);
        final reference = builder.add(output);
        _copies[value] = reference;
        for (final entry in stream.dictionary.entries.entries) {
          if (entry.key != 'Length') {
            output.dictionary[entry.key] = copy(entry.value);
          }
        }
        // Crypt filters belong to the source document's security handler.
        if (filters.contains(const CosName('Crypt'))) {
          final kept = [
            for (var i = 0; i < filters.length; i++)
              if (filters[i] != const CosName('Crypt')) i
          ];
          output.dictionary.entries.remove('Filter');
          output.dictionary.entries.remove('DecodeParms');
          if (kept.isNotEmpty) {
            output.dictionary['Filter'] =
                CosArray([for (final i in kept) copy(filters[i])]);
            final parameters = source.resolve(stream.dictionary['DecodeParms']);
            if (parameters is CosArray) {
              output.dictionary['DecodeParms'] = CosArray([
                for (final i in kept)
                  i < parameters.length
                      ? copy(parameters[i])
                      : CosNull.instance,
              ]);
            }
          }
        }
        return reference;
      case CosDictionary dictionary:
        if (dictionary.typeName == 'Page' || dictionary.typeName == 'Pages') {
          return CosNull.instance;
        }
        final output = CosDictionary();
        final reference = builder.add(output);
        _copies[value] = reference;
        for (final entry in dictionary.entries.entries) {
          // The prepared catalog has already frozen the print layer state.
          // Source usage/intent must not let a native backend override it.
          if (dictionary.typeName == 'OCG' &&
              (entry.key == 'Usage' || entry.key == 'Intent')) {
            continue;
          }
          output[entry.key] = copy(entry.value);
        }
        return reference;
      case CosArray array:
        final output = CosArray([]);
        final reference = builder.add(output);
        _copies[value] = reference;
        output.items.addAll(array.items.map(copy));
        return reference;
      case CosString string:
        return CosString(Uint8List.fromList(string.bytes), isHex: string.isHex);
      default:
        return value;
    }
  }
}

import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Version of the JSON contract returned by all DartPDF read operations.
const dartPdfJsonSchemaVersion = 1;

/// Hard result bounds shared by CLI and MCP transports.
class DartPdfLimits {
  const DartPdfLimits({
    this.maxPages = 50,
    this.maxTextCharsPerPage = 100000,
    this.maxTextChars = 500000,
    this.maxFields = 1000,
    this.maxAnnotations = 1000,
    this.maxAnnotationTextChars = 20000,
  })  : assert(maxPages > 0),
        assert(maxTextCharsPerPage > 0),
        assert(maxTextChars > 0),
        assert(maxFields > 0),
        assert(maxAnnotations > 0),
        assert(maxAnnotationTextChars > 0);

  final int maxPages;
  final int maxTextCharsPerPage;
  final int maxTextChars;
  final int maxFields;
  final int maxAnnotations;
  final int maxAnnotationTextChars;
}

/// Invalid page selection or request that exceeds a configured result bound.
class DartPdfRequestException implements Exception {
  const DartPdfRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A parsed, one-based CLI page range resolved to zero-based page indices.
class DartPdfPageSelection {
  const DartPdfPageSelection({
    required this.indices,
    required this.truncated,
  });

  final List<int> indices;
  final bool truncated;

  /// Parses comma-separated pages and inclusive ranges such as `1-3,7`.
  ///
  /// A missing [specification] selects the first [maxPages] pages and reports
  /// [truncated] when the document contains more. Explicit selections that
  /// exceed [maxPages] are rejected rather than silently changing the request.
  factory DartPdfPageSelection.parse(
    String? specification, {
    required int pageCount,
    required int maxPages,
  }) {
    if (maxPages <= 0) {
      throw const DartPdfRequestException('maxPages must be positive');
    }
    final spec = specification?.trim() ?? '';
    if (spec.isEmpty) {
      final count = pageCount < maxPages ? pageCount : maxPages;
      return DartPdfPageSelection(
        indices: List<int>.generate(count, (index) => index),
        truncated: pageCount > count,
      );
    }

    final indices = <int>[];
    final seen = <int>{};
    for (final rawPart in spec.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) {
        throw DartPdfRequestException('invalid page range "$spec"');
      }
      final dash = part.indexOf('-');
      final int start;
      final int end;
      if (dash < 0) {
        start = _parsePage(part, spec);
        end = start;
      } else {
        if (part.indexOf('-', dash + 1) >= 0) {
          throw DartPdfRequestException('invalid page range "$spec"');
        }
        start = _parsePage(part.substring(0, dash).trim(), spec);
        end = _parsePage(part.substring(dash + 1).trim(), spec);
        if (end < start) {
          throw DartPdfRequestException(
              'descending page range "$part" is not supported');
        }
      }
      if (start > pageCount || end > pageCount) {
        throw DartPdfRequestException(
            'page range "$part" exceeds document page count $pageCount');
      }
      for (var page = start; page <= end; page++) {
        final index = page - 1;
        if (seen.add(index)) indices.add(index);
        if (indices.length > maxPages) {
          throw DartPdfRequestException(
              'page selection exceeds the $maxPages-page limit');
        }
      }
    }
    return DartPdfPageSelection(indices: indices, truncated: false);
  }

  static int _parsePage(String value, String wholeSpec) {
    final page = int.tryParse(value);
    if (page == null || page < 1) {
      throw DartPdfRequestException('invalid page range "$wholeSpec"');
    }
    return page;
  }
}

/// Opens bytes once and exposes the read-only operations shared by transports.
class DartPdfService {
  const DartPdfService({this.limits = const DartPdfLimits()});

  final DartPdfLimits limits;

  DartPdfDocument open(Uint8List bytes, {String password = ''}) =>
      DartPdfDocument._(PdfDocument.open(bytes, password: password), limits);
}

/// One open PDF document and the stable JSON-producing command handlers.
class DartPdfDocument {
  DartPdfDocument._(this.document, this.limits);

  final PdfDocument document;
  final DartPdfLimits limits;

  Map<String, Object?> inspect() {
    final form = PdfAcroForm.of(document);
    final signatures = PdfSignature.of(document);
    var annotationCount = 0;
    final annotationTypes = <String, int>{};
    for (var pageIndex = 0; pageIndex < document.pageCount; pageIndex++) {
      for (final annotation in document.page(pageIndex).annotations) {
        annotationCount++;
        annotationTypes.update(annotation.subtype, (count) => count + 1,
            ifAbsent: () => 1);
      }
    }

    return _result('inspect', {
      'version': document.version,
      'metadata': document.info,
      'pageCount': document.pageCount,
      'encrypted': document.cos.isEncrypted,
      'forms': {
        'present': form != null,
        'fieldCount': form?.fields.length ?? 0,
      },
      'annotations': {
        'count': annotationCount,
        'bySubtype': annotationTypes,
      },
      'signatures': {
        'signed': signatures.isNotEmpty,
        'count': signatures.length,
        'items': [
          for (final signature in signatures)
            {
              'field': signature.field.name,
              if (signature.signerName != null) 'signer': signature.signerName,
              if (signature.subFilter != null) 'subFilter': signature.subFilter,
              if (signature.signingTime != null)
                'signingTime': signature.signingTime!.toIso8601String(),
              'documentTimestamp': signature.isDocumentTimeStamp,
            },
        ],
      },
    });
  }

  Map<String, Object?> extractText({String? pages}) {
    final selection = DartPdfPageSelection.parse(
      pages,
      pageCount: document.pageCount,
      maxPages: limits.maxPages,
    );
    final output = <Map<String, Object?>>[];
    var remaining = limits.maxTextChars;
    var truncated = selection.truncated;
    for (final pageIndex in selection.indices) {
      if (remaining <= 0) {
        truncated = true;
        break;
      }
      final extracted = PdfTextExtractor.reflowPage(document, pageIndex).text;
      final pageLimit = remaining < limits.maxTextCharsPerPage
          ? remaining
          : limits.maxTextCharsPerPage;
      final take = extracted.length < pageLimit ? extracted.length : pageLimit;
      final pageTruncated = take < extracted.length;
      output.add({
        'page': pageIndex + 1,
        'text': extracted.substring(0, take),
        'characters': take,
        if (pageTruncated) 'truncated': true,
      });
      remaining -= take;
      truncated = truncated || pageTruncated;
    }
    if (output.length < selection.indices.length) truncated = true;

    return _result('text', {
      'pageCount': document.pageCount,
      'selectedPages': [for (final index in selection.indices) index + 1],
      'returnedPages': output.length,
      'characters': limits.maxTextChars - remaining,
      'truncated': truncated,
      'pages': output,
    });
  }

  Map<String, Object?> listForms() {
    final form = PdfAcroForm.of(document);
    final fields = form?.fields ?? const <PdfFormField>[];
    final take =
        fields.length < limits.maxFields ? fields.length : limits.maxFields;
    return _result('forms.list', {
      'present': form != null,
      'total': fields.length,
      'returned': take,
      'truncated': take < fields.length,
      'fields': [
        for (final field in fields.take(take)) _fieldJson(field),
      ],
    });
  }

  Map<String, Object?> listAnnotations({String? pages}) {
    final selection = DartPdfPageSelection.parse(
      pages,
      pageCount: document.pageCount,
      maxPages: limits.maxPages,
    );
    final annotations = <Map<String, Object?>>[];
    var total = 0;
    var textBudget = limits.maxAnnotationTextChars;
    var textTruncated = false;
    for (final pageIndex in selection.indices) {
      for (final annotation in document.page(pageIndex).annotations) {
        total++;
        if (annotations.length >= limits.maxAnnotations) continue;
        final item = <String, Object?>{
          'page': pageIndex + 1,
          'subtype': annotation.subtype,
          'rect': _rectJson(annotation.rect),
          'flags': annotation.flags,
          'hidden': annotation.isHidden,
          'noView': annotation.isNoView,
          'readOnly': annotation.isReadOnly,
          'locked': annotation.isLocked,
        };
        void addBoundedText(String key, String? value) {
          if (value == null) return;
          final take = value.length < textBudget ? value.length : textBudget;
          item[key] = value.substring(0, take);
          if (take < value.length) {
            item['${key}Truncated'] = true;
            textTruncated = true;
          }
          textBudget -= take;
        }

        addBoundedText('name', annotation.name);
        addBoundedText('author', annotation.author);
        addBoundedText('contents', annotation.contents);
        annotations.add(item);
      }
    }
    return _result('annotations.list', {
      'pageCount': document.pageCount,
      'selectedPages': [for (final index in selection.indices) index + 1],
      'total': total,
      'returned': annotations.length,
      'truncated':
          selection.truncated || annotations.length < total || textTruncated,
      'annotations': annotations,
    });
  }

  Map<String, Object?> _fieldJson(PdfFormField field) {
    final widgets = <Map<String, Object?>>[];
    for (var index = 0; index < field.widgets.length; index++) {
      final rect = field.widgetRect(index);
      final pageIndex = field.widgetPageIndex(index);
      widgets.add({
        'page': pageIndex < 0 ? null : pageIndex + 1,
        if (rect != null) 'rect': _rectJson(rect),
        if (field.widgetOnState(index) != null)
          'onState': field.widgetOnState(index),
      });
    }
    return {
      'name': field.name,
      'type': field.type.name,
      if (!field.isPassword && field.value != null) 'value': field.value,
      if (field.isPassword && field.value != null) 'valueRedacted': true,
      'readOnly': field.isReadOnly,
      'required': field.isRequired,
      if (field.type == PdfFieldType.text) 'multiline': field.isMultiline,
      if (field.options.isNotEmpty)
        'options': [
          for (final option in field.options)
            {'value': option.$1, 'label': option.$2},
        ],
      'widgets': widgets,
    };
  }

  Map<String, Object?> _result(String operation, Map<String, Object?> data) => {
        'schemaVersion': dartPdfJsonSchemaVersion,
        'operation': operation,
        ...data,
      };

  static List<double> _rectJson(PdfRect rect) => [
        rect.left,
        rect.bottom,
        rect.right,
        rect.top,
      ];
}

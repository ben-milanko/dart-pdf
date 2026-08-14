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
    this.maxInspectMetadataEntries = 100,
    this.maxInspectSignatures = 100,
    this.maxInspectAnnotationSubtypes = 100,
    this.maxInspectTextChars = 100000,
    this.maxFields = 1000,
    this.maxFormWidgets = 2000,
    this.maxFormOptions = 5000,
    this.maxFormTextChars = 200000,
    this.maxAnnotations = 1000,
    this.maxAnnotationTextChars = 20000,
  })  : assert(maxPages > 0),
        assert(maxTextCharsPerPage > 0),
        assert(maxTextChars > 0),
        assert(maxInspectMetadataEntries > 0),
        assert(maxInspectSignatures > 0),
        assert(maxInspectAnnotationSubtypes > 0),
        assert(maxInspectTextChars > 0),
        assert(maxFields > 0),
        assert(maxFormWidgets > 0),
        assert(maxFormOptions > 0),
        assert(maxFormTextChars > 0),
        assert(maxAnnotations > 0),
        assert(maxAnnotationTextChars > 0);

  final int maxPages;
  final int maxTextCharsPerPage;
  final int maxTextChars;
  final int maxInspectMetadataEntries;
  final int maxInspectSignatures;
  final int maxInspectAnnotationSubtypes;
  final int maxInspectTextChars;
  final int maxFields;
  final int maxFormWidgets;
  final int maxFormOptions;
  final int maxFormTextChars;
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
    final textBudget = _TextBudget(limits.maxInspectTextChars);
    final metadata = <String, String>{};
    var metadataTruncated = false;
    var metadataSeen = 0;
    for (final entry in document.info.entries) {
      if (metadataSeen >= limits.maxInspectMetadataEntries ||
          textBudget.remaining == 0) {
        metadataTruncated = true;
        textBudget.markTruncated();
        break;
      }
      metadataSeen++;
      // Metadata keys become JSON object keys, so do not truncate them into a
      // collision. Omit an oversized key and report the compact result as
      // truncated instead.
      if (!textBudget.canTake(entry.key)) {
        metadataTruncated = true;
        textBudget.markTruncated();
        continue;
      }
      final key = textBudget.take(entry.key);
      final value = textBudget.take(entry.value);
      metadata[key] = value;
      if (value.length < entry.value.length) metadataTruncated = true;
    }

    var annotationCount = 0;
    var otherAnnotationSubtypeCount = 0;
    final annotationTypes = <String, int>{};
    for (var pageIndex = 0; pageIndex < document.pageCount; pageIndex++) {
      for (final annotation in document.page(pageIndex).annotations) {
        annotationCount++;
        final subtype = annotation.subtype;
        final existing = annotationTypes[subtype];
        if (existing != null) {
          annotationTypes[subtype] = existing + 1;
        } else if (annotationTypes.length <
                limits.maxInspectAnnotationSubtypes &&
            textBudget.canTake(subtype)) {
          annotationTypes[textBudget.take(subtype)] = 1;
        } else {
          otherAnnotationSubtypeCount++;
          textBudget.markTruncated();
        }
      }
    }

    final signatureItems = <Map<String, Object?>>[];
    final signatureTake = signatures.length < limits.maxInspectSignatures
        ? signatures.length
        : limits.maxInspectSignatures;
    for (final signature in signatures.take(signatureTake)) {
      final item = <String, Object?>{
        'documentTimestamp': signature.isDocumentTimeStamp,
      };
      textBudget.add(item, 'field', signature.field.name);
      textBudget.add(item, 'signer', signature.signerName);
      textBudget.add(item, 'subFilter', signature.subFilter);
      if (signature.signingTime != null) {
        item['signingTime'] = signature.signingTime!.toIso8601String();
      }
      signatureItems.add(item);
    }
    final signaturesTruncated = signatureTake < signatures.length;

    return _result('inspect', {
      'version': document.version,
      'metadata': metadata,
      if (metadataTruncated) 'metadataTruncated': true,
      'pageCount': document.pageCount,
      'encrypted': document.cos.isEncrypted,
      'forms': {
        'present': form != null,
        'fieldCount': form?.fields.length ?? 0,
      },
      'annotations': {
        'count': annotationCount,
        'bySubtype': annotationTypes,
        if (otherAnnotationSubtypeCount > 0)
          'otherSubtypeCount': otherAnnotationSubtypeCount,
        if (otherAnnotationSubtypeCount > 0) 'subtypesTruncated': true,
      },
      'signatures': {
        'signed': signatures.isNotEmpty,
        'count': signatures.length,
        'items': signatureItems,
        if (signaturesTruncated) 'truncated': true,
      },
      if (metadataTruncated ||
          otherAnnotationSubtypeCount > 0 ||
          signaturesTruncated ||
          textBudget.truncated)
        'truncated': true,
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
      final take = _safePrefixLength(extracted, pageLimit);
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
    final budget = _FormBudget(limits);
    final output = <Map<String, Object?>>[];
    for (final field in fields.take(take)) {
      output.add(_fieldJson(field, budget));
    }
    return _result('forms.list', {
      'present': form != null,
      'total': fields.length,
      'returned': take,
      'truncated': take < fields.length || budget.truncated,
      'fields': output,
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
    final textBudget = _TextBudget(limits.maxAnnotationTextChars);
    for (final pageIndex in selection.indices) {
      for (final annotation in document.page(pageIndex).annotations) {
        total++;
        if (annotations.length >= limits.maxAnnotations) continue;
        final item = <String, Object?>{
          'page': pageIndex + 1,
          'rect': _rectJson(annotation.rect),
          'flags': annotation.flags,
          'hidden': annotation.isHidden,
          'noView': annotation.isNoView,
          'readOnly': annotation.isReadOnly,
          'locked': annotation.isLocked,
        };
        textBudget.add(item, 'subtype', annotation.subtype);
        textBudget.add(item, 'name', annotation.name);
        textBudget.add(item, 'author', annotation.author);
        textBudget.add(item, 'contents', annotation.contents);
        annotations.add(item);
      }
    }
    return _result('annotations.list', {
      'pageCount': document.pageCount,
      'selectedPages': [for (final index in selection.indices) index + 1],
      'total': total,
      'returned': annotations.length,
      'truncated': selection.truncated ||
          annotations.length < total ||
          textBudget.truncated,
      'annotations': annotations,
    });
  }

  Map<String, Object?> _fieldJson(PdfFormField field, _FormBudget budget) {
    final item = <String, Object?>{
      'type': field.type.name,
      'readOnly': field.isReadOnly,
      'required': field.isRequired,
      if (field.type == PdfFieldType.text) 'multiline': field.isMultiline,
    };
    budget.text.add(item, 'name', field.name);
    if (!field.isPassword) budget.text.add(item, 'value', field.value);
    if (field.isPassword && field.value != null) item['valueRedacted'] = true;

    final options = field.options;
    if (options.isNotEmpty) {
      final take = options.length < budget.optionsRemaining
          ? options.length
          : budget.optionsRemaining;
      item['options'] = [
        for (final option in options.take(take))
          budget.optionJson(option.$1, option.$2),
      ];
      budget.optionsRemaining -= take;
      if (take < options.length) {
        item['optionsTruncated'] = true;
        budget.markTruncated();
      }
    }

    final widgets = <Map<String, Object?>>[];
    final widgetTake = field.widgets.length < budget.widgetsRemaining
        ? field.widgets.length
        : budget.widgetsRemaining;
    for (var index = 0; index < widgetTake; index++) {
      final rect = field.widgetRect(index);
      final pageIndex = field.widgetPageIndex(index);
      final widget = <String, Object?>{
        'page': pageIndex < 0 ? null : pageIndex + 1,
        if (rect != null) 'rect': _rectJson(rect),
      };
      budget.text.add(widget, 'onState', field.widgetOnState(index));
      widgets.add(widget);
    }
    budget.widgetsRemaining -= widgetTake;
    if (widgetTake < field.widgets.length) {
      item['widgetsTruncated'] = true;
      budget.markTruncated();
    }
    item['widgets'] = widgets;
    return item;
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

class _TextBudget {
  _TextBudget(this.remaining);

  int remaining;
  bool truncated = false;

  bool canTake(String value) => value.length <= remaining;

  String take(String value) {
    final length = _safePrefixLength(value, remaining);
    final result = value.substring(0, length);
    remaining -= length;
    if (length < value.length) truncated = true;
    return result;
  }

  void add(Map<String, Object?> output, String key, String? value) {
    if (value == null) return;
    final bounded = take(value);
    output[key] = bounded;
    if (bounded.length < value.length) output['${key}Truncated'] = true;
  }

  void markTruncated() => truncated = true;
}

class _FormBudget {
  _FormBudget(DartPdfLimits limits)
      : text = _TextBudget(limits.maxFormTextChars),
        widgetsRemaining = limits.maxFormWidgets,
        optionsRemaining = limits.maxFormOptions;

  final _TextBudget text;
  int widgetsRemaining;
  int optionsRemaining;
  bool _collectionTruncated = false;

  bool get truncated => _collectionTruncated || text.truncated;

  Map<String, Object?> optionJson(String value, String label) {
    final output = <String, Object?>{};
    text.add(output, 'value', value);
    text.add(output, 'label', label);
    return output;
  }

  void markTruncated() => _collectionTruncated = true;
}

int _safePrefixLength(String value, int maximum) {
  var length = value.length < maximum ? value.length : maximum;
  if (length > 0 && length < value.length) {
    final last = value.codeUnitAt(length - 1);
    final next = value.codeUnitAt(length);
    if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      length--;
    }
  }
  return length;
}

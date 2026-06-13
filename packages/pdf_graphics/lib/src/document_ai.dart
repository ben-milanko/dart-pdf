import 'package:pdf_document/pdf_document.dart';

import 'text_extraction.dart';

/// One page's textual content and geometry, for [PdfDocumentContext].
class PdfPageContext {
  const PdfPageContext({
    required this.pageIndex,
    required this.text,
    required this.width,
    required this.height,
  });

  final int pageIndex;

  /// The page's extracted text in reading order (empty for image-only
  /// pages that have no text layer — run OCR first; see `PdfOcrEditing`).
  final String text;

  /// Crop-box size in PDF points.
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
        'page': pageIndex,
        'width': width,
        'height': height,
        'text': text,
      };
}

/// One interactive form field, flattened for an agent.
class PdfFieldContext {
  const PdfFieldContext({
    required this.name,
    required this.type,
    required this.value,
    required this.pageIndex,
  });

  /// Fully qualified field name — the stable handle for setting a value.
  final String name;

  /// Field kind ('text', 'checkBox', 'comboBox', ...).
  final String type;

  /// Current value, if any.
  final String? value;

  /// Page showing the field's first widget, or −1 when unplaced.
  final int pageIndex;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type,
        if (value != null) 'value': value,
        'page': pageIndex,
      };
}

/// One annotation summarized for an agent.
class PdfAnnotationContext {
  const PdfAnnotationContext({
    required this.pageIndex,
    required this.subtype,
    required this.rect,
    this.contents,
    this.author,
  });

  final int pageIndex;

  /// The /Subtype name ('Highlight', 'FreeText', 'Link', ...).
  final String subtype;

  final PdfRect rect;
  final String? contents;
  final String? author;

  Map<String, Object?> toJson() => {
        'page': pageIndex,
        'subtype': subtype,
        'rect': [rect.left, rect.bottom, rect.right, rect.top],
        if (contents != null) 'contents': contents,
        if (author != null) 'author': author,
      };
}

/// A clean, serializable snapshot of a document's text and interactive
/// structure, shaped for handing to a language model.
///
/// This is the *read* half of the Document-AI seam: a thin adapter over the
/// library's existing extraction surface ([PdfTextExtractor], [PdfAcroForm],
/// [PdfPage.annotations]) that produces something an LLM can reason over.
/// The model and transport are host-supplied — dart-pdf does not embed an
/// agent. The *write* half (an agent driving edits) is the host-implemented
/// [PdfDocumentActionSink], which maps onto the existing editing APIs
/// (`PdfEditor`, the editing controller).
class PdfDocumentContext {
  const PdfDocumentContext({
    required this.pages,
    required this.fields,
    required this.annotations,
  });

  final List<PdfPageContext> pages;
  final List<PdfFieldContext> fields;
  final List<PdfAnnotationContext> annotations;

  /// Gathers context from [document]: per-page text (via [PdfTextExtractor]
  /// reflow, so it reads in paragraph order), every form field with its
  /// current value, and a summary of every annotation.
  ///
  /// Set [includeText] false to skip text extraction (which interprets each
  /// page) when only the form/annotation structure is needed.
  factory PdfDocumentContext.of(PdfDocument document,
      {bool includeText = true}) {
    final pages = <PdfPageContext>[];
    for (var i = 0; i < document.pageCount; i++) {
      final box = document.page(i).cropBox;
      pages.add(PdfPageContext(
        pageIndex: i,
        text: includeText ? PdfTextExtractor.reflowPage(document, i).text : '',
        width: box.width,
        height: box.height,
      ));
    }

    final form = PdfAcroForm.of(document);
    final fields = <PdfFieldContext>[
      if (form != null)
        for (final field in form.fields)
          PdfFieldContext(
            name: field.name,
            type: field.type.name,
            value: field.value,
            pageIndex: field.widgetPageIndex(0),
          ),
    ];

    final annotations = <PdfAnnotationContext>[];
    for (var i = 0; i < document.pageCount; i++) {
      for (final annotation in document.page(i).annotations) {
        annotations.add(PdfAnnotationContext(
          pageIndex: i,
          subtype: annotation.subtype,
          rect: annotation.rect,
          contents: annotation.contents,
          author: annotation.author,
        ));
      }
    }

    return PdfDocumentContext(
        pages: pages, fields: fields, annotations: annotations);
  }

  /// A plain-text rendering suitable for a prompt: each page's text under a
  /// header, then a compact listing of fields and annotations.
  String toPromptText() {
    final buffer = StringBuffer();
    for (final page in pages) {
      buffer
        ..writeln('--- Page ${page.pageIndex + 1} '
            '(${page.width.round()}×${page.height.round()} pt) ---')
        ..writeln(page.text.isEmpty ? '[no text layer]' : page.text)
        ..writeln();
    }
    if (fields.isNotEmpty) {
      buffer.writeln('Form fields:');
      for (final field in fields) {
        buffer.writeln(
            '  ${field.name} (${field.type}) = ${field.value ?? ''}');
      }
      buffer.writeln();
    }
    if (annotations.isNotEmpty) {
      buffer.writeln('Annotations:');
      for (final annotation in annotations) {
        buffer.writeln('  p${annotation.pageIndex + 1} ${annotation.subtype}'
            '${annotation.contents == null ? '' : ': ${annotation.contents}'}');
      }
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
        'pages': [for (final page in pages) page.toJson()],
        'fields': [for (final field in fields) field.toJson()],
        'annotations': [for (final a in annotations) a.toJson()],
      };
}

/// The *write* half of the Document-AI seam: the editing actions an agent
/// can drive, decoupled from any particular model or transport.
///
/// **This is an interface stub, host-provided.** dart-pdf does not ship an
/// agent. A host implements this over the existing editing surface (a
/// `PdfEditor`, or the editing controller in dart_pdf_editor) and wires it
/// to whatever model loop it runs — the model proposes actions against a
/// [PdfDocumentContext], the host validates them and calls these methods.
///
/// Implementations decide their own persistence (incremental save, undo
/// stack) and may reject or clamp out-of-range requests.
abstract class PdfDocumentActionSink {
  /// Sets the value of the form field named [fieldName]
  /// (maps to `PdfFormEditing.setTextValue` / checkbox / choice setters).
  void setFormFieldValue(String fieldName, String value);

  /// Adds a free-text annotation with [text] at [rect] on page [pageIndex]
  /// (maps to `PdfAnnotationEditing.addFreeText`).
  void addTextNote(int pageIndex, PdfRect rect, String text);

  /// Highlights the text spanning characters `[start, end)` of page
  /// [pageIndex]'s extracted text (maps to a markup annotation over the
  /// quads from [PdfPageText.quadsFor]).
  void highlightText(int pageIndex, int start, int end);
}

part of 'editor.dart';

/// The file formats Acrobat exchanges form data and comments in, plus PDF
/// itself - what [pdfSniffExchangeFormat] tells apart.
enum PdfExchangeFormat {
  /// A PDF document (`%PDF-`).
  pdf,

  /// Forms Data Format (§12.7.8): PDF object syntax under an `%FDF-`
  /// header, carrying /Fields values and/or /Annots.
  fdf,

  /// XML Forms Data Format (ISO 19444-1): the XML twin of FDF.
  xfdf,

  /// XML Data Package: an XFA form's packets (datasets, template, ...) with
  /// the PDF itself embedded as base64 or referenced by /href.
  xdp,
}

/// Identifies [bytes] as a PDF, FDF, XFDF, or XDP file from its header or
/// XML root element, or null when it is none of them.
///
/// Only the first few kilobytes are read; nothing is parsed or validated,
/// so a hit only says which reader to hand the bytes to.
PdfExchangeFormat? pdfSniffExchangeFormat(Uint8List bytes) {
  final limit = math.min(bytes.length, 4096);
  final head = latin1.decode(Uint8List.sublistView(bytes, 0, limit));
  // a header near the front, like the PDF reader's own junk tolerance
  final fdf = head.indexOf('%FDF-');
  final pdf = head.indexOf('%PDF-');
  if (fdf >= 0 && fdf < 1024 && (pdf < 0 || fdf < pdf)) {
    return PdfExchangeFormat.fdf;
  }
  if (pdf >= 0 && pdf < 1024) return PdfExchangeFormat.pdf;
  // XML: the first element that isn't a declaration, PI, comment or DTD
  var i = 0;
  while (true) {
    i = head.indexOf('<', i);
    if (i < 0 || i + 1 >= head.length) return null;
    final next = head.codeUnitAt(i + 1);
    if (next == 0x3F /* ? */ || next == 0x21 /* ! */) {
      i++;
      continue;
    }
    final match = _xmlRootNameRe.matchAsPrefix(head, i + 1);
    if (match == null) return null;
    return switch (match.group(2)) {
      'xfdf' => PdfExchangeFormat.xfdf,
      'xdp' => PdfExchangeFormat.xdp,
      _ => null,
    };
  }
}

final RegExp _xmlRootNameRe =
    RegExp(r'([A-Za-z_][\w.\-]*:)?([A-Za-z_][\w.\-]*)');

/// One form field value as an exchange file carries it.
class PdfFormDataField {
  const PdfFormDataField(this.name, this.values, {this.isState = false});

  /// The fully qualified field name (`parent.child`).
  final String name;

  /// The value(s): one entry for most fields, several for a multi-select
  /// list box. An empty string clears the field; an empty list means the
  /// file named the field without giving it a value, and importing leaves
  /// it alone.
  final List<String> values;

  /// Whether the value is a button state name (FDF writes it as a /Name,
  /// like a check box's `Yes` or `Off`) rather than text.
  final bool isState;

  /// The first value, or null when the file gave none.
  String? get value => values.isEmpty ? null : values.first;

  @override
  String toString() => 'PdfFormDataField($name: $values)';
}

/// One comment (markup annotation) as an exchange file carries it.
///
/// The annotation dictionary is detached - no indirect references, its
/// appearance streams (when the file had them) held inline - so it can be
/// written to another format or pasted into any document.
class PdfExchangeAnnotation {
  PdfExchangeAnnotation._(this.pageIndex, this._dict, {this.inReplyTo});

  /// The zero-based page the annotation belongs on.
  final int pageIndex;

  final CosDictionary _dict;

  /// The /NM of the annotation this one replies to, when it is a reply.
  final String? inReplyTo;

  /// The /Subtype name ('Highlight', 'Square', 'Text', ...).
  String get subtype => switch (_dict['Subtype']) {
        CosName(:final value) => value,
        _ => '',
      };

  /// The /NM unique name, when the file gave one.
  String? get name => _text('NM');

  /// The /Contents text.
  String? get contents => _text('Contents');

  /// The /T author.
  String? get author => _text('T');

  /// The /Rect in page space, or null when malformed.
  PdfRect? get rect => _rectOf(_dict['Rect']);

  /// Whether the file carried a ready-made appearance (/AP). Without one,
  /// importing generates it for the subtypes the editor can draw.
  bool get hasAppearance => _dict['AP'] is CosDictionary;

  String? _text(String key) => switch (_dict[key]) {
        CosString string => string.text,
        _ => null,
      };

  @override
  String toString() => 'PdfExchangeAnnotation($subtype, page $pageIndex)';
}

/// Form field values and comments read from, or bound for, an FDF, XFDF or
/// XDP file - the hub every exchange format converts through.
///
/// Read a file with [parse] (any of the three, sniffed) or the format's own
/// reader, apply it with [PdfFormDataExchange.importFormData]; capture a
/// document with [PdfFormData.of] and write it with [toFdf] or [toXfdf].
/// Because both directions go through this model, an FDF can be converted
/// to XFDF (and back) without a PDF in between.
class PdfFormData {
  PdfFormData({
    this.fields = const [],
    this.annotations = const [],
    this.targetFile,
    this.documentIds,
  });

  /// Field values, in file order.
  final List<PdfFormDataField> fields;

  /// Comments, in file order.
  final List<PdfExchangeAnnotation> annotations;

  /// The PDF the data belongs to: FDF /F, XFDF `<f href>`. Usually a file
  /// name relative to the data file.
  final String? targetFile;

  /// The target document's file identifiers (FDF /ID, XFDF `<ids>`):
  /// permanent then changing, as in the PDF trailer's /ID.
  final List<Uint8List>? documentIds;

  /// Reads an FDF, XFDF or XDP file, picking the reader by
  /// [pdfSniffExchangeFormat]. An XDP yields its datasets mapped onto field
  /// names only when they can't be matched to a document - prefer
  /// [PdfXdpPackage] for XDP. Throws [FormatException] for anything else.
  static PdfFormData parse(Uint8List bytes) =>
      switch (pdfSniffExchangeFormat(bytes)) {
        PdfExchangeFormat.fdf => parseFdf(bytes),
        PdfExchangeFormat.xfdf => parseXfdf(bytes),
        PdfExchangeFormat.xdp => PdfXdpPackage.parse(bytes).toFormData(),
        _ => throw const FormatException('not an FDF, XFDF or XDP file'),
      };

  /// Reads an FDF file. Lenient like the PDF reader: a missing or broken
  /// cross-reference table is rebuilt by scanning for objects. Throws
  /// [FormatException] when there is no FDF dictionary to read.
  static PdfFormData parseFdf(Uint8List bytes) => _readFdf(bytes);

  /// Reads an XFDF file. Throws [FormatException] on malformed XML or a
  /// root that isn't `<xfdf>`.
  static PdfFormData parseXfdf(Uint8List bytes) {
    final XmlLiteDocument xml;
    try {
      xml = XmlLiteDocument.parse(bytes);
    } on FormatException catch (e) {
      throw FormatException('malformed XFDF: ${e.message}');
    }
    if (xml.root.localName != 'xfdf') {
      throw FormatException('not XFDF: root is <${xml.root.qname}>');
    }
    return _readXfdf(xml.root);
  }

  /// Captures [document]'s form field values ([fields]) and comments
  /// ([annotations]) for export, the way Acrobat's Export Data / Export
  /// Comments does.
  ///
  /// Push buttons and signature fields carry no exchangeable value and are
  /// left out, as are links, form widgets and popups (a popup belongs to its
  /// parent comment and is recreated by the importing viewer). Comments
  /// without a /NM get a fresh one in the export so replies can name their
  /// parent; [document] itself is not changed. [targetFile] is recorded as
  /// the file the data belongs to.
  static PdfFormData of(
    PdfDocument document, {
    bool fields = true,
    bool annotations = true,
    String? targetFile,
  }) =>
      PdfFormData(
        fields: fields ? _captureFields(document) : const [],
        annotations: annotations ? _captureAnnotations(document) : const [],
        targetFile: targetFile,
        documentIds: _idsFrom(document.cos, document.cos.trailer['ID']),
      );

  /// Writes this data as an FDF file (`%FDF-1.2`).
  Uint8List toFdf() => _writeFdf(this);

  /// Writes this data as an XFDF document (UTF-8). Appearance streams don't
  /// travel in XFDF; an importer regenerates them from the annotation's
  /// style, as Acrobat does.
  Uint8List toXfdf() => utf8.encode(_writeXfdf(this));

  static List<PdfFormDataField> _captureFields(PdfDocument document) {
    final form = PdfAcroForm.of(document);
    if (form == null) return const [];
    final out = <PdfFormDataField>[];
    for (final field in form.fields) {
      switch (field.type) {
        case PdfFieldType.text:
          out.add(PdfFormDataField(field.name, [field.value ?? '']));
        case PdfFieldType.checkBox || PdfFieldType.radioGroup:
          final v = field.inherited('V');
          final state = v is CosName
              ? v.value
              : field.isChecked && field.onStates.isNotEmpty
                  ? field.onStates.first
                  : 'Off';
          out.add(PdfFormDataField(field.name, [state], isState: true));
        case PdfFieldType.comboBox || PdfFieldType.listBox:
          final values = field.values;
          out.add(PdfFormDataField(field.name, values.isEmpty ? [''] : values));
        case PdfFieldType.pushButton ||
              PdfFieldType.signature ||
              PdfFieldType.unknown:
          break;
      }
    }
    return out;
  }

  static List<PdfExchangeAnnotation> _captureAnnotations(PdfDocument document) {
    final cos = document.cos;
    final pages = <(int, PdfAnnotation)>[];
    for (var i = 0; i < document.pageCount; i++) {
      for (final annotation in document.page(i).annotations) {
        if (_exchangeSkipped.contains(annotation.subtype)) continue;
        pages.add((i, annotation));
      }
    }
    // a name per comment up front, so a reply can point at a parent that
    // had none in the document
    final names = Map<CosDictionary, String>.identity();
    for (final (_, annotation) in pages) {
      names[annotation.dict] = annotation.name ?? _generateAnnotationName();
    }
    final copier = _SnapshotCopier(cos);
    final out = <PdfExchangeAnnotation>[];
    for (final (page, annotation) in pages) {
      final dict = CosDictionary();
      annotation.dict.entries.forEach((key, value) {
        if (_exchangeDropped.contains(key)) return;
        dict[key] = copier.copy(value);
      });
      dict['NM'] = CosString.fromText(names[annotation.dict]!);
      final parent = cos.resolve(annotation.dict['IRT']);
      out.add(PdfExchangeAnnotation._(
        page,
        dict,
        inReplyTo: parent is CosDictionary ? names[parent] : null,
      ));
    }
    return out;
  }

  /// A two-string /ID array (trailer or FDF) as its two byte strings.
  static List<Uint8List>? _idsFrom(CosDocument cos, CosObject? value) {
    final id = cos.resolve(value);
    if (id is! CosArray || id.length < 2) return null;
    final out = <Uint8List>[];
    for (final item in id.items.take(2)) {
      final s = cos.resolve(item);
      if (s is! CosString) return null;
      out.add(Uint8List.fromList(s.bytes));
    }
    return out;
  }
}

/// Annotation subtypes that never travel in a data file: interactive
/// objects bound to this document (links, form widgets) and popups, which
/// belong to their parent comment.
const _exchangeSkipped = {'Popup', 'Widget', 'Link'};

/// Entries left behind when an annotation leaves its document: links into
/// the page tree, popups, reply wiring (carried as
/// [PdfExchangeAnnotation.inReplyTo] instead), structure and optional
/// content.
const _exchangeDropped = {
  'P', 'Popup', 'Parent', 'IRT', 'StructParent', 'OC', 'Page', //
};

PdfRect? _rectOf(CosObject? value) {
  if (value is! CosArray || value.length < 4) return null;
  final n = [for (final item in value.items.take(4)) _number(item)];
  if (n.any((v) => v == null)) return null;
  return PdfRect.normalized(n[0]!, n[1]!, n[2]!, n[3]!);
}

double? _number(CosObject? value) => switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => null,
    };

/// What [PdfFormDataExchange.importFormData] did.
class PdfFormDataImportResult {
  PdfFormDataImportResult._();

  /// Fields whose value changed.
  final List<String> filledFields = [];

  /// Fields the data named that this document has no field for.
  final List<String> unmatchedFields = [];

  /// Fields that exist but couldn't take the value (read-only, a value that
  /// isn't one of the field's options, a push button...), with the reason.
  final Map<String, String> skippedFields = {};

  /// Comments added to the document.
  int annotationsAdded = 0;

  /// Comments that replaced one with the same /NM already in the document.
  int annotationsReplaced = 0;

  /// Comments that couldn't be placed (a page the document doesn't have, a
  /// malformed /Rect), with the reason.
  final List<String> skippedAnnotations = [];

  /// Whether an XDP import replaced a dynamic XFA form's data packet
  /// ([PdfXdpImport.importXdp]) rather than filling AcroForm fields.
  bool xfaDatasetsReplaced = false;

  /// Whether anything in the document changed.
  bool get changed =>
      filledFields.isNotEmpty ||
      annotationsAdded + annotationsReplaced > 0 ||
      xfaDatasetsReplaced;

  @override
  String toString() => 'PdfFormDataImportResult(filled: '
      '${filledFields.length}, unmatched: ${unmatchedFields.length}, '
      'skipped: ${skippedFields.length}, comments added: $annotationsAdded, '
      'replaced: $annotationsReplaced, '
      'skipped: ${skippedAnnotations.length})';
}

/// Importing exchange files ([PdfFormData]) into the edited document -
/// Acrobat's Import Data and Import Comments.
extension PdfFormDataExchange on PdfEditor {
  /// Fills form fields from [data] and adds its comments.
  ///
  /// Fields match by fully qualified name; values go through the regular
  /// fill setters ([PdfFormFilling]), so appearances regenerate exactly as
  /// an interactive fill would, and a field whose value is unchanged is left
  /// untouched. A check box takes any value other than `Off`/empty/`0` as
  /// checked; a radio group takes one of its on-states (or `Off`).
  ///
  /// A comment whose /NM matches one already in the document replaces it,
  /// so importing the same file twice doesn't duplicate anything; replies
  /// are relinked to their parent by name. Comments that arrive without an
  /// appearance - every XFDF comment, and FDF ones from producers that skip
  /// /AP - get one generated for the subtypes the editor draws (text markup,
  /// ink, shapes, lines, free text, notes, stamps); others are added as-is.
  ///
  /// Set [fields] or [annotations] false to import only the other half.
  PdfFormDataImportResult importFormData(
    PdfFormData data, {
    bool fields = true,
    bool annotations = true,
  }) {
    final result = PdfFormDataImportResult._();
    if (fields) _importFields(data.fields, result);
    if (annotations) _importAnnotations(data.annotations, result);
    return result;
  }

  void _importFields(
      List<PdfFormDataField> values, PdfFormDataImportResult result) {
    if (values.isEmpty) return;
    final form = acroForm;
    final byName = <String, PdfFormField>{
      for (final field in form?.fields ?? const <PdfFormField>[])
        field.name: field,
    };
    for (final data in values) {
      final field = byName[data.name];
      if (field == null) {
        result.unmatchedFields.add(data.name);
        continue;
      }
      if (data.values.isEmpty) continue;
      try {
        final reason = _applyFieldValue(field, data.values);
        if (reason == null) {
          result.filledFields.add(field.name);
        } else if (reason.isNotEmpty) {
          result.skippedFields[field.name] = reason;
        }
      } on ArgumentError catch (e) {
        result.skippedFields[field.name] = '${e.message}';
      } on StateError catch (e) {
        result.skippedFields[field.name] = e.message;
      }
    }
  }

  /// Applies [values] to [field]: null when it was filled, '' when it
  /// already held them, otherwise why it was skipped.
  String? _applyFieldValue(PdfFormField field, List<String> values) {
    final value = values.first;
    switch (field.type) {
      case PdfFieldType.text:
        if ((field.value ?? '') == value) return '';
        if (field.isPassword) {
          setPasswordValue(field, value);
        } else {
          setTextValue(field, value);
        }
        return null;
      case PdfFieldType.checkBox:
        final checked = field.onStates.contains(value) || !_isOffValue(value);
        if (field.isChecked == checked) return '';
        setCheckBoxValue(field, checked);
        return null;
      case PdfFieldType.radioGroup:
        final current = field.inherited('V');
        // a radio group with /Opt names its buttons by index ('0', '1'...)
        // and keeps the export values in /Opt
        final byOption = field.options.indexWhere((o) => o.$1 == value);
        final state = field.onStates.contains(value)
            ? value
            : byOption >= 0 && field.onStates.contains('$byOption')
                ? '$byOption'
                : _isOffValue(value)
                    ? 'Off'
                    : null;
        if (state == null) {
          return '"$value" is not an option '
              '(${field.onStates.join(', ')})';
        }
        if ((current is CosName ? current.value : 'Off') == state) return '';
        setRadioValue(field, state);
        return null;
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        final wanted = [
          for (final v in values)
            if (v.isNotEmpty) v,
        ];
        if (_sameValues(field.values, wanted)) return '';
        if (wanted.length == 1 && !field.isMultiSelect) {
          setChoiceValue(field, wanted.single);
        } else {
          setChoiceValues(field, wanted);
        }
        return null;
      case PdfFieldType.pushButton ||
            PdfFieldType.signature ||
            PdfFieldType.unknown:
        return 'a ${field.type.name} field takes no value';
    }
  }

  static bool _isOffValue(String value) => const {
        '', 'off', '0', 'false', 'no', //
      }.contains(value.toLowerCase());

  static bool _sameValues(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _importAnnotations(
      List<PdfExchangeAnnotation> annotations, PdfFormDataImportResult result) {
    // parents before their replies, so every /IRT relinks
    final ordered = [
      ...annotations.where((a) => a.inReplyTo == null),
      ...annotations.where((a) => a.inReplyTo != null),
    ];
    final pageCount = document.pageCount;
    for (final annotation in ordered) {
      final page = annotation.pageIndex;
      final label = '${annotation.subtype} '
          '${annotation.name ?? '(unnamed)'}';
      if (page < 0 || page >= pageCount) {
        result.skippedAnnotations
            .add('$label: page ${page + 1} is not in the document');
        continue;
      }
      final rect = annotation.rect;
      if (rect == null) {
        result.skippedAnnotations.add('$label: no /Rect');
        continue;
      }
      final dict = _copyDetached(annotation._dict) as CosDictionary;
      final name = switch (dict['NM']) {
        CosString string => string.text,
        _ => _generateAnnotationName(),
      };
      dict['NM'] = CosString.fromText(name);
      final existing = _findByName(name, pageIndex: page);
      final isReply = annotation.inReplyTo != null || dict['RT'] is CosName;
      if (!annotation.hasAppearance &&
          !isReply &&
          _synthesizeAnnotation(page, dict, rect, name, existing)) {
        // generated from its style
      } else {
        final snapshot = PdfAnnotationSnapshot._(
          dict,
          annotation.subtype,
          rect,
          inReplyTo: annotation.inReplyTo,
          sourceRotation: document.page(page).rotation,
        );
        if (existing != null) {
          upsertAnnotation(page, snapshot);
        } else {
          pasteAnnotation(page, snapshot);
        }
      }
      if (existing != null) {
        result.annotationsReplaced++;
      } else {
        result.annotationsAdded++;
      }
    }
  }

  /// Draws an appearance-less comment through the editor's own generator
  /// for its subtype, then carries over the metadata the generator doesn't
  /// set (dates, subject, flags, rich text, review state...). Returns false
  /// - adding nothing - for subtypes it has no generator for.
  bool _synthesizeAnnotation(int page, CosDictionary dict, PdfRect rect,
      String name, (int, PdfAnnotation)? existing) {
    final subtype = switch (dict['Subtype']) {
      CosName(:final value) => value,
      _ => '',
    };
    final cos = document.cos;
    final color = _exchangeColor(dict['C']);
    final fill = _exchangeColor(dict['IC']);
    final opacity = (_number(dict['CA']) ?? 1).clamp(0.0, 1.0);
    final border = cos.resolve(dict['BS']);
    final bs = border is CosDictionary ? border : null;
    final width = _number(bs?['W']) ??
        switch (dict['Border']) {
          CosArray(:final items) when items.length >= 3 => _number(items[2]),
          _ => null,
        };
    final dash = switch (bs?['D']) {
      CosArray(:final items) when items.isNotEmpty => [
          for (final item in items)
            if (_number(item) case final double v) v,
        ],
      _ => null,
    };
    final contents = switch (dict['Contents']) {
      CosString string => string.text,
      _ => null,
    };
    final author = switch (dict['T']) {
      CosString string => string.text,
      _ => null,
    };
    List<(double, double)> points(CosObject? value) {
      if (value is! CosArray) return const [];
      final n = [for (final item in value.items) _number(item) ?? 0];
      return [for (var i = 0; i + 1 < n.length; i += 2) (n[i], n[i + 1])];
    }

    PdfLineEnding ending(int index) => switch (dict['LE']) {
          CosArray(:final items) when items.length > index => switch (
                items[index]) {
              CosName(:final value) => PdfLineEnding.fromName(value),
              _ => PdfLineEnding.none,
            },
          _ => PdfLineEnding.none,
        };

    void Function()? draw;
    switch (subtype) {
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        final quads = <PdfRect>[];
        final q = points(dict['QuadPoints']);
        for (var i = 0; i + 3 < q.length; i += 4) {
          final xs = [q[i].$1, q[i + 1].$1, q[i + 2].$1, q[i + 3].$1];
          final ys = [q[i].$2, q[i + 1].$2, q[i + 2].$2, q[i + 3].$2];
          quads.add(PdfRect(xs.reduce(math.min), ys.reduce(math.min),
              xs.reduce(math.max), ys.reduce(math.max)));
        }
        if (quads.isEmpty) quads.add(rect);
        final markup = switch (subtype) {
          'Highlight' => addHighlight,
          'Underline' => addUnderline,
          'StrikeOut' => addStrikeOut,
          _ => addSquiggly,
        };
        draw = () => markup(page, quads,
            color: color ?? (subtype == 'Highlight' ? 0xFFD100 : 0xD02020),
            opacity: opacity,
            contents: contents,
            author: author,
            name: name);
      case 'Ink':
        final strokes = switch (dict['InkList']) {
          CosArray(:final items) => [
              for (final stroke in items)
                if (points(stroke) case final p when p.isNotEmpty) p,
            ],
          _ => const <List<(double, double)>>[],
        };
        if (strokes.isEmpty) return false;
        draw = () => addInk(page, strokes,
            color: color ?? 0xD02020,
            strokeWidth: width ?? 1,
            opacity: opacity,
            contents: contents,
            author: author,
            name: name);
      case 'Square' || 'Circle':
        final stroke = width == 0 ? null : color;
        if (stroke == null && fill == null) return false;
        final shape = subtype == 'Square' ? addSquare : addCircle;
        draw = () => shape(page, rect,
            strokeColor: stroke,
            strokeWidth: width ?? 1,
            fillColor: fill,
            opacity: opacity,
            dashPattern: dash,
            contents: contents,
            author: author,
            name: name);
      case 'Line':
        final l = points(dict['L']);
        if (l.length < 2) return false;
        draw = () => addLine(page, l[0], l[1],
            strokeColor: color ?? 0xD02020,
            strokeWidth: width ?? 1,
            opacity: opacity,
            dashPattern: dash,
            startEnding: ending(0),
            endEnding: ending(1),
            contents: contents,
            author: author,
            name: name);
      case 'PolyLine':
        final v = points(dict['Vertices']);
        if (v.length < 2) return false;
        draw = () => addPolyLine(page, v,
            strokeColor: color ?? 0xD02020,
            strokeWidth: width ?? 1,
            opacity: opacity,
            dashPattern: dash,
            startEnding: ending(0),
            endEnding: ending(1),
            contents: contents,
            author: author,
            name: name);
      case 'Polygon':
        final v = points(dict['Vertices']);
        if (v.length < 3) return false;
        final be = cos.resolve(dict['BE']);
        final cloudy = be is CosDictionary &&
            switch (cos.resolve(be['S'])) {
              CosName(value: 'C') => true,
              _ => false,
            };
        draw = () => addPolygon(page, v,
            strokeColor: color ?? 0xD02020,
            strokeWidth: width ?? 1,
            fillColor: fill,
            opacity: opacity,
            dashPattern: dash,
            cloudy: cloudy,
            contents: contents,
            author: author,
            name: name);
      case 'FreeText':
        final da = switch (dict['DA']) {
          CosString string => string.text,
          _ => '',
        };
        final size =
            double.tryParse(_exchangeDaSizeRe.firstMatch(da)?.group(1) ?? '') ??
                12;
        final textColor = _exchangeDaColor(da) ?? 0x000000;
        final align = switch (dict['Q']) {
          CosInteger(value: 1) => PdfTextAlign.center,
          CosInteger(value: 2) => PdfTextAlign.right,
          _ => null,
        };
        draw = () => addFreeText(page, rect, contents ?? '',
            fontSize: size > 0 ? size : 12,
            color: textColor,
            align: align,
            fillColor: color,
            borderColor: width != null && width > 0 ? textColor : null,
            borderWidth: width ?? 0,
            opacity: opacity,
            author: author,
            name: name);
      case 'Text':
        draw = () => addNote(page, rect.left, rect.top, contents ?? '',
            color: color ?? 0xFFD100, author: author, name: name);
      case 'Stamp':
        final icon = switch (dict['Name']) {
          CosName(:final value) => value,
          _ => null,
        };
        final label = _stampLabel(icon) ?? contents ?? 'Stamp';
        draw = () => addStamp(page, rect, label,
            color: color ?? 0xC03030,
            opacity: opacity,
            author: author,
            name: name);
      default:
        return false;
    }
    if (existing != null) removeAnnotation(existing.$1, existing.$2);
    draw();
    final created = _findByName(name, pageIndex: page);
    if (created == null) return true;
    final target = created.$2.dict;
    var touched = false;
    dict.entries.forEach((key, value) {
      if (_generatorOwned.contains(key)) return;
      target[key] = value;
      touched = true;
    });
    if (touched) {
      _hoistStreams(target);
      _markAnnotationChanged(created.$1, target, visual: false);
    }
    return true;
  }

  /// Entries the appearance generators write from their own arguments; the
  /// imported copies of these are not carried over.
  static const _generatorOwned = {
    'Type', 'Subtype', 'Rect', 'AP', 'AS', 'NM', 'P', 'C', 'IC', 'CA', //
    'ca', 'BS', 'Border', 'BE', 'QuadPoints', 'InkList', 'L', 'LE', //
    'Vertices', 'DA', 'DS', 'Q', 'RD', 'Rotate', 'Popup', //
  };

  /// A display label for a standard stamp icon name: `NotApproved` reads
  /// `NOT APPROVED`; Acrobat's dynamic `SBApproved`/`SHSignHere` prefixes
  /// drop. Null for a missing or custom (`#...`) icon.
  static String? _stampLabel(String? icon) {
    if (icon == null || icon.isEmpty || icon.startsWith('#')) return null;
    var name = icon;
    final prefixed = RegExp(r'^S[BH](?=[A-Z])').firstMatch(name);
    if (prefixed != null) name = name.substring(prefixed.end);
    return name
        .replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ')
        .replaceAll('_', ' ')
        .toUpperCase();
  }
}

final RegExp _exchangeDaSizeRe = RegExp(r'(\d+(?:\.\d+)?)\s+Tf');
final RegExp _exchangeDaRgRe =
    RegExp(r'(\d*\.?\d+)\s+(\d*\.?\d+)\s+(\d*\.?\d+)\s+rg');
final RegExp _exchangeDaGRe = RegExp(r'(\d*\.?\d+)\s+g\b');

/// The fill colour a /DA string sets (`r g b rg` or `gray g`), as 0xRRGGBB.
int? _exchangeDaColor(String da) {
  final rgb = _exchangeDaRgRe.firstMatch(da);
  if (rgb != null) {
    return _packRgb([
      for (var i = 1; i <= 3; i++) double.tryParse(rgb.group(i)!) ?? 0,
    ]);
  }
  final gray = _exchangeDaGRe.firstMatch(da);
  if (gray != null) {
    final g = double.tryParse(gray.group(1)!) ?? 0;
    return _packRgb([g, g, g]);
  }
  return null;
}

/// A /C-style colour array (gray, RGB or CMYK components) as 0xRRGGBB, or
/// null when absent, empty (transparent) or malformed.
int? _exchangeColor(CosObject? value) {
  if (value is! CosArray) return null;
  final c = [for (final item in value.items) _number(item) ?? 0];
  return switch (c.length) {
    1 => _packRgb([c[0], c[0], c[0]]),
    3 => _packRgb(c),
    4 => _packRgb([
        for (var i = 0; i < 3; i++) (1 - c[i]) * (1 - c[3]),
      ]),
    _ => null,
  };
}

int _packRgb(List<double> rgb) {
  var out = 0;
  for (final v in rgb) {
    out = (out << 8) | (v.clamp(0.0, 1.0) * 255).round();
  }
  return out;
}

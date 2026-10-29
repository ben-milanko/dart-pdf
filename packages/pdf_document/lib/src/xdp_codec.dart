part of 'editor.dart';

const _xdpNamespace = 'http://ns.adobe.com/xdp/';
const _xdpPdfNamespace = 'http://ns.adobe.com/xdp/pdf/';
const _xfaDataNamespace = 'http://www.xfa.org/schema/xfa-data/1.0/';

/// An XML Data Package (`.xdp`): an XFA form's XML packets with the PDF it
/// belongs to embedded (base64 `<chunk>`) or referenced (`<pdf href>`).
///
/// Of the packets, the one carrying data is `<xfa:datasets>`: the field
/// values as an XML tree. An embedded `<xfdf>` packet carries comments.
/// Open an XDP with [parse] and [toPdf] (or [pdf] plus
/// [PdfXdpImport.importXdp]); write one with [build].
class PdfXdpPackage {
  PdfXdpPackage._({
    this.pdf,
    this.pdfHref,
    String? datasetsXml,
    List<_XdpLeaf> leaves = const [],
    this.comments,
  })  : _datasetsXml = datasetsXml,
        _leaves = leaves;

  /// The embedded PDF, or null when the package only references one
  /// ([pdfHref]) or carries none.
  final Uint8List? pdf;

  /// The PDF the package references instead of embedding it.
  final String? pdfHref;

  /// The comments of an embedded `<xfdf>` packet, if any.
  final PdfFormData? comments;

  /// The `<xfa:datasets>` packet, re-serialized, with the namespace it
  /// needs declared on itself. Null when the package has no datasets.
  final String? _datasetsXml;

  final List<_XdpLeaf> _leaves;

  /// Whether the package carries form data (an `<xfa:datasets>` packet).
  bool get hasData => _datasetsXml != null;

  /// The data values as fields named by their XFA path, in SOM style
  /// (`form1[0].address[0].city[0]`) - one per leaf element of `<xfa:data>`.
  /// Importing into a document ([PdfXdpImport.importXdp]) matches these to
  /// the document's own field names; this list is for inspection and
  /// conversion.
  List<PdfFormDataField> get dataFields => [
        for (final leaf in _leaves)
          PdfFormDataField(
              leaf.path.map((s) => '${s.$1}[${s.$2}]').join('.'), [leaf.value]),
      ];

  /// Reads an XDP file. Throws [FormatException] on malformed XML, a root
  /// that isn't `<xdp:xdp>`, or an embedded PDF that isn't valid base64.
  static PdfXdpPackage parse(Uint8List bytes) {
    final XmlLiteDocument xml;
    try {
      xml = XmlLiteDocument.parse(bytes);
    } on FormatException catch (e) {
      throw FormatException('malformed XDP: ${e.message}');
    }
    final root = xml.root;
    if (root.localName != 'xdp') {
      throw FormatException('not XDP: root is <${root.qname}>');
    }

    Uint8List? pdf;
    String? href;
    final pdfPacket = root.child('pdf');
    if (pdfPacket != null) {
      href = pdfPacket.attribute('href');
      final chunks = pdfPacket
          .descendantsNamed('chunk')
          .map((c) => c.text.replaceAll(RegExp(r'\s+'), ''))
          .join();
      if (chunks.isNotEmpty) {
        try {
          pdf = base64Decode(chunks);
        } on FormatException {
          throw const FormatException(
              'malformed XDP: the embedded PDF is not valid base64');
        }
      }
    }

    String? datasetsXml;
    final leaves = <_XdpLeaf>[];
    final datasets = root.child('datasets');
    if (datasets != null) {
      datasetsXml = _serializeStandalone(datasets);
      final data = datasets.child('data');
      if (data != null) _collectLeaves(data, const [], leaves);
    }

    final xfdf = root.child('xfdf');
    return PdfXdpPackage._(
      pdf: pdf,
      pdfHref: href,
      datasetsXml: datasetsXml,
      leaves: leaves,
      comments: xfdf == null ? null : _readXfdf(xfdf),
    );
  }

  /// The package's data and comments as a [PdfFormData] keyed by the XFA
  /// paths of [dataFields] - for converting to FDF/XFDF without a document.
  PdfFormData toFormData() => PdfFormData(
        fields: dataFields,
        annotations: comments?.annotations ?? const [],
        targetFile: pdfHref,
      );

  /// The embedded PDF with the package's data filled in (and comments
  /// added) - what opening the XDP in Acrobat shows. Returns [pdf]
  /// untouched when nothing applied. Throws [StateError] when the package
  /// doesn't embed its PDF.
  Uint8List toPdf({String password = ''}) {
    final bytes = pdf;
    if (bytes == null) {
      throw StateError(pdfHref == null
          ? 'the XDP package carries no PDF'
          : 'the XDP package references its PDF ($pdfHref) '
              'rather than embedding it');
    }
    final editor = PdfEditor(PdfDocument.open(bytes, password: password));
    final result = editor.importXdp(this);
    return result.changed ? editor.save() : bytes;
  }

  /// Writes [document] as an XDP package with the PDF embedded (or, given
  /// [pdfHref], referenced).
  ///
  /// An XFA form keeps its own packets (template, config, datasets, ...)
  /// verbatim, as Acrobat's Save As XDP does. Any other form gets a
  /// `<xfa:datasets>` packet built from its AcroForm values, one element
  /// per partial name, so the package round-trips through
  /// [PdfXdpImport.importXdp]. [document] should be the saved revision:
  /// the embedded bytes are its file's.
  static Uint8List build(PdfDocument document, {String? pdfHref}) {
    final pdfPacket = StringBuffer('<pdf xmlns="$_xdpPdfNamespace"');
    if (pdfHref != null) {
      pdfPacket.write(' href="${_xmlEscape(pdfHref)}"/>');
    } else {
      pdfPacket
        ..write('><document><chunk>')
        ..write(base64Encode(document.cos.bytes))
        ..write('</chunk></document></pdf>');
    }

    final packets = _xfaPackets(document);
    if (packets != null) {
      final close =
          RegExp(r'</([A-Za-z_][\w.\-]*:)?xdp\s*>\s*$').firstMatch(packets);
      if (close != null) {
        return utf8.encode('${packets.substring(0, close.start)}'
            '$pdfPacket\n${packets.substring(close.start)}');
      }
    }

    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
      ..write('<xdp:xdp xmlns:xdp="$_xdpNamespace">\n')
      ..write('<xfa:datasets xmlns:xfa="$_xfaDataNamespace">\n<xfa:data>\n');
    final fields = PdfFormData._captureFields(document);
    if (fields.isNotEmpty) _writeXdpData(out, fields);
    out
      ..write('</xfa:data>\n</xfa:datasets>\n')
      ..write('$pdfPacket\n')
      ..write('</xdp:xdp>\n');
    return utf8.encode(out.toString());
  }

  /// The document's XFA packets concatenated (they're one XDP document
  /// split into named pieces, §12.7.8), or null without XFA.
  static String? _xfaPackets(PdfDocument document) {
    final form = PdfAcroForm.of(document);
    if (form == null || !form.hasXfa) return null;
    final cos = document.cos;
    final xfa = cos.resolve(form.dict['XFA']);
    final out = BytesBuilder(copy: false);
    if (xfa is CosStream) {
      out.add(cos.decodeStreamData(xfa));
    } else if (xfa is CosArray) {
      for (var i = 1; i < xfa.length; i += 2) {
        final packet = cos.resolve(xfa[i]);
        if (packet is CosStream) out.add(cos.decodeStreamData(packet));
      }
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true).trim();
  }
}

/// One leaf of `<xfa:data>`: its element path (local names with their
/// occurrence index among same-named siblings) and text.
class _XdpLeaf {
  _XdpLeaf(this.path, this.value);
  final List<(String, int)> path;
  final String value;
}

void _collectLeaves(
    XmlLiteElement node, List<(String, int)> path, List<_XdpLeaf> out) {
  final seen = <String, int>{};
  for (final child in node.childElements) {
    final index = seen[child.localName] = (seen[child.localName] ?? -1) + 1;
    final at = [...path, (child.localName, index)];
    if (child.childElements.isEmpty) {
      out.add(_XdpLeaf(at, child.text));
    } else {
      _collectLeaves(child, at, out);
    }
  }
}

/// [element] serialized with its own prefix's namespace declared on it, so
/// it stands alone outside the `<xdp:xdp>` root that may have declared it.
String _serializeStandalone(XmlLiteElement element) {
  final prefix = element.prefix;
  final declaration = prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix';
  if (element.attribute(declaration) != null) return _xmlSerialize(element);
  final copy = XmlLiteElement(element.qname, [
    XmlLiteAttribute(declaration, element.namespaceUri),
    ...element.attributes,
  ])
    ..children.addAll(element.children);
  return _xmlSerialize(copy);
}

/// XFA SOM-style segments of an AcroForm field name: `form1[0].#subform[0]
/// .name[0]` reads [(form1, 0), (name, 0)] - unnamed (`#`) subforms drop,
/// since data binding skips them, and names are spelled as XML names the
/// way [_xmlName] writes them.
List<(String, int)> _somSegments(String name) {
  final out = <(String, int)>[];
  for (final part in name.split('.')) {
    final match = _somIndexRe.firstMatch(part);
    final base = match == null ? part : match.group(1)!;
    final index = match == null ? 0 : int.parse(match.group(2)!);
    if (base.isEmpty || base.startsWith('#')) continue;
    out.add((_xmlName(base), index));
  }
  return out;
}

final RegExp _somIndexRe = RegExp(r'^(.*)\[(\d+)\]$');

/// [name] as a valid XML element name: characters outside the name set
/// become `_`, and a leading digit, dot or hyphen gets a `_` in front.
String _xmlName(String name) {
  final safe = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
  if (safe.isEmpty) return '_';
  return RegExp(r'^[\d.\-]').hasMatch(safe) ? '_$safe' : safe;
}

void _writeXdpData(StringBuffer out, List<PdfFormDataField> fields) {
  // a tree keyed by (name, index) so repeated XFA-style names nest right
  final root = _XdpNode();
  for (final field in fields) {
    var node = root;
    for (final segment in _somSegments(field.name)) {
      node = node.kids.putIfAbsent(segment, _XdpNode.new);
    }
    if (!identical(node, root)) node.value = field.values.join('\n');
  }
  void write(_XdpNode node, int depth) {
    for (final MapEntry(key: (name, _), value: kid) in node.kids.entries) {
      final indent = '  ' * depth;
      if (kid.kids.isEmpty) {
        out.write('$indent<$name>${_xmlEscape(kid.value ?? '')}</$name>\n');
      } else {
        out.write('$indent<$name>\n');
        write(kid, depth + 1);
        out.write('$indent</$name>\n');
      }
    }
  }

  write(root, 1);
}

class _XdpNode {
  final Map<(String, int), _XdpNode> kids = {};
  String? value;
}

/// Importing XDP packages ([PdfXdpPackage]) into the edited document.
extension PdfXdpImport on PdfEditor {
  /// Applies [package]'s data and comments to the document.
  ///
  /// For a dynamic XFA form ([PdfAcroForm.isDynamicXfa]) - whose fields
  /// exist only in the XFA description - the package's `<xfa:datasets>`
  /// packet replaces the form's own, which is what an XFA viewer fills the
  /// form from ([PdfFormDataImportResult.xfaDatasetsReplaced]).
  ///
  /// Otherwise each data value is matched to an AcroForm field by its XFA
  /// path: names compare segment by segment with unnamed (`#subform`)
  /// levels skipped and page-level subforms allowed in between, falling
  /// back to the one field whose last segment matches. Matched values fill
  /// through [PdfFormDataExchange.importFormData]; unmatched paths are
  /// reported in [PdfFormDataImportResult.unmatchedFields].
  PdfFormDataImportResult importXdp(
    PdfXdpPackage package, {
    bool fields = true,
    bool annotations = true,
  }) {
    final result = PdfFormDataImportResult._();
    final datasets = package._datasetsXml;
    if (fields && datasets != null) {
      final form = acroForm;
      if (form != null && form.isDynamicXfa) {
        result.xfaDatasetsReplaced = _replaceXfaDatasets(form, datasets);
      } else {
        _importFields(_matchXdpLeaves(package, form, result), result);
      }
    }
    final comments = package.comments;
    if (annotations && comments != null) {
      _importAnnotations(comments.annotations, result);
    }
    return result;
  }

  List<PdfFormDataField> _matchXdpLeaves(PdfXdpPackage package,
      PdfAcroForm? form, PdfFormDataImportResult result) {
    final fields = [
      for (final field in form?.fields ?? const <PdfFormField>[])
        (field, _somSegments(field.name)),
    ];
    final used = Set<PdfFormField>.identity();
    final out = <PdfFormDataField>[];
    for (final leaf in package._leaves) {
      final path = leaf.path;
      final last = path.last;
      final ancestors = [for (final s in path.take(path.length - 1)) s.$1];
      PdfFormField? exact, nested, sole;
      var leafMatches = 0;
      for (final (field, segments) in fields) {
        if (segments.isEmpty || segments.last != last || used.contains(field)) {
          continue;
        }
        leafMatches++;
        sole = field;
        final names = [
          for (final s in segments.take(segments.length - 1)) s.$1,
        ];
        if (_listEquals(names, ancestors)) {
          exact ??= field;
        } else if (_isSubsequence(ancestors, names) ||
            _isSubsequence(names, ancestors)) {
          nested ??= field;
        }
      }
      final match = exact ?? nested ?? (leafMatches == 1 ? sole : null);
      if (match == null) {
        result.unmatchedFields
            .add(path.map((s) => '${s.$1}[${s.$2}]').join('.'));
        continue;
      }
      used.add(match);
      out.add(PdfFormDataField(match.name, [leaf.value]));
    }
    return out;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Whether [small]'s names all appear in [big], in order.
  static bool _isSubsequence(List<String> small, List<String> big) {
    var j = 0;
    for (final name in big) {
      if (j < small.length && small[j] == name) j++;
    }
    return j == small.length;
  }

  /// Swaps the form's `datasets` packet for [datasets]: the packet's own
  /// stream in an /XFA array (one is appended before the postamble when the
  /// form had none), or the `<xfa:datasets>` element inside a single-stream
  /// /XFA. Returns whether anything was written.
  bool _replaceXfaDatasets(PdfAcroForm form, String datasets) {
    final cos = document.cos;
    final bytes = utf8.encode(datasets);
    CosStream packet(Uint8List data) =>
        CosStream(CosDictionary({'Length': CosInteger(data.length)}), data);

    void stageForm() {
      final ref = cos.referenceTo(form.dict);
      if (ref != null) {
        _updater.replaceObject(ref.objectNumber, form.dict);
      } else {
        _updater.markChanged(document.catalog);
      }
    }

    void writeStream(CosObject? slot, CosStream stream, void Function() put) {
      if (slot is CosReference) {
        _updater.replaceObject(slot.objectNumber, stream);
        cos.adoptObject(slot, stream);
      } else {
        put();
        stageForm();
      }
    }

    final raw = form.dict['XFA'];
    final xfa = cos.resolve(raw);
    if (xfa is CosArray) {
      for (var i = 0; i + 1 < xfa.length; i += 2) {
        if (cos.resolve(xfa[i]) case CosString(:final text)
            when text == 'datasets') {
          final stream = packet(bytes);
          writeStream(xfa.items[i + 1], stream,
              () => xfa.items[i + 1] = _updater.addObject(stream));
          if (cos.referenceTo(xfa) case final CosReference ref) {
            _updater.replaceObject(ref.objectNumber, xfa);
          }
          _markVisual(null);
          return true;
        }
      }
      // no datasets packet yet: it goes before the postamble (the closing
      // </xdp:xdp>), or last
      var at = xfa.length;
      for (var i = 0; i + 1 < xfa.length; i += 2) {
        if (cos.resolve(xfa[i]) case CosString(:final text)
            when text == 'postamble') {
          at = i;
        }
      }
      xfa.items.insertAll(at, [
        CosString.fromText('datasets'),
        _updater.addObject(packet(bytes)),
      ]);
      final ref = cos.referenceTo(xfa);
      if (ref != null) {
        _updater.replaceObject(ref.objectNumber, xfa);
      } else {
        stageForm();
      }
      _markVisual(null);
      return true;
    }
    if (xfa is CosStream) {
      final text = utf8.decode(cos.decodeStreamData(xfa), allowMalformed: true);
      final existing =
          RegExp(r'<([A-Za-z_][\w.\-]*:)?datasets\b[\s\S]*?</\1datasets\s*>')
              .firstMatch(text);
      final String updated;
      if (existing != null) {
        updated = text.replaceRange(existing.start, existing.end, datasets);
      } else {
        final close = RegExp(r'</([A-Za-z_][\w.\-]*:)?xdp\s*>')
            .allMatches(text)
            .lastOrNull;
        if (close == null) return false;
        updated = text.replaceRange(close.start, close.start, datasets);
      }
      final stream = packet(utf8.encode(updated));
      writeStream(
          raw, stream, () => form.dict['XFA'] = _updater.addObject(stream));
      _markVisual(null);
      return true;
    }
    return false;
  }
}

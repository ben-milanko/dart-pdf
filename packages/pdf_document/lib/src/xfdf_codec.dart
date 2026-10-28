part of 'editor.dart';

// XFDF (ISO 19444-1) reading and writing for [PdfFormData]: the XML twin of
// FDF. Field values nest as <field name=...><value>; each comment is an
// element named for its subtype whose attributes and children map one to
// one onto annotation dictionary entries (the tables below). XFDF carries
// no appearance streams - importers regenerate them from the style.

const _xfdfNamespace = 'http://ns.adobe.com/xfdf/';

/// XFDF element name ↔ annotation /Subtype.
const _xfdfSubtypes = {
  'text': 'Text',
  'caret': 'Caret',
  'circle': 'Circle',
  'fileattachment': 'FileAttachment',
  'freetext': 'FreeText',
  'highlight': 'Highlight',
  'ink': 'Ink',
  'line': 'Line',
  'polygon': 'Polygon',
  'polyline': 'PolyLine',
  'redact': 'Redact',
  'sound': 'Sound',
  'square': 'Square',
  'squiggly': 'Squiggly',
  'stamp': 'Stamp',
  'strikeout': 'StrikeOut',
  'underline': 'Underline',
};

/// Plain string attributes ↔ text-string entries.
const _xfdfStrings = {
  'name': 'NM',
  'title': 'T',
  'subject': 'Subj',
  'date': 'M',
  'creationdate': 'CreationDate',
  'state': 'State',
  'statemodel': 'StateModel',
  'overlay-text': 'OverlayText',
};

/// Plain string attributes ↔ name entries.
const _xfdfNames = {
  'icon': 'Name',
  'intent': 'IT',
  'caption-style': 'CP',
};

/// Number attributes ↔ number entries.
const _xfdfNumbers = {
  'opacity': 'CA',
  'rotation': 'Rotate',
  'leaderLength': 'LL',
  'leaderExtend': 'LLE',
  'leaderOffset': 'LLO',
};

/// Number-list attributes ↔ number-array entries.
const _xfdfNumberLists = {
  'coords': 'QuadPoints',
  'vertices': 'Vertices',
  'fringe': 'RD',
  'callout': 'CL',
};

/// Element children holding text ↔ text-string entries.
const _xfdfTextChildren = {
  'contents': 'Contents',
  'defaultappearance': 'DA',
  'defaultstyle': 'DS',
};

/// /F annotation flag bits, in XFDF's `flags` spelling (§12.5.3).
const _xfdfFlags = [
  'invisible', 'hidden', 'print', 'nozoom', 'norotate', 'noview', //
  'readonly', 'locked', 'togglenoview', 'lockedcontents', //
];

/// XFDF border `style` ↔ /BS /S (cloudy is a /BE border effect instead).
const _xfdfBorderStyles = {
  'solid': 'S',
  'dash': 'D',
  'bevelled': 'B',
  'inset': 'I',
  'underline': 'U',
};

const _xfdfJustification = ['left', 'centered', 'right'];

final RegExp _xfdfListSep = RegExp(r'[\s,;]+');

PdfFormData _readXfdf(XmlLiteElement root) {
  final fields = <PdfFormDataField>[];
  void walk(XmlLiteElement field, String prefix) {
    final partial = field.attribute('name') ?? '';
    final name = prefix.isEmpty ? partial : '$prefix.$partial';
    final values = [
      for (final value in field.childElements)
        if (value.localName == 'value')
          value.text
        else if (value.localName == 'value-richtext')
          value.text,
    ];
    if (values.isNotEmpty) fields.add(PdfFormDataField(name, values));
    for (final kid in field.childrenNamed('field')) {
      walk(kid, name);
    }
  }

  for (final group in root.childrenNamed('fields')) {
    for (final field in group.childrenNamed('field')) {
      walk(field, '');
    }
  }

  final annotations = <PdfExchangeAnnotation>[];
  for (final group in root.childrenNamed('annots')) {
    for (final element in group.childElements) {
      final annotation = _xfdfAnnotation(element);
      if (annotation != null) annotations.add(annotation);
    }
  }

  final ids = root.child('ids');
  final original = _hexBytes(ids?.attribute('original'));
  final modified = _hexBytes(ids?.attribute('modified'));
  return PdfFormData(
    fields: fields,
    annotations: annotations,
    targetFile: root.child('f')?.attribute('href'),
    documentIds:
        original != null && modified != null ? [original, modified] : null,
  );
}

PdfExchangeAnnotation? _xfdfAnnotation(XmlLiteElement element) {
  final subtype = _xfdfSubtypes[element.localName];
  if (subtype == null) return null;
  final dict = CosDictionary({
    'Type': const CosName('Annot'),
    'Subtype': CosName(subtype),
  });
  final rect = _xfdfNumbersOf(element.attribute('rect'));
  if (rect.length == 4) dict['Rect'] = _reals(rect);

  _xfdfStrings.forEach((attribute, key) {
    final v = element.attribute(attribute);
    if (v != null) dict[key] = CosString.fromText(v);
  });
  _xfdfNames.forEach((attribute, key) {
    final v = element.attribute(attribute);
    if (v != null && v.isNotEmpty) dict[key] = CosName(v);
  });
  _xfdfNumbers.forEach((attribute, key) {
    final v = double.tryParse(element.attribute(attribute) ?? '');
    if (v != null) dict[key] = _real(v);
  });
  _xfdfNumberLists.forEach((attribute, key) {
    final v = _xfdfNumbersOf(element.attribute(attribute));
    if (v.isNotEmpty) dict[key] = _reals(v);
  });
  for (final (attribute, key) in const [
    ('color', 'C'),
    ('interior-color', 'IC')
  ]) {
    final rgb = _xfdfColor(element.attribute(attribute));
    if (rgb != null) dict[key] = _reals(rgb);
  }

  final flags = element.attribute('flags');
  if (flags != null) {
    var bits = 0;
    for (final flag in flags.split(_xfdfListSep)) {
      final i = _xfdfFlags.indexOf(flag.toLowerCase());
      if (i >= 0) bits |= 1 << i;
    }
    dict['F'] = CosInteger(bits);
  }

  final width = double.tryParse(element.attribute('width') ?? '');
  final style = element.attribute('style');
  final dashes = _xfdfNumbersOf(element.attribute('dashes'));
  if (width != null || style != null || dashes.isNotEmpty) {
    final bs = CosDictionary({'Type': const CosName('Border')});
    if (width != null) bs['W'] = _real(width);
    final s = _xfdfBorderStyles[style];
    if (s != null) bs['S'] = CosName(s);
    if (dashes.isNotEmpty) bs['D'] = _reals(dashes);
    dict['BS'] = bs;
    if (style == 'cloudy') {
      dict['BE'] = CosDictionary({
        'S': const CosName('C'),
        'I': _real(double.tryParse(element.attribute('intensity') ?? '') ?? 1),
      });
    }
  }

  final justification =
      _xfdfJustification.indexOf(element.attribute('justification') ?? '');
  if (justification >= 0) dict['Q'] = CosInteger(justification);

  final start = _xfdfNumbersOf(element.attribute('start'));
  final end = _xfdfNumbersOf(element.attribute('end'));
  if (start.length == 2 && end.length == 2) {
    dict['L'] = _reals([...start, ...end]);
  }
  final head = element.attribute('head');
  final tail = element.attribute('tail');
  if (head != null || tail != null) {
    dict['LE'] = CosArray([CosName(head ?? 'None'), CosName(tail ?? 'None')]);
  }
  final caption = element.attribute('caption');
  if (caption != null) dict['Cap'] = CosBoolean(caption == 'yes');
  final offsetH = double.tryParse(element.attribute('caption-offset-h') ?? '');
  final offsetV = double.tryParse(element.attribute('caption-offset-v') ?? '');
  if (offsetH != null || offsetV != null) {
    dict['CO'] = _reals([offsetH ?? 0, offsetV ?? 0]);
  }
  final replyType = element.attribute('replyType');
  if (replyType != null) {
    dict['RT'] = CosName(replyType.toLowerCase() == 'group' ? 'Group' : 'R');
  }

  _xfdfTextChildren.forEach((child, key) {
    final node = element.child(child);
    if (node != null) dict[key] = CosString.fromText(node.text);
  });
  final rich = element.child('contents-richtext');
  if (rich != null) {
    final body = rich.childElements.firstOrNull;
    if (body != null) {
      dict['RC'] =
          CosString.fromText('<?xml version="1.0"?>${_xmlSerialize(body)}');
      if (dict['Contents'] == null) {
        dict['Contents'] = CosString.fromText(body.text);
      }
    }
  }
  final ink = element.child('inklist');
  if (ink != null) {
    dict['InkList'] = CosArray([
      for (final gesture in ink.childrenNamed('gesture'))
        _reals(_xfdfNumbersOf(gesture.text)),
    ]);
  }

  return PdfExchangeAnnotation._(
    int.tryParse(element.attribute('page') ?? '') ?? 0,
    dict,
    inReplyTo: element.attribute('inreplyto'),
  );
}

String _writeXfdf(PdfFormData data) {
  final out = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
    ..write('<xfdf xmlns="$_xfdfNamespace" xml:space="preserve">\n');
  final target = data.targetFile;
  if (target != null) out.write('<f href="${_xmlEscape(target)}"/>\n');
  final ids = data.documentIds;
  if (ids != null && ids.length == 2) {
    out.write('<ids original="${_hex(ids[0])}" '
        'modified="${_hex(ids[1])}"/>\n');
  }

  if (data.fields.isNotEmpty) {
    out.write('<fields>\n');
    _writeXfdfFields(out, _nameTree(data.fields), 1);
    out.write('</fields>\n');
  }

  if (data.annotations.isNotEmpty) {
    out.write('<annots>\n');
    for (final annotation in data.annotations) {
      _writeXfdfAnnotation(out, annotation);
    }
    out.write('</annots>\n');
  }
  out.write('</xfdf>\n');
  return out.toString();
}

/// A node of the partial-name tree both XFDF and XDP nest values in.
class _NameNode {
  _NameNode(this.name);
  final String name;
  final Map<String, _NameNode> kids = {};
  List<String>? values;
}

_NameNode _nameTree(List<PdfFormDataField> fields) {
  final root = _NameNode('');
  for (final field in fields) {
    var node = root;
    for (final part in field.name.split('.')) {
      node = node.kids.putIfAbsent(part, () => _NameNode(part));
    }
    node.values = field.values;
  }
  return root;
}

void _writeXfdfFields(StringBuffer out, _NameNode node, int depth) {
  for (final kid in node.kids.values) {
    final indent = '  ' * depth;
    out.write('$indent<field name="${_xmlEscape(kid.name)}">\n');
    for (final value in kid.values ?? const <String>[]) {
      out.write('$indent  <value>${_xmlEscape(value)}</value>\n');
    }
    _writeXfdfFields(out, kid, depth + 1);
    out.write('$indent</field>\n');
  }
}

void _writeXfdfAnnotation(StringBuffer out, PdfExchangeAnnotation annotation) {
  final dict = annotation._dict;
  String? element;
  _xfdfSubtypes.forEach((name, subtype) {
    if (subtype == annotation.subtype) element = name;
  });
  if (element == null) return; // links, widgets... have no XFDF form
  final attributes = <String, String>{'page': '${annotation.pageIndex}'};
  final rect = annotation.rect;
  if (rect != null) {
    attributes['rect'] =
        _numberList([rect.left, rect.bottom, rect.right, rect.top]);
  }
  _xfdfStrings.forEach((attribute, key) {
    if (dict[key] case final CosString s) attributes[attribute] = s.text;
  });
  _xfdfNames.forEach((attribute, key) {
    if (dict[key] case CosName(:final value)) attributes[attribute] = value;
  });
  _xfdfNumbers.forEach((attribute, key) {
    final v = _number(dict[key]);
    if (v != null) attributes[attribute] = _formatNumber(v);
  });
  _xfdfNumberLists.forEach((attribute, key) {
    if (dict[key] case CosArray(:final items)) {
      final n = [for (final item in items) _number(item) ?? 0];
      if (n.isNotEmpty) {
        attributes[attribute] =
            key == 'Vertices' ? _pointList(n) : _numberList(n);
      }
    }
  });
  for (final (attribute, key) in const [
    ('color', 'C'),
    ('interior-color', 'IC')
  ]) {
    final rgb = _exchangeColor(dict[key]);
    if (rgb != null) {
      attributes[attribute] =
          '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }
  }
  if (dict['F'] case CosInteger(:final value) when value != 0) {
    attributes['flags'] = [
      for (var i = 0; i < _xfdfFlags.length; i++)
        if (value & (1 << i) != 0) _xfdfFlags[i],
    ].join(',');
  }
  if (dict['BS'] case final CosDictionary bs) {
    final w = _number(bs['W']);
    if (w != null) attributes['width'] = _formatNumber(w);
    if (bs['S'] case CosName(:final value)) {
      _xfdfBorderStyles.forEach((style, s) {
        if (s == value) attributes['style'] = style;
      });
    }
    if (bs['D'] case CosArray(:final items) when items.isNotEmpty) {
      attributes['dashes'] =
          _numberList([for (final item in items) _number(item) ?? 0]);
    }
  } else if (dict['Border'] case CosArray(:final items)
      when items.length >= 3) {
    final w = _number(items[2]);
    if (w != null) attributes['width'] = _formatNumber(w);
  }
  if (dict['BE'] case final CosDictionary be) {
    if (be['S'] case CosName(value: 'C')) {
      attributes['style'] = 'cloudy';
      final i = _number(be['I']);
      if (i != null) attributes['intensity'] = _formatNumber(i);
    }
  }
  if (dict['Q'] case CosInteger(:final value) when value > 0 && value < 3) {
    attributes['justification'] = _xfdfJustification[value];
  }
  if (dict['L'] case CosArray(:final items) when items.length >= 4) {
    final n = [for (final item in items.take(4)) _number(item) ?? 0];
    attributes['start'] = _numberList(n.sublist(0, 2));
    attributes['end'] = _numberList(n.sublist(2, 4));
  }
  if (dict['LE'] case CosArray(:final items) when items.length >= 2) {
    if (items[0] case CosName(:final value)) attributes['head'] = value;
    if (items[1] case CosName(:final value)) attributes['tail'] = value;
  }
  if (dict['Cap'] case CosBoolean(:final value)) {
    attributes['caption'] = value ? 'yes' : 'no';
  }
  if (dict['CO'] case CosArray(:final items) when items.length >= 2) {
    attributes['caption-offset-h'] = _formatNumber(_number(items[0]) ?? 0);
    attributes['caption-offset-v'] = _formatNumber(_number(items[1]) ?? 0);
  }
  final parent = annotation.inReplyTo;
  if (parent != null) {
    attributes['inreplyto'] = parent;
    if (dict['RT'] case CosName(value: 'Group')) {
      attributes['replyType'] = 'group';
    }
  }

  out.write('<$element');
  attributes.forEach((k, v) => out.write(' $k="${_xmlEscape(v)}"'));
  final children = StringBuffer();
  _xfdfTextChildren.forEach((child, key) {
    if (dict[key] case final CosString s) {
      children.write('<$child>${_xmlEscape(s.text)}</$child>');
    }
  });
  if (dict['RC'] case final CosString rc) {
    // only well-formed rich text travels; it nests verbatim as XML
    try {
      final body = XmlLiteDocument.parse(utf8.encode(rc.text)).root;
      children.write(
          '<contents-richtext>${_xmlSerialize(body)}</contents-richtext>');
    } on FormatException {
      // malformed /RC: the plain /Contents above still carries the text
    }
  }
  if (dict['InkList'] case CosArray(:final items)) {
    children.write('<inklist>');
    for (final stroke in items) {
      if (stroke case CosArray(items: final points)) {
        children.write('<gesture>'
            '${_pointList([for (final p in points) _number(p) ?? 0])}'
            '</gesture>');
      }
    }
    children.write('</inklist>');
  }
  if (children.isEmpty) {
    out.write('/>\n');
  } else {
    out.write('>$children</$element>\n');
  }
}

// ---------------------------------------------------------------------
// small XML helpers, shared with the XDP codec

String _xmlEscape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x26:
        out.write('&amp;');
      case 0x3C:
        out.write('&lt;');
      case 0x3E:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x09 || 0x0A || 0x0D:
        out.write('&#$rune;');
      default:
        // characters XML 1.0 can't carry at all are dropped
        if (rune >= 0x20 && rune != 0xFFFE && rune != 0xFFFF) {
          out.writeCharCode(rune);
        }
    }
  }
  return out.toString();
}

/// Re-serializes a parsed element (attributes as written, namespace
/// declarations included); comments and processing instructions drop.
String _xmlSerialize(XmlLiteElement element) {
  final out = StringBuffer();
  void write(XmlLiteElement e) {
    out.write('<${e.qname}');
    for (final a in e.attributes) {
      out.write(' ${a.qname}="${_xmlEscape(a.value)}"');
    }
    if (e.children.isEmpty) {
      out.write('/>');
      return;
    }
    out.write('>');
    for (final child in e.children) {
      switch (child) {
        case XmlLiteElement():
          write(child);
        case XmlLiteText(:final value):
          out.write(_xmlEscape(value)
              .replaceAll('&#10;', '\n')
              .replaceAll('&#9;', '\t'));
        default:
      }
    }
    out.write('</${e.qname}>');
  }

  write(element);
  return out.toString();
}

List<double> _xfdfNumbersOf(String? text) {
  if (text == null) return const [];
  return [
    for (final part in text.trim().split(_xfdfListSep))
      if (double.tryParse(part) case final double v) v,
  ];
}

List<double>? _xfdfColor(String? text) {
  if (text == null) return null;
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return [
    for (final shift in const [16, 8, 0]) ((v >> shift) & 0xFF) / 255,
  ];
}

CosObject _real(double v) => v == v.roundToDouble() && v.abs() < 1e15
    ? CosInteger(v.toInt())
    : CosReal(v);

CosArray _reals(List<double> values) =>
    CosArray([for (final v in values) _real(v)]);

String _formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

String _numberList(List<double> values) => values.map(_formatNumber).join(',');

/// `x,y;x,y` - XFDF's spelling of a point list (vertices, gestures).
String _pointList(List<double> values) => [
      for (var i = 0; i + 1 < values.length; i += 2)
        '${_formatNumber(values[i])},${_formatNumber(values[i + 1])}',
    ].join(';');

String _hex(Uint8List bytes) => [
      for (final b in bytes) b.toRadixString(16).padLeft(2, '0').toUpperCase(),
    ].join();

Uint8List? _hexBytes(String? text) {
  if (text == null || text.length.isOdd) return null;
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) return null;
    out[i] = v;
  }
  return out;
}

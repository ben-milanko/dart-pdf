/// A small, strict XML 1.0 reader and W3C Canonical XML (inclusive 1.0 and
/// exclusive 1.0, both without comments) - exactly what verifying the XML
/// signature on an ETSI trusted list needs, and nothing more.
///
/// Canonicalization is defined over the XPath data model the parser feeds
/// it: line endings normalized, attribute values normalized as CDATA (no
/// DTD), character and predefined entity references expanded. Documents that
/// declare their own entities are refused rather than half-understood.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A node in a parsed [XmlLiteDocument].
sealed class XmlLiteNode {
  XmlLiteElement? parent;
}

/// An element: its qualified name, attributes (namespace declarations
/// included, as written) and children.
class XmlLiteElement extends XmlLiteNode {
  XmlLiteElement(this.qname, this.attributes);

  final String qname;
  final List<XmlLiteAttribute> attributes;
  final List<XmlLiteNode> children = [];

  String get prefix {
    final i = qname.indexOf(':');
    return i < 0 ? '' : qname.substring(0, i);
  }

  String get localName {
    final i = qname.indexOf(':');
    return i < 0 ? qname : qname.substring(i + 1);
  }

  /// The namespace URI bound to [prefix] here ('' for the default namespace
  /// when none is declared; null for an undeclared prefix).
  String? lookupNamespace(String prefix) {
    for (XmlLiteElement? e = this; e != null; e = e.parent) {
      for (final a in e.attributes) {
        if (prefix.isEmpty ? a.qname == 'xmlns' : a.qname == 'xmlns:$prefix') {
          return a.value;
        }
      }
    }
    if (prefix == 'xml') return 'http://www.w3.org/XML/1998/namespace';
    return prefix.isEmpty ? '' : null;
  }

  /// This element's namespace URI.
  String get namespaceUri => lookupNamespace(prefix) ?? '';

  /// The value of the attribute named [qname], or null.
  String? attribute(String qname) {
    for (final a in attributes) {
      if (a.qname == qname) return a.value;
    }
    return null;
  }

  Iterable<XmlLiteElement> get childElements =>
      children.whereType<XmlLiteElement>();

  /// Child elements with local name [local] (any namespace).
  Iterable<XmlLiteElement> childrenNamed(String local) =>
      childElements.where((e) => e.localName == local);

  /// The first child element with local name [local], or null.
  XmlLiteElement? child(String local) {
    for (final e in childElements) {
      if (e.localName == local) return e;
    }
    return null;
  }

  /// Every descendant element with local name [local], in document order.
  Iterable<XmlLiteElement> descendantsNamed(String local) sync* {
    for (final e in childElements) {
      if (e.localName == local) yield e;
      yield* e.descendantsNamed(local);
    }
  }

  /// The concatenated text content of this element's descendants.
  String get text {
    final out = StringBuffer();
    void walk(XmlLiteElement e) {
      for (final c in e.children) {
        switch (c) {
          case XmlLiteText(:final value):
            out.write(value);
          case XmlLiteElement():
            walk(c);
          default:
        }
      }
    }

    walk(this);
    return out.toString();
  }
}

class XmlLiteAttribute {
  XmlLiteAttribute(this.qname, this.value);
  final String qname;
  final String value;

  bool get isNamespaceDeclaration =>
      qname == 'xmlns' || qname.startsWith('xmlns:');

  String get prefix {
    final i = qname.indexOf(':');
    return i < 0 ? '' : qname.substring(0, i);
  }

  String get localName {
    final i = qname.indexOf(':');
    return i < 0 ? qname : qname.substring(i + 1);
  }
}

class XmlLiteText extends XmlLiteNode {
  XmlLiteText(this.value);
  final String value;
}

class XmlLiteComment extends XmlLiteNode {
  XmlLiteComment(this.value);
  final String value;
}

class XmlLiteProcessingInstruction extends XmlLiteNode {
  XmlLiteProcessingInstruction(this.target, this.data);
  final String target;
  final String data;
}

/// A parsed document: top-level comments/PIs around the single [root].
class XmlLiteDocument {
  XmlLiteDocument(this.children, this.root);

  final List<XmlLiteNode> children;
  final XmlLiteElement root;

  /// Parses UTF-8 (optionally BOM-prefixed) XML. Throws [FormatException]
  /// on malformed input or a DTD that declares entities.
  static XmlLiteDocument parse(Uint8List bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final text = utf8.decode(Uint8List.sublistView(bytes, start));
    return parseString(text);
  }

  static XmlLiteDocument parseString(String source) =>
      _Parser(source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
          .document();

  /// The element whose `Id`/`ID`/`id` attribute is [id], or null.
  XmlLiteElement? elementById(String id) {
    XmlLiteElement? find(XmlLiteElement e) {
      for (final a in e.attributes) {
        if ((a.localName == 'Id' ||
                a.localName == 'ID' ||
                a.localName == 'id') &&
            a.value == id) {
          return e;
        }
      }
      for (final c in e.childElements) {
        final hit = find(c);
        if (hit != null) return hit;
      }
      return null;
    }

    return find(root);
  }
}

class _Parser {
  _Parser(this.s);

  final String s;
  var i = 0;

  Never _fail(String message) => throw FormatException(message, s, i);

  bool _startsWith(String token) => s.startsWith(token, i);

  void _expect(String token) {
    if (!_startsWith(token)) _fail('expected "$token"');
    i += token.length;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A;

  void _skipSpace() {
    while (i < s.length && _isSpace(s.codeUnitAt(i))) {
      i++;
    }
  }

  static bool _isNameChar(int c) => !(_isSpace(c) ||
      c == 0x3C || // <
      c == 0x3E || // >
      c == 0x2F || // /
      c == 0x3D || // =
      c == 0x3F || // ?
      c == 0x22 ||
      c == 0x27 ||
      c == 0x21); // !

  String _name() {
    final start = i;
    while (i < s.length && _isNameChar(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) _fail('expected a name');
    return s.substring(start, i);
  }

  XmlLiteDocument document() {
    final top = <XmlLiteNode>[];
    XmlLiteElement? root;
    if (_startsWith('<?xml') &&
        i + 5 < s.length &&
        _isSpace(s.codeUnitAt(i + 5))) {
      final end = s.indexOf('?>', i);
      if (end < 0) _fail('unterminated XML declaration');
      i = end + 2;
    }
    while (true) {
      _skipSpace();
      if (i >= s.length) break;
      if (_startsWith('<!--')) {
        top.add(_comment());
      } else if (_startsWith('<?')) {
        top.add(_pi());
      } else if (_startsWith('<!DOCTYPE')) {
        _doctype();
      } else if (_startsWith('<')) {
        if (root != null) _fail('more than one root element');
        root = _element(null);
        top.add(root);
      } else {
        _fail('text outside the root element');
      }
    }
    if (root == null) _fail('no root element');
    return XmlLiteDocument(top, root);
  }

  void _doctype() {
    var depth = 0;
    final start = i;
    while (i < s.length) {
      final c = s[i++];
      if (c == '[') depth++;
      if (c == ']') depth--;
      if (c == '>' && depth == 0) {
        if (s.substring(start, i).contains('<!ENTITY')) {
          _fail('documents that declare entities are not supported');
        }
        return;
      }
    }
    _fail('unterminated DOCTYPE');
  }

  XmlLiteComment _comment() {
    _expect('<!--');
    final end = s.indexOf('-->', i);
    if (end < 0) _fail('unterminated comment');
    final value = s.substring(i, end);
    i = end + 3;
    return XmlLiteComment(value);
  }

  XmlLiteProcessingInstruction _pi() {
    _expect('<?');
    final target = _name();
    final end = s.indexOf('?>', i);
    if (end < 0) _fail('unterminated processing instruction');
    var data = s.substring(i, end);
    var k = 0;
    while (k < data.length && _isSpace(data.codeUnitAt(k))) {
      k++;
    }
    data = data.substring(k);
    i = end + 2;
    return XmlLiteProcessingInstruction(target, data);
  }

  XmlLiteElement _element(XmlLiteElement? parent) {
    _expect('<');
    final qname = _name();
    final attributes = <XmlLiteAttribute>[];
    while (true) {
      _skipSpace();
      if (_startsWith('/>')) {
        i += 2;
        return XmlLiteElement(qname, attributes)..parent = parent;
      }
      if (_startsWith('>')) {
        i++;
        break;
      }
      final name = _name();
      _skipSpace();
      _expect('=');
      _skipSpace();
      if (i >= s.length) _fail('unterminated attribute');
      final quote = s[i];
      if (quote != '"' && quote != "'") _fail('unquoted attribute value');
      i++;
      final end = s.indexOf(quote, i);
      if (end < 0) _fail('unterminated attribute value');
      final raw = s.substring(i, end);
      i = end + 1;
      // XML 1.0 §3.3.3: literal whitespace becomes a space, then
      // references are expanded (so &#xA; survives as a newline).
      attributes.add(XmlLiteAttribute(
          name, _expand(raw.replaceAll(RegExp('[\t\n]'), ' '))));
    }
    final element = XmlLiteElement(qname, attributes)..parent = parent;
    final text = StringBuffer();
    void flush() {
      if (text.isEmpty) return;
      element.children.add(XmlLiteText(text.toString())..parent = element);
      text.clear();
    }

    while (true) {
      if (i >= s.length) _fail('unterminated element <$qname>');
      final lt = s.indexOf('<', i);
      if (lt < 0) _fail('unterminated element <$qname>');
      if (lt > i) {
        text.write(_expand(s.substring(i, lt)));
        i = lt;
      }
      if (_startsWith('</')) {
        i += 2;
        final end = _name();
        if (end != qname) _fail('mismatched </$end> for <$qname>');
        _skipSpace();
        _expect('>');
        flush();
        return element;
      } else if (_startsWith('<![CDATA[')) {
        i += 9;
        final end = s.indexOf(']]>', i);
        if (end < 0) _fail('unterminated CDATA');
        text.write(s.substring(i, end));
        i = end + 3;
      } else if (_startsWith('<!--')) {
        flush();
        element.children.add(_comment()..parent = element);
      } else if (_startsWith('<?')) {
        flush();
        element.children.add(_pi()..parent = element);
      } else {
        flush();
        element.children.add(_element(element));
      }
    }
  }

  String _expand(String raw) {
    if (!raw.contains('&')) return raw;
    final out = StringBuffer();
    var k = 0;
    while (k < raw.length) {
      final amp = raw.indexOf('&', k);
      if (amp < 0) {
        out.write(raw.substring(k));
        break;
      }
      out.write(raw.substring(k, amp));
      final semi = raw.indexOf(';', amp);
      if (semi < 0) _fail('unterminated reference');
      final ref = raw.substring(amp + 1, semi);
      switch (ref) {
        case 'lt':
          out.write('<');
        case 'gt':
          out.write('>');
        case 'amp':
          out.write('&');
        case 'quot':
          out.write('"');
        case 'apos':
          out.write("'");
        default:
          if (ref.startsWith('#x')) {
            out.writeCharCode(int.parse(ref.substring(2), radix: 16));
          } else if (ref.startsWith('#')) {
            out.writeCharCode(int.parse(ref.substring(1)));
          } else {
            _fail('undeclared entity &$ref;');
          }
      }
      k = semi + 1;
    }
    return out.toString();
  }
}

/// Canonical XML flavours used by XML signatures.
enum XmlC14nMethod {
  /// Canonical XML 1.0 (`http://www.w3.org/TR/2001/REC-xml-c14n-20010315`).
  inclusive,

  /// Exclusive XML Canonicalization 1.0
  /// (`http://www.w3.org/2001/10/xml-exc-c14n#`).
  exclusive;

  static XmlC14nMethod? fromUri(String uri) => switch (uri) {
        'http://www.w3.org/TR/2001/REC-xml-c14n-20010315' ||
        'http://www.w3.org/2006/12/xml-c14n11' =>
          XmlC14nMethod.inclusive,
        'http://www.w3.org/2001/10/xml-exc-c14n#' => XmlC14nMethod.exclusive,
        _ => null,
      };
}

/// Canonicalizes the whole [document] (comments dropped), leaving out the
/// subtree [omit] - the enveloped-signature transform.
Uint8List canonicalizeDocument(XmlLiteDocument document,
    {required XmlC14nMethod method,
    XmlLiteElement? omit,
    List<String> inclusivePrefixes = const []}) {
  final out = StringBuffer();
  var beforeRoot = true;
  for (final node in document.children) {
    switch (node) {
      case XmlLiteElement():
        _Canonicalizer(method, omit, inclusivePrefixes)
            .element(node, out, apex: true);
        beforeRoot = false;
      case XmlLiteProcessingInstruction():
        if (!beforeRoot) out.write('\n');
        _writePi(node, out);
        if (beforeRoot) out.write('\n');
      default: // comments are dropped
    }
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

/// Canonicalizes the subtree rooted at [element] as a document subset: the
/// namespaces it inherits from its ancestors are rendered on it as needed.
Uint8List canonicalizeElement(XmlLiteElement element,
    {required XmlC14nMethod method,
    XmlLiteElement? omit,
    List<String> inclusivePrefixes = const []}) {
  final out = StringBuffer();
  _Canonicalizer(method, omit, inclusivePrefixes)
      .element(element, out, apex: true);
  return Uint8List.fromList(utf8.encode(out.toString()));
}

void _writePi(XmlLiteProcessingInstruction pi, StringBuffer out) {
  out.write('<?${pi.target}');
  if (pi.data.isNotEmpty) out.write(' ${pi.data}');
  out.write('?>');
}

class _Canonicalizer {
  _Canonicalizer(this.method, this.omit, this.inclusivePrefixes);

  final XmlC14nMethod method;
  final XmlLiteElement? omit;
  final List<String> inclusivePrefixes;

  /// All namespace bindings in scope at [e] (prefix -> uri; '' = default).
  static Map<String, String> _inScope(XmlLiteElement e) {
    final chain = <XmlLiteElement>[];
    for (XmlLiteElement? p = e; p != null; p = p.parent) {
      chain.add(p);
    }
    final scope = <String, String>{};
    for (final el in chain.reversed) {
      for (final a in el.attributes) {
        if (a.qname == 'xmlns') {
          scope[''] = a.value;
        } else if (a.qname.startsWith('xmlns:')) {
          scope[a.qname.substring(6)] = a.value;
        }
      }
    }
    if (scope[''] == '') scope.remove('');
    return scope;
  }

  /// [rendered] is what the nearest output ancestor has rendered (prefix ->
  /// uri, '' = default namespace).
  void element(XmlLiteElement e, StringBuffer out,
      {bool apex = false, Map<String, String> rendered = const {}}) {
    if (identical(e, omit)) return;
    final scope = _inScope(e);
    final decls = <String, String>{};
    if (method == XmlC14nMethod.inclusive) {
      for (final entry in scope.entries) {
        if (rendered[entry.key] != entry.value) {
          decls[entry.key] = entry.value;
        }
      }
      // an in-scope default that was undone: xmlns=""
      if (!scope.containsKey('') && (rendered[''] ?? '').isNotEmpty) {
        decls[''] = '';
      }
    } else {
      final utilized = <String>{e.prefix};
      for (final a in e.attributes) {
        if (!a.isNamespaceDeclaration &&
            a.prefix.isNotEmpty &&
            a.prefix != 'xml') {
          utilized.add(a.prefix);
        }
      }
      for (final p in inclusivePrefixes) {
        utilized.add(p == '#default' ? '' : p);
      }
      for (final prefix in utilized) {
        final uri = scope[prefix] ?? '';
        if (prefix.isEmpty) {
          if ((rendered[''] ?? '') != uri) decls[''] = uri;
        } else if (scope.containsKey(prefix) && rendered[prefix] != uri) {
          decls[prefix] = uri;
        }
      }
    }
    final nextRendered = {...rendered, ...decls};

    out.write('<${e.qname}');
    final prefixes = decls.keys.toList()..sort();
    for (final p in prefixes) {
      out.write(p.isEmpty ? ' xmlns="' : ' xmlns:$p="');
      _escapeAttr(decls[p]!, out);
      out.write('"');
    }
    final attrs = [
      for (final a in e.attributes)
        if (!a.isNamespaceDeclaration) a,
    ];
    String nsOf(XmlLiteAttribute a) =>
        a.prefix.isEmpty ? '' : (e.lookupNamespace(a.prefix) ?? '');
    attrs.sort((a, b) {
      final ns = nsOf(a).compareTo(nsOf(b));
      return ns != 0 ? ns : a.localName.compareTo(b.localName);
    });
    for (final a in attrs) {
      out.write(' ${a.qname}="');
      _escapeAttr(a.value, out);
      out.write('"');
    }
    out.write('>');
    for (final c in e.children) {
      switch (c) {
        case XmlLiteText(:final value):
          _escapeText(value, out);
        case XmlLiteElement():
          element(c, out, rendered: nextRendered);
        case XmlLiteProcessingInstruction():
          _writePi(c, out);
        case XmlLiteComment():
      }
    }
    out.write('</${e.qname}>');
  }

  static void _escapeText(String v, StringBuffer out) {
    for (var k = 0; k < v.length; k++) {
      final c = v.codeUnitAt(k);
      switch (c) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0x0D:
          out.write('&#xD;');
        default:
          out.writeCharCode(c);
      }
    }
  }

  static void _escapeAttr(String v, StringBuffer out) {
    for (var k = 0; k < v.length; k++) {
      final c = v.codeUnitAt(k);
      switch (c) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x22:
          out.write('&quot;');
        case 0x09:
          out.write('&#x9;');
        case 0x0A:
          out.write('&#xA;');
        case 0x0D:
          out.write('&#xD;');
        default:
          out.writeCharCode(c);
      }
    }
  }
}

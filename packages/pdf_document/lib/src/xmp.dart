/// XMP metadata packet construction (ISO 16684-1) for the identification
/// schemas PDF/A and PDF/UA require - built as plain XML text so it works on
/// the Dart VM and the web with no platform XML dependency.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Builds an XMP packet with the Dublin Core, XMP Basic, PDF, and (when
/// requested) the PDF/A and PDF/UA identification schemas.
///
/// [pdfaPart] + [pdfaConformance] write the `pdfaid` schema (e.g. part 2,
/// conformance 'B' → PDF/A-2b). [pdfUaPart] writes the `pdfuaid` schema
/// (part 1 → PDF/UA-1). Dates are ISO-8601; [title]/[author] populate
/// `dc:title`/`dc:creator`.
Uint8List buildXmpPacket({
  String? title,
  String? author,
  String? subject,
  String? creatorTool,
  String? producer,
  String? createDate,
  String? modifyDate,
  int? pdfaPart,
  String? pdfaConformance,
  int? pdfUaPart,
}) {
  final b = StringBuffer()
    ..write('<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n')
    ..write('<x:xmpmeta xmlns:x="adobe:ns:meta/">\n')
    ..write(' <rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n')
    ..write('  <rdf:Description rdf:about=""\n')
    ..write('    xmlns:dc="http://purl.org/dc/elements/1.1/"\n')
    ..write('    xmlns:xmp="http://ns.adobe.com/xap/1.0/"\n')
    ..write('    xmlns:pdf="http://ns.adobe.com/pdf/1.3/"\n')
    ..write('    xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"\n')
    ..write('    xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/">\n');

  if (title != null) {
    b
      ..write('   <dc:title><rdf:Alt>'
          '<rdf:li xml:lang="x-default">')
      ..write(_esc(title))
      ..write('</rdf:li></rdf:Alt></dc:title>\n');
  }
  if (author != null) {
    b
      ..write('   <dc:creator><rdf:Seq><rdf:li>')
      ..write(_esc(author))
      ..write('</rdf:li></rdf:Seq></dc:creator>\n');
  }
  if (subject != null) {
    b
      ..write('   <dc:description><rdf:Alt>'
          '<rdf:li xml:lang="x-default">')
      ..write(_esc(subject))
      ..write('</rdf:li></rdf:Alt></dc:description>\n');
  }
  if (creatorTool != null) {
    b.write('   <xmp:CreatorTool>${_esc(creatorTool)}</xmp:CreatorTool>\n');
  }
  if (createDate != null) {
    b.write('   <xmp:CreateDate>${_esc(createDate)}</xmp:CreateDate>\n');
  }
  if (modifyDate != null) {
    b.write('   <xmp:ModifyDate>${_esc(modifyDate)}</xmp:ModifyDate>\n');
  }
  if (producer != null) {
    b.write('   <pdf:Producer>${_esc(producer)}</pdf:Producer>\n');
  }
  if (pdfaPart != null) {
    b.write('   <pdfaid:part>$pdfaPart</pdfaid:part>\n');
    if (pdfaConformance != null) {
      b.write('   <pdfaid:conformance>${_esc(pdfaConformance)}'
          '</pdfaid:conformance>\n');
    }
  }
  if (pdfUaPart != null) {
    b.write('   <pdfuaid:part>$pdfUaPart</pdfuaid:part>\n');
  }

  b
    ..write('  </rdf:Description>\n')
    ..write(' </rdf:RDF>\n')
    ..write('</x:xmpmeta>\n')
    // ~2KB of padding so a reader can edit in place, then the trailer.
    ..write('${' ' * 100}\n' * 20)
    ..write('<?xpacket end="w"?>');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Reads the `pdfuaid:part` value from an XMP packet's bytes, or null. Lenient
/// substring/regex scan - XMP is RDF/XML but the identifier is unambiguous.
int? readPdfUaPart(Uint8List xmp) => _readIntField(xmp, 'pdfuaid:part');

/// Reads the `pdfaid:part` value from an XMP packet, or null.
int? readPdfaPart(Uint8List xmp) => _readIntField(xmp, 'pdfaid:part');

/// Reads the `pdfaid:conformance` value (e.g. 'B') from an XMP packet, or null.
String? readPdfaConformance(Uint8List xmp) {
  final text = _decode(xmp);
  // Element form: <pdfaid:conformance>B</pdfaid:conformance>
  final el = RegExp(r'pdfaid:conformance>\s*([A-Za-z])').firstMatch(text);
  if (el != null) return el.group(1);
  // Attribute form: pdfaid:conformance="B"
  final attr =
      RegExp(r'pdfaid:conformance\s*=\s*"([A-Za-z])"').firstMatch(text);
  return attr?.group(1);
}

int? _readIntField(Uint8List xmp, String field) {
  final text = _decode(xmp);
  final el = RegExp('${RegExp.escape(field)}>\\s*(\\d+)').firstMatch(text);
  if (el != null) return int.tryParse(el.group(1)!);
  final attr = RegExp('${RegExp.escape(field)}\\s*=\\s*"(\\d+)"')
      .firstMatch(text);
  return attr == null ? null : int.tryParse(attr.group(1)!);
}

String _decode(Uint8List xmp) => utf8.decode(xmp, allowMalformed: true);

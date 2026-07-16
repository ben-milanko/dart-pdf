import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'content_writer.dart';
import 'document.dart';
import 'rect.dart';
import 'type0_metrics.dart';

/// What a content element draws.
enum PdfElementKind {
  /// One text-showing operation (`Tj`, `'`, `"`, or `TJ`).
  text,

  /// A painted path: construction operators through their paint operator.
  path,

  /// An image XObject invocation.
  image,

  /// A form XObject invocation.
  form,

  /// An inline image (`BI … EI`).
  inlineImage,

  /// A `sh` shading fill.
  shading,
}

/// One deletable drawing on a page: a contiguous run of content-stream
/// operations together with what they paint and roughly where.
class PdfContentElement {
  PdfContentElement._({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.text,
    this.resourceName,
    this.bounds,
    this.imageWidth,
    this.imageHeight,
  });

  /// Stable handle for [PdfContentEditing.deleteElements].
  final int id;

  final PdfElementKind kind;

  /// Operation index range `[start, end)` in the parsed content.
  final int start;
  final int end;

  /// The shown characters, Latin-1-decoded, for [PdfElementKind.text].
  /// Multi-byte and symbolic encodings come out garbled but unique.
  final String? text;

  /// The active /Font resource name for [PdfElementKind.text], or the
  /// /XObject resource name for [PdfElementKind.image] and
  /// [PdfElementKind.form].
  final String? resourceName;

  /// Approximate user-space bounding box: exact anchor points for paths
  /// and placed images, estimated extents for text (Helvetica metrics
  /// stand in for the real font). Null when no geometry is tracked
  /// (shading fills, degenerate transforms).
  final PdfRect? bounds;

  /// Pixel width for image-like elements when declared by the content stream
  /// or image XObject dictionary.
  final int? imageWidth;

  /// Pixel height for image-like elements when declared by the content stream
  /// or image XObject dictionary.
  final int? imageHeight;

  @override
  String toString() => 'PdfContentElement#$id($kind'
      '${text != null ? ' "$text"' : ''}'
      '${resourceName != null ? ' /$resourceName' : ''}'
      '${bounds != null ? ' $bounds' : ''})';
}

/// The drawable elements of one page's content stream, in paint order.
///
/// Parsing tracks the transformation and text matrices well enough to
/// attach approximate bounds to each element; it is not a renderer.
/// Elements inside form XObjects belong to the form, not the page, and
/// are not listed.
class PdfPageElements {
  PdfPageElements._(
      this.document, this.pageIndex, this.operations, this.elements);

  final PdfDocument document;
  final int pageIndex;

  /// The parsed content-stream operations the elements index into.
  final List<ContentOperation> operations;

  final List<PdfContentElement> elements;

  static PdfPageElements of(PdfDocument document, int pageIndex) {
    final page = document.page(pageIndex);
    final operations = ContentStreamParser.parse(page.contentBytes());
    final cos = document.cos;
    final resources = page.resources;

    final elements = <PdfContentElement>[];
    var ctm = _identity;
    final stack = <_Matrix>[];
    var text = _TextState();
    var pathStart = -1;
    var pathPoints = <(double, double)>[];

    void addElement(PdfElementKind kind, int start, int end,
        {String? shown,
        String? resource,
        PdfRect? bounds,
        int? imageWidth,
        int? imageHeight}) {
      elements.add(PdfContentElement._(
        id: elements.length,
        kind: kind,
        start: start,
        end: end,
        text: shown,
        resourceName: resource,
        bounds: bounds,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ));
    }

    // composite (/Type0) fonts draw 2-byte codes: resolve each named font
    // once to a decoder that turns codes into real text (via /ToUnicode) and
    // advance widths (via the descendant /W), so text elements read and
    // measure correctly instead of as Latin-1 byte pairs.
    final type0Decoders = <String, _Type0Decode?>{};
    _Type0Decode? type0For(String? name) {
      if (name == null) return null;
      return type0Decoders.putIfAbsent(name, () {
        final fonts = cos.resolve(resources['Font']);
        if (fonts is! CosDictionary) return null;
        final f = cos.resolve(fonts[name]);
        if (f is! CosDictionary) return null;
        final sub = cos.resolve(f['Subtype']);
        if (sub is! CosName || sub.value != 'Type0') return null;
        final toUni = cos.resolve(f['ToUnicode']);
        final text = toUni is CosStream
            ? parseToUnicodeCmap(cos.decodeStreamData(toUni))
            : <int, String>{};
        var widths = <int, double>{};
        var dw = 1000.0;
        final desc = cos.resolve(f['DescendantFonts']);
        if (desc is CosArray && desc.items.isNotEmpty) {
          final cid = cos.resolve(desc.items.first);
          if (cid is CosDictionary) {
            widths = parseCidWidths(cos, cid);
            dw = cidDefaultWidth(cos, cid);
          }
        }
        return _Type0Decode(text, widths, dw);
      });
    }

    double number(CosObject o) => switch (o) {
          CosInteger(:final value) => value.toDouble(),
          CosReal(:final value) => value,
          _ => 0,
        };

    int? integer(CosObject? o) {
      final resolved = cos.resolve(o);
      return switch (resolved) {
        CosInteger(:final value) => value,
        CosReal(:final value) => value.round(),
        _ => null,
      };
    }

    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      final operands = op.operands;
      switch (op.operator) {
        case 'q':
          stack.add(ctm);
        case 'Q':
          if (stack.isNotEmpty) ctm = stack.removeLast();
        case 'cm':
          if (operands.length >= 6) {
            ctm = _multiply((
              number(operands[0]),
              number(operands[1]),
              number(operands[2]),
              number(operands[3]),
              number(operands[4]),
              number(operands[5]),
            ), ctm);
          }

        // path construction
        case 'm' || 'l':
          if (pathStart < 0) pathStart = i;
          if (operands.length >= 2) {
            pathPoints.add((number(operands[0]), number(operands[1])));
          }
        case 'c':
          if (pathStart < 0) pathStart = i;
          for (var j = 0; j + 1 < operands.length; j += 2) {
            pathPoints.add((number(operands[j]), number(operands[j + 1])));
          }
        case 'v' || 'y':
          if (pathStart < 0) pathStart = i;
          for (var j = 0; j + 1 < operands.length; j += 2) {
            pathPoints.add((number(operands[j]), number(operands[j + 1])));
          }
        case 're':
          if (pathStart < 0) pathStart = i;
          if (operands.length >= 4) {
            final x = number(operands[0]), y = number(operands[1]);
            final w = number(operands[2]), h = number(operands[3]);
            pathPoints
              ..add((x, y))
              ..add((x + w, y + h));
          }
        case 'h':
          if (pathStart < 0) pathStart = i;
        // W/W* mark the path as a clip; they ride along as state

        // path painting
        case 'S' || 's' || 'f' || 'F' || 'f*' || 'B' || 'B*' || 'b' || 'b*':
          if (pathStart >= 0) {
            addElement(PdfElementKind.path, pathStart, i + 1,
                bounds: _hull([
                  for (final (x, y) in pathPoints) _apply(ctm, x, y),
                ]));
          }
          pathStart = -1;
          pathPoints = [];
        case 'n':
          // a no-op paint: with W it defines a clip (kept as state),
          // without it the path simply vanishes - either way no element
          pathStart = -1;
          pathPoints = [];

        // text
        case 'BT':
          text = _TextState();
        case 'Tf':
          if (operands.length >= 2) {
            text.size = number(operands[1]);
            text.fontName =
                operands[0] is CosName ? (operands[0] as CosName).value : null;
          }
        case 'TL':
          if (operands.isNotEmpty) text.leading = number(operands[0]);
        case 'Td':
          if (operands.length >= 2) {
            text.newline(number(operands[0]), number(operands[1]));
          }
        case 'TD':
          if (operands.length >= 2) {
            text.leading = -number(operands[1]);
            text.newline(number(operands[0]), number(operands[1]));
          }
        case 'Tm':
          if (operands.length >= 6) {
            text.setMatrix((
              number(operands[0]),
              number(operands[1]),
              number(operands[2]),
              number(operands[3]),
              number(operands[4]),
              number(operands[5]),
            ));
          }
        case 'T*':
          text.newline(0, -text.leading);
        case 'Tj' || "'" || '"' || 'TJ':
          if (op.operator == "'") text.newline(0, -text.leading);
          if (op.operator == '"') text.newline(0, -text.leading);
          final decoder = type0For(text.fontName);
          final shown = StringBuffer();
          var advanceEm = 0.0; // thousandths of an em, for /Type0 measurement
          void show(CosObject o) {
            if (o is! CosString) return;
            if (decoder == null) {
              shown.write(latin1.decode(o.bytes));
              return;
            }
            final b = o.bytes;
            for (var k = 0; k + 1 < b.length; k += 2) {
              final code = (b[k] << 8) | b[k + 1];
              shown.write(decoder.text[code] ?? '');
              advanceEm += decoder.widthOf(code);
            }
          }

          if (op.operator == 'TJ' && operands.isNotEmpty) {
            final array = operands[0];
            if (array is CosArray) {
              for (final item in array.items) {
                if (item is CosString) {
                  show(item);
                } else if (decoder != null &&
                    (item is CosInteger || item is CosReal)) {
                  advanceEm -= number(item); // kern, in thousandths of an em
                }
              }
            }
          } else if (op.operator == '"' && operands.length >= 3) {
            show(operands[2]);
          } else if (operands.isNotEmpty) {
            show(operands[0]);
          }
          final string = shown.toString();
          final width = decoder != null
              ? advanceEm / 1000 * text.size
              : measureHelvetica(string, text.size);
          final m = _multiply(text.matrix, ctm);
          addElement(PdfElementKind.text, i, i + 1,
              shown: string,
              resource: text.fontName,
              bounds: _hull([
                _apply(m, 0, -0.2 * text.size),
                _apply(m, width, -0.2 * text.size),
                _apply(m, 0, text.size),
                _apply(m, width, text.size),
              ]));
          text.advance(width);

        // XObjects, inline images, shading
        case 'Do':
          final name = operands.isNotEmpty && operands[0] is CosName
              ? (operands[0] as CosName).value
              : null;
          final xobjects = cos.resolve(resources['XObject']);
          final xobject = name != null && xobjects is CosDictionary
              ? cos.resolve(xobjects[name])
              : null;
          final subtypeName = xobject is CosStream
              ? cos.resolve(xobject.dictionary['Subtype'])
              : null;
          final subtype = subtypeName is CosName ? subtypeName.value : null;
          if (subtype == 'Form') {
            PdfRect? bounds;
            final bbox = xobject is CosStream
                ? pdfRectFrom(cos, xobject.dictionary['BBox'])
                : null;
            if (bbox != null) {
              bounds = _hull([
                _apply(ctm, bbox.left, bbox.bottom),
                _apply(ctm, bbox.right, bbox.bottom),
                _apply(ctm, bbox.left, bbox.top),
                _apply(ctm, bbox.right, bbox.top),
              ]);
            }
            addElement(PdfElementKind.form, i, i + 1,
                resource: name, bounds: bounds);
          } else {
            addElement(PdfElementKind.image, i, i + 1,
                resource: name,
                bounds: _unitSquare(ctm),
                imageWidth: xobject is CosStream
                    ? integer(xobject.dictionary['Width'])
                    : null,
                imageHeight: xobject is CosStream
                    ? integer(xobject.dictionary['Height'])
                    : null);
          }
        case 'BI':
          final dict = operands.isNotEmpty && operands[0] is CosDictionary
              ? operands[0] as CosDictionary
              : null;
          addElement(PdfElementKind.inlineImage, i, i + 1,
              bounds: _unitSquare(ctm),
              imageWidth: integer(dict?['W'] ?? dict?['Width']),
              imageHeight: integer(dict?['H'] ?? dict?['Height']));
        case 'sh':
          addElement(PdfElementKind.shading, i, i + 1);
      }
    }
    return PdfPageElements._(document, pageIndex, operations, elements);
  }

  /// Elements whose bounds contain the user-space point ([x], [y]),
  /// topmost (painted last) first.
  List<PdfContentElement> elementsAt(double x, double y) => [
        for (final element in elements.reversed)
          if (element.bounds?.contains(x, y) ?? false) element,
      ];

  /// Serializes [operations] back into content-stream bytes, skipping the
  /// operation indexes in [drop] and writing [replacements] instead where
  /// provided (used to keep the side effects of `'` and `"`).
  Uint8List serialize({
    Set<int> drop = const {},
    Map<int, String> replacements = const {},
  }) {
    final out = BytesBuilder();
    for (var i = 0; i < operations.length; i++) {
      if (drop.contains(i)) {
        final replacement = replacements[i];
        if (replacement != null) out.add(latin1.encode('$replacement\n'));
        continue;
      }
      ContentStreamSerializer.writeOperation(operations[i], out);
    }
    return out.takeBytes();
  }
}

class _TextState {
  _Matrix matrix = _identity;
  _Matrix lineMatrix = _identity;
  double size = 0;
  double leading = 0;
  String? fontName;

  void setMatrix(_Matrix m) {
    matrix = m;
    lineMatrix = m;
  }

  void newline(double tx, double ty) {
    lineMatrix = _multiply((1, 0, 0, 1, tx, ty), lineMatrix);
    matrix = lineMatrix;
  }

  void advance(double width) {
    matrix = _multiply((1, 0, 0, 1, width, 0), matrix);
  }
}

/// A composite (/Type0) font's text + width lookup for one page: code →
/// Unicode (from `/ToUnicode`) and code → advance (from the descendant `/W`,
/// falling back to `/DW`).
class _Type0Decode {
  _Type0Decode(this.text, this._widths, this._dw);

  final Map<int, String> text;
  final Map<int, double> _widths;
  final double _dw;

  double widthOf(int code) => _widths[code] ?? _dw;
}

typedef _Matrix = (double, double, double, double, double, double);

const _Matrix _identity = (1, 0, 0, 1, 0, 0);

_Matrix _multiply(_Matrix m, _Matrix n) => (
      m.$1 * n.$1 + m.$2 * n.$3,
      m.$1 * n.$2 + m.$2 * n.$4,
      m.$3 * n.$1 + m.$4 * n.$3,
      m.$3 * n.$2 + m.$4 * n.$4,
      m.$5 * n.$1 + m.$6 * n.$3 + n.$5,
      m.$5 * n.$2 + m.$6 * n.$4 + n.$6,
    );

(double, double) _apply(_Matrix m, double x, double y) =>
    (m.$1 * x + m.$3 * y + m.$5, m.$2 * x + m.$4 * y + m.$6);

PdfRect? _hull(List<(double, double)> points) {
  if (points.isEmpty) return null;
  var minX = points.first.$1, maxX = points.first.$1;
  var minY = points.first.$2, maxY = points.first.$2;
  for (final (x, y) in points) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return PdfRect(minX, minY, maxX, maxY);
}

PdfRect? _unitSquare(_Matrix ctm) => _hull([
      _apply(ctm, 0, 0),
      _apply(ctm, 1, 0),
      _apply(ctm, 0, 1),
      _apply(ctm, 1, 1),
    ]);

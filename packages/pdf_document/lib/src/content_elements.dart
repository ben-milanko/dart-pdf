import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'matrix_geometry.dart';
import 'rect.dart';
import 'simple_font.dart';
import 'type0_font.dart';

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

/// Where a [PdfElementKind.text] run sits in the content stream's own text
/// space, captured at the moment it draws.
///
/// This is what [PdfContentEditing.moveElements] needs to reposition a run
/// without disturbing the rest of its text object: the matrices to restore
/// afterwards, and the advance to replay so whatever follows on the line
/// still starts where it did.
class PdfTextPlacement {
  const PdfTextPlacement({
    required this.matrix,
    required this.lineMatrix,
    required this.entryLineMatrix,
    required this.fontSize,
    required this.advance,
  });

  /// The text matrix the glyphs draw under - after any line move the
  /// operator performs itself (`'` and `\"` begin with a `T*`).
  final PdfMatrix matrix;

  /// The line matrix in effect for the run: the origin a following
  /// `Td`/`TD`/`T*`/`'`/`\"` moves relative to.
  final PdfMatrix lineMatrix;

  /// The line matrix *before* the operator's own line move. Equal to
  /// [lineMatrix] for `Tj` and `TJ`.
  final PdfMatrix entryLineMatrix;

  /// The font size (`Tf`) in effect.
  final double fontSize;

  /// How far the run advances the text matrix, in text space: the sum of
  /// the glyph widths and `TJ` kerns, already scaled by [fontSize].
  final double advance;
}

/// One deletable drawing on a page: a contiguous run of content-stream
/// operations together with what they paint and roughly where.
class PdfContentElement {
  PdfContentElement._({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.ctm,
    this.text,
    this.resourceName,
    this.bounds,
    this.imageWidth,
    this.imageHeight,
    this.textPlacement,
  });

  /// Stable handle for [PdfContentEditing.deleteElements].
  final int id;

  final PdfElementKind kind;

  /// Operation index range `[start, end)` in the parsed content.
  final int start;
  final int end;

  /// The text this run shows, for [PdfElementKind.text], decoded through the
  /// font's own encoding: `/ToUnicode` and `/Encoding` `/Differences` for a
  /// simple font ([SimpleFont]), `/ToUnicode` for a composite one
  /// ([Type0Font]). A subsetted font that renumbered its codes therefore
  /// reads as the text on the page, not as its raw bytes.
  final String? text;

  /// The active /Font resource name for [PdfElementKind.text], or the
  /// /XObject resource name for [PdfElementKind.image] and
  /// [PdfElementKind.form].
  final String? resourceName;

  /// Approximate user-space bounding box: exact anchor points for paths
  /// and placed images, estimated extents for text (advances come from the
  /// font's own `/Widths` or `/W`, the vertical extent is still a guess).
  /// Null when no geometry is tracked (shading fills, degenerate
  /// transforms).
  final PdfRect? bounds;

  /// Pixel width for image-like elements when declared by the content stream
  /// or image XObject dictionary.
  final int? imageWidth;

  /// Pixel height for image-like elements when declared by the content stream
  /// or image XObject dictionary.
  final int? imageHeight;

  /// The transformation matrix in effect when the element paints, mapping
  /// the space its operators speak in onto page (user) space. Repositioning
  /// works through it: a page-space shift becomes
  /// `ctm × translation × ctm⁻¹` (see [translationUnder]).
  final PdfMatrix ctm;

  /// Text-space placement, for [PdfElementKind.text] elements only.
  final PdfTextPlacement? textPlacement;

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
    var ctm = PdfMatrix.identity;
    final stack = <PdfMatrix>[];
    var text = _TextState();
    var pathStart = -1;
    var pathPoints = <(double, double)>[];

    void addElement(PdfElementKind kind, int start, int end,
        {String? shown,
        String? resource,
        PdfRect? bounds,
        int? imageWidth,
        int? imageHeight,
        PdfTextPlacement? placement}) {
      elements.add(PdfContentElement._(
        id: elements.length,
        kind: kind,
        start: start,
        end: end,
        ctm: ctm,
        text: shown,
        resourceName: resource,
        bounds: bounds,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        textPlacement: placement,
      ));
    }

    // simple fonts draw one byte per glyph, but the byte is not the
    // character: /Differences and subset renumbering remap it freely, so
    // resolve each named font once to a code -> text table.
    final simpleFonts = <String?, SimpleFont>{};
    SimpleFont simpleFor(String? name) => simpleFonts.putIfAbsent(name, () {
          final fonts = cos.resolve(resources['Font']);
          final f = name == null || fonts is! CosDictionary
              ? null
              : cos.resolve(fonts[name]);
          return SimpleFont.decode(cos, f is CosDictionary ? f : null);
        });

    // composite (/Type0) fonts draw 2-byte codes: resolve each named font
    // once to a decoder that turns codes into real text (via /ToUnicode) and
    // advance widths (via the descendant /W), so text elements read and
    // measure correctly instead of as Latin-1 byte pairs.
    final type0Decoders = <String, Type0Font?>{};
    Type0Font? type0For(String? name) {
      if (name == null) return null;
      return type0Decoders.putIfAbsent(name, () {
        final fonts = cos.resolve(resources['Font']);
        if (fonts is! CosDictionary) return null;
        final f = cos.resolve(fonts[name]);
        if (f is! CosDictionary) return null;
        final sub = cos.resolve(f['Subtype']);
        if (sub is! CosName || sub.value != 'Type0') return null;
        return Type0Font.decode(cos, f);
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
            ctm = PdfMatrix(
              number(operands[0]),
              number(operands[1]),
              number(operands[2]),
              number(operands[3]),
              number(operands[4]),
              number(operands[5]),
            ).concat(ctm);
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
                bounds: boundsOfPoints([
                  for (final (x, y) in pathPoints) ctm.apply(x, y),
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
            text.setMatrix(PdfMatrix(
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
          // captured before the operator's own line move: repositioning the
          // run has to seed the text matrix *ahead* of that move
          final entryLine = text.lineMatrix;
          if (op.operator == "'") text.newline(0, -text.leading);
          if (op.operator == '"') text.newline(0, -text.leading);
          final decoder = type0For(text.fontName);
          final simple = decoder == null ? simpleFor(text.fontName) : null;
          final shown = StringBuffer();
          var advanceEm = 0.0; // thousandths of an em, for measurement
          var showedString = false;
          void show(CosObject o) {
            if (o is! CosString) return;
            showedString = true;
            final b = o.bytes;
            if (simple != null) {
              for (final code in b) {
                shown.write(simple.textFor(code));
                advanceEm += simple.widthOf(code);
              }
            } else if (decoder != null) {
              for (var k = 0; k + 1 < b.length; k += 2) {
                final code = (b[k] << 8) | b[k + 1];
                shown.write(decoder.codeToText[code] ?? '');
                advanceEm += decoder.widthOf(code);
              }
            }
          }

          if (op.operator == 'TJ' && operands.isNotEmpty) {
            final array = operands[0];
            if (array is CosArray) {
              for (final item in array.items) {
                if (item is CosString) {
                  show(item);
                } else if (item is CosInteger || item is CosReal) {
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
          // both paths accumulate the run's advance from the font's own
          // metrics now, so the estimate no longer assumes Helvetica.
          final width = advanceEm / 1000 * text.size;
          final m = text.matrix.concat(ctm);
          // A `TJ` array of pure kerns shows nothing - it only advances the
          // text matrix. It is not a drawing, so it is not an element; and
          // keeping it out is what lets [PdfContentEditing.moveElements]
          // splice its advance compensation in without renumbering the
          // elements after it.
          if (showedString) {
            addElement(PdfElementKind.text, i, i + 1,
                shown: string,
                resource: text.fontName,
                bounds: boundsOfPoints([
                  m.apply(0, -0.2 * text.size),
                  m.apply(width, -0.2 * text.size),
                  m.apply(0, text.size),
                  m.apply(width, text.size),
                ]),
                placement: PdfTextPlacement(
                  matrix: text.matrix,
                  lineMatrix: text.lineMatrix,
                  entryLineMatrix: entryLine,
                  fontSize: text.size,
                  advance: width,
                ));
          }
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
              bounds = boundsUnderMatrix(ctm, bbox);
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

  /// The page's operations with only the elements [keep] accepts still
  /// drawing.
  ///
  /// A dropped text run is replaced by the advance it would have made - a
  /// kern-only `TJ`, preceded by the line move `'` and `"` perform
  /// themselves - so every run after it in the same text object stays
  /// exactly where it was. Other kinds simply disappear; nothing downstream
  /// depends on a path or an image having been painted.
  ///
  /// Two useful lists come out of one parse: "the page without this
  /// element" (`(e) => e.id != id`) and "this element by itself"
  /// (`(e) => e.id == id`). The editor renders both to float a dragged
  /// drawing - the first fills the hole it leaves, the second is the
  /// artwork that travels, free of whatever else shares its bounding box.
  List<ContentOperation> operationsRetaining(
      bool Function(PdfContentElement element) keep) {
    final dropped = <int, PdfContentElement>{};
    for (final element in elements) {
      if (keep(element)) continue;
      for (var i = element.start; i < element.end; i++) {
        dropped[i] = element;
      }
    }
    if (dropped.isEmpty) return operations;
    final out = <ContentOperation>[];
    for (var i = 0; i < operations.length; i++) {
      final element = dropped[i];
      if (element == null) {
        out.add(operations[i]);
      } else if (i == element.start) {
        out.addAll(_standIn(element, operations[i]));
      }
    }
    return out;
  }

  /// What a dropped element leaves behind: nothing at all, unless it is text,
  /// which owes the rest of its text object the advance it would have made.
  static List<ContentOperation> _standIn(
      PdfContentElement element, ContentOperation op) {
    if (element.kind != PdfElementKind.text) return const [];
    final out = <ContentOperation>[];
    if (op.operator == '"' && op.operands.length >= 3) {
      out
        ..add(ContentOperation('Tw', [op.operands[0]]))
        ..add(ContentOperation('Tc', [op.operands[1]]));
    }
    if (op.operator == "'" || op.operator == '"') {
      out.add(ContentOperation('T*', const []));
    }
    final placement = element.textPlacement;
    if (placement != null &&
        placement.fontSize > 0 &&
        placement.advance.abs() > 1e-9) {
      out.add(ContentOperation('TJ', [
        CosArray([CosReal(-1000 * placement.advance / placement.fontSize)]),
      ]));
    }
    return out;
  }

  /// Serializes [operations] back into content-stream bytes, skipping the
  /// operation indexes in [drop] and writing [replacements] instead where
  /// provided (used to keep the side effects of `'` and `"`).
  ///
  /// [before] and [after] splice raw operator text around an operation
  /// without disturbing its index - how
  /// [PdfContentEditing.moveElements] brackets a drawing with a
  /// `q`/`cm`…`Q` or a pair of `Tm`s.
  Uint8List serialize({
    Set<int> drop = const {},
    Map<int, String> replacements = const {},
    Map<int, String> before = const {},
    Map<int, String> after = const {},
  }) {
    final out = BytesBuilder();
    for (var i = 0; i < operations.length; i++) {
      final prefix = before[i];
      if (prefix != null) out.add(latin1.encode('$prefix\n'));
      if (drop.contains(i)) {
        final replacement = replacements[i];
        if (replacement != null) out.add(latin1.encode('$replacement\n'));
      } else {
        ContentStreamSerializer.writeOperation(operations[i], out);
      }
      final suffix = after[i];
      if (suffix != null) out.add(latin1.encode('$suffix\n'));
    }
    return out.takeBytes();
  }
}

class _TextState {
  PdfMatrix matrix = PdfMatrix.identity;
  PdfMatrix lineMatrix = PdfMatrix.identity;
  double size = 0;
  double leading = 0;
  String? fontName;

  void setMatrix(PdfMatrix m) {
    matrix = m;
    lineMatrix = m;
  }

  void newline(double tx, double ty) {
    lineMatrix = PdfMatrix.translation(tx, ty).concat(lineMatrix);
    matrix = lineMatrix;
  }

  void advance(double width) {
    matrix = PdfMatrix.translation(width, 0).concat(matrix);
  }
}

PdfRect? _unitSquare(PdfMatrix ctm) => boundsOfPoints([
      ctm.apply(0, 0),
      ctm.apply(1, 0),
      ctm.apply(0, 1),
      ctm.apply(1, 1),
    ]);

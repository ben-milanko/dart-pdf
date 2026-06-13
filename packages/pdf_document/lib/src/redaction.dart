part of 'editor.dart';

/// Applying (burning) redaction marks created by
/// [PdfAnnotationEditing.addRedaction].
///
/// True redaction per §12.5.6.23: covered text and images are *removed
/// from the content-stream bytes* — not merely painted over — then the
/// /IC fill is drawn into the page content and the /Redact annotations are
/// deleted. The result is irreversible: a viewer (or a byte search of the
/// saved file) cannot recover the glyphs that were under a redaction rect.
///
/// Honest limitations (each documented at the relevant site):
///  * Per-glyph splitting is exact for simple single-byte fonts. Composite
///    (`/Type0`) text-showing operations that touch a rect are dropped
///    whole rather than split (the bytes are CID codes, not characters).
///  * Image and form XObjects fully inside a rect are dropped; partially
///    covered ones are left in place and the /IC fill box covers the
///    overlapping portion (their off-rect content stays). Form XObject
///    *internal* bytes are not recursively split.
extension PdfRedactionApply on PdfEditor {
  /// Burns every `/Redact` mark on [pageIndex] (or on every page when
  /// null) and returns the full edited file bytes.
  ///
  /// Removes the covered glyphs/images from the content stream, paints the
  /// /IC fill, removes the /Redact annotations, and scrubs any annotation
  /// whose /Rect is fully inside a redaction region.
  ///
  /// Unlike every other editor operation, the burn is NOT written as an
  /// incremental update — an incremental save keeps the original bytes
  /// (and therefore the redacted glyphs) physically in the file, where a
  /// byte search would recover them. Instead the whole document is
  /// re-serialized fresh (a compaction), dropping the superseded content
  /// streams entirely. This makes the result irreversible at the cost of
  /// invalidating any existing digital signature (redaction changes the
  /// content, so signatures could not survive regardless).
  ///
  /// Throws [UnsupportedError] for encrypted documents (the compaction
  /// would mix plaintext strings with the file's ciphertext streams);
  /// decrypt the file before redacting.
  Uint8List applyRedactions([int? pageIndex]) {
    final pages = pageIndex != null
        ? [pageIndex]
        : [for (var i = 0; i < document.pageCount; i++) i];
    var burned = 0;
    for (final i in pages) {
      if (_applyRedactionsOnPage(i)) burned++;
    }
    // No marks anywhere: keep any other staged edits as an incremental save.
    if (burned == 0) return save();
    return _compactedSave();
  }

  /// Re-serializes the document's current in-memory state into a fresh file
  /// with renumbered objects, dropping everything no longer reachable from
  /// the catalog (the redacted-away content streams and annotations). This
  /// is what makes redaction irreversible.
  Uint8List _compactedSave() {
    final cos = document.cos;
    if (cos.encryption != null) {
      throw UnsupportedError(
          'applyRedactions cannot compact an encrypted document; decrypt it '
          'before redacting');
    }
    final rootRef = cos.trailer['Root'];
    if (rootRef is! CosReference) {
      throw StateError('document has no indirect /Root');
    }
    final infoRef = cos.trailer['Info'];

    final order = <int>[]; // old object numbers, in discovery order
    final newNumber = <int, int>{}; // old → new (1-based)
    final generation = <int, int>{};
    final queue = <int>[];

    void discover(CosObject node) {
      if (node is! CosReference) return;
      if (newNumber.containsKey(node.objectNumber)) return;
      newNumber[node.objectNumber] = order.length + 1;
      generation[node.objectNumber] = node.generation;
      order.add(node.objectNumber);
      queue.add(node.objectNumber);
    }

    void scan(CosObject node) {
      switch (node) {
        case CosArray():
          for (final item in node.items) {
            item is CosReference ? discover(item) : scan(item);
          }
        case CosDictionary():
          node.entries.forEach((_, value) {
            value is CosReference ? discover(value) : scan(value);
          });
        case CosStream():
          scan(node.dictionary);
        default:
          break;
      }
    }

    discover(rootRef);
    if (infoRef is CosReference) discover(infoRef);
    var head = 0;
    while (head < queue.length) {
      final number = queue[head++];
      scan(cos.resolve(CosReference(number, generation[number]!)));
    }

    CosObject remap(CosObject node) {
      switch (node) {
        case CosReference():
          final n = newNumber[node.objectNumber];
          return n != null ? CosReference(n, 0) : CosNull.instance;
        case CosArray():
          return CosArray([for (final item in node.items) remap(item)]);
        case CosDictionary():
          final out = CosDictionary();
          node.entries.forEach((key, value) => out[key] = remap(value));
          return out;
        case CosStream():
          final dict = remap(node.dictionary) as CosDictionary
            ..['Length'] = CosInteger(node.rawBytes.length);
          return CosStream(dict, node.rawBytes);
        default:
          return node;
      }
    }

    final builder = CosDocumentBuilder();
    for (final number in order) {
      builder.add(remap(cos.resolve(CosReference(number, generation[number]!))));
    }
    return builder.build(
      root: CosReference(newNumber[rootRef.objectNumber]!, 0),
      info: infoRef is CosReference
          ? CosReference(newNumber[infoRef.objectNumber]!, 0)
          : null,
    );
  }

  /// Burns the redactions on one page; returns whether any mark was found.
  bool _applyRedactionsOnPage(int pageIndex) {
    final cos = document.cos;
    final page = document.page(pageIndex);
    final annotsRaw = page.dict['Annots'];
    final annots = cos.resolve(annotsRaw);
    if (annots is! CosArray) return false;

    final redactions = <_Redaction>[];
    for (final item in annots.items) {
      final d = cos.resolve(item);
      if (d is! CosDictionary) continue;
      final subtype = cos.resolve(d['Subtype']);
      if (subtype is CosName && subtype.value == 'Redact') {
        redactions.addAll(_redactionsFrom(cos, d));
      }
    }
    if (redactions.isEmpty) return false;
    final regions = [for (final r in redactions) r.rect];

    // 1. Surgically remove covered content from the page's streams.
    final original = page.contentBytes();
    final burned = _RedactionBurn(cos, page.resources, regions).run(original);

    // 2. Paint the fill (and any overlay text) over each region, on top.
    final fill = _redactionFillContent(page, redactions);

    final rebuilt = BytesBuilder(copy: false)
      ..add(latin1.encode('q\n'))
      ..add(burned)
      ..add(latin1.encode('\nQ\n'))
      ..add(fill);
    _setContent(page, rebuilt.takeBytes());

    // 3. Drop the /Redact annotations and scrub any annotation whose
    //    appearance is fully under a redaction region (it would leak the
    //    content the rect is meant to hide).
    final kept = <CosObject>[];
    for (final item in annots.items) {
      final d = cos.resolve(item);
      if (d is CosDictionary) {
        final subtype = cos.resolve(d['Subtype']);
        if (subtype is CosName && subtype.value == 'Redact') continue;
        final r = pdfRectFrom(cos, d['Rect']);
        if (r != null && _rectFullyCovered(r, regions)) continue;
      }
      kept.add(item);
    }
    page.dict['Annots'] = CosArray(kept);
    _updater.markChanged(page.dict);
    return true;
  }

  /// Reads the redaction regions of one `/Redact` dictionary: one rect per
  /// /QuadPoints group, falling back to /Rect.
  List<_Redaction> _redactionsFrom(CosDocument cos, CosDictionary dict) {
    final fillColor = _rgbFromArray(cos, dict['IC']) ?? 0x000000;
    String? overlayText;
    final ot = cos.resolve(dict['OverlayText']);
    if (ot is CosString) overlayText = _decodeTextString(ot);
    final da = cos.resolve(dict['DA']);
    final daText = da is CosString ? latin1.decode(da.bytes) : null;

    final rects = <PdfRect>[];
    final quads = cos.resolve(dict['QuadPoints']);
    if (quads is CosArray && quads.length >= 8) {
      final v = <double>[];
      for (final n in quads.items) {
        final r = cos.resolve(n);
        v.add(r is CosInteger
            ? r.value.toDouble()
            : r is CosReal
                ? r.value
                : 0);
      }
      for (var i = 0; i + 7 < v.length; i += 8) {
        final xs = [v[i], v[i + 2], v[i + 4], v[i + 6]];
        final ys = [v[i + 1], v[i + 3], v[i + 5], v[i + 7]];
        rects.add(PdfRect(
          xs.reduce(math.min),
          ys.reduce(math.min),
          xs.reduce(math.max),
          ys.reduce(math.max),
        ));
      }
    }
    if (rects.isEmpty) {
      final r = pdfRectFrom(cos, dict['Rect']);
      if (r != null) rects.add(r);
    }
    return [
      for (final r in rects)
        _Redaction(r, fillColor, overlayText, daText),
    ];
  }

  /// Content that paints each redaction's /IC fill and optional overlay
  /// text. Appended after the (burned) original content, so it covers the
  /// now-empty area opaquely.
  Uint8List _redactionFillContent(PdfPage page, List<_Redaction> redactions) {
    final out = BytesBuilder();
    var fontResource = '';
    for (final r in redactions) {
      final w = ContentWriter()
        ..save()
        ..fillColor(r.fillColor)
        ..rect(r.rect.left, r.rect.bottom, r.rect.width, r.rect.height)
        ..fill();
      if (r.overlayText != null && r.overlayText!.isNotEmpty) {
        if (fontResource.isEmpty) fontResource = _ensureHelvOnPage(page);
        final color = _overlayColorOf(r.daText, 0xFFFFFF);
        final size = _overlaySizeOf(r.daText, 12);
        final textWidth = measureHelvetica(r.overlayText!, size);
        final tx = r.rect.left + (r.rect.width - textWidth) / 2;
        final ty = r.rect.bottom + (r.rect.height - size) / 2 + size * 0.2;
        w
          ..beginText()
          ..font(fontResource, size)
          ..fillColor(color)
          ..textAt(math.max(tx, r.rect.left + 1), ty)
          ..showText(r.overlayText!)
          ..endText();
      }
      w.restore();
      out.add(w.takeBytes());
    }
    return out.takeBytes();
  }

  /// Ensures a base-14 Helvetica font (`/RHelv`) lives in the page's own
  /// /Font resources and returns its name, for overlay text.
  String _ensureHelvOnPage(PdfPage page) {
    final cos = document.cos;
    final resources = _materializeResources(page);
    final fontsRaw = resources['Font'];
    final fonts = cos.resolve(fontsRaw);
    final dict = fonts is CosDictionary && fontsRaw is! CosReference
        ? fonts
        : CosDictionary({if (fonts is CosDictionary) ...fonts.entries});
    resources['Font'] = dict;
    const name = 'RHelv';
    dict[name] = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Helvetica'),
      'Encoding': const CosName('WinAnsiEncoding'),
    });
    return name;
  }

  /// The page's own /Resources, copied when inherited or shared by
  /// reference (mutating an ancestor's would bleed into sibling pages).
  CosDictionary _materializeResources(PdfPage page) {
    final cos = document.cos;
    final direct = page.dict['Resources'];
    final resolved = cos.resolve(direct);
    if (resolved is CosDictionary && direct is! CosReference) return resolved;
    final copy = CosDictionary({
      if (resolved is CosDictionary) ...resolved.entries else ...page.resources.entries,
    });
    page.dict['Resources'] = copy;
    _updater.markChanged(page.dict);
    return copy;
  }

  int? _rgbFromArray(CosDocument cos, CosObject? value) {
    final array = cos.resolve(value);
    if (array is! CosArray || array.length == 0) return null;
    double comp(int i) {
      final n = cos.resolve(array[i]);
      return n is CosInteger
          ? n.value.toDouble()
          : n is CosReal
              ? n.value
              : 0;
    }

    if (array.length >= 3) {
      return ((comp(0) * 255).round() << 16) |
          ((comp(1) * 255).round() << 8) |
          (comp(2) * 255).round();
    }
    final g = (comp(0) * 255).round();
    return (g << 16) | (g << 8) | g;
  }

  String _decodeTextString(CosString s) {
    final b = s.bytes;
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      final out = StringBuffer();
      for (var i = 2; i + 1 < b.length; i += 2) {
        out.writeCharCode((b[i] << 8) | b[i + 1]);
      }
      return out.toString();
    }
    return latin1.decode(b);
  }

  int _overlayColorOf(String? da, int fallback) {
    if (da == null) return fallback;
    final m = RegExp(r'([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+rg').firstMatch(da);
    if (m == null) return fallback;
    int c(int g) => ((double.tryParse(m.group(g)!) ?? 0) * 255).round() & 0xFF;
    return (c(1) << 16) | (c(2) << 8) | c(3);
  }

  double _overlaySizeOf(String? da, double fallback) {
    if (da == null) return fallback;
    final m = RegExp(r'/\S+\s+([\d.]+)\s+Tf').firstMatch(da);
    if (m == null) return fallback;
    final s = double.tryParse(m.group(1)!) ?? fallback;
    return s > 0 ? s : fallback;
  }

  /// True when [rect]'s four corners all sit inside one of [regions].
  static bool _rectFullyCovered(PdfRect rect, List<PdfRect> regions) {
    for (final region in regions) {
      if (rect.left >= region.left &&
          rect.right <= region.right &&
          rect.bottom >= region.bottom &&
          rect.top <= region.top) {
        return true;
      }
    }
    return false;
  }
}

/// One redaction region with its fill style.
class _Redaction {
  _Redaction(this.rect, this.fillColor, this.overlayText, this.daText);

  final PdfRect rect;
  final int fillColor;
  final String? overlayText;
  final String? daText;
}

/// Walks a page content stream and rewrites it with the glyphs and images
/// that fall inside any redaction [regions] removed — the content-stream
/// surgery half of a redaction burn.
class _RedactionBurn {
  _RedactionBurn(this._cos, this._resources, this._regions);

  final CosDocument _cos;
  final CosDictionary _resources;
  final List<PdfRect> _regions;

  final Map<String, _RedFont?> _fontCache = {};

  // graphics state
  _RedMatrix _ctm = _redIdentity;
  final List<_RedGraphicsState> _gsStack = [];

  // text state (the q/Q-saved parameters live in _RedGraphicsState)
  _RedMatrix _tm = _redIdentity;
  _RedMatrix _tlm = _redIdentity;
  double _tfs = 0;
  double _tc = 0;
  double _tw = 0;
  double _th = 1;
  double _tl = 0;
  double _trise = 0;
  String? _fontName;

  Uint8List run(Uint8List content) {
    final ops = ContentStreamParser.parse(content);
    final out = BytesBuilder();
    for (final op in ops) {
      _handle(op, out);
    }
    return out.takeBytes();
  }

  double _n(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };

  void _handle(ContentOperation op, BytesBuilder out) {
    final operands = op.operands;
    switch (op.operator) {
      case 'q':
        _gsStack.add(_RedGraphicsState(
            _ctm, _tfs, _tc, _tw, _th, _tl, _trise, _fontName));
        _writeOp(op, out);
        return;
      case 'Q':
        if (_gsStack.isNotEmpty) {
          final s = _gsStack.removeLast();
          _ctm = s.ctm;
          _tfs = s.tfs;
          _tc = s.tc;
          _tw = s.tw;
          _th = s.th;
          _tl = s.tl;
          _trise = s.trise;
          _fontName = s.fontName;
        }
        _writeOp(op, out);
        return;
      case 'cm':
        if (operands.length >= 6) {
          _ctm = _redMul(
              (_n(operands[0]), _n(operands[1]), _n(operands[2]),
                  _n(operands[3]), _n(operands[4]), _n(operands[5])),
              _ctm);
        }
        _writeOp(op, out);
        return;
      case 'BT':
        _tm = _redIdentity;
        _tlm = _redIdentity;
        _writeOp(op, out);
        return;
      case 'Tf':
        if (operands.length >= 2) {
          _fontName = operands[0] is CosName
              ? (operands[0] as CosName).value
              : null;
          _tfs = _n(operands[1]);
        }
        _writeOp(op, out);
        return;
      case 'Tc':
        if (operands.isNotEmpty) _tc = _n(operands[0]);
        _writeOp(op, out);
        return;
      case 'Tw':
        if (operands.isNotEmpty) _tw = _n(operands[0]);
        _writeOp(op, out);
        return;
      case 'Tz':
        if (operands.isNotEmpty) _th = _n(operands[0]) / 100;
        _writeOp(op, out);
        return;
      case 'TL':
        if (operands.isNotEmpty) _tl = _n(operands[0]);
        _writeOp(op, out);
        return;
      case 'Ts':
        if (operands.isNotEmpty) _trise = _n(operands[0]);
        _writeOp(op, out);
        return;
      case 'Td':
        if (operands.length >= 2) {
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
        }
        _writeOp(op, out);
        return;
      case 'TD':
        if (operands.length >= 2) {
          _tl = -_n(operands[1]);
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
        }
        _writeOp(op, out);
        return;
      case 'Tm':
        if (operands.length >= 6) {
          _tm = (
            _n(operands[0]),
            _n(operands[1]),
            _n(operands[2]),
            _n(operands[3]),
            _n(operands[4]),
            _n(operands[5]),
          );
          _tlm = _tm;
        }
        _writeOp(op, out);
        return;
      case 'T*':
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _writeOp(op, out);
        return;
      case 'Tj':
        _showText(op, out);
        return;
      case "'":
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _showText(op, out, prefix: 'T*\n');
        return;
      case '"':
        if (operands.length >= 3) {
          _tw = _n(operands[0]);
          _tc = _n(operands[1]);
        }
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _showText(op, out,
            prefix: '${ContentWriter.fmt(_tw)} Tw '
                '${ContentWriter.fmt(_tc)} Tc T*\n');
        return;
      case 'TJ':
        _showText(op, out);
        return;
      case 'Do':
        if (_maybeDropXObject(op, out)) return;
        _writeOp(op, out);
        return;
      case 'BI':
        if (_rectIntersectsAny(_unitSquareBounds(_ctm))) {
          if (_boundsFullyCovered(_unitSquareBounds(_ctm))) return; // drop
        }
        _writeOp(op, out);
        return;
      default:
        _writeOp(op, out);
        return;
    }
  }

  /// Drops a fully-covered image/form XObject; returns true when dropped.
  bool _maybeDropXObject(ContentOperation op, BytesBuilder out) {
    final name = op.operands.isNotEmpty && op.operands.first is CosName
        ? (op.operands.first as CosName).value
        : null;
    if (name == null) return false;
    final xobjects = _cos.resolve(_resources['XObject']);
    final xobject =
        xobjects is CosDictionary ? _cos.resolve(xobjects[name]) : null;
    if (xobject is! CosStream) return false;

    final subtype = _cos.resolve(xobject.dictionary['Subtype']);
    PdfRect? bounds;
    if (subtype is CosName && subtype.value == 'Form') {
      final bbox = pdfRectFrom(_cos, xobject.dictionary['BBox']);
      if (bbox != null) {
        bounds = _hullBounds([
          _redApply(_ctm, bbox.left, bbox.bottom),
          _redApply(_ctm, bbox.right, bbox.bottom),
          _redApply(_ctm, bbox.left, bbox.top),
          _redApply(_ctm, bbox.right, bbox.top),
        ]);
      }
    } else {
      bounds = _unitSquareBounds(_ctm);
    }
    if (bounds != null && _boundsFullyCovered(bounds)) return true; // drop
    return false;
  }

  void _showText(ContentOperation op, BytesBuilder out, {String prefix = ''}) {
    if (prefix.isNotEmpty) out.add(latin1.encode(prefix));

    // Pull the (string | adjustment) elements out of the operator.
    final elements = <Object>[]; // CosString or double (TJ adjustment)
    if (op.operator == 'TJ' && op.operands.isNotEmpty) {
      final array = op.operands.first;
      if (array is CosArray) {
        for (final item in array.items) {
          if (item is CosString) {
            elements.add(item);
          } else if (item is CosInteger || item is CosReal) {
            elements.add(_n(item));
          }
        }
      }
    } else if (op.operator == '"' && op.operands.length >= 3) {
      if (op.operands[2] is CosString) elements.add(op.operands[2]);
    } else if (op.operands.isNotEmpty && op.operands.first is CosString) {
      elements.add(op.operands.first);
    }

    final font = _font(_fontName);
    // Composite fonts: bytes are CID codes, not characters. Don't try to
    // split — drop the whole op if it touches a region, else keep verbatim.
    if (font != null && font.isComposite) {
      final bounds = _compositeBounds(elements, font);
      if (bounds != null && _rectIntersectsAny(bounds)) {
        _advanceComposite(elements, font); // keep Tm in sync, emit nothing
        return;
      }
      _advanceComposite(elements, font);
      _writeOp(op, out);
      return;
    }
    if (_tfs == 0 || _th == 0) {
      // no measurable size: cannot place glyphs; leave the op untouched.
      _writeOp(op, out);
      return;
    }

    // Walk glyph by glyph, building a TJ array with covered glyphs removed
    // and replaced by a numeric gap so survivors keep their position.
    final rebuilt = <Object>[]; // CosString | double
    final current = BytesBuilder();
    var redactedAny = false;
    double pendingGap = 0; // accumulated removed advance (text-space points)

    void flushString() {
      if (current.length > 0) {
        rebuilt.add(CosString(current.takeBytes()));
      }
    }

    void flushGap() {
      if (pendingGap != 0) {
        // displacement = -num/1000 * tfs * th  ⇒  num = -gap*1000/(tfs*th)
        rebuilt.add(-pendingGap * 1000 / (_tfs * _th));
        pendingGap = 0;
      }
    }

    for (final element in elements) {
      if (element is double) {
        // existing TJ adjustment: advances the cursor, carry it through
        final disp = -element / 1000 * _tfs * _th;
        if (current.length > 0) {
          flushString();
        }
        // fold into the gap stream so spacing survives either way
        pendingGap += -disp; // gap is measured as forward advance
        _tm = _redMul((1, 0, 0, 1, disp, 0), _tm);
        continue;
      }
      final string = element as CosString;
      for (final code in string.bytes) {
        final w0 = font?.widthOf(code) ?? 500; // glyph units
        final glyphWidth = w0 / 1000 * _tfs * _th;
        final advance =
            (w0 / 1000 * _tfs + _tc + (code == 32 ? _tw : 0)) * _th;

        final covered = _glyphCovered(glyphWidth);
        if (covered) {
          redactedAny = true;
          flushString();
          pendingGap += advance;
        } else {
          flushGap();
          current.addByte(code);
        }
        _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
      }
    }

    if (!redactedAny) {
      // nothing covered: re-emit the original operator unchanged.
      _writeOp(op, out);
      return;
    }
    flushString();
    flushGap();

    if (rebuilt.isEmpty) {
      // everything was removed: emit nothing (but Tm already advanced).
      return;
    }
    out.add(latin1.encode('['));
    for (final piece in rebuilt) {
      if (piece is CosString) {
        out.add(CosSerializer.serialize(piece));
      } else {
        out.add(latin1.encode(ContentWriter.fmt(piece as double)));
      }
      out.addByte(0x20);
    }
    out.add(latin1.encode('] TJ\n'));
  }

  /// True when the glyph occupying [glyphWidth] text-space points from the
  /// current text position intersects any redaction region.
  bool _glyphCovered(double glyphWidth) {
    final m = _redMul(_tm, _ctm);
    final y0 = _trise - 0.2 * _tfs;
    final y1 = _trise + _tfs;
    final bounds = _hullBounds([
      _redApply(m, 0, y0),
      _redApply(m, glyphWidth, y0),
      _redApply(m, 0, y1),
      _redApply(m, glyphWidth, y1),
    ]);
    return bounds != null && _rectIntersectsAny(bounds);
  }

  PdfRect? _compositeBounds(List<Object> elements, _RedFont font) {
    var minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    var cursor = 0.0;
    final m = _redMul(_tm, _ctm);
    for (final element in elements) {
      if (element is double) {
        cursor += -element / 1000 * _tfs * _th;
        continue;
      }
      final string = element as CosString;
      final glyphs = string.bytes.length ~/ 2;
      for (var i = 0; i < glyphs; i++) {
        final gw = font.defaultWidth / 1000 * _tfs * _th;
        for (final (x, y) in [
          _redApply(m, cursor, _trise - 0.2 * _tfs),
          _redApply(m, cursor + gw, _trise + _tfs),
        ]) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
        cursor += gw + _tc * _th;
      }
    }
    if (minX > maxX) return null;
    return PdfRect(minX, minY, maxX, maxY);
  }

  void _advanceComposite(List<Object> elements, _RedFont font) {
    var advance = 0.0;
    for (final element in elements) {
      if (element is double) {
        advance += -element / 1000 * _tfs * _th;
        continue;
      }
      final string = element as CosString;
      final glyphs = string.bytes.length ~/ 2;
      advance += glyphs * (font.defaultWidth / 1000 * _tfs + _tc) * _th;
    }
    _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
  }

  _RedFont? _font(String? name) {
    if (name == null) return null;
    return _fontCache.putIfAbsent(name, () {
      final fonts = _cos.resolve(_resources['Font']);
      if (fonts is! CosDictionary) return null;
      final font = _cos.resolve(fonts[name]);
      if (font is! CosDictionary) return null;
      return _RedFont.from(_cos, font);
    });
  }

  bool _rectIntersectsAny(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left < region.right &&
          rect.right > region.left &&
          rect.bottom < region.top &&
          rect.top > region.bottom) {
        return true;
      }
    }
    return false;
  }

  bool _boundsFullyCovered(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left >= region.left &&
          rect.right <= region.right &&
          rect.bottom >= region.bottom &&
          rect.top <= region.top) {
        return true;
      }
    }
    return false;
  }

  PdfRect _unitSquareBounds(_RedMatrix ctm) =>
      _hullBounds([
        _redApply(ctm, 0, 0),
        _redApply(ctm, 1, 0),
        _redApply(ctm, 0, 1),
        _redApply(ctm, 1, 1),
      ])!;

  /// Re-serializes [op] verbatim (mirrors [PdfPageElements.serialize]).
  void _writeOp(ContentOperation op, BytesBuilder out) {
    if (op.operator == 'BI') {
      out.add(_inlineImageBytes(op));
      return;
    }
    for (final operand in op.operands) {
      out
        ..add(CosSerializer.serialize(operand))
        ..addByte(0x20);
    }
    out.add(latin1.encode('${op.operator}\n'));
  }

  static Uint8List _inlineImageBytes(ContentOperation op) {
    final out = BytesBuilder()..add(latin1.encode('BI'));
    final dict = op.operands[0] as CosDictionary;
    dict.entries.forEach((key, value) {
      out
        ..add(latin1.encode(' /$key '))
        ..add(CosSerializer.serialize(value));
    });
    out.add(latin1.encode(' ID\n'));
    out.add((op.operands[1] as CosString).bytes);
    out.add(latin1.encode('\nEI\n'));
    return out.takeBytes();
  }
}

/// The glyph metrics a redaction burn needs from one font.
class _RedFont {
  _RedFont._(this.isComposite, this._firstChar, this._widths, this._fallback,
      this.defaultWidth);

  final bool isComposite;
  final int _firstChar;
  final List<double>? _widths; // glyph units (1000/em), simple fonts
  final List<int> _fallback; // base-14 table for missing widths
  final double defaultWidth; // composite /DW or simple miss default

  static _RedFont from(CosDocument cos, CosDictionary font) {
    final subtype = cos.resolve(font['Subtype']);
    final isType0 = subtype is CosName && subtype.value == 'Type0';
    final baseFont = cos.resolve(font['BaseFont']);
    final baseName = baseFont is CosName ? baseFont.value : '';
    final fallback = _fallbackTable(baseName);

    if (isType0) {
      var dw = 1000.0;
      final descendants = cos.resolve(font['DescendantFonts']);
      if (descendants is CosArray && descendants.length > 0) {
        final d = cos.resolve(descendants.items.first);
        if (d is CosDictionary) {
          final dwv = cos.resolve(d['DW']);
          if (dwv is CosInteger) dw = dwv.value.toDouble();
          if (dwv is CosReal) dw = dwv.value;
        }
      }
      return _RedFont._(true, 0, null, fallback, dw);
    }

    final firstCharObj = cos.resolve(font['FirstChar']);
    final firstChar = firstCharObj is CosInteger ? firstCharObj.value : 0;
    final widthsObj = cos.resolve(font['Widths']);
    List<double>? widths;
    if (widthsObj is CosArray) {
      widths = [
        for (final w in widthsObj.items)
          switch (cos.resolve(w)) {
            CosInteger(:final value) => value.toDouble(),
            CosReal(:final value) => value,
            _ => 0.0,
          }
      ];
    }
    return _RedFont._(false, firstChar, widths, fallback, 500);
  }

  static List<int> _fallbackTable(String baseFont) {
    final n = baseFont.toLowerCase();
    if (n.contains('times') || n.contains('serif')) return timesRomanWidths;
    if (n.contains('bold')) return helveticaBoldWidths;
    return helveticaWidths;
  }

  /// Advance width of [code] in glyph units (1000/em).
  double widthOf(int code) {
    final widths = _widths;
    if (widths != null) {
      final i = code - _firstChar;
      if (i >= 0 && i < widths.length) {
        final w = widths[i];
        if (w > 0) return w;
      }
    }
    if (code >= 32 && code <= 126) return _fallback[code - 32].toDouble();
    return defaultWidth;
  }
}

class _RedGraphicsState {
  _RedGraphicsState(this.ctm, this.tfs, this.tc, this.tw, this.th, this.tl,
      this.trise, this.fontName);

  final _RedMatrix ctm;
  final double tfs;
  final double tc;
  final double tw;
  final double th;
  final double tl;
  final double trise;
  final String? fontName;
}

typedef _RedMatrix = (double, double, double, double, double, double);

const _RedMatrix _redIdentity = (1, 0, 0, 1, 0, 0);

_RedMatrix _redMul(_RedMatrix m, _RedMatrix n) => (
      m.$1 * n.$1 + m.$2 * n.$3,
      m.$1 * n.$2 + m.$2 * n.$4,
      m.$3 * n.$1 + m.$4 * n.$3,
      m.$3 * n.$2 + m.$4 * n.$4,
      m.$5 * n.$1 + m.$6 * n.$3 + n.$5,
      m.$5 * n.$2 + m.$6 * n.$4 + n.$6,
    );

(double, double) _redApply(_RedMatrix m, double x, double y) =>
    (m.$1 * x + m.$3 * y + m.$5, m.$2 * x + m.$4 * y + m.$6);

PdfRect? _hullBounds(List<(double, double)> points) {
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

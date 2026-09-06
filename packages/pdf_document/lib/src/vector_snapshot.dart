part of 'editor.dart';

/// A detached, **vector** copy of a rectangular region of a page - the page
/// content and resources under the region, resolved and copied inline so
/// the snapshot survives edits, undo, and even closing the source document.
///
/// It is the payload behind the Snapshot tool's "paste as vector":
/// [PdfVectorSnapshotEditing.pasteVectorSnapshot] re-materializes it onto
/// any page as a /Stamp annotation whose appearance *draws* the captured
/// graphics, so it stays sharp at any zoom (unlike a raster snapshot) and
/// stays movable/resizable/deletable like any annotation.
///
/// The page's /Rotate is baked into the capture ([_matrix]/[displayWidth]/
/// [displayHeight]), so a region snapped from a 90°/270° page pastes in the
/// orientation it was displayed in.
///
/// Capture with [PdfVectorSnapshotEditing.captureVectorSnapshot].
///
/// Size note: the whole page's content stream travels with the snapshot
/// (only the form BBox clips it), so a small snap of a content-heavy page
/// still embeds that page's operators once. Repeated pastes of the *same*
/// snapshot into one document share a single captured XObject rather than
/// duplicating it (see [PdfVectorSnapshotEditing.pasteVectorSnapshot]).
class PdfVectorSnapshot {
  PdfVectorSnapshot._(this.region, this.displayWidth, this.displayHeight,
      this._content, this._resources, this._matrix);

  /// Imports the first page of a PDF as a detached vector snapshot.
  ///
  /// The whole first page (its crop box) becomes the captured region, so the
  /// PDF's page size is the snapshot's natural paste size. Throws if the
  /// bytes aren't a readable PDF with at least one page.
  factory PdfVectorSnapshot.fromPdfBytes(Uint8List bytes,
      {String password = ''}) {
    final document = PdfDocument.open(bytes, password: password);
    final snapshot =
        PdfEditor(document).captureVectorSnapshot(0, document.page(0).cropBox);
    snapshot._validateSize();
    return snapshot;
  }

  /// The captured region in the source page's user space (points, origin
  /// bottom-left), before /Rotate.
  final PdfRect region;

  /// The region's displayed width and height - [region] rotated by the
  /// page's /Rotate, so a 90°/270° page swaps the two. The natural paste
  /// size.
  final double displayWidth;
  final double displayHeight;

  /// The source page's content streams, decoded and concatenated - the
  /// operators the appearance replays (under [_matrix], clipped to the
  /// form BBox).
  final Uint8List _content;

  /// The source page's /Resources, deep-copied inline (fonts, images,
  /// nested XObjects), detached from the source document.
  final CosDictionary _resources;

  /// The cm mapping the page's user space onto an upright
  /// `[0 0 displayWidth displayHeight]` box - translation for an unrotated
  /// page, a rotation+translation for 90/180/270.
  final List<double> _matrix;

  /// Serializes this snapshot as a self-contained, single-page PDF whose
  /// page is exactly the captured region (MediaBox `[0 0 displayWidth
  /// displayHeight]`, the page's /Rotate already baked into the content).
  ///
  /// Hosts can exchange these bytes as `application/pdf` with applications
  /// that support PDF clipboard data. Resources stay vector where the source
  /// was vector; embedded images keep their original encoding. Throws when
  /// the captured region has empty or non-finite dimensions.
  Uint8List toPdfBytes() {
    _validateSize();
    final builder = CosDocumentBuilder();

    // the page content replays the captured operators under the rotation
    // matrix, clipped to the page box by the MediaBox
    final body = BytesBuilder()
      ..add(latin1.encode('q ${_matrix.map(_fmtNum).join(' ')} cm\n'))
      ..add(_content)
      ..add(latin1.encode('\nQ'));
    final contentBytes = body.takeBytes();
    final contentRef = builder.add(CosStream(
      CosDictionary({'Length': CosInteger(contentBytes.length)}),
      contentBytes,
    ));

    // the detached resources carry fonts / images / nested forms as inline
    // streams — hoist them to indirect objects (§7.3.8) before referencing
    final resources = _copyDetached(_resources) as CosDictionary;
    _hoistBuilderStreams(builder, resources);

    // register the pages node empty so the page can reference it as /Parent,
    // then fill it in (the builder serializes nothing until build())
    final pages = CosDictionary();
    final pagesRef = builder.add(pages);
    final pageRef = builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': pagesRef,
      'MediaBox': _rectArray(PdfRect(0, 0, displayWidth, displayHeight)),
      'Resources': resources,
      'Contents': contentRef,
    }));
    pages
      ..['Type'] = const CosName('Pages')
      ..['Kids'] = CosArray([pageRef])
      ..['Count'] = CosInteger(1);
    final rootRef = builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': pagesRef,
    }));
    return builder.build(root: rootRef, preserveRealPrecision: true);
  }

  void _validateSize() {
    if (!displayWidth.isFinite ||
        !displayHeight.isFinite ||
        displayWidth <= 0 ||
        displayHeight <= 0) {
      throw const FormatException('Snapshot must have a finite, positive size');
    }
  }
}

/// Replaces every inline [CosStream] in [node] with a reference to an object
/// registered on [builder] (children first, so a stream nested in another
/// stream's /Resources hoists too) — the [CosDocumentBuilder] counterpart of
/// the updater's `_hoistStreams`.
void _hoistBuilderStreams(CosDocumentBuilder builder, CosObject node) {
  switch (node) {
    case CosDictionary dict:
      for (final key in dict.entries.keys.toList()) {
        final value = dict.entries[key]!;
        if (value is CosStream) {
          _hoistBuilderStreams(builder, value.dictionary);
          dict[key] = builder.add(value);
        } else {
          _hoistBuilderStreams(builder, value);
        }
      }
    case CosArray array:
      for (var i = 0; i < array.items.length; i++) {
        final value = array.items[i];
        if (value is CosStream) {
          _hoistBuilderStreams(builder, value.dictionary);
          array.items[i] = builder.add(value);
        } else {
          _hoistBuilderStreams(builder, value);
        }
      }
    default:
      break;
  }
}

/// Capturing and pasting vector regions ([PdfVectorSnapshot]) - the vector
/// half of the Snapshot tool, complementing the raster capture in
/// `dart_pdf_editor`.
extension PdfVectorSnapshotEditing on PdfEditor {
  /// Captures [region] (the source page's user space) of page [pageIndex]
  /// as a detached vector snapshot. Read-only: the document is untouched.
  ///
  /// The page's /Rotate is baked in, so the snapshot pastes the way the
  /// region was displayed.
  PdfVectorSnapshot captureVectorSnapshot(int pageIndex, PdfRect region) {
    final page = document.page(pageIndex);
    final content = page.contentBytes();
    final resources =
        _SnapshotCopier(document).copy(page.resources) as CosDictionary;
    final rx0 = region.left, ry0 = region.bottom;
    final rx1 = region.right, ry1 = region.top;
    final w = region.width, h = region.height;
    // a cm mapping the page user space into an upright [0 0 dW dH] box,
    // baking /Rotate (clockwise, matching the display); the box's width and
    // height swap on quarter turns
    final (List<double> matrix, double dW, double dH) = switch (page.rotation) {
      90 => ([0, -1, 1, 0, -ry0, rx1], h, w),
      180 => ([-1, 0, 0, -1, rx1, ry1], w, h),
      270 => ([0, 1, -1, 0, ry1, -rx0], h, w),
      _ => ([1, 0, 0, 1, -rx0, -ry0], w, h),
    };
    return PdfVectorSnapshot._(region, dW, dH, content, resources, matrix);
  }

  /// Pastes [snapshot] onto page [pageIndex], scaled to fill [targetRect],
  /// as a /Stamp annotation whose appearance draws the captured graphics as
  /// vectors.
  ///
  /// The captured region becomes its own Form XObject (BBox =
  /// `[0 0 displayWidth displayHeight]`, content = the page's operators
  /// under the rotation matrix); the annotation's appearance scales that
  /// box onto [targetRect].
  ///
  /// To avoid embedding the (whole-page) content once per paste, pass the
  /// object number returned by an earlier paste of the *same* snapshot into
  /// this document as [sharedObject]: when it still resolves to the
  /// captured form, this paste references it instead of duplicating it.
  /// Returns the captured form's object number (pass it back as
  /// [sharedObject] next time), or -1 when nothing was pasted.
  int pasteVectorSnapshot(
    int pageIndex,
    PdfRect targetRect,
    PdfVectorSnapshot snapshot, {
    double opacity = 1,
    String? author,
    String? name,
    int? sharedObject,
  }) {
    final dW = snapshot.displayWidth, dH = snapshot.displayHeight;
    if (dW <= 0 || dH <= 0 || targetRect.width <= 0 || targetRect.height <= 0) {
      return sharedObject ?? -1;
    }

    // reuse an already-materialized captured form when one was handed back
    // from a prior paste and still resolves - N pastes then share ONE
    // XObject instead of embedding N copies of the page content
    CosObject? existing;
    if (sharedObject != null) {
      try {
        existing = document.cos.resolve(CosReference(sharedObject, 0));
      } catch (_) {
        existing = null;
      }
    }
    final int capObject;
    final CosReference capRef;
    if (existing is CosStream &&
        existing.dictionary['Subtype'] is CosName &&
        (existing.dictionary['Subtype'] as CosName).value == 'Form') {
      capObject = sharedObject!;
      capRef = CosReference(sharedObject, 0);
    } else {
      final m = snapshot._matrix;
      final body = BytesBuilder()
        ..add(latin1.encode('q ${m.map(_fmtNum).join(' ')} cm\n'))
        ..add(snapshot._content)
        ..add(latin1.encode('\nQ'));
      final bytes = body.takeBytes();
      final captured = CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Form'),
          'BBox': _rectArray(PdfRect(0, 0, dW, dH)),
          'Resources': _copyDetached(snapshot._resources) as CosDictionary,
          'Length': CosInteger(bytes.length),
        }),
        bytes,
      );
      // the resources hold fonts / images / nested forms as inline streams -
      // hoist them to indirect objects (§7.3.8) before referencing the form
      _hoistStreams(captured.dictionary);
      capRef = _updater.addObject(captured);
      capObject = capRef.objectNumber;
    }

    // the appearance scales the captured [0 0 dW dH] box onto the target rect
    final sx = targetRect.width / dW;
    final sy = targetRect.height / dH;
    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    w
      ..save()
      ..concatMatrix(sx, 0, 0, sy, targetRect.left, targetRect.bottom)
      ..drawXObject('Cap')
      ..restore();
    _addAnnotation(
      pageIndex,
      // mark the stamp so the editor can tell a pasted vector snapshot apart
      // from an ordinary stamp - only these recolour as vectors
      _markupDict('Stamp', targetRect, 0x000000, null, author)
        ..[_vectorSnapshotMarker] = const CosBoolean(true),
      _form(targetRect, w,
          resources: _resources(
              extGState: gs, xObject: CosDictionary({'Cap': capRef}))),
      name: name,
    );
    return capObject;
  }

  /// Whether [annotation] is a vector snapshot this editor pasted - a /Stamp
  /// carrying the [_vectorSnapshotMarker] whose appearance draws a captured
  /// /Cap form. Only these can be recoloured in place by
  /// [recolorVectorSnapshot].
  bool isVectorSnapshotStamp(PdfAnnotation annotation) {
    if (annotation.subtype != 'Stamp') return false;
    final marker = document.cos.resolve(annotation.dict[_vectorSnapshotMarker]);
    return marker is CosBoolean && marker.value;
  }

  /// Recolours a pasted vector snapshot to a single ink [color] (`0xRRGGBB`),
  /// keeping it sharp vector graphics.
  ///
  /// Every fill/stroke colour the captured graphics set is rewritten to
  /// [color] - the snapshot becomes a monochrome silhouette, the standard
  /// "recolour a snapshot" behaviour - and colour-less (default-black) paths
  /// are covered too. Embedded raster images, inline images, and shadings
  /// keep their own colours (they are not vector fills). Nested Form XObjects
  /// the capture draws are recoloured as well.
  ///
  /// The recolour is isolated to [annotation]: it gets its own recoloured
  /// copy of the captured form, so other pastes of the same snapshot keep
  /// their colours. Idempotent - recolouring again just retints. Returns
  /// false when [annotation] is not a recolourable vector snapshot.
  bool recolorVectorSnapshot(
    int pageIndex,
    PdfAnnotation annotation,
    int color,
  ) {
    if (!isVectorSnapshotStamp(annotation)) return false;
    final cos = document.cos;
    final appearance = annotation.normalAppearance;
    if (appearance == null) return false;
    final resources = cos.resolve(appearance.dictionary['Resources']);
    if (resources is! CosDictionary) return false;
    final xObjects = cos.resolve(resources['XObject']);
    if (xObjects is! CosDictionary) return false;
    final captured = cos.resolve(xObjects['Cap']);
    if (captured is! CosStream) return false;
    final recolored = _recoloredForm(captured, color & 0xFFFFFF, {}, {});
    // point THIS appearance at the recoloured copy; other pastes that share
    // the original captured form are untouched
    xObjects['Cap'] = _updater.addObject(recolored);
    _updater.markChanged(appearance);
    _markAnnotationChanged(pageIndex, annotation.dict);
    return true;
  }

  /// A recoloured deep copy of a captured Form XObject: its content stream
  /// with every colour operator forced to [rgb], recursing into the nested
  /// Form XObjects it draws (copied once each through [done], guarded against
  /// cyclic references by [visiting]).
  CosStream _recoloredForm(
    CosStream form,
    int rgb,
    Map<CosStream, CosReference> done,
    Set<CosStream> visiting,
  ) {
    final cos = document.cos;
    final recoloredContent =
        _recolorContentBytes(cos.decodeStreamData(form), rgb);
    final dict = CosDictionary({...form.dictionary.entries});
    visiting.add(form);
    final resources = cos.resolve(form.dictionary['Resources']);
    if (resources is CosDictionary) {
      final xObjects = cos.resolve(resources['XObject']);
      if (xObjects is CosDictionary) {
        CosDictionary? recoloredXObjects;
        for (final entry in xObjects.entries.entries) {
          final nested = cos.resolve(entry.value);
          if (nested is! CosStream) continue;
          final subtype = cos.resolve(nested.dictionary['Subtype']);
          if (subtype is! CosName || subtype.value != 'Form') continue;
          if (visiting.contains(nested)) continue; // guard cyclic forms
          final ref = done[nested] ??=
              _updater.addObject(_recoloredForm(nested, rgb, done, visiting));
          (recoloredXObjects ??=
              CosDictionary({...xObjects.entries}))[entry.key] = ref;
        }
        if (recoloredXObjects != null) {
          dict['Resources'] = CosDictionary({...resources.entries})
            ..['XObject'] = recoloredXObjects;
        }
      }
    }
    visiting.remove(form);
    // the copy carries decoded (plaintext) content
    dict.entries
      ..remove('Filter')
      ..remove('DecodeParms')
      ..remove('DP');
    dict['Length'] = CosInteger(recoloredContent.length);
    return CosStream(dict, recoloredContent);
  }

  /// [content] with every fill/stroke colour operator rewritten to [rgb], so
  /// the graphics paint in a single ink. An initial colour is forced up front
  /// so paths that rely on the default black recolour too; colour-space
  /// selectors (`cs`/`CS`) are dropped since every colour is DeviceRGB now.
  /// Images, inline images, and shadings are left untouched.
  Uint8List _recolorContentBytes(Uint8List content, int rgb) {
    CosObject component(int value) => value <= 0
        ? CosInteger(0)
        : value >= 255
            ? CosInteger(1)
            : CosReal(value / 255);
    final operands = [
      component((rgb >> 16) & 0xFF),
      component((rgb >> 8) & 0xFF),
      component(rgb & 0xFF),
    ];
    ContentOperation fill() => ContentOperation('rg', operands);
    ContentOperation stroke() => ContentOperation('RG', operands);
    final out = <ContentOperation>[fill(), stroke()];
    for (final op in ContentStreamParser.parse(content)) {
      switch (op.operator) {
        case 'g' || 'rg' || 'k' || 'sc' || 'scn':
          out.add(fill());
        case 'G' || 'RG' || 'K' || 'SC' || 'SCN':
          out.add(stroke());
        case 'cs' || 'CS':
          break; // drop: colour space is moot once every colour is DeviceRGB
        default:
          out.add(op);
      }
    }
    return ContentStreamSerializer.serialize(out);
  }
}

/// The annotation-dictionary key [PdfVectorSnapshotEditing.pasteVectorSnapshot]
/// stamps onto its /Stamp so a pasted vector snapshot is distinguishable from
/// an ordinary stamp (see [PdfVectorSnapshotEditing.isVectorSnapshotStamp]).
const _vectorSnapshotMarker = 'DartPdfVectorSnapshot';

/// Formats a matrix component for a content stream - integers without a
/// trailing `.0`.
String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

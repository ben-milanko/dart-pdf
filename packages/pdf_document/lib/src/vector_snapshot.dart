part of 'editor.dart';

/// A detached, **vector** copy of a rectangular region of a page - the page
/// content and resources under the region, resolved and copied inline so
/// the snapshot survives edits, undo, and even closing the source document.
/// The page's live (un-flattened) annotations over the region are captured
/// too, drawn over the content from their appearances, so the snapshot
/// shows what the page shows.
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

  /// The source page's content streams, decoded and concatenated (then the
  /// captured annotations' drawing, when any) - the operators the
  /// appearance replays (under [_matrix], clipped to the
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
  ///
  /// With [annotations] (the default) the page's live, un-flattened
  /// annotations that overlap [region] are captured too, drawn over the
  /// content from their normal appearances exactly as flattening would -
  /// so the snapshot shows what the page shows on screen. Only annotations
  /// the renderer paints on screen qualify: hidden, no-view, popup, reply
  /// and review-state annotations, and any without an /AP, are left out.
  ///
  /// [clip], when given, is a closed polygon (at least three vertices, page
  /// user space) the capture is cut to - the Snapshot tool's traced
  /// footprint. Everything outside it is clipped away, so the snapshot keeps
  /// [region] as its box but draws only what the polygon encloses; pass the
  /// polygon's bounds as [region].
  PdfVectorSnapshot captureVectorSnapshot(int pageIndex, PdfRect region,
      {bool annotations = true, List<(double, double)>? clip}) {
    final page = document.page(pageIndex);
    final copier = _SnapshotCopier(document);
    var content = page.contentBytes();
    final resources = copier.copy(page.resources) as CosDictionary;
    if (annotations) {
      final drawn = _snapshotAnnotations(page, region, copier, resources);
      if (drawn != null) {
        // bracket the page content so its leftover graphics state cannot
        // leak into the annotation drawing (as flattening does)
        content = (BytesBuilder(copy: false)
              ..add(latin1.encode('q\n'))
              ..add(content)
              ..add(latin1.encode('\nQ\n'))
              ..add(drawn))
            .takeBytes();
      }
    }
    if (clip != null && clip.length >= 3) {
      // cut the drawing to the traced polygon (page user space - the content
      // replays under [_matrix], so the clip rides the same mapping)
      final w = ContentWriter()
        ..save()
        ..moveTo(clip.first.$1, clip.first.$2);
      for (final (x, y) in clip.skip(1)) {
        w.lineTo(x, y);
      }
      w
        ..closePath()
        ..clip();
      content = (BytesBuilder(copy: false)
            ..add(w.takeBytes())
            ..add(content)
            ..add(latin1.encode('\nQ')))
          .takeBytes();
    }
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

  /// The operators drawing [page]'s on-screen annotations that overlap
  /// [region], their appearance forms copied (detached, through [copier])
  /// into [resources]' /XObject dictionary - or null when none qualify.
  ///
  /// Mirrors the screen pass of the renderer's `drawAnnotations` for which
  /// annotations paint, and [_flattenAnnotations] for how: each appearance
  /// is fitted onto its /Rect per §12.5.5.
  Uint8List? _snapshotAnnotations(PdfPage page, PdfRect region,
      _SnapshotCopier copier, CosDictionary resources) {
    final cos = document.cos;
    final existing = resources['XObject'];
    final xObjects = CosDictionary({
      if (existing is CosDictionary) ...existing.entries,
    });
    final w = ContentWriter();
    var index = 0;
    var drew = false;
    for (final annot in page.annotations) {
      if (annot.isHidden || annot.isNoView) continue;
      if (annot.subtype == 'Popup') continue;
      if (annot.isReply || annot.isStateAnnotation) continue;
      final form = annot.normalAppearance;
      if (form == null) continue;
      final rect = annot.rect;
      if (rect.width <= 0 || rect.height <= 0) continue;
      // outside the region the form BBox clips it away entirely - skip it
      // rather than carry its appearance along
      if (rect.right <= region.left ||
          rect.left >= region.right ||
          rect.top <= region.bottom ||
          rect.bottom >= region.top) {
        continue;
      }
      final bbox = pdfRectFrom(cos, form.dictionary['BBox']);
      if (bbox == null) continue;
      final fit = fitFormToRect(bbox, _formMatrix(form), rect);
      final copied = copier.copy(form);
      if (copied is! CosStream) continue;

      var name = 'SnapAnnot$index';
      while (xObjects.containsKey(name)) {
        name = 'SnapAnnot${++index}';
      }
      index++;
      xObjects[name] = copied;
      w
        ..save()
        ..concatMatrix(fit.a, fit.b, fit.c, fit.d, fit.e, fit.f)
        ..drawXObject(name)
        ..restore();
      drew = true;
    }
    if (!drew) return null;
    resources['XObject'] = xObjects;
    return w.takeBytes();
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

  /// The cropped sub-region of a pasted vector snapshot's captured box that
  /// its appearance draws, normalized (origin bottom-left, `[0,0,1,1]` is the
  /// whole capture). Null when [annotation] is not a vector snapshot or shows
  /// the whole capture. Written by [cropVectorSnapshot].
  PdfRect? vectorSnapshotCrop(PdfAnnotation annotation) {
    if (!isVectorSnapshotStamp(annotation)) return null;
    final crop = pdfRectFrom(
        document.cos, document.cos.resolve(annotation.dict[_snapshotCropKey]));
    if (crop == null || crop.width <= 0 || crop.height <= 0) return null;
    if (crop.left <= 0 &&
        crop.bottom <= 0 &&
        crop.right >= 1 &&
        crop.top >= 1) {
      return null;
    }
    return crop;
  }

  /// Crops the pasted vector snapshot [annotation] to show only [crop] - the
  /// normalized sub-region of its captured box, origin bottom-left,
  /// `[0,0,1,1]` being the whole capture. Like
  /// [PdfAnnotationEditing.cropImageStamp] the crop is absolute (against the
  /// capture, so `[0,0,1,1]` restores it whatever was cropped before), and
  /// [rect], when given, becomes the new /Rect - size it to the visible
  /// sub-region so the graphics keep their scale. The graphics stay vector:
  /// the appearance re-references the same captured form, clipped.
  ///
  /// Opacity and any recolour carry over (both live in the appearance's
  /// resources, which are kept). Returns false when [annotation] is not a
  /// vector snapshot this editor pasted.
  bool cropVectorSnapshot(
    int pageIndex,
    PdfAnnotation annotation, {
    required PdfRect crop,
    PdfRect? rect,
  }) {
    if (!isVectorSnapshotStamp(annotation)) return false;
    final cos = document.cos;
    final appearance = annotation.normalAppearance;
    if (appearance == null) return false;
    final resources = cos.resolve(appearance.dictionary['Resources']);
    if (resources is! CosDictionary) return false;
    final xObjects = cos.resolve(resources['XObject']);
    if (xObjects is! CosDictionary) return false;
    final capRef = xObjects['Cap'];
    final captured = cos.resolve(capRef);
    if (capRef == null || captured is! CosStream) return false;
    final capBox = pdfRectFrom(cos, captured.dictionary['BBox']);
    if (capBox == null || capBox.width <= 0 || capBox.height <= 0) {
      return false;
    }
    final c = PdfAnnotationEditing._normalizeImageCrop(crop);
    final target = rect ?? annotation.rect;
    if (target.width <= 0 || target.height <= 0) return false;
    final full = c.left <= 0 && c.bottom <= 0 && c.right >= 1 && c.top >= 1;

    // the crop's sub-rect of the captured box fills the target rect
    final sx = target.width / (c.width * capBox.width);
    final sy = target.height / (c.height * capBox.height);
    final w = ContentWriter();
    final extGState = cos.resolve(resources['ExtGState']);
    if (extGState is CosDictionary && extGState.containsKey('GS0')) {
      w.extGState('GS0');
    }
    w.save();
    if (!full) {
      w
        ..rect(target.left, target.bottom, target.width, target.height)
        ..clip();
    }
    w
      ..concatMatrix(
        sx,
        0,
        0,
        sy,
        target.left - (capBox.left + c.left * capBox.width) * sx,
        target.bottom - (capBox.bottom + c.bottom * capBox.height) * sy,
      )
      ..drawXObject('Cap')
      ..restore();

    final dict = annotation.dict;
    if (full) {
      dict.entries.remove(_snapshotCropKey);
    } else {
      dict[_snapshotCropKey] = CosArray([
        CosReal(c.left),
        CosReal(c.bottom),
        CosReal(c.right),
        CosReal(c.top),
      ]);
    }
    if (rect != null) dict['Rect'] = _rectArray(rect);
    _replaceAppearance(
      dict,
      appearance,
      target,
      w,
      resources: CosDictionary({...resources.entries}),
    );
    _markAnnotationChanged(pageIndex, dict);
    return true;
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

/// The private key recording a pasted vector snapshot's crop (normalized
/// against its captured box) - see
/// [PdfVectorSnapshotEditing.cropVectorSnapshot].
const _snapshotCropKey = 'DartPdfSnapshotCrop';

/// Formats a matrix component for a content stream - integers without a
/// trailing `.0`.
String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

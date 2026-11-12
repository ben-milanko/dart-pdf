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
/// Links over the region travel too ([links]): a capture keeps each /Link
/// whose action is portable (a /URI - see [PdfSnapshotLink]), a paste
/// re-creates them as live /Link annotations tied to the pasted stamp, and
/// [toPdfBytes] writes them onto its page.
///
/// Size note: the whole page's content stream travels with the snapshot
/// (only the form BBox clips it), so a small snap of a content-heavy page
/// still embeds that page's operators once. Repeated pastes of the *same*
/// snapshot into one document share a single captured XObject rather than
/// duplicating it (see [PdfVectorSnapshotEditing.pasteVectorSnapshot]).
class PdfVectorSnapshot {
  PdfVectorSnapshot._(this.region, this.displayWidth, this.displayHeight,
      this._content, this._resources, this._matrix,
      [this.links = const []]);

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

  /// The links captured over the region, in the upright
  /// `[0 0 displayWidth displayHeight]` box (origin bottom-left) - pasted
  /// back as live /Link annotations over the stamp.
  final List<PdfSnapshotLink> links;

  /// Serializes this snapshot as a self-contained, single-page PDF whose
  /// page is exactly the captured region (MediaBox `[0 0 displayWidth
  /// displayHeight]`, the page's /Rotate already baked into the content).
  ///
  /// Hosts can exchange these bytes as `application/pdf` with applications
  /// that support PDF clipboard data. Resources stay vector where the source
  /// was vector; embedded images keep their original encoding, and [links]
  /// become /Link annotations on the page. Throws when
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
    final page = CosDictionary({
      'Type': const CosName('Page'),
      'Parent': pagesRef,
      'MediaBox': _rectArray(PdfRect(0, 0, displayWidth, displayHeight)),
      'Resources': resources,
      'Contents': contentRef,
    });
    final pageRef = builder.add(page);
    if (links.isNotEmpty) {
      // the snapshot's box *is* this page's box, so the link rects carry over
      page['Annots'] = CosArray([
        for (final link in links)
          builder.add(link._annotation(link.rect)..['P'] = pageRef),
      ]);
    }
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

/// A link captured with a [PdfVectorSnapshot]: where it sits in the
/// snapshot's upright `[0 0 displayWidth displayHeight]` box and the action
/// it runs.
///
/// Only actions that mean the same thing in any document are captured - a
/// /URI (web or mail link). In-document jumps (/GoTo, a bare /Dest, named
/// destinations) point at the *source* document's pages, which a detached
/// snapshot no longer has, so those links are left out rather than pasted
/// pointing somewhere else. A link with several /QuadPoints (one wrapping
/// over lines) is captured as one entry per quad, so the pasted link covers
/// the words rather than the whole box around them.
class PdfSnapshotLink {
  PdfSnapshotLink._(this.rect, this._action, this._contents);

  /// The link's area in the snapshot's display box.
  final PdfRect rect;

  /// The detached action dictionary (a /URI action).
  final CosDictionary _action;

  /// The source link's /Contents (its accessible description), if any.
  final String? _contents;

  /// The URI the link opens.
  String? get uri {
    final value = _action['URI'];
    return value is CosString ? value.text : null;
  }

  /// A fresh, detached /Link annotation dictionary over [rect] running this
  /// link's action, with no visible border.
  CosDictionary _annotation(PdfRect rect) {
    final dict = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Link'),
      'Rect': _rectArray(rect),
      'F': const CosInteger(4),
      'Border': CosArray(
          [const CosInteger(0), const CosInteger(0), const CosInteger(0)]),
      'A': _copyDetached(_action),
    });
    if (_contents != null) dict['Contents'] = CosString.fromText(_contents);
    return dict;
  }
}

/// The action types a [PdfSnapshotLink] keeps (see there for why).
const _portableLinkActions = {'URI'};

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
  ///
  /// Links over the region are captured as [PdfVectorSnapshot.links]
  /// (whatever [annotations] says - a link is not drawn, it is what the
  /// drawing *does*), clipped to the region and, for a traced capture, kept
  /// only where they reach into the polygon.
  PdfVectorSnapshot captureVectorSnapshot(int pageIndex, PdfRect region,
      {bool annotations = true, List<(double, double)>? clip}) {
    final page = document.page(pageIndex);
    final copier = _SnapshotCopier(document.cos);
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
    final links = _snapshotLinks(
        page, region, clip, PdfMatrix.row(matrix), PdfRect(0, 0, dW, dH));
    return PdfVectorSnapshot._(
        region, dW, dH, content, resources, matrix, links);
  }

  /// [page]'s portable links (see [PdfSnapshotLink]) over [region], mapped
  /// through [toBox] (page user space -> the snapshot's display box) and
  /// clipped to [box]. With a traced [clip] polygon, a link is kept only when
  /// it reaches into the polygon.
  List<PdfSnapshotLink> _snapshotLinks(PdfPage page, PdfRect region,
      List<(double, double)>? clip, PdfMatrix toBox, PdfRect box) {
    final cos = document.cos;
    final links = <PdfSnapshotLink>[];
    final copier = _SnapshotCopier(cos);
    for (final annot in page.annotations) {
      if (annot.subtype != 'Link' || annot.isHidden) continue;
      final action = cos.resolve(annot.dict['A']);
      if (action is! CosDictionary) continue;
      final type = cos.resolve(action['S']);
      if (type is! CosName || !_portableLinkActions.contains(type.value)) {
        continue;
      }
      final copied = copier.copy(action);
      if (copied is! CosDictionary) continue;
      // a chained /Next could be anything; the link runs its own action only
      copied.entries.remove('Next');
      final contents = cos.resolve(annot.dict['Contents']);
      for (final area in _linkAreas(annot)) {
        final inRegion = area.intersect(region);
        if (inRegion.width <= 0 || inRegion.height <= 0) continue;
        if (clip != null && clip.length >= 3 && !_reaches(inRegion, clip)) {
          continue;
        }
        final rect = _boundsOf4(toBox, inRegion).intersect(box);
        if (rect.width <= 0 || rect.height <= 0) continue;
        links.add(PdfSnapshotLink._(
            rect, copied, contents is CosString ? contents.text : null));
      }
    }
    return links;
  }

  /// The areas [link] is active over: one per /QuadPoints quad (their
  /// bounds), or its /Rect when it has no usable quads.
  List<PdfRect> _linkAreas(PdfAnnotation link) {
    final cos = document.cos;
    final raw = cos.resolve(link.dict['QuadPoints']);
    final areas = <PdfRect>[];
    if (raw is CosArray && raw.length >= 8 && raw.length % 8 == 0) {
      final values = <double>[];
      for (final item in raw.items) {
        final n = cos.resolve(item);
        if (n is CosInteger) {
          values.add(n.value.toDouble());
        } else if (n is CosReal) {
          values.add(n.value);
        } else {
          values.clear();
          break;
        }
      }
      for (var i = 0; i + 7 < values.length; i += 8) {
        var l = values[i], r = values[i], b = values[i + 1], t = values[i + 1];
        for (var j = 2; j < 8; j += 2) {
          final x = values[i + j], y = values[i + j + 1];
          if (x < l) l = x;
          if (x > r) r = x;
          if (y < b) b = y;
          if (y > t) t = y;
        }
        // quads outside /Rect are ignored by viewers (§12.5.6.5)
        final area = PdfRect(l, b, r, t).intersect(link.rect);
        if (area.width > 0 && area.height > 0) areas.add(area);
      }
    }
    if (areas.isEmpty) areas.add(link.rect);
    return areas;
  }

  /// Whether [rect] reaches into the closed [polygon]: a corner or the
  /// center inside it, or a polygon vertex inside [rect].
  static bool _reaches(PdfRect rect, List<(double, double)> polygon) {
    bool inside(double x, double y) {
      var hit = false;
      for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        final (xi, yi) = polygon[i];
        final (xj, yj) = polygon[j];
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
          hit = !hit;
        }
      }
      return hit;
    }

    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.bottom + rect.top) / 2;
    return inside(cx, cy) ||
        inside(rect.left, rect.bottom) ||
        inside(rect.right, rect.bottom) ||
        inside(rect.right, rect.top) ||
        inside(rect.left, rect.top) ||
        polygon.any((p) => rect.contains(p.$1, p.$2));
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
  /// box onto [targetRect]'s displayed axes, counter-rotating for the
  /// destination page's /Rotate so the capture keeps its visible orientation.
  ///
  /// To avoid embedding the (whole-page) content once per paste, pass the
  /// object number returned by an earlier paste of the *same* snapshot into
  /// this document as [sharedObject]: when it still resolves to the
  /// captured form, this paste references it instead of duplicating it.
  /// Returns the captured form's object number (pass it back as
  /// [sharedObject] next time), or -1 when nothing was pasted.
  ///
  /// The snapshot's [PdfVectorSnapshot.links] come along as live /Link
  /// annotations over the stamp (added before it in /Annots, so the stamp
  /// stays the page's last annotation). They belong to the stamp: moving,
  /// resizing, rotating, flipping, or cropping it re-lays them, and removing
  /// it removes them.
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

    // The capture is already in display orientation. Lay it out on the
    // destination's visual axes, then cancel that page's display rotation.
    final pageRotation = _appearancePageRotation(pageIndex, null);
    final visualRect =
        PdfAnnotationEditing._orientedVisualRect(targetRect, pageRotation);
    final sx = visualRect.width / dW;
    final sy = visualRect.height / dH;
    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    if (pageRotation != 0) {
      w.save();
      PdfAnnotationEditing._orientedCounterRotation(
          w, targetRect, pageRotation);
    }
    w
      ..save()
      ..concatMatrix(sx, 0, 0, sy, visualRect.left, visualRect.bottom)
      ..drawXObject('Cap')
      ..restore();
    if (pageRotation != 0) w.restore();
    // mark the stamp so the editor can tell a pasted vector snapshot apart
    // from an ordinary stamp - only these recolour as vectors
    final stamp = _markupDict('Stamp', targetRect, 0x000000, null, author)
      ..[_vectorSnapshotMarker] = const CosBoolean(true);
    if (snapshot.links.isEmpty) {
      _addAnnotation(
        pageIndex,
        stamp,
        _form(targetRect, w,
            resources: _resources(
                extGState: gs, xObject: CosDictionary({'Cap': capRef}))),
        name: name,
      );
      return capObject;
    }

    // the captured box -> appearance form space mapping the content above
    // draws under (the scale onto the visual rect, then the counter-
    // rotation), recorded so the links can be re-laid whenever the stamp's
    // geometry changes
    var capToForm = PdfMatrix(sx, 0, 0, sy, visualRect.left, visualRect.bottom);
    if (pageRotation != 0) {
      capToForm =
          capToForm.concat(_counterRotationMatrix(targetRect, pageRotation));
    }
    stamp[_snapshotCapMatrixKey] =
        CosArray([for (final v in capToForm.toList()) CosReal(v)]);
    stamp['NM'] = CosString.fromText(name ?? _generateAnnotationName());
    stamp['AP'] = CosDictionary({
      'N': _updater.addObject(_form(targetRect, w,
          resources: _resources(
              extGState: gs, xObject: CosDictionary({'Cap': capRef}))))
    });
    final stampRef = _updater.addObject(stamp);
    final links = _PdfPageAnnotationList(this, pageIndex);
    for (final link in snapshot.links) {
      links.append(_updater.addObject(link._annotation(link.rect)
        ..[_snapshotLinkOwnerKey] = stampRef
        ..[_snapshotLinkBoxKey] = _rectArray(link.rect)));
    }
    links.append(stampRef);
    _markAnnotations([pageIndex]);
    _layoutSnapshotLinks(pageIndex, stamp);
    return capObject;
  }

  /// The matrix [writePdfCounterRotation] writes for [rect]'s center.
  static PdfMatrix _counterRotationMatrix(PdfRect rect, int rotation) {
    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.bottom + rect.top) / 2;
    return switch (rotation) {
      90 => PdfMatrix(0, 1, -1, 0, cx + cy, cy - cx),
      180 => PdfMatrix(-1, 0, 0, -1, 2 * cx, 2 * cy),
      270 => PdfMatrix(0, -1, 1, 0, cx - cy, cx + cy),
      _ => PdfMatrix.identity,
    };
  }

  /// Re-lays the /Link annotations a pasted vector snapshot [stamp] owns
  /// (see [pasteVectorSnapshot]) over its current geometry: each link's box
  /// in the captured snapshot maps through the recorded capture -> form
  /// mapping, is clipped to the appearance BBox (a crop hides what it cuts
  /// away), and lands on the page through the appearance's /Matrix and
  /// BBox -> /Rect fit - so the links follow every move, resize, rotation,
  /// flip, and crop. A link cropped away entirely is hidden (/F Hidden),
  /// not removed, so widening the crop again brings it back. No-op for
  /// anything else.
  void _layoutSnapshotLinks(int pageIndex, CosDictionary stamp) {
    final cos = document.cos;
    final rawMatrix = cos.resolve(stamp[_snapshotCapMatrixKey]);
    if (rawMatrix is! CosArray || rawMatrix.length != 6) return;
    final values = <double>[];
    for (final item in rawMatrix.items) {
      final n = cos.resolve(item);
      if (n is CosInteger) {
        values.add(n.value.toDouble());
      } else if (n is CosReal) {
        values.add(n.value);
      } else {
        return;
      }
    }
    final capToForm = PdfMatrix.row(values);
    final rect = pdfRectFrom(cos, stamp['Rect']);
    final ap = cos.resolve(stamp['AP']);
    final form = ap is CosDictionary ? cos.resolve(ap['N']) : null;
    if (rect == null || form is! CosStream) return;
    final bbox = pdfRectFrom(cos, form.dictionary['BBox']);
    final formToPage = _bakedFormMatrix(form, rect);
    if (bbox == null || formToPage == null) return;
    final list = _PdfPageAnnotationList(this, pageIndex);
    for (final link in _ownedSnapshotLinks(pageIndex, stamp)) {
      final box = pdfRectFrom(cos, link[_snapshotLinkBoxKey]);
      if (box == null) continue;
      final inForm = _boundsOf4(capToForm, box).intersect(bbox);
      if (inForm.width <= 0 || inForm.height <= 0) {
        link['F'] = const CosInteger(4 | 2); // cropped away: hidden
      } else {
        final corners = [
          formToPage.apply(inForm.left, inForm.bottom),
          formToPage.apply(inForm.right, inForm.bottom),
          formToPage.apply(inForm.right, inForm.top),
          formToPage.apply(inForm.left, inForm.top),
        ];
        link
          ..['F'] = const CosInteger(4)
          ..['Rect'] = _rectArray(_boundsOf4(formToPage, inForm))
          ..['QuadPoints'] = CosArray([
            for (final (x, y) in corners) ...[CosReal(x), CosReal(y)],
          ]);
      }
      list.markOwnerChangedFor(link);
    }
  }

  /// The /Link dictionaries on page [pageIndex] that [stamp] owns.
  List<CosDictionary> _ownedSnapshotLinks(int pageIndex, CosDictionary stamp) {
    final cos = document.cos;
    final annots = cos.resolve(document.page(pageIndex).dict['Annots']);
    if (annots is! CosArray) return const [];
    return [
      for (final item in annots.items)
        if (cos.resolve(item) case final CosDictionary link
            when link.containsKey(_snapshotLinkOwnerKey) &&
                identical(cos.resolve(link[_snapshotLinkOwnerKey]), stamp))
          link,
    ];
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
    if (dict.containsKey(_snapshotCapMatrixKey)) {
      // the new appearance draws the captured box under this mapping (the
      // crop path ignores the page's /Rotate, as the matrix above does)
      dict[_snapshotCapMatrixKey] = CosArray([
        CosReal(sx),
        CosReal(0),
        CosReal(0),
        CosReal(sy),
        CosReal(target.left - (capBox.left + c.left * capBox.width) * sx),
        CosReal(
            target.bottom - (capBox.bottom + c.bottom * capBox.height) * sy),
      ]);
    }
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

/// The private key on a pasted vector snapshot stamp recording the mapping
/// from its captured box into its appearance's form space - what
/// [PdfVectorSnapshotEditing._layoutSnapshotLinks] lays its links out by.
const _snapshotCapMatrixKey = 'DartPdfSnapshotCapMatrix';

/// The private key on a pasted snapshot's /Link pointing at the stamp that
/// owns it.
const _snapshotLinkOwnerKey = 'DartPdfSnapshotLinkOf';

/// The private key on a pasted snapshot's /Link recording its area in the
/// captured box (the snapshot's display box).
const _snapshotLinkBoxKey = 'DartPdfSnapshotLinkBox';

/// The bounds of [rect]'s corners under [m].
PdfRect _boundsOf4(PdfMatrix m, PdfRect rect) {
  final (x0, y0) = m.apply(rect.left, rect.bottom);
  final (x1, y1) = m.apply(rect.right, rect.bottom);
  final (x2, y2) = m.apply(rect.right, rect.top);
  final (x3, y3) = m.apply(rect.left, rect.top);
  double lo(double a, double b, double c, double d) =>
      math.min(math.min(a, b), math.min(c, d));
  double hi(double a, double b, double c, double d) =>
      math.max(math.max(a, b), math.max(c, d));
  return PdfRect(lo(x0, x1, x2, x3), lo(y0, y1, y2, y3), hi(x0, x1, x2, x3),
      hi(y0, y1, y2, y3));
}

/// Formats a matrix component for a content stream - integers without a
/// trailing `.0`.
String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

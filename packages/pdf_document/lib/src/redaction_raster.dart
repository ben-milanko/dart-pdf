part of 'editor.dart';

/// A rendered page: [width] x [height] pixels of 8-bit RGBA, row by row
/// from the top. [premultiplied] says whether colour is premultiplied by
/// alpha (Flutter's `ImageByteFormat.rawRgba` is).
class PdfPageRaster {
  PdfPageRaster({
    required this.width,
    required this.height,
    required this.rgba,
    this.premultiplied = true,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      throw ArgumentError('raster is not $width x $height RGBA');
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;
  final bool premultiplied;

  /// The pixels as 8-bit RGB over white paper.
  Uint8List toRgbOnWhite() {
    final out = Uint8List(width * height * 3);
    for (var p = 0, q = 0; p < width * height * 4; p += 4, q += 3) {
      final a = rgba[p + 3];
      for (var c = 0; c < 3; c++) {
        final v = rgba[p + c];
        out[q + c] = premultiplied
            ? math.min(255, v + 255 - a)
            : (v * a + 255 * (255 - a) + 127) ~/ 255;
      }
    }
    return out;
  }
}

/// Image-replacement redaction: the strongest form, for when no trace of a
/// page's structure may survive.
///
/// A burn ([PdfRedactionApply.burnRedactions]) removes what lies under the
/// boxes from the page's content, but the page stays made of text, paths
/// and images - and every review of the burn has found constructs whose
/// covered content some viewer or tool still recovers. Replacing a page
/// with a picture of itself leaves nothing to recover but the pixels: no
/// text, fonts, positions, marked content or annotations. The cost is that
/// the page's text can no longer be selected, searched or read aloud, and
/// the file grows.
///
/// The host renders the pages (this package can't): typically burn first,
/// open the burned bytes, render each redacted page as it is displayed
/// (crop box, rotation applied, annotations drawn), and pass the pictures
/// here.
extension PdfRedactionRaster on PdfEditor {
  /// Replaces each page in [rasters] (by page index) with its picture and
  /// returns the full, compacted file bytes.
  ///
  /// Each raster must show the page as displayed - its crop box with the
  /// page rotation applied - at any resolution. The page becomes one image
  /// filling a media box of the displayed size, upright; everything else it
  /// held goes: content, resources, annotations (and the form fields only
  /// they showed), thumbnails, metadata, actions, structure-tree text that
  /// described it. The page object itself stays, so bookmarks and links to
  /// it still land.
  ///
  /// Throws [UnsupportedError] for an encrypted document, like a burn.
  Uint8List replacePagesWithImages(Map<int, PdfPageRaster> rasters) {
    final cos = document.cos;
    if (cos.encryption != null) {
      throw UnsupportedError(
        'replacePagesWithImages cannot compact an encrypted document; '
        'decrypt it first',
      );
    }
    final session = _RedactionSession();
    final rasterized = Set<CosDictionary>.identity();
    rasters.forEach((index, raster) {
      final page = document.page(index);
      final dict = page.dict;
      rasterized.add(dict);
      final crop = page.cropBox;
      final swap = page.rotation == 90 || page.rotation == 270;
      final w = swap ? crop.height : crop.width;
      final h = swap ? crop.width : crop.height;

      // its annotations are in the picture now (and form fields only they
      // showed go with them)
      final annots = cos.resolve(dict['Annots']);
      if (annots is CosArray) {
        for (final item in annots.items) {
          final a = cos.resolve(item);
          if (a is! CosDictionary) continue;
          final ref = item is CosReference ? item : cos.referenceTo(a);
          if (ref != null) session.purged.add(ref.objectNumber);
          if (PdfRedactionApply._isSubtype(cos, a, 'Widget')) {
            _purgeWidgetField(a, session);
          }
        }
      }

      final pixels = raster.toRgbOnWhite();
      final payload =
          Uint8List.fromList(const ZLibEncoder().encodeBytes(pixels, level: 6));
      final image = _updater.addObject(CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': CosInteger(raster.width),
          'Height': CosInteger(raster.height),
          'ColorSpace': const CosName('DeviceRGB'),
          'BitsPerComponent': const CosInteger(8),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(payload.length),
        }),
        payload,
      ));
      final content = Uint8List.fromList(latin1.encode(
          'q ${ContentWriter.fmt(w)} 0 0 ${ContentWriter.fmt(h)} 0 0 cm '
          '/RdPage Do Q\n'));
      final contents = _updater.addObject(CosStream(
          CosDictionary({'Length': CosInteger(content.length)}), content));

      // the page keeps only its place in the tree; every inheritable
      // attribute is set here so nothing comes back from an ancestor
      final keep = {
        for (final key in const ['Type', 'Parent', 'UserUnit'])
          if (dict.containsKey(key)) key: dict[key]!,
      };
      final box = CosArray([
        const CosInteger(0),
        const CosInteger(0),
        CosReal(w),
        CosReal(h),
      ]);
      dict.entries
        ..clear()
        ..addAll(keep)
        ..addAll({
          'MediaBox': box,
          'CropBox': box,
          'Rotate': const CosInteger(0),
          'Resources': CosDictionary({
            'XObject': CosDictionary({'RdPage': image}),
          }),
          'Contents': contents,
        });
      _updater.markChanged(dict);
    });
    if (rasters.isEmpty) return save();

    // Structure elements that described these pages' content lose their
    // text: those on the page (their own /Pg, one inherited from a parent,
    // or a marked-content or object reference's /Pg), and every element
    // above them, whose /Alt or /ActualText can sum up what they held.
    final catalog = cos.resolve(cos.trailer['Root']);
    final root = catalog is CosDictionary
        ? cos.resolve(catalog['StructTreeRoot'])
        : null;
    if (root is CosDictionary) {
      final parentOf = Map<CosDictionary, CosDictionary?>.identity();
      final stripped = Set<CosDictionary>.identity();
      void strip(CosDictionary? element) {
        while (element != null && stripped.add(element)) {
          for (final key in _PdfRedactionText.markedKeys) {
            element.entries.remove(key);
          }
          _touch(element);
          element = parentOf[element];
        }
      }

      final stack = <(CosObject, CosDictionary?, CosDictionary?)>[
        (cos.resolve(root['K']), null, null),
      ];
      while (stack.isNotEmpty && parentOf.length < 500000) {
        final (node, parent, inheritedPage) = stack.removeLast();
        if (node is CosArray) {
          for (final kid in node.items) {
            stack.add((cos.resolve(kid), parent, inheritedPage));
          }
          continue;
        }
        if (node is! CosDictionary) continue;
        final pg = cos.resolve(node['Pg']);
        final page = pg is CosDictionary ? pg : inheritedPage;
        final type = cos.resolve(node['Type']);
        final isReference =
            type is CosName && (type.value == 'MCR' || type.value == 'OBJR');
        if (isReference) {
          if (page != null && rasterized.contains(page)) strip(parent);
          continue;
        }
        if (parentOf.containsKey(node)) continue;
        parentOf[node] = parent;
        if (page != null && rasterized.contains(page)) strip(node);
        stack.add((cos.resolve(node['K']), node, page));
      }
    }
    _guardPageTree(session);
    _markDestructive(rasters.keys);
    return _compactedSave(session.purged);
  }
}

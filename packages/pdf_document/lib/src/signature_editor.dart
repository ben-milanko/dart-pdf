part of 'editor.dart';

/// The visible signature box drawn into a signature field's widget when
/// signing - the two-column layout Acrobat and Bluebeam render once a
/// field is signed: the signer's name (or a handwritten-signature image)
/// set large in the left panel, and the signing details ("Digitally signed
/// by …", date, reason, location) listed on the right.
///
/// Pass one to [PdfSigning.saveSigned] or [PdfPadesSigning.saveSignedPades]
/// to place and render the box. When signing into a form field that already
/// carries a visible /Rect, the box is drawn into that rectangle even
/// without an explicit appearance (the defaults are used); [page] and
/// [rect] only place a box on a freshly created field.
class PdfSignatureAppearance {
  const PdfSignatureAppearance({
    this.page = 0,
    this.rect,
    this.graphic,
    this.backgroundImage,
    this.showName = true,
    this.showDate = true,
    this.showReason = true,
    this.showLocation = true,
    this.backgroundColor,
    this.borderColor = 0x2E5E86,
    this.textColor = 0x1A1A1A,
  });

  /// The 0-based page a newly created signature widget is placed on.
  /// Ignored when signing into a field that already exists - that field
  /// keeps the page its widget already sits on.
  final int page;

  /// The widget rectangle, in PDF user space, for a newly created field.
  /// Required to put a visible box on a fresh field; ignored when signing
  /// an existing field (which keeps its own /Rect).
  final PdfRect? rect;

  /// An optional handwritten-signature or logo image drawn in the left
  /// panel in place of the large name text.
  final PdfEmbeddableImage? graphic;

  /// An optional image drawn opaquely across the whole box, behind the
  /// border, divider, text and [graphic] - a company logo or letterhead
  /// backdrop. Scaled to cover the box (aspect fill, clipped to the /Rect).
  final PdfEmbeddableImage? backgroundImage;

  /// Draws the large signer name in the left panel and the
  /// "Digitally signed by …" line on the right.
  final bool showName;

  /// Draws the signing date/time on the right.
  final bool showDate;

  /// Draws the /Reason on the right, when the signature carries one.
  final bool showReason;

  /// Draws the /Location on the right, when the signature carries one.
  final bool showLocation;

  /// Panel background fill (0xRRGGBB), or null for a transparent box.
  final int? backgroundColor;

  /// The border and column-divider color (0xRRGGBB).
  final int borderColor;

  /// The text color (0xRRGGBB).
  final int textColor;
}

/// The signer details rendered into a visible signature box.
class _SignatureText {
  const _SignatureText({this.name, this.time, this.reason, this.location});

  final String? name;
  final DateTime? time;
  final String? reason;
  final String? location;
}

/// Signing: writes the pending edits plus a new signature as one
/// incremental update, then fills in the byte range and CMS container.
extension PdfSigning on PdfEditor {
  /// Signs the document and returns the complete signed file. Any edits
  /// queued on this editor are included in the signed revision.
  ///
  /// The signature is `adbe.pkcs7.detached` (CMS, RSA PKCS#1 v1.5 with
  /// SHA-256). [certificates] is the signer's DER chain, leaf first; its
  /// subject becomes the visible signer unless [signerName] overrides it.
  /// An existing empty signature field called [fieldName] is used when
  /// present, otherwise an invisible signature field is created on the
  /// first page.
  ///
  /// Pass an [appearance] to draw a visible signature box (the Acrobat/
  /// Bluebeam two-column layout). When signing into a field that already
  /// has a visible /Rect the box is rendered into it even without an
  /// [appearance]; [PdfSignatureAppearance.rect] places a box on a fresh
  /// field. After this call the editor is spent - saving again would
  /// invalidate the signature it just produced.
  Uint8List saveSigned({
    required RsaPrivateKey privateKey,
    required List<Uint8List> certificates,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) {
    if (certificates.isEmpty) {
      throw ArgumentError('the signer certificate is required');
    }
    final time = (signingTime ?? DateTime.now()).toUtc();
    final revision = _emitSignatureRevision(
      subFilter: 'adbe.pkcs7.detached',
      capacity: _cmsCapacity(certificates),
      fieldName: fieldName,
      signingTime: time,
      signerName: signerName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      defaultSignerCert: certificates.first,
      appearance: appearance,
    );
    final cms = cmsSignDetached(
      contentDigest: crypto.sha256.convert(revision.signedData).bytes,
      privateKey: privateKey,
      certificates: certificates,
      signingTime: time,
    );
    _writeContents(revision, cms);
    return revision.saved;
  }

  /// Signs with an EC ([EcPrivateKey]) private key instead of RSA - the path
  /// a self-signed P-256 [PdfSigningIdentity] takes. Otherwise identical to
  /// [saveSigned]: an `adbe.pkcs7.detached` CMS (ECDSA over SHA-256), the
  /// signer's certificate DER chain leaf-first, an optional visible
  /// [appearance], and the same spent-after-use contract.
  Uint8List saveSignedEcdsa({
    required EcPrivateKey privateKey,
    required List<Uint8List> certificates,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) {
    if (certificates.isEmpty) {
      throw ArgumentError('the signer certificate is required');
    }
    final time = (signingTime ?? DateTime.now()).toUtc();
    final revision = _emitSignatureRevision(
      subFilter: 'adbe.pkcs7.detached',
      capacity: _cmsCapacity(certificates),
      fieldName: fieldName,
      signingTime: time,
      signerName: signerName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      defaultSignerCert: certificates.first,
      appearance: appearance,
    );
    final cms = cmsSignDetachedEcdsa(
      contentDigest: crypto.sha256.convert(revision.signedData).bytes,
      privateKey: privateKey,
      certificates: certificates,
      signingTime: time,
    );
    _writeContents(revision, cms);
    return revision.saved;
  }

  /// One-tap signing with a [PdfSigningIdentity] - typically one minted by
  /// [PdfSigningIdentity.generate]. Dispatches to [saveSignedEcdsa],
  /// defaulting the visible signer name to the identity's [name].
  Uint8List saveSelfSigned({
    required PdfSigningIdentity identity,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) =>
      saveSignedEcdsa(
        privateKey: identity.privateKey,
        certificates: identity.certificates,
        fieldName: fieldName,
        signerName: signerName ?? identity.name,
        reason: reason,
        location: location,
        contactInfo: contactInfo,
        signingTime: signingTime,
        appearance: appearance,
      );

  /// Bytes reserved for an embedded RFC 3161 timestamp token. The token is a
  /// full CMS SignedData that carries the TSA's own certificate chain (a
  /// public TSA like DigiCert ships several KB of certs), so it needs its own
  /// budget on top of the signer chain. Used both as the standalone
  /// DocTimeStamp /Contents size and as extra slack for a PAdES B-T CMS, whose
  /// token is fetched only after the /Contents space is already reserved.
  static const int _timestampTokenReserve = 16384;

  /// Generous space for a CMS: certificates, attributes, signature, plus - when
  /// a PAdES path embeds an RFC 3161 timestamp ([withTimestamp]) - a full
  /// timestamp token's worth of slack.
  static int _cmsCapacity(List<Uint8List> certificates,
      {bool withTimestamp = false}) {
    var capacity = 6144;
    for (final cert in certificates) {
      capacity += cert.length;
    }
    if (withTimestamp) capacity += _timestampTokenReserve;
    return capacity;
  }

  /// Writes one incremental revision carrying a /Sig (or /DocTimeStamp)
  /// dictionary with placeholder /Contents and /ByteRange, attaches it to a
  /// signature field, saves, patches the real /ByteRange, and returns the
  /// buffer, the /Contents hex span, and the signed byte ranges. The caller
  /// computes the CMS or timestamp token and fills the span via
  /// [_writeContents].
  _SignatureRevision _emitSignatureRevision({
    required String subFilter,
    required int capacity,
    String? fieldName,
    DateTime? signingTime,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    Uint8List? defaultSignerCert,
    bool docTimeStamp = false,
    int? docMdpPermissions,
    PdfSignatureAppearance? appearance,
  }) {
    if (document.cos.isEncrypted) {
      // the signature /Contents and /ByteRange must stay unencrypted and
      // byte-patchable in the written file; encrypt-on-write would
      // scramble the placeholders this method patches
      throw UnsupportedEncryptionException(
          'signing encrypted documents is not supported yet');
    }
    final cos = document.cos;
    final placeholder = Uint8List(capacity);
    final name = signerName ??
        (defaultSignerCert != null ? _subjectCn(defaultSignerCert) : null);

    final entries = <String, CosObject>{
      'Type': CosName(docTimeStamp ? 'DocTimeStamp' : 'Sig'),
      'Filter': const CosName('Adobe.PPKLite'),
      'SubFilter': CosName(subFilter),
      'ByteRange': CosArray([
        const CosInteger(0),
        CosInteger(_rangePlaceholder),
        CosInteger(_rangePlaceholder),
        CosInteger(_rangePlaceholder),
      ]),
      'Contents': CosString(placeholder, isHex: true),
      if (!docTimeStamp && signingTime != null)
        'M': CosString.fromText(_pdfDate(signingTime)),
      if (!docTimeStamp && name != null) 'Name': CosString.fromText(name),
      if (!docTimeStamp && reason != null) 'Reason': CosString.fromText(reason),
      if (!docTimeStamp && location != null)
        'Location': CosString.fromText(location),
      if (!docTimeStamp && contactInfo != null)
        'ContactInfo': CosString.fromText(contactInfo),
    };
    final sigDict = CosDictionary(entries);
    if (docMdpPermissions != null) {
      sigDict['Reference'] = CosArray([
        CosDictionary({
          'Type': const CosName('SigRef'),
          'TransformMethod': const CosName('DocMDP'),
          'TransformParams': CosDictionary({
            'Type': const CosName('TransformParams'),
            'V': const CosName('1.2'),
            'P': CosInteger(docMdpPermissions),
          }),
          'DigestMethod': const CosName('SHA256'),
        }),
      ]);
    }
    final sigRef = _updater.addObject(sigDict);
    if (docMdpPermissions != null) {
      _applyDocMdp(sigRef);
    }
    _attachSignatureField(
      sigRef,
      fieldName,
      certify: docMdpPermissions != null,
      appearance: docTimeStamp ? null : appearance,
      text: _SignatureText(
        name: name,
        time: signingTime,
        reason: reason,
        location: location,
      ),
    );

    final saved = _updater.save();

    final tPatch = PdfPerf.begin();
    final tailStart = cos.bytes.length;
    final hexLength = placeholder.length * 2;
    final contentsStart =
        _find(saved, tailStart, '<${'0' * hexLength}>'.codeUnits);
    if (contentsStart < 0) {
      throw StateError('signature placeholder not found in output');
    }
    final contentsEnd = contentsStart + hexLength + 2;
    final rangeToken = '[0 $_rangePlaceholder $_rangePlaceholder '
        '$_rangePlaceholder]';
    final rangeStart = _find(saved, tailStart, rangeToken.codeUnits);
    if (rangeStart < 0) {
      throw StateError('byte-range placeholder not found in output');
    }
    final byteRange =
        '[0 $contentsStart $contentsEnd ${saved.length - contentsEnd}]'
            .padRight(rangeToken.length)
            .codeUnits;
    saved.setRange(rangeStart, rangeStart + byteRange.length, byteRange);
    PdfPerf.end(PdfPerfPhase.byteRangePatch, tPatch);

    final signedBytes = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(saved, 0, contentsStart))
      ..add(Uint8List.sublistView(saved, contentsEnd));
    return _SignatureRevision(
        saved, contentsStart, contentsEnd, signedBytes.takeBytes());
  }

  /// Fills a revision's /Contents placeholder with [blob] (a CMS container
  /// or a bare RFC 3161 token), hex-encoded.
  static void _writeContents(_SignatureRevision revision, Uint8List blob) {
    final capacity = (revision.contentsEnd - revision.contentsStart - 2) ~/ 2;
    if (blob.length > capacity) {
      throw StateError('signature blob exceeded its reserved space');
    }
    const hexDigits = '0123456789ABCDEF';
    final saved = revision.saved;
    for (var i = 0; i < blob.length; i++) {
      saved[revision.contentsStart + 1 + i * 2] =
          hexDigits.codeUnitAt(blob[i] >> 4);
      saved[revision.contentsStart + 2 + i * 2] =
          hexDigits.codeUnitAt(blob[i] & 0xF);
    }
  }

  /// Points the catalog's /Perms /DocMDP at the certifying signature, the
  /// author signature's lock on the document (§12.8.2.2).
  void _applyDocMdp(CosReference sigRef) {
    final cos = document.cos;
    final perms = cos.resolve(document.catalog['Perms']);
    if (perms is CosDictionary) {
      perms['DocMDP'] = sigRef;
      final permsRef = document.catalog['Perms'];
      if (permsRef is CosReference) {
        _updater.replaceObject(permsRef.objectNumber, perms);
      } else {
        _updater.markChanged(document.catalog);
      }
    } else {
      document.catalog['Perms'] = CosDictionary({'DocMDP': sigRef});
      _updater.markChanged(document.catalog);
    }
  }

  /// Ten digits so the patched real values always fit.
  static const _rangePlaceholder = 9999999999;

  static String _pdfDate(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'D:${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  static String? _subjectCn(Uint8List certDer) {
    try {
      return X509Certificate.parse(certDer).subjectCommonName;
    } on Object {
      return null;
    }
  }

  static int _find(Uint8List haystack, int from, List<int> needle) {
    outer:
    for (var i = from; i + needle.length <= haystack.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// Points an existing empty signature field at [sigRef], or creates a
  /// field on the requested page. [certify] marks an author signature
  /// (the DocMDP /Perms wiring is applied separately by the caller). When
  /// the target widget has a visible /Rect a signature box is rendered
  /// into it from [appearance] and [text]; a fresh field is invisible
  /// unless [appearance] supplies a [PdfSignatureAppearance.rect].
  void _attachSignatureField(
    CosReference sigRef,
    String? fieldName, {
    bool certify = false,
    PdfSignatureAppearance? appearance,
    _SignatureText? text,
  }) {
    final cos = document.cos;
    final form = PdfAcroForm.of(document);

    if (fieldName != null && form != null) {
      final existing = form.fieldNamed(fieldName);
      if (existing != null) {
        if (existing.type != PdfFieldType.signature) {
          throw ArgumentError('field "$fieldName" is not a signature field');
        }
        if (cos.resolve(existing.dict['V']) is CosDictionary) {
          throw StateError('field "$fieldName" is already signed');
        }
        existing.dict['V'] = sigRef;
        // Fill the field's box with a signature appearance when it is
        // visible, matching how Acrobat/Bluebeam render a signed field.
        final widget = existing.widgets.first;
        final rect = pdfRectFrom(cos, widget['Rect']);
        if (rect != null && rect.width > 1 && rect.height > 1) {
          _installSignatureAppearance(widget, rect,
              appearance ?? const PdfSignatureAppearance(), text);
          if (!identical(widget, existing.dict) &&
              cos.referenceTo(widget) != null) {
            _updater.markChanged(widget);
          }
        }
        _updater.markChanged(existing.dict);
        _ensureSigFlags();
        return;
      }
    }

    final visible = appearance?.rect;
    final pageIndex = visible != null
        ? appearance!.page.clamp(0, document.pageCount - 1)
        : 0;
    final page = document.page(pageIndex);
    final pageRef = cos.referenceTo(page.dict);
    final name = fieldName ?? _freshFieldName(form);
    final rect = visible == null
        ? CosArray([
            const CosInteger(0), const CosInteger(0), //
            const CosInteger(0), const CosInteger(0),
          ])
        : CosArray([
            CosReal(visible.left),
            CosReal(visible.bottom),
            CosReal(visible.right),
            CosReal(visible.top),
          ]);
    final fieldDict = CosDictionary({
      'FT': const CosName('Sig'),
      'T': CosString.fromText(name),
      'V': sigRef,
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Widget'),
      'Rect': rect,
      'F': const CosInteger(132), // print + locked
      if (pageRef != null) 'P': pageRef,
    });
    if (visible != null) {
      _installSignatureAppearance(fieldDict, visible, appearance!, text);
    }
    final fieldRef = _updater.addObject(fieldDict);

    // page /Annots
    _PdfPageAnnotationList(this, pageIndex).append(fieldRef);

    // AcroForm /Fields
    final acroForm = cos.resolve(document.catalog['AcroForm']);
    if (acroForm is CosDictionary) {
      final fields = cos.resolve(acroForm['Fields']);
      if (fields is CosArray) {
        fields.items.add(fieldRef);
      } else {
        acroForm['Fields'] = CosArray([fieldRef]);
      }
      acroForm['SigFlags'] = const CosInteger(3);
      final acroRef = document.catalog['AcroForm'];
      if (acroRef is CosReference) {
        _updater.replaceObject(acroRef.objectNumber, acroForm);
      } else {
        _updater.markChanged(document.catalog);
      }
    } else {
      document.catalog['AcroForm'] = _updater.addObject(CosDictionary({
        'Fields': CosArray([fieldRef]),
        'SigFlags': const CosInteger(3),
      }));
      _updater.markChanged(document.catalog);
    }
  }

  void _ensureSigFlags() {
    final cos = document.cos;
    final acroForm = cos.resolve(document.catalog['AcroForm']);
    if (acroForm is! CosDictionary) return;
    final flags = cos.resolve(acroForm['SigFlags']);
    final current = flags is CosInteger ? flags.value : 0;
    if (current & 3 != 3) {
      acroForm['SigFlags'] = CosInteger(current | 3);
      final acroRef = document.catalog['AcroForm'];
      if (acroRef is CosReference) {
        _updater.replaceObject(acroRef.objectNumber, acroForm);
      } else {
        _updater.markChanged(document.catalog);
      }
    }
  }

  String _freshFieldName(PdfAcroForm? form) {
    final taken = {
      if (form != null)
        for (final field in form.fields) field.name,
    };
    var i = 1;
    while (taken.contains('Signature$i')) {
      i++;
    }
    return 'Signature$i';
  }

  // ---------------------------------------------------------------------
  // visible signature box (§12.7.4.5)

  /// Renders the signature box into [widget]'s /AP /N: an optional
  /// background and border, a left panel holding the signer's name (or a
  /// handwritten-signature image), and a right panel listing the signing
  /// details. Mirrors the two-column layout Acrobat and Bluebeam draw.
  void _installSignatureAppearance(CosDictionary widget, PdfRect rect,
      PdfSignatureAppearance config, _SignatureText? text) {
    final w = rect.width, h = rect.height;
    final info = text ?? const _SignatureText();
    final writer = ContentWriter();
    final fonts = CosDictionary({});
    final xObjects = CosDictionary({});
    const pad = 4.0;

    if (config.backgroundColor != null) {
      writer
        ..fillColor(config.backgroundColor!)
        ..rect(0, 0, w, h)
        ..fill();
    }
    if (config.backgroundImage != null) {
      final image = config.backgroundImage!;
      if (image.width > 0 && image.height > 0) {
        final imageRef =
            _updater.addObject(image.toXObject((s) => _updater.addObject(s)));
        // Cover the box (aspect fill), clipped to the /Rect so overflow of
        // the larger dimension is trimmed rather than drawn outside the box.
        final scale =
            math.max(w / image.width, h / image.height);
        final dw = image.width * scale, dh = image.height * scale;
        writer
          ..save()
          ..rect(0, 0, w, h)
          ..clip()
          ..concatMatrix(dw, 0, 0, dh, (w - dw) / 2, (h - dh) / 2)
          ..drawXObject('SigBg')
          ..restore();
        xObjects['SigBg'] = imageRef;
      }
    }
    writer
      ..strokeColor(config.borderColor)
      ..lineWidth(1)
      ..rect(0.5, 0.5, w - 1, h - 1)
      ..stroke();

    final name = info.name;
    final showName = config.showName && name != null && name.isNotEmpty;
    final hasGraphic = config.graphic != null;
    final hasLeft = hasGraphic || showName;

    final details = <String>[
      if (config.showName && name != null && name.isNotEmpty)
        'Digitally signed by $name',
      if (config.showDate && info.time != null)
        'Date: ${_displaySignDate(info.time!)}',
      if (config.showReason &&
          info.reason != null &&
          info.reason!.isNotEmpty)
        'Reason: ${info.reason}',
      if (config.showLocation &&
          info.location != null &&
          info.location!.isNotEmpty)
        'Location: ${info.location}',
    ];

    // Column split: a divider only when both panels carry content.
    double divider;
    if (hasLeft && details.isNotEmpty) {
      divider = w * 0.42;
      writer
        ..strokeColor(config.borderColor)
        ..lineWidth(0.5)
        ..moveTo(divider, pad)
        ..lineTo(divider, h - pad)
        ..stroke();
    } else if (hasLeft) {
      divider = w; // left content only
    } else {
      divider = 0; // details only
    }

    if (hasGraphic) {
      final image = config.graphic!;
      final imageRef =
          _updater.addObject(image.toXObject((s) => _updater.addObject(s)));
      final panelW = divider - 2 * pad, panelH = h - 2 * pad;
      if (panelW > 0 && panelH > 0 && image.width > 0 && image.height > 0) {
        final scale = math.min(
            panelW / image.width, panelH / image.height);
        final dw = image.width * scale, dh = image.height * scale;
        writer
          ..save()
          ..concatMatrix(dw, 0, 0, dh, pad + (panelW - dw) / 2,
              pad + (panelH - dh) / 2)
          ..drawXObject('SigImg')
          ..restore();
        xObjects['SigImg'] = imageRef;
      }
    } else if (showName) {
      const boldFont = PdfStandardFont.helveticaBold;
      fonts[boldFont.resourceName] = _signatureFont(boldFont);
      _drawSignatureText(
        writer,
        [name],
        boldFont,
        config.textColor,
        pad,
        pad,
        divider - pad,
        h - pad,
        maxSize: 22,
        align: PdfTextAlign.center,
        centerVertical: true,
      );
    }

    if (details.isNotEmpty) {
      const detailFont = PdfStandardFont.helvetica;
      fonts[detailFont.resourceName] = _signatureFont(detailFont);
      final left = divider > 0 ? divider + pad : pad;
      _drawSignatureText(
        writer,
        details,
        detailFont,
        config.textColor,
        left,
        pad,
        w - pad,
        h - pad,
        maxSize: 9,
      );
    }

    final resources = CosDictionary({
      if (fonts.entries.isNotEmpty) 'Font': fonts,
      if (xObjects.entries.isNotEmpty) 'XObject': xObjects,
    });
    final form = _widgetForm(w, h, writer, resources: resources);
    _setNormalAppearance(widget, form);
  }

  /// A base-14 font dict (with /Widths) for the appearance's /Font resource.
  CosDictionary _signatureFont(PdfStandardFont font) => CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type1'),
        'BaseFont': CosName(font.baseFont),
        'Encoding': const CosName('WinAnsiEncoding'),
        'FirstChar': const CosInteger(32),
        'LastChar': const CosInteger(126),
        'Widths': CosArray([for (final width in font.widths) CosInteger(width)]),
      });

  /// Lays [lines] out in the box `[left, bottom, right, top]`, shrinking the
  /// font (from [maxSize]) and wrapping until the block fits, clipped to the
  /// box. Top-anchored unless [centerVertical]; aligned per [align].
  void _drawSignatureText(
    ContentWriter writer,
    List<String> lines,
    PdfStandardFont font,
    int color,
    double left,
    double bottom,
    double right,
    double top, {
    required double maxSize,
    PdfTextAlign align = PdfTextAlign.left,
    bool centerVertical = false,
  }) {
    final boxW = right - left, boxH = top - bottom;
    if (boxW <= 0 || boxH <= 0) return;

    var size = maxSize;
    List<String> wrapped;
    while (true) {
      wrapped = [
        for (final line in lines)
          ...pdfWrapText(line, boxW, (s) => font.measure(s, size)),
      ];
      if (wrapped.length * size * 1.3 <= boxH || size <= 4) break;
      size -= 0.5;
    }
    if (wrapped.isEmpty) return;

    // The box edges already exclude the caller's padding, so the shared
    // builder runs with zero padding and unclamped alignment.
    writer.save();
    writePdfTextBox(
      writer,
      PdfRect(left, bottom, right, top),
      wrapped,
      font: font,
      fontSize: size,
      align: align,
      padding: 0,
      lineHeight: size * 1.3,
      vAlign: centerVertical
          ? PdfTextBoxVAlign.centerBlock
          : PdfTextBoxVAlign.top,
      writeColor: (w) => w.fillColor(color),
    );
    writer.restore();
  }

  /// Acrobat-style display date: `2026.06.10 12:00:00 +00'00'`. Signing
  /// times are normalized to UTC before display.
  static String _displaySignDate(DateTime time) {
    final utc = time.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}.${two(utc.month)}.${two(utc.day)} '
        "${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} +00'00'";
  }
}

/// A written-but-unsigned revision: the buffer with patched /ByteRange, the
/// /Contents hex span to fill, and the signed byte ranges to digest.
class _SignatureRevision {
  _SignatureRevision(
      this.saved, this.contentsStart, this.contentsEnd, this.signedData);

  final Uint8List saved;
  final int contentsStart;
  final int contentsEnd;
  final Uint8List signedData;
}

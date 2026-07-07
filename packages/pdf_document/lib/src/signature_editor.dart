part of 'editor.dart';

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
  /// first page. After this call the editor is spent - saving again
  /// would invalidate the signature it just produced.
  Uint8List saveSigned({
    required RsaPrivateKey privateKey,
    required List<Uint8List> certificates,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
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

  /// Generous space for a CMS: certificates, attributes, signature, plus a
  /// timestamp token's worth of slack for the PAdES paths.
  static int _cmsCapacity(List<Uint8List> certificates) {
    var capacity = 6144;
    for (final cert in certificates) {
      capacity += cert.length;
    }
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
    _attachSignatureField(sigRef, fieldName,
        certify: docMdpPermissions != null);

    final saved = _updater.save();

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

  /// Points an existing empty signature field at [sigRef], or creates an
  /// invisible one on the first page. [certify] marks an author signature
  /// (the DocMDP /Perms wiring is applied separately by the caller).
  void _attachSignatureField(CosReference sigRef, String? fieldName,
      {bool certify = false}) {
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
        _updater.markChanged(existing.dict);
        _ensureSigFlags();
        return;
      }
    }

    final page = document.page(0);
    final pageRef = cos.referenceTo(page.dict);
    final name = fieldName ?? _freshFieldName(form);
    final fieldDict = CosDictionary({
      'FT': const CosName('Sig'),
      'T': CosString.fromText(name),
      'V': sigRef,
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Widget'),
      'Rect': CosArray([
        const CosInteger(0), const CosInteger(0), //
        const CosInteger(0), const CosInteger(0),
      ]),
      'F': const CosInteger(132), // print + locked
      if (pageRef != null) 'P': pageRef,
    });
    final fieldRef = _updater.addObject(fieldDict);

    // page /Annots
    _PdfPageAnnotationList(this, 0).append(fieldRef);

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

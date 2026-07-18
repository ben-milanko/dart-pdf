part of 'editor.dart';

/// PAdES (ETSI EN 319 142) signing: the enterprise signature tier on top of
/// [PdfSigning.saveSigned]. Adds the CAdES baseline signed attributes
/// (signing-certificate-v2), RFC 3161 signature timestamps, a /DSS Document
/// Security Store for long-term validation, and a renewable document
/// timestamp.
///
/// The TSA and revocation transports are injected ([PdfTimestampClient],
/// [PdfRevocationClient]) - the library performs no network I/O.
extension PdfPadesSigning on PdfEditor {
  /// Signs the document at PAdES baseline [level] and returns the complete
  /// signed file. Builds an `ETSI.CAdES.detached` signature with the
  /// signing-certificate-v2 attribute (B-B); above B-B it embeds a signature
  /// timestamp (B-T), a /DSS with revocation material (B-LT), and a document
  /// timestamp (B-LTA), each as its own incremental update.
  ///
  /// [certificates] is the signer's DER chain, leaf first. A
  /// [timestampClient] is required for B-T and up; a [revocationClient]
  /// supplies the OCSP/CRL material for B-LT and up (without one the /DSS
  /// carries only the certificate chain). Set [certify] to make this an
  /// author signature with a /DocMDP transform at [docMdpPermissions]
  /// (1 = no changes, 2 = form-fill + signing, 3 = + annotations).
  ///
  /// Pass an [appearance] to draw a visible signature box (the Acrobat/
  /// Bluebeam two-column layout); the same rules as [PdfSigning.saveSigned]
  /// apply. After this call the editor is spent.
  Future<Uint8List> saveSignedPades({
    required RsaPrivateKey privateKey,
    required List<Uint8List> certificates,
    PdfPadesLevel level = PdfPadesLevel.bB,
    PdfTimestampClient? timestampClient,
    PdfRevocationClient? revocationClient,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    bool certify = false,
    int docMdpPermissions = 2,
    PdfSignatureAppearance? appearance,
  }) =>
      _saveSignedPades(
        signAttributes: (digest) =>
            rsaSign(privateKey, DigestOid.sha256, digest),
        signatureAlgorithm: null, // rsaEncryption (the assembler's default)
        certificates: certificates,
        level: level,
        timestampClient: timestampClient,
        revocationClient: revocationClient,
        fieldName: fieldName,
        signerName: signerName,
        reason: reason,
        location: location,
        contactInfo: contactInfo,
        signingTime: signingTime,
        certify: certify,
        docMdpPermissions: docMdpPermissions,
        appearance: appearance,
      );

  /// The EC counterpart of [saveSignedPades]: signs the CAdES-baseline
  /// signature with an [EcPrivateKey] (ECDSA over SHA-256) instead of RSA.
  /// This is how a self-signed P-256 [PdfSigningIdentity] earns a trusted
  /// signature timestamp (B-T) - CA-anchored signing time even though the
  /// signer certificate itself is not publicly trusted. All other arguments
  /// behave exactly as in [saveSignedPades].
  Future<Uint8List> saveSignedPadesEcdsa({
    required EcPrivateKey privateKey,
    required List<Uint8List> certificates,
    PdfPadesLevel level = PdfPadesLevel.bB,
    PdfTimestampClient? timestampClient,
    PdfRevocationClient? revocationClient,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    bool certify = false,
    int docMdpPermissions = 2,
    PdfSignatureAppearance? appearance,
  }) =>
      _saveSignedPades(
        signAttributes: (digest) => ecdsaSign(privateKey, digest),
        signatureAlgorithm: ecdsaSignatureAlgorithm(crypto.sha256),
        certificates: certificates,
        level: level,
        timestampClient: timestampClient,
        revocationClient: revocationClient,
        fieldName: fieldName,
        signerName: signerName,
        reason: reason,
        location: location,
        contactInfo: contactInfo,
        signingTime: signingTime,
        certify: certify,
        docMdpPermissions: docMdpPermissions,
        appearance: appearance,
      );

  /// One-tap PAdES signing with a [PdfSigningIdentity]: dispatches to
  /// [saveSignedPadesEcdsa] and defaults the signer name to the identity's.
  /// Wire a [timestampClient] to a default public TSA (see
  /// [PdfDefaultTimestampAuthority]) and pass [PdfPadesLevel.bT] so even a
  /// self-signed signature carries trusted time.
  Future<Uint8List> saveSelfSignedPades({
    required PdfSigningIdentity identity,
    PdfPadesLevel level = PdfPadesLevel.bB,
    PdfTimestampClient? timestampClient,
    PdfRevocationClient? revocationClient,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    bool certify = false,
    int docMdpPermissions = 2,
    PdfSignatureAppearance? appearance,
  }) =>
      saveSignedPadesEcdsa(
        privateKey: identity.privateKey,
        certificates: identity.certificates,
        level: level,
        timestampClient: timestampClient,
        revocationClient: revocationClient,
        fieldName: fieldName,
        signerName: signerName ?? identity.name,
        reason: reason,
        location: location,
        contactInfo: contactInfo,
        signingTime: signingTime,
        certify: certify,
        docMdpPermissions: docMdpPermissions,
        appearance: appearance,
      );

  /// Shared PAdES core: [signAttributes] signs the SHA-256 digest of the
  /// signed attributes (RSA or ECDSA), and [signatureAlgorithm] is the
  /// matching SignerInfo AlgorithmIdentifier (null = rsaEncryption).
  Future<Uint8List> _saveSignedPades({
    required Uint8List Function(List<int> attributeDigest) signAttributes,
    required Uint8List? signatureAlgorithm,
    required List<Uint8List> certificates,
    required PdfPadesLevel level,
    PdfTimestampClient? timestampClient,
    PdfRevocationClient? revocationClient,
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    bool certify = false,
    int docMdpPermissions = 2,
    PdfSignatureAppearance? appearance,
  }) async {
    if (certificates.isEmpty) {
      throw ArgumentError('the signer certificate is required');
    }
    if (level >= PdfPadesLevel.bT && timestampClient == null) {
      throw ArgumentError(
          'PAdES ${level.name} requires a timestampClient for the timestamp');
    }
    final time = (signingTime ?? DateTime.now()).toUtc();
    final signerCert = X509Certificate.parse(certificates.first);
    final signerChain = [for (final c in certificates) X509Certificate.parse(c)];

    // --- B-B / B-T: the CAdES-baseline signature in the /Contents ---
    final revision = _emitSignatureRevision(
      subFilter: 'ETSI.CAdES.detached',
      capacity: PdfSigning._cmsCapacity(certificates,
          withTimestamp: level >= PdfPadesLevel.bT),
      fieldName: fieldName,
      signingTime: time,
      signerName: signerName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      defaultSignerCert: certificates.first,
      docMdpPermissions: certify ? docMdpPermissions : null,
      appearance: appearance,
    );
    final signedAttrs = cmsSignedAttributes(
      contentDigest: crypto.sha256.convert(revision.signedData).bytes,
      signingTime: time,
      essCertificate: signerCert,
    );
    final signature =
        signAttributes(crypto.sha256.convert(signedAttrs).bytes);

    final unsigned = <Uint8List>[];
    var tsaChain = const <X509Certificate>[];
    if (level >= PdfPadesLevel.bT) {
      final token = await _fetchTimestamp(timestampClient!, signature);
      unsigned.add(cmsSignatureTimeStampAttribute(token));
      tsaChain = _certsOfToken(token);
    }
    final cms = cmsAssembleSignedData(
      signedAttributes: signedAttrs,
      signature: signature,
      certificates: certificates,
      unsignedAttributes: unsigned,
      signatureAlgorithm: signatureAlgorithm,
    );
    PdfSigning._writeContents(revision, cms);
    var bytes = revision.saved;

    // --- B-LT: embed validation material in a /DSS keyed to this signature
    if (level >= PdfPadesLevel.bLT) {
      final chain = [...signerChain, ...tsaChain];
      var material = revocationClient == null
          ? const PdfRevocationMaterial()
          : await revocationClient(chain);
      // always embed the certificate chain so the signature resolves offline
      material = material +
          PdfRevocationMaterial(certificates: [
            for (final c in chain) c.der,
          ]);
      bytes = _addValidationData(bytes, cms, material);
    }

    // --- B-LTA: a document timestamp over everything incl. the /DSS ---
    if (level >= PdfPadesLevel.bLTA) {
      bytes = await _addDocumentTimestamp(bytes, timestampClient!);
    }
    return bytes;
  }

  /// Adds a document timestamp (DocTimeStamp, SubFilter ETSI.RFC3161) over
  /// the whole current file as a fresh incremental update - the archive
  /// timestamp that B-LTA renews. Standalone too: call it on an already
  /// signed file to extend (or initiate) long-term assurance.
  Future<Uint8List> addDocumentTimestamp(
          PdfTimestampClient timestampClient) =>
      _addDocumentTimestamp(document.cos.bytes, timestampClient);

  Future<Uint8List> _addDocumentTimestamp(
      Uint8List bytes, PdfTimestampClient timestampClient) async {
    final editor = PdfEditor(PdfDocument.open(bytes));
    final revision = editor._emitSignatureRevision(
      subFilter: 'ETSI.RFC3161',
      capacity: PdfSigning._timestampTokenReserve,
      docTimeStamp: true,
    );
    final request = buildTimeStampRequest(
        messageImprint: crypto.sha256.convert(revision.signedData).bytes);
    final token = await timestampClient(request);
    PdfSigning._writeContents(revision, token);
    return revision.saved;
  }

  /// Writes a /DSS (Document Security Store) carrying [material] and a /VRI
  /// entry keyed to [cms] (the signature's /Contents), as one incremental
  /// update on top of [bytes]. This is what makes a signature LTV-enabled.
  Uint8List _addValidationData(
      Uint8List bytes, Uint8List cms, PdfRevocationMaterial material) {
    final editor = PdfEditor(PdfDocument.open(bytes));
    final vriKey = _vriKey(cms);
    editor._writeDss(material, vriKey);
    return editor._updater.save();
  }

  /// VRI dictionaries are keyed by the uppercase base-16 SHA-1 of the
  /// signature's /Contents bytes (the CMS), per PDF 2.0 §12.8.4.3.
  static String _vriKey(Uint8List cms) {
    final digest = crypto.sha1.convert(cms).bytes;
    return [
      for (final b in digest) b.toRadixString(16).padLeft(2, '0').toUpperCase(),
    ].join();
  }

  Future<Uint8List> _fetchTimestamp(
      PdfTimestampClient client, Uint8List signatureValue) async {
    final request = buildTimeStampRequest(
        messageImprint: crypto.sha256.convert(signatureValue).bytes);
    return client(request);
  }

  static List<X509Certificate> _certsOfToken(Uint8List token) {
    try {
      return TimeStampToken.parse(token).cms.certificates;
    } on Object {
      return const [];
    }
  }

  /// Writes (or merges into) the catalog's /DSS. Each DER blob becomes its
  /// own stream object; the /VRI entry under [vriKey] points at the same
  /// objects so a verifier can map material to this signature.
  void _writeDss(PdfRevocationMaterial material, String vriKey) {
    final cos = document.cos;
    CosReference streamRef(Uint8List der) => _updater.addObject(
        CosStream(CosDictionary({'Length': CosInteger(der.length)}), der));

    final certRefs = [for (final c in material.certificates) streamRef(c)];
    final ocspRefs = [for (final o in material.ocspResponses) streamRef(o)];
    final crlRefs = [for (final c in material.crls) streamRef(c)];

    // start from any existing /DSS so multiple signatures accumulate
    final existing = cos.resolve(document.catalog['DSS']);
    final dss = existing is CosDictionary ? existing : CosDictionary({});
    _appendRefs(dss, 'Certs', certRefs);
    _appendRefs(dss, 'OCSPs', ocspRefs);
    _appendRefs(dss, 'CRLs', crlRefs);

    final vri = CosDictionary({
      if (certRefs.isNotEmpty) 'Cert': CosArray([...certRefs]),
      if (ocspRefs.isNotEmpty) 'OCSP': CosArray([...ocspRefs]),
      if (crlRefs.isNotEmpty) 'CRL': CosArray([...crlRefs]),
    });
    final vriDict = cos.resolve(dss['VRI']);
    if (vriDict is CosDictionary) {
      vriDict[vriKey] = _updater.addObject(vri);
      dss['VRI'] = vriDict;
    } else {
      dss['VRI'] = CosDictionary({vriKey: _updater.addObject(vri)});
    }

    final dssRef = document.catalog['DSS'];
    if (existing is CosDictionary && dssRef is CosReference) {
      _updater.replaceObject(dssRef.objectNumber, dss);
    } else {
      document.catalog['DSS'] = _updater.addObject(dss);
      _updater.markChanged(document.catalog);
    }
  }

  void _appendRefs(CosDictionary dss, String key, List<CosReference> refs) {
    if (refs.isEmpty) return;
    final current = document.cos.resolve(dss[key]);
    dss[key] = CosArray([
      if (current is CosArray) ...current.items,
      ...refs,
    ]);
  }
}

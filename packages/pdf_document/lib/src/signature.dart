import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'form.dart';
import 'pades.dart';
import 'revocation.dart';

/// A signed signature field: the /V signature dictionary of an AcroForm
/// field with /FT /Sig (§12.8).
class PdfSignature {
  PdfSignature._(this.document, this.field, this.dict);

  final PdfDocument document;
  final PdfFormField field;

  /// The signature dictionary (/Type /Sig).
  final CosDictionary dict;

  /// All signed signature fields, in field order.
  static List<PdfSignature> of(PdfDocument document) {
    final form = PdfAcroForm.of(document);
    if (form == null) return const [];
    return [
      for (final field in form.fields)
        if (field.type == PdfFieldType.signature)
          if (document.cos.resolve(field.dict['V']) case final CosDictionary v)
            PdfSignature._(document, field, v),
    ];
  }

  String? _text(String key) {
    final value = document.cos.resolve(dict[key]);
    return value is CosString ? value.text : null;
  }

  /// Signer name as recorded by the signing software (/Name).
  String? get signerName => _text('Name');

  String? get reason => _text('Reason');
  String? get location => _text('Location');
  String? get contactInfo => _text('ContactInfo');

  /// /SubFilter, e.g. `adbe.pkcs7.detached` or `ETSI.CAdES.detached`.
  String? get subFilter {
    final value = document.cos.resolve(dict['SubFilter']);
    return value is CosName ? value.value : null;
  }

  /// True for a document timestamp (DocTimeStamp / ETSI.RFC3161) rather than
  /// an approval or author signature - the archive timestamp of PAdES B-LTA.
  bool get isDocumentTimeStamp {
    final type = document.cos.resolve(dict['Type']);
    return (type is CosName && type.value == 'DocTimeStamp') ||
        subFilter == 'ETSI.RFC3161';
  }

  /// Claimed signing time from /M (the cryptographic signingTime
  /// attribute, when present, is reported by [validate]).
  DateTime? get signingTime {
    final m = _text('M');
    if (m == null) return null;
    final match = RegExp(
            r"D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?(?:([+\-Z])(\d{2})?'?(\d{2})?)?")
        .firstMatch(m);
    if (match == null) return null;
    int part(int i, [int fallback = 0]) =>
        match.group(i) == null ? fallback : int.parse(match.group(i)!);
    var time = DateTime.utc(
        part(1), part(2, 1), part(3, 1), part(4), part(5), part(6));
    if (match.group(7) == '+' || match.group(7) == '-') {
      final offset = Duration(hours: part(8), minutes: part(9));
      time = match.group(7) == '+' ? time.subtract(offset) : time.add(offset);
    }
    return time;
  }

  /// The [start, length, start, length] pairs of signed bytes.
  List<int> get byteRange {
    final array = document.cos.resolve(dict['ByteRange']);
    if (array is! CosArray) return const [];
    return [
      for (final item in array.items)
        if (document.cos.resolve(item) case final CosInteger n) n.value,
    ];
  }

  /// The raw CMS (or PKCS#1) signature blob.
  Uint8List get contents {
    final value = document.cos.resolve(dict['Contents']);
    return value is CosString ? value.bytes : Uint8List(0);
  }

  /// Checks the signature against the document bytes: range coverage,
  /// digest, and the cryptographic signature against the embedded
  /// certificate.
  ///
  /// With a [trustStore], the signer's certificate chain is also built
  /// and verified up to one of the store's anchors (signatures up the
  /// chain, issuer matching, validity windows at the signing time) - see
  /// [PdfSignatureValidation.chainTrusted]. Without one,
  /// [PdfSignatureValidation.chainTrusted] stays null unless revocation
  /// makes the signer untrusted.
  ///
  /// Revocation is checked offline against the document's /DSS only
  /// ([PdfSignatureValidation.revocation]); [validateOnline] adds live
  /// OCSP/CRL lookups.
  ///
  /// The expensive part - hashing the covered bytes and verifying the
  /// signature ([cryptoCore]) - is remembered per signature for as long as
  /// the document's byte buffer is unchanged, so validating again at the same
  /// revision (a trust store arriving, the panel rebuilding) hashes nothing.
  /// [cores] lets a caller that can prove the covered bytes unchanged across
  /// revisions supply that part from its own cache; it is consulted for this
  /// signature and for every document timestamp the PAdES level depends on.
  PdfSignatureValidation validate({
    PdfTrustStore? trustStore,
    PdfSignatureCoreResolver? cores,
  }) {
    final base = _validateWithChain(trustStore, cores);
    return base._withRevocation(
        _revocationVerdicts(base, trustStore, live: null, now: null),
        liveChecked: false);
  }

  /// [validate] plus live revocation checking: the signer certificate and
  /// every intermediate of its chain are checked through [revocationClient]
  /// (typically [pdfOnlineRevocationClient] - OCSP via the certificate's
  /// Authority Information Access first, then its CRL distribution points),
  /// alongside whatever the document's /DSS embeds. The library still makes
  /// no network calls of its own; the client is the host's transport.
  ///
  /// Live material must verify (issuer / authorized-responder signature,
  /// CertID match) and be current at [now] (default: the clock). Each
  /// certificate's verdict and its source (embedded or live) is reported in
  /// [PdfSignatureValidation.revocation].
  ///
  /// **Policy.** A revoked certificate makes the chain untrusted
  /// ([PdfSignatureValidation.chainTrusted] false) unless the signature
  /// carries a verified RFC 3161 timestamp dated *before* the revocation
  /// time - then the signature provably predates the revocation and stays
  /// valid (reported with [PdfCertificateRevocation.affectsSignature] false).
  /// The claimed signing time (/M or the signingTime attribute) is not
  /// trusted for this, since the signer controls it. A certificate whose
  /// status can't be established (no responder, network failure, stale or
  /// unverifiable answer) is reported as [PdfRevocationStatus.unknown] and
  /// does not by itself make the chain untrusted (soft-fail, as desktop
  /// viewers do). A failing [revocationClient] is caught and reported the
  /// same way.
  ///
  /// [cores] is as for [validate].
  Future<PdfSignatureValidation> validateOnline({
    PdfTrustStore? trustStore,
    required PdfRevocationClient revocationClient,
    DateTime? now,
    PdfSignatureCoreResolver? cores,
  }) async {
    final base = _validateWithChain(trustStore, cores);
    final chain = _revocationChain(base, trustStore);
    PdfRevocationMaterial? material;
    String? failure;
    if (chain.length > 1) {
      try {
        material = await revocationClient(chain);
      } on Object catch (e) {
        failure = 'live revocation check failed: $e';
      }
    }
    final live = _ParsedMaterial.of(material ?? const PdfRevocationMaterial());
    final verdicts = _revocationVerdicts(base, trustStore,
        live: live, now: (now ?? DateTime.now()).toUtc(), chain: chain);
    return base._withRevocation(
      failure == null
          ? verdicts
          : [
              for (final v in verdicts)
                v.status == PdfRevocationStatus.none
                    ? PdfCertificateRevocation(
                        certificate: v.certificate,
                        issuer: v.issuer,
                        status: PdfRevocationStatus.unknown,
                        problems: [...v.problems, failure],
                      )
                    : v,
            ],
      liveChecked: true,
    );
  }

  PdfSignatureValidation _validateWithChain(
      PdfTrustStore? trustStore, PdfSignatureCoreResolver? cores) {
    var result = _validateSignature(cores);
    if (trustStore != null) {
      result = result._withChain(trustStore, result.signedAt ?? signingTime);
    }
    return result;
  }

  /// The certificate path revocation is checked along, leaf first: the
  /// trust chain when one was built to an anchor, otherwise the best path
  /// through the signature's own and the /DSS's certificates.
  List<X509Certificate> _revocationChain(
      PdfSignatureValidation base, PdfTrustStore? trustStore) {
    final leaf = base.signerCertificate;
    if (leaf == null) return const [];
    if (base.trustChain.length > 1) return base.trustChain;
    final dss = PdfDss.of(document);
    return verifyCertificateChain(
      leaf: leaf,
      intermediates: [
        ...base.certificates,
        ...?dss?.certificates,
        ...?trustStore?.anchors,
      ],
      trustAnchors: const [],
    ).chain;
  }

  List<PdfCertificateRevocation> _revocationVerdicts(
    PdfSignatureValidation base,
    PdfTrustStore? trustStore, {
    required _ParsedMaterial? live,
    required DateTime? now,
    List<X509Certificate>? chain,
  }) {
    final path = chain ?? _revocationChain(base, trustStore);
    if (path.isEmpty) return const [];
    final dss = PdfDss.of(document);
    final verdicts = <PdfCertificateRevocation>[];
    for (var i = 0; i < path.length; i++) {
      final cert = path[i];
      final issuer = i + 1 < path.length ? path[i + 1] : null;
      // A self-signed root (or a directly trusted anchor at the end of the
      // path) has no issuer to vouch for its status.
      if (issuer == null &&
          (_sameDer(cert.subjectDer, cert.issuerDer) || i > 0)) {
        break;
      }
      final embedded = checkCertificateRevocation(
        certificate: cert,
        issuer: issuer,
        ocspResponses: dss?.ocspResponses ?? const [],
        crls: dss?.crls ?? const [],
        source: PdfRevocationSource.embedded,
      );
      final fromLive = live == null
          ? null
          : checkCertificateRevocation(
              certificate: cert,
              issuer: issuer,
              ocspResponses: live.ocsps,
              crls: live.crls,
              source: PdfRevocationSource.live,
              freshAt: now,
            );
      verdicts.add(combineRevocation(embedded, fromLive));
    }
    final trustedTime = base.timestamp != null && base.timestamp!.valid
        ? base.timestamp!.time
        : null;
    return applyRevocationPolicy(verdicts, trustedTime);
  }

  /// Test-only diagnostics, not part of the stable API (like
  /// `PdfInterpreter.debugResolveOverprint`): the bytes fed to byte-range
  /// digests by validation in this isolate, so a test can prove a cached
  /// result was reused. Nothing reads it; reset it freely.
  static int debugHashedBytes = 0;

  /// [_validateSignature] results by signature dictionary, each valid for the
  /// byte buffer (object and length) it was computed on: one revision.
  /// [CosDocument.applyIncrementalUpdate] swaps in a new buffer and a reopen
  /// builds new dictionaries, so a later revision never hits. The buffer is
  /// held weakly: the COS layer keeps a dictionary alive across revisions,
  /// and it must not keep an outgrown buffer alive with it.
  static final Expando<
      (
        WeakReference<Uint8List>,
        int,
        _SignatureInputs,
        PdfSignatureValidation
      )> _revisionMemo = Expando('PdfSignature validation');

  /// The signature half of [validate] (no chain, no revocation verdicts):
  /// memoised per revision, except over a sparse buffer whose holes may
  /// still fill in.
  PdfSignatureValidation _validateSignature([PdfSignatureCoreResolver? cores]) {
    final cos = document.cos;
    final bytes = cos.bytes;
    if (cos.populatedRanges != null) return _validateSignatureUncached(cores);
    final memo = _revisionMemo[dict];
    if (memo != null &&
        identical(memo.$1.target, bytes) &&
        memo.$2 == bytes.length &&
        memo.$3.matches(this)) {
      return memo.$4;
    }
    final result = _validateSignatureUncached(cores);
    _revisionMemo[dict] =
        (WeakReference(bytes), bytes.length, _SignatureInputs.of(this), result);
    return result;
  }

  PdfSignatureValidation _validateSignatureUncached(
      PdfSignatureCoreResolver? cores) {
    final problems = <String>[];
    final (rangesSane, coversWholeDocument) = _checkRanges(problems);
    if (!rangesSane) {
      return PdfSignatureValidation._(false, false, false, null, const [],
          const [], List.unmodifiable(problems));
    }
    final core = _resolveCore(cores);
    problems.addAll(core.problems);
    // What a later revision can change sits on top of the core: coverage
    // (above), and for a CMS signature the PAdES level and the /DSS status.
    PdfPadesLevel? padesLevel;
    var embeddedRevocation = PdfRevocationStatus.none;
    if (core._cms) {
      padesLevel = _padesLevel(core, cores);
      embeddedRevocation = _embeddedRevocationStatus(
          core.signerCertificate, core.certificates, PdfDss.of(document));
    }
    return PdfSignatureValidation._(
      core.digestMatches,
      core.signatureValid,
      coversWholeDocument,
      core.signerCertificate,
      core.certificates,
      core.signedAt != null ? [core.signedAt!] : const [],
      List.unmodifiable(problems),
      padesLevel: padesLevel,
      timestamp: core.timestamp,
      embeddedRevocation: embeddedRevocation,
    );
  }

  /// Whether /ByteRange describes a signable span of this revision (two
  /// ranges from offset 0 around a gap holding the /Contents hex string),
  /// and whether it reaches the end of the file. Adds the problems found to
  /// [problems], when given.
  (bool sane, bool coversWholeDocument) _checkRanges([List<String>? problems]) {
    final bytes = document.cos.bytes;
    final ranges = byteRange;
    var rangesSane = ranges.length == 4 &&
        ranges[0] == 0 &&
        ranges[1] >= 0 &&
        ranges[2] >= ranges[1] &&
        ranges[3] >= 0 &&
        ranges[2] + ranges[3] <= bytes.length;
    if (!rangesSane) {
      problems?.add('malformed /ByteRange');
    } else {
      // the gap must hold exactly the /Contents hex string
      final gapStart = ranges[0] + ranges[1];
      final gapEnd = ranges[2];
      if (gapStart >= gapEnd ||
          bytes[gapStart] != 0x3C /* < */ ||
          bytes[gapEnd - 1] != 0x3E /* > */) {
        problems?.add('/ByteRange gap does not hold the signature');
        rangesSane = false;
      }
    }
    final coversWholeDocument =
        rangesSane && ranges[2] + ranges[3] == bytes.length;
    if (rangesSane && !coversWholeDocument) {
      problems?.add('the document was updated after this signature; only '
          'the signed revision is covered');
    }
    return (rangesSane, coversWholeDocument);
  }

  /// Whether /ByteRange describes a span of this revision that can be hashed:
  /// two ranges from offset 0, inside the file, around a gap holding the
  /// /Contents hex string. When false [cryptoCore] is null and [validate]
  /// hashes nothing, reporting why. A signature copied in with another
  /// file's pages keeps that file's offsets, so it is typically false.
  bool get hasSignableByteRange => _checkRanges().$1;

  /// This signature's [PdfSignatureCryptoCore]: the covered bytes hashed and
  /// the signature (CMS, PKCS#1 or RFC 3161 token) verified - the costly,
  /// revision-independent part of [validate]. Null when /ByteRange does not
  /// describe a signable span of this revision ([hasSignableByteRange];
  /// [validate] reports why).
  PdfSignatureCryptoCore? cryptoCore() =>
      hasSignableByteRange ? _computeCore() : null;

  PdfSignatureCryptoCore _resolveCore(PdfSignatureCoreResolver? cores) {
    if (cores == null) return _computeCore();
    final core = cores(this, _computeCore);
    // A resolver answers from its own cache; never take a core computed for
    // other signature dictionary values than this revision's.
    return core.describes(this) ? core : _computeCore();
  }

  /// Computes the core; the caller has checked the ranges.
  PdfSignatureCryptoCore _computeCore() {
    final bytes = document.cos.bytes;
    final ranges = byteRange;
    final inputs = _SignatureInputs.of(this);
    debugHashedBytes += ranges[1] + ranges[3];
    final data = Uint8List(ranges[1] + ranges[3]);
    data.setRange(0, ranges[1], bytes);
    data.setRange(ranges[1], data.length,
        Uint8List.sublistView(bytes, ranges[2], ranges[2] + ranges[3]));

    switch (inputs.subFilter) {
      case 'adbe.x509.rsa_sha1':
        return _validateX509RsaSha1(data, inputs);
      case 'adbe.pkcs7.sha1':
        return _validateCms(data, inputs, digestOfRanges: true);
      case 'ETSI.RFC3161':
        return _validateDocTimeStamp(data, inputs);
      default: // adbe.pkcs7.detached, ETSI.CAdES.detached
        return _validateCms(data, inputs);
    }
  }

  /// A document timestamp: /Contents is a bare RFC 3161 token over the byte
  /// ranges. Validity = the token's imprint matches the signed bytes and the
  /// TSA's CMS signature verifies.
  PdfSignatureCryptoCore _validateDocTimeStamp(
      Uint8List data, _SignatureInputs inputs) {
    final problems = <String>[];
    final info = _validateTimestamp(inputs.contents, data);
    if (info.problem != null) problems.add(info.problem!);
    if (!info.valid && info.problem == null) {
      problems.add('document timestamp does not verify');
    }
    return PdfSignatureCryptoCore._(
      inputs,
      digestMatches: info.valid,
      signatureValid: info.valid,
      signerCertificate: info.tsaCertificate,
      certificates:
          info.tsaCertificate != null ? [info.tsaCertificate!] : const [],
      signedAt: info.time,
      problems: problems,
      timestamp: info,
    );
  }

  PdfTimestampInfo _validateTimestamp(Uint8List tokenDer, Uint8List stamped) {
    try {
      final token = TimeStampToken.parse(tokenDer);
      final result = verifyTimeStampToken(token, stamped);
      return PdfTimestampInfo(
        time: result.genTime,
        valid: result.valid,
        tsaCertificate: token.signerCertificate,
        problem: result.problem,
      );
    } on Object catch (e) {
      return PdfTimestampInfo(
          time: null, valid: false, problem: 'cannot parse timestamp: $e');
    }
  }

  /// Determines the PAdES baseline level of a CMS signature from its CAdES
  /// markers, its signature timestamp, and this revision's /DSS and document
  /// timestamps.
  PdfPadesLevel? _padesLevel(
      PdfSignatureCryptoCore core, PdfSignatureCoreResolver? cores) {
    if (subFilter != 'ETSI.CAdES.detached' || !core._hasSigningCertificate) {
      return null;
    }
    var level = PdfPadesLevel.bB;
    final timestamp = core.timestamp;
    if (timestamp != null && timestamp.valid) {
      level = PdfPadesLevel.bT;
      final dss = PdfDss.of(document);
      if (dss != null && !dss.isEmpty) {
        level = PdfPadesLevel.bLT;
        if (_documentHasValidTimeStamp(cores)) level = PdfPadesLevel.bLTA;
      }
    }
    return level;
  }

  /// Whether a document timestamp of this revision verifies. Only its
  /// signature half matters (the chain and revocation verdicts of a full
  /// [validate] pass `signatureValid` through unchanged), and that half is
  /// memoised, so the timestamp's own row reuses it.
  bool _documentHasValidTimeStamp(PdfSignatureCoreResolver? cores) {
    for (final sig in PdfSignature.of(document)) {
      if (sig.isDocumentTimeStamp &&
          sig._validateSignature(cores).signatureValid) {
        return true;
      }
    }
    return false;
  }

  PdfSignatureCryptoCore _validateCms(Uint8List data, _SignatureInputs inputs,
      {bool digestOfRanges = false}) {
    final problems = <String>[];
    final CmsSignedData cms;
    try {
      cms = CmsSignedData.parse(inputs.contents);
    } on Object catch (e) {
      problems.add('cannot parse CMS signature: $e');
      return PdfSignatureCryptoCore._(inputs, problems: problems);
    }
    if (cms.signerInfos.isEmpty) {
      problems.add('CMS has no signer');
      return PdfSignatureCryptoCore._(inputs,
          certificates: cms.certificates, problems: problems);
    }
    final signer = cms.signerInfos.first;

    List<int> content = data;
    var sha1Matches = true;
    if (digestOfRanges) {
      // adbe.pkcs7.sha1: the CMS encapsulates SHA-1 of the byte ranges
      final eContent = cms.eContent;
      if (eContent == null) {
        problems.add('adbe.pkcs7.sha1 signature has no encapsulated digest');
        return PdfSignatureCryptoCore._(inputs,
            signerCertificate: cms.certificateFor(signer),
            certificates: cms.certificates,
            problems: problems);
      }
      final rangesDigest = crypto.sha1.convert(data).bytes;
      sha1Matches = _equal(rangesDigest, eContent);
      if (!sha1Matches) problems.add('document digest mismatch');
      content = eContent;
    }

    final verification = cmsVerify(cms, signer, content);
    if (verification.problem != null) problems.add(verification.problem!);
    final digestMatches = verification.digestMatches && sha1Matches;
    if (!verification.digestMatches) problems.add('signed digest mismatch');
    if (!verification.signatureValid && verification.problem == null) {
      problems.add('cryptographic signature is invalid');
    }

    // PAdES extras: the signature timestamp. The baseline level and the
    // status the embedded /DSS revocation material reports for the signer
    // depend on the revision, so validation derives them on top.
    final timestamp = signer.signatureTimeStampToken != null
        ? _validateTimestamp(
            Uint8List.fromList(signer.signatureTimeStampToken!),
            Uint8List.fromList(signer.signature))
        : null;
    if (timestamp != null && !timestamp.valid) {
      problems.add('embedded signature timestamp does not verify'
          '${timestamp.problem != null ? ': ${timestamp.problem}' : ''}');
    }

    return PdfSignatureCryptoCore._(
      inputs,
      digestMatches: digestMatches,
      signatureValid: verification.signatureValid,
      signerCertificate: cms.certificateFor(signer),
      certificates: cms.certificates,
      signedAt: signer.signingTime,
      problems: problems,
      timestamp: timestamp,
      hasSigningCertificate: signer.hasSigningCertificate,
      cms: true,
    );
  }

  /// Resolves the signer certificate's revocation status from the /DSS the
  /// document carries (offline LTV), or [PdfRevocationStatus.none] when no
  /// material covers it.
  PdfRevocationStatus _embeddedRevocationStatus(X509Certificate? signerCert,
      List<X509Certificate> cmsCerts, PdfDss? dss) {
    if (signerCert == null || dss == null) return PdfRevocationStatus.none;
    X509Certificate? issuer;
    for (final c in [...cmsCerts, ...dss.certificates]) {
      if (_sameDer(c.subjectDer, signerCert.issuerDer) &&
          signerCert.isSignedBy(c)) {
        issuer = c;
        break;
      }
    }
    final verdict = checkCertificateRevocation(
      certificate: signerCert,
      issuer: issuer,
      ocspResponses: dss.ocspResponses,
      crls: dss.crls,
      source: PdfRevocationSource.embedded,
    );
    if (verdict.status == PdfRevocationStatus.none && !dss.isEmpty) {
      return PdfRevocationStatus.unknown;
    }
    return verdict.status;
  }

  static bool _sameDer(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  PdfSignatureCryptoCore _validateX509RsaSha1(
      Uint8List data, _SignatureInputs inputs) {
    final problems = <String>[];
    final certValue = document.cos.resolve(dict['Cert']);
    final certBytes = switch (certValue) {
      CosString s => s.bytes,
      CosArray a when a.length > 0 =>
        (document.cos.resolve(a[0]) as CosString).bytes,
      _ => null,
    };
    if (certBytes == null) {
      problems.add('adbe.x509.rsa_sha1 signature has no /Cert');
      return PdfSignatureCryptoCore._(inputs, problems: problems);
    }
    final cert = X509Certificate.parse(Uint8List.fromList(certBytes));
    final key = cert.publicKey;
    if (key is! RsaPublicKey) {
      problems.add('unsupported key algorithm ${cert.publicKeyAlgorithmOid}');
      return PdfSignatureCryptoCore._(inputs,
          signerCertificate: cert, certificates: [cert], problems: problems);
    }
    // /Contents is a DER OCTET STRING wrapping the PKCS#1 signature
    var signature = inputs.contents;
    try {
      final wrapped = DerObject.parsePrefix(signature);
      if (wrapped.tag == DerTag.octetString) signature = wrapped.content;
    } on Object {
      // raw signature bytes
    }
    final valid = rsaVerify(
        key, DigestOid.sha1, crypto.sha1.convert(data).bytes, signature);
    if (!valid) problems.add('cryptographic signature is invalid');
    return PdfSignatureCryptoCore._(
      inputs,
      digestMatches: valid,
      signatureValid: valid,
      signerCertificate: cert,
      certificates: [cert],
      problems: problems,
    );
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The part of a signature's validation that depends only on the bytes it
/// covers and on its signature dictionary's /ByteRange, /Contents, /SubFilter
/// and /Cert: the document digest, the cryptographic signature, the embedded
/// certificates and signing time, and the signature timestamp. Hashing the
/// covered bytes makes it the expensive part.
///
/// [PdfSignature.validate] derives everything else per revision on top of it
/// - whether the signature still covers the whole file, the PAdES level (the
/// /DSS and document timestamps) and the embedded revocation status. A cache
/// of cores can therefore outlive a revision, as long as whoever keeps it
/// knows the covered bytes did not change (they cannot while every revision
/// appends to the same buffer). It is plain data, so it can be computed on
/// another isolate and sent back.
class PdfSignatureCryptoCore {
  PdfSignatureCryptoCore._(
    this._inputs, {
    this.digestMatches = false,
    this.signatureValid = false,
    this.signerCertificate,
    List<X509Certificate> certificates = const [],
    this.signedAt,
    required List<String> problems,
    this.timestamp,
    bool hasSigningCertificate = false,
    bool cms = false,
  })  : certificates = List.unmodifiable(certificates),
        problems = List.unmodifiable(problems),
        _hasSigningCertificate = hasSigningCertificate,
        _cms = cms;

  final _SignatureInputs _inputs;

  /// The [start, length, start, length] byte ranges it was computed over.
  List<int> get byteRange => _inputs.byteRange;

  /// The offset just past the last covered byte. Rewriting any byte before it
  /// (an undo followed by a new edit, a whole-file rewrite) makes this core
  /// stale.
  int get coveredEnd => byteRange[2] + byteRange[3];

  /// See [PdfSignatureValidation.digestMatches].
  final bool digestMatches;

  /// See [PdfSignatureValidation.signatureValid].
  final bool signatureValid;

  /// See [PdfSignatureValidation.signerCertificate].
  final X509Certificate? signerCertificate;

  /// See [PdfSignatureValidation.certificates].
  final List<X509Certificate> certificates;

  /// See [PdfSignatureValidation.signedAt].
  final DateTime? signedAt;

  /// The problems found by these checks, in the order [PdfSignature.validate]
  /// reports them (after any /ByteRange coverage problem).
  final List<String> problems;

  /// The signature timestamp, or a document timestamp's own token.
  final PdfTimestampInfo? timestamp;

  final bool _hasSigningCertificate;

  /// A CMS signature with a signer: validation adds its PAdES level and its
  /// embedded revocation status, which depend on the revision.
  final bool _cms;

  /// Whether this core was computed for [signature]'s current /ByteRange,
  /// /Contents, /SubFilter and /Cert. It cannot tell whether the covered
  /// bytes changed; that is the caching caller's guarantee.
  bool describes(PdfSignature signature) => _inputs.matches(signature);
}

/// Supplies [signature]'s [PdfSignatureCryptoCore], from a cache or by calling
/// [compute] (see [PdfSignature.validate]). A returned core that does not
/// [PdfSignatureCryptoCore.describes] the signature is ignored and recomputed.
typedef PdfSignatureCoreResolver = PdfSignatureCryptoCore Function(
    PdfSignature signature, PdfSignatureCryptoCore Function() compute);

/// The signature dictionary values a [PdfSignatureCryptoCore] depends on
/// besides the covered bytes, copied: the core never keeps the file buffer
/// alive through a view, and an in-place edit of the dictionary is noticed.
class _SignatureInputs {
  _SignatureInputs._(this.byteRange, this.contents, this.subFilter, this.cert);

  factory _SignatureInputs.of(PdfSignature signature) {
    final cert = _certString(signature);
    return _SignatureInputs._(
      List.unmodifiable(signature.byteRange),
      Uint8List.fromList(signature.contents),
      signature.subFilter,
      cert == null ? null : Uint8List.fromList(cert),
    );
  }

  final List<int> byteRange;
  final Uint8List contents;
  final String? subFilter;
  final Uint8List? cert;

  bool matches(PdfSignature signature) {
    if (subFilter != signature.subFilter) return false;
    if (!PdfSignature._equal(byteRange, signature.byteRange)) return false;
    if (!PdfSignature._equal(contents, signature.contents)) return false;
    final current = _certString(signature);
    return cert == null
        ? current == null
        : current != null && PdfSignature._equal(cert!, current);
  }

  /// /Cert (adbe.x509.rsa_sha1), or its first entry when it is an array.
  static Uint8List? _certString(PdfSignature signature) {
    final cos = signature.document.cos;
    CosObject? value = cos.resolve(signature.dict['Cert']);
    if (value is CosArray) {
      value = value.length > 0 ? cos.resolve(value[0]) : null;
    }
    return value is CosString ? value.bytes : null;
  }
}

/// Trust anchors for certificate-chain validation: the root (and any
/// directly trusted) certificates the verifier chooses to rely on. The
/// library ships no built-in roots - supply your platform's or your
/// organization's.
class PdfTrustStore {
  PdfTrustStore();

  /// A trust store seeded with [certificates] (DER, e.g. an org CA built with
  /// `PdfSigningIdentity.generateCa`) so the identities it vouches for
  /// validate against this store.
  factory PdfTrustStore.trusting(Iterable<Uint8List> certificates) {
    final store = PdfTrustStore();
    for (final der in certificates) {
      store.addDer(der);
    }
    return store;
  }

  final List<X509Certificate> anchors = [];

  /// Anchor DER (base64) -> the list it came from, when the adder said.
  final Map<String, String> _sources = {};

  /// Adds [certificate] as an anchor. [source] names the list it came from
  /// (e.g. "EU Trusted List"), reported back by [sourceOf].
  void addCertificate(X509Certificate certificate, {String? source}) {
    anchors.add(certificate);
    if (source != null) _sources[_key(certificate)] ??= source;
  }

  void addDer(Uint8List der, {String? source}) =>
      addCertificate(X509Certificate.parse(der), source: source);

  /// The trust list [anchor] was added from, or null when none was named.
  String? sourceOf(X509Certificate anchor) => _sources[_key(anchor)];

  static String _key(X509Certificate c) => base64.encode(c.der);

  /// Adds every CERTIFICATE block in [pem].
  void addPem(String pem) {
    final blocks =
        RegExp(r'-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----')
            .allMatches(pem);
    if (blocks.isEmpty) {
      throw ArgumentError('no CERTIFICATE blocks in PEM input');
    }
    for (final block in blocks) {
      addDer(pemBytes(block.group(0)!));
    }
  }
}

/// Outcome of validating one signature.
class PdfSignatureValidation {
  PdfSignatureValidation._(
    this.digestMatches,
    this.signatureValid,
    this.coversWholeDocument,
    this.signerCertificate,
    this.certificates,
    List<DateTime> signingTimes,
    this.problems, {
    this.chainTrusted,
    this.trustChain = const [],
    this.chainProblems = const [],
    this.padesLevel,
    this.timestamp,
    this.embeddedRevocation = PdfRevocationStatus.none,
    this.revocation = const [],
    this.liveRevocationChecked = false,
  }) : signedAt = signingTimes.isEmpty ? null : signingTimes.first;

  PdfSignatureValidation _withRevocation(
      List<PdfCertificateRevocation> verdicts,
      {required bool liveChecked}) {
    final revokedProblems = [
      for (final v in verdicts)
        if (v.affectsSignature)
          'certificate "${v.certificate.subjectCommonName ?? 'serial '
                  '${v.certificate.serial}'}" was revoked'
              '${v.revocationTime != null ? ' on '
                  '${v.revocationTime!.toIso8601String()}' : ''}',
    ];
    return PdfSignatureValidation._(
      digestMatches,
      signatureValid,
      coversWholeDocument,
      signerCertificate,
      certificates,
      signedAt != null ? [signedAt!] : const [],
      problems,
      chainTrusted: revokedProblems.isNotEmpty ? false : chainTrusted,
      trustChain: trustChain,
      chainProblems: [...chainProblems, ...revokedProblems],
      padesLevel: padesLevel,
      timestamp: timestamp,
      embeddedRevocation: embeddedRevocation,
      revocation: verdicts,
      liveRevocationChecked: liveChecked,
    );
  }

  PdfSignatureValidation _withChain(PdfTrustStore store, DateTime? at) {
    bool? trusted;
    var chain = const <X509Certificate>[];
    var chainProblems = const <String>[];
    final leaf = signerCertificate;
    if (leaf == null) {
      trusted = false;
      chainProblems = const ['no signer certificate to build a chain from'];
    } else {
      final result = verifyCertificateChain(
        leaf: leaf,
        intermediates: certificates,
        trustAnchors: store.anchors,
        at: at,
      );
      trusted = result.trusted;
      chain = result.chain;
      chainProblems = result.problems;
    }
    return PdfSignatureValidation._(
      digestMatches,
      signatureValid,
      coversWholeDocument,
      signerCertificate,
      certificates,
      signedAt != null ? [signedAt!] : const [],
      problems,
      chainTrusted: trusted,
      trustChain: chain,
      chainProblems: chainProblems,
      padesLevel: padesLevel,
      timestamp: timestamp,
      embeddedRevocation: embeddedRevocation,
    );
  }

  /// The signed bytes still hash to the digest embedded in the signature.
  final bool digestMatches;

  /// The signature verifies against the signer certificate's public key.
  final bool signatureValid;

  /// The byte range spans the entire file. False means the document
  /// received incremental updates after signing - common and legitimate
  /// (later signatures, form fills), but only the signed revision is
  /// attested.
  final bool coversWholeDocument;

  /// The certificate the signature verifies against. Trust in this
  /// certificate is established only when a [PdfTrustStore] is passed to
  /// [PdfSignature.validate] - see [chainTrusted].
  final X509Certificate? signerCertificate;

  /// Every certificate shipped with the signature.
  final List<X509Certificate> certificates;

  /// The cryptographically signed signing time, when present.
  final DateTime? signedAt;

  final List<String> problems;

  /// Whether the signer chains to a supplied trust anchor: null when
  /// validation ran without a trust store, otherwise the verdict of
  /// signature checks up the chain, issuer matching, and validity
  /// windows. A certificate revoked before the signature's trusted time
  /// (see [PdfSignature.validateOnline]) forces it false, trust store or
  /// not.
  final bool? chainTrusted;

  /// The certificate path that was built, leaf first.
  final List<X509Certificate> trustChain;

  /// Why the chain is untrusted, when it is.
  final List<String> chainProblems;

  /// The PAdES baseline level this signature reaches (B-B…B-LTA), or null
  /// when it is not a PAdES (ETSI.CAdES.detached + signing-certificate-v2)
  /// signature.
  final PdfPadesLevel? padesLevel;

  /// The signature timestamp (PAdES B-T and up), or - for a document
  /// timestamp signature - the timestamp itself. Null when none is present.
  final PdfTimestampInfo? timestamp;

  /// What the document's embedded /DSS revocation material reports for the
  /// signer certificate, checked offline. [PdfRevocationStatus.none] when no
  /// material covers it.
  final PdfRevocationStatus embeddedRevocation;

  /// The revocation verdict for each certificate of the signer's chain that
  /// has an issuer (leaf first; the root is not checked), from the /DSS and -
  /// after [PdfSignature.validateOnline] - live OCSP/CRL.
  final List<PdfCertificateRevocation> revocation;

  /// Whether a live revocation check ran ([PdfSignature.validateOnline]).
  final bool liveRevocationChecked;

  /// The chain-wide revocation verdict: [PdfRevocationStatus.revoked] when
  /// any certificate is revoked, [PdfRevocationStatus.good] when every
  /// checked certificate is good, [PdfRevocationStatus.none] when nothing
  /// was checked or found, and [PdfRevocationStatus.unknown] otherwise.
  PdfRevocationStatus get revocationStatus {
    if (revocation.isEmpty) return PdfRevocationStatus.none;
    if (revocation.any((r) => r.status == PdfRevocationStatus.revoked)) {
      return PdfRevocationStatus.revoked;
    }
    if (revocation.every((r) => r.status == PdfRevocationStatus.good)) {
      return PdfRevocationStatus.good;
    }
    if (revocation.every((r) => r.status == PdfRevocationStatus.none)) {
      return PdfRevocationStatus.none;
    }
    return PdfRevocationStatus.unknown;
  }

  /// True when a revoked certificate invalidates this signature under the
  /// revocation policy (revoked, and not provably after a trusted
  /// timestamp).
  bool get revokedBeforeSigning => revocation.any((r) => r.affectsSignature);

  /// True when the signer certificate is self-signed (no CA vouches for it).
  bool get isSelfSigned {
    final cert = signerCertificate;
    if (cert == null || cert.subjectDer.length != cert.issuerDer.length) {
      return false;
    }
    for (var i = 0; i < cert.subjectDer.length; i++) {
      if (cert.subjectDer[i] != cert.issuerDer[i]) return false;
    }
    return true;
  }

  /// The document bytes the signature covers are exactly what was signed.
  bool get intact => digestMatches && signatureValid;

  /// The signature carries everything needed to validate it offline forever:
  /// a valid timestamp and embedded revocation material (PAdES B-LT or B-LTA).
  bool get isLtvEnabled =>
      padesLevel != null && padesLevel!.index >= PdfPadesLevel.bLT.index;
}

/// A validated RFC 3161 timestamp embedded in a signature or document
/// timestamp.
class PdfTimestampInfo {
  PdfTimestampInfo({
    required this.time,
    required this.valid,
    this.tsaCertificate,
    this.problem,
  });

  /// The trusted time the TSA attests (genTime), when the token parsed.
  final DateTime? time;

  /// The token's imprint matches the stamped bytes and the TSA's signature
  /// verifies. Trust in the TSA certificate itself is a trust-store matter.
  final bool valid;

  /// The TSA's signing certificate, when embedded.
  final X509Certificate? tsaCertificate;

  final String? problem;
}

/// The revocation verdict for a certificate.
enum PdfRevocationStatus {
  /// No OCSP/CRL covering the certificate was found.
  none,

  /// Material was found (or a lookup attempted) but is inconclusive: issuer
  /// unavailable, unverifiable or stale material, a responder that does not
  /// know the certificate, or a failed network lookup.
  unknown,

  /// An OCSP "good" response or a CRL that does not list the serial.
  good,

  /// The certificate is listed revoked.
  revoked,
}

/// The /DSS Document Security Store (PDF 2.0 §12.8.4.3): the certificates,
/// OCSP responses, and CRLs a document carries for long-term validation.
class PdfDss {
  PdfDss(this.certificates, this.ocspResponses, this.crls);

  final List<X509Certificate> certificates;
  final List<OcspResponse> ocspResponses;
  final List<CertificateRevocationList> crls;

  bool get isEmpty =>
      certificates.isEmpty && ocspResponses.isEmpty && crls.isEmpty;

  /// Reads the catalog's /DSS, or null when the document has none.
  static PdfDss? of(PdfDocument document) {
    final dss = document.cos.resolve(document.catalog['DSS']);
    if (dss is! CosDictionary) return null;

    List<Uint8List> blobs(String key) {
      final array = document.cos.resolve(dss[key]);
      if (array is! CosArray) return const [];
      final out = <Uint8List>[];
      for (final item in array.items) {
        final stream = document.cos.resolve(item);
        if (stream is CosStream) {
          try {
            out.add(document.cos.decodeStreamData(stream));
          } on Object {
            // skip an undecodable entry rather than fail the whole store
          }
        }
      }
      return out;
    }

    List<T> parsed<T>(String key, T Function(Uint8List) parse) {
      final out = <T>[];
      for (final der in blobs(key)) {
        try {
          out.add(parse(der));
        } on Object {
          // skip a malformed entry
        }
      }
      return out;
    }

    return PdfDss(
      parsed('Certs', X509Certificate.parse),
      parsed('OCSPs', OcspResponse.parse),
      parsed('CRLs', CertificateRevocationList.parse),
    );
  }
}

/// Live revocation material, parsed once per [PdfSignature.validateOnline].
class _ParsedMaterial {
  _ParsedMaterial(this.ocsps, this.crls);

  factory _ParsedMaterial.of(PdfRevocationMaterial material) {
    final ocsps = <OcspResponse>[];
    for (final der in material.ocspResponses) {
      try {
        ocsps.add(OcspResponse.parse(der));
      } on Object {
        // a malformed response is simply not evidence
      }
    }
    final crls = <CertificateRevocationList>[];
    for (final der in material.crls) {
      try {
        crls.add(CertificateRevocationList.parse(der));
      } on Object {
        // likewise
      }
    }
    return _ParsedMaterial(ocsps, crls);
  }

  final List<OcspResponse> ocsps;
  final List<CertificateRevocationList> crls;
}

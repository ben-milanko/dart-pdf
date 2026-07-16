import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'form.dart';
import 'pades.dart';

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
          if (document.cos.resolve(field.dict['V'])
              case final CosDictionary v)
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
    var time = DateTime.utc(part(1), part(2, 1), part(3, 1), part(4),
        part(5), part(6));
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
  /// chain, issuer matching, validity windows at the signing time;
  /// revocation is not checked) - see [PdfSignatureValidation.chainTrusted].
  /// Without one, [PdfSignatureValidation.chainTrusted] stays null.
  PdfSignatureValidation validate({PdfTrustStore? trustStore}) {
    var result = _validateSignature();
    if (trustStore != null) {
      result = result._withChain(trustStore, result.signedAt ?? signingTime);
    }
    return result;
  }

  PdfSignatureValidation _validateSignature() {
    final bytes = document.cos.bytes;
    final problems = <String>[];
    final ranges = byteRange;

    var rangesSane = ranges.length == 4 &&
        ranges[0] == 0 &&
        ranges[1] >= 0 &&
        ranges[2] >= ranges[1] &&
        ranges[3] >= 0 &&
        ranges[2] + ranges[3] <= bytes.length;
    if (!rangesSane) {
      problems.add('malformed /ByteRange');
    } else {
      // the gap must hold exactly the /Contents hex string
      final gapStart = ranges[0] + ranges[1];
      final gapEnd = ranges[2];
      if (gapStart >= gapEnd ||
          bytes[gapStart] != 0x3C /* < */ ||
          bytes[gapEnd - 1] != 0x3E /* > */) {
        problems.add('/ByteRange gap does not hold the signature');
        rangesSane = false;
      }
    }
    final coversWholeDocument = rangesSane &&
        ranges[2] + ranges[3] == bytes.length;
    if (rangesSane && !coversWholeDocument) {
      problems.add('the document was updated after this signature; only '
          'the signed revision is covered');
    }
    if (!rangesSane) {
      return PdfSignatureValidation._(
          false, false, false, null, const [], const [], problems);
    }

    final data = Uint8List(ranges[1] + ranges[3]);
    data.setRange(0, ranges[1], bytes);
    data.setRange(ranges[1], data.length,
        Uint8List.sublistView(bytes, ranges[2], ranges[2] + ranges[3]));

    switch (subFilter) {
      case 'adbe.x509.rsa_sha1':
        return _validateX509RsaSha1(data, coversWholeDocument, problems);
      case 'adbe.pkcs7.sha1':
        return _validateCms(data, coversWholeDocument, problems,
            digestOfRanges: true);
      case 'ETSI.RFC3161':
        return _validateDocTimeStamp(data, coversWholeDocument, problems);
      default: // adbe.pkcs7.detached, ETSI.CAdES.detached
        return _validateCms(data, coversWholeDocument, problems);
    }
  }

  /// A document timestamp: /Contents is a bare RFC 3161 token over the byte
  /// ranges. Validity = the token's imprint matches the signed bytes and the
  /// TSA's CMS signature verifies.
  PdfSignatureValidation _validateDocTimeStamp(
      Uint8List data, bool coversWholeDocument, List<String> problems) {
    final info = _validateTimestamp(contents, data);
    if (info.problem != null) problems.add(info.problem!);
    if (!info.valid && info.problem == null) {
      problems.add('document timestamp does not verify');
    }
    return PdfSignatureValidation._(
      info.valid,
      info.valid,
      coversWholeDocument,
      info.tsaCertificate,
      info.tsaCertificate != null ? [info.tsaCertificate!] : const [],
      info.time != null ? [info.time!] : const [],
      problems,
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
  /// markers, [timestamp], and the document's /DSS and document timestamp.
  PdfPadesLevel? _padesLevel(
      CmsSignerInfo signer, PdfTimestampInfo? timestamp) {
    if (subFilter != 'ETSI.CAdES.detached' || !signer.hasSigningCertificate) {
      return null;
    }
    var level = PdfPadesLevel.bB;
    if (timestamp != null && timestamp.valid) {
      level = PdfPadesLevel.bT;
      final dss = PdfDss.of(document);
      if (dss != null && !dss.isEmpty) {
        level = PdfPadesLevel.bLT;
        if (_documentHasValidTimeStamp()) level = PdfPadesLevel.bLTA;
      }
    }
    return level;
  }

  bool _documentHasValidTimeStamp() {
    for (final sig in PdfSignature.of(document)) {
      if (sig.isDocumentTimeStamp && sig.validate().signatureValid) {
        return true;
      }
    }
    return false;
  }

  PdfSignatureValidation _validateCms(
      Uint8List data, bool coversWholeDocument, List<String> problems,
      {bool digestOfRanges = false}) {
    final CmsSignedData cms;
    try {
      cms = CmsSignedData.parse(contents);
    } on Object catch (e) {
      problems.add('cannot parse CMS signature: $e');
      return PdfSignatureValidation._(false, false, coversWholeDocument,
          null, const [], const [], problems);
    }
    if (cms.signerInfos.isEmpty) {
      problems.add('CMS has no signer');
      return PdfSignatureValidation._(false, false, coversWholeDocument,
          null, cms.certificates, const [], problems);
    }
    final signer = cms.signerInfos.first;

    List<int> content = data;
    var sha1Matches = true;
    if (digestOfRanges) {
      // adbe.pkcs7.sha1: the CMS encapsulates SHA-1 of the byte ranges
      final eContent = cms.eContent;
      if (eContent == null) {
        problems.add('adbe.pkcs7.sha1 signature has no encapsulated digest');
        return PdfSignatureValidation._(false, false, coversWholeDocument,
            cms.certificateFor(signer), cms.certificates, const [], problems);
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

    // PAdES extras: the signature timestamp, the baseline level, and the
    // status the embedded /DSS revocation material reports for the signer.
    final timestamp = signer.signatureTimeStampToken != null
        ? _validateTimestamp(Uint8List.fromList(signer.signatureTimeStampToken!),
            Uint8List.fromList(signer.signature))
        : null;
    if (timestamp != null && !timestamp.valid) {
      problems.add('embedded signature timestamp does not verify'
          '${timestamp.problem != null ? ': ${timestamp.problem}' : ''}');
    }
    final padesLevel = _padesLevel(signer, timestamp);
    final dss = PdfDss.of(document);
    final revocation = _embeddedRevocationStatus(
        cms.certificateFor(signer), cms.certificates, dss);

    return PdfSignatureValidation._(
      digestMatches,
      verification.signatureValid,
      coversWholeDocument,
      cms.certificateFor(signer),
      cms.certificates,
      signer.signingTime != null ? [signer.signingTime!] : const [],
      problems,
      padesLevel: padesLevel,
      timestamp: timestamp,
      embeddedRevocation: revocation,
    );
  }

  /// Resolves the signer certificate's revocation status from the /DSS the
  /// document carries (offline LTV), or [PdfRevocationStatus.none] when no
  /// material covers it.
  PdfRevocationStatus _embeddedRevocationStatus(X509Certificate? signerCert,
      List<X509Certificate> cmsCerts, PdfDss? dss) {
    if (signerCert == null || dss == null) return PdfRevocationStatus.none;
    final pool = [...cmsCerts, ...dss.certificates];
    X509Certificate? issuer;
    for (final c in pool) {
      if (_sameDer(c.subjectDer, signerCert.issuerDer)) {
        issuer = c;
        break;
      }
    }
    for (final ocsp in dss.ocspResponses) {
      final single = ocsp.forSerial(signerCert.serial);
      if (single == null) continue;
      if (issuer != null && !ocsp.signatureValid(issuer)) continue;
      return switch (single.status) {
        OcspCertStatus.good => PdfRevocationStatus.good,
        OcspCertStatus.revoked => PdfRevocationStatus.revoked,
        OcspCertStatus.unknown => PdfRevocationStatus.unknown,
      };
    }
    for (final crl in dss.crls) {
      if (issuer != null) {
        if (!_sameDer(crl.issuerDer, issuer.subjectDer)) continue;
        if (!crl.signatureValid(issuer)) continue;
      }
      return crl.forSerial(signerCert.serial) != null
          ? PdfRevocationStatus.revoked
          : PdfRevocationStatus.good;
    }
    return dss.isEmpty
        ? PdfRevocationStatus.none
        : PdfRevocationStatus.unknown;
  }

  static bool _sameDer(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  PdfSignatureValidation _validateX509RsaSha1(
      Uint8List data, bool coversWholeDocument, List<String> problems) {
    final certValue = document.cos.resolve(dict['Cert']);
    final certBytes = switch (certValue) {
      CosString s => s.bytes,
      CosArray a when a.length > 0 =>
        (document.cos.resolve(a[0]) as CosString).bytes,
      _ => null,
    };
    if (certBytes == null) {
      problems.add('adbe.x509.rsa_sha1 signature has no /Cert');
      return PdfSignatureValidation._(false, false, coversWholeDocument,
          null, const [], const [], problems);
    }
    final cert = X509Certificate.parse(certBytes);
    final key = cert.publicKey;
    if (key is! RsaPublicKey) {
      problems.add('unsupported key algorithm ${cert.publicKeyAlgorithmOid}');
      return PdfSignatureValidation._(false, false, coversWholeDocument,
          cert, [cert], const [], problems);
    }
    // /Contents is a DER OCTET STRING wrapping the PKCS#1 signature
    var signature = contents;
    try {
      final wrapped = DerObject.parsePrefix(signature);
      if (wrapped.tag == DerTag.octetString) signature = wrapped.content;
    } on Object {
      // raw signature bytes
    }
    final valid = rsaVerify(
        key, DigestOid.sha1, crypto.sha1.convert(data).bytes, signature);
    if (!valid) problems.add('cryptographic signature is invalid');
    return PdfSignatureValidation._(
        valid, valid, coversWholeDocument, cert, [cert], const [], problems);
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Trust anchors for certificate-chain validation: the root (and any
/// directly trusted) certificates the verifier chooses to rely on. The
/// library ships no built-in roots - supply your platform's or your
/// organization's.
class PdfTrustStore {
  final List<X509Certificate> anchors = [];

  void addCertificate(X509Certificate certificate) =>
      anchors.add(certificate);

  void addDer(Uint8List der) => anchors.add(X509Certificate.parse(der));

  /// Adds every CERTIFICATE block in [pem].
  void addPem(String pem) {
    final blocks = RegExp(
            r'-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----')
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
  }) : signedAt = signingTimes.isEmpty ? null : signingTimes.first;

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
  /// windows (revocation is not checked).
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

/// The revocation verdict for a certificate, from embedded LTV material.
enum PdfRevocationStatus {
  /// No OCSP/CRL covering the certificate was found.
  none,

  /// Material was found but is inconclusive (e.g. issuer unavailable).
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

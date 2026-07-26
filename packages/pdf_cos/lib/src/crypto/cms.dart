/// CMS / PKCS#7 SignedData (RFC 5652) - the container inside a PDF
/// signature's /Contents - plus the X.509 reading it needs and
/// certificate-chain verification against caller-supplied trust anchors
/// ([verifyCertificateChain]; no revocation or policy processing).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';
import 'ecdsa.dart';
import 'rsa.dart';
import 'x509_builder.dart';

abstract final class _Oid {
  static const signedData = '1.2.840.113549.1.7.2';
  static const data = '1.2.840.113549.1.7.1';
  static const contentType = '1.2.840.113549.1.9.3';
  static const messageDigest = '1.2.840.113549.1.9.4';
  static const signingTime = '1.2.840.113549.1.9.5';
  static const rsaEncryption = '1.2.840.113549.1.1.1';
  static const rsassaPss = '1.2.840.113549.1.1.10';
  static const ecPublicKey = '1.2.840.10045.2.1';
  static const signingCertificate = '1.2.840.113549.1.9.16.2.12';
  static const signingCertificateV2 = '1.2.840.113549.1.9.16.2.47';
  static const signatureTimeStampToken = '1.2.840.113549.1.9.16.2.14';
}

/// Parses RSASSA-PSS-params (RFC 4055 §3.1) from an AlgorithmIdentifier's
/// parameters, returning the message/MGF hash and the explicit salt length
/// (null when absent - the verifier then recovers it from the signature).
/// Missing or partial parameters fall back to the ASN.1 defaults (SHA-1).
(crypto.Hash, int?) _pssParams(DerObject? params) {
  var hash = crypto.sha1;
  int? saltLength;
  if (params != null && params.tag == DerTag.sequence) {
    for (final field in params.children) {
      if (field.tag == DerTag.context(0)) {
        // hashAlgorithm [0] EXPLICIT AlgorithmIdentifier
        final h = _hashFor(field.children.first.children.first.asOid);
        if (h != null) hash = h;
      } else if (field.tag == DerTag.context(2)) {
        // saltLength [2] EXPLICIT INTEGER
        saltLength = field.children.first.asInteger.toInt();
      }
      // maskGenAlgorithm [1] is assumed MGF1 over the same hash, and
      // trailerField [3] is always 1 - neither needs reading here.
    }
  }
  return (hash, saltLength);
}

/// Maps a digest OID (or a combined signature OID) to its hash.
crypto.Hash? _hashFor(String oid) => switch (oid) {
      DigestOid.sha1 || '1.2.840.113549.1.1.5' || '1.2.840.10045.4.1' =>
        crypto.sha1,
      DigestOid.sha256 ||
      '1.2.840.113549.1.1.11' ||
      '1.2.840.10045.4.3.2' =>
        crypto.sha256,
      DigestOid.sha384 ||
      '1.2.840.113549.1.1.12' ||
      '1.2.840.10045.4.3.3' =>
        crypto.sha384,
      DigestOid.sha512 ||
      '1.2.840.113549.1.1.13' ||
      '1.2.840.10045.4.3.4' =>
        crypto.sha512,
      _ => null,
    };

String? _digestOidFor(crypto.Hash hash) => switch (hash) {
      crypto.sha1 => DigestOid.sha1,
      crypto.sha256 => DigestOid.sha256,
      crypto.sha384 => DigestOid.sha384,
      crypto.sha512 => DigestOid.sha512,
      _ => null,
    };

class X509Certificate {
  X509Certificate._(this.der);

  factory X509Certificate.parse(Uint8List der) {
    final cert = X509Certificate._(der);
    final top = DerObject.parse(der).children;
    cert.tbsDer = top[0].encoded;
    cert.signatureAlgorithmOid = top[1].children[0].asOid;
    if (top[1].children.length > 1) {
      cert.signatureAlgorithmParams = top[1].children[1];
    }
    cert.signatureValue = top[2].asBitString;
    final tbs = top[0].children;
    var i = 0;
    if (tbs[0].tag == DerTag.context(0)) i = 1; // explicit version
    cert.serial = tbs[i].asInteger;
    cert.issuerDer = tbs[i + 2].encoded;
    final validity = tbs[i + 3].children;
    cert.notBefore = validity[0].asTime;
    cert.notAfter = validity[1].asTime;
    cert.subjectDer = tbs[i + 4].encoded;
    final spki = tbs[i + 5].children;
    cert.subjectPublicKeyInfoDer = tbs[i + 5].encoded;
    final algorithm = spki[0].children;
    cert.publicKeyAlgorithmOid = algorithm[0].asOid;
    final keyBits = spki[1].asBitString;
    cert.subjectPublicKeyBytes = keyBits;
    switch (cert.publicKeyAlgorithmOid) {
      case _Oid.rsaEncryption:
        cert.publicKey = RsaPublicKey.fromPkcs1(keyBits);
      case _Oid.ecPublicKey when algorithm.length > 1:
        final curve = EcCurve.byOid(algorithm[1].asOid);
        if (curve != null) {
          cert.publicKey = EcPublicKey.fromPoint(curve, keyBits);
        }
      default:
        cert.publicKey = null;
    }
    // extensions [3] EXPLICIT, when present (X.509 v3)
    for (var j = i + 6; j < tbs.length; j++) {
      if (tbs[j].tag == DerTag.context(3)) {
        cert._parseExtensions(tbs[j].children.first);
        break;
      }
    }
    return cert;
  }

  void _parseExtensions(DerObject extensions) {
    for (final ext in extensions.children) {
      final oid = ext.children[0].asOid;
      // value is the last field (skip the optional critical BOOLEAN)
      final value = ext.children.last;
      if (oid == '1.3.6.1.5.5.7.1.1') {
        // authorityInfoAccess: SEQUENCE OF AccessDescription
        final aia = DerObject.parse(value.content);
        for (final desc in aia.children) {
          if (desc.children[0].asOid == '1.3.6.1.5.5.7.48.1' && // id-ad-ocsp
              desc.children[1].tag == DerTag.contextPrimitive(6)) {
            ocspResponderUrl = String.fromCharCodes(desc.children[1].content);
          }
        }
      } else if (oid == '2.5.29.31') {
        // cRLDistributionPoints: SEQUENCE OF DistributionPoint
        final points = DerObject.parse(value.content);
        for (final dp in points.children) {
          _collectGeneralNameUris(dp, crlDistributionUrls);
        }
      }
    }
  }

  static void _collectGeneralNameUris(DerObject node, List<String> out) {
    // walk down to the [6] IA5String URI leaves, regardless of the
    // DistributionPointName / [0] fullName nesting
    if (node.tag == DerTag.contextPrimitive(6)) {
      out.add(String.fromCharCodes(node.content));
      return;
    }
    if (node.isConstructed) {
      for (final child in node.children) {
        _collectGeneralNameUris(child, out);
      }
    }
  }

  final Uint8List der;
  late final BigInt serial;
  late final Uint8List issuerDer;
  late final Uint8List subjectDer;
  late final DateTime notBefore;
  late final DateTime notAfter;
  late final String publicKeyAlgorithmOid;

  /// The DER of the whole SubjectPublicKeyInfo (algorithm + key bits).
  late final Uint8List subjectPublicKeyInfoDer;

  /// The subjectPublicKey BIT STRING payload (no unused-bits octet) - what
  /// OCSP's issuerKeyHash is computed over (RFC 6960 §4.1.1).
  late final Uint8List subjectPublicKeyBytes;

  /// The to-be-signed portion, what the issuer's signature covers.
  late final Uint8List tbsDer;
  late final String signatureAlgorithmOid;
  DerObject? signatureAlgorithmParams;
  late final Uint8List signatureValue;

  /// Whether this certificate's signature verifies with [issuer]'s key.
  /// False for unsupported algorithms or missing keys.
  bool isSignedBy(X509Certificate issuer) {
    if (signatureAlgorithmOid == _Oid.rsassaPss) {
      if (issuer.publicKey case final RsaPublicKey key) {
        final (hash, saltLength) = _pssParams(signatureAlgorithmParams);
        final digest = hash.convert(tbsDer).bytes;
        return rsaVerifyPss(key, hash, digest, signatureValue,
            saltLength: saltLength);
      }
      return false;
    }
    final hash = _hashFor(signatureAlgorithmOid);
    if (hash == null) return false;
    final digest = hash.convert(tbsDer).bytes;
    switch (issuer.publicKey) {
      case final RsaPublicKey key:
        final digestOid = _digestOidFor(hash)!;
        return rsaVerify(key, digestOid, digest, signatureValue);
      case final EcPublicKey key:
        return ecdsaVerify(key, digest, signatureValue);
      default:
        return false;
    }
  }

  /// [RsaPublicKey], [EcPublicKey], or null for unsupported algorithms.
  Object? publicKey;

  /// Attribute values of a Name by OID, e.g. CN is `2.5.4.3`.
  static Map<String, String> _nameOf(Uint8List nameDer) {
    final out = <String, String>{};
    for (final rdn in DerObject.parse(nameDer).children) {
      for (final pair in rdn.children) {
        out[pair.children[0].asOid] = pair.children[1].asString;
      }
    }
    return out;
  }

  /// The OCSP responder URL from the Authority Information Access extension,
  /// when the certificate carries one.
  String? ocspResponderUrl;

  /// HTTP CRL distribution-point URLs from the CRL Distribution Points
  /// extension.
  final List<String> crlDistributionUrls = [];

  Map<String, String> get subject => _nameOf(subjectDer);
  Map<String, String> get issuer => _nameOf(issuerDer);

  String? get subjectCommonName => subject['2.5.4.3'];
  String? get issuerCommonName => issuer['2.5.4.3'];
}

class CmsSignerInfo {
  CmsSignerInfo._();

  late final String digestAlgorithmOid;
  late final String signatureAlgorithmOid;

  /// The signature AlgorithmIdentifier parameters, when present - carries
  /// the RSASSA-PSS-params (hash, MGF, salt length) for PSS signers.
  DerObject? signatureAlgorithmParams;
  late final Uint8List signature;

  /// The signed attributes re-tagged as an EXPLICIT SET, the exact bytes
  /// the signature is computed over (RFC 5652 §5.4). Null when the signer
  /// signed the content digest directly.
  Uint8List? signedAttrsDer;
  Uint8List? messageDigest;
  DateTime? signingTime;

  /// True when an ESS signing-certificate / signing-certificate-v2 signed
  /// attribute is present - the marker of a CAdES/PAdES baseline signature.
  bool hasSigningCertificate = false;

  /// The DER of an embedded RFC 3161 signature-time-stamp token, when the
  /// SignerInfo carries one as an unsigned attribute (PAdES B-T and up).
  Uint8List? signatureTimeStampToken;

  Uint8List? sidIssuerDer;
  BigInt? sidSerial;
}

class CmsSignedData {
  CmsSignedData._(this.certificates, this.signerInfos, this.eContent);

  /// Parses a ContentInfo wrapping SignedData. [der] may carry trailing
  /// zero padding (PDF signers pre-allocate /Contents).
  factory CmsSignedData.parse(Uint8List der) {
    final contentInfo = DerObject.parsePrefix(der);
    final children = contentInfo.children;
    if (children.isEmpty || children[0].asOid != _Oid.signedData) {
      throw const FormatException('not a CMS SignedData');
    }
    final signedData = children[1].children.first.children;
    var i = 0;
    i++; // version
    i++; // digestAlgorithms
    final encap = signedData[i++].children;
    Uint8List? eContent;
    if (encap.length > 1 && encap[1].tag == DerTag.context(0)) {
      final inner = encap[1].children.first;
      eContent = inner.content;
    }
    final certificates = <X509Certificate>[];
    while (i < signedData.length &&
        (signedData[i].tag == DerTag.context(0) ||
            signedData[i].tag == DerTag.context(1))) {
      if (signedData[i].tag == DerTag.context(0)) {
        for (final certDer in signedData[i].children) {
          try {
            certificates.add(X509Certificate.parse(certDer.encoded));
          } on Object {
            // an attribute certificate or unparsable entry - skip it
          }
        }
      }
      i++;
    }
    final signerInfos = <CmsSignerInfo>[
      for (final info in signedData[i].children) _parseSignerInfo(info),
    ];
    return CmsSignedData._(certificates, signerInfos, eContent);
  }

  static CmsSignerInfo _parseSignerInfo(DerObject info) {
    final signer = CmsSignerInfo._();
    final fields = info.children;
    var i = 1; // skip version
    if (fields[i].tag == DerTag.sequence) {
      final sid = fields[i].children;
      signer.sidIssuerDer = sid[0].encoded;
      signer.sidSerial = sid[1].asInteger;
    }
    i++;
    signer.digestAlgorithmOid = fields[i++].children[0].asOid;
    if (fields[i].tag == DerTag.context(0)) {
      final attrs = fields[i];
      // the signature is over these bytes with the IMPLICIT [0] tag
      // replaced by SET - same length, different identifier octet
      final retagged = Uint8List.fromList(attrs.encoded);
      retagged[0] = DerTag.set;
      signer.signedAttrsDer = retagged;
      for (final attribute in attrs.children) {
        final oid = attribute.children[0].asOid;
        final values = attribute.children[1].children;
        if (values.isEmpty) continue;
        if (oid == _Oid.messageDigest) {
          signer.messageDigest = values.first.content;
        } else if (oid == _Oid.signingTime) {
          signer.signingTime = values.first.asTime;
        } else if (oid == _Oid.signingCertificateV2 ||
            oid == _Oid.signingCertificate) {
          signer.hasSigningCertificate = true;
        }
      }
      i++;
    }
    final signatureAlgorithm = fields[i++].children;
    signer.signatureAlgorithmOid = signatureAlgorithm[0].asOid;
    if (signatureAlgorithm.length > 1) {
      signer.signatureAlgorithmParams = signatureAlgorithm[1];
    }
    signer.signature = fields[i++].content;
    // unsignedAttrs [1] IMPLICIT - scan for a signature-time-stamp token
    if (i < fields.length && fields[i].tag == DerTag.context(1)) {
      for (final attribute in fields[i].children) {
        final oid = attribute.children[0].asOid;
        final values = attribute.children[1].children;
        if (values.isEmpty) continue;
        if (oid == _Oid.signatureTimeStampToken) {
          signer.signatureTimeStampToken = values.first.encoded;
        }
      }
    }
    return signer;
  }

  final List<X509Certificate> certificates;
  final List<CmsSignerInfo> signerInfos;

  /// Encapsulated content, when not detached (adbe.pkcs7.sha1 stores the
  /// document digest here).
  final Uint8List? eContent;

  /// The certificate a signer info points at via issuer + serial.
  X509Certificate? certificateFor(CmsSignerInfo signer) {
    for (final cert in certificates) {
      if (cert.serial == signer.sidSerial &&
          _bytesEqual(cert.issuerDer, signer.sidIssuerDer)) {
        return cert;
      }
    }
    return certificates.isEmpty ? null : certificates.first;
  }

  static bool _bytesEqual(Uint8List a, Uint8List? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Outcome of verifying one CMS signer against detached [content] bytes.
class CmsVerification {
  CmsVerification(this.digestMatches, this.signatureValid, this.problem);

  /// The signed message digest equals the digest of the content.
  final bool digestMatches;

  /// The signature verifies against the signer's certificate key.
  final bool signatureValid;

  /// Why verification could not complete, when it could not.
  final String? problem;
}

/// Verifies [signer] over the detached [content]. For encapsulated
/// variants pass the eContent as [content] override semantics handled by
/// the caller.
CmsVerification cmsVerify(
    CmsSignedData cms, CmsSignerInfo signer, List<int> content) {
  final hash = _hashFor(signer.digestAlgorithmOid);
  if (hash == null) {
    return CmsVerification(
        false, false, 'unsupported digest ${signer.digestAlgorithmOid}');
  }
  final contentDigest = hash.convert(content).bytes;

  // what the signature is over, and the digest it must embed
  final List<int> signedBytes;
  var digestMatches = true;
  if (signer.signedAttrsDer != null) {
    final embedded = signer.messageDigest;
    digestMatches = embedded != null &&
        CmsSignedData._bytesEqual(Uint8List.fromList(contentDigest),
            Uint8List.fromList(embedded));
    signedBytes = signer.signedAttrsDer!;
  } else {
    signedBytes = content;
  }

  final cert = cms.certificateFor(signer);
  if (cert == null) {
    return CmsVerification(digestMatches, false, 'no signer certificate');
  }
  if (signer.signatureAlgorithmOid == _Oid.rsassaPss) {
    if (cert.publicKey case final RsaPublicKey key) {
      // PSS names its own hash in the parameters; fall back to the
      // signer's digest algorithm when they are absent.
      var (pssHash, saltLength) = _pssParams(signer.signatureAlgorithmParams);
      if (signer.signatureAlgorithmParams == null) pssHash = hash;
      final signedDigest = pssHash.convert(signedBytes).bytes;
      return CmsVerification(
          digestMatches,
          rsaVerifyPss(key, pssHash, signedDigest, signer.signature,
              saltLength: saltLength),
          null);
    }
    return CmsVerification(
        digestMatches, false, 'RSASSA-PSS requires an RSA key');
  }

  // the signature algorithm may name the digest itself (sha256WithRSA);
  // otherwise the separate digest algorithm applies
  final signatureHash =
      _hashFor(signer.signatureAlgorithmOid) ?? hash;
  final digestOid = _digestOidFor(signatureHash)!;
  final signedDigest = signatureHash.convert(signedBytes).bytes;

  switch (cert.publicKey) {
    case final RsaPublicKey key:
      return CmsVerification(
          digestMatches,
          rsaVerify(key, digestOid, signedDigest, signer.signature),
          null);
    case final EcPublicKey key:
      return CmsVerification(digestMatches,
          ecdsaVerify(key, signedDigest, signer.signature), null);
    default:
      return CmsVerification(digestMatches, false,
          'unsupported key algorithm ${cert.publicKeyAlgorithmOid}');
  }
}

/// Maps a digest [hash] to its bare AlgorithmIdentifier OID, or null for an
/// unsupported hash. Public companion to the internal `_digestOidFor`.
String? digestOidForHash(crypto.Hash hash) => _digestOidFor(hash);

/// Maps a digest (or combined signature) OID to its [crypto.Hash].
crypto.Hash? hashForDigestOid(String oid) => _hashFor(oid);

/// The ESS signing-certificate-v2 signed attribute (RFC 5035) binding the
/// signature to [cert]: SigningCertificateV2 with one ESSCertIDv2 holding
/// the certificate hash and its issuer/serial. This is what lifts a CMS
/// signature to a PAdES/CAdES baseline (the signer commits to which
/// certificate signed). [hash] is the cert-hash algorithm (sha256 default,
/// for which the AlgorithmIdentifier is omitted per the ASN.1 DEFAULT).
Uint8List essSigningCertificateV2Attribute(X509Certificate cert,
    {crypto.Hash hash = crypto.sha256}) {
  final certHash = hash.convert(cert.der).bytes;
  final issuerSerial = derSequence([
    // GeneralNames ::= SEQUENCE OF GeneralName; directoryName is [4] EXPLICIT
    derSequence([derContext(4, cert.issuerDer)]),
    derInteger(cert.serial),
  ]);
  final essCertId = derSequence([
    if (hash != crypto.sha256)
      derSequence([derOid(_digestOidFor(hash)!), derNull()]),
    derOctetString(certHash),
    issuerSerial,
  ]);
  final signingCertificateV2 = derSequence([
    derSequence([essCertId]), // certs SEQUENCE OF ESSCertIDv2
  ]);
  return derSequence([
    derOid(_Oid.signingCertificateV2),
    derSet([signingCertificateV2]),
  ]);
}

/// The DER SET OF signed attributes the CMS signature is computed over:
/// content-type, message-digest (= [contentDigest]), optional signing-time,
/// optional ESS signing-certificate-v2 (pass [essCertificate] for a PAdES
/// baseline), and any [extra] attributes already DER-encoded as Attribute
/// SEQUENCEs. [hash] selects the cert-hash and is matched to the message
/// digest algorithm by the caller.
Uint8List cmsSignedAttributes({
  required List<int> contentDigest,
  DateTime? signingTime,
  X509Certificate? essCertificate,
  crypto.Hash hash = crypto.sha256,
  String contentType = _Oid.data,
  List<Uint8List> extra = const [],
}) {
  return derSetOf([
    derSequence([
      derOid(_Oid.contentType),
      derSet([derOid(contentType)]),
    ]),
    if (signingTime != null)
      derSequence([
        derOid(_Oid.signingTime),
        derSet([derUtcTime(signingTime)]),
      ]),
    derSequence([
      derOid(_Oid.messageDigest),
      derSet([derOctetString(contentDigest)]),
    ]),
    if (essCertificate != null)
      essSigningCertificateV2Attribute(essCertificate, hash: hash),
    ...extra,
  ]);
}

/// Assembles a detached CMS SignedData from a [signedAttributes] blob (the
/// SET OF from [cmsSignedAttributes]) and the RSA [signature] over it.
/// [certificates] is the DER chain, signer first. [unsignedAttributes]
/// (e.g. a signature-time-stamp) are carried in the SignerInfo's [1] field.
/// [hash] is the digest algorithm named in digestAlgorithms and the
/// SignerInfo (it must match what produced the message digest / signature).
Uint8List cmsAssembleSignedData({
  required Uint8List signedAttributes,
  required Uint8List signature,
  required List<Uint8List> certificates,
  crypto.Hash hash = crypto.sha256,
  List<Uint8List> unsignedAttributes = const [],
  String eContentType = _Oid.data,
  Uint8List? eContent,
  Uint8List? signatureAlgorithm,
}) {
  if (certificates.isEmpty) {
    throw ArgumentError('at least the signer certificate is required');
  }
  final signerCert = X509Certificate.parse(certificates.first);
  final digestOid = _digestOidFor(hash);
  if (digestOid == null) {
    throw ArgumentError('unsupported digest algorithm');
  }
  final digestAlgorithm = derSequence([derOid(digestOid), derNull()]);
  final signerInfo = derSequence([
    derInteger(BigInt.one),
    derSequence([signerCert.issuerDer, derInteger(signerCert.serial)]),
    digestAlgorithm,
    // re-tag the SET of signed attributes as IMPLICIT [0]
    Uint8List.fromList(signedAttributes)..[0] = DerTag.context(0),
    // the signature AlgorithmIdentifier: rsaEncryption by default, or the
    // ecdsa-with-SHAx identifier an EC signer passes in
    signatureAlgorithm ?? derSequence([derOid(_Oid.rsaEncryption), derNull()]),
    derOctetString(signature),
    if (unsignedAttributes.isNotEmpty)
      derContext(1, [for (final a in unsignedAttributes) ...a]),
  ]);

  // RFC 5652 §5.1: SignedData is version 3 when the encapsulated content
  // type is not id-data (e.g. an RFC 3161 TSTInfo), version 1 otherwise.
  final version = eContentType == _Oid.data ? 1 : 3;
  final signedData = derSequence([
    derInteger(BigInt.from(version)),
    derSet([digestAlgorithm]),
    // encapContentInfo: detached carries only the type; encapsulated wraps
    // the content in an EXPLICIT [0] OCTET STRING
    derSequence([
      derOid(eContentType),
      if (eContent != null) derContext(0, derOctetString(eContent)),
    ]),
    derContext(0, [for (final cert in certificates) ...cert]),
    derSet([signerInfo]),
  ]);

  return derSequence([
    derOid(_Oid.signedData),
    derContext(0, signedData),
  ]);
}

/// Builds a CMS SignedData that *encapsulates* [eContent] (content type
/// [eContentType]), signing it with RSA PKCS#1 v1.5. This is the form used
/// by RFC 3161 timestamp tokens (eContentType id-ct-TSTInfo) and other
/// attribute certificates. The content-type signed attribute is set to
/// [eContentType] as RFC 5652 §11.1 requires.
Uint8List cmsSignEncapsulated({
  required Uint8List eContent,
  required String eContentType,
  required RsaPrivateKey privateKey,
  required List<Uint8List> certificates,
  crypto.Hash hash = crypto.sha256,
  DateTime? signingTime,
}) {
  final signedAttrs = cmsSignedAttributes(
    contentDigest: hash.convert(eContent).bytes,
    contentType: eContentType,
    signingTime: signingTime,
    hash: hash,
  );
  final signature = rsaSign(
      privateKey, _digestOidFor(hash)!, hash.convert(signedAttrs).bytes);
  return cmsAssembleSignedData(
    signedAttributes: signedAttrs,
    signature: signature,
    certificates: certificates,
    hash: hash,
    eContentType: eContentType,
    eContent: eContent,
  );
}

/// The signature-time-stamp unsigned attribute (RFC 3161 / ETSI) wrapping a
/// bare RFC 3161 [timeStampToken] (a ContentInfo). Goes in a SignerInfo's
/// unsigned-attributes set to lift a CAdES/PAdES signature from B-B to B-T.
Uint8List cmsSignatureTimeStampAttribute(Uint8List timeStampToken) =>
    derSequence([
      derOid(_Oid.signatureTimeStampToken),
      derSet([timeStampToken]),
    ]);

/// Builds a detached CMS SignedData over content whose digest is
/// [contentDigest], signing with RSA PKCS#1 v1.5. [certificates] is the DER
/// chain, signer certificate first. Pass [essCertificate] (normally the
/// signer cert) to add the ESS signing-certificate-v2 attribute that makes
/// the result a CAdES/PAdES baseline signature.
Uint8List cmsSignDetached({
  required List<int> contentDigest,
  required RsaPrivateKey privateKey,
  required List<Uint8List> certificates,
  DateTime? signingTime,
  X509Certificate? essCertificate,
  crypto.Hash hash = crypto.sha256,
}) {
  final signedAttrs = cmsSignedAttributes(
    contentDigest: contentDigest,
    signingTime: signingTime,
    essCertificate: essCertificate,
    hash: hash,
  );
  final signature = rsaSign(
      privateKey, _digestOidFor(hash)!, hash.convert(signedAttrs).bytes);
  return cmsAssembleSignedData(
    signedAttributes: signedAttrs,
    signature: signature,
    certificates: certificates,
    hash: hash,
  );
}

/// Like [cmsSignDetached] but signs the attributes with ECDSA - the path a
/// self-signed P-256 identity takes. The SignerInfo carries the
/// ecdsa-with-SHAx signature algorithm and the DER `SEQUENCE { r, s }`
/// signature value.
Uint8List cmsSignDetachedEcdsa({
  required List<int> contentDigest,
  required EcPrivateKey privateKey,
  required List<Uint8List> certificates,
  DateTime? signingTime,
  X509Certificate? essCertificate,
  crypto.Hash hash = crypto.sha256,
}) {
  final signedAttrs = cmsSignedAttributes(
    contentDigest: contentDigest,
    signingTime: signingTime,
    essCertificate: essCertificate,
    hash: hash,
  );
  final signature =
      ecdsaSign(privateKey, hash.convert(signedAttrs).bytes, hash: hash);
  return cmsAssembleSignedData(
    signedAttributes: signedAttrs,
    signature: signature,
    certificates: certificates,
    hash: hash,
    signatureAlgorithm: ecdsaSignatureAlgorithm(hash),
  );
}

/// The outcome of X.509 path building and verification.
///
/// Scope: signature verification up the chain, issuer/subject matching,
/// validity windows, and anchoring in caller-supplied roots. Revocation
/// (CRL/OCSP), name constraints, key usage, and policy processing are
/// not evaluated.
class CertificateChainResult {
  const CertificateChainResult({
    required this.trusted,
    required this.chain,
    required this.problems,
  });

  /// The chain ends at (or the leaf itself is) a trust anchor.
  final bool trusted;

  /// The path that was built, leaf first.
  final List<X509Certificate> chain;

  /// Why the chain is untrusted, when it is.
  final List<String> problems;
}

bool _sameDer(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

X509Certificate? _findIssuer(
    X509Certificate of, List<X509Certificate> candidates) {
  for (final candidate in candidates) {
    if (_sameDer(candidate.subjectDer, of.issuerDer) &&
        of.isSignedBy(candidate)) {
      return candidate;
    }
  }
  // fall back to name match alone so the problem reported is "bad
  // signature" rather than "issuer not found"
  for (final candidate in candidates) {
    if (_sameDer(candidate.subjectDer, of.issuerDer)) return candidate;
  }
  return null;
}

/// Builds and verifies the path from [leaf] to one of [trustAnchors],
/// using [intermediates] (typically the other certificates shipped in
/// the CMS container) to fill the middle. [at] is the moment each
/// certificate must be valid - pass the signing time; null skips the
/// validity-window check.
CertificateChainResult verifyCertificateChain({
  required X509Certificate leaf,
  List<X509Certificate> intermediates = const [],
  required List<X509Certificate> trustAnchors,
  DateTime? at,
}) {
  final problems = <String>[];
  final chain = <X509Certificate>[leaf];
  var trusted = false;
  var current = leaf;

  String nameOf(X509Certificate cert) =>
      cert.subjectCommonName ?? 'serial ${cert.serial}';

  while (true) {
    if (trustAnchors.any((a) => _sameDer(a.der, current.der))) {
      trusted = true;
      break;
    }
    if (chain.length > 10) {
      problems.add('certificate chain is longer than 10 links');
      break;
    }
    final issuer =
        _findIssuer(current, [...trustAnchors, ...intermediates]);
    if (issuer == null) {
      final selfSigned = _sameDer(current.subjectDer, current.issuerDer);
      problems.add(selfSigned
          ? 'self-signed certificate "${nameOf(current)}" is not a '
              'trust anchor'
          : 'no certificate found for issuer of "${nameOf(current)}"');
      break;
    }
    if (!current.isSignedBy(issuer)) {
      problems.add('signature on "${nameOf(current)}" does not verify '
          'against its issuer "${nameOf(issuer)}"');
      break;
    }
    if (_sameDer(issuer.der, current.der)) {
      problems.add('self-signed certificate "${nameOf(current)}" is not '
          'a trust anchor');
      break;
    }
    chain.add(issuer);
    if (trustAnchors.any((a) => _sameDer(a.der, issuer.der))) {
      trusted = true;
      break;
    }
    current = issuer;
  }

  if (at != null) {
    for (final cert in chain) {
      if (at.isBefore(cert.notBefore) || at.isAfter(cert.notAfter)) {
        problems.add('certificate "${nameOf(cert)}" is not valid at '
            '${at.toIso8601String()}');
        trusted = false;
      }
    }
  }
  return CertificateChainResult(
      trusted: trusted && problems.isEmpty, chain: chain, problems: problems);
}

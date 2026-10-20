/// Verification of an enveloped W3C XML Signature (XMLDSig / XAdES) over a
/// whole document - the shape ETSI TS 119 612 trusted lists are signed in.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'xml_lite.dart';

const _dsigNs = 'http://www.w3.org/2000/09/xmldsig#';
const _enveloped = 'http://www.w3.org/2000/09/xmldsig#enveloped-signature';

/// The outcome of [verifyEnvelopedXmlSignature].
class XmlSignatureVerification {
  XmlSignatureVerification(this.valid, this.signer, this.problems);

  /// Every reference digest matches, one of them covers the whole document,
  /// and the SignedInfo signature verifies with [signer]'s key. Whether
  /// [signer] is a certificate you trust is the caller's decision.
  final bool valid;

  /// The certificate from the signature's KeyInfo.
  final X509Certificate? signer;

  final List<String> problems;
}

/// Verifies the enveloped signature (a `ds:Signature` child of the root)
/// of [document]. At least one reference must cover the whole document
/// (`URI=""` or the root element's Id, with the enveloped-signature
/// transform), so a signature over only its own properties is refused.
///
/// Supported: exclusive and inclusive C14N 1.0; SHA-1/256/384/512
/// digests; RSA PKCS#1 v1.5, RSASSA-PSS (the `xmldsig-more#sha*-rsa-MGF1`
/// family) and ECDSA signature methods.
XmlSignatureVerification verifyEnvelopedXmlSignature(XmlLiteDocument document) {
  final problems = <String>[];
  XmlLiteElement? signature;
  for (final e in document.root.childElements) {
    if (e.localName == 'Signature' && e.namespaceUri == _dsigNs) {
      signature = e;
    }
  }
  if (signature == null) {
    return XmlSignatureVerification(false, null, ['document is not signed']);
  }
  final signedInfo = signature.child('SignedInfo');
  final signatureValue = signature.child('SignatureValue');
  if (signedInfo == null || signatureValue == null) {
    return XmlSignatureVerification(false, null, ['malformed ds:Signature']);
  }

  X509Certificate? signer;
  final certText = signature
      .descendantsNamed('X509Certificate')
      .map((e) => e.text)
      .firstOrNull;
  if (certText != null) {
    try {
      signer = X509Certificate.parse(_base64(certText));
    } on Object catch (e) {
      problems.add('cannot parse the signing certificate: $e');
    }
  }
  if (signer == null) {
    return XmlSignatureVerification(
        false, null, [...problems, 'no signing certificate in KeyInfo']);
  }

  final c14nUri =
      signedInfo.child('CanonicalizationMethod')?.attribute('Algorithm') ?? '';
  final c14n = XmlC14nMethod.fromUri(c14nUri);
  if (c14n == null) {
    return XmlSignatureVerification(
        false, signer, ['unsupported canonicalization $c14nUri']);
  }

  var coversDocument = false;
  var referencesOk = true;
  for (final ref in signedInfo.childrenNamed('Reference')) {
    final uri = ref.attribute('URI') ?? '';
    final transforms = [
      for (final t in ref.child('Transforms')?.childrenNamed('Transform') ??
          const <XmlLiteElement>[])
        t,
    ];
    XmlLiteElement target;
    if (uri.isEmpty) {
      target = document.root;
    } else if (uri.startsWith('#')) {
      final found = document.elementById(uri.substring(1));
      if (found == null) {
        problems.add('reference $uri points at nothing');
        referencesOk = false;
        continue;
      }
      target = found;
    } else {
      problems.add('unsupported external reference $uri');
      referencesOk = false;
      continue;
    }
    var envelope = false;
    var method = XmlC14nMethod.inclusive; // the default after node-set
    var prefixes = const <String>[];
    var supported = true;
    for (final t in transforms) {
      final alg = t.attribute('Algorithm') ?? '';
      if (alg == _enveloped) {
        envelope = true;
      } else if (XmlC14nMethod.fromUri(alg) case final m?) {
        method = m;
        final list = t.child('InclusiveNamespaces')?.attribute('PrefixList');
        if (list != null) {
          prefixes =
              list.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        }
      } else {
        problems.add('unsupported transform $alg');
        supported = false;
      }
    }
    if (!supported) {
      referencesOk = false;
      continue;
    }
    final hash = _digestFor(ref.child('DigestMethod')?.attribute('Algorithm'));
    if (hash == null) {
      problems.add('unsupported digest method on reference "$uri"');
      referencesOk = false;
      continue;
    }
    final Uint8List bytes;
    if (identical(target, document.root) && uri.isEmpty) {
      bytes = canonicalizeDocument(document,
          method: method,
          omit: envelope ? signature : null,
          inclusivePrefixes: prefixes);
    } else {
      bytes = canonicalizeElement(target,
          method: method,
          omit: envelope ? signature : null,
          inclusivePrefixes: prefixes);
    }
    final expected = _base64(ref.child('DigestValue')?.text ?? '');
    if (!_equal(hash.convert(bytes).bytes, expected)) {
      problems.add('digest mismatch on reference "$uri"');
      referencesOk = false;
      continue;
    }
    if (identical(target, document.root) && envelope) coversDocument = true;
  }
  if (!coversDocument) {
    problems.add('no reference covers the whole document');
  }

  final signed = canonicalizeElement(signedInfo,
      method: c14n,
      inclusivePrefixes: signedInfo
              .child('CanonicalizationMethod')
              ?.child('InclusiveNamespaces')
              ?.attribute('PrefixList')
              ?.split(RegExp(r'\s+'))
              .where((p) => p.isNotEmpty)
              .toList() ??
          const []);
  final method =
      signedInfo.child('SignatureMethod')?.attribute('Algorithm') ?? '';
  final sigOk = _verify(method, signer, signed, _base64(signatureValue.text));
  if (sigOk == null) {
    problems.add('unsupported signature method $method');
  } else if (!sigOk) {
    problems.add('signature does not verify');
  }
  return XmlSignatureVerification(
      referencesOk && coversDocument && sigOk == true, signer, problems);
}

Uint8List _base64(String text) =>
    base64.decode(text.replaceAll(RegExp(r'\s'), ''));

crypto.Hash? _digestFor(String? uri) => switch (uri) {
      'http://www.w3.org/2000/09/xmldsig#sha1' => crypto.sha1,
      'http://www.w3.org/2001/04/xmlenc#sha256' => crypto.sha256,
      'http://www.w3.org/2001/04/xmldsig-more#sha384' => crypto.sha384,
      'http://www.w3.org/2001/04/xmlenc#sha512' => crypto.sha512,
      _ => null,
    };

/// Verifies [signature] over [data]; null for an unsupported method.
bool? _verify(String method, X509Certificate signer, Uint8List data,
    Uint8List signature) {
  const more = 'http://www.w3.org/2001/04/xmldsig-more#';
  const more07 = 'http://www.w3.org/2007/05/xmldsig-more#';
  final (kind, hash) = switch (method) {
    'http://www.w3.org/2000/09/xmldsig#rsa-sha1' => ('rsa', crypto.sha1),
    '${more}rsa-sha256' => ('rsa', crypto.sha256),
    '${more}rsa-sha384' => ('rsa', crypto.sha384),
    '${more}rsa-sha512' => ('rsa', crypto.sha512),
    '${more07}sha256-rsa-MGF1' => ('pss', crypto.sha256),
    '${more07}sha384-rsa-MGF1' => ('pss', crypto.sha384),
    '${more07}sha512-rsa-MGF1' => ('pss', crypto.sha512),
    '${more}ecdsa-sha256' => ('ec', crypto.sha256),
    '${more}ecdsa-sha384' => ('ec', crypto.sha384),
    '${more}ecdsa-sha512' => ('ec', crypto.sha512),
    _ => ('', crypto.sha256),
  };
  if (kind.isEmpty) return null;
  final digest = hash.convert(data).bytes;
  final key = signer.publicKey;
  switch (kind) {
    case 'rsa' when key is RsaPublicKey:
      return rsaVerify(key, digestOidForHash(hash)!, digest, signature);
    case 'pss' when key is RsaPublicKey:
      return rsaVerifyPss(key, hash, digest, signature);
    case 'ec' when key is EcPublicKey:
      // XMLDSig carries ECDSA as the raw r || s concatenation (RFC 4050).
      if (signature.length.isOdd) return false;
      final half = signature.length ~/ 2;
      BigInt big(List<int> b) =>
          b.fold(BigInt.zero, (v, x) => (v << 8) | BigInt.from(x));
      final der = derSequence([
        derInteger(big(signature.sublist(0, half))),
        derInteger(big(signature.sublist(half))),
      ]);
      return ecdsaVerify(key, digest, der);
    default:
      return false;
  }
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// A certificate-backed identity used to create a cryptographic PDF
/// signature.
///
/// [fromFiles] accepts an unencrypted RSA PKCS#1/PKCS#8 private key in PEM or
/// DER form and one or more X.509 certificate files in PEM or DER form. A PEM
/// certificate file may contain a complete chain. The certificate matching the
/// private key is placed first automatically, as required by CMS/PAdES.
///
/// The identity is held in memory only. The editor never writes the private key
/// to preferences or into the PDF; the PDF receives the public certificate
/// chain and a detached RSA/SHA-256 signature.
class PdfDigitalSignatureIdentity {
  PdfDigitalSignatureIdentity._(
    this._privateKey,
    this._certificates,
    this._signerCertificate,
  );

  factory PdfDigitalSignatureIdentity.fromFiles({
    required Uint8List privateKey,
    required List<Uint8List> certificates,
  }) {
    if (certificates.isEmpty) {
      throw const FormatException('Select at least one X.509 certificate.');
    }
    final key = _parsePrivateKey(privateKey);
    final ders = _parseCertificates(certificates);
    final parsed = <X509Certificate>[];
    for (var i = 0; i < ders.length; i++) {
      try {
        parsed.add(X509Certificate.parse(ders[i]));
      } catch (_) {
        throw FormatException('Certificate ${i + 1} is not valid X.509.');
      }
    }

    var signerIndex = -1;
    for (var i = 0; i < parsed.length; i++) {
      final publicKey = parsed[i].publicKey;
      if (publicKey is RsaPublicKey &&
          publicKey.modulus == key.modulus &&
          publicKey.exponent == key.publicExponent) {
        signerIndex = i;
        break;
      }
    }
    if (signerIndex < 0) {
      throw const FormatException(
        'The private key does not match any selected RSA certificate.',
      );
    }

    final ordered = <Uint8List>[
      ders[signerIndex],
      for (var i = 0; i < ders.length; i++)
        if (i != signerIndex) ders[i],
    ];
    return PdfDigitalSignatureIdentity._(
      key,
      List.unmodifiable(ordered),
      parsed[signerIndex],
    );
  }

  final RsaPrivateKey _privateKey;
  final List<Uint8List> _certificates;
  final X509Certificate _signerCertificate;

  /// The signer's certificate common name, when present.
  String? get signerName => _signerCertificate.subjectCommonName;

  DateTime get validFrom => _signerCertificate.notBefore;
  DateTime get validUntil => _signerCertificate.notAfter;

  /// Number of certificates embedded in the signature, including the signer.
  int get certificateCount => _certificates.length;

  /// Creates a PAdES B-B (`ETSI.CAdES.detached`) signature over [bytes].
  ///
  /// The result is an incremental PDF revision: [bytes] remains its exact
  /// prefix. [fieldName] reuses an empty signature field when one with that
  /// name exists; otherwise the engine creates an invisible signature field.
  Future<Uint8List> sign(
    Uint8List bytes, {
    String password = '',
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
  }) {
    final editor = PdfEditor(PdfDocument.open(bytes, password: password));
    return editor.saveSignedPades(
      privateKey: _privateKey,
      certificates: _certificates,
      level: PdfPadesLevel.bB,
      fieldName: _nonEmpty(fieldName),
      signerName: _nonEmpty(signerName),
      reason: _nonEmpty(reason),
      location: _nonEmpty(location),
      contactInfo: _nonEmpty(contactInfo),
      signingTime: signingTime,
    );
  }
}

RsaPrivateKey _parsePrivateKey(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('BEGIN ENCRYPTED PRIVATE KEY')) {
      throw const FormatException(
        'Encrypted private keys are not supported. Choose an unencrypted '
        'RSA PKCS#1 or PKCS#8 key.',
      );
    }
    if (text.contains('BEGIN PRIVATE KEY') ||
        text.contains('BEGIN RSA PRIVATE KEY')) {
      return RsaPrivateKey.fromPem(text);
    }
    return RsaPrivateKey.fromDer(bytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'The private key is not an unencrypted RSA PKCS#1 or PKCS#8 key.',
    );
  }
}

List<Uint8List> _parseCertificates(List<Uint8List> files) {
  final out = <Uint8List>[];
  final seen = <String>{};
  final block = RegExp(
    r'-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----',
  );
  for (final file in files) {
    final text = utf8.decode(file, allowMalformed: true);
    final matches = block.allMatches(text).toList();
    final certificates = matches.isEmpty
        ? [file]
        : [for (final match in matches) pemBytes(match.group(0)!)];
    for (final certificate in certificates) {
      if (seen.add(base64Encode(certificate))) out.add(certificate);
    }
  }
  if (out.isEmpty) {
    throw const FormatException('No X.509 certificates were found.');
  }
  return out;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

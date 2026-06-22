/// X.509 Certificate Revocation List parsing (RFC 5280 §5), the read side
/// only: enough to embed a CRL in a /DSS and, offline, decide whether a
/// serial appears revoked and that the list is genuine and current.
library;

import 'dart:typed_data';

import 'asn1.dart';
import 'cms.dart';
import 'ecdsa.dart';
import 'rsa.dart';

/// One revoked entry: the certificate serial and when it was revoked.
class CrlEntry {
  CrlEntry(this.serialNumber, this.revocationDate);
  final BigInt serialNumber;
  final DateTime revocationDate;
}

/// A parsed CertificateList. [der] keeps the original bytes for verbatim
/// embedding in a /DSS /CRLs array.
class CertificateRevocationList {
  CertificateRevocationList._(
    this.der,
    this.issuerDer,
    this.thisUpdate,
    this.nextUpdate,
    this.entries,
    this._tbsDer,
    this._signatureAlgorithmOid,
    this._signature,
  );

  factory CertificateRevocationList.parse(Uint8List der) {
    final top = DerObject.parse(der).children;
    final tbs = top[0];
    final signatureAlgorithm = top[1].children;
    final signatureAlgorithmOid = signatureAlgorithm[0].asOid;
    final signature = top[2].asBitString;

    // TBSCertList ::= SEQUENCE { version OPTIONAL, signature, issuer,
    //   thisUpdate, nextUpdate OPTIONAL, revokedCertificates OPTIONAL, ... }
    final f = tbs.children;
    var i = 0;
    if (f[i].tag == DerTag.integer) i++; // version (v2)
    i++; // signature AlgorithmIdentifier
    final issuerDer = f[i++].encoded;
    final thisUpdate = f[i++].asTime;
    DateTime? nextUpdate;
    if (i < f.length &&
        (f[i].tag == DerTag.utcTime || f[i].tag == DerTag.generalizedTime)) {
      nextUpdate = f[i++].asTime;
    }
    final entries = <CrlEntry>[];
    if (i < f.length && f[i].tag == DerTag.sequence) {
      for (final revoked in f[i].children) {
        final fields = revoked.children;
        entries.add(CrlEntry(fields[0].asInteger, fields[1].asTime));
      }
    }
    return CertificateRevocationList._(
      der,
      issuerDer,
      thisUpdate,
      nextUpdate,
      entries,
      tbs.encoded,
      signatureAlgorithmOid,
      signature,
    );
  }

  final Uint8List der;
  final Uint8List issuerDer;
  final DateTime thisUpdate;
  final DateTime? nextUpdate;
  final List<CrlEntry> entries;

  final Uint8List _tbsDer;
  final String _signatureAlgorithmOid;
  final Uint8List _signature;

  /// The revocation entry for [serial], or null when the serial is not
  /// listed (i.e. not revoked as of [thisUpdate]).
  CrlEntry? forSerial(BigInt serial) {
    for (final e in entries) {
      if (e.serialNumber == serial) return e;
    }
    return null;
  }

  /// Verifies the CRL signature against its [issuer]'s key. The issuer is
  /// the CA whose certificates this list covers (its subject must equal the
  /// CRL issuer name — checked by the caller via [issuerDer]).
  bool signatureValid(X509Certificate issuer) {
    final hash = hashForDigestOid(_signatureAlgorithmOid);
    if (hash == null) return false;
    final digest = hash.convert(_tbsDer).bytes;
    switch (issuer.publicKey) {
      case final RsaPublicKey key:
        final digestOid = digestOidForHash(hash);
        if (digestOid == null) return false;
        return rsaVerify(key, digestOid, digest, _signature);
      case final EcPublicKey key:
        return ecdsaVerify(key, digest, _signature);
      default:
        return false;
    }
  }
}

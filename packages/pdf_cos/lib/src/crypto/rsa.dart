/// RSA PKCS#1 v1.5 signatures over Dart's native [BigInt.modPow] — used
/// to verify and produce CMS signatures. No padding oracle concerns
/// apply: signing pads deterministically and verification rebuilds the
/// expected encoding and compares.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';

/// Digest algorithm OIDs paired with their DigestInfo prefixes.
abstract final class DigestOid {
  static const sha1 = '1.3.14.3.2.26';
  static const sha256 = '2.16.840.1.101.3.4.2.1';
  static const sha384 = '2.16.840.1.101.3.4.2.2';
  static const sha512 = '2.16.840.1.101.3.4.2.3';
}

class RsaPublicKey {
  RsaPublicKey(this.modulus, this.exponent);

  /// Parses a PKCS#1 RSAPublicKey: SEQUENCE { n, e }.
  factory RsaPublicKey.fromPkcs1(Uint8List der) {
    final seq = DerObject.parse(der).children;
    return RsaPublicKey(seq[0].asInteger, seq[1].asInteger);
  }

  final BigInt modulus;
  final BigInt exponent;

  int get byteLength => (modulus.bitLength + 7) >> 3;
}

class RsaPrivateKey {
  RsaPrivateKey({
    required this.modulus,
    required this.publicExponent,
    required this.privateExponent,
  });

  /// Parses PKCS#8 PrivateKeyInfo or bare PKCS#1 RSAPrivateKey DER.
  factory RsaPrivateKey.fromDer(Uint8List der) {
    var seq = DerObject.parse(der).children;
    // PKCS#8: SEQUENCE { version, AlgorithmIdentifier, OCTET STRING key }
    if (seq.length == 3 && seq[1].tag == DerTag.sequence) {
      seq = DerObject.parse(seq[2].content).children;
    }
    // PKCS#1: SEQUENCE { version, n, e, d, p, q, dP, dQ, qInv }
    return RsaPrivateKey(
      modulus: seq[1].asInteger,
      publicExponent: seq[2].asInteger,
      privateExponent: seq[3].asInteger,
    );
  }

  /// Parses a PEM block (`BEGIN PRIVATE KEY` or `BEGIN RSA PRIVATE KEY`).
  factory RsaPrivateKey.fromPem(String pem) =>
      RsaPrivateKey.fromDer(pemBytes(pem));

  final BigInt modulus;
  final BigInt publicExponent;
  final BigInt privateExponent;

  RsaPublicKey get publicKey => RsaPublicKey(modulus, publicExponent);

  int get byteLength => (modulus.bitLength + 7) >> 3;
}

/// Strips a PEM armor and decodes the base64 body.
Uint8List pemBytes(String pem) {
  final body = pem
      .split('\n')
      .where((line) => !line.contains('-----') && line.trim().isNotEmpty)
      .join();
  return Uint8List.fromList(base64.decode(body));
}

/// DigestInfo ::= SEQUENCE { AlgorithmIdentifier, OCTET STRING digest }
Uint8List _digestInfo(String digestOid, List<int> digest) => derSequence([
      derSequence([derOid(digestOid), derNull()]),
      derOctetString(digest),
    ]);

Uint8List _emsaPkcs1v15(String digestOid, List<int> digest, int length) {
  final info = _digestInfo(digestOid, digest);
  if (length < info.length + 11) {
    throw ArgumentError('RSA key too small for digest');
  }
  return Uint8List.fromList([
    0x00, 0x01,
    ...List.filled(length - info.length - 3, 0xFF),
    0x00,
    ...info,
  ]);
}

BigInt _toBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

Uint8List _toBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var rest = value;
  for (var i = length - 1; i >= 0 && rest > BigInt.zero; i--) {
    out[i] = (rest & BigInt.from(0xFF)).toInt();
    rest >>= 8;
  }
  return out;
}

/// Verifies a PKCS#1 v1.5 signature over a precomputed [digest].
bool rsaVerify(
    RsaPublicKey key, String digestOid, List<int> digest, List<int> signature) {
  final s = _toBigInt(signature);
  if (s >= key.modulus) return false;
  final em = _toBytes(s.modPow(key.exponent, key.modulus), key.byteLength);
  final expected = _emsaPkcs1v15(digestOid, digest, key.byteLength);
  if (em.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < em.length; i++) {
    diff |= em[i] ^ expected[i];
  }
  if (diff == 0) return true;
  // some encoders omit the NULL AlgorithmIdentifier parameters
  final altInfo = derSequence([
    derSequence([derOid(digestOid)]),
    derOctetString(digest),
  ]);
  final alt = Uint8List.fromList([
    0x00, 0x01,
    ...List.filled(key.byteLength - altInfo.length - 3, 0xFF),
    0x00,
    ...altInfo,
  ]);
  if (em.length != alt.length) return false;
  diff = 0;
  for (var i = 0; i < em.length; i++) {
    diff |= em[i] ^ alt[i];
  }
  return diff == 0;
}

/// MGF1 mask generation (RFC 8017 §B.2.1): hash `seed || counter` for an
/// incrementing 32-bit big-endian counter until [length] bytes accumulate.
Uint8List _mgf1(crypto.Hash hash, List<int> seed, int length) {
  final out = BytesBuilder(copy: false);
  for (var counter = 0; out.length < length; counter++) {
    final block = [
      ...seed,
      (counter >> 24) & 0xFF,
      (counter >> 16) & 0xFF,
      (counter >> 8) & 0xFF,
      counter & 0xFF,
    ];
    out.add(hash.convert(block).bytes);
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// Verifies an RSASSA-PSS signature (RFC 8017 §8.1.2) over a precomputed
/// message hash [mHash]. [hash] is used both for the message digest and as
/// the MGF1 hash — PSS permits them to differ, but conformant signers (and
/// every real PDF signature) use one algorithm for both.
///
/// When [saltLength] is null the salt length is recovered from the encoded
/// message, which accepts any conformant signature regardless of the length
/// its parameters declared; when supplied it is enforced.
bool rsaVerifyPss(
  RsaPublicKey key,
  crypto.Hash hash,
  List<int> mHash,
  List<int> signature, {
  int? saltLength,
}) {
  final modBits = key.modulus.bitLength;
  final emBits = modBits - 1; // leftmost bit of EM is always zero
  final emLen = (emBits + 7) >> 3;
  final hLen = mHash.length;
  if (emLen < hLen + 2) return false;

  // RSAVP1: m = s^e mod n, then EM = I2OSP(m, emLen).
  final s = _toBigInt(signature);
  if (s >= key.modulus) return false;
  final em = _toBytes(s.modPow(key.exponent, key.modulus), emLen);
  if (em[emLen - 1] != 0xBC) return false;

  final dbLen = emLen - hLen - 1;
  final maskedDb = Uint8List.sublistView(em, 0, dbLen);
  final h = Uint8List.sublistView(em, dbLen, dbLen + hLen);

  // The leftmost 8*emLen - emBits bits of EM must be zero (0..7 bits).
  final topBits = 8 * emLen - emBits;
  if (topBits > 0 && (maskedDb[0] & ((0xFF << (8 - topBits)) & 0xFF)) != 0) {
    return false;
  }

  final dbMask = _mgf1(hash, h, dbLen);
  final db = Uint8List(dbLen);
  for (var i = 0; i < dbLen; i++) {
    db[i] = maskedDb[i] ^ dbMask[i];
  }
  db[0] &= 0xFF >> topBits;

  // DB = PS (zero octets) || 0x01 || salt. Scanning to the 0x01 separator
  // recovers the salt length when it was not declared.
  var i = 0;
  while (i < dbLen && db[i] == 0) {
    i++;
  }
  if (i >= dbLen || db[i] != 0x01) return false;
  final salt = Uint8List.sublistView(db, i + 1);
  if (saltLength != null && salt.length != saltLength) return false;

  // M' = (0x)00 00 00 00 00 00 00 00 || mHash || salt; H' must equal H.
  final mPrime = [...List.filled(8, 0), ...mHash, ...salt];
  final hPrime = hash.convert(mPrime).bytes;
  if (hPrime.length != h.length) return false;
  var diff = 0;
  for (var j = 0; j < h.length; j++) {
    diff |= h[j] ^ hPrime[j];
  }
  return diff == 0;
}

/// Produces a PKCS#1 v1.5 signature over a precomputed [digest].
Uint8List rsaSign(RsaPrivateKey key, String digestOid, List<int> digest) {
  final em = _emsaPkcs1v15(digestOid, digest, key.byteLength);
  return _toBytes(
      _toBigInt(em).modPow(key.privateExponent, key.modulus), key.byteLength);
}

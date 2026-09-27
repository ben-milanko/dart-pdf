/// ECDSA over the NIST prime curves: signature verification (enough to
/// validate the EC-signed PDFs modern signing services produce) plus
/// key generation and deterministic (RFC 6979) signing, the pieces the
/// one-tap self-signed signing identity needs. All pure Dart, VM + web.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';

/// A short-Weierstrass prime curve y² = x³ + ax + b (mod p).
class EcCurve {
  const EcCurve._(
      this.oid, this._p, this._a, this._b, this._gx, this._gy, this.order);

  final String oid;
  final String _p, _a, _b, _gx, _gy;
  final String order;

  BigInt get p => _params.p;
  BigInt get a => _params.a;
  BigInt get b => _params.b;
  BigInt get n => _params.n;
  (BigInt, BigInt) get g => (_params.gx, _params.gy);

  /// The constants above parsed from hex once per curve rather than on every
  /// read (the point arithmetic reads them constantly).
  _EcParams get _params => _EcParams.of(this);

  static const p256 = EcCurve._(
    '1.2.840.10045.3.1.7',
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    'ffffffff00000001000000000000000000000000fffffffffffffffffffffffc',
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
    '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
  );

  static const p384 = EcCurve._(
    '1.3.132.0.34',
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe'
        'ffffffff0000000000000000ffffffff',
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe'
        'ffffffff0000000000000000fffffffc',
    'b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875a'
        'c656398d8a2ed19d2a85c8edd3ec2aef',
    'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
        '5502f25dbf55296c3a545e3872760ab7',
    '3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c0'
        '0a60b1ce1d7e819d7a431d7c90ea0e5f',
    'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf'
        '581a0db248b0a77aecec196accc52973',
  );

  static const p521 = EcCurve._(
    '1.3.132.0.35',
    '01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'ffff',
    '01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffc',
    '0051953eb9618e1c9a1f929a21a0b68540eea2da725b99b315f3b8b489918ef1'
        '09e156193951ec7e937b1652c0bd3bb1bf073573df883d2c34f1ef451fd46b50'
        '3f00',
    '00c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d'
        '3dbaa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5'
        'bd66',
    '011839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e'
        '662c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd1'
        '6650',
    '01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb6fb71e9138'
        '6409',
  );

  static EcCurve? byOid(String oid) => switch (oid) {
        '1.2.840.10045.3.1.7' => p256,
        '1.3.132.0.34' => p384,
        '1.3.132.0.35' => p521,
        _ => null,
      };
}

class EcPublicKey {
  EcPublicKey(this.curve, this.x, this.y);

  /// Parses an uncompressed SEC1 point (0x04 || X || Y).
  factory EcPublicKey.fromPoint(EcCurve curve, Uint8List point) {
    if (point.isEmpty || point[0] != 0x04) {
      throw const FormatException('only uncompressed EC points supported');
    }
    final half = (point.length - 1) ~/ 2;
    BigInt parse(Uint8List bytes) {
      var v = BigInt.zero;
      for (final b in bytes) {
        v = (v << 8) | BigInt.from(b);
      }
      return v;
    }

    return EcPublicKey(
      curve,
      parse(Uint8List.sublistView(point, 1, 1 + half)),
      parse(Uint8List.sublistView(point, 1 + half)),
    );
  }

  final EcCurve curve;
  final BigInt x;
  final BigInt y;

  /// The uncompressed SEC1 encoding (0x04 || X || Y), each coordinate
  /// left-padded to the curve's field size - the form stored in an X.509
  /// SubjectPublicKeyInfo BIT STRING.
  Uint8List get sec1 {
    final size = (curve.p.bitLength + 7) >> 3;
    final out = Uint8List(1 + 2 * size);
    out[0] = 0x04;
    _writeFixed(out, 1, x, size);
    _writeFixed(out, 1 + size, y, size);
    return out;
  }
}

/// An EC private key: a scalar [d] on [curve]. The public key is [d]·G.
class EcPrivateKey {
  EcPrivateKey(this.curve, this.d);

  /// Generates a fresh key on [curve], drawing the scalar uniformly from
  /// `[1, n-1]` with [random] (defaults to [Random.secure]). No `dart:io`
  /// and no big-integer prime search, so it runs on the VM and the web.
  factory EcPrivateKey.generate(EcCurve curve, {Random? random}) {
    final rng = random ?? Random.secure();
    final n = curve.n;
    final size = (n.bitLength + 7) >> 3;
    while (true) {
      var d = BigInt.zero;
      for (var i = 0; i < size; i++) {
        d = (d << 8) | BigInt.from(rng.nextInt(256));
      }
      // The order is just under 2^(8*size), so rejection almost never
      // loops; sampling the full width and rejecting keeps it unbiased.
      if (d >= BigInt.one && d < n) return EcPrivateKey(curve, d);
    }
  }

  /// Parses an RFC 5915 `ECPrivateKey` (the DER an OpenSSL
  /// `EC PRIVATE KEY` PEM wraps), or the same structure unwrapped from a
  /// PKCS#8 `PrivateKeyInfo`. The named-curve parameter selects the curve
  /// (P-256 when absent).
  factory EcPrivateKey.fromSec1(Uint8List der) {
    var seq = DerObject.parse(der).children;
    var curve = EcCurve.p256;
    // PKCS#8: SEQUENCE { version, AlgorithmIdentifier, OCTET STRING key }
    if (seq.length >= 3 &&
        seq[1].tag == DerTag.sequence &&
        seq[2].tag == DerTag.octetString) {
      // The named curve lives in the PKCS#8 AlgorithmIdentifier; the inner
      // ECPrivateKey usually omits its own [0] parameters, so read it here.
      final algorithm = seq[1].children;
      if (algorithm.length > 1) {
        final named = EcCurve.byOid(algorithm[1].asOid);
        if (named != null) curve = named;
      }
      seq = DerObject.parse(seq[2].content).children;
    }
    // An RFC 5915 key (or a PKCS#8 inner key that kept them) names the curve
    // in its own [0] parameters, which take precedence when present.
    for (final field in seq.skip(2)) {
      if (field.tag == DerTag.context(0)) {
        final named = EcCurve.byOid(field.children.first.asOid);
        if (named != null) curve = named;
      }
    }
    var d = BigInt.zero;
    for (final byte in seq[1].content) {
      d = (d << 8) | BigInt.from(byte);
    }
    return EcPrivateKey(curve, d);
  }

  final EcCurve curve;
  final BigInt d;

  EcPublicKey get publicKey {
    final point = _multiply(curve, curve.g, d)!;
    return EcPublicKey(curve, point.$1, point.$2);
  }

  /// The RFC 5915 `ECPrivateKey` DER: version, the fixed-width scalar, the
  /// named-curve OID, and the SEC1 public point - a self-contained,
  /// round-trippable encoding suitable for storing in a keychain/keystore.
  Uint8List get sec1Der {
    final size = (curve.n.bitLength + 7) >> 3;
    return derSequence([
      derInteger(BigInt.one),
      derOctetString(_int2octets(d, size)),
      derContext(0, derOid(curve.oid)),
      derContext(1, derBitString(publicKey.sec1)),
    ]);
  }
}

/// Signs [digest] with [key], returning the signature as DER
/// `SEQUENCE { r, s }` (what [ecdsaVerify], CMS, and X.509 expect).
///
/// The per-signature nonce is derived deterministically per RFC 6979 with
/// [hash] (which must be the hash that produced [digest]), so signing needs
/// no secure randomness and the output is reproducible - the property the
/// key-agreement test vectors and the KATs rely on.
Uint8List ecdsaSign(EcPrivateKey key, List<int> digest,
    {crypto.Hash hash = crypto.sha256}) {
  final (r, s) = _signRs(key, digest, hash);
  return derSequence([derInteger(r), derInteger(s)]);
}

/// The raw (r, s) scalars, exposed for the RFC 6979 known-answer tests.
(BigInt, BigInt) ecdsaSignRs(EcPrivateKey key, List<int> digest,
        {crypto.Hash hash = crypto.sha256}) =>
    _signRs(key, digest, hash);

(BigInt, BigInt) _signRs(EcPrivateKey key, List<int> digest, crypto.Hash hash) {
  final curve = key.curve;
  final n = curve.n;
  final e = _bits2int(digest, n.bitLength);
  for (final k in _rfc6979Nonces(key, digest, hash)) {
    final point = _multiply(curve, curve.g, k);
    if (point == null) continue;
    final r = point.$1 % n;
    if (r == BigInt.zero) continue;
    final s = (k.modInverse(n) * (e + r * key.d)) % n;
    if (s == BigInt.zero) continue;
    return (r, s);
  }
  // Unreachable in practice: the generator yields an endless stream.
  throw StateError('ECDSA nonce generation failed');
}

/// The RFC 6979 §3.2 deterministic-nonce stream: repeatedly HMAC-DRBG a
/// candidate `k`, retrying (per the spec) whenever one is out of range.
Iterable<BigInt> _rfc6979Nonces(
    EcPrivateKey key, List<int> digest, crypto.Hash hash) sync* {
  final n = key.curve.n;
  final qlen = n.bitLength;
  final holen = hash.convert(const []).bytes.length; // hash output length
  final rolen = (qlen + 7) >> 3;

  List<int> hmac(List<int> mac, List<int> data) =>
      crypto.Hmac(hash, mac).convert(data).bytes;

  final x = _int2octets(key.d, rolen);
  final h1 = _bits2octets(digest, n, rolen);

  var v = List<int>.filled(holen, 0x01);
  var k = List<int>.filled(holen, 0x00);
  k = hmac(k, [...v, 0x00, ...x, ...h1]);
  v = hmac(k, v);
  k = hmac(k, [...v, 0x01, ...x, ...h1]);
  v = hmac(k, v);

  while (true) {
    final t = <int>[];
    while (t.length < rolen) {
      v = hmac(k, v);
      t.addAll(v);
    }
    final candidate = _bits2int(t, qlen);
    if (candidate >= BigInt.one && candidate < n) yield candidate;
    k = hmac(k, [...v, 0x00]);
    v = hmac(k, v);
  }
}

/// RFC 6979 bits2int: the big-endian integer of [bytes], keeping only the
/// leftmost [qlen] bits. Identical to the digest truncation [ecdsaVerify]
/// applies, so signer and verifier agree on `e`.
BigInt _bits2int(List<int> bytes, int qlen) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  final excess = bytes.length * 8 - qlen;
  if (excess > 0) value >>= excess;
  return value;
}

/// RFC 6979 int2octets: [value] as [length] big-endian octets.
Uint8List _int2octets(BigInt value, int length) {
  final out = Uint8List(length);
  var rest = value;
  for (var i = length - 1; i >= 0 && rest > BigInt.zero; i--) {
    out[i] = (rest & BigInt.from(0xFF)).toInt();
    rest >>= 8;
  }
  return out;
}

/// RFC 6979 bits2octets: reduce bits2int([bytes]) modulo [n], as octets.
Uint8List _bits2octets(List<int> bytes, BigInt n, int length) =>
    _int2octets(_bits2int(bytes, n.bitLength) % n, length);

void _writeFixed(Uint8List out, int offset, BigInt value, int length) {
  var rest = value;
  for (var i = offset + length - 1; i >= offset && rest > BigInt.zero; i--) {
    out[i] = (rest & BigInt.from(0xFF)).toInt();
    rest >>= 8;
  }
}

/// Verifies an ECDSA signature (DER SEQUENCE { r, s }) over [digest].
bool ecdsaVerify(EcPublicKey key, List<int> digest, Uint8List signatureDer) {
  final BigInt r, s;
  try {
    final seq = DerObject.parse(signatureDer).children;
    r = seq[0].asInteger;
    s = seq[1].asInteger;
  } on Object {
    return false;
  }
  final params = key.curve._params;
  final n = params.n;
  if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;

  // leftmost bits of the digest, per SEC1 §4.1.4
  var e = BigInt.zero;
  for (final byte in digest) {
    e = (e << 8) | BigInt.from(byte);
  }
  final excess = digest.length * 8 - n.bitLength;
  if (excess > 0) e >>= excess;

  final w = s.modInverse(n);
  final u1 = (e * w) % n;
  // Never zero: r is in [1, n-1] and w is invertible modulo the prime n.
  final u2 = (r * w) % n;
  final point = params.shamir(u1, u2, key.x, key.y);
  // The affine x of the sum, reduced mod n, must equal r. x < p < 2n, so x is
  // r or r + n; compare in Jacobian form (x = X/Z^2) to skip an inversion.
  final (x, _, z) = point;
  if (z == BigInt.zero) return false;
  final m = params.p;
  final zz = z * z % m;
  if (r * zz % m == x) return true;
  final rn = r + n;
  return rn < m && rn * zz % m == x;
}

/// A point in Jacobian coordinates: (X, Y, Z) stands for the affine point
/// (X/Z², Y/Z³); Z == 0 is the point at infinity. Coordinates stay reduced
/// into [0, p).
typedef _Jacobian = (BigInt, BigInt, BigInt);

final _Jacobian _infinity = (BigInt.one, BigInt.one, BigInt.zero);
final BigInt _three = BigInt.from(3);

/// The parsed constants of an [EcCurve] and its point arithmetic. The curve is
/// a `const` class, which can't cache parsed values in late fields, so they
/// live here - one instance per curve OID, built on first use.
///
/// The arithmetic works in Jacobian coordinates, so a scalar multiplication
/// pays a single field inversion (converting the result back) instead of one
/// per point addition; every supported curve has a = -3, which the doubling
/// formula relies on.
class _EcParams {
  _EcParams._(EcCurve curve)
      : p = BigInt.parse(curve._p, radix: 16),
        a = BigInt.parse(curve._a, radix: 16),
        b = BigInt.parse(curve._b, radix: 16),
        n = BigInt.parse(curve.order, radix: 16),
        gx = BigInt.parse(curve._gx, radix: 16),
        gy = BigInt.parse(curve._gy, radix: 16) {
    if (a != p - _three) {
      throw UnsupportedError('EC arithmetic needs a = -3 (${curve.oid})');
    }
  }

  static final Map<String, _EcParams> _byOid = {};

  static _EcParams of(EcCurve curve) =>
      _byOid[curve.oid] ??= _EcParams._(curve);

  final BigInt p, a, b, n, gx, gy;

  /// 2·[point], per dbl-2001-b (a = -3).
  _Jacobian twice(_Jacobian point) {
    final (x, y, z) = point;
    // Infinity doubles to itself, and a point with y = 0 has order two (none
    // exists on these prime-order curves, but an off-curve key could hit it).
    if (z == BigInt.zero || y == BigInt.zero) return _infinity;
    final m = p;
    final delta = z * z % m;
    final gamma = y * y % m;
    final beta = x * gamma % m;
    final alpha = _three * ((x - delta) * (x + delta) % m) % m;
    final x3 = (alpha * alpha - (beta << 3)) % m;
    final yz = y + z;
    final z3 = (yz * yz - gamma - delta) % m;
    final y3 = (alpha * ((beta << 2) - x3) - ((gamma * gamma % m) << 3)) % m;
    return (x3, y3, z3);
  }

  /// [point] + the affine point ([x2], [y2]), per madd-2007-bl - including
  /// the cases that formula can't take: an infinite [point], the same point
  /// (a doubling), and its negation (infinity).
  _Jacobian addAffine(_Jacobian point, BigInt x2, BigInt y2) {
    final (x1, y1, z1) = point;
    if (z1 == BigInt.zero) return (x2, y2, BigInt.one);
    final m = p;
    final z1z1 = z1 * z1 % m;
    final u2 = x2 * z1z1 % m;
    final s2 = y2 * z1 % m * z1z1 % m;
    final h = (u2 - x1) % m;
    final r = ((s2 - y1) << 1) % m;
    if (h == BigInt.zero) {
      // Same x: either P + P or P + (-P).
      return r == BigInt.zero ? twice(point) : _infinity;
    }
    final hh = h * h % m;
    final i = (hh << 2) % m;
    final j = h * i % m;
    final v = x1 * i % m;
    final x3 = (r * r - j - (v << 1)) % m;
    final y3 = (r * (v - x3) - ((y1 * j) << 1)) % m;
    final zh = z1 + h;
    final z3 = (zh * zh - z1z1 - hh) % m;
    return (x3, y3, z3);
  }

  /// [point] in affine coordinates, or null for the point at infinity.
  _Point? toAffine(_Jacobian point) {
    final (x, y, z) = point;
    if (z == BigInt.zero) return null;
    final zi = z.modInverse(p);
    final zi2 = zi * zi % p;
    return (x * zi2 % p, y * zi2 % p * zi % p);
  }

  /// [scalar]·([x], [y]) by left-to-right double-and-add; infinity for a
  /// non-positive scalar.
  _Jacobian multiply(BigInt scalar, BigInt x, BigInt y) {
    if (scalar <= BigInt.zero) return _infinity;
    var acc = _infinity;
    for (final bit in _bits(scalar)) {
      acc = twice(acc);
      if (bit == 1) acc = addAffine(acc, x, y);
    }
    return acc;
  }

  /// The binary digits of non-negative [k], most significant first, without
  /// leading zeros (none for zero). Read off its hex form: BigInt's radix-2
  /// conversion takes a generic repeated-division path that costs ~15x the
  /// hex one (~50 us for a 256-bit scalar on AOT), a visible slice of a
  /// verify that extracts two scalars.
  static Uint8List _bits(BigInt k) {
    if (k.sign <= 0) return Uint8List(0);
    final hex = k.toRadixString(16);
    final all = Uint8List(hex.length * 4);
    for (var i = 0; i < hex.length; i++) {
      final c = hex.codeUnitAt(i);
      final nibble = c >= 0x61 /* a */
          ? c - 0x57
          : c >= 0x41 /* A */
              ? c - 0x37
              : c - 0x30;
      all[i * 4] = nibble >> 3;
      all[i * 4 + 1] = (nibble >> 2) & 1;
      all[i * 4 + 2] = (nibble >> 1) & 1;
      all[i * 4 + 3] = nibble & 1;
    }
    return Uint8List.sublistView(all, all.length - k.bitLength);
  }

  /// [u1]·G + [u2]·Q for Q = ([keyX], [keyY]), with Shamir's trick: one shared
  /// doubling chain over both scalars' bits, adding G, Q, or the precomputed
  /// G + Q wherever either has a one. A zero scalar just contributes no
  /// additions; Q = ±G is taken by [addAffine] (G + Q is then 2G or infinity).
  _Jacobian shamir(BigInt u1, BigInt u2, BigInt keyX, BigInt keyY) {
    final qx = keyX % p;
    final qy = keyY % p;
    final gq = toAffine(addAffine((gx, gy, BigInt.one), qx, qy));
    final bits1 = _bits(u1);
    final bits2 = _bits(u2);
    final length = bits1.length > bits2.length ? bits1.length : bits2.length;
    final skip1 = length - bits1.length;
    final skip2 = length - bits2.length;
    var acc = _infinity;
    for (var i = 0; i < length; i++) {
      acc = twice(acc);
      final one1 = i >= skip1 && bits1[i - skip1] == 1;
      final one2 = i >= skip2 && bits2[i - skip2] == 1;
      if (one1 && one2) {
        if (gq != null) acc = addAffine(acc, gq.$1, gq.$2);
      } else if (one1) {
        acc = addAffine(acc, gx, gy);
      } else if (one2) {
        acc = addAffine(acc, qx, qy);
      }
    }
    return acc;
  }
}

typedef _Point = (BigInt, BigInt);

/// [scalar]·[point] in affine coordinates, or null for infinity.
_Point? _multiply(EcCurve curve, _Point point, BigInt scalar) {
  final params = curve._params;
  return params.toAffine(params.multiply(scalar, point.$1, point.$2));
}

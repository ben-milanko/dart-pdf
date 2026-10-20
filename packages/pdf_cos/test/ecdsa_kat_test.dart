// Known-answer tests for ECDSA over NIST P-256, P-384 and P-521:
// - a subset of the Project Wycheproof verification vectors (C2SP/wycheproof,
//   Apache License 2.0) chosen for the point arithmetic: point duplication,
//   the Shamir-multiplication edge case, extreme intermediate values, small
//   r and s, and special public keys. The encoding-focused vectors are left
//   out - they exercise the DER parser, not the curve;
// - the RFC 6979 A.2.6/A.2.7 P-384 and P-521 signing vectors;
// - a secp521r1 signature made by OpenSSL;
// - a randomized agreement sweep against a textbook affine verifier.
// dart2js has its own BigInt, so run these under `dart test -p node` too.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

BigInt _big(String s) => BigInt.parse(s.replaceAll(' ', ''), radix: 16);

/// A Wycheproof verify case: the index of its public key in the curve's key
/// table, the message (hex), the DER signature (hex), and the expected result.
typedef _Vector = ({int id, int key, String msg, String sig, bool valid});

/// dart2js runs BigInt arithmetic an order of magnitude slower; the sweep
/// shrinks there so the suite stays inside the default timeout.
final bool _onWeb = identical(0, 0.0);

void main() {
  group('curve constants', () {
    test('the P-521 order is the 521-bit NIST n', () {
      // FIPS 186-4 D.1.2.5, in decimal.
      expect(
          EcCurve.p521.n,
          BigInt.parse('68647976601306097149819007990813932172694353001433'
              '05409394463459185543183397655394245057746333217197532963996371'
              '363321113864768612440380340372808892707005449'));
      expect(EcCurve.p521.n.bitLength, 521);
    });

    for (final curve in [EcCurve.p256, EcCurve.p384, EcCurve.p521]) {
      test('${curve.oid}: G is on the curve and (n-1)G = -G', () {
        final (gx, gy) = curve.g;
        final p = curve.p;
        expect((gy * gy - (gx * gx * gx + curve.a * gx + curve.b)) % p,
            BigInt.zero);
        // n is the order of G exactly when (n-1)G is G's negation.
        final minusG = EcPrivateKey(curve, curve.n - BigInt.one).publicKey;
        expect(minusG.x, gx);
        expect(minusG.y, p - gy);
      });
    }
  });

  group('Wycheproof verify vectors', () {
    for (final (name, curve, hash, keys, vectors) in [
      ('P-256', EcCurve.p256, crypto.sha256, _p256Keys, _p256Vectors),
      ('P-384', EcCurve.p384, crypto.sha384, _p384Keys, _p384Vectors),
      ('P-521', EcCurve.p521, crypto.sha512, _p521Keys, _p521Vectors),
    ]) {
      test(name, () {
        for (final v in vectors) {
          final (x, y) = keys[v.key];
          final key = EcPublicKey(curve, _big(x), _big(y));
          final digest = hash.convert(_hex(v.msg)).bytes;
          expect(ecdsaVerify(key, digest, _hex(v.sig)), v.valid,
              reason: 'tcId ${v.id}');
        }
      });
    }
  });

  group('RFC 6979 deterministic signing on P-384 and P-521', () {
    void check(EcPrivateKey key, crypto.Hash hash, String message, String rHex,
        String sHex) {
      final digest = hash.convert(ascii.encode(message)).bytes;
      final (r, s) = ecdsaSignRs(key, digest, hash: hash);
      expect(r, _big(rHex), reason: 'r for "$message"');
      expect(s, _big(sHex), reason: 's for "$message"');
      expect(
          ecdsaVerify(key.publicKey, digest,
              derSequence([derInteger(r), derInteger(s)])),
          isTrue);
    }

    test('P-384 with SHA-384 (A.2.6)', () {
      final key = EcPrivateKey(
          EcCurve.p384,
          _big(
              '6B9D3DAD2E1B8C1C05B19875B6659F4DE23C3B667BF297BA9AA47740787137D8'
              '96D5724E4C70A825F872C9EA60D2EDF5'));
      expect(
          key.publicKey.x,
          _big(
              'EC3A4E415B4E19A4568618029F427FA5DA9A8BC4AE92E02E06AAE5286B300C64'
              'DEF8F0EA9055866064A254515480BC13'));
      expect(
          key.publicKey.y,
          _big(
              '8015D9B72D7D57244EA8EF9AC0C621896708A59367F9DFB9F54CA84B3F1C9DB1'
              '288B231C3AE0D4FE7344FD2533264720'));
      check(
          key,
          crypto.sha384,
          'sample',
          '94EDBB92A5ECB8AAD4736E56C691916B3F88140666CE9FA73D64C4EA95AD133C'
              '81A648152E44ACF96E36DD1E80FABE46',
          '99EF4AEB15F178CEA1FE40DB2603138F130E740A19624526203B6351D0A3A94F'
              'A329C145786E679E7B82C71A38628AC8');
      check(
          key,
          crypto.sha384,
          'test',
          '8203B63D3C853E8D77227FB377BCF7B7B772E97892A80F36AB775D509D7A5FEB'
              '0542A7F0812998DA8F1DD3CA3CF023DB',
          'DDD0760448D42D8A43AF45AF836FCE4DE8BE06B485E9B61B827C2F13173923E0'
              '6A739F040649A667BF3B828246BAA5A5');
    });

    test('P-521 with SHA-512 (A.2.7)', () {
      final key = EcPrivateKey(
          EcCurve.p521,
          _big(
              '0FAD06DAA62BA3B25D2FB40133DA757205DE67F5BB0018FEE8C86E1B68C7E75C'
              'AA896EB32F1F47C70855836A6D16FCC1466F6D8FBEC67DB89EC0C08B0E996B83'
              '538'));
      expect(
          key.publicKey.x,
          _big(
              '1894550D0785932E00EAA23B694F213F8C3121F86DC97A04E5A7167DB4E5BCD3'
              '71123D46E45DB6B5D5370A7F20FB633155D38FFA16D2BD761DCAC474B9A2F502'
              '3A4'));
      expect(
          key.publicKey.y,
          _big(
              '0493101C962CD4D2FDDF782285E64584139C2F91B47F87FF82354D6630F746A2'
              '8A0DB25741B5B34A828008B22ACC23F924FAAFBD4D33F81EA66956DFEAA2BFDF'
              'CF5'));
      check(
          key,
          crypto.sha512,
          'sample',
          '0C328FAFCBD79DD77850370C46325D987CB525569FB63C5D3BC53950E6D4C5F1'
              '74E25A1EE9017B5D450606ADD152B534931D7D4E8455CC91F9B15BF05EC36E37'
              '7FA',
          '0617CCE7CF5064806C467F678D3B4080D6F1CC50AF26CA209417308281B68AF2'
              '82623EAA63E5B5C0723D8B8C37FF0777B1A20F8CCB1DCCC43997F1EE0E44DA4A'
              '67A');
      check(
          key,
          crypto.sha512,
          'test',
          '13E99020ABF5CEE7525D16B69B229652AB6BDF2AFFCAEF38773B4B7D08725F10'
              'CDB93482FDCC54EDCEE91ECA4166B2A7C6265EF0CE2BD7051B7CEF945BABD47E'
              'E6D',
          '1FBD0013C674AA79CB39849527916CE301C66EA7CE8B80682786AD60F98F7E78'
              'A19CA69EFF5C57400E3B3A0AD66CE0978214D13BAF4E9AC60752F7B155E2DE4D'
              'CE3');
    });
  });

  test('an OpenSSL secp521r1 signature verifies', () {
    // `openssl dgst -sha512 -sign` over "hello" with a throwaway P-521 key.
    final spki = DerObject.parse(_hex(_openSslP521Spki)).children;
    final key = EcPublicKey.fromPoint(
        EcCurve.byOid(spki[0].children[1].asOid)!, spki[1].asBitString);
    final digest = crypto.sha512.convert(ascii.encode('hello')).bytes;
    final signature = _hex(_openSslP521Signature);
    expect(ecdsaVerify(key, digest, signature), isTrue);
    final other = crypto.sha512.convert(ascii.encode('hellO')).bytes;
    expect(ecdsaVerify(key, other, signature), isFalse);
  });

  group('edge cases of the joint multiplication', () {
    for (final curve in [EcCurve.p256, EcCurve.p384, EcCurve.p521]) {
      final hash = _hashFor(curve);
      final n = curve.n;
      final cases = {
        'Q = G': BigInt.one,
        'Q = -G': n - BigInt.one,
        'Q = 2G': BigInt.two,
      };
      for (final MapEntry(key: label, value: d) in cases.entries) {
        test('${curve.oid}: $label', () {
          final key = EcPrivateKey(curve, d);
          final digest = hash.convert(utf8.encode('edge $label')).bytes;
          final signature = ecdsaSign(key, digest, hash: hash);
          expect(ecdsaVerify(key.publicKey, digest, signature), isTrue);
          expect(_affineVerify(key.publicKey, digest, signature), isTrue);
          final other = hash.convert(utf8.encode('other $label')).bytes;
          expect(ecdsaVerify(key.publicKey, other, signature), isFalse);
        });
      }

      test('${curve.oid}: a zero digest (u1 = 0)', () {
        final key = EcPrivateKey(curve, BigInt.from(0x1234567));
        final zero = List<int>.filled(hash.convert(const []).bytes.length, 0);
        final signature = ecdsaSign(key, zero, hash: hash);
        expect(ecdsaVerify(key.publicKey, zero, signature), isTrue);
        expect(_affineVerify(key.publicKey, zero, signature), isTrue);
        final one = [...zero]..[zero.length - 1] = 1;
        expect(ecdsaVerify(key.publicKey, one, signature), isFalse);
      });
    }
  });

  group('agrees with a textbook affine verifier', () {
    for (final curve in [EcCurve.p256, EcCurve.p384, EcCurve.p521]) {
      test(curve.oid, () {
        final random = Random(0x5EC0 + curve.n.bitLength);
        final hash = _hashFor(curve);
        final n = curve.n;
        var cases = 0, accepted = 0;
        for (var k = 0; k < (_onWeb ? 1 : 2); k++) {
          final key = EcPrivateKey.generate(curve, random: random);
          final public = key.publicKey;
          // the affine multiplication reaches the same public point
          expect(_affineMultiply(curve, curve.g, key.d), (public.x, public.y));
          for (var m = 0; m < (_onWeb ? 1 : 3); m++) {
            final message = List<int>.generate(
                1 + random.nextInt(64), (_) => random.nextInt(256));
            final digest = hash.convert(message).bytes;
            final signature = ecdsaSign(key, digest, hash: hash);
            final rs = DerObject.parse(signature).children;
            final r = rs[0].asInteger, s = rs[1].asInteger;
            Uint8List der(BigInt r, BigInt s) =>
                derSequence([derInteger(r), derInteger(s)]);
            final flipped = [...digest]..[random.nextInt(digest.length)] ^=
                1 << random.nextInt(8);
            final variants = <(List<int>, Uint8List)>[
              (digest, signature),
              (flipped, signature),
              (digest, der((r + BigInt.one) % n, s)),
              (digest, der(r, (s + BigInt.one) % n)),
              (digest, der(r, n - s)), // the malleated twin is also valid
              (digest, der(BigInt.zero, s)),
              (digest, der(r, n)),
              (hash.convert([m, k]).bytes, signature),
              (digest, Uint8List.fromList(const [0x30, 0x00])),
            ];
            for (final (d, sig) in variants) {
              cases++;
              final ours = ecdsaVerify(public, d, sig);
              expect(ours, _affineVerify(public, d, sig),
                  reason: 'case $cases');
              if (ours) accepted++;
            }
          }
        }
        // each valid signature and its (r, n - s) twin, nothing else
        expect(accepted, cases ~/ 9 * 2);
      });
    }
  });
}

crypto.Hash _hashFor(EcCurve curve) => switch (curve.n.bitLength) {
      256 => crypto.sha256,
      384 => crypto.sha384,
      _ => crypto.sha512,
    };

// ---------------------------------------------------------------------------
// The reference: affine double-and-add with a modular inversion per point
// operation and two separate multiplications, as ecdsaVerify used to do.

typedef _Affine = (BigInt, BigInt);

_Affine? _affineAdd(EcCurve curve, _Affine? p, _Affine? q) {
  if (p == null) return q;
  if (q == null) return p;
  final m = curve.p;
  final (x1, y1) = p;
  final (x2, y2) = q;
  BigInt slope;
  if (x1 == x2) {
    if ((y1 + y2) % m == BigInt.zero) return null;
    slope = (BigInt.from(3) * x1 * x1 + curve.a) *
        (BigInt.two * y1).modInverse(m) %
        m;
  } else {
    slope = (y2 - y1) * (x2 - x1).modInverse(m) % m;
  }
  final x3 = (slope * slope - x1 - x2) % m;
  final y3 = (slope * (x1 - x3) - y1) % m;
  return (x3, y3);
}

_Affine? _affineMultiply(EcCurve curve, _Affine point, BigInt scalar) {
  _Affine? result;
  _Affine? addend = point;
  for (var k = scalar; k > BigInt.zero; k >>= 1) {
    if (k.isOdd) result = _affineAdd(curve, result, addend);
    addend = _affineAdd(curve, addend, addend);
  }
  return result;
}

bool _affineVerify(EcPublicKey key, List<int> digest, Uint8List der) {
  final BigInt r, s;
  try {
    final seq = DerObject.parse(der).children;
    r = seq[0].asInteger;
    s = seq[1].asInteger;
  } on Object {
    return false;
  }
  final curve = key.curve;
  final n = curve.n;
  if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;
  var e = BigInt.zero;
  for (final byte in digest) {
    e = (e << 8) | BigInt.from(byte);
  }
  final excess = digest.length * 8 - n.bitLength;
  if (excess > 0) e >>= excess;
  final w = s.modInverse(n);
  final point = _affineAdd(curve, _affineMultiply(curve, curve.g, e * w % n),
      _affineMultiply(curve, (key.x, key.y), r * w % n));
  return point != null && point.$1 % n == r;
}

// ---------------------------------------------------------------------------
// Fixtures.

const _openSslP521Spki =
    '30819b301006072a8648ce3d020106052b8104002303818600040060e466b62bae'
    '3241b0730e719bd00b8ded10a0e6e0b381268a5119f48d026f24b32ba1700d99a7'
    'c97e7cceaa6b2525a35faebfa632e5fde376817c42de934dcacc01363f1fad6e08'
    '41f8df07be19f54ccacf978ae5f8ec619c1052b51f0689d4ca9a7cb2bffe4147b9'
    'b2c60580441e4417f0710dfc783b5663f9b48fe7544ce244feff';

const _openSslP521Signature =
    '308188024201a9321f105d7be1231800392803b512190a4546d15f30ad1dc2686c'
    '8561ef321b53794d5c30dad7948e9f13dddaf9786573e7cccd986a4dd31625fdd9'
    '238f057a6e024201929474de2b46b6aeeabd0e41b6ef7d2bc7e9148280a7490f93'
    '3d660223d704812a84d9da9bda8ce39a50272b9da65194050e5cbf581f82ed9092'
    'fcc96332ff2fe8';

// Wycheproof ecdsa_secp{256r1_sha256,384r1_sha384,521r1_sha512}_test.json
// (testvectors_v1), keys as (wx, wy) hex and cases by tcId.

const _p256Keys = <(String, String)>[
  (
    '4aaec73635726f213fb8a9e64da3b8632e41495a944d0045b522eba7240fad5',
    '87d9315798aaa3a5ba01775787ced05eaaf7b4e09fc81d6d1aa546e8365d525d',
  ),
  (
    '2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838',
    'c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e',
  ),
  (
    'ad99500288d466940031d72a9f5445a4d43784640855bf0a69874d2de5fe103',
    'c5011e6ef2c42dcd50d5d3d29f99ae6eba2c80c9244f4c5422f0979ff0c3ba5e',
  ),
  (
    'ab05fd9d0de26b9ce6f4819652d9fc69193d0aa398f0fba8013e09c582204554',
    '19235271228c786759095d12b75af0692dd4103f19f6a8c32f49435a1e9b8d45',
  ),
  (
    'a71af64de5126a4a4e02b7922d66ce9415ce88a4c9d25514d91082c8725ac957',
    '5d47723c8fbe580bb369fec9c2665d8e30a435b9932645482e7c9f11e872296b',
  ),
  (
    '61722eaba731c697c7a9ba4d0afdbb5713d8aa12b0eab601bb33dbaf792c5adc',
    '272cd993b2b663aba5b3a26c101182ff178684945e83879e71598b95fe647dfc',
  ),
  (
    'b533d4695dd5b8c5e07757e55e6e516f7e2c88fa0239e23f60e8ec07dd70f287',
    '1b134ee58cc583278456863f33c3a85d881f7d4a39850143e29d4eaf009afe47',
  ),
  (
    '5b812fd521aafa69835a849cce6fbdeb6983b442d2444fe70e134c027fc46963',
    '838a40f2a36092e9004e92d8d940cf5638550ce672ce8b8d4e15eba5499249e9',
  ),
  (
    '5b812fd521aafa69835a849cce6fbdeb6983b442d2444fe70e134c027fc46963',
    '7c75bf0c5c9f6d17ffb16d2726bf30a9c7aaf31a8d317472b1ea145ab66db616',
  ),
  (
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
    '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
  ),
  (
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
    'b01cbd1c01e58065711814b583f061e9d431cca994cea1313449bf97c840ae0a',
  ),
  (
    '4f337ccfd67726a805e4f1600ae2849df3807eca117380239fbd816900000000',
    'ed9dea124cc8c396416411e988c30f427eb504af43a3146cd5df7ea60666d685',
  ),
];

const _p256Vectors = <_Vector>[
  (
    id: 1, // ValidSignature
    key: 0,
    msg: '',
    sig: '3045022100b292a619339f6e567a305c951c0dcbcc42d16e47f219f9e98e76e0'
        '9d8770b34a02200177e60492c5a8242f76f07bfe3661bde59ec2a17ce5bd2dab'
        '2abebdf89a62e2',
    valid: true,
  ),
  (
    id: 2, // ValidSignature
    key: 0,
    msg: '4d7367',
    sig: '30450220530bd6b0c9af2d69ba897f6b5fb59695cfbf33afe66dbadcf5b8d2a2'
        'a6538e23022100d85e489cb7a161fd55ededcedbf4cc0c0987e3e3f0f242cae9'
        '34c72caa3f43e9',
    valid: true,
  ),
  (
    id: 152, // RangeCheck
    key: 1,
    msg: '313233343030',
    sig: '30460221012ba3a8bd6b94d5ed80a6d9d1190a436ebccc0833490686deac8635'
        'bcb9bf5369022100b329f479a2bbd0a5c384ee1493b1f5186a87139cac5df408'
        '7c134b49156847db',
    valid: false,
  ),
  (
    id: 168, // InvalidSignature
    key: 1,
    msg: '313233343030',
    sig: '3006020100020100',
    valid: false,
  ),
  (
    id: 295, // EdgeCaseShamirMultiplication
    key: 1,
    msg: '3639383139',
    sig: '3044022064a1aab5000d0e804f3e2fc02bdee9be8ff312334e2ba16d11547c97'
        '711c898e02206af015971cc30be6d1a206d4e013e0997772a2f91d73286ffd68'
        '3b9bb2cf4f1b',
    valid: true,
  ),
  (
    id: 296, // SpecialCaseHash
    key: 1,
    msg: '343236343739373234',
    sig: '3044022016aea964a2f6506d6f78c81c91fc7e8bded7d397738448de1e19a0ec'
        '580bf2660220252cd762130c6667cfe8b7bc47d27d78391e8e80c578d1cd38c3'
        'ff033be928e9',
    valid: true,
  ),
  (
    id: 350, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '303502104319055358e8617b0c46353d039cdaab022100ffffffff00000000ff'
        'ffffffffffffffbce6faada7179e84f3b9cac2fc63254e',
    valid: true,
  ),
  (
    id: 351, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '3046022100ffffffff00000001000000000000000000000000ffffffffffffff'
        'fffffffffc022100ffffffff00000000ffffffffffffffffbce6faada7179e84'
        'f3b9cac2fc63254e',
    valid: false,
  ),
  (
    id: 352, // ArithmeticError
    key: 3,
    msg: '313233343030',
    sig: '3046022100ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9ca'
        'c2fc63254f022100ffffffff00000000ffffffffffffffffbce6faada7179e84'
        'f3b9cac2fc63254e',
    valid: true,
  ),
  (
    id: 355, // SmallRandS
    key: 4,
    msg: '313233343030',
    sig: '3006020105020101',
    valid: true,
  ),
  (
    id: 377, // ModularInverse
    key: 5,
    msg: '313233343030',
    sig: '30440220555555550000000055555555555555553ef7a8e48d07df81a6934396'
        '54210c70022002f676969f451a8ccafa4c4f09791810e6d632dbd60b1d5540f3'
        '284fbe1889b0',
    valid: true,
  ),
  (
    id: 392, // PointDuplication
    key: 6,
    msg: '313233343030',
    sig: '304402207fffffff800000007fffffffffffffffde737d56d38bcf4279dce561'
        '7e3192a80220555555550000000055555555555555553ef7a8e48d07df81a693'
        '439654210c70',
    valid: false,
  ),
  (
    id: 427, // PointDuplication
    key: 7,
    msg: '313233343030',
    sig: '304502206f2347cab7dd76858fe0555ac3bc99048c4aacafdfb6bcbe05ea6c42'
        'c4934569022100bb726660235793aa9957a61e76e00c2c435109cf9a15dd624d'
        '53f4301047856b',
    valid: true,
  ),
  (
    id: 428, // PointDuplication
    key: 8,
    msg: '313233343030',
    sig: '304502206f2347cab7dd76858fe0555ac3bc99048c4aacafdfb6bcbe05ea6c42'
        'c4934569022100bb726660235793aa9957a61e76e00c2c435109cf9a15dd624d'
        '53f4301047856b',
    valid: false,
  ),
  (
    id: 444, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '3045022100bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419'
        'feca6050230220249249246db6db6ddb6db6db6db6db6dad4591868595a8ee6b'
        'f5f864ff7be0c2',
    valid: false,
  ),
  (
    id: 445, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '3044022044a5ad0ad0636d9f12bc9e0a6bdd5e1cbcb012ea7bf091fcec15b0c4'
        '3202d52e0220249249246db6db6ddb6db6db6db6db6dad4591868595a8ee6bf5'
        'f864ff7be0c2',
    valid: false,
  ),
  (
    id: 446, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '3045022100bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419'
        'feca6050230220249249246db6db6ddb6db6db6db6db6dad4591868595a8ee6b'
        'f5f864ff7be0c2',
    valid: false,
  ),
  (
    id: 447, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '3044022044a5ad0ad0636d9f12bc9e0a6bdd5e1cbcb012ea7bf091fcec15b0c4'
        '3202d52e0220249249246db6db6ddb6db6db6db6db6dad4591868595a8ee6bf5'
        'f864ff7be0c2',
    valid: false,
  ),
  (
    id: 448, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '3046022100d434e262a49eab7781e353a3565e482550dd0fd5defa013c7f2974'
        '5eff3569f10221009b0c0a93f267fb6052fd8077be769c2b98953195d7bc10de'
        '844218305c6ba17a',
    valid: true,
  ),
  (
    id: 449, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '304402200fe774355c04d060f76d79fd7a772e421463489221bf0a33add0be9b'
        '1979110b0220500dcba1c69a8fbd43fa4f57f743ce124ca8b91a1f325f3fac61'
        '81175df55737',
    valid: true,
  ),
];

const _p384Keys = <(String, String)>[
  (
    '29bdb76d5fa741bfd70233cb3a66cc7d44beb3b0663d92a8136650478bcefb61'
        'ef182e155a54345a5e8e5e88f064e5bc',
    '9a525ab7f764dad3dae1468c2b419f3b62b9ba917d5e8c4fb1ec47404a3fc764'
        '74b2713081be9db4c00e043ada9fc4a3',
  ),
  (
    '2da57dda1089276a543f9ffdac0bff0d976cad71eb7280e7d9bfd9fee4bdb2f2'
        '0f47ff888274389772d98cc5752138aa',
    '4b6d054d69dcf3e25ec49df870715e34883b1836197d76f8ad962e78f6571bbc'
        '7407b0d6091f9e4d88f014274406174f',
  ),
  (
    '4bf4e52f958427ebb5915fb8c9595551b4d3a3fdab67badd9d6c3093f425ba43'
        '630df71f42f0eb7ceaa94d9f6448a85d',
    'd30331588249fd2fdc0b309ec7ed8481bc16f27800c13d7db700fc82e1b1c854'
        '5aa0c0d3b56e3bfe789fc18a916887c2',
  ),
  (
    '3623bb296b88f626d0f92656bf016f115b721277ccb4930739bfbd81f9c1e734'
        '630e0685d32e154e0b4a5c62e43851f6',
    '768356b4a5764c128c7b1105e3d778a89d1e01da297ede1bc4312c2583e0bbdd'
        'd21613583dd09ab895c63be479f94576',
  ),
  (
    '554f2fd0b700a9f4568752b673d9c0d29dc96c10fe67e38c6d6d339bfafe05f9'
        '70da8c3d2164e82031307a44bd322511',
    '71312b61b59113ff0bd3b8a9a4934df262aa8096f840e9d8bffa5d7491ded87b'
        '38c496f9b9e4f0ba1089f8d3ffc88a9f',
  ),
  (
    '5abbf618a084f67138c418a896d61af3af1826040835b73e7619846b495eba6f'
        '7eeaa2e9cc61c85f6100fedc25c16743',
    'b065a427bc503139529e4faa63dda553aed2696fd02c2b6ceb2d941d2c4363cf'
        '9ac7a6759d50e8b9d07fe286f17cef5c',
  ),
  (
    'f896353cc3a8afdd543ec3aef062ca97bc32ed1724ea38b940b8c0ea0e23b341'
        '87afbe70daf8dbaa5b511557e5d2bdda',
    'c4bd265da67ceeafca636f6f4c0472f22a9d02e2289184f73bbb700ae8fc921e'
        'ff4920f290bfcb49fbb232cc13a21028',
  ),
  (
    'e585a067d6dff37ae7f17f81583119b61291597345f107acffe237a08f4886d4'
        'fdf94fe63182e6143c99be25a7b7d86b',
    '572c1e06dd2c7b94b873f0578fcb2b99d60e246e51245d0804edd44b32f0f000'
        'c8f8f88f1d4a65fea51dbbb4ab1e2823',
  ),
  (
    'e585a067d6dff37ae7f17f81583119b61291597345f107acffe237a08f4886d4'
        'fdf94fe63182e6143c99be25a7b7d86b',
    'a8d3e1f922d3846b478c0fa87034d46629f1db91aedba2f7fb122bb4cd0f0ffe'
        '3707076fe2b59a015ae2444c54e1d7dc',
  ),
  (
    'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
        '5502f25dbf55296c3a545e3872760ab7',
    '3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c0'
        '0a60b1ce1d7e819d7a431d7c90ea0e5f',
  ),
  (
    'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
        '5502f25dbf55296c3a545e3872760ab7',
    'c9e821b569d9d390a26167406d6d23d6070be242d765eb831625ceec4a0f473e'
        'f59f4e30e2817e6285bce2846f15f1a0',
  ),
  (
    'ffffffffaa63f1a239ac70197c6ebfcea5756dc012123f82c51fa874d66028be'
        '00e976a1080606737cc75c40bdfe4aac',
    'acbd85389088a62a6398384c22b52d492f23f46e4a27a4724ad55551da5c4834'
        '38095a247cb0c3378f1f52c3425ff9f1',
  ),
];

const _p384Vectors = <_Vector>[
  (
    id: 1, // ValidSignature
    key: 0,
    msg: '',
    sig: '3064023032401249714e9091f05a5e109d5c1216fdc05e98614261aa0dbd9e9c'
        'd4415dee29238afbd3b103c1e40ee5c9144aee0f02304326756fb2c4fd726360'
        'dd6479b5849478c7a9d054a833a58c1631c33b63c3441336ddf2c7fe0ed129aa'
        'e6d4ddfeb753',
    valid: true,
  ),
  (
    id: 2, // ValidSignature
    key: 0,
    msg: '4d7367',
    sig: '3066023100d7143a836608b25599a7f28dec6635494c2992ad1e2bbeecb7ef60'
        '1a9c01746e710ce0d9c48accb38a79ede5b9638f3402310080f9e165e8c61035'
        'bf8aa7b5533960e46dd0e211c904a064edb6de41f797c0eae4e327612ee3f816'
        'f4157272bb4fabc9',
    valid: true,
  ),
  (
    id: 152, // RangeCheck
    key: 1,
    msg: '313233343030',
    sig: '306602310112b30abef6b5476fe6b612ae557c0425661e26b44b1bfe19a25617'
        'aad7485e6312a8589714f647acf7a94cffbe8a724a023100e7bf25603e2d0707'
        '6ff30b7a2abec473da8b11c572b35fc631991d5de62ddca7525aaba89325dfd0'
        '4fecc47bff426f82',
    valid: false,
  ),
  (
    id: 168, // InvalidSignature
    key: 1,
    msg: '313233343030',
    sig: '3006020100020100',
    valid: false,
  ),
  (
    id: 295, // EdgeCaseShamirMultiplication
    key: 1,
    msg: '3133323237',
    sig: '3066023100ac042e13ab83394692019170707bc21dd3d7b8d233d11b65175708'
        '5bdd5767eabbb85322984f14437335de0cdf565684023100bd770d3ee4beadba'
        'be7ca46e8c4702783435228d46e2dd360e322fe61c86926fa49c8116ec940f72'
        'ac8c30d9beb3e12f',
    valid: true,
  ),
  (
    id: 296, // SpecialCaseHash
    key: 1,
    msg: '31373530353531383135',
    sig: '3066023100d3298a0193c4316b34e3833ff764a82cff4ef57b5dd79ed6237b51'
        'ff76ceab13bf92131f41030515b7e012d2ba857830023100bfc7518d2ad20ed5'
        'f58f3be79720f1866f7a23b3bd1bf913d3916819d008497a071046311d3c2fd0'
        '5fc284c964a39617',
    valid: true,
  ),
  (
    id: 382, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '304d0218389cb27e0bc8d21fa7e5f24cb74f58851313e696333ad68b023100ff'
        'ffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf58'
        '1a0db248b0a77aecec196accc52970',
    valid: true,
  ),
  (
    id: 383, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '3066023100ffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffeffffffff0000000000000000fffffffe023100ffffffffffffffff'
        'ffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77a'
        'ecec196accc52970',
    valid: false,
  ),
  (
    id: 384, // ArithmeticError
    key: 3,
    msg: '313233343030',
    sig: '3066023100ffffffffffffffffffffffffffffffffffffffffffffffffc7634d'
        '81f4372ddf581a0db248b0a77aecec196accc52972023100ffffffffffffffff'
        'ffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77a'
        'ecec196accc52971',
    valid: true,
  ),
  (
    id: 387, // SmallRandS
    key: 4,
    msg: '313233343030',
    sig: '3006020102020101',
    valid: true,
  ),
  (
    id: 407, // ModularInverse
    key: 5,
    msg: '313233343030',
    sig: '3064023055555555555555555555555555555555555555555555555542766f2b'
        '5167b9f51d5e0490c2e58d28f9a40878eeec63260230427f8227a67d94225576'
        '47d27945a90ae1d2ec2931f90113cd5b407099e3d8f5a889d62069e64c0e1c4e'
        'fe29690b0992',
    valid: true,
  ),
  (
    id: 422, // PointDuplication
    key: 6,
    msg: '313233343030',
    sig: '306402307fffffffffffffffffffffffffffffffffffffffffffffffe3b1a6c0'
        'fa1b96efac0d06d9245853bd76760cb5666294b9023055555555555555555555'
        '555555555555555555555555555542766f2b5167b9f51d5e0490c2e58d28f9a4'
        '0878eeec6326',
    valid: false,
  ),
  (
    id: 453, // PointDuplication
    key: 7,
    msg: '313233343030',
    sig: '3065023100b37699e0d518a4d370dbdaaaea3788850fa03f8186d1f78fdfbae6'
        '540aa670b31c8ada0fff3e737bd69520560fe0ce60023064adb4d51a93f96bed'
        '4665de2d4e1169cc95819ec6e9333edfd5c07ca134ceef7c95957b719ae349fc'
        '439eaa49fbbe34',
    valid: true,
  ),
  (
    id: 454, // PointDuplication
    key: 8,
    msg: '313233343030',
    sig: '3065023100b37699e0d518a4d370dbdaaaea3788850fa03f8186d1f78fdfbae6'
        '540aa670b31c8ada0fff3e737bd69520560fe0ce60023064adb4d51a93f96bed'
        '4665de2d4e1169cc95819ec6e9333edfd5c07ca134ceef7c95957b719ae349fc'
        '439eaa49fbbe34',
    valid: false,
  ),
  (
    id: 470, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '3065023100f9b127f0d81ebcd17b7ba0ea131c660d340b05ce557c82160e0f79'
        '3de07d38179023942871acb7002dfafdfffc8deace0230249249249249249249'
        '2492492492492492492492492492491c7be680477598d6c3716fabc13dcec86a'
        'fd2833d41c2a7e',
    valid: false,
  ),
  (
    id: 471, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '30640230064ed80f27e1432e84845f15ece399f2cbf4fa31aa837de9b953d444'
        '13b9f5c7c7f67989d703f07abef11b6ad0373ea5023024924924924924924924'
        '92492492492492492492492492491c7be680477598d6c3716fabc13dcec86afd'
        '2833d41c2a7e',
    valid: false,
  ),
  (
    id: 472, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '3065023100f9b127f0d81ebcd17b7ba0ea131c660d340b05ce557c82160e0f79'
        '3de07d38179023942871acb7002dfafdfffc8deace0230249249249249249249'
        '2492492492492492492492492492491c7be680477598d6c3716fabc13dcec86a'
        'fd2833d41c2a7e',
    valid: false,
  ),
  (
    id: 473, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '30640230064ed80f27e1432e84845f15ece399f2cbf4fa31aa837de9b953d444'
        '13b9f5c7c7f67989d703f07abef11b6ad0373ea5023024924924924924924924'
        '92492492492492492492492492491c7be680477598d6c3716fabc13dcec86afd'
        '2833d41c2a7e',
    valid: false,
  ),
  (
    id: 474, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '3065023007648b6660d01ba2520a09d298adf3b1a02c32744bd2877208f5a416'
        '2f6c984373139d800a4cdc1ffea15bce4871a0ed02310099fd367012cb9e02cd'
        'e2749455e0d495c52818f3c14f6e6aad105b0925e2a7290ac4a06d9fadf4b15b'
        '578556fe332a5f',
    valid: true,
  ),
  (
    id: 475, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '3065023100a049dcd96c72e4f36144a51bba30417b451a305dd01c9e30a5e04d'
        'f94342617dc383f17727708e3277cd7246ca44074102303970e264d85b228bf9'
        'e9b9c4947c5dd041ea8b5bde30b93aa59fedf2c428d3e2540a54e0530688accc'
        'b83ac7b29b79a2',
    valid: true,
  ),
];

const _p521Keys = <(String, String)>[
  (
    '12a908bfc5b70e17bdfae74294994808bf2a42dab59af8b0523a026d640a2a3d'
        '6d344520b62177e2cfa339ca42fb0883ec425904fbda2833a3b5b0a9a0081136'
        '5d8',
    '12333d532f8f8eb1a623c378a3694651192bbda833e3b8d7b8f90b2bfc9b045f'
        '8a55e1b6a5fe1512c400c4bc9c86fd7c699d642f5cee9bb827c8b0abc0da01ce'
        'f1e',
  ),
  (
    '5c6457ec088d532f482093965ae53ccd07e556ed59e2af945cd8c7a95c1c644f'
        '8a56a8a8a3cd77392ddd861e8a924dac99c69069093bd52a52fa6c56004a0745'
        '08',
    '7878d6d42e4b4dd1e9c0696cb3e19f63033c3db4e60d473259b3ebe079aaf0a9'
        '86ee6177f8217a78c68b813f7e149a4e56fd9562c07fed3d895942d7d101cb83'
        'f6',
  ),
  (
    '491cd6c5f93b7414d6d45cfe3d264bd077fc4427a4b0afede76cac537a7ca5ee'
        '2c44564258260f7691b81fdfecebfd03ba672277875c5b311ea920e74fb3978a'
        'f5',
    '144a353a251b4297894161bae12d16a89c33b719f904cfccc277df78cea53791'
        '98642fd549df919904dc0cf3662eeab01ef11b8e3cb49b51b853d98f042600c0'
        '997',
  ),
  (
    '15f281dcdc976641ce024dca1eac8ddd7f949e3290d3b2de11c4873f3676a06f'
        'f9f704c24813bd8d63528b2e813f78b869ff38112527e79b383a3bd527badb92'
        '9ff',
    '1502e4cc7032d3ec35b0f8d05409438a86966d623f7a2f432bf712f76dc63454'
        '05dfcfcdc36d477831d38eec64ede7f4d39aa91bffcc56ec4241cb06735b2809'
        'fbe',
  ),
  (
    '5e7eb6c4f481830abaad8a60ddb09891164ee418ea4cd2995062e227d33c229f'
        'b737bf330703097d6b3b69a3f09e79c9de0b402bf846dd26b5bb1191cff80135'
        '5d',
    '1789c9afda567e61de414437b0e93a17611e6e76853762bc0aff1e2bc9e46ce1'
        '285b931651d7129b85aef2c1fab1728e7eb4449b2956dec33e6cd7c9ba125c5c'
        'd9d',
  ),
  (
    '3877bf6711c3c088da9b4a18e6e9f5d2d6611fa56d67b5664a142a744aebd31a'
        'b4b85672fce0eed8006fec114afcd1f6eeced0c9751ac62a684840f7e0ba2928'
        'a1',
    '4055ce08f42ce5aeeac80a2536e75dd936785e6e38691092b030cd2261f5ebd9'
        'd1529a8cb85657d95e30febd37a7f5e523fda7780d56e27570ecb626a2570661'
        'ba',
  ),
  (
    '2a07f13f3e8df382145b7942fe6f91c12ff3064b314b4e3476bf3afbb982070f'
        '17f63b2de5fbe8c91a87ae632869facf17d5ce9d139b37ed557581bb9a7e4b8f'
        'a3',
    '24b904c5fc536ae53b323a7fd0b7b8e420302406ade84ea8a10ca7c5c934bad5'
        '489db6e3a8cc3064602cc83f309e9d247aae72afca08336bc8919e15f4be5ad7'
        '7a',
  ),
  (
    '16fce9f375bbd2968adaaf3575595129ef3e721c3b7c83d5a4a79f4b5dfbbdb1'
        'f66da7243e5120c5dbd7be1ca073e04b4cc58ca8ce2f34ff6a3d02a929bf2fc2'
        '797',
    '83f130792d6c45c8f2a67471e51246e2b8781465b8291cbda66d22719cd536bf'
        '801e0076030919d5701732ce7678bf472846ed0777937ed77caad74d05664614'
        'a2',
  ),
  (
    '16fce9f375bbd2968adaaf3575595129ef3e721c3b7c83d5a4a79f4b5dfbbdb1'
        'f66da7243e5120c5dbd7be1ca073e04b4cc58ca8ce2f34ff6a3d02a929bf2fc2'
        '797',
    '17c0ecf86d293ba370d598b8e1aedb91d4787eb9a47d6e3425992dd8e632ac94'
        '07fe1ff89fcf6e62a8fe8cd31898740b8d7b912f8886c8128835528b2fa99b9e'
        'b5d',
  ),
  (
    'c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3d'
        'baa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd'
        '66',
    '11839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e6'
        '62c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd16'
        '650',
  ),
  (
    'c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3d'
        'baa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd'
        '66',
    'e7c6d6958765c43ffba375a04bd382e426670abbb6a864bb97e85042e8d8c199'
        'd368118d66a10bd9bf3aaf46fec052f89ecac38f795d8d3dbf77416b89602e99'
        'af',
  ),
  (
    '304b3d071ed1ef302391b566af8c9d1cb7afe9aabc141ac39ab39676c63e48c1'
        'b2c6451eb460e452bd573e1fb5f15b8e5f9c03f634d8db6897285064b3ce9bd9'
        '8a',
    '9b98bfd33398c2cf8606fc0ae468b6d617ccb3e704af3b8506642a775d5b4da9'
        'd00209364a9f0a4ad77cbac604a015c97e6b5a18844a589a4f1c7d9625',
  ),
];

const _p521Vectors = <_Vector>[
  (
    id: 1, // ValidSignature
    key: 0,
    msg: '',
    sig: '308188024201625d6115092a8e2ee21b9f8a425aa73814dec8b2335e86150ab4'
        '229f5a3421d2e6256d632c7a4365a1ee01dd2a936921bbb4551a512d1d4b5a56'
        'c314e4a02534c5024201b792d23f2649862595451055777bda1b02dc6cc8fef2'
        '3231e44b921b16155cd42257441d75a790371e91819f0a9b1fd0ebd02c90b5b7'
        '74527746ed9bfe743dbe2f',
    valid: true,
  ),
  (
    id: 2, // ValidSignature
    key: 0,
    msg: '4d7367',
    sig: '30818602415adc833cbc1d6141ced457bab2b01b0814054d7a28fa8bb2925d1e'
        '7525b7cf7d5c938a17abfb33426dcc05ce8d44db02f53a75ea04017dca51e1fb'
        'b14ce3311b1402415f69b2a6de129147a8437b79c72315d35173d88c2d611908'
        '5c90dae8ec05c55e067e7dfa4f681035e3dccab099291c0ecf4428332a9cb073'
        '6d16e79111ac76d766',
    valid: true,
  ),
  (
    id: 151, // RangeCheck
    key: 1,
    msg: '313233343030',
    sig: '3081870242024e4223ee43e8cb89de3b1339ffc279e582f82c7ab0f71bbde43d'
        'be374ac75ffbe97b3367122fa4a20584c271233f3ec3b7f7b31b0faa4d340b92'
        'a6b0d5cd17ea4e024128b5d0926a4172b349b0fd2e929487a5edb94b142df923'
        'a697e7446acdacdba0a029e43d69111174dba2fe747122709a69ce69d5285e17'
        '4a01a93022fea8318ac1',
    valid: false,
  ),
  (
    id: 168, // InvalidSignature
    key: 1,
    msg: '313233343030',
    sig: '3006020100020100',
    valid: false,
  ),
  (
    id: 295, // EdgeCaseShamirMultiplication
    key: 1,
    msg: '39353032',
    sig: '308187024200b4b10646a668c385e1c4da613eb6592c0976fc4df843fc446f20'
        '673be5ac18c7d8608a943f019d96216254b09de5f20f3159402ced88ef805a41'
        '54f780e093e044024165cd4e7f2d8b752c35a62fc11a4ab745a91ca80698a226'
        'b41f156fb764b79f4d76548140eb94d2c477c0a9be3e1d4d1acbf9cf449701c1'
        '0bd47c2e3698b3287934',
    valid: true,
  ),
  (
    id: 296, // SpecialCaseHash
    key: 1,
    msg: '33393439313934313732',
    sig: '308188024201209e6f7b6f2f764261766d4106c3e4a43ac615f645f3ef5c7139'
        '651e86e4a177f9c2ab68027afbc6784ccb78d05c258a8b9b18fb1c0f28be4d02'
        '4da90738fbd374024201ade5d2cb6bf79d80583aeb11ac3254fc151fa3633055'
        '08a0f121457d00911f8f5ef6d4ec27460d26f3b56f4447f434ff9abe6a91e505'
        '5e7fe7707345e562983d64',
    valid: true,
  ),
  (
    id: 419, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '3067022105ae79787c40d069948033feb708f65a2fc44a36477663b851449048'
        'e16ec79bf5024201ffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47'
        'aebb6fb71e91386406',
    valid: true,
  ),
  (
    id: 420, // ArithmeticError
    key: 2,
    msg: '313233343030',
    sig: '308188024201ffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffe024201ffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b889'
        '9c47aebb6fb71e91386406',
    valid: false,
  ),
  (
    id: 421, // ArithmeticError
    key: 3,
    msg: '313233343030',
    sig: '308188024201ffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb'
        '6fb71e91386407024201ffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b889'
        '9c47aebb6fb71e91386406',
    valid: true,
  ),
  (
    id: 424, // SmallRandS
    key: 4,
    msg: '313233343030',
    sig: '3006020101020101',
    valid: true,
  ),
  (
    id: 444, // ModularInverse
    key: 5,
    msg: '313233343030',
    sig: '308187024200aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaa8c5d782813fba87792a9955c2fd033745693c9892d8896d3a3e'
        '7a925f85bd76ad02413766c66283b12cbccb593f39d32c356cb4ab940931bedf'
        '5d8053458cd26d03b1e9ba364d2056a8c3c7fd8b8f47ab8277adee9bc701ffe1'
        'fabde72a01dc098f76db',
    valid: true,
  ),
  (
    id: 459, // PointDuplication
    key: 6,
    msg: '313233343030',
    sig: '308188024200ffffffffffffffffffffffffffffffffffffffffffffffffffff'
        'fffffffffffffd28c343c1df97cb35bfe600a47b84d2e81ddae4dc44ce23d75d'
        'b7db8f489c3204024200aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaa8c5d782813fba87792a9955c2fd033745693c9892d8'
        '896d3a3e7a925f85bd76ad',
    valid: false,
  ),
  (
    id: 494, // PointDuplication
    key: 7,
    msg: '313233343030',
    sig: '30818802420090c8d0d718cb9d8d81094e6d068fb13c16b4df8c77bac676dddf'
        'e3e68855bed06b9ba8d0f8a80edce03a9fac7da561e24b1cd22d459239a14669'
        '5a671f81f73aaf024201150b0fe9f0dff27fa180cc9442c3bfc9e39523289860'
        '7b110a51bcb1086cb9726e251a07c9557808df32460715950a3dc446ae4229b9'
        'ed59fe241b389aee3a6963',
    valid: true,
  ),
  (
    id: 495, // PointDuplication
    key: 8,
    msg: '313233343030',
    sig: '30818802420090c8d0d718cb9d8d81094e6d068fb13c16b4df8c77bac676dddf'
        'e3e68855bed06b9ba8d0f8a80edce03a9fac7da561e24b1cd22d459239a14669'
        '5a671f81f73aaf024201150b0fe9f0dff27fa180cc9442c3bfc9e39523289860'
        '7b110a51bcb1086cb9726e251a07c9557808df32460715950a3dc446ae4229b9'
        'ed59fe241b389aee3a6963',
    valid: false,
  ),
  (
    id: 511, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '308185024043f800fbeaf9238c58af795bcdad04bc49cd850c394d3382953356'
        'b023210281757b30e19218a37cbd612086fbc158caa8b4e1acb2ec00837e5d94'
        '1f342fb3cc024149249249249249249249249249249249249249249249249249'
        '2492492492492491795c5c808906cc587ff89278234a8566e3f565f5ca840a3d'
        '887dac7214bee9b8',
    valid: false,
  ),
  (
    id: 512, // PointDuplication
    key: 9,
    msg: '313233343030',
    sig: '308187024201ffbc07ff041506dc73a75086a43252fb43b6327af3c6b2cc7d6a'
        'cca94fdcdefd78dc0b56a22d16f2eec26ae0c1fb484d059300e80bd6b0472b3d'
        '1222ff5d08b03d02414924924924924924924924924924924924924924924924'
        '92492492492492492491795c5c808906cc587ff89278234a8566e3f565f5ca84'
        '0a3d887dac7214bee9b8',
    valid: false,
  ),
  (
    id: 513, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '308185024043f800fbeaf9238c58af795bcdad04bc49cd850c394d3382953356'
        'b023210281757b30e19218a37cbd612086fbc158caa8b4e1acb2ec00837e5d94'
        '1f342fb3cc024149249249249249249249249249249249249249249249249249'
        '2492492492492491795c5c808906cc587ff89278234a8566e3f565f5ca840a3d'
        '887dac7214bee9b8',
    valid: false,
  ),
  (
    id: 514, // PointDuplication
    key: 10,
    msg: '313233343030',
    sig: '308187024201ffbc07ff041506dc73a75086a43252fb43b6327af3c6b2cc7d6a'
        'cca94fdcdefd78dc0b56a22d16f2eec26ae0c1fb484d059300e80bd6b0472b3d'
        '1222ff5d08b03d02414924924924924924924924924924924924924924924924'
        '92492492492492492491795c5c808906cc587ff89278234a8566e3f565f5ca84'
        '0a3d887dac7214bee9b8',
    valid: false,
  ),
  (
    id: 515, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '3081870242011c9684af6dc52728410473c63053b01c358d67e81f8a1324ad71'
        '1c60481a4a86dd3e75de20ca55ce7a9a39b1f82fd5da4fadf26a5bb8edd467af'
        '8825efe4746218024134c058aba6488d6943e11e0d1348429449ea17ac5edf8b'
        'caf654106b98b2ddf346c537b8a9a3f9b3174b77637d220ef5318dbbc33d0aac'
        '0fe2ddeda17b23cb2de6',
    valid: true,
  ),
  (
    id: 516, // EdgeCasePublicKey
    key: 11,
    msg: '4d657373616765',
    sig: '30818702417c47a668625648cd8a31ac92174cf3d61041f7ad292588def6ed14'
        '3b1ff9a288fd20cf36f58d4bfe4b2cd4a381d4da50c8eda5674f020449ae1d3d'
        'd77e44ed485e024201058e86b327d284e35bab49fc7c335417573f310afa9e1a'
        '53566e0fae516e099007965030f6f46b077116353f26cb466d1cf3f35300d744'
        'd2d8f883c8a31b43c20d',
    valid: true,
  ),
];

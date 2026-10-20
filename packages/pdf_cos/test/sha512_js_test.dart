// The 32-bit-halves SHA-384/512 that sha2_digest.dart selects under dart2js.
// It is imported directly, so the VM run checks it against package:crypto's
// native 64-bit implementation too. CI also runs this file under
// `dart test -p node`, where the R6 open below goes through it for real.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/src/crypto/sha2_digest.dart';
import 'package:pdf_cos/src/crypto/sha512_js.dart';
// Only the encrypted-fixture builder: the barrel also exports fixtures with
// 64-bit integer literals, which dart2js cannot compile.
// ignore: implementation_imports
import 'package:pdf_test_fixtures/src/encrypted.dart';
import 'package:test/test.dart';

void main() {
  Uint8List message(math.Random random, int length) =>
      Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));

  void expectMatchesPackage(Uint8List data) {
    expect(sha512Js(data), crypto.sha512.convert(data).bytes,
        reason: 'SHA-512 of ${data.length} bytes');
    expect(sha384Js(data), crypto.sha384.convert(data).bytes,
        reason: 'SHA-384 of ${data.length} bytes');
  }

  test('matches package:crypto for every length 0-300', () {
    // Covers the padding boundaries: 111 bytes is the longest message whose
    // 0x80 and 16-byte length still fit one 128-byte block, 112 spills into a
    // second, and 127/128 straddle a whole block.
    final random = math.Random(1);
    for (var length = 0; length <= 300; length++) {
      expectMatchesPackage(message(random, length));
    }
  });

  test('matches package:crypto for random lengths up to 20 KB', () {
    final random = math.Random(2);
    for (var i = 0; i < 60; i++) {
      expectMatchesPackage(message(random, random.nextInt(20 * 1024)));
    }
    // The 64x-repeated block sizes Algorithm 2.B hashes.
    for (final length in [1024, 2048, 3072, 4096, 5120, 6144, 7168]) {
      expectMatchesPackage(message(random, length));
    }
  });

  test('FIPS 180-4 "abc" vectors', () {
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    const abc = [0x61, 0x62, 0x63]; // 'abc'
    expect(
        hex(sha512Js(abc)),
        'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
        '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
    expect(
        hex(sha384Js(abc)),
        'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed'
        '8086072ba1e7cc2358baeca134c825a7');
  });

  test('sha2Digest keeps package:crypto for the other hashes', () {
    final data = message(math.Random(3), 1000);
    expect(sha2Digest(crypto.sha256, data), crypto.sha256.convert(data).bytes);
    expect(sha2Digest(crypto.sha1, data), crypto.sha1.convert(data).bytes);
    expect(sha2Digest(crypto.sha384, data), crypto.sha384.convert(data).bytes);
    expect(sha2Digest(crypto.sha512, data), crypto.sha512.convert(data).bytes);
  });

  test('Algorithm 2.B derives the same hash either way', () {
    // The revision 6 hash, with its SHA-384/512 arms taken from package:crypto
    // or from the halves implementation.
    Uint8List hash2B(List<int> password, List<int> salt, List<int> extra,
        {required bool halves}) {
      var k = crypto.sha256.convert([...password, ...salt, ...extra]).bytes;
      var e = const <int>[];
      for (var round = 0; round < 64 || e.last > round - 32; round++) {
        final part = [...password, ...k, ...extra];
        final k1 = Uint8List(part.length * 64);
        for (var i = 0; i < 64; i++) {
          k1.setRange(i * part.length, (i + 1) * part.length, part);
        }
        e = Aes(k.sublist(0, 16)).cbcEncrypt(k.sublist(16, 32), k1);
        var sum = 0;
        for (var i = 0; i < 16; i++) {
          sum += e[i];
        }
        k = switch (sum % 3) {
          0 => crypto.sha256.convert(e).bytes,
          1 => halves ? sha384Js(e) : crypto.sha384.convert(e).bytes,
          _ => halves ? sha512Js(e) : crypto.sha512.convert(e).bytes,
        };
      }
      return Uint8List.fromList(k.sublist(0, 32));
    }

    final random = math.Random(4);
    for (var i = 0; i < 12; i++) {
      final password = message(random, random.nextInt(24));
      final salt = message(random, 8);
      // Owner-password checks hash the 48-byte /U in as well.
      final extra = i.isOdd ? message(random, 48) : Uint8List(0);
      expect(hash2B(password, salt, extra, halves: true),
          hash2B(password, salt, extra, halves: false));
    }
  });

  group('an AES-256 (R6) document opens and decrypts', () {
    void expectDecrypted(CosDocument doc) {
      expect(doc.encryption!.revision, 6);
      final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
      final page = doc.resolve((doc.resolve(pages['Kids']) as CosArray)[0])
          as CosDictionary;
      final contents = doc.resolve(page['Contents']) as CosStream;
      expect(latin1.decode(doc.decodeStreamData(contents)),
          'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET');
    }

    test('with the empty user password', () {
      expectDecrypted(CosDocument.open(buildEncryptedPdf(revision: 6)));
    });

    test('with a user password and with the owner password', () {
      final bytes = buildEncryptedPdf(
          revision: 6, userPassword: 'hunter2', ownerPassword: 'admin');
      expectDecrypted(CosDocument.open(bytes, password: 'hunter2'));
      expectDecrypted(CosDocument.open(bytes, password: 'admin'));
      expect(() => CosDocument.open(bytes, password: 'wrong'),
          throwsA(isA<CosPasswordException>()));
    });
  });
}

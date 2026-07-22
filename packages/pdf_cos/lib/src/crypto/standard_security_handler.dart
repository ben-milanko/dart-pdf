import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../exceptions.dart';
import '../objects.dart';
import 'aes.dart';
import 'rc4.dart';

/// Which cipher a class of content (strings or streams) uses.
enum PdfCipher { none, rc4, aes128, aes256 }

/// The standard security handler (§7.6.4): authenticates a password and
/// decrypts strings and streams.
///
/// Supported: V1/V2 (RC4, 40–128 bit), V4 crypt filters (/V2 and /AESV2),
/// and V5 (/AESV3, AES-256) for both revision 6 (ISO 32000-2) and the
/// deprecated Adobe revision 5. Public-key (/Adobe.PubSec) handlers are
/// not supported.
class StandardSecurityHandler {
  StandardSecurityHandler._({
    required this.revision,
    required Uint8List fileKey,
    required this.stringCipher,
    required this.streamCipher,
    required this.encryptMetadata,
  }) : _fileKey = fileKey;

  final int revision;
  final Uint8List _fileKey;
  final PdfCipher stringCipher;
  final PdfCipher streamCipher;
  final bool encryptMetadata;

  static final _padding = Uint8List.fromList([
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, //
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ]);

  /// Builds a handler from a parsed /Encrypt dictionary, authenticating
  /// [password] first as the user and then as the owner password.
  ///
  /// Throws [UnsupportedEncryptionException] for non-standard handlers and
  /// [CosPasswordException] when the password (often the empty default)
  /// opens neither door.
  factory StandardSecurityHandler.fromEncrypt(
    CosDictionary encrypt,
    Uint8List? firstId,
    String password,
    CosObject Function(CosObject?) resolve,
  ) {
    final filter = resolve(encrypt['Filter']);
    if (filter is CosName && filter.value != 'Standard') {
      throw UnsupportedEncryptionException('security handler ${filter.value}');
    }
    int intOf(String key, int fallback) {
      final value = resolve(encrypt[key]);
      return value is CosInteger ? value.value : fallback;
    }

    Uint8List bytesOf(String key) {
      final value = resolve(encrypt[key]);
      return value is CosString ? value.bytes : Uint8List(0);
    }

    final v = intOf('V', 0);
    final revision = intOf('R', v <= 1 ? 2 : 3);
    final o = bytesOf('O');
    final u = bytesOf('U');
    final p = intOf('P', -1);
    final lengthBits = intOf('Length', 40);
    final em = resolve(encrypt['EncryptMetadata']);
    final encryptMetadata = em is! CosBoolean || em.value;

    // V4/V5: crypt filters say what strings and streams actually use
    var stringCipher = PdfCipher.rc4;
    var streamCipher = PdfCipher.rc4;
    if (v == 4 || v == 5) {
      PdfCipher cipherFor(String key) {
        final name = resolve(encrypt[key]);
        if (name is! CosName || name.value == 'Identity') {
          return PdfCipher.none;
        }
        final cf = resolve(encrypt['CF']);
        final filter = cf is CosDictionary ? resolve(cf[name.value]) : null;
        final method =
            filter is CosDictionary ? resolve(filter['CFM']) : null;
        return switch (method is CosName ? method.value : '') {
          'V2' => PdfCipher.rc4,
          'AESV2' => PdfCipher.aes128,
          'AESV3' => PdfCipher.aes256,
          'None' => PdfCipher.none,
          final m => throw UnsupportedEncryptionException('crypt filter $m'),
        };
      }

      stringCipher = cipherFor('StrF');
      streamCipher = cipherFor('StmF');
    } else if (v != 1 && v != 2) {
      throw UnsupportedEncryptionException('/V $v');
    }

    final Uint8List fileKey;
    if (revision >= 5) {
      fileKey = _authenticateAes256(
          encrypt, password, o, u, revision, resolve);
    } else {
      fileKey = _authenticateClassic(password, o, u, p, revision,
          v == 1 ? 40 : lengthBits, firstId ?? Uint8List(0), encryptMetadata);
    }

    return StandardSecurityHandler._(
      revision: revision,
      fileKey: fileKey,
      stringCipher: stringCipher,
      streamCipher: streamCipher,
      encryptMetadata: encryptMetadata,
    );
  }

  // ---------- R2–R4: RC4/AES-128 password algorithms ----------

  static Uint8List _pad(String password) {
    final bytes = latin1.encode(password);
    final out = Uint8List(32);
    final n = math.min(32, bytes.length);
    out.setRange(0, n, bytes);
    out.setRange(n, 32, _padding);
    return out;
  }

  /// Algorithm 2: password + /O + /P + /ID → file key.
  static Uint8List _computeClassicKey(
    Uint8List paddedPassword,
    Uint8List o,
    int p,
    int revision,
    int lengthBits,
    Uint8List firstId,
    bool encryptMetadata,
  ) {
    final input = BytesBuilder()
      ..add(paddedPassword)
      ..add(o.length >= 32 ? o.sublist(0, 32) : o)
      ..add([p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF, (p >> 24) & 0xFF])
      ..add(firstId);
    if (revision >= 4 && !encryptMetadata) {
      input.add([0xFF, 0xFF, 0xFF, 0xFF]);
    }
    var hash = md5.convert(input.takeBytes()).bytes;
    final n = revision == 2 ? 5 : (lengthBits ~/ 8).clamp(5, 16);
    if (revision >= 3) {
      for (var i = 0; i < 50; i++) {
        hash = md5.convert(hash.sublist(0, n)).bytes;
      }
    }
    return Uint8List.fromList(hash.sublist(0, n));
  }

  /// Algorithms 4/5: does [key] reproduce /U for this revision?
  static bool _checkUser(
      Uint8List key, Uint8List u, int revision, Uint8List firstId) {
    if (revision == 2) {
      final expected = rc4(key, _padding);
      return u.length >= 32 && _equal(expected, u.sublist(0, 32));
    }
    final hash = md5.convert([..._padding, ...firstId]).bytes;
    var cipher = rc4(key, Uint8List.fromList(hash));
    for (var i = 1; i <= 19; i++) {
      final stepKey = [for (final b in key) b ^ i];
      cipher = rc4(stepKey, cipher);
    }
    return u.length >= 16 && _equal(cipher.sublist(0, 16), u.sublist(0, 16));
  }

  static Uint8List _authenticateClassic(
    String password,
    Uint8List o,
    Uint8List u,
    int p,
    int revision,
    int lengthBits,
    Uint8List firstId,
    bool encryptMetadata,
  ) {
    // try as the user password
    var key = _computeClassicKey(_pad(password), o, p, revision, lengthBits,
        firstId, encryptMetadata);
    if (_checkUser(key, u, revision, firstId)) return key;

    // try as the owner password (Algorithm 7): decrypt /O into the user
    // password, then authenticate that
    var hash = md5.convert(_pad(password)).bytes;
    if (revision >= 3) {
      for (var i = 0; i < 50; i++) {
        hash = md5.convert(hash).bytes;
      }
    }
    final n = revision == 2 ? 5 : (lengthBits ~/ 8).clamp(5, 16);
    final ownerKey = Uint8List.fromList(hash.sublist(0, n));
    var userPadded = o.length >= 32 ? o.sublist(0, 32) : o;
    if (revision == 2) {
      userPadded = rc4(ownerKey, Uint8List.fromList(userPadded));
    } else {
      for (var i = 19; i >= 0; i--) {
        final stepKey = [for (final b in ownerKey) b ^ i];
        userPadded = rc4(stepKey, Uint8List.fromList(userPadded));
      }
    }
    key = _computeClassicKey(Uint8List.fromList(userPadded), o, p, revision,
        lengthBits, firstId, encryptMetadata);
    if (_checkUser(key, u, revision, firstId)) return key;

    throw CosPasswordException();
  }

  // ---------- R5/R6: AES-256 password algorithms ----------

  static Uint8List _authenticateAes256(
    CosDictionary encrypt,
    String password,
    Uint8List o,
    Uint8List u,
    int revision,
    CosObject Function(CosObject?) resolve,
  ) {
    Uint8List bytesOf(String key) {
      final value = resolve(encrypt[key]);
      return value is CosString ? value.bytes : Uint8List(0);
    }

    if (o.length < 48 || u.length < 48) throw CosPasswordException();
    // UTF-8, truncated to 127 bytes (SASLprep is not applied)
    var pwd = utf8.encode(password);
    if (pwd.length > 127) pwd = pwd.sublist(0, 127);

    Uint8List hash(List<int> password, List<int> salt, List<int> extra) =>
        revision == 5
            ? Uint8List.fromList(
                sha256.convert([...password, ...salt, ...extra]).bytes)
            : _hash2B(password, salt, extra);

    // user password? validation salt is U[32..40), key salt U[40..48)
    if (_equal(hash(pwd, u.sublist(32, 40), const []), u.sublist(0, 32))) {
      final intermediate = hash(pwd, u.sublist(40, 48), const []);
      final ue = bytesOf('UE');
      if (ue.length >= 32) {
        return Aes(intermediate).cbcDecrypt(Uint8List(16), ue.sublist(0, 32));
      }
    }
    // owner password? hashed with the full 48-byte /U appended
    final u48 = u.sublist(0, 48);
    if (_equal(hash(pwd, o.sublist(32, 40), u48), o.sublist(0, 32))) {
      final intermediate = hash(pwd, o.sublist(40, 48), u48);
      final oe = bytesOf('OE');
      if (oe.length >= 32) {
        return Aes(intermediate).cbcDecrypt(Uint8List(16), oe.sublist(0, 32));
      }
    }
    throw CosPasswordException();
  }

  /// Algorithm 2.B (ISO 32000-2): the hardened SHA-2 hash for revision 6.
  static Uint8List _hash2B(
      List<int> password, List<int> salt, List<int> extra) {
    var k = sha256.convert([...password, ...salt, ...extra]).bytes;
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
        0 => sha256.convert(e).bytes,
        1 => sha384.convert(e).bytes,
        _ => sha512.convert(e).bytes,
      };
    }
    return Uint8List.fromList(k.sublist(0, 32));
  }

  // ---------- object-graph operations ----------

  /// Whether [stream]'s payload is actually encrypted, per the exempt-stream
  /// policy shared by loading and saving: cross-reference streams are never
  /// encrypted (§7.5.8.2), /Metadata is exempt under /EncryptMetadata false,
  /// and a /Crypt filter whose /Name is /Identity (or absent - the default)
  /// marks the bytes as already plain. [resolve] follows indirect dictionary
  /// entries (/Type, /Filter, /DecodeParms).
  bool streamPayloadIsEncrypted(
      CosStream stream, CosObject Function(CosObject?) resolve) {
    final dict = stream.dictionary;
    final type = resolve(dict['Type']);
    if (type is CosName && type.value == 'XRef') return false;
    if (type is CosName && type.value == 'Metadata' && !encryptMetadata) {
      return false;
    }
    final filter = resolve(dict['Filter']);
    final hasCrypt = filter is CosName && filter.value == 'Crypt' ||
        filter is CosArray &&
            filter.items.any((f) {
              final name = resolve(f);
              return name is CosName && name.value == 'Crypt';
            });
    if (hasCrypt) {
      var parms = resolve(dict['DecodeParms']);
      if (parms is CosArray && filter is CosArray) {
        // aligned with the filter array; find the /Crypt slot
        final slots = parms;
        parms = CosNull.instance;
        for (var i = 0; i < filter.items.length && i < slots.length; i++) {
          final name = resolve(filter.items[i]);
          if (name is CosName && name.value == 'Crypt') {
            parms = resolve(slots[i]);
            break;
          }
        }
      }
      if (parms is! CosDictionary) return false;
      final name = resolve(parms['Name']);
      return name is CosName && name.value != 'Identity';
    }
    return true;
  }

  /// Decrypts every string in [object]'s graph in place under the
  /// ([objectNumber], [generation]) key. References are leaves, so a single
  /// indirect object's graph is a tree. A stream's payload is left as raw
  /// file bytes for lazy decoding (see [decryptStream]); only its
  /// dictionary strings are touched here.
  void decryptObjectGraph(
      CosObject object, int objectNumber, int generation) {
    switch (object) {
      case CosArray():
        for (var i = 0; i < object.items.length; i++) {
          final item = object.items[i];
          if (item is CosString) {
            object.items[i] = CosString(
                decryptString(item.bytes, objectNumber, generation),
                isHex: item.isHex);
          } else {
            decryptObjectGraph(item, objectNumber, generation);
          }
        }
      case CosDictionary():
        for (final key in object.entries.keys.toList()) {
          final value = object.entries[key]!;
          if (value is CosString) {
            object.entries[key] = CosString(
                decryptString(value.bytes, objectNumber, generation),
                isHex: value.isHex);
          } else {
            decryptObjectGraph(value, objectNumber, generation);
          }
        }
      case CosStream():
        decryptObjectGraph(object.dictionary, objectNumber, generation);
      default:
        break;
    }
  }

  /// Deep-copies [object] with every string and non-exempt stream payload
  /// encrypted under the ([objectNumber], [generation]) key, leaving the
  /// original graph untouched so later edits in the same session keep their
  /// plaintext. A stream whose [keepsFileCiphertext] reports its payload as
  /// still the file's original bytes passes through verbatim (it is already
  /// ciphertext); exempt streams (cross-reference, unencrypted /Metadata,
  /// /Crypt-Identity - see [streamPayloadIsEncrypted]) stay plain. [resolve]
  /// follows indirect dictionary entries for the exempt-policy check.
  CosObject encryptObjectGraph(
    CosObject object,
    int objectNumber,
    int generation, {
    required CosObject Function(CosObject?) resolve,
    required bool Function(CosStream) keepsFileCiphertext,
  }) {
    CosObject copy(CosObject value) {
      switch (value) {
        case CosString():
          return CosString(
              encryptString(value.bytes, objectNumber, generation),
              isHex: value.isHex);
        case CosArray():
          return CosArray([for (final item in value.items) copy(item)]);
        case CosStream():
          final dict = copy(value.dictionary) as CosDictionary;
          if (keepsFileCiphertext(value) ||
              !streamPayloadIsEncrypted(value, resolve)) {
            return CosStream(dict, value.rawBytes);
          }
          final cipher =
              encryptStream(value.rawBytes, objectNumber, generation);
          dict['Length'] = CosInteger(cipher.length);
          return CosStream(dict, cipher);
        case CosDictionary():
          final out = CosDictionary();
          value.entries.forEach((key, v) => out[key] = copy(v));
          return out;
        default:
          return value;
      }
    }

    return copy(object);
  }

  // ---------- per-object decryption ----------

  Uint8List decryptString(Uint8List data, int objectNumber, int generation) =>
      _decrypt(stringCipher, data, objectNumber, generation);

  Uint8List decryptStream(Uint8List data, int objectNumber, int generation) =>
      _decrypt(streamCipher, data, objectNumber, generation);

  // ---------- per-object encryption (encrypt-on-write) ----------

  /// Generates the random IV for each AES payload. Swappable so tests can
  /// produce deterministic output; never reuse an IV in production.
  static Uint8List Function() randomIv = _secureRandomIv;

  static Uint8List _secureRandomIv() {
    final rng = math.Random.secure();
    return Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
  }

  Uint8List encryptString(Uint8List data, int objectNumber, int generation) =>
      _encrypt(stringCipher, data, objectNumber, generation);

  Uint8List encryptStream(Uint8List data, int objectNumber, int generation) =>
      _encrypt(streamCipher, data, objectNumber, generation);

  Uint8List _encrypt(
      PdfCipher cipher, Uint8List data, int objectNumber, int generation) {
    switch (cipher) {
      case PdfCipher.none:
        return data;
      case PdfCipher.rc4:
        return rc4(_objectKey(objectNumber, generation, aes: false), data);
      case PdfCipher.aes128:
        return Aes.encryptContent(
            _objectKey(objectNumber, generation, aes: true),
            data,
            randomIv());
      case PdfCipher.aes256:
        return Aes.encryptContent(_fileKey, data, randomIv());
    }
  }

  Uint8List _decrypt(
      PdfCipher cipher, Uint8List data, int objectNumber, int generation) {
    switch (cipher) {
      case PdfCipher.none:
        return data;
      case PdfCipher.rc4:
        return rc4(_objectKey(objectNumber, generation, aes: false), data);
      case PdfCipher.aes128:
        return Aes.decryptContent(
            _objectKey(objectNumber, generation, aes: true), data);
      case PdfCipher.aes256:
        return Aes.decryptContent(_fileKey, data);
    }
  }

  // Memo for the most recent [_objectKey] derivation.
  //
  // One entry is enough because the access pattern is strictly per-object:
  // decryptObjectGraph / encryptObjectGraph walk one indirect object's whole
  // graph under a fixed (objectNumber, generation), so every string in that
  // object asks for the same key. A 50-string object cost 50 MD5s over the
  // file key; it now costs one. A wider cache would grow with the object
  // count for no additional hit rate.
  int? _memoObject;
  int? _memoGeneration;
  bool? _memoAes;
  Uint8List? _memoKey;

  /// Algorithm 1: file key + object number and generation (+ the AES salt).
  /// AES-256 (R5/R6) uses the file key directly.
  Uint8List _objectKey(int objectNumber, int generation,
      {required bool aes}) {
    if (_memoObject == objectNumber &&
        _memoGeneration == generation &&
        _memoAes == aes) {
      return _memoKey!;
    }
    final key = _deriveObjectKey(objectNumber, generation, aes: aes);
    _memoObject = objectNumber;
    _memoGeneration = generation;
    _memoAes = aes;
    _memoKey = key;
    return key;
  }

  Uint8List _deriveObjectKey(int objectNumber, int generation,
      {required bool aes}) {
    final input = BytesBuilder()
      ..add(_fileKey)
      ..add([
        objectNumber & 0xFF,
        (objectNumber >> 8) & 0xFF,
        (objectNumber >> 16) & 0xFF,
        generation & 0xFF,
        (generation >> 8) & 0xFF,
      ]);
    if (aes) input.add(const [0x73, 0x41, 0x6C, 0x54]); // 'sAlT'
    final hash = md5.convert(input.takeBytes()).bytes;
    return Uint8List.fromList(
        hash.sublist(0, math.min(_fileKey.length + 5, 16)));
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

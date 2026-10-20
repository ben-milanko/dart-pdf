/// Writer-side standard security handler, enough to build encrypted test
/// fixtures. The /O, /U, /OE, /UE entries are re-derived from the spec
/// here (only the vector-pinned cipher primitives are shared with the
/// reader), so a round-trip failure points at a real algorithm bug.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf_cos/pdf_cos.dart' show Aes, rc4;

final _pad = Uint8List.fromList([
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, //
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
]);

final _fileId = Uint8List.fromList(List.generate(16, (i) => i * 13 & 0xFF));

const _p = -44;

Uint8List _padded(String password) {
  final bytes = latin1.encode(password);
  final out = Uint8List(32);
  final n = bytes.length > 32 ? 32 : bytes.length;
  out.setRange(0, n, bytes);
  out.setRange(n, 32, _pad);
  return out;
}

String _hex(List<int> bytes) =>
    '<${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>';

/// Algorithm 3: the /O entry.
Uint8List _ownerEntry(String owner, String user, int revision, int n) {
  var hash = md5.convert(_padded(owner.isEmpty ? user : owner)).bytes;
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      hash = md5.convert(hash).bytes;
    }
  }
  final key = hash.sublist(0, n);
  var out = _padded(user);
  if (revision == 2) {
    out = rc4(key, out);
  } else {
    for (var i = 0; i < 20; i++) {
      out = rc4([for (final b in key) b ^ i], out);
    }
  }
  return out;
}

/// Algorithm 2: the file key from the user password.
Uint8List _fileKey(String user, Uint8List o, int revision, int n,
    {bool encryptMetadata = true}) {
  final input = [
    ..._padded(user),
    ...o,
    _p & 0xFF, (_p >> 8) & 0xFF, (_p >> 16) & 0xFF, (_p >> 24) & 0xFF,
    ..._fileId,
    // Algorithm 2 step (f): revision 4+ folds in 0xFFFFFFFF when metadata
    // is left unencrypted.
    if (revision >= 4 && !encryptMetadata) ...[0xFF, 0xFF, 0xFF, 0xFF],
  ];
  var hash = md5.convert(input).bytes;
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      hash = md5.convert(hash.sublist(0, n)).bytes;
    }
  }
  return Uint8List.fromList(hash.sublist(0, n));
}

/// Algorithms 4/5: the /U entry.
Uint8List _userEntry(Uint8List key, int revision) {
  if (revision == 2) return rc4(key, _pad);
  final hash = md5.convert([..._pad, ..._fileId]).bytes;
  var cipher = rc4(key, Uint8List.fromList(hash));
  for (var i = 1; i <= 19; i++) {
    cipher = rc4([for (final b in key) b ^ i], cipher);
  }
  return Uint8List.fromList([...cipher, ...Uint8List(16)]);
}

/// Algorithm 1: per-object key.
Uint8List _objectKey(Uint8List fileKey, int number, int generation,
    {required bool aes}) {
  final input = [
    ...fileKey,
    number & 0xFF, (number >> 8) & 0xFF, (number >> 16) & 0xFF,
    generation & 0xFF, (generation >> 8) & 0xFF,
    if (aes) ...const [0x73, 0x41, 0x6C, 0x54],
  ];
  final hash = md5.convert(input).bytes;
  final n = fileKey.length + 5 > 16 ? 16 : fileKey.length + 5;
  return Uint8List.fromList(hash.sublist(0, n));
}

Uint8List _aesPayload(Uint8List key, Uint8List iv, List<int> plain) {
  final padLength = 16 - plain.length % 16;
  final padded = Uint8List.fromList(
      [...plain, for (var i = 0; i < padLength; i++) padLength]);
  return Uint8List.fromList([...iv, ...Aes(key).cbcEncrypt(iv, padded)]);
}

/// Algorithm 2.B, writer side (revision 6).
Uint8List _hash2B(List<int> password, List<int> salt, List<int> extra) {
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

/// Builds an encrypted one-page PDF ("Hello, world!" plus an /Info whose
/// /Title is the encrypted string "Secret Title").
///
/// [revision] selects the scheme:
/// - 2 - RC4 40-bit (V1)
/// - 3 - RC4 128-bit (V2)
/// - 4 - AES-128 via the /AESV2 crypt filter (V4)
/// - 6 - AES-256 via /AESV3 (V5, ISO 32000-2)
///
/// [encryptMetadata] false emits `/EncryptMetadata false` and folds the
/// Algorithm 2 step (f) `0xFFFFFFFF` into the key; only honoured for
/// revision 4 (the classic key derivation that considers the flag).
Uint8List buildEncryptedPdf({
  int revision = 3,
  String userPassword = '',
  String ownerPassword = 'owner',
  bool encryptMetadata = true,
}) {
  const title = 'Secret Title';
  const content = 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET';
  final iv = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));

  final Uint8List fileKey;
  final String encryptDict;
  if (revision == 6) {
    fileKey = Uint8List.fromList(List.generate(32, (i) => i * 7 + 3 & 0xFF));
    final pwd = utf8.encode(userPassword);
    final vSalt = Uint8List.fromList(List.generate(8, (i) => 0x11 * (i + 1) & 0xFF));
    final kSalt = Uint8List.fromList(List.generate(8, (i) => 0x21 * (i + 1) & 0xFF));
    final u = Uint8List.fromList(
        [..._hash2B(pwd, vSalt, const []), ...vSalt, ...kSalt]);
    final ue = Aes(_hash2B(pwd, kSalt, const []))
        .cbcEncrypt(Uint8List(16), fileKey);
    final opwd = utf8.encode(ownerPassword);
    final ovSalt = Uint8List.fromList(List.generate(8, (i) => 0x31 * (i + 1) & 0xFF));
    final okSalt = Uint8List.fromList(List.generate(8, (i) => 0x41 * (i + 1) & 0xFF));
    final o = Uint8List.fromList(
        [..._hash2B(opwd, ovSalt, u), ...ovSalt, ...okSalt]);
    final oe = Aes(_hash2B(opwd, okSalt, u)).cbcEncrypt(Uint8List(16), fileKey);
    // /Perms: P (little-endian), 0xFFFFFFFF, 'T' (metadata encrypted),
    // 'adb', 4 filler bytes - one AES block, zero-IV CBC == ECB
    final perms = Aes(fileKey).cbcEncrypt(
        Uint8List(16),
        Uint8List.fromList([
          _p & 0xFF, (_p >> 8) & 0xFF, (_p >> 16) & 0xFF, (_p >> 24) & 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF,
          0x54, 0x61, 0x64, 0x62, 0, 0, 0, 0,
        ]));
    encryptDict = '<< /Filter /Standard /V 5 /R 6 /Length 256 /P $_p '
        '/O ${_hex(o)} /U ${_hex(u)} /OE ${_hex(oe)} /UE ${_hex(ue)} '
        '/Perms ${_hex(perms)} '
        '/CF << /StdCF << /CFM /AESV3 /Length 32 >> >> '
        '/StmF /StdCF /StrF /StdCF >>';
  } else {
    final n = revision == 2 ? 5 : 16;
    final o = _ownerEntry(ownerPassword, userPassword, revision, n);
    fileKey =
        _fileKey(userPassword, o, revision, n, encryptMetadata: encryptMetadata);
    final u = _userEntry(fileKey, revision);
    final common = '/Filter /Standard /P $_p /O ${_hex(o)} /U ${_hex(u)}';
    final metadataEntry = encryptMetadata ? '' : ' /EncryptMetadata false';
    encryptDict = switch (revision) {
      2 => '<< $common /V 1 /R 2 >>',
      3 => '<< $common /V 2 /R 3 /Length 128 >>',
      _ => '<< $common /V 4 /R 4 /Length 128$metadataEntry '
          '/CF << /StdCF << /CFM /AESV2 /Length 16 >> >> '
          '/StmF /StdCF /StrF /StdCF >>',
    };
  }

  Uint8List encrypt(List<int> plain, int number) {
    if (revision == 6) {
      return _aesPayload(fileKey, iv, plain);
    }
    if (revision == 4) {
      return _aesPayload(_objectKey(fileKey, number, 0, aes: true), iv, plain);
    }
    return rc4(_objectKey(fileKey, number, 0, aes: false),
        Uint8List.fromList(plain));
  }

  // object 4 is the content stream, object 6 the /Info dictionary
  final cipherContent = encrypt(latin1.encode(content), 4);
  final cipherTitle = encrypt(latin1.encode(title), 6);

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${cipherContent.length} >>\nstream\n'
        '${String.fromCharCodes(cipherContent)}\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Title ${_hex(cipherTitle)} >>',
    encryptDict,
  ];

  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  final id = _hex(_fileId);
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
        '/Info 6 0 R /Encrypt 7 0 R /ID [$id $id] >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  final out = buffer.toString();
  return Uint8List.fromList([for (final c in out.codeUnits) c & 0xFF]);
}

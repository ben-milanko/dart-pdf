import 'dart:typed_data';

/// AES block cipher (FIPS 197) with the CBC modes PDF encryption needs
/// (§7.6.2, §7.6.4.3): content decryption (16-byte IV prefix, PKCS#7
/// padding) and the unpadded CBC encryption inside the AES-256 password
/// hash (Algorithm 2.B). Pure Dart so it runs on the VM and the web.
///
/// Word-oriented (the classic "T-table" formulation): the state is four
/// big-endian 32-bit columns held in locals, and each inner round is sixteen
/// lookups into tables that combine SubBytes, ShiftRows and MixColumns
/// (`_te*`, `_td*`). That is about 7x the throughput of byte-at-a-time
/// rounds, natively and under dart2js - it matters because every AES stream
/// a render worker decodes and every Algorithm 2.B open runs through here.
/// Only `>>>`, `&` and `^` on 32-bit values, so dart2js computes the same
/// bytes as the VM.
class Aes {
  /// Key must be 16, 24, or 32 bytes.
  Aes(List<int> key)
      : assert(key.length == 16 || key.length == 24 || key.length == 32),
        _rounds = key.length ~/ 4 + 6,
        _roundKeys = _expandKey(key);

  final int _rounds;
  final Uint32List _roundKeys;

  /// Round keys for the equivalent inverse cipher (FIPS 197 §5.3.5). Built
  /// on the first decrypt only, so encrypt-only users (Algorithm 2.B builds
  /// a fresh cipher per round) never pay for them.
  late final Uint32List _decryptKeys = _equivalentInverseKeys();

  // --- CBC convenience entry points ---

  /// Decrypts a PDF content payload: leading 16-byte IV, then ciphertext.
  /// PKCS#7 padding is stripped leniently (real files get it wrong);
  /// payloads too short or misaligned yield empty/truncated output rather
  /// than throwing.
  static Uint8List decryptContent(List<int> key, Uint8List data) {
    if (data.length < 32) return Uint8List(0);
    final blocks = (data.length - 16) & ~15;
    final plain = Aes(key).cbcDecrypt(Uint8List.sublistView(data, 0, 16),
        Uint8List.sublistView(data, 16, 16 + blocks));
    final pad = plain.isEmpty ? 0 : plain.last;
    return pad >= 1 && pad <= 16
        ? Uint8List.sublistView(plain, 0, plain.length - pad)
        : plain;
  }

  /// Encrypts a PDF content payload: PKCS#7-pads [data], prepends the
  /// 16-byte [iv], CBC-encrypts. The inverse of [decryptContent].
  static Uint8List encryptContent(List<int> key, Uint8List data, List<int> iv) {
    final padLength = 16 - (data.length % 16);
    final padded = Uint8List(data.length + padLength)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + padLength, padLength);
    return (BytesBuilder(copy: false)
          ..add(Uint8List.fromList(iv))
          ..add(Aes(key).cbcEncrypt(iv, padded)))
        .takeBytes();
  }

  /// Encrypts with CBC and no padding; [data] must be block-aligned.
  /// Used by Algorithm 2.B and by test fixtures (with PKCS#7 applied by
  /// the caller).
  Uint8List cbcEncrypt(List<int> iv, Uint8List data) {
    assert(data.length % 16 == 0);
    final out = Uint8List(data.length);
    // nothing to chain: don't touch the IV (a short one only ever threw
    // when a block used it)
    if (out.isEmpty) return out;
    final rk = _roundKeys;
    final rounds = _rounds;
    final t0 = _te0, t1 = _te1, t2 = _te2, t3 = _te3, sb = _sbox;
    // the chaining value: the IV, then each ciphertext block as written
    var p0 = _ivWord(iv, 0), p1 = _ivWord(iv, 4);
    var p2 = _ivWord(iv, 8), p3 = _ivWord(iv, 12);
    for (var off = 0; off < data.length; off += 16) {
      var s0 = _word(data, off) ^ p0 ^ rk[0];
      var s1 = _word(data, off + 4) ^ p1 ^ rk[1];
      var s2 = _word(data, off + 8) ^ p2 ^ rk[2];
      var s3 = _word(data, off + 12) ^ p3 ^ rk[3];
      var k = 4;
      for (var r = 1; r < rounds; r++) {
        final a0 = t0[s0 >>> 24] ^
            t1[(s1 >>> 16) & 0xFF] ^
            t2[(s2 >>> 8) & 0xFF] ^
            t3[s3 & 0xFF] ^
            rk[k];
        final a1 = t0[s1 >>> 24] ^
            t1[(s2 >>> 16) & 0xFF] ^
            t2[(s3 >>> 8) & 0xFF] ^
            t3[s0 & 0xFF] ^
            rk[k + 1];
        final a2 = t0[s2 >>> 24] ^
            t1[(s3 >>> 16) & 0xFF] ^
            t2[(s0 >>> 8) & 0xFF] ^
            t3[s1 & 0xFF] ^
            rk[k + 2];
        final a3 = t0[s3 >>> 24] ^
            t1[(s0 >>> 16) & 0xFF] ^
            t2[(s1 >>> 8) & 0xFF] ^
            t3[s2 & 0xFF] ^
            rk[k + 3];
        s0 = a0;
        s1 = a1;
        s2 = a2;
        s3 = a3;
        k += 4;
      }
      p0 = _lastRound(sb, s0, s1, s2, s3) ^ rk[k];
      p1 = _lastRound(sb, s1, s2, s3, s0) ^ rk[k + 1];
      p2 = _lastRound(sb, s2, s3, s0, s1) ^ rk[k + 2];
      p3 = _lastRound(sb, s3, s0, s1, s2) ^ rk[k + 3];
      _put(out, off, p0);
      _put(out, off + 4, p1);
      _put(out, off + 8, p2);
      _put(out, off + 12, p3);
    }
    return out;
  }

  /// Decrypts with CBC and no padding; [data] must be block-aligned.
  Uint8List cbcDecrypt(List<int> iv, Uint8List data) {
    assert(data.length % 16 == 0);
    final out = Uint8List(data.length);
    if (out.isEmpty) return out;
    final dk = _decryptKeys;
    final rounds = _rounds;
    final t0 = _td0, t1 = _td1, t2 = _td2, t3 = _td3, sb = _invSbox;
    // the previous ciphertext block, kept as words: no per-block copy
    var p0 = _ivWord(iv, 0), p1 = _ivWord(iv, 4);
    var p2 = _ivWord(iv, 8), p3 = _ivWord(iv, 12);
    for (var off = 0; off < data.length; off += 16) {
      final c0 = _word(data, off), c1 = _word(data, off + 4);
      final c2 = _word(data, off + 8), c3 = _word(data, off + 12);
      var s0 = c0 ^ dk[0], s1 = c1 ^ dk[1], s2 = c2 ^ dk[2], s3 = c3 ^ dk[3];
      var k = 4;
      for (var r = 1; r < rounds; r++) {
        final a0 = t0[s0 >>> 24] ^
            t1[(s3 >>> 16) & 0xFF] ^
            t2[(s2 >>> 8) & 0xFF] ^
            t3[s1 & 0xFF] ^
            dk[k];
        final a1 = t0[s1 >>> 24] ^
            t1[(s0 >>> 16) & 0xFF] ^
            t2[(s3 >>> 8) & 0xFF] ^
            t3[s2 & 0xFF] ^
            dk[k + 1];
        final a2 = t0[s2 >>> 24] ^
            t1[(s1 >>> 16) & 0xFF] ^
            t2[(s0 >>> 8) & 0xFF] ^
            t3[s3 & 0xFF] ^
            dk[k + 2];
        final a3 = t0[s3 >>> 24] ^
            t1[(s2 >>> 16) & 0xFF] ^
            t2[(s1 >>> 8) & 0xFF] ^
            t3[s0 & 0xFF] ^
            dk[k + 3];
        s0 = a0;
        s1 = a1;
        s2 = a2;
        s3 = a3;
        k += 4;
      }
      _put(out, off, _lastRound(sb, s0, s3, s2, s1) ^ dk[k] ^ p0);
      _put(out, off + 4, _lastRound(sb, s1, s0, s3, s2) ^ dk[k + 1] ^ p1);
      _put(out, off + 8, _lastRound(sb, s2, s1, s0, s3) ^ dk[k + 2] ^ p2);
      _put(out, off + 12, _lastRound(sb, s3, s2, s1, s0) ^ dk[k + 3] ^ p3);
      p0 = c0;
      p1 = c1;
      p2 = c2;
      p3 = c3;
    }
    return out;
  }

  // --- word helpers ---

  /// Big-endian word at [o]. A misaligned tail reads past the end and
  /// throws, as the byte-wise implementation did.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  static int _word(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Big-endian IV word. The IV is any `List<int>`; only each element's low
  /// byte counts, exactly as when it was XORed into a byte buffer.
  static int _ivWord(List<int> iv, int o) =>
      ((iv[o] & 0xFF) << 24) |
      ((iv[o + 1] & 0xFF) << 16) |
      ((iv[o + 2] & 0xFF) << 8) |
      (iv[o + 3] & 0xFF);

  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  static void _put(Uint8List out, int o, int w) {
    out[o] = w >>> 24;
    out[o + 1] = (w >>> 16) & 0xFF;
    out[o + 2] = (w >>> 8) & 0xFF;
    out[o + 3] = w & 0xFF;
  }

  /// The final round's SubBytes (or InvSubBytes, per [sb]) with the row
  /// shift folded in: byte 0 of the result from [a], 1 from [b], 2 from
  /// [c], 3 from [d].
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  static int _lastRound(Uint8List sb, int a, int b, int c, int d) =>
      (sb[a >>> 24] << 24) |
      (sb[(b >>> 16) & 0xFF] << 16) |
      (sb[(c >>> 8) & 0xFF] << 8) |
      sb[d & 0xFF];

  /// The encryption schedule reversed, with InvMixColumns applied to the
  /// inner round keys so decryption rounds have the same table shape as
  /// encryption ones. `_td*[_sbox[x]]` is InvMixColumns of the byte x in
  /// the matching row, since InvSubBytes undoes the S-box.
  Uint32List _equivalentInverseKeys() {
    final ek = _roundKeys;
    final rounds = _rounds;
    final dk = Uint32List(ek.length);
    for (var c = 0; c < 4; c++) {
      dk[c] = ek[rounds * 4 + c];
      dk[rounds * 4 + c] = ek[c];
    }
    for (var r = 1; r < rounds; r++) {
      for (var c = 0; c < 4; c++) {
        final w = ek[(rounds - r) * 4 + c];
        dk[r * 4 + c] = _td0[_sbox[w >>> 24]] ^
            _td1[_sbox[(w >>> 16) & 0xFF]] ^
            _td2[_sbox[(w >>> 8) & 0xFF]] ^
            _td3[_sbox[w & 0xFF]];
      }
    }
    return dk;
  }

  static Uint32List _expandKey(List<int> key) {
    final nk = key.length ~/ 4;
    final rounds = nk + 6;
    final w = Uint32List(4 * (rounds + 1));
    for (var i = 0; i < nk; i++) {
      w[i] = (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }
    var rcon = 1;
    for (var i = nk; i < w.length; i++) {
      var t = w[i - 1];
      if (i % nk == 0) {
        t = _subWord((t << 8) | (t >>> 24)) ^ (rcon << 24);
        rcon = _xtime(rcon);
      } else if (nk > 6 && i % nk == 4) {
        t = _subWord(t);
      }
      w[i] = w[i - nk] ^ t;
    }
    return w;
  }

  static int _subWord(int w) =>
      (_sbox[(w >>> 24) & 0xFF] << 24) |
      (_sbox[(w >>> 16) & 0xFF] << 16) |
      (_sbox[(w >>> 8) & 0xFF] << 8) |
      _sbox[w & 0xFF];

  // --- GF(2^8) tables, computed once at first use ---

  static int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1B : 0)) & 0xFF;

  static int _gfMul(int a, int b) {
    var result = 0;
    while (b != 0) {
      if (b & 1 != 0) result ^= a;
      a = _xtime(a);
      b >>= 1;
    }
    return result;
  }

  static final Uint8List _sbox = _buildSbox();
  static final Uint8List _invSbox = () {
    final inv = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      inv[_sbox[i]] = i;
    }
    return inv;
  }();

  static Uint8List _buildSbox() {
    // multiplicative inverses via the 3/0xF6 generator trick, then the
    // affine transform from FIPS 197 §5.1.1
    final box = Uint8List(256);
    var p = 1, q = 1;
    do {
      p = _gfMul(p, 3);
      q = _gfMul(q, 0xF6); // 3⁻¹
      var x = q;
      x ^= (q << 1) | (q >> 7);
      x ^= (q << 2) | (q >> 6);
      x ^= (q << 3) | (q >> 5);
      x ^= (q << 4) | (q >> 4);
      box[p] = (x ^ 0x63) & 0xFF;
    } while (p != 1);
    box[0] = 0x63;
    return box;
  }

  // Round tables, 1 KB each. _te0[x] is the MixColumns column of the
  // S-boxed byte, rows (2s, s, s, 3s); _td0[x] the InvMixColumns column of
  // the inverse-S-boxed byte, rows (14i, 9i, 13i, 11i). _te1..3 / _td1..3
  // are the same words rotated right by 8/16/24 bits - the column position
  // the byte lands in after ShiftRows.
  static final Uint32List _te0 = _roundTable(_sbox, 2, 1, 1, 3);
  static final Uint32List _te1 = _rotate(_te0, 8);
  static final Uint32List _te2 = _rotate(_te0, 16);
  static final Uint32List _te3 = _rotate(_te0, 24);
  static final Uint32List _td0 = _roundTable(_invSbox, 14, 9, 13, 11);
  static final Uint32List _td1 = _rotate(_td0, 8);
  static final Uint32List _td2 = _rotate(_td0, 16);
  static final Uint32List _td3 = _rotate(_td0, 24);

  static Uint32List _roundTable(Uint8List box, int m0, int m1, int m2, int m3) {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      final s = box[i];
      table[i] = (_gfMul(s, m0) << 24) |
          (_gfMul(s, m1) << 16) |
          (_gfMul(s, m2) << 8) |
          _gfMul(s, m3);
    }
    return table;
  }

  static Uint32List _rotate(Uint32List table, int bits) {
    final out = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      final w = table[i];
      out[i] = (w >>> bits) | ((w << (32 - bits)) & 0xFFFFFFFF);
    }
    return out;
  }
}

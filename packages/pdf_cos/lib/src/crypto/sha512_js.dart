import 'dart:typed_data';

/// One-shot SHA-384 and SHA-512 (FIPS 180-4) for dart2js, where JavaScript has
/// no 64-bit integers.
///
/// package:crypto's web build emulates every 64-bit add, shift and rotate
/// through `Uint32List` helper calls ("slow sinks"): about 4-5 MB/s, some 20x
/// slower than its native build. That made SHA-384/512 about 85% of an
/// AES-256 (R6) document open in the browser, since Algorithm 2.B hashes
/// roughly 280 KB with them per open. This keeps each 64-bit word as a high
/// and a low 32-bit half in locals, rotates with `>>>`/`<<`/`|` across the
/// pair, and carries the low half's overflow into the high half by dividing
/// by 2^32: about 60 MB/s under dart2js.
///
/// Web only (see `sha2_digest.dart`): the native VM's package:crypto runs on
/// real 64-bit integers and is faster than this there. Bit-exact against
/// package:crypto on both platforms (`test/sha512_js_test.dart`).
Uint8List sha512Js(List<int> message) => _digest(message, _iv512, 64);

/// SHA-384: SHA-512 from a different initial hash value, truncated to 48
/// bytes. See [sha512Js].
Uint8List sha384Js(List<int> message) => _digest(message, _iv384, 48);

/// The 80 round constants as (high, low) 32-bit halves.
final Uint32List _k = Uint32List.fromList(const [
  0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f, //
  0xe9b5dba5, 0x8189dbbc, 0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019,
  0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118, 0xd807aa98, 0xa3030242,
  0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
  0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1, 0x9bdc06a7, 0x25c71235,
  0xc19bf174, 0xcf692694, 0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3,
  0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65, 0x2de92c6f, 0x592b0275,
  0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
  0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f,
  0xbf597fc7, 0xbeef0ee4, 0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725,
  0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70, 0x27b70a85, 0x46d22ffc,
  0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
  0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6,
  0x92722c85, 0x1482353b, 0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001,
  0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30, 0xd192e819, 0xd6ef5218,
  0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
  0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53, 0x2748774c, 0xdf8eeb99,
  0x34b0bcb5, 0xe19b48a8, 0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb,
  0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3, 0x748f82ee, 0x5defb2fc,
  0x78a5636f, 0x43172f60, 0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
  0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915,
  0xc67178f2, 0xe372532b, 0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207,
  0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178, 0x06f067aa, 0x72176fba,
  0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
  0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc,
  0x431d67c4, 0x9c100d4c, 0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a,
  0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817,
]);

const _iv512 = [
  0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b, 0x3c6ef372, 0xfe94f82b, //
  0xa54ff53a, 0x5f1d36f1, 0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f,
  0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179,
];

const _iv384 = [
  0xcbbb9d5d, 0xc1059ed8, 0x629a292a, 0x367cd507, 0x9159015a, 0x3070dd17, //
  0x152fecd8, 0xf70e5939, 0x67332667, 0xffc00b31, 0x8eb44a87, 0x68581511,
  0xdb0c2e0d, 0x64f98fa7, 0x47b5481d, 0xbefa4fa4,
];

/// The 80-word message schedule as (high, low) halves, reused by every block
/// (the digest is synchronous, so it is never shared between two calls).
final Uint32List _w = Uint32List(160);

const double _two32 = 4294967296.0;

Uint8List _digest(List<int> message, List<int> iv, int outLength) {
  final h = Uint32List.fromList(iv);
  final k = _k;
  final w = _w;
  final n = message.length;
  // The message, a 0x80 byte, zeros, and the 128-bit big-endian bit length,
  // padded to whole 128-byte blocks.
  final padded = Uint8List(((n + 17 + 127) >> 7) << 7)..setRange(0, n, message);
  padded[n] = 0x80;
  final data = ByteData.sublistView(padded);
  final bitLength = n * 8;
  data.setUint32(padded.length - 8, (bitLength / _two32).floor());
  data.setUint32(padded.length - 4, bitLength & 0xFFFFFFFF);
  for (var offset = 0; offset < padded.length; offset += 128) {
    for (var i = 0; i < 32; i++) {
      w[i] = data.getUint32(offset + i * 4);
    }
    // Stores into the Uint32List truncate each half to 32 bits; the `&`
    // masks do the same for the native VM's wider intermediate values.
    for (var i = 16; i < 80; i++) {
      var xh = w[(i - 15) * 2], xl = w[(i - 15) * 2 + 1];
      final s0h =
          ((xh >>> 1) | (xl << 31)) ^ ((xh >>> 8) | (xl << 24)) ^ (xh >>> 7);
      final s0l = ((xl >>> 1) | (xh << 31)) ^
          ((xl >>> 8) | (xh << 24)) ^
          ((xl >>> 7) | (xh << 25));
      xh = w[(i - 2) * 2];
      xl = w[(i - 2) * 2 + 1];
      final s1h =
          ((xh >>> 19) | (xl << 13)) ^ ((xl >>> 29) | (xh << 3)) ^ (xh >>> 6);
      final s1l = ((xl >>> 19) | (xh << 13)) ^
          ((xh >>> 29) | (xl << 3)) ^
          ((xl >>> 6) | (xh << 26));
      final lo = (s0l & 0xFFFFFFFF) +
          (s1l & 0xFFFFFFFF) +
          w[(i - 7) * 2 + 1] +
          w[(i - 16) * 2 + 1];
      final hi = (s0h & 0xFFFFFFFF) +
          (s1h & 0xFFFFFFFF) +
          w[(i - 7) * 2] +
          w[(i - 16) * 2] +
          (lo / _two32).floor();
      w[i * 2] = hi;
      w[i * 2 + 1] = lo;
    }
    var ah = h[0], al = h[1], bh = h[2], bl = h[3];
    var ch = h[4], cl = h[5], dh = h[6], dl = h[7];
    var eh = h[8], el = h[9], fh = h[10], fl = h[11];
    var gh = h[12], gl = h[13], hh = h[14], hl = h[15];
    for (var i = 0; i < 80; i++) {
      final s1h = ((eh >>> 14) | (el << 18)) ^
          ((eh >>> 18) | (el << 14)) ^
          ((el >>> 9) | (eh << 23));
      final s1l = ((el >>> 14) | (eh << 18)) ^
          ((el >>> 18) | (eh << 14)) ^
          ((eh >>> 9) | (el << 23));
      final chh = (eh & fh) ^ (~eh & gh);
      final chl = (el & fl) ^ (~el & gl);
      final t1l = hl +
          (s1l & 0xFFFFFFFF) +
          (chl & 0xFFFFFFFF) +
          k[i * 2 + 1] +
          w[i * 2 + 1];
      final t1h = hh +
          (s1h & 0xFFFFFFFF) +
          (chh & 0xFFFFFFFF) +
          k[i * 2] +
          w[i * 2] +
          (t1l / _two32).floor();
      final s0h = ((ah >>> 28) | (al << 4)) ^
          ((al >>> 2) | (ah << 30)) ^
          ((al >>> 7) | (ah << 25));
      final s0l = ((al >>> 28) | (ah << 4)) ^
          ((ah >>> 2) | (al << 30)) ^
          ((ah >>> 7) | (al << 25));
      final mjh = (ah & bh) ^ (ah & ch) ^ (bh & ch);
      final mjl = (al & bl) ^ (al & cl) ^ (bl & cl);
      final t2l = (s0l & 0xFFFFFFFF) + (mjl & 0xFFFFFFFF);
      final t2h =
          (s0h & 0xFFFFFFFF) + (mjh & 0xFFFFFFFF) + (t2l / _two32).floor();
      hh = gh;
      hl = gl;
      gh = fh;
      gl = fl;
      fh = eh;
      fl = el;
      final el2 = dl + (t1l & 0xFFFFFFFF);
      eh = (dh + t1h + (el2 / _two32).floor()) & 0xFFFFFFFF;
      el = el2 & 0xFFFFFFFF;
      dh = ch;
      dl = cl;
      ch = bh;
      cl = bl;
      bh = ah;
      bl = al;
      final al2 = (t1l & 0xFFFFFFFF) + (t2l & 0xFFFFFFFF);
      ah = (t1h + t2h + (al2 / _two32).floor()) & 0xFFFFFFFF;
      al = al2 & 0xFFFFFFFF;
    }
    _addWord(h, 0, ah, al);
    _addWord(h, 2, bh, bl);
    _addWord(h, 4, ch, cl);
    _addWord(h, 6, dh, dl);
    _addWord(h, 8, eh, el);
    _addWord(h, 10, fh, fl);
    _addWord(h, 12, gh, gl);
    _addWord(h, 14, hh, hl);
  }
  final out = Uint8List(64);
  final outData = ByteData.sublistView(out);
  for (var i = 0; i < 16; i++) {
    outData.setUint32(i * 4, h[i]);
  }
  return outLength == 64 ? out : Uint8List.sublistView(out, 0, outLength);
}

/// Adds the 64-bit word ([high], [low]) into [h] at word [i] (mod 2^64).
void _addWord(Uint32List h, int i, int high, int low) {
  final lo = h[i + 1] + low;
  h[i] = h[i] + high + (lo / _two32).floor();
  h[i + 1] = lo;
}

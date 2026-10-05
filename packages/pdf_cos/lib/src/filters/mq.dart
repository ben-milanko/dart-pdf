/// The MQ arithmetic decoder of JBIG2 and JPEG 2000 (ITU-T T.88
/// Annex E / T.800 Annex C), with the JBIG2 Annex A integer decoders.
library;

import 'dart:typed_data';

/// Adaptive contexts for the arithmetic integer decoder (Annex A).
class MqIntContext {
  final Int8List mps = Int8List(512);
  final Uint8List index = Uint8List(512);
}

/// The MQ arithmetic decoder (Annex E).
class MqDecoder {
  MqDecoder(this.data) {
    _bp = 0;
    _c = (_byte(_bp)) << 16;
    _byteIn();
    _c = (_c << 7) & 0xFFFFFFFF;
    _ct -= 7;
    _a = 0x8000;
  }

  final Uint8List data;
  late int _bp;
  int _c = 0;
  int _a = 0;
  int _ct = 0;

  int _byte(int index) => index < data.length ? data[index] : 0xFF;

  void _byteIn() {
    if (_byte(_bp) == 0xFF) {
      if (_byte(_bp + 1) > 0x8F) {
        _c += 0xFF00;
        _ct = 8;
      } else {
        _bp++;
        _c += _byte(_bp) << 9;
        _ct = 7;
      }
    } else {
      _bp++;
      _c += _byte(_bp) << 8;
      _ct = 8;
    }
    _c &= 0xFFFFFFFF;
  }

  static const _qe = [
    (0x5601, 1, 1, 1), (0x3401, 2, 6, 0), (0x1801, 3, 9, 0), //
    (0x0AC1, 4, 12, 0), (0x0521, 5, 29, 0), (0x0221, 38, 33, 0),
    (0x5601, 7, 6, 1), (0x5401, 8, 14, 0), (0x4801, 9, 14, 0),
    (0x3801, 10, 14, 0), (0x3001, 11, 17, 0), (0x2401, 12, 18, 0),
    (0x1C01, 13, 20, 0), (0x1601, 29, 21, 0), (0x5601, 15, 14, 1),
    (0x5401, 16, 14, 0), (0x5101, 17, 15, 0), (0x4801, 18, 16, 0),
    (0x3801, 19, 17, 0), (0x3401, 20, 18, 0), (0x3001, 21, 19, 0),
    (0x2801, 22, 19, 0), (0x2401, 23, 20, 0), (0x2201, 24, 21, 0),
    (0x1C01, 25, 22, 0), (0x1801, 26, 23, 0), (0x1601, 27, 24, 0),
    (0x1401, 28, 25, 0), (0x1201, 29, 26, 0), (0x1101, 30, 27, 0),
    (0x0AC1, 31, 28, 0), (0x09C1, 32, 29, 0), (0x08A1, 33, 30, 0),
    (0x0521, 34, 31, 0), (0x0441, 35, 32, 0), (0x02A1, 36, 33, 0),
    (0x0221, 37, 34, 0), (0x0141, 38, 35, 0), (0x0111, 39, 36, 0),
    (0x0085, 40, 37, 0), (0x0049, 41, 38, 0), (0x0025, 42, 39, 0),
    (0x0015, 43, 40, 0), (0x0009, 44, 41, 0), (0x0005, 45, 42, 0),
    (0x0001, 45, 43, 0), (0x5601, 46, 46, 0),
  ];

  // [_qe] split into flat typed tables: [decode] runs once per coded bit of
  // every JBIG2 generic region and JPEG 2000 code block, and reading a record
  // out of a const list costs a field load per component on every call.
  static final Uint16List _qeValue =
      Uint16List.fromList([for (final e in _qe) e.$1]);
  static final Uint8List _qeNmps =
      Uint8List.fromList([for (final e in _qe) e.$2]);
  static final Uint8List _qeNlps =
      Uint8List.fromList([for (final e in _qe) e.$3]);
  static final Uint8List _qeSwitch =
      Uint8List.fromList([for (final e in _qe) e.$4]);

  /// Decodes one bit in [cx] using per-context state arrays.
  int decode(Int8List mpsTable, Uint8List indexTable, int cx) {
    final i = indexTable[cx];
    final mps = mpsTable[cx];
    final qe = _qeValue[i];

    var a = _a - qe;
    var c = _c;
    int d;
    if ((c >> 16) < qe) {
      if (a < qe) {
        d = mps;
        indexTable[cx] = _qeNmps[i];
      } else {
        d = 1 - mps;
        if (_qeSwitch[i] == 1) mpsTable[cx] = 1 - mps;
        indexTable[cx] = _qeNlps[i];
      }
      a = qe;
    } else {
      c -= qe << 16;
      if (a & 0x8000 != 0) {
        _a = a;
        _c = c;
        return mps;
      }
      if (a < qe) {
        d = 1 - mps;
        if (_qeSwitch[i] == 1) mpsTable[cx] = 1 - mps;
        indexTable[cx] = _qeNlps[i];
      } else {
        d = mps;
        indexTable[cx] = _qeNmps[i];
      }
    }
    var ct = _ct;
    do {
      if (ct == 0) {
        _c = c;
        _byteIn();
        c = _c;
        ct = _ct;
      }
      a = (a << 1) & 0xFFFF;
      c = (c << 1) & 0xFFFFFFFF;
      ct--;
    } while (a & 0x8000 == 0);
    _a = a;
    _c = c;
    _ct = ct;
    return d;
  }

  /// Arithmetic integer decoding (Annex A.2). Null is OOB.
  int? decodeInt(MqIntContext context) {
    var prev = 1;
    int bit() {
      final b = decode(context.mps, context.index, prev);
      prev = prev < 256 ? (prev << 1) | b : ((((prev << 1) | b) & 511) | 256);
      return b;
    }

    final sign = bit();
    int value;
    if (bit() == 0) {
      value = (bit() << 1) | bit();
    } else if (bit() == 0) {
      value = ((((bit() << 1) | bit()) << 1 | bit()) << 1 | bit()) + 4;
    } else if (bit() == 0) {
      value = 0;
      for (var i = 0; i < 6; i++) {
        value = (value << 1) | bit();
      }
      value += 20;
    } else if (bit() == 0) {
      value = 0;
      for (var i = 0; i < 8; i++) {
        value = (value << 1) | bit();
      }
      value += 84;
    } else if (bit() == 0) {
      value = 0;
      for (var i = 0; i < 12; i++) {
        value = (value << 1) | bit();
      }
      value += 340;
    } else {
      value = 0;
      for (var i = 0; i < 32; i++) {
        value = (value << 1) | bit();
      }
      value += 4436;
    }
    if (sign == 1 && value == 0) return null; // OOB
    return sign == 1 ? -value : value;
  }

  /// IAID decoding: a [codeLength]-bit symbol id.
  int decodeId(Int8List mpsTable, Uint8List indexTable, int codeLength) {
    var prev = 1;
    for (var i = 0; i < codeLength; i++) {
      prev = (prev << 1) | decode(mpsTable, indexTable, prev);
    }
    return prev - (1 << codeLength);
  }
}

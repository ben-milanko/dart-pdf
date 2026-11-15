// Runs on the VM and under dart2js (`dart test -p node`, as CI does). The
// `web` group imports the web implementation directly, so the VM run covers
// it too; under node, `inflateZlib` itself is that implementation, so the
// FlateFilter and CosCompactor groups exercise the path browsers run.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/src/filters/zlib_inflate_io.dart' as io;
import 'package:pdf_cos/src/filters/zlib_inflate_web.dart' as web;
import 'package:test/test.dart';

void main() {
  final text = _text(20000);
  final encoded = _zlib(text);

  group('web inflateZlib', () {
    test('decodes what zlib encodes, at every level', () {
      final samples = {
        'text': text,
        // distance-1 runs: overlapping back-references
        'run': Uint8List.fromList(List.filled(5000, 0x41)),
        // 300 random bytes repeated: long matches that do not overlap
        'repeat': Uint8List.fromList(
            [for (var i = 0; i < 20; i++) ..._noise(300, seed: 7)]),
        'noise': _noise(4000),
        'empty': Uint8List(0),
      };
      for (final MapEntry(key: name, value: data) in samples.entries) {
        for (final level in [0, 1, 6, 9]) {
          final zlib = _zlib(data, level: level);
          for (final strict in [false, true]) {
            expect(web.inflateZlib(zlib, strict: strict), data,
                reason: '$name at level $level, strict: $strict');
          }
        }
      }
    });

    test('ignores bytes after the Adler-32', () {
      for (final tail in [
        [0x0a],
        [0x0d, 0x0a],
        [0x0d],
        [0x20, 0x0a, 0x25, 0x25],
        [0x78, 0x9c], // even something that looks like another header
      ]) {
        final withTail = Uint8List.fromList([...encoded, ...tail]);
        expect(web.inflateZlib(withTail), text, reason: 'tail $tail');
        expect(web.inflateZlib(withTail, strict: true), text,
            reason: 'strict, tail $tail');
      }
    });

    test('tolerates a missing or partial Adler-32 unless strict', () {
      for (final cut in [4, 2, 1]) {
        final short = Uint8List.sublistView(encoded, 0, encoded.length - cut);
        expect(web.inflateZlib(short), text, reason: 'without $cut bytes');
        expect(
            () => web.inflateZlib(short, strict: true), throwsFormatException,
            reason: 'strict, without $cut bytes');
      }
    });

    test('strict rejects a wrong Adler-32 and a truncated body', () {
      final badSum = Uint8List.fromList(encoded);
      badSum[badSum.length - 1] ^= 1;
      expect(web.inflateZlib(badSum), text);
      expect(
          () => web.inflateZlib(badSum, strict: true), throwsFormatException);

      final truncated = Uint8List.sublistView(encoded, 0, encoded.length ~/ 2);
      expect(() => web.inflateZlib(truncated), returnsNormally);
      expect(() => web.inflateZlib(truncated, strict: true),
          throwsFormatException);
    });

    test('keeps the empty result for a header that is not zlib', () {
      final body = encoded.sublist(2);
      final notZlib = {
        'method 9': [0x79, 0x9c, ...body],
        'bad FCHECK': [0x78, 0x9d, ...body],
        'preset dictionary': [0x78, 0xbb, 0, 0, 0, 1, ...body],
        'raw deflate': body.sublist(0, body.length - 4),
        'one byte': [0x78],
      };
      for (final MapEntry(key: name, value: bytes) in notZlib.entries) {
        final data = Uint8List.fromList(bytes);
        // No raw-deflate leniency the VM's native zlib does not have.
        expect(web.inflateZlib(data), isEmpty, reason: name);
        expect(() => web.inflateZlib(data, strict: true), throwsFormatException,
            reason: 'strict, $name');
      }
    });

    test('does not keep a buffer much larger than its result', () {
      // Stored blocks barely shrink, so the 4x size hint overshoots.
      final stored = _zlib(_noise(50000), level: 0);
      final inflated = web.inflateZlib(stored);
      expect(inflated.length, 50000);
      expect(
          inflated.buffer.lengthInBytes, lessThanOrEqualTo(50000 * 17 ~/ 16));
    });

    test('agrees with the platform decoder on well-formed streams', () {
      for (final data in [text, _noise(9000), Uint8List(0)]) {
        for (final level in [0, 6]) {
          final zlib = _zlib(data, level: level);
          expect(web.inflateZlib(zlib), inflateZlib(zlib));
        }
      }
    });
  });

  // The decoder every FlateDecode stream goes through on this platform: the
  // native one on the VM (which collects zlib's output in pieces and joins
  // them once), the pure-Dart one under dart2js.
  group('inflateZlib', () {
    test('decodes outputs far larger than one piece of native output', () {
      final samples = {
        'text': _text(3 << 20),
        'noise': _noise(1 << 20),
        'run': Uint8List(2 << 20)..fillRange(0, 2 << 20, 0x41),
      };
      for (final MapEntry(key: name, value: data) in samples.entries) {
        for (final level in [0, 1, 6]) {
          final inflated = inflateZlib(_zlib(data, level: level));
          // length first: a mismatch should not print megabytes
          expect(inflated.length, data.length, reason: '$name at $level');
          expect(_same(inflated, data), isTrue, reason: '$name at $level');
        }
      }
    });

    test('returns a buffer of its own, no larger than it needs', () {
      for (final data in [
        Uint8List(0),
        _text(10),
        _text(20000),
        _noise(50000),
        _text(1 << 20),
      ]) {
        for (final level in [0, 6]) {
          final zlib = _zlib(data, level: level);
          final first = inflateZlib(zlib);
          expect(first.buffer.lengthInBytes,
              lessThanOrEqualTo(data.length * 17 ~/ 16),
              reason: '${data.length} bytes at level $level');
          // A decoded stream is cached and shared; a second decode must not
          // hand out memory the first one still owns.
          final second = inflateZlib(zlib);
          if (first.isNotEmpty) {
            first[0] ^= 0xff;
            expect(second[0], data[0]);
          }
          expect(_same(second, data), isTrue);
        }
      }
    });

    test('is not confused by input that is a view into a larger buffer', () {
      final padded = Uint8List.fromList([9, 9, 9, ...encoded, 7, 7, 7, 7]);
      final view = Uint8List.sublistView(padded, 3, 3 + encoded.length);
      expect(inflateZlib(view), text);
    });

    test('ignores bytes after the stream', () {
      for (final tail in [
        [0x0a],
        [0x0d, 0x0a],
        _noise(5000, seed: 3),
      ]) {
        final withTail = Uint8List.fromList([...encoded, ...tail]);
        expect(inflateZlib(withTail), text, reason: '${tail.length} bytes');
      }
    });

    test('keeps what a truncated stream decoded, unless strict', () {
      final big = _text(1 << 20);
      final zlib = _zlib(big);
      final truncated = Uint8List.sublistView(zlib, 0, zlib.length ~/ 2);
      final partial = inflateZlib(truncated);
      expect(partial.length, inInclusiveRange(1, big.length - 1));
      expect(
          _same(partial, Uint8List.sublistView(big, 0, partial.length)), isTrue,
          reason: 'what was recovered is a prefix of the data');
      expect(() => inflateZlib(truncated, strict: true), throwsFormatException);
    });
  });

  // The VM decoder's output collector, driven directly: the native decoder
  // only ever hands it whole lists, so the defensive branches need a caller
  // of their own. (The file has no dart:io import, so this runs under node
  // too.)
  group('native inflateZlib (the VM implementation)', () {
    test('agrees with the web implementation, well-formed or not', () {
      final big = _text(1 << 20);
      final zlib = _zlib(big);
      final inputs = {
        'text': encoded,
        'megabyte': zlib,
        'empty': _zlib(Uint8List(0)),
        'stored': _zlib(_noise(50000), level: 0),
        'trailing bytes': Uint8List.fromList([...encoded, 13, 10]),
        'no Adler-32': Uint8List.sublistView(encoded, 0, encoded.length - 4),
      };
      for (final MapEntry(key: name, value: data) in inputs.entries) {
        expect(_same(io.inflateZlib(data), web.inflateZlib(data)), isTrue,
            reason: name);
      }
    }, testOn: 'vm');

    test('a whole list of its own is held, not copied', () {
      final chunk = Uint8List.fromList([1, 2, 3]);
      final out = io.InflatedChunks()..writeBytes(chunk);
      expect(out.length, 3);
      expect(out.takeBytes(), same(chunk));
    });

    test('anything else is copied', () {
      final backing = Uint8List.fromList([9, 1, 2, 3, 9]);
      final view = Uint8List.sublistView(backing, 1, 4);
      final viewed = io.InflatedChunks()..writeBytes(view);
      expect(viewed.takeBytes(), [1, 2, 3]);
      expect(viewed.takeBytes().buffer, isNot(same(backing.buffer)),
          reason: 'a view would pin, and alias, the larger buffer');

      final whole = Uint8List.fromList([1, 2, 3, 4]);
      final partial = io.InflatedChunks()..writeBytes(whole, length: 2);
      expect(partial.length, 2);
      expect(partial.takeBytes(), [1, 2]);
      expect(partial.takeBytes(), isNot(same(whole)));

      final plain = io.InflatedChunks()..writeBytes(<int>[7, 8]);
      expect(plain.takeBytes(), [7, 8]);

      final nothing = io.InflatedChunks()..writeBytes(Uint8List(0));
      expect(nothing.length, 0);
      expect(nothing.takeBytes(), isEmpty);
    });

    test('pieces join once, in order, at their exact size', () {
      final out = io.InflatedChunks()
        ..writeBytes(Uint8List.fromList([1, 2]))
        ..writeByte(3)
        ..writeStream(InputMemoryStream(Uint8List.fromList([4, 5, 6])))
        ..writeBytes(Uint8List.fromList([7]))
        ..flush();
      expect(out.length, 7);
      final joined = out.takeBytes();
      expect(joined, [1, 2, 3, 4, 5, 6, 7]);
      expect(joined.buffer.lengthInBytes, 7);
      expect(out.takeBytes(), same(joined), reason: 'no second join');

      expect(out.subset(2), [3, 4, 5, 6, 7]);
      expect(out.subset(1, 3), [2, 3]);
      expect(out.subset(-2), [6, 7]);
      expect(out.subset(0, -5), [1, 2]);

      out.clear();
      expect(out.length, 0);
      expect(out.takeBytes(), isEmpty);
    });
  });

  group('FlateFilter', () {
    test('decodes a stream with a trailing EOL', () {
      final stream = CosStream(
          CosDictionary({'Filter': const CosName('FlateDecode')}),
          Uint8List.fromList([...encoded, 0x0d, 0x0a]));
      expect(decodeStream(stream), text);
    });
  });

  group('CosCompactor', () {
    CosDocument docWith(CosDictionary dict, Uint8List payload) {
      final builder = CosDocumentBuilder();
      final stream = builder.add(CosStream(dict, payload));
      final root = builder.add(CosDictionary({
        'Type': const CosName('Catalog'),
        'Sample': stream,
      }));
      return CosDocument.open(builder.build(root: root));
    }

    CosStream sampleOf(CosDocument doc) =>
        doc.resolve(doc.catalog['Sample']) as CosStream;

    test('keeps a trailing-EOL Flate stream through recompress', () {
      // Stored (level 0) so the compactor's re-deflate is smaller and the
      // payload is replaced; the trailing LF is the common real-world shape.
      final payload = Uint8List.fromList([..._zlib(text, level: 0), 0x0a]);
      final doc = docWith(
          CosDictionary({'Filter': const CosName('FlateDecode')}), payload);
      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, 1);
      final compacted = CosDocument.open(result.bytes);
      final stream = sampleOf(compacted);
      expect(stream.rawBytes.length, lessThan(payload.length));
      expect(compacted.decodeStreamData(stream), text);
    });

    test('preserves a Flate stream whose Adler-32 is wrong', () {
      final payload = _zlib(text, level: 0);
      payload[payload.length - 1] ^= 1;
      final doc = docWith(
          CosDictionary({'Filter': const CosName('FlateDecode')}), payload);
      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, 0);
      expect(sampleOf(CosDocument.open(result.bytes)).rawBytes, payload);
    });

    test('re-deflates a small empty stream', () {
      // A real writer's 10-byte empty stream; the re-deflate is 8 bytes.
      final payload = Uint8List.fromList(
          [0x48, 0x89, 0x02, 0x08, 0x30, 0x00, 0x00, 0x00, 0x00, 0x01]);
      expect(inflateZlib(payload, strict: true), isEmpty);
      final doc = docWith(
          CosDictionary({'Filter': const CosName('FlateDecode')}), payload);
      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, 1);
      final stream = sampleOf(CosDocument.open(result.bytes));
      expect(stream.rawBytes.length, lessThan(payload.length));
      expect(inflateZlib(stream.rawBytes), isEmpty);
    });

    test('never trades a larger payload for an empty re-deflate', () {
      // A valid zlib stream of empty stored blocks: 111 bytes that inflate
      // to nothing. Past an empty stream's framing, that is suspect.
      final payload = Uint8List.fromList([
        0x78, 0x01, //
        for (var i = 0; i < 20; i++) ...[0x00, 0x00, 0x00, 0xff, 0xff],
        0x01, 0x00, 0x00, 0xff, 0xff, // final, empty
        0x00, 0x00, 0x00, 0x01, // Adler-32 of nothing
      ]);
      expect(inflateZlib(payload, strict: true), isEmpty);
      final doc = docWith(
          CosDictionary({'Filter': const CosName('FlateDecode')}), payload);
      final result = CosCompactor(doc).run();
      expect(result.streamsDeflated, 0);
      expect(sampleOf(CosDocument.open(result.bytes)).rawBytes, payload);
    });
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _zlib(Uint8List data, {int level = 6}) =>
    Uint8List.fromList(const ZLibEncoder().encodeBytes(data, level: level));

/// Content-stream-like text: repetitive enough to compress well.
Uint8List _text(int length) {
  final out = StringBuffer();
  for (var i = 0; out.length < length; i++) {
    out.write('BT /F1 ${9 + i % 5} Tf ${72 + i % 400} ${720 - i % 650} Td '
        '(line $i of the page) Tj ET\n');
  }
  return Uint8List.fromList(out.toString().substring(0, length).codeUnits);
}

/// Deterministic incompressible bytes.
Uint8List _noise(int length, {int seed = 1}) {
  final out = Uint8List(length);
  var state = seed;
  for (var i = 0; i < length; i++) {
    state = (state * 214013 + 2531011) & 0x7fffffff; // exact in JS too
    out[i] = state >> 16;
  }
  return out;
}

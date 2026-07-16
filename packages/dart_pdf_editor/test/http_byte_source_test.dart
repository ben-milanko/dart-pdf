// PdfHttpByteSource: Range-request progressive loading, full-download
// fallback for servers that ignore Range, header/auth forwarding,
// cancellation, and error handling. Uses http's MockClient - no real network.

import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A MockClient serving [data]. When [supportRange] is false it answers every
/// request with a full 200 body, modelling a server (or a web CORS response
/// with hidden headers) that does not expose ranges. Records requests.
MockClient rangeServer(
  Uint8List data, {
  bool supportRange = true,
  List<http.Request>? log,
}) {
  return MockClient((request) async {
    log?.add(request);
    final range = request.headers['Range'];
    if (supportRange && range != null) {
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        var end = int.parse(match.group(2)!);
        if (start >= data.length) {
          return http.Response.bytes(const [], 416);
        }
        if (end >= data.length) end = data.length - 1;
        return http.Response.bytes(
          data.sublist(start, end + 1),
          206,
          headers: {'content-range': 'bytes $start-$end/${data.length}'},
        );
      }
    }
    return http.Response.bytes(data, 200);
  });
}

void main() {
  final uri = Uri.parse('https://example.test/doc.pdf');

  group('range-capable server', () {
    test('probes length and range support with one small request', () async {
      final data = buildMultiPagePdf(4);
      final requests = <http.Request>[];
      final source = PdfHttpByteSource(uri,
          client: rangeServer(data, log: requests));

      expect(await source.length, data.length);
      expect(source.supportsRange, isTrue);
      // The probe is a single one-byte range, not a full download.
      expect(requests.single.headers['Range'], 'bytes=0-0');
    });

    test('reads a middle range', () async {
      final data = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final source = PdfHttpByteSource(uri, client: rangeServer(data));
      final chunk = await source.readRange(100, 150);
      expect(chunk, data.sublist(100, 150));
    });

    test('opens a document through PdfDocument.openSource', () async {
      final source =
          PdfHttpByteSource(uri, client: rangeServer(buildClassicPdf()));
      final doc = await PdfDocument.openSource(source);
      expect(doc.catalog.typeName, 'Catalog');
      expect(doc.pageCount, 1);
    });

    test('opens a linearized-style multi-revision document', () async {
      final base = CosDocument.open(buildClassicPdf());
      final updated = (CosIncrementalUpdater(base)
            ..replaceObject(5, CosDictionary({'Rewritten': const CosBoolean(true)})))
          .save();
      final source = PdfHttpByteSource(uri, client: rangeServer(updated));
      final doc = await CosDocument.openSource(source);
      expect(doc.catalog.typeName, 'Catalog');
    });

    test('forwards authentication headers on every request', () async {
      final data = buildClassicPdf();
      final requests = <http.Request>[];
      final source = PdfHttpByteSource(
        uri,
        headers: {'Authorization': 'Bearer secret-token'},
        client: rangeServer(data, log: requests),
      );
      await CosDocument.openSource(source);
      expect(requests, isNotEmpty);
      expect(
        requests.every((r) => r.headers['Authorization'] == 'Bearer secret-token'),
        isTrue,
      );
    });

    test('reports progress with the known total', () async {
      final data = buildMultiPagePdf(4);
      final events = <({int received, int? total})>[];
      final source = PdfHttpByteSource(
        uri,
        client: rangeServer(data),
        onProgress: (received, total) =>
            events.add((received: received, total: total)),
      );
      await CosDocument.openSource(source);
      expect(events, isNotEmpty);
      expect(events.last.total, data.length);
      for (var i = 1; i < events.length; i++) {
        expect(events[i].received, greaterThanOrEqualTo(events[i - 1].received));
      }
    });
  });

  group('server without range support', () {
    test('falls back to a full download and still opens', () async {
      final data = buildClassicPdf();
      final requests = <http.Request>[];
      final source = PdfHttpByteSource(uri,
          client: rangeServer(data, supportRange: false, log: requests));

      final doc = await CosDocument.openSource(source);
      expect(doc.catalog.typeName, 'Catalog');
      expect(source.supportsRange, isFalse);
      // Length is learned from the 200 body, and later reads are served from
      // memory - only the first request actually hit the network.
      expect(await source.length, data.length);
    });

    test('serves subsequent ranges from the cached body', () async {
      final data = Uint8List.fromList(List.generate(500, (i) => i % 251));
      var hits = 0;
      final client = MockClient((request) async {
        hits++;
        return http.Response.bytes(data, 200); // ignores Range
      });
      final source = PdfHttpByteSource(uri, client: client);
      final a = await source.readRange(10, 20);
      final b = await source.readRange(400, 450);
      expect(a, data.sublist(10, 20));
      expect(b, data.sublist(400, 450));
      expect(hits, 1); // one download, both slices from memory
    });
  });

  group('errors and cancellation', () {
    test('an error status throws PdfHttpException', () async {
      final source = PdfHttpByteSource(uri,
          client: MockClient((_) async => http.Response('nope', 404)));
      await expectLater(source.length, throwsA(isA<PdfHttpException>()));
    });

    test('a transport failure is wrapped', () async {
      final source = PdfHttpByteSource(uri,
          client: MockClient((_) async => throw http.ClientException('boom')));
      await expectLater(
          source.readRange(0, 10), throwsA(isA<PdfHttpException>()));
    });

    test('cancellation before reading throws', () async {
      final token = PdfCancelToken()..cancel();
      final source = PdfHttpByteSource(uri,
          client: rangeServer(buildClassicPdf()), cancelToken: token);
      await expectLater(
          source.readRange(0, 10), throwsA(isA<PdfHttpCancelledException>()));
    });

    test('cancellation mid-load aborts openSource', () async {
      final token = PdfCancelToken();
      var served = 0;
      final data = buildMultiPagePdf(6);
      final client = MockClient((request) async {
        served++;
        if (served >= 2) token.cancel(); // cancel after the probe
        final range = request.headers['Range']!;
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final s = int.parse(m.group(1)!);
        var e = int.parse(m.group(2)!);
        if (e >= data.length) e = data.length - 1;
        return http.Response.bytes(data.sublist(s, e + 1), 206,
            headers: {'content-range': 'bytes $s-$e/${data.length}'});
      });
      final source =
          PdfHttpByteSource(uri, client: client, cancelToken: token);
      await expectLater(CosDocument.openSource(source),
          throwsA(isA<PdfHttpCancelledException>()));
    });
  });

  test('close() leaves a caller-supplied client open', () async {
    // The source only owns (and closes) a client it created itself; an
    // injected client is the caller's to manage.
    final client = rangeServer(buildClassicPdf());
    final source = PdfHttpByteSource(uri, client: client);
    await source.close();
    // The injected client is still usable after close().
    final response = await client.get(uri, headers: {'Range': 'bytes=0-0'});
    expect(response.statusCode, 206);
  });
}

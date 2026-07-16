import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf_cos/pdf_cos.dart';

/// Cooperative cancellation for a [PdfHttpByteSource]. Call [cancel] to stop
/// an in-progress or subsequent load; pending and future reads then throw a
/// [PdfHttpCancelledException]. A token is single-use.
class PdfCancelToken {
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const PdfHttpCancelledException();
  }
}

/// Thrown from a [PdfHttpByteSource] read after its [PdfCancelToken] fired.
class PdfHttpCancelledException implements Exception {
  const PdfHttpCancelledException();

  @override
  String toString() => 'PdfHttpCancelledException: load cancelled';
}

/// Thrown when the server responds in a way the source cannot use (an error
/// status, or a body that does not match the requested range).
class PdfHttpException implements Exception {
  PdfHttpException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'PdfHttpException: $message'
      : 'PdfHttpException ($statusCode): $message';
}

/// A [PdfByteSource] that reads a remote PDF over HTTP(S), using Range
/// requests when the server supports them and transparently falling back to a
/// single full download when it does not.
///
/// Pass [headers] for authentication (e.g. `Authorization`) or content
/// negotiation. On the web, cross-origin loads are subject to CORS: the
/// server must send `Access-Control-Allow-Origin` and, for Range-based
/// progressive loading, expose `Accept-Ranges`/`Content-Range` via
/// `Access-Control-Expose-Headers`; otherwise the browser hides them and this
/// source falls back to a full download. To send cookies cross-origin, supply
/// a `BrowserClient()..withCredentials = true` as [client].
///
/// Use with [PdfDocument.openSource] / [CosDocument.openSource]:
///
/// ```dart
/// final source = PdfHttpByteSource(Uri.parse('https://host/big.pdf'),
///     headers: {'Authorization': 'Bearer $token'}, cancelToken: token);
/// final document = await PdfDocument.openSource(source);
/// ```
class PdfHttpByteSource implements PdfByteSource {
  PdfHttpByteSource(
    this.uri, {
    Map<String, String>? headers,
    http.Client? client,
    this.cancelToken,
    this.onProgress,
  })  : _headers = headers,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The document URL.
  final Uri uri;

  final Map<String, String>? _headers;
  final http.Client _client;
  final bool _ownsClient;

  /// Optional cancellation handle.
  final PdfCancelToken? cancelToken;

  /// Called after each network read with the running total of bytes received
  /// and the document length once known.
  final void Function(int received, int? total)? onProgress;

  bool _probed = false;
  bool _supportsRange = false;
  int? _length;

  /// Whether the server answered the probe with a 206 (Range supported). Only
  /// meaningful after the first read; false when the source fell back to a
  /// full download. Useful for diagnostics and tests.
  bool get supportsRange => _supportsRange;

  /// Populated when the server ignores Range (or has no length): the whole
  /// body, downloaded once and served from memory thereafter.
  Uint8List? _fullBuffer;

  int _received = 0;

  @override
  Future<int?> get length async {
    await _probe();
    return _length;
  }

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    cancelToken?.throwIfCancelled();
    await _probe();

    final buffer = _fullBuffer;
    if (buffer != null) return _slice(buffer, start, endExclusive);

    final s = start < 0 ? 0 : start;
    if (endExclusive <= s) return Uint8List(0);

    final response = await _get(rangeStart: s, rangeEndInclusive: endExclusive - 1);
    cancelToken?.throwIfCancelled();
    switch (response.statusCode) {
      case 206:
        return _report(response.bodyBytes);
      case 200:
        // The server ignored the Range header and sent the whole file; keep
        // it and serve this and every later range from memory.
        _adoptFullBody(response.bodyBytes);
        return _slice(_fullBuffer!, start, endExclusive);
      case 416:
        return Uint8List(0); // requested wholly past the end
      default:
        throw PdfHttpException('unexpected status reading range $s-${endExclusive - 1}',
            statusCode: response.statusCode);
    }
  }

  /// Probes range support and length with a single one-byte ranged GET.
  Future<void> _probe() async {
    if (_probed) return;
    _probed = true;
    cancelToken?.throwIfCancelled();
    final response = await _get(rangeStart: 0, rangeEndInclusive: 0);
    cancelToken?.throwIfCancelled();
    switch (response.statusCode) {
      case 206:
        _supportsRange = true;
        _length = _totalFromContentRange(response.headers['content-range']);
        _report(response.bodyBytes);
      case 200:
        _supportsRange = false;
        _adoptFullBody(response.bodyBytes);
      case 416:
        _length = 0;
        _adoptFullBody(Uint8List(0));
      default:
        throw PdfHttpException('unexpected status ${response.statusCode} for $uri',
            statusCode: response.statusCode);
    }
  }

  Future<http.Response> _get({
    required int rangeStart,
    required int rangeEndInclusive,
  }) async {
    final extra = _headers;
    final headers = <String, String>{
      if (extra != null) ...extra,
      'Range': 'bytes=$rangeStart-$rangeEndInclusive',
    };
    try {
      return await _client.get(uri, headers: headers);
    } on PdfHttpCancelledException {
      rethrow;
    } on Object catch (error) {
      throw PdfHttpException('request failed for $uri: $error');
    }
  }

  void _adoptFullBody(Uint8List body) {
    _fullBuffer = body;
    _length = body.length;
    _report(body, cumulativeOverride: body.length);
  }

  Uint8List _report(Uint8List data, {int? cumulativeOverride}) {
    _received = cumulativeOverride ?? _received + data.length;
    onProgress?.call(_received, _length);
    return data;
  }

  static Uint8List _slice(Uint8List buffer, int start, int endExclusive) {
    final s = start < 0 ? 0 : (start > buffer.length ? buffer.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > buffer.length ? buffer.length : endExclusive);
    return Uint8List.sublistView(buffer, s, e);
  }

  /// Parses the total length from a `Content-Range: bytes 0-0/12345` header;
  /// returns null for `.../*` or a missing/malformed header.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final total = header.substring(slash + 1).trim();
    if (total == '*') return null;
    return int.tryParse(total);
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
  }
}

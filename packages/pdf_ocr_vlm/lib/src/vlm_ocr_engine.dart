import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:http/http.dart' as http;
import 'package:pdf_document/pdf_document.dart' show PdfOcrSpan;

/// Thrown when a remote OCR service is unreachable, returns a non-200
/// status, or returns a body this engine cannot parse.
class VlmOcrException implements Exception {
  VlmOcrException(this.message);

  final String message;

  @override
  String toString() => 'VlmOcrException: $message';
}

/// The rasterized page handed to a request builder. The page has already
/// been rendered to a PNG ([imageBase64] / [imageDataUrl]); the builder
/// turns it into whatever JSON the target service expects.
class VlmOcrInput {
  const VlmOcrInput({
    required this.imageBase64,
    required this.imageDataUrl,
    required this.width,
    required this.height,
    required this.pageIndex,
    required this.languages,
    required this.model,
    required this.prompt,
  });

  /// The page raster as base64-encoded PNG bytes.
  final String imageBase64;

  /// The same PNG as a `data:image/png;base64,...` URL — what an
  /// OpenAI-compatible chat vision API wants under `image_url`.
  final String imageDataUrl;

  /// Raster pixel dimensions (the coordinate space recognized boxes use).
  final int width;
  final int height;

  /// The page's index in its document (for logging / multi-page services).
  final int pageIndex;

  /// Optional ISO language hints passed through from the engine.
  final List<String> languages;

  /// Optional model name passed through from the engine.
  final String? model;

  /// Optional instruction prompt (used by chat-style VLM backends).
  final String? prompt;
}

/// A single recognized fragment, positioned in **raster pixels**
/// (top-left origin, y down — the natural output of an OCR model run on the
/// PNG the engine sent). [VlmOcrEngine] converts these to PDF user space via
/// `PdfOcrPageImage.userSpaceRect`.
class VlmOcrWord {
  const VlmOcrWord({
    required this.text,
    required this.pixelBounds,
    this.confidence = 1.0,
  });

  final String text;
  final Rect pixelBounds;
  final double confidence;
}

/// Builds the HTTP request body (a JSON-encodable object or a ready String)
/// for one page. Override to target a service with a bespoke schema.
typedef VlmOcrRequestBody = FutureOr<Object?> Function(VlmOcrInput input);

/// Parses a decoded JSON response into recognized words. Override to read a
/// service's bespoke response shape.
typedef VlmOcrResponseParser = List<VlmOcrWord> Function(
  Object? json,
  PdfOcrPageImage page,
);

/// A [PdfOcrEngine] that recognizes a page by POSTing its raster to an HTTP
/// OCR service and mapping the returned boxes back into PDF user space.
///
/// Two ready paths:
///
///  * the default constructor speaks a small, documented JSON contract
///    (POST `{image, width, height, ...}` → `{spans: [{text, bbox,
///    confidence}]}`) — point it at the reference adapter in the README, or
///    any server you wrap to that shape;
///  * [VlmOcrEngine.dotsOcr] speaks the OpenAI-compatible chat API exposed by
///    a vLLM server running `rednote-hilab/dots.ocr` (a current
///    state-of-the-art open-source document-OCR VLM) with no adapter at all.
///
/// For anything else — a cloud VLM, PaddleOCR, Tesseract, a gRPC gateway —
/// pass a custom [requestBody]/[responseParser], or implement [PdfOcrEngine]
/// directly. The page geometry math (crop box, /Rotate, pixel→user) is done
/// for you by `PdfOcrPageImage.userSpaceRect`.
class VlmOcrEngine implements PdfOcrEngine {
  VlmOcrEngine({
    required this.endpoint,
    this.headers = const {},
    this.languages = const [],
    this.model,
    this.prompt,
    this.minConfidence = 0,
    VlmOcrRequestBody? requestBody,
    VlmOcrResponseParser? responseParser,
    http.Client? client,
    this.timeout = const Duration(minutes: 2),
  })  : buildRequestBody = requestBody ?? defaultVlmRequestBody,
        parseResponse = responseParser ?? defaultVlmResponseParser,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The OCR service URL the page raster is POSTed to.
  final Uri endpoint;

  /// Extra request headers, e.g. `{'authorization': 'Bearer ...'}`.
  final Map<String, String> headers;

  /// Optional language hints handed to [buildRequestBody].
  final List<String> languages;

  /// Optional model name handed to [buildRequestBody].
  final String? model;

  /// Optional instruction prompt handed to [buildRequestBody] (chat VLMs).
  final String? prompt;

  /// Words below this confidence are dropped before mapping.
  final double minConfidence;

  /// Turns a rasterized page into the request body.
  final VlmOcrRequestBody buildRequestBody;

  /// Turns the decoded JSON response into recognized words.
  final VlmOcrResponseParser parseResponse;

  /// Per-page request timeout.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// Targets a vLLM server hosting `rednote-hilab/dots.ocr` over its
  /// OpenAI-compatible chat endpoint (default
  /// `http://localhost:8000/v1/chat/completions`).
  ///
  /// dots.ocr returns a JSON array of layout cells, each with a pixel `bbox`
  /// (`[x1, y1, x2, y2]`, top-left origin), a `category`, and the cell
  /// `text`. Cells whose category is in [categories] (text-bearing blocks by
  /// default; `Picture` and `Table` are excluded) become the OCR layer.
  ///
  /// See the package README for the one-line Docker command that serves the
  /// model.
  factory VlmOcrEngine.dotsOcr({
    Uri? endpoint,
    String model = 'model',
    String? apiKey,
    String? prompt,
    Set<String>? categories,
    List<String> languages = const [],
    double minConfidence = 0,
    http.Client? client,
    Duration timeout = const Duration(minutes: 2),
  }) {
    final cats = categories ?? dotsOcrTextCategories;
    return VlmOcrEngine(
      endpoint:
          endpoint ?? Uri.parse('http://localhost:8000/v1/chat/completions'),
      headers: {if (apiKey != null) 'authorization': 'Bearer $apiKey'},
      model: model,
      languages: languages,
      prompt: prompt ?? dotsOcrLayoutPrompt,
      minConfidence: minConfidence,
      requestBody: openAiChatRequestBody,
      responseParser: dotsOcrResponseParser(cats),
      client: client,
      timeout: timeout,
    );
  }

  @override
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page) async {
    final png = await _encodePng(page.image);
    final b64 = base64Encode(png);
    final input = VlmOcrInput(
      imageBase64: b64,
      imageDataUrl: 'data:image/png;base64,$b64',
      width: page.width,
      height: page.height,
      pageIndex: page.pageIndex,
      languages: languages,
      model: model,
      prompt: prompt,
    );

    final body = await buildRequestBody(input);
    final encoded = body is String ? body : jsonEncode(body);

    http.Response res;
    try {
      res = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              ...headers,
            },
            body: encoded,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw VlmOcrException('OCR request to $endpoint timed out after '
          '${timeout.inSeconds}s');
    } catch (e) {
      throw VlmOcrException('OCR request to $endpoint failed: $e');
    }

    if (res.statusCode != 200) {
      throw VlmOcrException(
          'OCR service returned HTTP ${res.statusCode}: ${res.body}');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      throw VlmOcrException('OCR service returned non-JSON body: $e');
    }

    final words = parseResponse(decoded, page);
    return [
      for (final w in words)
        if (w.confidence >= minConfidence &&
            w.text.trim().isNotEmpty &&
            w.pixelBounds.width > 0 &&
            w.pixelBounds.height > 0)
          PdfOcrSpan(
            text: w.text,
            bounds: page.userSpaceRect(w.pixelBounds),
            confidence: w.confidence,
          ),
    ];
  }

  /// Releases the underlying HTTP client if this engine created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw VlmOcrException('could not encode the page raster to PNG');
    }
    return data.buffer.asUint8List();
  }
}

/// The default request body for the simple JSON contract: a POST of the
/// page PNG plus its dimensions and any hints. See the README for the
/// matching response shape and a reference server.
Object defaultVlmRequestBody(VlmOcrInput input) => {
      'image': input.imageBase64,
      'image_format': 'png',
      'width': input.width,
      'height': input.height,
      'page': input.pageIndex,
      if (input.languages.isNotEmpty) 'languages': input.languages,
      if (input.model != null) 'model': input.model,
    };

/// The default response parser for the simple JSON contract.
///
/// Accepts either a top-level list of items or a map carrying one under
/// `spans`/`words`/`lines`/`results`/`regions`/`data`. Each item needs some
/// `text` (`text`/`transcription`/`content`) and a box, given either as a
/// 4-number `bbox`/`box`/`bounding_box`/`rect` (`[x0, y0, x1, y1]`, pixels)
/// or a list of points under `polygon`/`poly`/`points`/`quad`. Confidence is
/// read from `confidence`/`score`/`conf`, defaulting to 1.
List<VlmOcrWord> defaultVlmResponseParser(Object? json, PdfOcrPageImage page) {
  final list = _asItemList(json);
  final words = <VlmOcrWord>[];
  for (final item in list) {
    if (item is! Map) continue;
    final text = _firstString(item, const ['text', 'transcription', 'content']);
    if (text == null) continue;
    final rect = _rectFrom(item);
    if (rect == null) continue;
    words.add(VlmOcrWord(
      text: text,
      pixelBounds: rect,
      confidence: _confidence(item),
    ));
  }
  return words;
}

/// Builds an OpenAI-compatible chat-completions request that sends the page
/// as an inline image and asks for OCR. Used by [VlmOcrEngine.dotsOcr]; reuse
/// it (with a matching [VlmOcrResponseParser]) for other chat-style VLM
/// gateways.
Object openAiChatRequestBody(VlmOcrInput input) => {
      if (input.model != null) 'model': input.model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': input.prompt ?? dotsOcrLayoutPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': input.imageDataUrl},
            },
          ],
        },
      ],
      'temperature': 0.0,
      'max_tokens': 16384,
    };

/// dots.ocr layout categories that carry plain, selectable text. `Picture`
/// (no text), `Table` (text is HTML markup), and `Formula` (LaTeX) are left
/// out by default; pass your own set to [VlmOcrEngine.dotsOcr] to include
/// them.
const Set<String> dotsOcrTextCategories = {
  'Caption',
  'Footnote',
  'List-item',
  'Page-footer',
  'Page-header',
  'Section-header',
  'Text',
  'Title',
};

/// The layout-parsing instruction dots.ocr is trained on: emit a JSON array
/// of cells in reading order, each with a pixel `bbox`, a `category`, and the
/// cell `text`.
const String dotsOcrLayoutPrompt =
    'Please output the layout information from this PDF page image, '
    'including each layout element\'s bbox, its category, and the '
    'corresponding text content within the bbox.\n\n'
    '1. Bbox format: [x1, y1, x2, y2] in pixel coordinates of this image.\n'
    '2. Layout Categories: the possible categories are Caption, Footnote, '
    'Formula, List-item, Page-footer, Page-header, Picture, Section-header, '
    'Table, Text, and Title.\n'
    '3. Text Extraction: extract the plain text for each element; leave it '
    'empty for Picture.\n'
    '4. Reading order: arrange the elements in human reading order.\n'
    '5. Output: a single JSON array, no extra commentary.';

/// Builds a parser for dots.ocr's OpenAI-compatible responses, keeping only
/// cells whose `category` is in [categories].
VlmOcrResponseParser dotsOcrResponseParser(Set<String> categories) {
  return (Object? json, PdfOcrPageImage page) {
    final content = _openAiMessageContent(json);
    if (content == null) {
      throw VlmOcrException(
          'dots.ocr response had no choices[0].message.content');
    }
    Object? cells;
    try {
      cells = jsonDecode(_stripJsonFences(content));
    } catch (e) {
      throw VlmOcrException('dots.ocr content was not valid JSON: $e');
    }
    final list = _asItemList(cells);
    final words = <VlmOcrWord>[];
    for (final item in list) {
      if (item is! Map) continue;
      final category = item['category'];
      if (category is String && !categories.contains(category)) continue;
      final text = _firstString(item, const ['text', 'content']);
      if (text == null) continue;
      final rect = _rectFrom(item);
      if (rect == null) continue;
      words.add(VlmOcrWord(text: text, pixelBounds: rect));
    }
    return words;
  };
}

// --- parsing helpers -------------------------------------------------------

List<Object?> _asItemList(Object? json) {
  if (json is List) return json;
  if (json is Map) {
    for (final key in const [
      'spans',
      'words',
      'lines',
      'results',
      'regions',
      'cells',
      'data',
    ]) {
      final value = json[key];
      if (value is List) return value;
    }
  }
  return const [];
}

String? _openAiMessageContent(Object? json) {
  if (json is! Map) return null;
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  if (message is Map) {
    final content = message['content'];
    if (content is String) return content;
  }
  // Some gateways put the text directly on the choice.
  final text = first['text'];
  return text is String ? text : null;
}

String _stripJsonFences(String content) {
  var s = content.trim();
  if (s.startsWith('```')) {
    final newline = s.indexOf('\n');
    if (newline != -1) s = s.substring(newline + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
  }
  return s.trim();
}

String? _firstString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is String) return value;
  }
  return null;
}

double _confidence(Map item) {
  for (final key in const ['confidence', 'score', 'conf']) {
    final value = item[key];
    if (value is num) return value.toDouble().clamp(0.0, 1.0);
  }
  return 1.0;
}

Rect? _rectFrom(Map item) {
  for (final key in const ['bbox', 'box', 'bounding_box', 'rect']) {
    final value = item[key];
    if (value is List && value.length >= 4 && value.every((e) => e is num)) {
      final x0 = (value[0] as num).toDouble();
      final y0 = (value[1] as num).toDouble();
      final x1 = (value[2] as num).toDouble();
      final y1 = (value[3] as num).toDouble();
      return Rect.fromLTRB(x0, y0, x1, y1);
    }
  }
  for (final key in const ['polygon', 'poly', 'points', 'quad']) {
    final value = item[key];
    final rect = _rectFromPoints(value);
    if (rect != null) return rect;
  }
  return null;
}

Rect? _rectFromPoints(Object? value) {
  if (value is! List || value.isEmpty) return null;
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  var count = 0;

  void add(num x, num y) {
    minX = x < minX ? x.toDouble() : minX;
    minY = y < minY ? y.toDouble() : minY;
    maxX = x > maxX ? x.toDouble() : maxX;
    maxY = y > maxY ? y.toDouble() : maxY;
    count++;
  }

  if (value.first is List) {
    for (final p in value) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        add(p[0] as num, p[1] as num);
      }
    }
  } else if (value.first is num && value.length >= 4 && value.length.isEven) {
    for (var i = 0; i + 1 < value.length; i += 2) {
      if (value[i] is num && value[i + 1] is num) {
        add(value[i] as num, value[i + 1] as num);
      }
    }
  }
  if (count < 2) return null;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

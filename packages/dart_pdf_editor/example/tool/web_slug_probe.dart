import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

const _embeddedFontPdf =
    'JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4K'
    'ZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50'
    'IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAv'
    'TWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8'
    'PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xl'
    'bmd0aCAzMyA+PgpzdHJlYW0KQlQgL0YxIDI0IFRmIDcyIDcwMCBUZCAoQUIpIFRqIEVU'
    'CmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAv'
    'VHJ1ZVR5cGUgL0Jhc2VGb250IC9UZXN0Rm9udCAvRmlyc3RDaGFyIDY1IC9MYXN0Q2hh'
    'ciA2NiAvV2lkdGhzIFs2MDAgMTAwMF0gL0VuY29kaW5nIC9XaW5BbnNpRW5jb2Rpbmcg'
    'L0ZvbnREZXNjcmlwdG9yIDcgMCBSID4+CmVuZG9iago2IDAgb2JqCjw8IC9MZW5ndGgg'
    'Mzc2IC9MZW5ndGgxIDM3NiA+PgpzdHJlYW0KAAEAAAAHAEAAAgAwY21hcAAAAAAAAAB8'
    'AAAALGdseWYAAAAAAAAAqAAAAEBoZWFkAAAAAAAAAOgAAAA2aGhlYQAAAAAAAAEgAAAAJG'
    'htdHgAAAAAAAABRAAAAAxsb2NhAAAAAAAAAVAAAAAIbWF4cAAAAAAAAAFYAAAAIAAAAAEA'
    'AwABAAAADAAEACAAAAAEAAQAAQAAAEL//wAAAEH////AAAEAAAAAAAEAAAAAA+gD6AAC'
    'AAABAQEAAAH0AfQAAAPo/BgAAAEAAAAAA+gD6AADAAABAQEBAAAD6AAA/BgAAAAAA+gAA'
    'AABAAAAAAAAAAAAAF8PPPUAAAPoAAAAAAAAAAAAAAAAAAAAAAAAAAAD6APoAAAACAACA'
    'AAAAAAAAAEAAAMg/zgAAAPoAAAAAAPoAAEAAAAAAAAAAAAAAAAAAAADAfQAAAJYAAAD6A'
    'AAAAAAAAAPACAAAQAAAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAplbmRzdHJlYW0'
    'KZW5kb2JqCjcgMCBvYmoKPDwgL1R5cGUgL0ZvbnREZXNjcmlwdG9yIC9Gb250TmFtZS'
    'AvVGVzdEZvbnQgL0ZsYWdzIDMyIC9Gb250QkJveCBbMCAwIDEwMDAgMTAwMF0gL0l0YW'
    'xpY0FuZ2xlIDAgL0FzY2VudCA4MDAgL0Rlc2NlbnQgLTIwMCAvQ2FwSGVpZ2h0IDgwMC'
    'AvU3RlbVYgODAgL0ZvbnRGaWxlMiA2IDAgUiA+PgplbmRvYmoKeHJlZgowIDgKMDAwMD'
    'AwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNTggMDAw'
    'MDAgbiAKMDAwMDAwMDExNSAwMDAwMCBuIAowMDAwMDAwMjQxIDAwMDAwIG4gCjAwMDA'
    'wMDAzMjQgMDAwMDAgbiAKMDAwMDAwMDQ5MSAwMDAwMCBuIAowMDAwMDAwOTMxIDAwMD'
    'AwIG4gCnRyYWlsZXIKPDwgL1NpemUgOCAvUm9vdCAxIDAgUiA+PgpzdGFydHhyZWYKMT'
    'ExMwolJUVPRgo=';

void main() => runApp(const _SlugProbeApp());

class _SlugProbeApp extends StatefulWidget {
  const _SlugProbeApp();

  @override
  State<_SlugProbeApp> createState() => _SlugProbeAppState();
}

class _SlugProbeAppState extends State<_SlugProbeApp> {
  final _transform = TransformationController();
  late final PdfDocument _document;
  late final PdfPage _page;
  late final Timer _telemetry;
  int _lastQuads = -1;

  @override
  void initState() {
    super.initState();
    StripPdfDevice.resetStats();
    _document = PdfDocument.open(base64Decode(_embeddedFontPdf));
    _page = _document.page(0);
    _telemetry = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final quads = StripPdfDevice.totalSlugQuads;
      if (quads == _lastQuads) return;
      _lastQuads = quads;
      debugPrint('[slug-probe] quads=$quads '
          'stripQuads=${StripPdfDevice.totalStripQuads} '
          'flushes=${StripPdfDevice.totalFlushes}');
      if (mounted) setState(() {});
    });
  }

  void _zoom(double scale) {
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale);
    _transform.value = matrix;
    debugPrint('[slug-probe] transform=${scale}x '
        'quads=${StripPdfDevice.totalSlugQuads}');
  }

  @override
  void dispose() {
    _telemetry.cancel();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Web Slug transform probe'),
            actions: [
              Text('quads ${StripPdfDevice.totalSlugQuads}'),
              const SizedBox(width: 12),
              TextButton(onPressed: () => _zoom(1), child: const Text('1x')),
              TextButton(onPressed: () => _zoom(3), child: const Text('3x')),
              const SizedBox(width: 12),
            ],
          ),
          body: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 1,
              maxScale: 4,
              child: SizedBox(
                width: 612,
                child: PdfPageView(page: _page),
              ),
            ),
          ),
        ),
      );
}

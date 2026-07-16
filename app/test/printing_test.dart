// Unit coverage for the print wrapper: the job-name normaliser and the
// `printPdfBytes` hand-off to the `printing` plugin. The real plugin talks over
// the `net.nfet.printing` method channel, which we mock here - driving the
// `onCompleted` callback so `Printing.layoutPdf` resolves without a platform.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/printing.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('printJobName', () {
    test('strips a trailing .pdf, case-insensitively', () {
      expect(printJobName('Report.pdf'), 'Report');
      expect(printJobName('SCAN.PDF'), 'SCAN');
    });

    test('trims surrounding whitespace', () {
      expect(printJobName('  Quarterly.pdf  '), 'Quarterly');
    });

    test('keeps a name that has no extension', () {
      expect(printJobName('Untitled'), 'Untitled');
    });

    test('falls back to Document when nothing is left', () {
      expect(printJobName('   '), 'Document');
      expect(printJobName('.pdf'), 'Document');
    });
  });

  group('printPdfBytes', () {
    const channel = MethodChannel('net.nfet.printing');

    /// Drives the mocked print plugin, capturing the job name and the bytes
    /// the `onLayout` callback ultimately produces. Returns the completer for
    /// asserting after `printPdfBytes` resolves.
    ({List<int> layoutBytes, List<String?> names, List<int> calls})
        mockPrinter() {
      final messenger = binding.defaultBinaryMessenger;
      final names = <String?>[];
      final calls = <int>[];
      final layoutBytes = <int>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'printPdf') return null;
        calls.add(1);
        final args = call.arguments as Map;
        names.add(args['name'] as String?);
        // Ask Dart for the layout, mirroring the native plugin, then capture
        // the bytes it returns (delivered on the response callback) before
        // completing the job.
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('onLayout', <String, dynamic>{
              'job': args['job'],
              'width': 595.0,
              'height': 842.0,
              'marginLeft': 0.0,
              'marginTop': 0.0,
              'marginRight': 0.0,
              'marginBottom': 0.0,
            }),
          ),
          (reply) {
            if (reply == null) return;
            final decoded = channel.codec.decodeEnvelope(reply);
            if (decoded is Uint8List) layoutBytes.addAll(decoded);
          },
        );
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('onCompleted', <String, dynamic>{
              'job': args['job'],
              'completed': true,
            }),
          ),
          (_) {},
        );
        return 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return (layoutBytes: layoutBytes, names: names, calls: calls);
    }

    test('hands the document to the print plugin', () async {
      final printer = mockPrinter();
      final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

      await printPdfBytes(bytes: bytes, title: 'Report.pdf');

      expect(printer.calls, hasLength(1));
      expect(printer.names.single, 'Report'); // the .pdf-stripped job name
    });

    test('prints the original bytes verbatim off Windows', () async {
      final printer = mockPrinter();
      final bytes = Uint8List.fromList('%PDF-1.7 original'.codeUnits);

      var rasterCalls = 0;
      await printPdfBytes(
        bytes: bytes,
        title: 'Report.pdf',
        platform: TargetPlatform.macOS,
        rasterize: (_) async {
          rasterCalls += 1;
          return Uint8List.fromList('rastered'.codeUnits);
        },
      );

      expect(rasterCalls, 0); // never rasterised off Windows
      expect(printer.layoutBytes, bytes);
    });

    test('prints a rasterised copy on Windows', () async {
      final printer = mockPrinter();
      final bytes = Uint8List.fromList('%PDF-1.7 original'.codeUnits);
      final raster = Uint8List.fromList('%PDF-1.7 rastered'.codeUnits);

      await printPdfBytes(
        bytes: bytes,
        title: 'Report.pdf',
        platform: TargetPlatform.windows,
        rasterize: (_) async => raster,
      );

      expect(printer.layoutBytes, raster);
    });

    test('falls back to the original bytes when rasterising fails on Windows',
        () async {
      final printer = mockPrinter();
      final bytes = Uint8List.fromList('%PDF-1.7 original'.codeUnits);

      await printPdfBytes(
        bytes: bytes,
        title: 'Report.pdf',
        platform: TargetPlatform.windows,
        rasterize: (_) async => throw StateError('boom'),
      );

      expect(printer.layoutBytes, bytes);
    });
  });
}

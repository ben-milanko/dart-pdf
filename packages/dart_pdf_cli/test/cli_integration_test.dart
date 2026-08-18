import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late File pdf;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('dartpdf-cli-test-');
    pdf = File('${temporary.path}/sample.pdf');
    await pdf.writeAsBytes(buildClassicPdf());
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('inspect command emits compact JSON and keeps diagnostics off stdout',
      () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/dartpdf.dart', 'inspect', pdf.path, '--json'],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stderr, isEmpty);
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(json['operation'], 'inspect');
    expect(json['pageCount'], 1);
  });

  test('missing input is a meaningful non-zero diagnostic', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/dartpdf.dart', 'text', '--json'],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 64);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('requires exactly one input PDF path'));
  });

  test('password files are bounded instead of being read without limit',
      () async {
    final password = File('${temporary.path}/password.txt');
    await password.writeAsString(List.filled(4097, 'x').join());
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/dartpdf.dart',
        'inspect',
        pdf.path,
        '--password-file',
        password.path,
        '--json',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 64);
    expect(result.stdout, isEmpty);
    expect(
        result.stderr, contains('password input exceeds the 4096-byte limit'));
  });

  test('stdio MCP lists and calls the shared inspect handler', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/dartpdf.dart', 'mcp', '--root', temporary.path],
      workingDirectory: Directory.current.path,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();

    Future<Map<String, dynamic>> response(int id) async {
      while (await lines.moveNext().timeout(const Duration(seconds: 20))) {
        final value = jsonDecode(lines.current) as Map<String, dynamic>;
        if (value['id'] == id) return value;
      }
      throw StateError('MCP server closed before response $id');
    }

    void send(Map<String, Object?> message) {
      process.stdin.writeln(jsonEncode(message));
    }

    try {
      send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-11-25',
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'dartpdf-test', 'version': '1.0.0'},
        },
      });
      final initialized = await response(1);
      expect(initialized['error'], isNull);
      send({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      final listed = await response(2);
      final tools =
          ((listed['result'] as Map<String, dynamic>)['tools'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(
        tools.map((tool) => tool['name']),
        containsAll([
          'inspect_pdf',
          'extract_pdf_text',
          'list_pdf_forms',
          'list_pdf_annotations',
        ]),
      );
      final inspectTool =
          tools.singleWhere((tool) => tool['name'] == 'inspect_pdf');
      final inspectSchema = inspectTool['inputSchema'] as Map<String, dynamic>;
      final inspectProperties =
          inspectSchema['properties'] as Map<String, dynamic>;
      expect(
        (inspectProperties['path'] as Map<String, dynamic>)['maxLength'],
        32768,
      );

      send({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'inspect_pdf',
          'arguments': {'path': 'sample.pdf'},
        },
      });
      final called = await response(3);
      final result = called['result'] as Map<String, dynamic>;
      expect(result['isError'], isNot(true));
      final structured = result['structuredContent'] as Map<String, dynamic>;
      expect(structured['operation'], 'inspect');
      expect(structured['pageCount'], 1);

      send({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'inspect_pdf',
          'arguments': {'path': '${Directory.current.path}/pubspec.yaml'},
        },
      });
      final denied = await response(4);
      final deniedResult = denied['result'] as Map<String, dynamic>;
      expect(deniedResult['isError'], isTrue);
      expect(
        ((deniedResult['content'] as List<dynamic>).single
            as Map<String, dynamic>)['text'],
        contains('outside configured MCP filesystem roots'),
      );

      send({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {
          'name': 'inspect_pdf',
          'arguments': {'path': List.filled(5000, 'x').join()},
        },
      });
      final boundedError = await response(5);
      final boundedResult = boundedError['result'] as Map<String, dynamic>;
      expect(boundedResult['isError'], isTrue);
      final errorText = ((boundedResult['content'] as List<dynamic>).single
          as Map<String, dynamic>)['text'] as String;
      expect(errorText.length, lessThanOrEqualTo(4130));
    } finally {
      process.kill();
      await process.stdin.close();
      await process.exitCode;
      await lines.cancel();
      await stderrDone;
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('build_desktop_cli produces sanitized Mach-O on macOS without private symbols', () async {
    if (!Platform.isMacOS) return;

    final targetArch = switch (Platform.version.toLowerCase()) {
      final v when v.contains('arm64') || v.contains('aarch64') => 'arm64',
      _ => 'x64',
    };
    final outputBinary = File('${temporary.path}/dartpdf-sanitized-test');

    final buildResult = await Process.run(
      Platform.resolvedExecutable,
      [
        '../../tool/build_desktop_cli.dart',
        '--output',
        outputBinary.path,
        '--target-os',
        'macos',
        '--target-arch',
        targetArch,
      ],
      workingDirectory: Directory.current.path,
    );
    expect(buildResult.exitCode, 0, reason: buildResult.stderr as String);
    expect(await outputBinary.exists(), isTrue);

    // Verify private symbol __dyld_find_unwind_sections is absent from undefined symbols
    final nmResult = await Process.run('nm', ['-u', outputBinary.path]);
    expect(nmResult.exitCode, 0);
    expect(nmResult.stdout as String, isNot(contains('__dyld_find_unwind_sections')));

    // Verify the sanitized executable runs properly
    final execResult = await Process.run(
      outputBinary.path,
      ['inspect', pdf.path, '--json'],
    );
    expect(execResult.exitCode, 0, reason: execResult.stderr as String);
    final json = jsonDecode(execResult.stdout as String) as Map<String, dynamic>;
    expect(json['operation'], 'inspect');
    expect(json['pageCount'], 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}


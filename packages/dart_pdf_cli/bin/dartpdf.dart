import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:dart_pdf_cli/dart_pdf_cli.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_cos/pdf_cos.dart';

const _version = '0.1.0';
const _usageExit = 64;
const _dataExit = 65;
const _inputExit = 66;

Future<void> main(List<String> arguments) async {
  exitCode = await _DartPdfCli().run(arguments);
}

class _DartPdfCli {
  _DartPdfCli() : parser = _buildParser();

  final ArgParser parser;
  final DartPdfService service = const DartPdfService();

  Future<int> run(List<String> arguments) async {
    try {
      final results = parser.parse(arguments);
      if (results['version'] as bool) {
        stdout.writeln('dartpdf $_version');
        return 0;
      }
      if (results['help'] as bool || results.command == null) {
        _writeUsage();
        return results.command == null && !(results['help'] as bool)
            ? _usageExit
            : 0;
      }

      final command = results.command!;
      if (command.name == 'mcp') return await _runMcp(command);
      if (command.name == 'forms' || command.name == 'annotations') {
        if (command['help'] as bool) {
          stdout.writeln(_usageFor(command.name!));
          return 0;
        }
        final nested = command.command;
        if (nested == null || nested.name != 'list') {
          throw _UsageException(
              '${command.name} requires the "list" command', parser.usage);
        }
        return await _runReadCommand('${command.name}.list', nested);
      }
      return await _runReadCommand(command.name!, command);
    } on _UsageException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(error.usage);
      return _usageExit;
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(parser.usage);
      return _usageExit;
    } on FileSystemException catch (error) {
      stderr.writeln('dartpdf: ${error.message}'
          '${error.path == null ? '' : ': ${error.path}'}');
      return _inputExit;
    } on CosPasswordException catch (error) {
      stderr.writeln('dartpdf: $error');
      return _dataExit;
    } on CosParseException catch (error) {
      stderr.writeln('dartpdf: $error');
      return _dataExit;
    } on DartPdfRequestException catch (error) {
      stderr.writeln('dartpdf: ${error.message}');
      return _usageExit;
    } on Object catch (error) {
      stderr.writeln('dartpdf: $error');
      return _dataExit;
    }
  }

  Future<int> _runReadCommand(String operation, ArgResults results) async {
    if (results['help'] as bool) {
      stdout.writeln(_usageFor(operation));
      return 0;
    }
    if (results.rest.length != 1) {
      throw _UsageException('$operation requires exactly one input PDF path',
          _usageFor(operation));
    }
    final password = await _readCliPassword(results);
    final bytes = await File(results.rest.single).readAsBytes();
    final document = service.open(bytes, password: password);
    final Map<String, Object?> output = switch (operation) {
      'inspect' => document.inspect(),
      'text' => document.extractText(pages: results['pages'] as String?),
      'forms.list' => document.listForms(),
      'annotations.list' =>
        document.listAnnotations(pages: results['pages'] as String?),
      _ => throw StateError('unknown operation $operation'),
    };
    final encoder = results['json'] as bool
        ? const JsonEncoder()
        : const JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert(output));
    return 0;
  }

  Future<int> _runMcp(ArgResults results) async {
    if (results['help'] as bool) {
      stdout.writeln(_usageFor('mcp'));
      return 0;
    }
    if (results.rest.isNotEmpty) {
      throw _UsageException(
          'mcp takes no positional arguments', _usageFor('mcp'));
    }
    final requestedRoots = (results['root'] as List<String>);
    final access = await _RootedFileAccess.create(
      requestedRoots.isEmpty ? [Directory.current.path] : requestedRoots,
    );
    final server = createDartPdfMcpServer(
      readFile: access.readBytes,
      readPassword: access.readPassword,
      service: service,
    );
    await server.connect(StdioServerTransport());
    return 0;
  }

  Future<String> _readCliPassword(ArgResults results) async {
    final fromStdin = results['password-stdin'] as bool;
    final envName = results['password-env'] as String?;
    final fileName = results['password-file'] as String?;
    final count = [fromStdin, envName != null, fileName != null]
        .where((selected) => selected)
        .length;
    if (count > 1) {
      throw const DartPdfRequestException(
          'choose only one password source: stdin, environment, or file');
    }
    if (fromStdin) {
      return _trimLineEnding(await stdin.transform(utf8.decoder).join());
    }
    if (envName != null) {
      final value = Platform.environment[envName];
      if (value == null) {
        throw DartPdfRequestException(
            'password environment variable "$envName" is not set');
      }
      return value;
    }
    if (fileName != null) {
      return _trimLineEnding(await File(fileName).readAsString());
    }
    return '';
  }

  String _usageFor(String operation) {
    ArgParser? current = parser;
    for (final part in operation.split('.')) {
      current = current?.commands[part];
    }
    return 'Usage: dartpdf ${operation.replaceAll('.', ' ')} [options] input.pdf\n'
        '${current?.usage ?? ''}';
  }

  void _writeUsage() {
    stdout.writeln('DartPDF command line and MCP tools\n\n'
        'Usage: dartpdf <command> [arguments]\n\n${parser.usage}');
  }
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addFlag('version', negatable: false, help: 'Show the version.');
  parser
    ..addCommand('inspect', _pdfParser())
    ..addCommand('text', _pdfParser(pages: true))
    ..addCommand(
      'forms',
      _groupParser(_pdfParser()),
    )
    ..addCommand(
      'annotations',
      _groupParser(_pdfParser(pages: true)),
    )
    ..addCommand(
      'mcp',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addMultiOption(
          'root',
          help: 'Filesystem root accessible to MCP tools. Repeatable.',
          splitCommas: false,
        ),
    );
  return parser;
}

ArgParser _groupParser(ArgParser listParser) => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addCommand('list', listParser);

ArgParser _pdfParser({bool pages = false}) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag(
      'json',
      negatable: false,
      help: 'Emit compact JSON instead of indented JSON.',
    )
    ..addFlag(
      'password-stdin',
      negatable: false,
      help: 'Read the PDF password from stdin.',
    )
    ..addOption(
      'password-env',
      help: 'Read the PDF password from this environment variable.',
    )
    ..addOption(
      'password-file',
      help: 'Read the PDF password from a protected file.',
    );
  if (pages) {
    parser.addOption(
      'pages',
      help: 'One-based pages/ranges, for example 1-5,8.',
    );
  }
  return parser;
}

class _RootedFileAccess {
  _RootedFileAccess._(this.roots);

  final List<String> roots;

  static Future<_RootedFileAccess> create(List<String> requestedRoots) async {
    final roots = <String>[];
    for (final requested in requestedRoots) {
      final directory = Directory(p.absolute(requested));
      final resolved = p.normalize(await directory.resolveSymbolicLinks());
      if (!await Directory(resolved).exists()) {
        throw FileSystemException('MCP root is not a directory', requested);
      }
      if (!roots.contains(resolved)) roots.add(resolved);
    }
    return _RootedFileAccess._(roots);
  }

  Future<Uint8List> readBytes(String requestedPath) async {
    final file = await _resolveFile(requestedPath);
    return file.readAsBytes();
  }

  Future<String> readPassword(Map<String, dynamic> arguments) async {
    final envName = arguments['passwordEnv'] as String?;
    final fileName = arguments['passwordFile'] as String?;
    if (envName != null && fileName != null) {
      throw const DartPdfRequestException(
          'choose only one password source: environment or file');
    }
    if (envName != null) {
      final value = Platform.environment[envName];
      if (value == null) {
        throw DartPdfRequestException(
            'password environment variable "$envName" is not set');
      }
      return value;
    }
    if (fileName != null) {
      return _trimLineEnding(
          await (await _resolveFile(fileName)).readAsString());
    }
    return '';
  }

  Future<File> _resolveFile(String requestedPath) async {
    if (requestedPath.trim().isEmpty) {
      throw const DartPdfRequestException('path must not be empty');
    }
    final candidates = p.isAbsolute(requestedPath)
        ? [requestedPath]
        : [for (final root in roots) p.join(root, requestedPath)];
    for (final candidate in candidates) {
      final unresolved = File(candidate);
      if (!await unresolved.exists()) continue;
      final resolved = p.normalize(await unresolved.resolveSymbolicLinks());
      final allowed = roots.any(
          (root) => p.equals(root, resolved) || p.isWithin(root, resolved));
      if (allowed) return File(resolved);
      throw DartPdfRequestException(
          'path is outside configured MCP filesystem roots: $requestedPath');
    }
    throw FileSystemException('file does not exist', requestedPath);
  }
}

String _trimLineEnding(String value) {
  if (value.endsWith('\r\n')) return value.substring(0, value.length - 2);
  if (value.endsWith('\n')) return value.substring(0, value.length - 1);
  return value;
}

class _UsageException implements Exception {
  const _UsageException(this.message, this.usage);

  final String message;
  final String usage;
}

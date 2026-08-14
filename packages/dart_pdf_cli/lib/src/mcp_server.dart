import 'dart:async';
import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';

import 'service.dart';

const _maxMcpPathChars = 32768;
const _maxMcpPageSpecChars = 4096;
const _maxMcpEnvironmentNameChars = 1024;
const _maxMcpErrorChars = 4096;

/// Reads one PDF path after the host has applied its filesystem policy.
typedef DartPdfFileReader = Future<Uint8List> Function(String path);

/// Resolves a password source from MCP tool arguments.
///
/// Implementations should prefer environment variables or protected files and
/// return an empty string when no password source was supplied.
typedef DartPdfPasswordReader = Future<String> Function(
    Map<String, dynamic> arguments);

/// Creates the read-only DartPDF MCP server over transport-independent
/// [DartPdfDocument] handlers.
McpServer createDartPdfMcpServer({
  required DartPdfFileReader readFile,
  DartPdfPasswordReader? readPassword,
  DartPdfService service = const DartPdfService(),
}) {
  final server = McpServer(
    const Implementation(name: 'dartpdf', version: '0.1.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(),
      ),
    ),
  );
  final passwordReader = readPassword ?? (_) async => '';
  final inputSchema = JsonSchema.object(
    properties: {
      'path': JsonSchema.string(
        minLength: 1,
        maxLength: _maxMcpPathChars,
        description: 'PDF path inside one of the server configured roots.',
      ),
      'passwordEnv': JsonSchema.string(
        maxLength: _maxMcpEnvironmentNameChars,
        description: 'Environment variable holding the PDF password.',
      ),
      'passwordFile': JsonSchema.string(
        maxLength: _maxMcpPathChars,
        description:
            'Protected password file inside a configured filesystem root.',
      ),
    },
    required: const ['path'],
  );
  final pagedInputSchema = JsonSchema.object(
    properties: {
      'path': JsonSchema.string(
        minLength: 1,
        maxLength: _maxMcpPathChars,
        description: 'PDF path inside one of the server configured roots.',
      ),
      'pages': JsonSchema.string(
        maxLength: _maxMcpPageSpecChars,
        description:
            'One-based pages/ranges such as "1-5,8". Defaults to a bounded prefix.',
      ),
      'passwordEnv': JsonSchema.string(
        maxLength: _maxMcpEnvironmentNameChars,
        description: 'Environment variable holding the PDF password.',
      ),
      'passwordFile': JsonSchema.string(
        maxLength: _maxMcpPathChars,
        description:
            'Protected password file inside a configured filesystem root.',
      ),
    },
    required: const ['path'],
  );
  const annotations = ToolAnnotations(
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  );

  server.registerTool(
    'inspect_pdf',
    title: 'Inspect PDF',
    description:
        'Return compact document metadata, page/form/annotation counts, encryption state, and signature state.',
    inputSchema: inputSchema,
    annotations: annotations,
    callback: (arguments, extra) => _runTool(
      arguments,
      readFile: readFile,
      readPassword: passwordReader,
      service: service,
      operation: (document, _) => document.inspect(),
    ),
  );
  server.registerTool(
    'extract_pdf_text',
    title: 'Extract PDF text',
    description:
        'Extract bounded, page-addressable text. Results are capped by the server page and character limits.',
    inputSchema: pagedInputSchema,
    annotations: annotations,
    callback: (arguments, extra) => _runTool(
      arguments,
      readFile: readFile,
      readPassword: passwordReader,
      service: service,
      operation: (document, args) =>
          document.extractText(pages: args['pages'] as String?),
    ),
  );
  server.registerTool(
    'list_pdf_forms',
    title: 'List PDF form fields',
    description:
        'List bounded AcroForm field metadata and values without Flutter.',
    inputSchema: inputSchema,
    annotations: annotations,
    callback: (arguments, extra) => _runTool(
      arguments,
      readFile: readFile,
      readPassword: passwordReader,
      service: service,
      operation: (document, _) => document.listForms(),
    ),
  );
  server.registerTool(
    'list_pdf_annotations',
    title: 'List PDF annotations',
    description:
        'List bounded annotation metadata for selected pages without Flutter.',
    inputSchema: pagedInputSchema,
    annotations: annotations,
    callback: (arguments, extra) => _runTool(
      arguments,
      readFile: readFile,
      readPassword: passwordReader,
      service: service,
      operation: (document, args) =>
          document.listAnnotations(pages: args['pages'] as String?),
    ),
  );
  return server;
}

Future<CallToolResult> _runTool(
  Map<String, dynamic> arguments, {
  required DartPdfFileReader readFile,
  required DartPdfPasswordReader readPassword,
  required DartPdfService service,
  required Map<String, Object?> Function(
          DartPdfDocument document, Map<String, dynamic> arguments)
      operation,
}) async {
  try {
    final path = arguments['path'];
    if (path is! String || path.trim().isEmpty) {
      throw const DartPdfRequestException('path must be a non-empty string');
    }
    final bytes = await readFile(path);
    final password = await readPassword(arguments);
    final result =
        operation(service.open(bytes, password: password), arguments);
    return CallToolResult.fromStructuredContent(
        Map<String, dynamic>.from(result));
  } on Object catch (error) {
    return CallToolResult(
      isError: true,
      content: [TextContent(text: _toolErrorMessage(error))],
    );
  }
}

String _toolErrorMessage(Object error) {
  var message =
      error is DartPdfRequestException ? error.message : error.toString();
  if (message.length > _maxMcpErrorChars) {
    var end = _maxMcpErrorChars;
    final last = message.codeUnitAt(end - 1);
    final next = message.codeUnitAt(end);
    if (last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      end--;
    }
    message = '${message.substring(0, end)}…';
  }
  return 'DartPDF request failed: $message';
}

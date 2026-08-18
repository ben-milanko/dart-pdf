import 'dart:io';

import 'sanitize_macho.dart';

const _usage = '''
Usage: dart tool/build_desktop_cli.dart \\
  --output <path> \\
  --target-os <linux|macos|windows> \\
  --target-arch <arm64|x64>

Compiles one native dartpdf CLI/MCP sidecar with the workspace package graph.
Universal macOS release builds compile one sidecar on each native architecture
and merge them in the release workflow.
''';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    await _build(options);
  } on _UsageError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on _BuildError catch (error) {
    stderr.writeln('dartpdf sidecar build failed: ${error.message}');
    exitCode = 1;
  }
}

Future<void> _build(_Options options) async {
  final script = File.fromUri(Platform.script).absolute;
  final repository = script.parent.parent;
  final entrypoint = File(
    '${repository.path}${Platform.pathSeparator}'
    'packages${Platform.pathSeparator}dart_pdf_cli${Platform.pathSeparator}'
    'bin${Platform.pathSeparator}dartpdf.dart',
  );
  final packageConfig = File(
    '${repository.path}${Platform.pathSeparator}'
    '.dart_tool${Platform.pathSeparator}package_config.json',
  );
  final output = File(options.output).absolute;

  if (!entrypoint.existsSync()) {
    throw _BuildError('entrypoint not found: ${entrypoint.path}');
  }
  if (!packageConfig.existsSync()) {
    throw _BuildError(
      'workspace package config not found: ${packageConfig.path}\n'
      'Run `flutter pub get` at the repository root first.',
    );
  }
  output.parent.createSync(recursive: true);

  await _compile(
    repository: repository,
    entrypoint: entrypoint,
    packageConfig: packageConfig,
    output: output,
    targetOs: options.targetOs,
    targetArch: options.targetArch,
  );

  if (options.targetOs == 'macos') {
    sanitizeMachoFile(output);
  }

  stdout.writeln(
    'Built ${output.path} (${options.targetOs}/${options.targetArch})',
  );
}

Future<void> _compile({
  required Directory repository,
  required File entrypoint,
  required File packageConfig,
  required File output,
  required String targetOs,
  required String targetArch,
}) {
  return _run(
    Platform.resolvedExecutable,
    [
      'compile',
      'exe',
      '--target-os',
      targetOs,
      '--target-arch',
      targetArch,
      '--packages=${packageConfig.path}',
      '--output=${output.path}',
      entrypoint.path,
    ],
    workingDirectory: repository.path,
  );
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) {
    throw _BuildError('$executable exited with status $result');
  }
}

final class _Options {
  const _Options({
    required this.output,
    required this.targetOs,
    required this.targetArch,
  });

  factory _Options.parse(List<String> arguments) {
    String? output;
    String? targetOs;
    String? targetArch;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String valueAfter(String name) {
        if (index + 1 >= arguments.length) {
          throw _UsageError('missing value for $name');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--output':
          output = valueAfter(argument);
        case '--target-os':
          targetOs = valueAfter(argument);
        case '--target-arch':
          if (targetArch != null) {
            throw _UsageError('--target-arch may only be supplied once');
          }
          targetArch = _normalizeArchitecture(valueAfter(argument));
        case '-h':
        case '--help':
          stdout.writeln(_usage);
          exit(0);
        default:
          throw _UsageError('unknown argument: $argument');
      }
    }

    if (output == null || output.isEmpty) {
      throw _UsageError('--output is required');
    }
    if (!const {'linux', 'macos', 'windows'}.contains(targetOs)) {
      throw _UsageError('--target-os must be linux, macos, or windows');
    }
    if (targetArch == null) {
      throw _UsageError('--target-arch is required');
    }

    return _Options(
      output: output,
      targetOs: targetOs!,
      targetArch: targetArch,
    );
  }

  final String output;
  final String targetOs;
  final String targetArch;
}

String _normalizeArchitecture(String architecture) {
  return switch (architecture.toLowerCase()) {
    'amd64' || 'x86_64' => 'x64',
    'aarch64' => 'arm64',
    'arm64' || 'x64' => architecture.toLowerCase(),
    _ => throw _UsageError('unsupported target architecture: $architecture'),
  };
}

final class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}

final class _BuildError implements Exception {
  const _BuildError(this.message);

  final String message;
}

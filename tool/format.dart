import 'dart:io';

/// Runs the SDK formatter with the workspace's language version explicitly.
///
/// In a fresh checkout, `pub get` may not have created
/// `.dart_tool/package_config.json` yet. Without that file, `dart format`
/// assumes the latest language version and can migrate this Dart 3.5 workspace
/// to the newer tall style. Passing the pubspec's lower bound keeps formatting
/// stable both before and after dependency resolution.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: fvm dart tool/format.dart [dart format options] <paths...>',
    );
    exitCode = 64;
    return;
  }
  if (arguments.any((argument) =>
      argument == '--language-version' ||
      argument.startsWith('--language-version='))) {
    stderr.writeln(
      'tool/format.dart owns --language-version; update the root pubspec '
      'SDK constraint instead.',
    );
    exitCode = 64;
    return;
  }

  final repoRoot = File.fromUri(Platform.script).parent.parent;
  final pubspec = File('${repoRoot.path}/pubspec.yaml').readAsStringSync();
  final sdkMatch = RegExp(
    r'''^\s+sdk:\s*["']?[^\d\r\n]*(\d+)\.(\d+)''',
    multiLine: true,
  ).firstMatch(pubspec);
  if (sdkMatch == null) {
    stderr.writeln('Could not read the SDK lower bound from pubspec.yaml.');
    exitCode = 65;
    return;
  }
  final languageVersion = '${sdkMatch[1]}.${sdkMatch[2]}';

  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      'format',
      '--language-version=$languageVersion',
      ...arguments,
    ],
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}

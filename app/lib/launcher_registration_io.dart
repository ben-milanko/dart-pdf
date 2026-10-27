import 'dart:async';
import 'dart:convert';
import 'dart:io';

String? _helper() {
  if (!Platform.isLinux ||
      Platform.environment.containsKey('SNAP') ||
      Platform.environment.containsKey('FLATPAK_ID')) {
    return null;
  }
  final file = File(
      '${File(Platform.resolvedExecutable).parent.path}/install-desktop.py');
  return file.existsSync() ? file.path : null;
}

Future<ProcessResult> _run(List<String> args) async {
  final helper = _helper();
  if (helper == null) throw UnsupportedError('No portable installer');
  final process = await Process.start('python3', [helper, ...args]);
  final output = StringBuffer();
  final errors = StringBuffer();
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(output.write, onDone: stdoutDone.complete);
  final err = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(errors.write, onDone: stderrDone.complete);
  try {
    final results = await Future.wait<Object?>([
      process.exitCode,
      stdoutDone.future,
      stderrDone.future,
    ]).timeout(const Duration(seconds: 15));
    return ProcessResult(process.pid, results.first as int, output.toString(),
        errors.toString());
  } finally {
    process.kill(ProcessSignal.sigkill);
    await out.cancel();
    await err.cancel();
  }
}

Future<String> launcherRegistrationStatus() async {
  if (_helper() == null) return 'unsupported';
  try {
    final result = await _run(['--status']);
    if (result.exitCode != 0) return 'unsupported';
    return (jsonDecode(result.stdout as String)
        as Map<String, dynamic>)['status'] as String;
  } catch (_) {
    return 'unsupported';
  }
}

Future<void> registerLauncher() async {
  final result = await _run([]);
  if (result.exitCode != 0 ||
      await launcherRegistrationStatus() != 'registered') {
    throw const FileSystemException(
        'Launcher registration could not be verified');
  }
}

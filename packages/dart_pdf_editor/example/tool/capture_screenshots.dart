// Host orchestrator for native device screenshots.
//
// Launches the self-driving screenshot app (lib/screenshots_main.dart)
// with `flutter run`, watches its stdout for the per-scene markers it
// prints, and fires the platform's native screenshot tool for each one:
//   iOS      xcrun simctl io <udid> screenshot
//   Android  adb -s <serial> exec-out screencap -p
//   macOS    screencapture -R <front-window-bounds>
//
// Driven by env (tool/screenshots.sh sets these); can also be run by
// hand once a device is booted:
//   SHOT_PLATFORM=ios SHOT_DEVICE=<udid> FLUTTER_DEVICE=<udid> \
//     dart run tool/capture_screenshots.dart
//
// Env:
//   SHOT_PLATFORM     ios | android | macos               (required)
//   FLUTTER_DEVICE    `flutter run -d` id (sim udid / adb serial / macos)
//   SHOT_DEVICE       simctl udid / adb serial; unused on macos
//   SHOT_ENTRY        run target (default: lib/screenshots_main.dart)
//   SHOT_MAC_PROCESS  macOS app process name to crop to (else frontmost)
//   SHOT_OUT          output root (default: screenshots)
//   FLUTTER           flutter launcher (default: "fvm flutter", else "flutter")

import 'dart:async';
import 'dart:convert';
import 'dart:io';

late final String platform;
late final String shotDevice;
late final String outRoot;
late final String macProcess;

Future<void> main() async {
  platform = _env('SHOT_PLATFORM');
  final flutterDevice = _env('FLUTTER_DEVICE');
  shotDevice = Platform.environment['SHOT_DEVICE'] ?? 'booted';
  outRoot = Platform.environment['SHOT_OUT'] ?? 'screenshots';
  macProcess = _env('SHOT_MAC_PROCESS');
  final entry = Platform.environment['SHOT_ENTRY'] ?? 'lib/screenshots_main.dart';
  if (platform.isEmpty || flutterDevice.isEmpty) {
    stderr.writeln('SHOT_PLATFORM and FLUTTER_DEVICE are required.');
    exit(2);
  }

  Directory('$outRoot/$platform').createSync(recursive: true);

  final launcher = (Platform.environment['FLUTTER'] ??
          (await _has('fvm') ? 'fvm flutter' : 'flutter'))
      .split(' ');
  final args = [
    ...launcher.skip(1),
    'run',
    '-d', flutterDevice,
    '-t', entry,
    '--no-dds',
  ];

  stdout.writeln('[capture] flutter ${args.join(' ')}  ($platform)');
  final proc = await Process.start(launcher.first, args,
      workingDirectory: Directory.current.path);

  var captured = 0;
  final done = Completer<void>();
  // Serialize captures so a slow grab can't overlap the next marker.
  var chain = Future<void>.value();

  void handle(String line) {
    // Surface the app/flutter logs so a failed run is debuggable.
    stdout.writeln(line);
    final shot = RegExp(r'@@SHOT@@ (\S+)').firstMatch(line);
    if (shot != null) {
      final name = shot.group(1)!;
      chain = chain.then((_) async {
        await _capture(name);
        captured++;
      });
    } else if (line.contains('@@SHOT_DONE@@')) {
      chain = chain.then((_) {
        if (!done.isCompleted) done.complete();
      });
    }
  }

  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handle);
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(stderr.writeln);

  // Bail if the run wedges (build failure, device never settles).
  final timeout = Future<void>.delayed(const Duration(minutes: 8), () {
    if (!done.isCompleted) {
      stderr.writeln('[capture] timed out waiting for scenes.');
      done.complete();
    }
  });

  await Future.any([done.future, timeout]);
  await chain; // let the last queued capture finish

  // Quit `flutter run` cleanly, then make sure the process is gone.
  proc.stdin.write('q');
  await proc.stdin.flush().catchError((_) {});
  unawaited(proc.stdin.close().catchError((_) {}));
  await proc.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
    proc.kill(ProcessSignal.sigterm);
    return -1;
  });

  stdout.writeln('[capture] $captured screenshot(s) → $outRoot/$platform/');
  if (captured == 0) exit(1);
}

Future<void> _capture(String name) async {
  final path = '$outRoot/$platform/$name.png';
  // Let the compositor present the held frame before reading the screen.
  await Future<void>.delayed(const Duration(milliseconds: 700));

  ProcessResult result;
  switch (platform) {
    case 'ios':
      result = await Process.run(
          'xcrun', ['simctl', 'io', shotDevice, 'screenshot', path]);
    case 'android':
      result = await Process.run(
          'adb', ['-s', shotDevice, 'exec-out', 'screencap', '-p'],
          stdoutEncoding: null);
      if (result.exitCode == 0) {
        await File(path).writeAsBytes(result.stdout as List<int>);
      }
    case 'macos':
      result = await _captureMacWindow(path);
    default:
      stderr.writeln('[capture] unknown platform "$platform"');
      return;
  }

  if (result.exitCode != 0) {
    stderr.writeln('[capture] $name failed (exit ${result.exitCode}): '
        '${result.stderr}');
  } else {
    stdout.writeln('[capture] shot: $path');
  }
}

/// Captures just the app's window on macOS. Asks System Events for the
/// bounds of the *largest* window of the target process (named via
/// SHOT_MAC_PROCESS, else the frontmost app) — the largest window is the
/// document window, never a tooltip/popup that briefly steals focus — and
/// crops to it with `screencapture -R`. Falls back to the whole main
/// display if the bounds can't be read (e.g. Automation not yet granted).
Future<ProcessResult> _captureMacWindow(String path) async {
  // Raise the app so no other window overlaps the cropped region —
  // `screencapture -R` grabs the screen, not the window's backing store,
  // so anything on top (a terminal, the IDE) would bleed in otherwise.
  if (macProcess.isNotEmpty) {
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of process '
          '"$macProcess" to true',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  final selector = macProcess.isNotEmpty
      ? 'process "$macProcess"'
      : 'first process whose frontmost is true';
  final script = '''
tell application "System Events"
  set theProc to $selector
  set bestArea to -1
  set bestRect to {0, 0, 0, 0}
  repeat with w in windows of theProc
    set sz to size of w
    set ar to (item 1 of sz) * (item 2 of sz)
    if ar > bestArea then
      set bestArea to ar
      set ps to position of w
      set bestRect to {item 1 of ps, item 2 of ps, item 1 of sz, item 2 of sz}
    end if
  end repeat
  return bestRect
end tell''';
  final bounds = await Process.run('osascript', ['-e', script]);
  if (bounds.exitCode == 0) {
    final nums = RegExp(r'-?\d+')
        .allMatches(bounds.stdout.toString())
        .map((m) => m.group(0)!)
        .toList();
    // Reject the {0,0,0,0} default (no window found / zero area).
    if (nums.length >= 4 && int.parse(nums[2]) > 0 && int.parse(nums[3]) > 0) {
      final region = '${nums[0]},${nums[1]},${nums[2]},${nums[3]}';
      return Process.run('screencapture', ['-x', '-R', region, path]);
    }
    stderr.writeln('[capture] no window for ${macProcess.isEmpty ? 'frontmost app' : '"$macProcess"'}; full display.');
  } else {
    stderr.writeln('[capture] osascript failed (${bounds.stderr}); full display.');
  }
  return Process.run('screencapture', ['-x', path]);
}

String _env(String key) => Platform.environment[key] ?? '';

Future<bool> _has(String cmd) async {
  try {
    final r = await Process.run('command', ['-v', cmd], runInShell: true);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

// Host orchestrator for native device screenshots.
//
// Launches the self-driving screenshot app (lib/screenshots_main.dart)
// with `flutter run`, watches its stdout for the per-scene markers it
// prints, and fires the platform's native screenshot tool for each one:
//   iOS      xcrun simctl io <udid> screenshot
//   Android  adb -s <serial> exec-out screencap -p
//   macOS    screencapture -l <windowID> (window id by pid via CGWindowList;
//            the pid is the one we launched, parsed from the run output, so an
//            installed copy of the same-named app can't be captured instead)
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
//   SHOT_MAC_APP_HINT path substring identifying *our* app instance, so the
//                     crop targets it by pid even when another copy of the
//                     same-named app (e.g. an installed build) is running
//   SHOT_OUT          output root (default: screenshots)
//   FLUTTER           flutter launcher (default: "fvm flutter", else "flutter")

import 'dart:async';
import 'dart:convert';
import 'dart:io';

late final String platform;
late final String shotDevice;
late final String outRoot;
late final String macProcess;
late final String macAppHint;

/// PID of the app instance *we* launched, parsed from the macOS embedder's
/// startup log line (`AppName[pid:tid] Running with merged UI…`). This is
/// unambiguous even when an installed copy of the same-named app is already
/// running — the bug that made every macOS shot a full-display grab, because
/// the name fallback resolved to the installed app, which had no window.
int? launchedPid;

/// Path to the compiled CGWindowList helper (prints a window id + bounds for a
/// pid). Null when it couldn't be built, in which case the macOS crop degrades
/// to the System Events region path, then a full-display grab.
String? macWinHelper;

Future<void> main() async {
  platform = _env('SHOT_PLATFORM');
  final flutterDevice = _env('FLUTTER_DEVICE');
  shotDevice = Platform.environment['SHOT_DEVICE'] ?? 'booted';
  outRoot = Platform.environment['SHOT_OUT'] ?? 'screenshots';
  macProcess = _env('SHOT_MAC_PROCESS');
  macAppHint = _env('SHOT_MAC_APP_HINT');
  final entry = Platform.environment['SHOT_ENTRY'] ?? 'lib/screenshots_main.dart';
  if (platform.isEmpty || flutterDevice.isEmpty) {
    stderr.writeln('SHOT_PLATFORM and FLUTTER_DEVICE are required.');
    exit(2);
  }

  Directory('$outRoot/$platform').createSync(recursive: true);

  // Build the window-capture helper up front so the first scene can use it.
  if (platform == 'macos') macWinHelper = await _buildMacWinHelper();

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
    // Grab our launched app's pid from the macOS embedder's first log line
    // (`AppName[pid:tid] …`). First match wins — that's the main process.
    if (platform == 'macos' && launchedPid == null && macProcess.isNotEmpty) {
      final m = RegExp('${RegExp.escape(macProcess)}' r'\[(\d+):\d+\]')
          .firstMatch(line);
      if (m != null) {
        launchedPid = int.parse(m.group(1)!);
        stdout.writeln('[capture] $macProcess launched as pid $launchedPid');
      }
    }
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
  // Terminate now. The 8-minute fallback timer and the flutter-run output
  // streams would otherwise keep the VM alive long after the work is done,
  // stalling the shell that waits on us (and the compose step that follows it).
  exit(captured == 0 ? 1 : 0);
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

/// Captures just the app's window on macOS, by pid.
///
/// The pid is the one we *launched* (parsed from the embedder's log line), so
/// it can never resolve to an installed copy of the same-named app — the bug
/// that turned every shot into a full-display grab. It falls back to the
/// SHOT_MAC_APP_HINT path match (for hand runs) and finally the process name.
///
/// Primary path: ask the CGWindowList helper for the largest on-screen window
/// owned by the pid and grab that window's own backing store with
/// `screencapture -l<id>`. This needs no Automation permission and can't pick
/// up an overlapping window. If the helper is unavailable it falls back to the
/// System Events window bounds + `screencapture -R <region>` crop (which does
/// need Automation), and finally to a full-display grab.
Future<ProcessResult> _captureMacWindow(String path) async {
  final pid = launchedPid ?? await _macAppPid();

  // Once, before the first shot: size + place the window so every capture is a
  // consistent, high-resolution frame regardless of which display the app
  // happened to open on.
  if (pid != null) await _prepareMacWindow(pid);

  // Preferred: capture the window's backing store by CGWindowID.
  if (macWinHelper != null && pid != null) {
    final info = await Process.run(macWinHelper!, ['$pid']);
    if (info.exitCode == 0) {
      final id = info.stdout.toString().trim().split(RegExp(r'\s+')).first;
      if (id.isNotEmpty) {
        final cap =
            await Process.run('screencapture', ['-x', '-o', '-l$id', path]);
        if (cap.exitCode == 0) return cap;
        stderr.writeln('[capture] screencapture -l$id failed '
            '(${cap.stderr}); trying region crop.');
      }
    } else {
      stderr.writeln('[capture] no on-screen window for pid $pid; '
          'trying region crop.');
    }
  }

  // Fallback: System Events bounds + region crop (needs Automation access).
  final selector = pid != null
      ? 'first process whose unix id is $pid'
      : macProcess.isNotEmpty
          ? 'process "$macProcess"'
          : 'first process whose frontmost is true';

  // Raise the app so no other window overlaps the cropped region —
  // `screencapture -R` grabs the screen, not the window's backing store,
  // so anything on top (a terminal, the IDE) would bleed in otherwise.
  if (pid != null || macProcess.isNotEmpty) {
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of ($selector) to true',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

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

/// Whether [_prepareMacWindow] has already run this session (it's a one-time,
/// idempotent setup; later captures keep the window it placed).
bool _macWindowPrepared = false;

/// Sizes and positions the app window once, before the first macOS capture, so
/// every shot is a deterministic, high-resolution frame.
///
/// The window is moved onto the main display's top-left and sized to the macOS
/// store aspect (SHOT_MAC_WINDOW, default 1440×900). On a 2× (Retina) main
/// display that captures as exactly 2880×1800 — a valid Mac App Store size with
/// no upscaling; on a 1× display it's 1440×900, still ample for the marketing
/// canvas. Needs Automation access; if that's unavailable (e.g. a CI runner)
/// the default-sized window is captured instead — smaller, but never broken.
Future<void> _prepareMacWindow(int pid) async {
  if (_macWindowPrepared) return;
  _macWindowPrepared = true;

  final size = (Platform.environment['SHOT_MAC_WINDOW'] ?? '1440x900')
      .split(RegExp(r'[x ]'))
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
  if (size.length < 2) return;
  final w = size[0], h = size[1];

  // No `set frontmost` here: the `-l` capture grabs the window's own backing
  // store even when it's behind other windows, so we never steal the user's
  // focus. (Apps that run Flutter's merged UI/platform thread expose no windows
  // to AX at all — `count of windows` is 0 — so this is a no-op there and the
  // window is captured at its default size.)
  final script = '''
tell application "System Events"
  set p to first process whose unix id is $pid
  if (count of windows of p) > 0 then
    set position of window 1 of p to {120, 80}
    set size of window 1 of p to {$w, $h}
  end if
end tell''';
  final r = await Process.run('osascript', ['-e', script]);
  if (r.exitCode != 0) {
    stderr.writeln('[capture] could not resize window (${r.stderr.toString().trim()}); '
        'capturing it at its default size.');
  }
  // Let the resize/move animation and the relayout settle before the grab.
  await Future<void>.delayed(const Duration(milliseconds: 700));
}

/// Resolves the pid of *our* running app from SHOT_MAC_APP_HINT (a path
/// substring unique to this build). Returns null when no hint is set or no
/// match is running, so the caller can fall back to name/frontmost targeting.
Future<int?> _macAppPid() async {
  if (macAppHint.isEmpty) return null;
  final r = await Process.run('pgrep', ['-f', macAppHint]);
  if (r.exitCode != 0) return null;
  // Lowest pid is the main app process (children spawn after it).
  final pids = (r.stdout as String)
      .split('\n')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList()
    ..sort();
  return pids.isEmpty ? null : pids.first;
}

/// Compiles the tiny CGWindowList helper to a temp binary once, returning its
/// path (or null if the Swift toolchain isn't available). The helper prints
/// `windowID x y w h` for the largest on-screen, normal-layer window
/// owned by a pid — enough to feed `screencapture -l`. Reading window geometry
/// needs neither Automation nor Screen Recording permission.
Future<String?> _buildMacWinHelper() async {
  try {
    final tmp = Directory.systemTemp;
    final src = File('${tmp.path}/dart_pdf_winid.swift')
      ..writeAsStringSync(_winidSwiftSource);
    final bin = '${tmp.path}/dart_pdf_winid';
    final r = await Process.run('xcrun', ['swiftc', '-O', src.path, '-o', bin]);
    if (r.exitCode == 0) {
      stdout.writeln('[capture] built macOS window helper at $bin');
      return bin;
    }
    stderr.writeln('[capture] swiftc failed (${r.stderr}); '
        'macOS crop will use System Events.');
  } catch (e) {
    stderr.writeln('[capture] window helper unavailable ($e); '
        'macOS crop will use System Events.');
  }
  return null;
}

/// CoreGraphics window-list helper, compiled at runtime by [_buildMacWinHelper].
const _winidSwiftSource = r'''
import CoreGraphics
import Foundation

// Prints "windowID x y w h" for the largest on-screen, normal-layer window
// owned by the given pid; exits 1 if none. Uses only the public window list,
// so it needs neither Automation nor Screen Recording for geometry.
guard CommandLine.arguments.count > 1,
      let pid = Int(CommandLine.arguments[1]) else {
  FileHandle.standardError.write("usage: winid <pid>\n".data(using: .utf8)!)
  exit(2)
}
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
        as? [[String: Any]] else { exit(1) }
var best: (id: Int, x: Int, y: Int, w: Int, h: Int)? = nil
var bestArea = -1
for info in infos {
  guard let owner = info[kCGWindowOwnerPID as String] as? Int,
        owner == pid else { continue }
  let layer = info[kCGWindowLayer as String] as? Int ?? 0
  if layer != 0 { continue }                 // skip menus/panels/popovers
  guard let id = info[kCGWindowNumber as String] as? Int,
        let b = info[kCGWindowBounds as String] as? [String: Any],
        let x = b["X"] as? Int, let y = b["Y"] as? Int,
        let w = b["Width"] as? Int, let h = b["Height"] as? Int else { continue }
  let area = w * h
  if area > bestArea { bestArea = area; best = (id, x, y, w, h) }
}
guard let r = best else { exit(1) }
print("\(r.id) \(r.x) \(r.y) \(r.w) \(r.h)")
''';

String _env(String key) => Platform.environment[key] ?? '';

Future<bool> _has(String cmd) async {
  try {
    final r = await Process.run('command', ['-v', cmd], runInShell: true);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

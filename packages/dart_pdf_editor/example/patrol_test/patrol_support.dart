// Shared set-up for the native Patrol targets. This file deliberately does not
// end in `_test.dart`, so Patrol never bundles it as a test of its own.

import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// File name (inside the app's temporary directory) that receives a copy of
/// every `[perf …]` line, or empty to keep the trace console-only.
///
/// CI sets it per attempt and reads the file back out of the simulator's app
/// container. The streamed device log is not a reliable transport for these
/// lines: Patrol stops streaming the moment the native runner exits, which on
/// the iOS simulator is routinely before the last test's tail - the scenario
/// markers the performance report needs - has been forwarded.
const patrolPerfTraceName = String.fromEnvironment('PDF_PATROL_PERF_TRACE');

/// Mirrors [PdfPerfLog] into [patrolPerfTraceName] when CI asked for it.
///
/// Every Patrol test runs in a fresh app launch, and each launch runs `main()`
/// again, so the file is opened for append: the tests of one attempt write one
/// trace, in execution order. Each line is a single unbuffered `write(2)`, so
/// a line is on disk as soon as it is logged and nothing is lost when the
/// native runner terminates the app between tests - and there is no per-line
/// flush for the file to cost the timings it records.
void mirrorPerfTraceToFile() {
  const name = patrolPerfTraceName;
  if (name.isEmpty) return;
  if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
    throw ArgumentError.value(name, 'PDF_PATROL_PERF_TRACE',
        'must be a plain file name inside the app temporary directory');
  }
  final file = File('${Directory.systemTemp.path}/$name');
  final trace = file.openSync(mode: FileMode.append);
  // Printed (not traced) so the CI log records where to look if the pull ever
  // comes back empty.
  debugPrint('patrol perf trace file=${file.path}');
  PdfPerfLog.sink = (line) => trace.writeStringSync('$line\n');
}

/// Closes the window in which a platform accessibility toggle fails a test
/// that otherwise passed.
///
/// When the OS turns semantics on (Android's UiAutomator connecting for the
/// native automator, or VoiceOver-style services on iOS), the framework's
/// default `onSemanticsEnabledChanged` handler takes a `SemanticsHandle`. If
/// that lands after `testWidgets` has recorded the handle count but before
/// Patrol's own workaround (leancodepl/patrol#1474: it installs a no-op
/// handler as the first statement of the test body) runs, the end-of-test
/// check fails the test with "A SemanticsHandle was active at the end of the
/// test" - the Dart body passed, the harness did not. Installing the same
/// no-op before the file's first test runs leaves no such window. The tests
/// still see a semantics tree: `patrolTest` enables it for every test through
/// its own handle.
void guardPlatformSemanticsToggles() {
  setUpAll(() {
    WidgetsBinding.instance.platformDispatcher.onSemanticsEnabledChanged =
        () {};
  });
}

/// Reports *what* overflowed when a [RenderFlex] overflow fails a test.
///
/// Flutter's overflow report names only the flex and its own size, and by the
/// time Patrol prints it the render tree is disposed. This walks the flex
/// while it is still alive: each child's creator and size, then down the
/// tallest child through every render object taller than the flex, so the log
/// ends at the box that is actually too big. Returns a callback that puts the
/// previous [FlutterError.onError] back; call it before the test ends.
VoidCallback reportFlexOverflowCulprits() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final flex = _overflowingFlex(details);
    if (flex != null) debugPrint(_describeOverflow(flex));
    previous?.call(details);
  };
  return () => FlutterError.onError = previous;
}

RenderFlex? _overflowingFlex(FlutterErrorDetails details) {
  if (!details.exceptionAsString().contains('overflowed')) return null;
  // the report describes the flex itself as one of its diagnostics nodes
  for (final node
      in details.informationCollector?.call() ?? const <DiagnosticsNode>[]) {
    if (node.value case final RenderFlex flex) return flex;
  }
  return null;
}

String _describeOverflow(RenderFlex flex) {
  final out = StringBuffer('flex overflow culprits: ${_box(flex)}\n');
  final children = <RenderBox>[];
  flex.visitChildren((child) => children.add(child as RenderBox));
  for (final child in children) {
    out.writeln('  child ${_box(child)}');
  }
  final extent =
      flex.direction == Axis.vertical ? flex.size.height : flex.size.width;
  double main(RenderBox box) => !box.hasSize
      ? 0
      : flex.direction == Axis.vertical
          ? box.size.height
          : box.size.width;
  RenderObject? tallest = children.isEmpty
      ? null
      : children.reduce((a, b) => main(a) >= main(b) ? a : b);
  for (var depth = 0; tallest is RenderBox && depth < 60; depth++) {
    out.writeln('  ${'  ' * (depth % 20)}> ${_box(tallest)}');
    RenderBox? next;
    tallest.visitChildren((child) {
      if (child is RenderBox &&
          main(child) > extent &&
          (next == null || main(child) > main(next!))) {
        next = child;
      }
    });
    tallest = next;
  }
  return out.toString();
}

String _box(RenderBox box) {
  final creator = box.debugCreator?.toString() ?? '?';
  final shortCreator =
      creator.length > 240 ? '${creator.substring(0, 240)}…' : creator;
  return '${box.runtimeType} '
      'size=${box.hasSize ? box.size : 'none'} '
      'constraints=${box.constraints} '
      'creator=$shortCreator';
}

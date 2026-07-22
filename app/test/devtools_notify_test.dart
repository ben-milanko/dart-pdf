// The devtools log/timing capture must not let its own notify machinery drive
// the frames it measures: high-volume perf-trace lines record silently, and
// nothing schedules a rebuild while the panel is closed.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/devtools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tools = AppDevTools.instance;

  setUp(tools.clearLog);

  tearDown(() {
    tools.logPerfTrace = false;
    tools.clearLog();
  });

  test('a perf-sink line is recorded without notifying listeners', () async {
    tools.logPerfTrace = true;
    var notifies = 0;
    void listener() => notifies++;
    tools.addListener(listener);
    addTearDown(() => tools.removeListener(listener));

    PdfPerfLog.sink!('JANK 20.0ms');
    await pumpEventQueue();

    expect(notifies, 0);
    expect(tools.log.map((e) => e.message), contains('perf: JANK 20.0ms'));
  });

  test('an ordinary addLog notifies listeners', () async {
    var notifies = 0;
    void listener() => notifies++;
    tools.addListener(listener);
    addTearDown(() => tools.removeListener(listener));

    // _scheduleNotify throttles to 250 ms and this is a process-wide
    // singleton, so a notify from an earlier test would swallow this one.
    // Wait the window out rather than depend on test order.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    tools.addLog('ordinary line');
    await pumpEventQueue();

    expect(notifies, 1);
    expect(tools.log.map((e) => e.message), contains('ordinary line'));
  });

  test('with no listeners, entries are still recorded', () {
    tools.addLog('quiet history');
    tools.logPerfTrace = true;
    PdfPerfLog.sink!('JANK 21.0ms');

    final messages = tools.log.map((e) => e.message);
    expect(messages, contains('quiet history'));
    expect(messages, contains('perf: JANK 21.0ms'));
  });

  test('a listener attached later sees the previously recorded entries',
      () async {
    tools.addLog('before the panel opened');

    void listener() {}
    tools.addListener(listener);
    addTearDown(() => tools.removeListener(listener));

    // History is read from the log itself, not pushed through a notify.
    expect(tools.log.map((e) => e.message),
        contains('before the panel opened'));
  });
}

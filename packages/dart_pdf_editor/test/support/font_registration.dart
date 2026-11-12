import 'package:flutter_test/flutter_test.dart';

/// Lets an engine font registration (`FontLoader` / `ui.loadFontFromList`)
/// finish its round trip before a widget test ends.
///
/// Registering a font makes the engine post a `fontsChange` system message,
/// which `RelayoutWhenSystemFontsChangeMixin` answers with a frame callback.
/// Since Flutter 3.50 that message lands on a later *real* event-loop turn,
/// after the test's fake-async pumps have finished, so the callback is still
/// pending at teardown and the harness fails the test with "An animation is
/// still running even after the widget tree was disposed". One real turn
/// delivers the message and a pump runs its callback.
///
/// Call it at the end of a test that registers a font family the engine has
/// not seen yet in this isolate.
Future<void> settleFontRegistration(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

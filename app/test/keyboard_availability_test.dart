import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/keyboard_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('dev.milanko.dartpdf/keyboard');
  const codec = StandardMethodCodec();
  final mobilePlatforms =
      TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});
  late bool connected;
  late int queries;
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connected = false;
    queries = 0;
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isConnected');
      queries++;
      return connected;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> notify(WidgetTester tester, bool value) async {
    connected = value;
    final reply = Completer<void>();
    messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('changed', value)),
        (_) => reply.complete());
    await reply.future;
    await tester.pump();
  }

  Widget root(Widget child) => MaterialApp(
        builder: (context, child) => KeyboardAvailability(child: child!),
        home: Scaffold(body: child),
      );

  Widget signal() => Builder(
      builder: (context) =>
          Text('keyboard: ${PdfKeyboardAvailability.of(context)}'));

  testWidgets('mobile tracks keyboard connections and refreshes after resume',
      (tester) async {
    connected = true;
    await tester.pumpWidget(root(signal()));
    await tester.pump();
    expect(find.text('keyboard: true'), findsOneWidget);
    await notify(tester, false);
    expect(find.text('keyboard: false'), findsOneWidget);
    // The software keyboard opening is not a physical connection.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(find.text('keyboard: false'), findsOneWidget);
    await notify(tester, true);
    expect(find.text('keyboard: true'), findsOneWidget);
    connected = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('keyboard: false'), findsOneWidget);
    expect(queries, 2);
  }, variant: mobilePlatforms);

  testWidgets('an old inventory reply cannot overwrite a newer disconnect',
      (tester) async {
    final inventory = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => inventory.future);
    await tester.pumpWidget(root(signal()));
    expect(find.text('keyboard: false'), findsOneWidget);
    await notify(tester, true);
    await notify(tester, false);
    inventory.complete(true);
    await tester.pump();
    expect(find.text('keyboard: false'), findsOneWidget);
  });

  testWidgets('missing mobile bridge keeps hints hidden', (tester) async {
    messenger.setMockMethodCallHandler(channel, null);
    await tester.pumpWidget(root(signal()));
    await tester.pump();
    expect(find.text('keyboard: false'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps shortcut hints without querying the mobile bridge',
      (tester) async {
    await tester.pumpWidget(root(signal()));
    expect(find.text('keyboard: true'), findsOneWidget);
    expect(queries, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('an open app menu updates shortcut hints without losing actions',
      (tester) async {
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(root(EditorScreen(prefs: prefs)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    expect(find.text('New document…'), findsOneWidget);
    expect(find.text('Ctrl+N'), findsNothing);
    expect(find.text('Ctrl+K'), findsNothing);
    await notify(tester, true);
    expect(find.text('Ctrl+N'), findsOneWidget);
    expect(find.text('Ctrl+K'), findsOneWidget);
    await notify(tester, false);
    expect(find.text('Ctrl+N'), findsNothing);
    expect(find.text('Ctrl+K'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-command-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('command-palette-field')), 'print');
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+P'), findsNothing);
    // A disabled command still explains why it is unavailable.
    expect(find.text('Needs an open document'), findsOneWidget);
    await notify(tester, true);
    expect(find.textContaining('↑'), findsOneWidget);
    await notify(tester, false);
    expect(find.textContaining('↑'), findsNothing);
  });

  testWidgets('tooltips and open mobile Settings follow keyboard availability',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(
        root(PdfEditorView(bytes: buildClassicPdf(), preferences: prefs)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Undo'), findsOneWidget);
    await notify(tester, true);
    expect(find.byTooltip('Undo (⌘Z)'), findsOneWidget);
    await notify(tester, false);
    await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-shell-shortcuts')), findsNothing);
    await notify(tester, true);
    expect(find.byKey(const ValueKey('pdf-shell-shortcuts')), findsOneWidget);
    await notify(tester, false);
    expect(find.byKey(const ValueKey('pdf-shell-shortcuts')), findsNothing);
  });

  testWidgets('hidden hints do not disable keyboard commands', (tester) async {
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(root(EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildClassicPdf(), title: 'Report.pdf'))));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
    expect(find.text('Ctrl+N'), findsNothing);
  });
}

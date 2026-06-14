// Apple Pencil hardware double-tap → eraser toggle: the controller pairing
// (PdfEditingController.togglePencilEraser) and the method-channel binding
// (PdfPencilInteraction) that the native iOS gesture drives.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PdfEditingController controller() {
    final c = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(c.dispose);
    return c;
  }

  group('togglePencilEraser', () {
    test('from reader mode arms the eraser and toggles back to reader', () {
      final c = controller();
      expect(c.tool, isNull);

      c.togglePencilEraser();
      expect(c.tool, PdfEditTool.eraser);

      c.togglePencilEraser();
      expect(c.tool, isNull, reason: 'restores the exact prior state');
    });

    test('pairs with the tool that was armed', () {
      final c = controller();
      c.tool = PdfEditTool.ink;

      c.togglePencilEraser();
      expect(c.tool, PdfEditTool.eraser);

      c.togglePencilEraser();
      expect(c.tool, PdfEditTool.ink, reason: 'returns to the drawing tool');
    });

    test('a hand-armed eraser toggles back to ink', () {
      final c = controller();
      c.tool = PdfEditTool.eraser; // armed directly, never paired

      c.togglePencilEraser();
      expect(c.tool, PdfEditTool.ink);
    });

    test('arming another tool while toggled-on breaks the pairing', () {
      final c = controller();
      c.tool = PdfEditTool.ink;
      c.togglePencilEraser(); // eraser, remembering ink
      expect(c.tool, PdfEditTool.eraser);

      // user manually switches away and back to a fresh tool
      c.tool = PdfEditTool.rectangle;
      c.togglePencilEraser(); // eraser, now remembering rectangle
      expect(c.tool, PdfEditTool.eraser);

      c.togglePencilEraser();
      expect(c.tool, PdfEditTool.rectangle);
    });

    test('notifies listeners', () {
      final c = controller();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.togglePencilEraser();
      expect(notifications, greaterThan(0));
    });
  });

  group('PdfPencilInteraction', () {
    // Delivers a native call to the channel's registered handler, the way the
    // iOS UIPencilInteraction does at runtime.
    Future<void> sendDoubleTap() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      return messenger.handlePlatformMessage(
        PdfPencilInteraction.channel.name,
        PdfPencilInteraction.channel.codec.encodeMethodCall(
            const MethodCall(PdfPencilInteraction.doubleTapMethod)),
        (_) {},
      );
    }

    test('a channel double-tap toggles the eraser', () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap();
      expect(c.tool, PdfEditTool.eraser);

      await sendDoubleTap();
      expect(c.tool, isNull);
    });

    test('a custom action overrides the eraser toggle', () async {
      final c = controller();
      var taps = 0;
      final pencil = PdfPencilInteraction(onDoubleTap: () => taps++)..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap();
      expect(taps, 1);
      expect(c.tool, isNull, reason: 'the controller toggle is bypassed');
    });

    test('dispose stops listening', () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      expect(pencil.isAttached, isTrue);

      pencil.dispose();
      expect(pencil.isAttached, isFalse);

      await sendDoubleTap();
      expect(c.tool, isNull, reason: 'the handler was cleared');
    });

    test('unknown methods are ignored', () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      final result = await pencil.handleMethodCall(const MethodCall('bogus'));
      expect(result, isNull);
      expect(c.tool, isNull);
    });
  });
}

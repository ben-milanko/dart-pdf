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
    // iOS UIPencilInteraction does at runtime — optionally carrying the user's
    // preferred-action choice.
    Future<void> sendDoubleTap([String? preferredAction]) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      return messenger.handlePlatformMessage(
        PdfPencilInteraction.channel.name,
        PdfPencilInteraction.channel.codec.encodeMethodCall(MethodCall(
            PdfPencilInteraction.doubleTapMethod,
            preferredAction == null
                ? null
                : {'preferredAction': preferredAction})),
        (_) {},
      );
    }

    test('a "switch eraser" double-tap toggles the eraser', () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap('switchEraser');
      expect(c.tool, PdfEditTool.eraser);

      await sendDoubleTap('switchEraser');
      expect(c.tool, isNull);
    });

    test('an action-less double-tap still toggles (out-of-the-box default)',
        () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap();
      expect(c.tool, PdfEditTool.eraser);
    });

    test('"off" (ignore) honors the user and does nothing', () async {
      final c = controller();
      c.tool = PdfEditTool.ink;
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap('ignore');
      expect(c.tool, PdfEditTool.ink, reason: 'the gesture was turned off');
    });

    test('a non-eraser action (show palette) is left alone', () async {
      final c = controller();
      c.tool = PdfEditTool.ink;
      final pencil = PdfPencilInteraction()..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap('showColorPalette');
      expect(c.tool, PdfEditTool.ink, reason: 'not our action to hijack');
    });

    test('a custom handler overrides the policy and gets the action',
        () async {
      final c = controller();
      final actions = <PdfPencilTapAction>[];
      final pencil = PdfPencilInteraction(onDoubleTap: actions.add)..attach(c);
      addTearDown(pencil.dispose);

      await sendDoubleTap('ignore');
      await sendDoubleTap('switchEraser');
      expect(actions,
          [PdfPencilTapAction.ignore, PdfPencilTapAction.switchEraser]);
      expect(c.tool, isNull, reason: 'the controller toggle is bypassed');
    });

    test('dispose stops listening', () async {
      final c = controller();
      final pencil = PdfPencilInteraction()..attach(c);
      expect(pencil.isAttached, isTrue);

      pencil.dispose();
      expect(pencil.isAttached, isFalse);

      await sendDoubleTap('switchEraser');
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

  group('PdfPencilTapAction', () {
    test('fromName maps known names and defaults the rest to unspecified', () {
      expect(PdfPencilTapAction.fromName('ignore'), PdfPencilTapAction.ignore);
      expect(PdfPencilTapAction.fromName('switchEraser'),
          PdfPencilTapAction.switchEraser);
      expect(PdfPencilTapAction.fromName('switchPrevious'),
          PdfPencilTapAction.switchPrevious);
      expect(PdfPencilTapAction.fromName(null), PdfPencilTapAction.unspecified);
      expect(PdfPencilTapAction.fromName('garbage'),
          PdfPencilTapAction.unspecified);
    });

    test('only the tool-switch actions toggle the eraser', () {
      expect(PdfPencilTapAction.switchEraser.togglesEraser, isTrue);
      expect(PdfPencilTapAction.switchPrevious.togglesEraser, isTrue);
      expect(PdfPencilTapAction.unspecified.togglesEraser, isTrue);
      expect(PdfPencilTapAction.ignore.togglesEraser, isFalse);
      expect(PdfPencilTapAction.showColorPalette.togglesEraser, isFalse);
      expect(PdfPencilTapAction.runSystemShortcut.togglesEraser, isFalse);
    });
  });
}

// The regression exercises the same feature gate that Flutter's showDialog
// consults when deciding whether to create a native dialog window.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter_test/flutter_test.dart';

/// The stock text prompt's dialog and field.
final prompt = find.byKey(const ValueKey('pdf-text-prompt'));
final promptField = find.byKey(const ValueKey('pdf-text-prompt-field'));

void main() {
  testWidgets('PDF dialogs remain interactive inside a windowed view',
      (tester) async {
    final original = isWindowingEnabled;
    isWindowingEnabled = true;
    String? result;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('In-view dialog'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'accepted'),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('In-view dialog'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(result, 'accepted');
      expect(find.text('In-view dialog'), findsNothing);
    } finally {
      isWindowingEnabled = original;
    }
  });

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter
  ]) {
    testWidgets('${key.debugName} submits a focused text prompt once',
        (tester) async {
      String? result;
      var completions = 0;
      await openDialog(tester, (context) async {
        result =
            await showPdfTextPrompt(context, title: 'Name', initial: 'Old');
        completions++;
      });
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue);
      await tester.enterText(promptField, 'New');
      // Flutter's legacy Windows test key-code map omits numpad Enter.
      // Use Linux key data while exercising each platform's widget behavior.
      await tester.sendKeyEvent(key, platform: 'linux');
      await tester.pumpAndSettle();
      expect(result, 'New');
      expect(completions, 1);
      expect(prompt, findsNothing);
    }, variant: TargetPlatformVariant.all());
  }

  testWidgets('Enter accepts the current color after editing its hex field',
      (tester) async {
    Color? result;
    await openDialog(tester, (context) async {
      result = await showPdfColorPicker(context, initial: Colors.red);
    });
    await tester.enterText(
        find.byKey(const ValueKey('pdf-color-hex')), '00FF00');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, const Color(0xFF00FF00));
  });

  testWidgets('Enter saves a stamp with pending size edits', (tester) async {
    PdfCustomStamp? result;
    await openDialog(tester, (context) async {
      result = await showPdfStampEditor(context);
    });
    await tester.enterText(
        find.byKey(const ValueKey('pdf-stamp-text')), 'APPROVED');
    await tester.enterText(
        find.byKey(const ValueKey('pdf-stamp-width')), '320');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result?.text, 'APPROVED');
    expect(result?.template?.width, 320);
  });

  testWidgets('Shift+Enter leaves a multiline prompt open; Enter submits it',
      (tester) async {
    String? result;
    await openDialog(tester, (context) async {
      result = await showPdfTextPrompt(context, title: 'Note', multiline: true);
    });
    await tester.enterText(promptField, 'First');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(prompt, findsOneWidget);
    // The platform text-input client supplies the newline after the shortcut
    // leaves Shift+Enter unhandled.
    await tester.enterText(promptField, 'First\nSecond');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, 'First\nSecond');
  });

  testWidgets('Enter confirms IME composition before submitting',
      (tester) async {
    String? result;
    await openDialog(tester, (context) async {
      result = await showPdfTextPrompt(context, title: 'Name');
    });
    final field = tester
        .widget<EditableText>(find.descendant(
            of: promptField, matching: find.byType(EditableText)))
        .controller;
    field.value = const TextEditingValue(
      text: '東京',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prompt, findsOneWidget);
    expect(result, isNull);
    field.clearComposing();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, '東京');
  });

  testWidgets(
      'disabled submit stays open and reads the enabled button on rebuild',
      (tester) async {
    var enabled = false;
    var submits = 0;
    late StateSetter update;
    await openDialog(
        tester,
        (context) => showPdfDialog<void>(
              context: context,
              builder: (context) =>
                  StatefulBuilder(builder: (context, setState) {
                update = setState;
                return AlertDialog(
                  content: const TextField(autofocus: true),
                  actions: [
                    PdfDialogSubmit.action(
                        onSubmit: enabled ? () => submits++ : null,
                        child: FilledButton(
                          onPressed: enabled ? () => submits++ : null,
                          child: const Text('Save'),
                        ))
                  ],
                );
              }),
            ));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submits, 0);
    update(() => enabled = true);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(submits, 1);
  });

  testWidgets(
      'nested dialogs submit independently and restore the outer action',
      (tester) async {
    var outerSubmits = 0;
    String? innerResult;
    await openDialog(
        tester,
        (context) => showPdfDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Outer'),
                content: TextButton(
                  onPressed: () async {
                    innerResult = await showPdfTextPrompt(context,
                        title: 'Inner', initial: 'Value');
                  },
                  child: const Text('Open inner'),
                ),
                actions: [
                  PdfDialogSubmit.action(
                      onSubmit: () {
                        outerSubmits++;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Save outer'))
                ],
              ),
            ));
    await tester.tap(find.text('Open inner'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(innerResult, 'Value');
    expect(outerSubmits, 0);
    expect(find.text('Outer'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(outerSubmits, 1);
    expect(find.text('Outer'), findsNothing);
    expect(prompt, findsNothing);
  });

  testWidgets('Enter activates Cancel when it has keyboard focus',
      (tester) async {
    final cancelFocus = FocusNode();
    addTearDown(cancelFocus.dispose);
    bool? result;
    await openDialog(tester, (context) async {
      result = await showPdfDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          actions: [
            TextButton(
              focusNode: cancelFocus,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            PdfDialogSubmit.action(
                onSubmit: () => Navigator.of(context).pop(true),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                )),
          ],
        ),
      );
    });
    cancelFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isFalse);
  }, variant: TargetPlatformVariant.all());

  testWidgets('the deprecated ButtonStyleButton form still submits on Enter',
      (tester) async {
    var submits = 0;
    await openDialog(
        tester,
        (context) => showPdfDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: const TextField(autofocus: true),
                actions: [
                  // ignore: deprecated_member_use_from_same_package
                  PdfDialogSubmit(
                      child: FilledButton(
                    onPressed: () => submits++,
                    child: const Text('Save'),
                  )),
                ],
              ),
            ));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submits, 1);
  });

  // Enter keeps its meaning by role, not by widget type: a value control
  // (segments, a dropdown) is part of the form, so Enter submits from it;
  // a focused command button activates itself.
  Future<int> enterWithFocusOn(
      WidgetTester tester, Widget Function(FocusNode focus) control) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var submits = 0;
    await openDialog(
        tester,
        (context) => showPdfDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: control(focus),
                actions: [
                  PdfDialogSubmit.action(
                      onSubmit: () => submits++, child: const Text('Save')),
                ],
              ),
            ));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    return submits;
  }

  testWidgets('Enter submits from a focused segmented selector',
      (tester) async {
    final submits = await enterWithFocusOn(
        tester,
        (focus) => SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 1,
                    label: Focus(
                        focusNode: focus,
                        skipTraversal: true,
                        child: const Text('One'))),
                const ButtonSegment(value: 2, label: Text('Two')),
              ],
              selected: const {1},
              onSelectionChanged: (_) {},
            ));
    expect(submits, 1);
  });

  testWidgets('Enter submits from a focused dropdown', (tester) async {
    final submits = await enterWithFocusOn(
        tester,
        (focus) => DropdownButton<int>(
              focusNode: focus,
              value: 1,
              items: const [
                DropdownMenuItem(value: 1, child: Text('One')),
                DropdownMenuItem(value: 2, child: Text('Two')),
              ],
              onChanged: (_) {},
            ));
    expect(submits, 1);
    expect(find.text('Two'), findsNothing, reason: 'the menu stayed closed');
  });

  testWidgets('a focused command button keeps Enter', (tester) async {
    var pressed = 0;
    final submits = await enterWithFocusOn(
        tester,
        (focus) => IconButton(
              focusNode: focus,
              icon: const Icon(Icons.add),
              onPressed: () => pressed++,
            ));
    expect(submits, 0);
    expect(pressed, 1);
  });
}

Future<void> openDialog(
    WidgetTester tester, Future<void> Function(BuildContext) open) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
    builder: (context) =>
        TextButton(onPressed: () => open(context), child: const Text('Open')),
  )));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

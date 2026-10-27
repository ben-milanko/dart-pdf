import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<FocusNode> pumpField(WidgetTester tester,
      {required bool dismiss}) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget app(Widget child) => MaterialApp(
          builder: dismiss
              ? (context, child) =>
                  PdfDismissKeyboardOnTapOutside(child: child!)
              : null,
          home: child,
        );
    await tester.pumpWidget(app(Scaffold(
      body: Column(children: [
        TextField(
          focusNode: focus,
          keyboardType: TextInputType.number,
        ),
      ]),
    )));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    return focus;
  }

  testWidgets('a touch outside keeps focus on iOS by default', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final focus = await pumpField(tester, dismiss: false);
    await tester.tapAt(const Offset(400, 400), kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('PdfDismissKeyboardOnTapOutside drops focus on an iOS touch',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final focus = await pumpField(tester, dismiss: true);
    await tester.tapAt(const Offset(400, 400), kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}

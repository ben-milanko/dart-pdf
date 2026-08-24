import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/middle_ellipsis_text.dart';

void main() {
  testWidgets('keeps both ends of an overflowing file name', (tester) async {
    const name = 'a-very-long-drawing-file-name.pdf';
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 110,
          child: MiddleEllipsisText(name, style: TextStyle(fontSize: 14)),
        ),
      ),
    ));

    final render = tester.renderObject(find.byType(MiddleEllipsisText));
    // ignore: avoid_dynamic_calls
    final rendered = (render as dynamic).debugDisplayedText as String;
    expect(rendered, isNot(name));
    expect(rendered, contains('…'));
    expect(rendered, startsWith('a'));
    expect(rendered, endsWith('.pdf'));
  });

  testWidgets('leaves a fitting file name unchanged', (tester) async {
    const name = 'drawing.pdf';
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          child: MiddleEllipsisText(name, style: TextStyle(fontSize: 14)),
        ),
      ),
    ));

    final render = tester.renderObject(find.byType(MiddleEllipsisText));
    // ignore: avoid_dynamic_calls
    expect((render as dynamic).debugDisplayedText, name);
  });
}

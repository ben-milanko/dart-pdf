// The web app's safe-area insets: the browser's env(safe-area-inset-*) join
// the MediaQuery padding, so the app bar pads under the status bar and fills
// the strip above it instead of leaving the page background showing.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/web_safe_area.dart';

void main() {
  test('insets add to the view padding and the padding', () {
    const data = MediaQueryData(
      viewPadding: EdgeInsets.only(top: 4),
      padding: EdgeInsets.only(top: 4),
    );
    final out =
        withSafeAreaInsets(data, const EdgeInsets.fromLTRB(0, 47, 0, 34));
    expect(out.viewPadding, const EdgeInsets.fromLTRB(0, 51, 0, 34));
    expect(out.padding, const EdgeInsets.fromLTRB(0, 51, 0, 34));
  });

  test('an open keyboard covers the home-indicator inset', () {
    const data = MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300));
    final out =
        withSafeAreaInsets(data, const EdgeInsets.fromLTRB(0, 47, 0, 34));
    expect(out.viewPadding.bottom, 34);
    expect(out.padding, const EdgeInsets.only(top: 47));
  });

  testWidgets('off the web it is just its child', (tester) async {
    late MediaQueryData seen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => WebSafeArea(child: child!),
      home: Builder(builder: (context) {
        seen = MediaQuery.of(context);
        return const SizedBox();
      }),
    ));
    expect(seen.padding, EdgeInsets.zero);
  });
}

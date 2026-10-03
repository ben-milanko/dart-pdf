// Every ink well in the editor's chrome splashes on a Material it can be
// seen on. A splash paints on the nearest Material ancestor, so an opaque
// card, chip or strip between the two hides it. Under a host on the legacy
// package:flutter/material.dart there is no material_ui Material above the
// editor at all except the wrapper's transparent one, which sits beneath
// every surface - so each surface that holds ink wells brings its own.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether [widget] paints an opaque fill over the Material beneath it.
bool _fills(Widget widget) {
  if (widget is ColoredBox) return widget.color.a > 0;
  if (widget is DecoratedBox) {
    final d = widget.decoration;
    if (d is BoxDecoration) return (d.color?.a ?? 0) > 0 || d.gradient != null;
    if (d is ShapeDecoration) return (d.color?.a ?? 0) > 0;
  }
  return false;
}

/// The ink wells on screen whose splashes an opaque fill hides, described
/// by the nearest keyed ancestors.
Set<String> _hiddenInk(WidgetTester tester, String surface) {
  final out = <String>{};
  for (final e in find.byWidgetPredicate((w) => w is InkResponse).evaluate()) {
    Widget? fill;
    e.visitAncestorElements((a) {
      if (a.widget is Material) return false;
      if (_fills(a.widget)) {
        fill = a.widget;
        return false;
      }
      return true;
    });
    if (fill == null) continue;
    final keys = <Object>[];
    e.visitAncestorElements((a) {
      final key = a.widget.key;
      if (key is ValueKey) keys.add(key.value as Object);
      return keys.length < 2;
    });
    out.add('$surface: ${e.widget.key ?? e.widget.runtimeType} under a '
        '${fill.runtimeType} (in $keys)');
  }
  return out;
}

Future<void> _sweep(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final editing = PdfEditingController(buildMultiPagePdf(3));
  addTearDown(editing.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(legacy.MaterialApp(
    home: legacy.Scaffold(body: PdfEditorView(controller: editing)),
  ));
  await tester.pumpAndSettle();
  editing.addInkStroke(0, [(100, 100), (200, 200)]);
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  final hidden = <String>{..._hiddenInk(tester, 'resting')};
  Future<void> tapEach(bool Function(String key) wanted) async {
    final keys = {
      for (final e in find
          .byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              wanted((w.key! as ValueKey<String>).value))
          .evaluate())
        (e.widget.key! as ValueKey<String>).value,
    };
    for (final key in keys) {
      final target = find.byKey(ValueKey(key));
      if (target.evaluate().isEmpty) continue;
      await tester.tap(target.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      hidden.addAll(_hiddenInk(tester, key));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  }

  // the tool groups' strips, then every panel and sheet toggle
  await tapEach((k) => k.startsWith('pdf-group-'));
  await tapEach((k) => k.startsWith('pdf-shell-') && k.endsWith('-toggle'));
  // a selected annotation's strip and action chip
  editing.selectAnnotation(0, 0);
  await tester.pumpAndSettle();
  hidden.addAll(_hiddenInk(tester, 'selection'));
  expect(hidden, isEmpty);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop chrome', (tester) async {
    await _sweep(tester, const Size(1400, 900));
  });

  testWidgets('compact chrome', (tester) async {
    await _sweep(tester, const Size(420, 860));
  });
}

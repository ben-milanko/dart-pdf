import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openAppMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
  }

  Future<void> openRecentsSubmenu(WidgetTester tester) async {
    await openAppMenu(tester);
    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();
  }

  String shortcut(String key, {bool shift = false}) {
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return apple
        ? '${shift ? '⇧' : ''}⌘$key'
        : 'Ctrl+${shift ? 'Shift+' : ''}$key';
  }

  void seedRecents() {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.recents': jsonEncode([
        {
          't': 'alpha.pdf',
          'p': '/docs/alpha.pdf',
          'o': 2000,
        },
        {
          't': 'beta.pdf',
          'p': '/docs/beta.pdf',
          'o': 1000,
        },
      ]),
    });
  }

  testWidgets('DartPDF menu shows Open and Open Recent entries',
      (tester) async {
    seedRecents();
    await pumpApp(tester);

    await openAppMenu(tester);

    expect(find.byKey(const ValueKey('menu-open')), findsOneWidget);
    expect(find.text('Open a PDF…'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-recent-submenu')), findsOneWidget);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text(shortcut('O')), findsOneWidget);
    expect(find.text(shortcut('O', shift: true)), findsOneWidget);

    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();

    expect(find.text('alpha.pdf'), findsWidgets);
    expect(find.text('beta.pdf'), findsWidgets);
    expect(find.text('Clear recent files'), findsWidgets);
  });

  testWidgets('Open Recent stays visible when there are no recent files',
      (tester) async {
    await pumpApp(tester);

    await openRecentsSubmenu(tester);

    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('No recent files'), findsOneWidget);
    expect(find.text('Clear recent files'), findsNothing);
  });
}

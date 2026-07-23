import 'package:dart_pdf_editor/dart_pdf_editor.dart';
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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('language picker writes the chosen locale to prefs',
      (tester) async {
    await openSettings(tester);

    // Defaults to "System default" (null locale).
    expect(prefs.locale, isNull);
    expect(find.byKey(const ValueKey('settings-language')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-language')));
    await tester.pumpAndSettle();
    // The menu lists each language by its native name; pick Spanish.
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    expect(prefs.locale, const Locale('es'));
  });

  testWidgets('settings offer default application setup', (tester) async {
    await openSettings(tester);

    expect(find.byKey(const ValueKey('settings-default-app')), findsOneWidget);
    expect(find.text('Set up as default application'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-default-app')));
    await tester.pumpAndSettle();

    expect(find.text('Set up as default application'), findsWidgets);
    expect(find.textContaining('PDF'), findsWidgets);
  });

  for (final scenario in [
    (
      platform: TargetPlatform.windows,
      subtitle: 'Open Windows default apps settings for PDFs.',
      dialogText: 'Windows Settings will open to Default apps.',
      openSettingsButton: true,
    ),
    (
      platform: TargetPlatform.macOS,
      subtitle: 'Follow Finder',
      dialogText: 'In Finder, select any PDF',
      openSettingsButton: false,
    ),
    (
      platform: TargetPlatform.linux,
      subtitle: 'default applications settings',
      dialogText: 'Open your desktop settings',
      openSettingsButton: false,
    ),
    (
      platform: TargetPlatform.android,
      subtitle: 'tap Always',
      dialogText: 'Open a PDF from Files or Downloads',
      openSettingsButton: false,
    ),
    (
      platform: TargetPlatform.iOS,
      subtitle: 'Open In from Files',
      dialogText: 'iOS does not provide a global default PDF editor.',
      openSettingsButton: false,
    ),
    (
      platform: TargetPlatform.fuchsia,
      subtitle: 'PDF file handler',
      dialogText: 'Use the system settings for file handlers',
      openSettingsButton: false,
    ),
  ]) {
    testWidgets('default app setup copy for ${scenario.platform.name}',
        (tester) async {
      await openSettings(tester);

      expect(find.textContaining(scenario.subtitle), findsOneWidget);
      // The settings content scrolls; ensure the default-app tile is on-screen
      // before tapping (a longer per-platform subtitle can push it below the
      // fold on the smaller mobile surfaces).
      final tile = find.byKey(const ValueKey('settings-default-app'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.textContaining(scenario.dialogText), findsOneWidget);
      expect(
        find.byKey(const ValueKey('default-app-open-settings')),
        scenario.openSettingsButton ? findsOneWidget : findsNothing,
      );
    }, variant: TargetPlatformVariant.only(scenario.platform));
  }
}

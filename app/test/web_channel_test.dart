import 'package:dart_pdf_editor_app/l10n/app_delegates.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_editor_app/web_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<List<Uri>> _pumpTile(WidgetTester tester,
    {required bool nightly}) async {
  final opened = <Uri>[];
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(
      child: WebChannelSwitchTile(
        nightly: nightly,
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    ),
  ));
  return opened;
}

void main() {
  test('each channel points at the other site', () {
    expect(otherWebChannelUri(nightly: false).toString(),
        'https://app-nightly.dart-pdf.com/');
    expect(otherWebChannelUri(nightly: true).toString(),
        'https://app.dart-pdf.com/');
  });

  testWidgets('the stable app offers the nightly', (tester) async {
    final opened = await _pumpTile(tester, nightly: false);
    expect(find.text('Try the nightly web app'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-web-channel')));
    expect(opened, [Uri.parse(dartPdfNightlyWebAppUrl)]);
  });

  testWidgets('the nightly app offers the way back', (tester) async {
    final opened = await _pumpTile(tester, nightly: true);
    expect(find.text('Switch to the stable web app'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-web-channel')));
    expect(opened, [Uri.parse(dartPdfWebAppUrl)]);
  });
}

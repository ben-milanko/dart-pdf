import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native printer automatically registers in a plain Flutter host',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    const channel = MethodChannel('dev.milanko.dart_pdf_printing');
    final desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    // Invalid arguments are rejected by the registered platform backend.
    // This never opens a print dialog or sends anything to a printer.
    await expectLater(
      channel.invokeMethod<void>(desktop ? 'printPageVector' : 'printPdf', {}),
      throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'bad_args')),
    );
    if (desktop) {
      final info = await channel.invokeMapMethod<String, dynamic>(
          'beginJob', {'name': 'Registration test'});
      expect(info?['vector'], isTrue);
      await channel.invokeMethod<void>('cancelJob');
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      for (final method in [
        'printerSettings',
        'printerProperties',
        'beginJob'
      ]) {
        await expectLater(
          channel.invokeMethod<void>(method, {'printer': ''}),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'bad_args')),
        );
      }
    }
  });
}

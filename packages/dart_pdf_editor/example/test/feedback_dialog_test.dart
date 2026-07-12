import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer_example/error_log.dart';
import 'package:pdf_viewer_example/feedback.dart';

void main() {
  testWidgets('opens the feedback form with the diagnostics prefilled',
      (tester) async {
    final log = AppLog()
      ..info('App started')
      ..error('Could not open sample.pdf');
    Uri? opened;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showFeedbackDialog(
                context,
                log: log,
                onOpen: (url) async => opened = url,
              ),
              child: const Text('feedback'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('feedback'));
    await tester.pumpAndSettle();

    // The captured events are shown for review.
    expect(find.text('Send feedback'), findsOneWidget);
    expect(find.textContaining('Could not open sample.pdf'), findsWidgets);

    await tester.tap(find.text('Open feedback form'));
    await tester.pumpAndSettle();

    expect(opened, isNotNull);
    expect(opened!.queryParameters['template'], 'app_feedback.yml');
    expect(opened!.queryParameters['version'], kAppVersion);
    expect(opened!.queryParameters['diagnostics'],
        contains('Could not open sample.pdf'));
  });

  testWidgets('unchecking "Attach" omits the diagnostics', (tester) async {
    final log = AppLog()..error('secret error');
    Uri? opened;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showFeedbackDialog(
              context,
              log: log,
              onOpen: (url) async => opened = url,
            ),
            child: const Text('feedback'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('feedback'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Attach these diagnostics to the report'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open feedback form'));
    await tester.pumpAndSettle();

    expect(opened, isNotNull);
    expect(opened!.queryParameters.containsKey('diagnostics'), isFalse);
  });

  testWidgets('Copy diagnostics writes the report to the clipboard',
      (tester) async {
    final log = AppLog()..info('breadcrumb');
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showFeedbackDialog(
              context,
              log: log,
              onOpen: (url) async {},
            ),
            child: const Text('feedback'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('feedback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy diagnostics'));
    await tester.pumpAndSettle();

    expect(clipboard, isNotNull);
    expect(clipboard, contains('breadcrumb'));
  });
}

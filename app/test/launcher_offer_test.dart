import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_pdf_editor_app/launcher_offer.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Widget host(
          {required Future<String> Function() status,
          Future<void> Function()? register,
          bool enabled = true}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LauncherOffer(
            enabled: enabled,
            status: status,
            register: register ?? () async {},
            child: const Scaffold(body: Text('Document remains open'))),
      );
  testWidgets('missing offers once; Not now does not register or persist',
      (t) async {
    var calls = 0;
    var installs = 0;
    final app = host(status: () async {
      calls++;
      return 'missing';
    }, register: () async {
      installs++;
    });
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Set up launcher'), findsOneWidget);
    expect(find.text('Document remains open'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Set up launcher'), findsNothing);
    expect(calls, 1);
    expect(installs, 0);
    expect(
        (await SharedPreferences.getInstance())
            .getBool(LauncherOffer.suppressionKey),
        isNull);
  });
  for (final status in ['registered', 'unsupported']) {
    testWidgets('$status does not offer', (t) async {
      await t.pumpWidget(host(status: () async => status));
      await t.pumpAndSettle();
      expect(find.text('Set up launcher'), findsNothing);
    });
  }
  testWidgets('suppression survives a new widget session', (t) async {
    var calls = 0;
    final app = host(status: () async {
      calls++;
      return 'missing';
    });
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    await t.tap(find.text('Don’t show again'));
    await t.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance())
            .getBool(LauncherOffer.suppressionKey),
        isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Set up launcher'), findsNothing);
  });
  testWidgets('success requires verified registration', (t) async {
    var status = 'missing';
    await t.pumpWidget(host(
        status: () async => status,
        register: () async {
          status = 'registered';
        }));
    await t.pumpAndSettle();
    await t.tap(find.text('Set up launcher'));
    await t.pumpAndSettle();
    expect(find.text('Set up launcher'), findsNothing);
    expect(find.text('Document remains open'), findsOneWidget);
  });
  for (final throws in [true, false]) {
    testWidgets('error stays retryable, throws=$throws', (t) async {
      await t.pumpWidget(host(
          status: () async => 'missing',
          register: () async {
            if (throws) throw StateError('failure');
          }));
      await t.pumpAndSettle();
      await t.tap(find.text('Set up launcher'));
      await t.pumpAndSettle();
      expect(
          find.text(
              'Could not save this change. Try again, or choose Not now.'),
          findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });
  }
  testWidgets('failed suppression stays visible and dismissible', (t) async {
    await t.pumpWidget(MaterialApp(
        home: LauncherOffer(
      status: () async => 'missing',
      saveSuppression: () async => false,
      child: const SizedBox(),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Don’t show again'));
    await t.pumpAndSettle();
    expect(
        find.text('Could not save this change. Try again, or choose Not now.'),
        findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(find.text('Set up launcher'), findsNothing);
  });
  testWidgets('Not now offers again after restart', (t) async {
    final app = host(status: () async => 'missing');
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Set up launcher'), findsOneWidget);
  });
  testWidgets('document identity survives banner and pending registration',
      (t) async {
    final probe = Completer<String>();
    final install = Completer<void>();
    final key = GlobalKey<_DocumentState>();
    var registered = false;
    await t.pumpWidget(MaterialApp(
        home: LauncherOffer(
      status: () => registered ? Future.value('registered') : probe.future,
      register: () async {
        await install.future;
        registered = true;
      },
      child: _Document(key: key),
    )));
    await t.pumpAndSettle();
    final state = key.currentState;
    await t.tap(find.text('Document 0'));
    await t.pump();
    probe.complete('missing');
    await t.pumpAndSettle();
    expect(key.currentState, same(state));
    await t.tap(find.text('Set up launcher'));
    await t.pump();
    await t.tap(find.text('Document 1'));
    await t.pump();
    expect(find.text('Document 2'), findsOneWidget);
    install.complete();
    await t.pumpAndSettle();
    expect(key.currentState, same(state));
    expect(find.text('Document 2'), findsOneWidget);
  });
  testWidgets('disposing during detection is safe', (t) async {
    final probe = Completer<String>();
    await t.pumpWidget(host(status: () => probe.future));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    probe.complete('missing');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('pending check does not block document; disabled never probes',
      (t) async {
    final pending = Completer<String>();
    await t.pumpWidget(host(status: () => pending.future));
    await t.pump();
    expect(find.text('Document remains open'), findsOneWidget);
    pending.complete('unsupported');
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
        host(enabled: false, status: () => throw StateError('must not run')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}

class _Document extends StatefulWidget {
  const _Document({super.key});
  @override
  State<_Document> createState() => _DocumentState();
}

class _DocumentState extends State<_Document> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: TextButton(
          onPressed: () => setState(() => count++),
          child: Text('Document $count')));
}

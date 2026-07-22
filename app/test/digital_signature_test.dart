import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/digital_signature.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/keyless_signing.dart';
import 'package:dart_pdf_editor_app/signature_appearance_store.dart';

/// An unsigned OIDC token carrying [claims], enough for the keyless flow.
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  PdfDigitalSignatureIdentity identity() =>
      PdfDigitalSignatureIdentity.fromFiles(
        privateKey: Uint8List.fromList(testSignerKeyPem.codeUnits),
        certificates: [Uint8List.fromList(testSignerCertPem.codeUnits)],
      );

  // An in-process Fulcio + TSA so the keyless flow runs with no network.
  final fulcioCa = TestFulcioCa.generate(notBefore: DateTime.utc(2026));
  final keylessAt = DateTime.utc(2026, 6, 10, 12);
  Future<PdfSigningIdentity> mintKeyless() => fulcioSigningIdentity(
        oidcToken: _jwt({'email': 'dev@example.com'}),
        transport: (request) async =>
            buildTestFulcioResponse(request, ca: fulcioCa, notBefore: keylessAt),
      );
  Future<Uint8List> fakeTsa(Uint8List request) async =>
      buildTestTimeStampToken(request, genTime: keylessAt);

  testWidgets('digital signing dialog loads and matches the identity',
      (tester) async {
    DigitalSignatureOptions? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                privateKeyPicker: () async => XFile.fromData(
                  Uint8List.fromList(testSignerKeyPem.codeUnits),
                  name: 'signer-key.pem',
                ),
                certificatePicker: () async => [
                  XFile.fromData(
                    Uint8List.fromList(testSignerCertPem.codeUnits),
                    name: 'signer-cert.pem',
                  ),
                ],
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DigitalSignatureDialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('digital-signature-sign')),
          )
          .onPressed,
      isNull,
    );

    // The certificate-file option lives under "Advanced" (easy options first).
    await tester.tap(find.byKey(const ValueKey('digital-signature-advanced')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('digital-signature-private-key')));
    await tester.tap(
      find.byKey(const ValueKey('digital-signature-private-key')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('digital-signature-certificates')));
    await tester.tap(
      find.byKey(const ValueKey('digital-signature-certificates')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dart PDF Test Signer'), findsOneWidget);
    expect(find.byKey(const ValueKey('digital-signature-error')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('digital-signature-location')),
      'Melbourne',
    );
    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.identity!.signerName, 'Dart PDF Test Signer');
    expect(result!.reason, 'Approved');
    expect(result!.location, 'Melbourne');
  });

  testWidgets('a key/cert mismatch shows a localized error, not a raw exception',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDigitalSigningDialog(
              context,
              // A valid key paired with a certificate for a different key -
              // fromFiles throws PdfSignatureIdentityException(keyCertificateMismatch),
              // which the app maps to a localized message at the display site.
              privateKeyPicker: () async => XFile.fromData(
                Uint8List.fromList(testSignerKeyPem.codeUnits),
                name: 'signer-key.pem',
              ),
              certificatePicker: () async => [
                XFile.fromData(
                  Uint8List.fromList(testChainSignerCertPem.codeUnits),
                  name: 'other-cert.pem',
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('digital-signature-advanced')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('digital-signature-private-key')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-private-key')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey('digital-signature-certificates')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-certificates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('digital-signature-error')), findsOneWidget);
    expect(
      find.text('The private key does not match any selected RSA certificate.'),
      findsOneWidget,
    );
  });

  testWidgets('one-tap: create a self-signed identity and sign with it',
      (tester) async {
    DigitalSignatureOptions? result;
    final store = InMemoryIdentityStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                identityStore: store,
                createSelfSignedIdentity: (context, store) async {
                  final identity = PdfSigningIdentity.generate(name: 'Ada Lovelace');
                  await store.save(identity.name!, identity);
                  return identity;
                },
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Sign is disabled until an identity is chosen.
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('digital-signature-sign')))
          .onPressed,
      isNull,
    );

    await tester
        .tap(find.byKey(const ValueKey('digital-signature-create-identity')));
    await tester.pumpAndSettle();

    // The self-signed identity is shown and was persisted to the store.
    expect(find.byKey(const ValueKey('digital-signature-self-signed')),
        findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(await store.ids(), ['Ada Lovelace']);

    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.identity, isNull);
    expect(result!.selfSignedIdentity, isNotNull);
    expect(result!.selfSignedIdentity!.name, 'Ada Lovelace');
    expect(result!.signerName, 'Ada Lovelace');
  });

  testWidgets('app menu signs with a self-signed identity, then saves',
      (tester) async {
    Uint8List? saved;
    final original = buildClassicPdf();
    final identity = PdfSigningIdentity.generate(name: 'Grace Hopper');
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: original, title: 'Contract.pdf'),
        digitalSignatureOptionsProvider: (context) async =>
            DigitalSignatureOptions(
          selfSignedIdentity: identity,
          reason: 'Approved for release',
        ),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saved = Uint8List.fromList(bytes);
          return SaveResult.downloaded(suggestedName);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sublist(0, original.length), original);
    final signatures = PdfSignature.of(PdfDocument.open(saved!));
    expect(signatures, hasLength(1));
    expect(signatures.single.signerName, 'Grace Hopper');
    expect(signatures.single.subFilter, 'adbe.pkcs7.detached');
    final validation = signatures.single.validate();
    expect(validation.intact, isTrue);
    expect(validation.coversWholeDocument, isTrue);
  });

  testWidgets('app menu digitally signs then saves the current document',
      (tester) async {
    Uint8List? saved;
    final original = buildClassicPdf();
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: original, title: 'Contract.pdf'),
        digitalSignatureOptionsProvider: (context) async =>
            DigitalSignatureOptions(
          identity: identity(),
          reason: 'Approved for release',
          location: 'Melbourne',
        ),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saved = Uint8List.fromList(bytes);
          return SaveResult.downloaded(suggestedName);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sublist(0, original.length), original);
    final signatures = PdfSignature.of(PdfDocument.open(saved!));
    expect(signatures, hasLength(1));
    expect(signatures.single.reason, 'Approved for release');
    expect(signatures.single.location, 'Melbourne');
    final validation = signatures.single.validate();
    expect(validation.intact, isTrue);
    expect(validation.coversWholeDocument, isTrue);
    expect(validation.padesLevel, PdfPadesLevel.bB);
  });

  testWidgets('after signing, Undo removes the accidental signature',
      (tester) async {
    final saves = <Uint8List>[];
    final original = buildClassicPdf();
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: original, title: 'Contract.pdf'),
        digitalSignatureOptionsProvider: (context) async =>
            DigitalSignatureOptions(
          selfSignedIdentity: PdfSigningIdentity.generate(name: 'Ada'),
          reason: 'oops',
        ),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saves.add(Uint8List.fromList(bytes));
          return SaveResult.downloaded(suggestedName);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
    await tester.pumpAndSettle();

    // signed once, and the "Undo" affordance is offered
    expect(saves, hasLength(1));
    expect(PdfSignature.of(PdfDocument.open(saves.first)), hasLength(1));
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // re-saved, now without the signature
    expect(saves.length, greaterThan(1));
    expect(PdfSignature.of(PdfDocument.open(saves.last)), isEmpty);
    expect(find.text('Signature removed'), findsOneWidget);
  });

  testWidgets('keyless: sign in with email, then the dialog returns it',
      (tester) async {
    final keyless = await mintKeyless();
    DigitalSignatureOptions? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                createKeylessIdentity: (context) async => keyless,
                timestampClient: fakeTsa,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Sign is disabled until an identity is chosen.
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('digital-signature-sign')))
          .onPressed,
      isNull,
    );

    await tester
        .ensureVisible(find.byKey(const ValueKey('digital-signature-keyless')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-keyless')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('digital-signature-keyless-identity')),
        findsOneWidget);
    expect(find.text('dev@example.com'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.identity, isNull);
    expect(result!.selfSignedIdentity, isNull);
    expect(result!.keylessIdentity, isNotNull);
    expect(result!.timestampClient, isNotNull);
    expect(result!.signerName, 'dev@example.com');
  });

  testWidgets('placement shows the Appearance section and returns an appearance',
      (tester) async {
    // A 1x1 opaque PNG stands in for a company logo backdrop.
    final logo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final store = InMemoryIdentityStore();
    DigitalSignatureOptions? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                identityStore: store,
                createSelfSignedIdentity: (context, store) async =>
                    PdfSigningIdentity.generate(name: 'Ada Lovelace'),
                placement: (page: 0, rect: const PdfRect(72, 640, 320, 720)),
                logoPicker: () async => logo,
                pageCount: 4,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // the Appearance section (only shown for a placement) offers the pickers
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byKey(const ValueKey('digital-signature-draw')), findsOneWidget);

    // add a logo backdrop
    await tester
        .ensureVisible(find.byKey(const ValueKey('digital-signature-logo')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-logo')));
    await tester.pumpAndSettle();
    expect(find.text('Logo added ✓'), findsOneWidget);

    // apply the box to pages 1–3 (of the 4-page document, 0-based 0..2)
    await tester.ensureVisible(
        find.byKey(const ValueKey('digital-signature-apply-pages')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-apply-pages')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-page-range-to')), '3');
    await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
    await tester.pumpAndSettle();

    // choose an identity, then sign
    await tester.ensureVisible(
        find.byKey(const ValueKey('digital-signature-create-identity')));
    await tester
        .tap(find.byKey(const ValueKey('digital-signature-create-identity')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final appearance = result!.appearance;
    expect(appearance, isNotNull);
    expect(appearance!.page, 0);
    expect(appearance.rect, const PdfRect(72, 640, 320, 720));
    expect(appearance.backgroundImage, isNotNull);
    // "apply to pages" 1–3 repeats the box on the other pages (0-based 1, 2)
    expect(appearance.repeatPages, [1, 2]);
  });

  testWidgets('saves the drawn mark/logo and pre-fills them next time',
      (tester) async {
    final logo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final store = InMemorySignatureAppearanceStore();

    Future<void> open() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDigitalSigningDialog(
                context,
                createSelfSignedIdentity: (context, s) async =>
                    PdfSigningIdentity.generate(name: 'Ada Lovelace'),
                placement: (page: 0, rect: const PdfRect(72, 640, 320, 720)),
                logoPicker: () async => logo,
                appearanceStore: store,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    // First session: add a logo - it is written to the device store.
    await open();
    expect(find.text('Logo added ✓'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('digital-signature-logo')));
    await tester.tap(find.byKey(const ValueKey('digital-signature-logo')));
    await tester.pumpAndSettle();
    expect(find.text('Logo added ✓'), findsOneWidget);
    expect((await store.load()).logoBytes, isNotNull);

    // Dismiss, then reopen: the remembered logo is pre-filled.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open();
    expect(find.text('Logo added ✓'), findsOneWidget);
  });

  testWidgets('a silent login pre-selects the keyless identity on open',
      (tester) async {
    final keyless = await mintKeyless();
    DigitalSignatureOptions? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                createKeylessIdentity: (context) async => keyless,
                timestampClient: fakeTsa,
                // the silent creator succeeds (a cached/refreshable login)
                autoCreateKeylessIdentity: (context) async => keyless,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // pre-selected without tapping "Sign in with your email"
    expect(find.byKey(const ValueKey('digital-signature-keyless-identity')),
        findsOneWidget);
    expect(find.text('dev@example.com'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('digital-signature-sign')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();
    expect(result!.keylessIdentity, isNotNull);
  });

  testWidgets('no silent login: nothing is pre-selected on open (no browser)',
      (tester) async {
    var interactiveCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDigitalSigningDialog(
              context,
              createKeylessIdentity: (context) async {
                interactiveCalls++; // stands in for the browser sign-in
                return await mintKeyless();
              },
              timestampClient: fakeTsa,
              // the silent creator declines (a browser would be needed)
              autoCreateKeylessIdentity: (context) async => null,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // opening the dialog did not run the interactive (browser) sign-in
    expect(interactiveCalls, 0);
    // and nothing keyless is pre-selected; the button is still offered
    expect(find.byKey(const ValueKey('digital-signature-keyless-identity')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('digital-signature-keyless')), findsOneWidget);
  });

  testWidgets('on web, a note points to the desktop/mobile app for keyless',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDigitalSigningDialog(
              context,
              keylessUnavailable: true, // stands in for kIsWeb
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // no keyless button (no provider), but the explanatory note is shown
    expect(find.byKey(const ValueKey('digital-signature-keyless')), findsNothing);
    expect(find.byKey(const ValueKey('digital-signature-keyless-web-note')),
        findsOneWidget);
  });

  testWidgets('keyless option is hidden unless a token provider is wired',
      (tester) async {
    Future<void> open({OidcTokenProvider? tokenProvider}) async {
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (bytes: buildClassicPdf(), title: 'Contract.pdf'),
          oidcTokenProvider: tokenProvider,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.byKey(const ValueKey('digital-signature-keyless')), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await open(tokenProvider: (context) async => _jwt({'email': 'x@y.z'}));
    expect(
        find.byKey(const ValueKey('digital-signature-keyless')), findsOneWidget);
  });

  testWidgets('app menu signs keyless (B-T), then saves a timestamped signature',
      (tester) async {
    final keyless = await mintKeyless();
    Uint8List? saved;
    final original = buildClassicPdf();
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: original, title: 'Contract.pdf'),
        digitalSignatureOptionsProvider: (context) async =>
            DigitalSignatureOptions(
          keylessIdentity: keyless,
          timestampClient: fakeTsa,
          reason: 'Approved for release',
          signingTime: keylessAt,
        ),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saved = Uint8List.fromList(bytes);
          return SaveResult.downloaded(suggestedName);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sublist(0, original.length), original);
    final signature = PdfSignature.of(PdfDocument.open(saved!)).single;
    expect(signature.signerName, 'dev@example.com');
    expect(signature.subFilter, 'ETSI.CAdES.detached');
    final validation = signature.validate(
        trustStore: PdfTrustStore.trusting([fulcioCa.certificate]));
    expect(validation.intact, isTrue, reason: validation.problems.join('; '));
    expect(validation.timestamp, isNotNull);
    expect(validation.chainTrusted, isTrue);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Direct tests for [StandardSecurityHandler]'s object-graph operations and
/// the exempt-stream policy that used to be duplicated across the document
/// loader and the incremental updater. The handler is otherwise only
/// exercised end-to-end via `encryption_test.dart`.
void main() {
  // A real RC4 handler (symmetric, so encrypt then decrypt round-trips
  // without an IV), pulled off an opened fixture.
  StandardSecurityHandler handler() =>
      CosDocument.open(buildEncryptedPdf(revision: 3)).encryption!;

  // Direct graphs have no indirect references, so resolve is the identity.
  CosObject identity(CosObject? object) => object ?? CosNull.instance;

  CosStream stream(CosDictionary dict, String payload) =>
      CosStream(dict, ascii(payload));

  group('streamPayloadIsEncrypted (exempt policy)', () {
    final h = handler();

    test('an ordinary content stream is encrypted', () {
      expect(
          h.streamPayloadIsEncrypted(stream(CosDictionary(), 'q Q'), identity),
          isTrue);
    });

    test('cross-reference streams are never encrypted', () {
      expect(
          h.streamPayloadIsEncrypted(
              stream(CosDictionary({'Type': const CosName('XRef')}), 'x'),
              identity),
          isFalse);
    });

    test('/Metadata stays encrypted when /EncryptMetadata is true', () {
      final metadata =
          stream(CosDictionary({'Type': const CosName('Metadata')}), '<xml/>');
      // the revision-3 fixture leaves metadata encrypted by default
      expect(h.encryptMetadata, isTrue);
      expect(h.streamPayloadIsEncrypted(metadata, identity), isTrue);
    });

    test('/Metadata is exempt when /EncryptMetadata is false', () {
      final noMetaHandler = CosDocument.open(
              buildEncryptedPdf(revision: 4, encryptMetadata: false))
          .encryption!;
      expect(noMetaHandler.encryptMetadata, isFalse);
      final metadata =
          stream(CosDictionary({'Type': const CosName('Metadata')}), '<xml/>');
      // exempt from encryption - the exempt (false) branch of the policy
      expect(
          noMetaHandler.streamPayloadIsEncrypted(metadata, identity), isFalse);
      // and encrypt-on-write passes such a payload through plain
      final out = noMetaHandler.encryptObjectGraph(metadata, 10, 0,
          resolve: identity, keepsFileCiphertext: (_) => false) as CosStream;
      expect(out.rawBytes, ascii('<xml/>'));
    });

    test('a /Crypt filter naming /Identity marks the bytes as plain', () {
      final dict = CosDictionary({
        'Filter': const CosName('Crypt'),
        'DecodeParms': CosDictionary({'Name': const CosName('Identity')}),
      });
      expect(
          h.streamPayloadIsEncrypted(stream(dict, 'plain'), identity), isFalse);
    });

    test('a /Crypt filter naming a real crypt filter stays encrypted', () {
      final dict = CosDictionary({
        'Filter': const CosName('Crypt'),
        'DecodeParms': CosDictionary({'Name': const CosName('StdCF')}),
      });
      expect(
          h.streamPayloadIsEncrypted(stream(dict, 'cipher'), identity), isTrue);
    });

    test('a bare /Crypt filter (no parms) defaults to /Identity', () {
      final dict = CosDictionary({'Filter': const CosName('Crypt')});
      expect(
          h.streamPayloadIsEncrypted(stream(dict, 'plain'), identity), isFalse);
    });

    test('the /Crypt slot is found inside a filter/parms array pair', () {
      final dict = CosDictionary({
        'Filter':
            CosArray([const CosName('FlateDecode'), const CosName('Crypt')]),
        'DecodeParms': CosArray([
          CosNull.instance,
          CosDictionary({'Name': const CosName('Identity')}),
        ]),
      });
      expect(
          h.streamPayloadIsEncrypted(stream(dict, 'plain'), identity), isFalse);
    });
  });

  group('decryptObjectGraph', () {
    test('decrypts strings anywhere in the graph, leaving payloads raw', () {
      final h = handler();
      final title = h.encryptString(ascii('Secret'), 10, 0);
      final nested = h.encryptString(ascii('Deep'), 10, 0);
      final payload = ascii('still ciphertext');
      final graph = CosDictionary({
        'Title': CosString(title),
        'Kids': CosArray([CosString(nested)]),
        'Stream': CosStream(
            CosDictionary(
                {'Author': CosString(h.encryptString(ascii('Nib'), 10, 0))}),
            payload),
      });

      h.decryptObjectGraph(graph, 10, 0);

      expect((graph['Title'] as CosString).text, 'Secret');
      expect(((graph['Kids'] as CosArray)[0] as CosString).text, 'Deep');
      final s = graph['Stream'] as CosStream;
      expect((s.dictionary['Author'] as CosString).text, 'Nib');
      // the payload is untouched - it decrypts lazily in decodeStreamData
      expect(s.rawBytes, payload);
    });
  });

  group('encryptObjectGraph', () {
    test('encrypts strings and ordinary stream payloads', () {
      final h = handler();
      final content = ascii('BT (hi) Tj ET');
      final graph = CosDictionary({
        'Title': CosString.fromText('Plain'),
        // an array so the CosArray branch of the walk is exercised
        'Names':
            CosArray([CosString.fromText('Nested'), const CosName('Keep')]),
        'Content': stream(CosDictionary({'Length': CosInteger(content.length)}),
            'BT (hi) Tj ET'),
      });

      final out = h.encryptObjectGraph(graph, 10, 0,
          resolve: identity,
          keepsFileCiphertext: (_) => false) as CosDictionary;

      // the original graph is untouched
      expect((graph['Title'] as CosString).text, 'Plain');
      expect((graph['Content'] as CosStream).rawBytes, content);

      // strings round-trip back through the reader, anywhere in the graph
      expect(h.decryptString((out['Title'] as CosString).bytes, 10, 0),
          CosString.fromText('Plain').bytes);
      final names = out['Names'] as CosArray;
      expect(h.decryptString((names[0] as CosString).bytes, 10, 0),
          CosString.fromText('Nested').bytes);
      // a non-string array element is copied through unchanged
      expect((names[1] as CosName).value, 'Keep');
      final outStream = out['Content'] as CosStream;
      expect(outStream.rawBytes, isNot(content));
      expect((outStream.dictionary['Length'] as CosInteger).value,
          outStream.rawBytes.length);
      expect(h.decryptStream(outStream.rawBytes, 10, 0), content);
    });

    test('leaves an exempt /Crypt-Identity stream plain (the fixed bug)', () {
      // This is the divergence the old updater got wrong: it would have
      // re-encrypted an Identity-crypt stream. encryptObjectGraph routes
      // the exempt check through streamPayloadIsEncrypted, so it can't.
      final h = handler();
      final identityStream = stream(
          CosDictionary({
            'Filter': const CosName('Crypt'),
            'DecodeParms': CosDictionary({'Name': const CosName('Identity')}),
          }),
          'stays plain');

      final out = h.encryptObjectGraph(identityStream, 10, 0,
          resolve: identity, keepsFileCiphertext: (_) => false) as CosStream;

      expect(out.rawBytes, ascii('stays plain'));
    });

    test('passes a payload still holding file ciphertext through verbatim', () {
      final h = handler();
      final fileBytes = ascii('original file ciphertext');
      final loaded = stream(
          CosDictionary({'Length': CosInteger(fileBytes.length)}),
          'original file ciphertext');

      final out = h.encryptObjectGraph(loaded, 10, 0,
          resolve: identity,
          keepsFileCiphertext: (s) => identical(s, loaded)) as CosStream;

      expect(out.rawBytes, fileBytes);
    });
  });

  group('signature /Contents exemption (§7.6.1)', () {
    final cms = Uint8List.fromList([0x30, 0x82, 0x01, 0x00, 0xAB, 0xCD]);

    CosDictionary sigDict({String? type = 'Sig', bool byteRange = true}) =>
        CosDictionary({
          if (type != null) 'Type': CosName(type),
          'Filter': const CosName('Adobe.PPKLite'),
          if (byteRange)
            'ByteRange': CosArray([
              const CosInteger(0), const CosInteger(10), //
              const CosInteger(20), const CosInteger(30),
            ]),
          'Contents': CosString(cms, isHex: true),
          'Reason': CosString.fromText('Approval'),
        });

    test('recognises /Sig, /DocTimeStamp and an untyped /ByteRange dict', () {
      bool exempt(CosDictionary d) =>
          StandardSecurityHandler.isSignatureContents(d, 'Contents');
      expect(exempt(sigDict()), isTrue);
      expect(exempt(sigDict(type: 'DocTimeStamp', byteRange: false)), isTrue);
      expect(exempt(sigDict(type: null)), isTrue);
      expect(StandardSecurityHandler.isSignatureContents(sigDict(), 'Reason'),
          isFalse);
      // an annotation's /Contents is ordinary text and stays encrypted
      expect(
          exempt(CosDictionary({
            'Type': const CosName('Annot'),
            'Contents': CosString.fromText('note'),
          })),
          isFalse);
    });

    test('encrypt leaves /Contents plain and encrypts the other strings', () {
      final h = handler();
      final out = h.encryptObjectGraph(sigDict(), 12, 0,
          resolve: identity,
          keepsFileCiphertext: (_) => false) as CosDictionary;
      expect((out['Contents'] as CosString).bytes, cms);
      expect((out['Contents'] as CosString).isHex, isTrue);
      expect((out['Reason'] as CosString).bytes,
          isNot(CosString.fromText('Approval').bytes));
    });

    test('decrypt reads /Contents raw and round-trips the rest', () {
      final h = handler();
      final written = h.encryptObjectGraph(sigDict(), 12, 0,
          resolve: identity,
          keepsFileCiphertext: (_) => false) as CosDictionary;
      h.decryptObjectGraph(written, 12, 0);
      expect((written['Contents'] as CosString).bytes, cms);
      expect((written['Reason'] as CosString).text, 'Approval');
    });
  });

  test('openAppended reuses the keys for a revision written without them', () {
    final original = CosDocument.open(
        buildEncryptedPdf(revision: 6, userPassword: 'user'),
        password: 'user');
    final updater = CosIncrementalUpdater(original);
    final infoRef = original.trailer['Info'] as CosReference;
    final info = original.resolve(infoRef) as CosDictionary;
    info['Title'] = CosString.fromText('Rewritten');
    updater.replaceObject(infoRef.objectNumber, info);
    final saved = updater.save();

    expect(() => CosDocument.open(saved), throwsA(isA<CosPasswordException>()));
    final reopened = original.openAppended(saved);
    expect(reopened.isEncrypted, isTrue);
    final title = (reopened.resolve(reopened.trailer['Info'])
        as CosDictionary)['Title'] as CosString;
    expect(title.text, 'Rewritten');
  });

  group('openAppended on another revision', () {
    // An update over [original] that rewrites /Info, optionally also
    // replacing the /Encrypt object (same number) with [encrypt].
    Uint8List revise(CosDocument original, {CosDictionary? encrypt}) {
      final updater = CosIncrementalUpdater(original);
      final infoRef = original.trailer['Info'] as CosReference;
      final info = original.resolve(infoRef) as CosDictionary;
      info['Title'] = CosString.fromText('Rewritten');
      updater.replaceObject(infoRef.objectNumber, info);
      if (encrypt != null) {
        updater.replaceObject(original.encryptObjectNumber!, encrypt);
      }
      return updater.save();
    }

    String titleOf(CosDocument document) =>
        ((document.resolve(document.trailer['Info']) as CosDictionary)['Title']
                as CosString)
            .text;

    test('an earlier revision (an undo) reuses the keys, not the password', () {
      final bytes = buildEncryptedPdf(revision: 6, userPassword: 'user');
      final original = CosDocument.open(bytes, password: 'user');
      final latest = original.openAppended(revise(original));
      expect(latest.encryption, same(original.encryption));

      // the prefix the first revision ended at: same /Encrypt, no password
      final earlier = latest.openAppended(bytes);
      expect(earlier.encryption, same(original.encryption));
      expect(titleOf(earlier), 'Secret Title');
    });

    test('a revision that re-keys /Encrypt authenticates its own password', () {
      final original = CosDocument.open(
          buildEncryptedPdf(revision: 6, userPassword: 'user'),
          password: 'user');
      // same object number and file key (the fixture's), but /U, /UE, /O,
      // /OE now answer to a different user password
      final other = CosDocument.open(
          buildEncryptedPdf(revision: 6, userPassword: 'other'),
          password: 'other');
      final rekeyed = revise(original,
          encrypt: other.resolve(other.trailer['Encrypt']) as CosDictionary);

      expect(() => original.openAppended(rekeyed),
          throwsA(isA<CosPasswordException>()),
          reason: 'the old keys are not donated to different key material');
      final reopened = original.openAppended(rekeyed, password: 'other');
      expect(reopened.encryption, isNot(same(original.encryption)));
      expect(titleOf(reopened), 'Rewritten');
    });

    test('a donor that folded in a re-keyed /Encrypt vouches only for its own',
        () {
      // applyIncrementalUpdate keeps the handler it authenticated while the
      // folded revision redefines the /Encrypt object: the guard compares
      // against the dictionary those keys came from, not the donor's trailer
      final original = CosDocument.open(
          buildEncryptedPdf(revision: 6, userPassword: 'user'),
          password: 'user');
      final other = CosDocument.open(
          buildEncryptedPdf(revision: 6, userPassword: 'other'),
          password: 'other');
      final rekeyed = revise(original,
          encrypt: other.resolve(other.trailer['Encrypt']) as CosDictionary);
      final keys = original.encryption;
      original.applyIncrementalUpdate(rekeyed);
      expect(original.encryption, same(keys));

      expect(() => original.openAppended(rekeyed),
          throwsA(isA<CosPasswordException>()),
          reason: 'the keys were derived from the old /Encrypt, not this one');
      final reopened = original.openAppended(rekeyed, password: 'other');
      expect(reopened.encryption, isNot(same(keys)));
      expect(titleOf(reopened), 'Rewritten');
    });

    test('a revision that only swaps a crypt filter is not given the old keys',
        () {
      // /O, /U, /OE, /UE untouched - the key is the same - but the rewritten
      // /Encrypt declares streams unencrypted: the old handler would still
      // AES-decrypt them
      final original = CosDocument.open(buildEncryptedPdf(revision: 6));
      final encrypt =
          original.resolve(original.trailer['Encrypt']) as CosDictionary;
      final identityStreams = revise(original,
          encrypt: CosDictionary(
              {...encrypt.entries, 'StmF': const CosName('Identity')}));

      final reopened = original.openAppended(identityStreams);
      expect(reopened.encryption, isNot(same(original.encryption)));
      expect(original.encryption!.streamCipher, PdfCipher.aes256);
      expect(reopened.encryption!.streamCipher, PdfCipher.none);
      expect(titleOf(reopened), 'Rewritten');
    });
  });

  test('the /Encrypt string ciphers are the ones the handler advertises', () {
    // sanity: the fixture handler really uses RC4 so the round-trips above
    // are meaningful (a no-op cipher would pass every assertion vacuously).
    expect(handler().stringCipher, PdfCipher.rc4);
    expect(handler().streamCipher, PdfCipher.rc4);
  });

  test('handler-owned policy matches what an encrypted document decodes', () {
    // The document loader and this handler now share one exempt policy;
    // this guards against the two drifting apart again.
    final doc = CosDocument.open(buildEncryptedPdf(revision: 4));
    final page = doc
        .resolve((doc.resolve(doc.catalog['Pages']) as CosDictionary)['Kids']);
    final pageDict = doc.resolve((page as CosArray)[0]) as CosDictionary;
    final contents = doc.resolve(pageDict['Contents']) as CosStream;
    expect(doc.encryption!.streamPayloadIsEncrypted(contents, doc.resolve),
        isTrue);
    expect(latin1.decode(doc.decodeStreamData(contents)),
        'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET');
  });
}

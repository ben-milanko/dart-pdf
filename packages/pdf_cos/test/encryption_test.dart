import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  const expectedContent = 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET';

  void expectDecrypted(CosDocument doc) {
    expect(doc.isEncrypted, isTrue);
    final page = doc.resolve(
        (doc.resolve(doc.catalog['Pages']) as CosDictionary)['Kids']);
    final pageDict =
        doc.resolve((page as CosArray)[0]) as CosDictionary;
    final contents = doc.resolve(pageDict['Contents']) as CosStream;
    expect(latin1.decode(doc.decodeStreamData(contents)), expectedContent);
    final info = doc.resolve(doc.trailer['Info']) as CosDictionary;
    expect((doc.resolve(info['Title']) as CosString).text, 'Secret Title');
  }

  group('decrypts with the empty user password', () {
    for (final (revision, name) in [
      (2, 'R2 RC4 40-bit'),
      (3, 'R3 RC4 128-bit'),
      (4, 'R4 AES-128 (AESV2)'),
      (6, 'R6 AES-256 (AESV3)'),
    ]) {
      test(name, () {
        expectDecrypted(
            CosDocument.open(buildEncryptedPdf(revision: revision)));
      });
    }
  });

  group('decrypts with a non-empty user password', () {
    for (final revision in [2, 3, 4, 6]) {
      test('R$revision', () {
        final bytes =
            buildEncryptedPdf(revision: revision, userPassword: 'hunter2');
        expectDecrypted(CosDocument.open(bytes, password: 'hunter2'));
      });
    }
  });

  group('the owner password opens the document too', () {
    for (final revision in [2, 3, 4, 6]) {
      test('R$revision', () {
        final bytes = buildEncryptedPdf(
            revision: revision,
            userPassword: 'hunter2',
            ownerPassword: 'admin');
        expectDecrypted(CosDocument.open(bytes, password: 'admin'));
      });
    }
  });

  group('a wrong password throws CosPasswordException', () {
    for (final revision in [2, 3, 4, 6]) {
      test('R$revision', () {
        final bytes =
            buildEncryptedPdf(revision: revision, userPassword: 'hunter2');
        expect(() => CosDocument.open(bytes, password: 'wrong'),
            throwsA(isA<CosPasswordException>()));
        // and the empty default is wrong here too
        expect(() => CosDocument.open(bytes),
            throwsA(isA<CosPasswordException>()));
      });
    }
  });

  group('encrypt-on-write', () {
    for (final revision in [2, 3, 4, 6]) {
      test('R$revision round-trips string and stream edits', () {
        final doc = CosDocument.open(buildEncryptedPdf(revision: revision));
        final updater = CosIncrementalUpdater(doc);

        final infoRef = doc.trailer['Info'] as CosReference;
        updater.replaceObject(
            infoRef.objectNumber,
            CosDictionary({'Title': CosString.fromText('Updated Title')}));
        final payload = ascii('fresh plaintext stream payload');
        final streamRef = updater.addObject(CosStream(
            CosDictionary({'Length': CosInteger(payload.length)}), payload));

        final saved = updater.save();

        // the appended bytes must not leak the plaintext
        final tail = saved.sublist(doc.bytes.length);
        expect(String.fromCharCodes(tail), isNot(contains('Updated Title')));
        expect(String.fromCharCodes(tail),
            isNot(contains('fresh plaintext stream payload')));

        final reopened = CosDocument.open(saved);
        final info = reopened.resolve(reopened.trailer['Info'])
            as CosDictionary;
        expect((reopened.resolve(info['Title']) as CosString).text,
            'Updated Title');
        final stream = reopened.getObject(streamRef.objectNumber, 0)
            as CosStream;
        expect(reopened.decodeStreamData(stream), payload);
        // untouched original content still decrypts
        final kids = reopened.resolve((reopened
            .resolve(reopened.catalog['Pages']) as CosDictionary)['Kids']);
        final pageDict =
            reopened.resolve((kids as CosArray)[0]) as CosDictionary;
        final contents =
            reopened.resolve(pageDict['Contents']) as CosStream;
        expect(latin1.decode(reopened.decodeStreamData(contents)),
            expectedContent);
      });
    }

    test('passworded documents stay passworded after an edit', () {
      final original =
          buildEncryptedPdf(revision: 4, userPassword: 'hunter2');
      final doc = CosDocument.open(original, password: 'hunter2');
      final updater = CosIncrementalUpdater(doc);
      final infoRef = doc.trailer['Info'] as CosReference;
      updater.replaceObject(infoRef.objectNumber,
          CosDictionary({'Title': CosString.fromText('Edited')}));
      final saved = updater.save();
      expect(() => CosDocument.open(saved),
          throwsA(isA<CosPasswordException>()));
      final reopened = CosDocument.open(saved, password: 'hunter2');
      final info =
          reopened.resolve(reopened.trailer['Info']) as CosDictionary;
      expect((reopened.resolve(info['Title']) as CosString).text, 'Edited');
    });

    test('a fresh /Crypt-Identity stream is written plain, not re-encrypted',
        () {
      // The verified bug (issue #313): the updater's exempt policy omitted
      // the /Crypt-filter-with-/Identity case the loader honoured, so
      // encrypt-on-write would wrongly re-encrypt an Identity-crypt stream.
      // The policy now lives once, on the handler.
      final doc = CosDocument.open(buildEncryptedPdf(revision: 4));
      final updater = CosIncrementalUpdater(doc);
      const marker = 'identity-crypt payload stays plain';
      updater.addObject(CosStream(
          CosDictionary({
            'Length': CosInteger(marker.length),
            'Filter': const CosName('Crypt'),
            'DecodeParms':
                CosDictionary({'Name': const CosName('Identity')}),
          }),
          ascii(marker)));

      final saved = updater.save();
      final tail = String.fromCharCodes(saved.sublist(doc.bytes.length));
      // exempt from encryption, so the plaintext survives verbatim
      expect(tail, contains(marker));
    });

    test('resaving a loaded stream does not double-encrypt it', () {
      final doc = CosDocument.open(buildEncryptedPdf(revision: 4));
      final page = doc.resolve(
          (doc.resolve(doc.catalog['Pages']) as CosDictionary)['Kids']);
      final pageDict =
          doc.resolve((page as CosArray)[0]) as CosDictionary;
      final contents = doc.resolve(pageDict['Contents']) as CosStream;
      final updater = CosIncrementalUpdater(doc)..markChanged(contents);
      final reopened = CosDocument.open(updater.save());
      final reKids = reopened.resolve((reopened
          .resolve(reopened.catalog['Pages']) as CosDictionary)['Kids']);
      final rePage =
          reopened.resolve((reKids as CosArray)[0]) as CosDictionary;
      final reContents = reopened.resolve(rePage['Contents']) as CosStream;
      expect(latin1.decode(reopened.decodeStreamData(reContents)),
          expectedContent);
    });
  });

  test('unencrypted documents are unaffected', () {
    final doc = CosDocument.open(buildClassicPdf());
    expect(doc.isEncrypted, isFalse);
    expect(doc.encryption, isNull);
  });

  test('the /Encrypt dictionary strings stay raw', () {
    final doc = CosDocument.open(buildEncryptedPdf(revision: 3));
    final encrypt = doc.resolve(doc.trailer['Encrypt']) as CosDictionary;
    final o = doc.resolve(encrypt['O']) as CosString;
    expect(o.bytes, hasLength(32)); // untouched Algorithm 3 output
    expect(doc.encryption!.stringCipher, PdfCipher.rc4);
  });

  test('V4 crypt filters map to the right ciphers', () {
    final doc = CosDocument.open(buildEncryptedPdf(revision: 4));
    expect(doc.encryption!.stringCipher, PdfCipher.aes128);
    expect(doc.encryption!.streamCipher, PdfCipher.aes128);
  });

  test('R6 uses the file key for all content', () {
    final doc = CosDocument.open(buildEncryptedPdf(revision: 6));
    expect(doc.encryption!.revision, 6);
    expect(doc.encryption!.streamCipher, PdfCipher.aes256);
  });
}

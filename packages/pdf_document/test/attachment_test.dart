import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  group('embedded files', () {
    test('add then reopen exposes name, bytes, size, mime and checksum', () {
      final data = bytesOf('hello attachment world');
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      editor.addEmbeddedFile('notes.txt', data,
          description: 'a note', mimeType: 'text/plain');

      final attachments = PdfAttachments.of(reopened(editor));
      expect(attachments.embeddedFiles, hasLength(1));
      final file = attachments.embeddedFiles.single;
      expect(file.name, 'notes.txt');
      expect(file.fileName, 'notes.txt');
      expect(file.description, 'a note');
      expect(file.mimeType, 'text/plain');
      expect(file.size, data.length);
      expect(file.bytes(), data);
      expect(file.checksum, Uint8List.fromList(crypto.md5.convert(data).bytes));
    });

    test('uncompressed embedding also round-trips', () {
      final data = bytesOf('raw bytes');
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('raw.bin', data, compress: false);
      final file = PdfAttachments.of(reopened(editor)).embeddedFiles.single;
      expect(file.bytes(), data);
    });

    test('multiple files are stored name-sorted', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('zeta.txt', bytesOf('z'))
        ..addEmbeddedFile('alpha.txt', bytesOf('a'))
        ..addEmbeddedFile('mid.txt', bytesOf('m'));
      final files = PdfAttachments.of(reopened(editor)).embeddedFiles;
      expect(files.map((f) => f.name), ['alpha.txt', 'mid.txt', 'zeta.txt']);
    });

    test('adding the same name replaces the entry', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('doc.txt', bytesOf('first'))
        ..addEmbeddedFile('doc.txt', bytesOf('second'));
      final files = PdfAttachments.of(reopened(editor)).embeddedFiles;
      expect(files, hasLength(1));
      expect(files.single.bytes(), bytesOf('second'));
    });

    test('remove drops a file from the name tree', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('keep.txt', bytesOf('k'))
        ..addEmbeddedFile('drop.txt', bytesOf('d'));
      expect(editor.removeEmbeddedFile('drop.txt'), isTrue);
      expect(editor.removeEmbeddedFile('missing.txt'), isFalse);
      final files = PdfAttachments.of(reopened(editor)).embeddedFiles;
      expect(files.map((f) => f.name), ['keep.txt']);
    });

    test('removing the last file clears /EmbeddedFiles', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('only.txt', bytesOf('o'));
      editor.removeEmbeddedFile('only.txt');
      expect(PdfAttachments.of(reopened(editor)).embeddedFiles, isEmpty);
    });

    test('dates round-trip', () {
      final created = DateTime.utc(2023, 5, 4, 12, 30, 15);
      final modified = DateTime.utc(2024, 1, 2, 3, 4, 5);
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..addEmbeddedFile('dated.txt', bytesOf('x'),
            creationDate: created, modificationDate: modified);
      final file = PdfAttachments.of(reopened(editor)).embeddedFiles.single;
      expect(file.creationDate, created);
      expect(file.modificationDate, modified);
    });
  });

  group('file-attachment annotations', () {
    test('adds an annotation carrying its own embedded file', () {
      final data = bytesOf('annotation payload');
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
        ..addFileAttachmentAnnotation(1,
            fileName: 'clip.txt',
            data: data,
            rect: const PdfRect(100, 100, 120, 120),
            description: 'see attached',
            mimeType: 'text/plain');

      final out = reopened(editor);
      final attachments = PdfAttachments.of(out);
      expect(attachments.embeddedFiles, isEmpty);
      expect(attachments.fileAttachments, hasLength(1));
      final file = attachments.fileAttachments.single;
      expect(file.fileName, 'clip.txt');
      expect(file.bytes(), data);
      expect(file.mimeType, 'text/plain');

      // a real /FileAttachment annotation lives on the page
      final annots = out.cos.resolve(out.page(1).dict['Annots']) as CosArray;
      final annot = out.cos.resolve(annots[0]) as CosDictionary;
      expect((annot['Subtype'] as CosName).value, 'FileAttachment');
    });
  });

  test('saves are incremental: original bytes survive verbatim', () {
    final original = buildMultiPagePdf(1);
    final editor = PdfEditor(PdfDocument.open(original))
      ..addEmbeddedFile('a.txt', bytesOf('a'));
    final saved = editor.save();
    expect(saved.sublist(0, original.length), original);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as fs;

import 'package:dart_pdf_editor_app/file_io.dart';

class _FakeFileSelector extends fs.FileSelectorPlatform {
  _FakeFileSelector(this.files);

  final List<fs.XFile> files;
  bool openedMultiple = false;
  List<fs.XTypeGroup>? acceptedTypeGroups;

  @override
  Future<List<fs.XFile>> openFiles({
    List<fs.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openedMultiple = true;
    this.acceptedTypeGroups = acceptedTypeGroups;
    return files;
  }

  @override
  Future<fs.XFile?> openFile({
    List<fs.XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    this.acceptedTypeGroups = acceptedTypeGroups;
    return files.isEmpty ? null : files.first;
  }
}

void main() {
  test('ensurePdfName adds a .pdf extension and a default stem', () {
    expect(ensurePdfName('report'), 'report.pdf');
    expect(ensurePdfName('report.pdf'), 'report.pdf');
    expect(ensurePdfName('  '), 'document.pdf');
  });

  test('ensurePdfExtension forces .pdf on a chosen save path', () {
    // The desktop save dialog can hand back a path with no/other extension.
    expect(ensurePdfExtension('/home/ben/pages'), '/home/ben/pages.pdf');
    expect(ensurePdfExtension('/home/ben/pages.PDF'), '/home/ben/pages.PDF');
    expect(ensurePdfExtension('/home/ben/pages.pdf'), '/home/ben/pages.pdf');
    expect(ensurePdfExtension(r'C:\Docs\export'), r'C:\Docs\export.pdf');
  });

  test('ensureJsonExtension forces .json on a chosen save path', () {
    expect(ensureJsonExtension('/home/ben/stamps'), '/home/ben/stamps.json');
    expect(
        ensureJsonExtension('/home/ben/stamps.JSON'), '/home/ben/stamps.JSON');
  });

  test('custom stamp bundles round-trip and accept plain lists', () {
    final stamp = PdfCustomStamp(
      text: 'PAID',
      color: 0xC03030,
      template: PdfStampTemplate.text('PAID', 0xC03030),
      type: 'Approval',
      tags: const ['audit'],
    );

    final bundle = encodeCustomStampBundle([stamp]);
    final decoded = jsonDecode(bundle) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect(decoded['stamps'], isA<List>());
    expect(decodeCustomStampBundle(bundle), [stamp]);

    final plainList = jsonEncode([stamp.encode()]);
    expect(decodeCustomStampBundle(plainList), [stamp]);
  });

  test('custom stamp bundle rejects malformed entries', () {
    expect(
      () => decodeCustomStampBundle('{"stamps":[{"text":"BROKEN"}]}'),
      throwsFormatException,
    );
  });

  testWidgets('pickPdfFiles enables multi-select in the file picker',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('dartpdf_pick');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = '${dir.path}/a.pdf';
    final b = '${dir.path}/b.pdf';
    File(a).writeAsBytesSync([1]);
    File(b).writeAsBytesSync([2]);

    final original = fs.FileSelectorPlatform.instance;
    final fake = _FakeFileSelector([fs.XFile(a), fs.XFile(b)]);
    fs.FileSelectorPlatform.instance = fake;
    addTearDown(() => fs.FileSelectorPlatform.instance = original);

    final files = await pickPdfFiles('PDF documents');
    expect(fake.openedMultiple, isTrue);
    expect(fake.acceptedTypeGroups, hasLength(1));
    expect(fake.acceptedTypeGroups!.single.label, 'PDF documents');
    expect(fake.acceptedTypeGroups!.single.extensions, ['pdf']);
    expect(files.map((f) => f.path), [a, b]);
  });

  testWidgets('single-file pickers pass their localized filter label through',
      (tester) async {
    final original = fs.FileSelectorPlatform.instance;
    final fake = _FakeFileSelector(
        [fs.XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'x')]);
    fs.FileSelectorPlatform.instance = fake;
    addTearDown(() => fs.FileSelectorPlatform.instance = original);

    await pickPdfBytes('PDF documents');
    expect(fake.acceptedTypeGroups!.single.label, 'PDF documents');
    expect(fake.acceptedTypeGroups!.single.extensions, ['pdf']);

    await pickImageBytes('Images');
    expect(fake.acceptedTypeGroups!.single.label, 'Images');
    expect(fake.acceptedTypeGroups!.single.extensions,
        containsAll(['png', 'jpg', 'jpeg']));
  });

  testWidgets('importCustomStamps filters on the stamp-bundle label',
      (tester) async {
    final stamp = PdfCustomStamp(
      text: 'PAID',
      color: 0xC03030,
      template: PdfStampTemplate.text('PAID', 0xC03030),
      type: 'Approval',
    );
    final original = fs.FileSelectorPlatform.instance;
    final fake = _FakeFileSelector([
      fs.XFile.fromData(
        Uint8List.fromList(utf8.encode(encodeCustomStampBundle([stamp]))),
        name: 'stamps.json',
      ),
    ]);
    fs.FileSelectorPlatform.instance = fake;
    addTearDown(() => fs.FileSelectorPlatform.instance = original);

    final stamps = await importCustomStamps('DartPDF stamps');
    expect(stamps, [stamp]);
    expect(fake.acceptedTypeGroups!.single.label, 'DartPDF stamps');
    expect(fake.acceptedTypeGroups!.single.extensions, ['json']);
  });

  test('saveBytesToPath overwrites the file in place', () async {
    final dir = await Directory.systemTemp.createTemp('dartpdf_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/out.pdf';

    final result =
        await saveBytesToPath(Uint8List.fromList([1, 2, 3, 4]), path);
    expect(result.succeeded, isTrue);
    expect(result.path, path);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);

    // A second save overwrites, not appends.
    await saveBytesToPath(Uint8List.fromList([9, 9]), path);
    expect(await File(path).readAsBytes(), [9, 9]);
  });

  test('readPdfAtPath reads a snapshot back off disk on native', () async {
    // Native's byte-snapshot store (readCachedPdf) declines, so readPdfAtPath
    // reads the recent/session file straight off its filesystem path.
    final dir = await Directory.systemTemp.createTemp('dartpdf_read');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/recent.pdf';
    await File(path).writeAsBytes([37, 80, 68, 70]); // %PDF

    expect(await readPdfAtPath(path), [37, 80, 68, 70]);
  });

  test('readPdfAtPath throws for a missing file so the caller drops it',
      () async {
    await expectLater(
      readPdfAtPath('/no/such/dir/gone.pdf'),
      throwsA(anything),
    );
  });

  test('saveBytesToPath reports failure for an unwritable path', () async {
    final result = await saveBytesToPath(Uint8List(1), '/no/such/dir/out.pdf');
    expect(result.succeeded, isFalse);
    expect(result.message, startsWith('Save failed'));
  });

  testWidgets(
      'saveBytesAs forces .pdf when the save dialog drops the extension',
      (tester) async {
    // Drive the desktop branch: the dialog returns whatever path the user
    // typed, so an extensionless choice must still be written as a `.pdf`.
    // The platform override must be cleared before the test body returns (the
    // binding asserts foundation debug vars are unset), so reset it inline.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }));

      // Real file I/O and the platform-channel reply only complete on the live
      // event loop, so the whole save must run inside runAsync.
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('dartpdf_saveas');
        final chosen = '${dir.path}/exported'; // user cleared the .pdf
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/file_selector'),
          (call) async => call.method == 'getSavePath' ? chosen : null,
        );
        try {
          final result = await saveBytesAs(
              ctx, Uint8List.fromList([1, 2, 3, 4]), 'exported',
              pdfLabel: 'PDF documents');

          expect(result.succeeded, isTrue);
          expect(result.path, '$chosen.pdf');
          expect(await File('$chosen.pdf').readAsBytes(), [1, 2, 3, 4]);
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/file_selector'),
            null,
          );
          await dir.delete(recursive: true);
        }
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/file_io.dart';

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

  test('saveBytesToPath overwrites the file in place', () async {
    final dir = await Directory.systemTemp.createTemp('dartpdf_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/out.pdf';

    final result = await saveBytesToPath(Uint8List.fromList([1, 2, 3, 4]), path);
    expect(result.succeeded, isTrue);
    expect(result.path, path);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);

    // A second save overwrites, not appends.
    await saveBytesToPath(Uint8List.fromList([9, 9]), path);
    expect(await File(path).readAsBytes(), [9, 9]);
  });

  test('saveBytesToPath reports failure for an unwritable path', () async {
    final result =
        await saveBytesToPath(Uint8List(1), '/no/such/dir/out.pdf');
    expect(result.succeeded, isFalse);
    expect(result.message, startsWith('Save failed'));
  });

  testWidgets('saveBytesAs forces .pdf when the save dialog drops the extension',
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
              ctx, Uint8List.fromList([1, 2, 3, 4]), 'exported');

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

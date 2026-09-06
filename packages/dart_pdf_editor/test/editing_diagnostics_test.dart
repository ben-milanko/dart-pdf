// The session diagnostics getters the devtools Session panel reads:
// revisionCount (undo/redo history length) and sessionBufferBytes (the
// grow-only buffer that only ever grows within a session - the memory-audit
// signal). Every edit is an incremental save appended to one buffer, so an
// edit both grows the buffer and adds a revision; undo/redo moves the cursor
// without shrinking either.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfEditingController session diagnostics', () {
    test('a fresh session is one revision sized to the opened bytes', () {
      SharedPreferences.setMockInitialValues({});
      final source = buildMultiPagePdf(1);
      final editing = PdfEditingController(source);
      addTearDown(editing.dispose);

      expect(editing.revisionCount, 1);
      expect(editing.sessionBufferBytes, source.length);
      expect(editing.canUndo, isFalse);
    });

    test('each edit adds a revision and grows the buffer', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      final buffer0 = editing.sessionBufferBytes;

      editing.placeCheckMark(0, 100, 100);
      expect(editing.revisionCount, 2);
      expect(editing.sessionBufferBytes, greaterThan(buffer0),
          reason: 'the incremental revision appended to the buffer');
      final buffer1 = editing.sessionBufferBytes;

      editing.placeCheckMark(0, 200, 200);
      expect(editing.revisionCount, 3);
      expect(editing.sessionBufferBytes, greaterThan(buffer1));

      // The current revision view is a prefix of the whole grow-only buffer.
      expect(editing.bytes.length, lessThanOrEqualTo(editing.sessionBufferBytes));
    });

    test('undo keeps the buffer and revision history intact', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      editing.placeCheckMark(0, 100, 100);
      final revisionsAfterEdit = editing.revisionCount;
      final bufferAfterEdit = editing.sessionBufferBytes;
      final currentBytes = editing.bytes.length;

      editing.undo();
      // Undo rewinds the cursor - so "save to disk" shrinks back...
      expect(editing.bytes.length, lessThan(currentBytes));
      // ...but the history and grow-only buffer are unchanged (redo works).
      expect(editing.revisionCount, revisionsAfterEdit);
      expect(editing.sessionBufferBytes, bufferAfterEdit);
      expect(editing.canRedo, isTrue);
    });
  });
}

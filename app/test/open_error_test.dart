import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/open_error.dart';

void main() {
  test('filesystem summaries omit exception plumbing and the source path', () {
    final error = FileSystemException(
      'Cannot open file',
      r'C:\Users\ben\OneDrive - Company\Very long folder\drawing.pdf',
      const OSError('The system cannot find the file specified', 2),
    );

    final summary = openErrorSummary(error);

    expect(
        summary, 'Cannot open file: The system cannot find the file specified');
    expect(summary, isNot(contains(r'C:\Users')));
    expect(summary, isNot(contains('FileSystemException')));
    expect(summary, isNot(contains('errno')));
  });
}

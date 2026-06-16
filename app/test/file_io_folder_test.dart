import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/file_io.dart';

void main() {
  group('containingFolderPath', () {
    test('returns POSIX parent folders', () {
      expect(containingFolderPath('/Users/ben/Documents/file.pdf'),
          '/Users/ben/Documents');
      expect(containingFolderPath('/file.pdf'), '/');
    });

    test('returns Windows parent folders', () {
      expect(containingFolderPath(r'C:\Users\ben\file.pdf'), r'C:\Users\ben');
      expect(containingFolderPath(r'C:\file.pdf'), r'C:\');
    });
  });
}

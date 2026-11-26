// DocumentTab's own identity, apart from the tab-set transitions that
// dart_pdf_tabs' DocumentTabs tests cover.

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('documentId keys by the origin, not the title', () {
    final one =
        DocumentTab.loading(title: 'report.pdf', originPath: '/a/report.pdf');
    final two =
        DocumentTab.loading(title: 'report.pdf', originPath: '/b/report.pdf');
    final cached =
        DocumentTab.loading(title: 'report.pdf', cachePath: 'cache/123.pdf');
    final bare = DocumentTab.loading(title: 'report.pdf');
    expect(one.documentId, isNot(two.documentId));
    expect(cached.documentId, 'cache/123.pdf');
    expect(bare.documentId, 'report.pdf');
  });

  test('a loading tab is a placeholder; an error tab is not', () {
    expect(DocumentTab.loading(title: 'a.pdf').isPlaceholder, isTrue);
    expect(
        DocumentTab.error(title: 'a.pdf', error: 'x').isPlaceholder, isFalse);
  });
}

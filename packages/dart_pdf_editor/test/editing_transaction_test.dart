import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('document mutation drives narrow render and content stamps', () {
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);
    final render = [for (var i = 0; i < 3; i++) editing.pageRenderStamp(i)];
    final content = [
      for (var i = 0; i < 3; i++) editing.pageContentRenderStamp(i),
    ];

    expect(
      editing.apply(
        (editor) => editor.stampPage(
          1,
          (stamp) => stamp.text('impact', x: 10, y: 10),
        ),
      ),
      isTrue,
    );

    expect(editing.pageRenderStamp(0), render[0]);
    expect(editing.pageRenderStamp(1), greaterThan(render[1]));
    expect(editing.pageRenderStamp(2), render[2]);
    expect(editing.pageContentRenderStamp(0), content[0]);
    expect(editing.pageContentRenderStamp(1), greaterThan(content[1]));
    expect(editing.pageContentRenderStamp(2), content[2]);
  });

  test('annotation metadata emits sync without invalidating rendering',
      () async {
    final editing = PdfEditingController(buildClassicPdf())
      ..addRectangle(0, const PdfRect(100, 600, 200, 700))
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    final render = editing.pageRenderStamp(0);
    final content = editing.pageContentRenderStamp(0);
    final batches = <List<PdfAnnotationChange>>[];
    final subscription = editing.annotationChanges.listen(batches.add);
    addTearDown(subscription.cancel);

    expect(editing.setSelectedAuthor('Ben'), isTrue);
    await pumpEventQueue();

    expect(editing.pageRenderStamp(0), render);
    expect(editing.pageContentRenderStamp(0), content);
    expect(batches, hasLength(1));
    expect(batches.single.single.kind, PdfAnnotationChangeKind.modified);
  });

  test('undo and redo replay the mutation-reported impact', () {
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);

    editing.addRectangle(1, const PdfRect(100, 600, 200, 700));
    final afterEdit = [
      for (var i = 0; i < 3; i++) editing.pageRenderStamp(i),
    ];
    editing.undo();
    final afterUndo = [
      for (var i = 0; i < 3; i++) editing.pageRenderStamp(i),
    ];
    editing.redo();
    final afterRedo = [
      for (var i = 0; i < 3; i++) editing.pageRenderStamp(i),
    ];

    expect(afterUndo[0], afterEdit[0]);
    expect(afterUndo[1], greaterThan(afterEdit[1]));
    expect(afterUndo[2], afterEdit[2]);
    expect(afterRedo[0], afterUndo[0]);
    expect(afterRedo[1], greaterThan(afterUndo[1]));
    expect(afterRedo[2], afterUndo[2]);
  });

  test('structural mutation clears page and annotation selection', () {
    final editing = PdfEditingController(buildMultiPagePdf(3))
      ..addRectangle(0, const PdfRect(100, 600, 200, 700))
      ..selectAnnotation(0, 0)
      ..selectPage(0);
    addTearDown(editing.dispose);

    expect(editing.apply((editor) => editor.movePage(0, 2)), isTrue);

    expect(editing.hasAnnotationSelection, isFalse);
    expect(editing.selectedPages, isEmpty);
  });

  test('legacy impact hints remain compatible for custom mutations', () {
    final editing = PdfEditingController(buildMultiPagePdf(2));
    addTearDown(editing.dispose);
    final before = editing.pageRenderStamp(1);

    expect(
      editing.apply(
        (editor) => editor.setInfo(title: 'legacy'),
        pages: const [1],
        contentPages: const [],
      ),
      isTrue,
    );

    expect(editing.pageRenderStamp(1), greaterThan(before));
  });
}

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PdfRect> _markupQuads(
  List<PdfRect> input, {
  PdfMarkupKind kind = PdfMarkupKind.highlight,
}) {
  final editing = PdfEditingController(buildMultiPagePdf(1));
  addTearDown(editing.dispose);
  editing.addMarkup(kind, {0: input});
  return editing.document.page(0).annotations.single.behavior.markupQuads!;
}

Set<String> _grouping(List<PdfRect> quads) => {
      for (final q in quads) '${q.left},${q.bottom},${q.right},${q.top}',
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('selected English words become one continuous line highlight', () {
    expect(
      _markupQuads(const [
        PdfRect(100, 700, 170, 724),
        PdfRect(210, 700, 280, 724),
      ]),
      const [PdfRect(100, 700, 280, 724)],
    );
  });

  test('selected Chinese runs become one continuous line highlight', () {
    expect(
      _markupQuads(const [
        PdfRect(40, 650, 64, 674),
        PdfRect(64, 650, 88, 674),
        PdfRect(88, 650, 136, 674),
      ]),
      const [PdfRect(40, 650, 136, 674)],
    );
  });

  test('horizontal gap size does not split one selected line', () {
    expect(
      _markupQuads(const [
        PdfRect(40, 650, 80, 674),
        PdfRect(300, 650, 360, 674),
      ]),
      const [PdfRect(40, 650, 360, 674)],
    );
  });

  test('separate visual lines remain separate', () {
    expect(
      _markupQuads(const [
        PdfRect(100, 700, 160, 712),
        PdfRect(180, 700, 240, 712),
        PdfRect(100, 680, 170, 692),
        PdfRect(190, 680, 260, 692),
      ]),
      const [
        PdfRect(100, 700, 240, 712),
        PdfRect(100, 680, 260, 692),
      ],
    );
  });

  test('mixed heights sharing a line merge', () {
    expect(
      _markupQuads(const [
        PdfRect(100, 700, 150, 712),
        PdfRect(160, 697, 230, 715),
      ]),
      const [PdfRect(100, 697, 230, 715)],
    );
  });

  test('a tall bridge cannot transitively merge distinct lines', () {
    final quads = _markupQuads(const [
      PdfRect(100, 700, 150, 712),
      PdfRect(155, 694, 205, 718),
      PdfRect(210, 686, 260, 698),
    ]);
    expect(quads, const [
      PdfRect(100, 694, 205, 718),
      PdfRect(210, 686, 260, 698),
    ]);
  });

  test('forward reversed and shuffled input keep the same line grouping', () {
    const forward = [
      PdfRect(10, 700, 30, 712),
      PdfRect(40, 700, 60, 712),
      PdfRect(10, 680, 30, 692),
      PdfRect(40, 680, 60, 692),
    ];
    final expected = _grouping(_markupQuads(forward));
    expect(_grouping(_markupQuads(forward.reversed.toList())), expected);
    expect(
      _grouping(_markupQuads([forward[2], forward[0], forward[3], forward[1]])),
      expected,
    );
  });

  test('line output order follows the earliest original member', () {
    expect(
      _markupQuads(const [
        PdfRect(10, 680, 30, 692),
        PdfRect(10, 700, 30, 712),
        PdfRect(40, 680, 60, 692),
        PdfRect(40, 700, 60, 712),
      ]),
      const [
        PdfRect(10, 680, 60, 692),
        PdfRect(10, 700, 60, 712),
      ],
    );
  });

  test('diagonal and vertical arrangements remain unmerged', () {
    expect(
      _markupQuads(const [
        PdfRect(100, 700, 112, 712),
        PdfRect(114, 694, 126, 706),
        PdfRect(128, 688, 140, 700),
      ]),
      hasLength(3),
    );
  });

  test('invalid rectangles are ignored', () {
    expect(
      _markupQuads(const [
        PdfRect(double.nan, 0, 10, 10),
        PdfRect(0, 0, double.infinity, 10),
        PdfRect(10, 10, 10, 20),
        PdfRect(20, 20, 10, 30),
        PdfRect(100, 700, 180, 712),
      ]),
      const [PdfRect(100, 700, 180, 712)],
    );
  });

  test('an all-invalid request is a true no-op', () {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    final document = editing.document;
    final revision = editing.revisionId;

    editing.addMarkup(PdfMarkupKind.highlight, const {
      0: [
        PdfRect(double.nan, 0, 10, 10),
        PdfRect(0, 0, 0, 10),
      ],
    });

    expect(editing.revisionId, revision);
    expect(identical(editing.document, document), isTrue);
    expect(editing.document.page(0).annotations, isEmpty);
  });

  for (final kind in PdfMarkupKind.values) {
    test('$kind shares continuous selected-line geometry', () {
      expect(
        _markupQuads(
          const [
            PdfRect(100, 700, 150, 712),
            PdfRect(200, 700, 260, 712),
          ],
          kind: kind,
        ),
        const [PdfRect(100, 700, 260, 712)],
      );
    });
  }
}

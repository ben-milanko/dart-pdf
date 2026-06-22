import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('PdfPageView reserves the page aspect ratio', (tester) async {
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(child: PdfPageView(page: doc.page(0))),
    );
    final size = tester.getSize(find.byType(PdfPageView));
    // US Letter: 612 x 792
    expect(
        size.width / size.height, moreOrLessEquals(612 / 792, epsilon: 1e-6));
  });

  testWidgets('raising scale re-rasterizes at higher resolution',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    // lay out at exactly the page's point width so scale is the only factor
    Widget at(double scale) => Center(
        child:
            SizedBox(width: 612, child: PdfPageView(page: page, scale: scale)));

    await tester.pumpWidget(at(1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final base = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(base.width, 612);

    await tester.pumpWidget(at(3));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final zoomed = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(zoomed.width, 612 * 3);
  });

  testWidgets('raster resolution follows the on-screen width', (tester) async {
    // Regression: rasters were sized from the page's nominal point size,
    // so a page stretched across a wide window (or a big external
    // display) was upscaled and blurry.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    Widget at(double width) =>
        Center(child: SizedBox(width: width, child: PdfPageView(page: page)));

    await tester.pumpWidget(at(800));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final wide = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(wide.width, 800);

    await tester.pumpWidget(at(306));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final narrow = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(narrow.width, 306);
  });

  testWidgets('a structural epoch bump drops the slot\'s stale raster',
      (tester) async {
    // The lazy page list has no per-page key, so after an insert/remove/
    // reorder a page State is reused for a different page in the same slot.
    // A bumped pageEpoch must drop the previous page's raster so a fast
    // scroll can't paint it for the page now in the slot. renderHold (raised
    // by the viewer during a fast scroll) keeps the re-render pending, so the
    // raster shown between the swap and the new render is observable.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    // varied heights (792, 396, 1008) let us tell the pages apart by raster.
    final doc = PdfDocument.open(buildVariedHeightPdf(3));
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    Widget at(PdfPage page, int epoch) => Center(
        child: SizedBox(
            width: 612,
            child:
                PdfPageView(page: page, pageEpoch: epoch, renderHold: hold)));

    await tester.pumpWidget(at(doc.page(0), 0));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 792);

    // Hold renders (as during a fast scroll). A same-epoch page change (a
    // content-only edit reused the slot): the old raster is intentionally
    // kept and re-rendered in place when the hold releases — no blank flash.
    hold.value = true;
    await tester.pumpWidget(at(doc.page(2), 0));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 792,
        reason: 'a same-geometry edit keeps the raster while the render holds');

    // Bumped epoch (a structural change put a different page in this slot):
    // the stale raster must drop now, before the held render lands — else the
    // fast scroll paints page 0's image for page 2.
    await tester.pumpWidget(at(doc.page(2), 1));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing,
        reason: 'a structural epoch bump drops the previous page raster');

    // Releasing the hold re-renders for the page now in the slot.
    hold.value = false;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 1008);
  });

  testWidgets('raster resolution is capped at deep zoom', (tester) async {
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(child: PdfPageView(page: doc.page(0), scale: 1000)),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final images = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .map((w) => w.image!)
        .toList();
    // the base raster plus the deep-zoom detail patch
    expect(images, hasLength(2));
    for (final image in images) {
      // capped to ~2^24 total pixels (plus ceil() rounding), 8192/side
      expect(image.width * image.height, lessThan((1 << 24) * 1.001));
      expect(image.width, lessThanOrEqualTo(8192));
      expect(image.height, lessThanOrEqualTo(8192));
    }
  });

  testWidgets('no detail patch below the raster caps', (tester) async {
    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(child: PdfPageView(page: doc.page(0))),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('the detail patch is sharper than the capped base',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    // page laid out 10x wider than its point size: only a slice fits the
    // viewport, so the patch covers a fraction of the page (OverflowBox
    // lets the page exceed the test surface without overflow errors)
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: 6120, child: PdfPageView(page: doc.page(0))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final rawImages = find.byType(RawImage);
    expect(rawImages, findsNWidgets(2));
    final base = tester.widgetList<RawImage>(rawImages).first.image!;
    final patch = tester.widgetList<RawImage>(rawImages).last.image!;
    // base: 612x792 capped to sqrt(2^24/(612*792)) ≈ 5.88 px per point
    final baseDensity = base.width / 612;
    expect(baseDensity, lessThan(6));
    // patch density: raster pixels per page point of the area it covers
    final patchLayoutWidth = tester.getSize(rawImages.last).width;
    final patchPoints = patchLayoutWidth / 6120 * 612;
    expect(patch.width / patchPoints,
        moreOrLessEquals(10, epsilon: 0.5)); // the uncapped desired ratio
  });
}

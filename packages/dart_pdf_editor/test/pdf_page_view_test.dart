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

  testWidgets(
      'pages denser than retainedZoomReplayMaxCommands zoom via the '
      'cached-picture fallback', (tester) async {
    // Force every page over the density ceiling: no scene is retained and
    // the zoom re-raster must take the classic nested-picture path (the
    // same code retainedZoomReplay=false uses). Same assertions as the
    // retained-path test above - the two paths are byte-identical, so only
    // the raster geometry is observable.
    PdfPageView.retainedZoomReplayMaxCommands = 0;
    addTearDown(() => PdfPageView.retainedZoomReplayMaxCommands = 20000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
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
    // kept and re-rendered in place when the hold releases - no blank flash.
    hold.value = true;
    await tester.pumpWidget(at(doc.page(2), 0));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.height, 792,
        reason: 'a same-geometry edit keeps the raster while the render holds');

    // Bumped epoch (a structural change put a different page in this slot):
    // the stale raster must drop now, before the held render lands - else the
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

  testWidgets(
      'an additive content edit keeps the raster; a destructive one '
      'drops it', (tester) async {
    // After finishing an ink markup on a heavy page the document swaps and
    // the page's contentStamp advances. The old raster must stay painted
    // until the new render lands (the just-drawn markup rides on top via the
    // editing overlay) - otherwise the whole page flashes blank while the
    // slow re-interpret runs. A redaction burn, by contrast, advances the
    // destructiveStamp and must drop the (un-redacted) raster at once.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    Widget at({int content = 0, int destructive = 0}) => Center(
        child: SizedBox(
            width: 612,
            child: PdfPageView(
                page: page,
                contentStamp: content,
                destructiveStamp: destructive,
                renderHold: hold)));

    await tester.pumpWidget(at());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);

    // Hold renders (as the viewer does while a heavy page re-interprets).
    // An additive edit (contentStamp bump) keeps the raster on screen.
    hold.value = true;
    await tester.pumpWidget(at(content: 1));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'an additive edit must not flash the page blank');

    // A destructive edit (destructiveStamp bump) drops the raster at once so
    // the removed content can't linger before the re-render lands.
    await tester.pumpWidget(at(content: 1, destructive: 1));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing,
        reason: 'a destructive edit drops the stale raster immediately');

    // Releasing the hold re-renders.
    hold.value = false;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('an additive content edit keeps the detail patch until refreshed',
      (tester) async {
    // At deep zoom a sharp detail patch paints above the capped base raster.
    // After an annotation commit, keep that sharp patch while the editing
    // overlay's commit afterimage covers the new annotation. The overlay only
    // clears once the fresh detail patch has replaced it.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = PdfDocument.open(buildClassicPdf());
    final page = doc.page(0);
    final hold = ValueNotifier<bool>(false);
    addTearDown(hold.dispose);
    var ready = 0;
    Widget at({int content = 0}) => Center(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 6120,
              child: PdfPageView(
                page: page,
                contentStamp: content,
                renderHold: hold,
                onRasterReady: () => ready++,
              ),
            ),
          ),
        );

    await tester.pumpWidget(at());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2),
        reason: 'base raster plus deep-zoom detail patch');
    expect(ready, 1);

    hold.value = true;
    await tester.pumpWidget(at(content: 1));
    await tester.pump();

    expect(find.byType(RawImage), findsNWidgets(2),
        reason: 'the stale detail patch stays up for sharpness');
    expect(ready, 1,
        reason: 'the annotation afterimage must stay until a fresh detail '
            'patch is ready');
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

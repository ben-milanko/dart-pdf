import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/page_drag.dart';
import 'package:dart_pdf_editor_app/tab_drag.dart';

class _FakeLocator implements TabDropLocator {
  TabDropLocation? location;
  Object? failure;

  @override
  Future<TabDropLocation?> locate(Iterable<int> windowHandles) async {
    if (failure case final error?) throw error;
    return location;
  }
}

class _FakeWindow implements PageDropWindow {
  _FakeWindow(this.windowHandle, {this.session});

  @override
  final int windowHandle;
  final PdfEditingController? session;
  int? slot;
  bool accept = true;
  int? markedAt;
  int clears = 0;
  final List<({int pageCount, int? at})> accepted = [];

  @override
  bool ownsSession(PdfEditingController controller) =>
      identical(session, controller);

  @override
  int? pageDropIndexAt(Offset localPoint) {
    markedAt = slot;
    return slot;
  }

  @override
  void clearPageDropMarker() {
    markedAt = null;
    clears++;
  }

  @override
  bool acceptDroppedPages(Uint8List bytes, int pageCount, {int? at}) {
    if (!accept) return false;
    expect(PdfDocument.open(bytes).pageCount, pageCount);
    accepted.add((pageCount: pageCount, at: at));
    return true;
  }
}

void main() {
  late _FakeLocator locator;
  late PageDragCoordinator coordinator;
  late PdfEditingController source;
  late _FakeWindow home;
  late _FakeWindow other;

  setUp(() {
    locator = _FakeLocator();
    coordinator = PageDragCoordinator(locator: locator);
    source = PdfEditingController(buildMultiPagePdf(3),
        pageClipboard: PdfPageClipboard());
    home = _FakeWindow(1, session: source);
    other = _FakeWindow(2)..slot = 1;
    coordinator
      ..register(home)
      ..register(other);
  });

  tearDown(() {
    coordinator.dispose();
    source.dispose();
  });

  PdfPageDragOut drag(List<int> pages) => PdfPageDragOut(
        controller: source,
        pages: pages,
        globalPosition: const Offset(-10, 10),
      );

  void over(int handle) => locator.location =
      TabDropLocation(windowHandle: handle, localPoint: const Offset(5, 5));

  test('a drop over another window moves the pages there', () async {
    over(2);
    expect(await coordinator.drop(drag([0, 2])), PageDragResult.moved);
    expect(other.accepted.single, (pageCount: 2, at: 1));
    expect(source.document.pageCount, 1);
    // one undo in the source restores the pages it gave away
    source.undo();
    expect(source.document.pageCount, 3);
    expect(other.markedAt, isNull, reason: 'the drop clears the marker');
  });

  test('dragging every page out copies them', () async {
    over(2);
    expect(await coordinator.drop(drag([0, 1, 2])), PageDragResult.copied);
    expect(other.accepted.single.pageCount, 3);
    expect(source.document.pageCount, 3);
  });

  test('a drop over no window, or its own, does nothing', () async {
    locator.location = null;
    expect(await coordinator.drop(drag([0])), PageDragResult.cancelled);
    over(1);
    expect(await coordinator.drop(drag([0])), PageDragResult.cancelled);
    expect(home.accepted, isEmpty);
    expect(other.accepted, isEmpty);
    expect(source.document.pageCount, 3);
  });

  test('a refused or failed drop keeps the source pages', () async {
    over(2);
    other.accept = false;
    expect(await coordinator.drop(drag([0])), PageDragResult.failed);
    locator.failure = StateError('channel gone');
    expect(await coordinator.drop(drag([0])), PageDragResult.failed);
    expect(source.document.pageCount, 3);
  });

  test('hovering another window marks its slot until the drag returns',
      () async {
    over(2);
    coordinator.update(drag([0]));
    await pumpEventQueue();
    expect(other.markedAt, 1);
    expect(home.markedAt, isNull);

    coordinator.update(null);
    expect(other.markedAt, isNull);
  });
}

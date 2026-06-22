// The annotation sidebar's comment-thread UI: reply, show replies and the
// review-state chip, resolve and reopen — driving the controller's thread
// methods (which round-trip through pdf_document's reply model).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<void> pumpSidebar(WidgetTester tester, PdfEditingController editing,
      PdfViewerController viewer) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ),
          PdfAnnotationSidebar(controller: editing, viewerController: viewer),
        ]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('reply through the sidebar adds a thread reply', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..author = 'Ann'
      ..addNote(0, 100, 700, 'Please check');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    // open the reply field
    await tester.tap(find.byKey(const ValueKey('pdf-reply-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-reply-field')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('pdf-reply-field')), 'Looks fine to me');
    await tester.tap(find.byKey(const ValueKey('pdf-reply-send')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // the reply landed in the document, linked to the note
    final reply = editing.document
        .page(0)
        .annotations
        .firstWhere((a) => a.isReply);
    expect(reply.contents, 'Looks fine to me');
    expect(reply.author, 'Ann');
    expect(reply.subtype, 'Text');

    // and shows in the sidebar, with the field closed again
    expect(find.text('Looks fine to me'), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-reply-field')), findsNothing);

    // the reply is NOT listed as its own top-level row (Note appears once)
    expect(find.text('Note'), findsOneWidget);
  });

  testWidgets('resolve then reopen toggles the state chip', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..author = 'Ann'
      ..addRectangle(0, const PdfRect(100, 100, 200, 150));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    expect(find.text('Resolved'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pdf-resolve-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(PdfCommentThread.forPage(editing.document, 0).single.isResolved,
        isTrue);
    expect(find.text('Resolved'), findsOneWidget);

    // the button now reopens
    await tester.tap(find.byKey(const ValueKey('pdf-resolve-button')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(PdfCommentThread.forPage(editing.document, 0).single.isResolved,
        isFalse);
    expect(find.text('Resolved'), findsNothing);
  });

  testWidgets('controller.setReviewState records a review verdict',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..author = 'Ann'
      ..addRectangle(0, const PdfRect(100, 100, 200, 150));
    addTearDown(editing.dispose);

    final root = editing.document.page(0).annotations.single;
    expect(editing.setReviewState(0, root, PdfReviewState.accepted), isTrue);
    final thread = PdfCommentThread.forPage(editing.document, 0).single;
    expect(thread.state!.state, PdfReviewState.accepted);
    expect(thread.state!.author, 'Ann');

    // a blank reply is a no-op
    final fresh = editing.document.page(0).annotations
        .firstWhere((a) => !a.isReply && !a.isStateAnnotation);
    expect(editing.replyToAnnotation(0, fresh, '   '), isFalse);
  });

  testWidgets('sending an empty reply just closes the field', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addNote(0, 100, 700, 'root');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    await tester.tap(find.byKey(const ValueKey('pdf-reply-button')));
    await tester.pump();
    // send without typing anything
    await tester.tap(find.byKey(const ValueKey('pdf-reply-send')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-reply-field')), findsNothing);
    expect(editing.document.page(0).annotations.where((a) => a.isReply),
        isEmpty);
  });

  testWidgets('a reply emits on the change feed for sync', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addNote(0, 100, 700, 'root');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    final batches = <List<PdfAnnotationChange>>[];
    final sub = editing.annotationChanges.listen(batches.add);
    addTearDown(sub.cancel);

    final root = editing.document.page(0).annotations.single;
    editing.replyToAnnotation(0, root, 'a synced reply');
    await tester.pump();

    expect(batches, isNotEmpty);
    final created = batches.expand((b) => b).where(
        (c) => c.kind == PdfAnnotationChangeKind.created);
    expect(created.any((c) => c.snapshot?.inReplyTo == root.name), isTrue);
  });
}

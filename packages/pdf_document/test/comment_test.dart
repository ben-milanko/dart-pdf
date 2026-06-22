// Threaded comments (§12.5.6.x): replies linked by /IRT, review state via
// state replies, the read-only thread model, and round-tripping the IRT
// link through snapshots so threads sync.

import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

/// A base document with one named square to reply to, reopened so the
/// annotation is a real indirect object.
PdfDocument withRoot() => edited(
    PdfDocument.open(buildClassicPdf()),
    (e) => e.addSquare(0, const PdfRect(100, 600, 200, 680),
        contents: 'Please review', author: 'Ann', name: 'root-1'));

void main() {
  group('reply authoring', () {
    test('replyToAnnotation writes /IRT, /RT, contents, author, /NM', () {
      final root = withRoot().page(0).annotations.single;
      final doc = edited(withRoot(), (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'Looks good', author: 'Bob', name: 'reply-1');
      });
      expect(root.name, 'root-1');

      final reply = doc
          .page(0)
          .annotations
          .firstWhere((a) => a.name == 'reply-1');
      expect(reply.subtype, 'Text');
      expect(reply.contents, 'Looks good');
      expect(reply.author, 'Bob');
      expect(reply.replyType, 'R');
      expect(reply.isReply, isTrue);
      expect(reply.inReplyTo, 'root-1',
          reason: '/IRT resolves to the parent /NM');
      expect(reply.creationDate, isNotNull);
      // a reply carries no on-page appearance — it is thread content
      expect(reply.normalAppearance, isNull);
    });

    test('replies nest into a chain', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'first reply', name: 'r1', author: 'Bob');
      });
      doc = edited(doc, (e) {
        final r1 = e.document.page(0).annotations
            .firstWhere((a) => a.name == 'r1');
        e.replyToAnnotation(0, r1, 'reply to the reply',
            name: 'r2', author: 'Ann');
      });
      final r2 = doc.page(0).annotations.firstWhere((a) => a.name == 'r2');
      expect(r2.inReplyTo, 'r1');
    });

    test('can reply within the same session (staged objects resolve)', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..addSquare(0, const PdfRect(10, 10, 60, 60), name: 'fresh');
      // the staged annotation is already an indirect object (the updater
      // registers added objects), so a reply links to it without a reopen
      final fresh = doc.page(0).annotations.single;
      final replyName = editor.replyToAnnotation(0, fresh, 'hi', name: 'r');
      expect(replyName, 'r');
      final out = PdfDocument.open(editor.save());
      final reply = out.page(0).annotations.firstWhere((a) => a.name == 'r');
      expect(reply.inReplyTo, 'fresh');
    });
  });

  group('review state', () {
    test('setReviewState writes a state reply with empty contents', () {
      final doc = edited(withRoot(), (e) {
        e.setReviewState(0, e.document.page(0).annotations.single,
            PdfReviewState.accepted,
            author: 'Bob', name: 'state-1');
      });
      final state =
          doc.page(0).annotations.firstWhere((a) => a.name == 'state-1');
      expect(state.reviewState, 'Accepted');
      expect(state.stateModel, 'Review');
      expect(state.isStateAnnotation, isTrue);
      expect(state.contents, '', reason: '§12.5.6.2: empty /Contents');
      expect(state.inReplyTo, 'root-1');
    });

    test('resolveThread/reopenThread flip isResolved', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.resolveThread(0, e.document.page(0).annotations.single,
            author: 'Bob');
      });
      var thread = PdfCommentThread.forPage(doc, 0).single;
      expect(thread.isResolved, isTrue);
      expect(thread.state!.state, PdfReviewState.completed);

      // a later reopen wins (newer timestamp)
      doc = edited(doc, (e) {
        final root = e.document.page(0).annotations
            .firstWhere((a) => a.name == 'root-1');
        e.reopenThread(0, root, author: 'Ann',
            at: DateTime.utc(2030, 1, 1));
      });
      thread = PdfCommentThread.forPage(doc, 0).single;
      expect(thread.isResolved, isFalse);
      expect(thread.state!.state, PdfReviewState.none);
    });
  });

  group('thread model', () {
    test('forPage assembles root, replies, and state history', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        final root = e.document.page(0).annotations.single;
        e.replyToAnnotation(0, root, 'reply A',
            author: 'Bob', name: 'rA', createdAt: DateTime.utc(2030, 1, 1));
      });
      doc = edited(doc, (e) {
        final root = e.document.page(0).annotations
            .firstWhere((a) => a.name == 'root-1');
        e.replyToAnnotation(0, root, 'reply B',
            author: 'Cyd', name: 'rB', createdAt: DateTime.utc(2030, 1, 2));
      });
      doc = edited(doc, (e) {
        final root = e.document.page(0).annotations
            .firstWhere((a) => a.name == 'root-1');
        e.setReviewState(0, root, PdfReviewState.accepted, author: 'Bob');
      });

      final threads = PdfCommentThread.forPage(doc, 0);
      expect(threads, hasLength(1));
      final thread = threads.single;
      expect(thread.name, 'root-1');
      expect(thread.replyCount, 2);
      expect(thread.root.text, 'Please review');
      expect(thread.root.replies.map((c) => c.name), ['rA', 'rB'],
          reason: 'replies sort oldest first');
      expect(thread.state!.state, PdfReviewState.accepted);

      // every comment surfaces once, no state annotation among them
      expect(thread.comments.map((c) => c.name),
          containsAll(['root-1', 'rA', 'rB']));
      expect(thread.comments.any((c) => c.annotation.isStateAnnotation),
          isFalse);
    });

    test('of() finds the thread for any member', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'a reply', name: 'rX');
      });
      final reply = doc.page(0).annotations.firstWhere((a) => a.name == 'rX');
      final thread = PdfCommentThread.of(doc, 0, reply);
      expect(thread, isNotNull);
      expect(thread!.name, 'root-1');
    });
  });

  group('thread sync round-trip', () {
    test('a reply snapshot keeps the IRT-by-name and relinks on upsert', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'remote reply', author: 'Bob', name: 'reply-1');
      });
      final reply =
          doc.page(0).annotations.firstWhere((a) => a.name == 'reply-1');
      final snapshot =
          PdfAnnotationSnapshot.capture(doc, reply, keepName: true)!;
      expect(snapshot.inReplyTo, 'root-1');

      // through the wire
      final wire = jsonEncode(snapshot.toJson());
      final restored = PdfAnnotationSnapshot.fromJson(
          jsonDecode(wire) as Map<String, dynamic>);
      expect(restored.inReplyTo, 'root-1');

      // replay into another copy that already has the root
      final target = withRoot();
      final out = edited(target, (e) => e.upsertAnnotation(0, restored));
      final arrived =
          out.page(0).annotations.firstWhere((a) => a.name == 'reply-1');
      expect(arrived.inReplyTo, 'root-1',
          reason: 'IRT relinked to the parent in the receiving document');
      expect(arrived.contents, 'remote reply');
      expect(arrived.replyType, 'R');

      // and the thread reassembles
      final thread = PdfCommentThread.forPage(out, 0).single;
      expect(thread.replyCount, 1);
    });

    test('an orphan reply (parent absent) stays valid without /IRT', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'orphan', name: 'reply-1');
      });
      final reply =
          doc.page(0).annotations.firstWhere((a) => a.name == 'reply-1');
      final snapshot =
          PdfAnnotationSnapshot.capture(doc, reply, keepName: true)!;

      // a target WITHOUT the root
      final bare = PdfDocument.open(buildClassicPdf());
      final out = edited(bare, (e) => e.upsertAnnotation(0, snapshot));
      final arrived =
          out.page(0).annotations.firstWhere((a) => a.name == 'reply-1');
      expect(arrived.inReplyTo, isNull);
      expect(arrived.dict['IRT'], isNull);
      expect(arrived.contents, 'orphan');
    });

    test('replies and state changes show up in the change diff', () {
      final baseBytes = PdfEditor(PdfDocument.open(buildClassicPdf())).let((e) {
        e.addSquare(0, const PdfRect(100, 600, 200, 680), name: 'root-1');
        return e.save();
      });
      final repliedBytes = PdfEditor(PdfDocument.open(baseBytes)).let((e) {
        final root = e.document.page(0).annotations.single;
        e.replyToAnnotation(0, root, 'a reply', name: 'reply-1');
        return e.save();
      });
      final changes = pdfDiffAnnotations(
          PdfDocument.open(baseBytes), PdfDocument.open(repliedBytes),
          pages: [0]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, PdfAnnotationChangeKind.created);
      expect(changes.single.name, 'reply-1');
      expect(changes.single.snapshot!.inReplyTo, 'root-1');
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

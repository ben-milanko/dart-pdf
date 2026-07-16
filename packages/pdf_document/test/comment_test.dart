// Threaded comments (§12.5.6.x): replies linked by /IRT, review state via
// state replies, the read-only thread model, and round-tripping the IRT
// link through snapshots so threads sync.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
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
      // a reply carries no on-page appearance - it is thread content
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

  group('reply edge cases', () {
    test('a reply without a name gets a generated /NM and carries /Subj', () {
      final doc = edited(withRoot(), (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'no name given', subject: 'Re: review');
      });
      final reply =
          doc.page(0).annotations.firstWhere((a) => a.isReply);
      expect(reply.name, isNotNull, reason: 'a UUID was minted');
      expect(reply.subject, 'Re: review');
    });

    test('replying to a non-indirect annotation throws', () {
      final doc = PdfDocument.open(buildClassicPdf());
      // a dictionary that is not an object in the document
      final detached = PdfAnnotation.fromDict(
          doc,
          CosDictionary({
            'Type': const CosName('Annot'),
            'Subtype': const CosName('Square'),
            'Rect': CosArray(const [
              CosInteger(0),
              CosInteger(0),
              CosInteger(10),
              CosInteger(10)
            ]),
          }));
      final editor = PdfEditor(doc);
      expect(() => editor.replyToAnnotation(0, detached, 'hi'),
          throwsArgumentError);
      expect(() => editor.setReviewState(0, detached, PdfReviewState.accepted),
          throwsArgumentError);
    });
  });

  group('annotation thread getters on a plain annotation', () {
    test('a plain markup carries no reply/state/date fields', () {
      final doc = withRoot();
      final root = doc.page(0).annotations.single;
      expect(root.isReply, isFalse);
      expect(root.isStateAnnotation, isFalse);
      expect(root.inReplyTo, isNull);
      expect(root.replyType, isNull);
      expect(root.reviewState, isNull);
      expect(root.stateModel, isNull);
      expect(root.subject, isNull);
      // no /CreationDate or /M on a freshly added square
      expect(root.creationDate, isNull);
      expect(root.modificationDate, isNull);
    });

    test('dates parse from a +offset and reject malformed strings', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final annot = PdfAnnotation.fromDict(
          doc,
          CosDictionary({
            'Type': const CosName('Annot'),
            'Subtype': const CosName('Text'),
            'Rect': CosArray(const [
              CosInteger(0),
              CosInteger(0),
              CosInteger(10),
              CosInteger(10)
            ]),
            // a local-offset date the way Acrobat writes it
            'CreationDate': CosString.fromText("D:20260622133000+05'30'"),
            'M': CosString.fromText('not a date'),
          }));
      // +05:30 maps back to 08:00 UTC
      expect(annot.creationDate, DateTime.utc(2026, 6, 22, 8, 0, 0));
      expect(annot.modificationDate, isNull, reason: 'malformed → null');
    });

    test('pdfFormatDate and the date getters round-trip', () {
      final doc = edited(withRoot(), (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single, 'hi',
            createdAt: DateTime.utc(2026, 6, 22, 13, 5, 9));
      });
      final reply = doc.page(0).annotations.firstWhere((a) => a.isReply);
      expect(reply.creationDate, DateTime.utc(2026, 6, 22, 13, 5, 9));
      expect(reply.modificationDate, DateTime.utc(2026, 6, 22, 13, 5, 9));
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

    test('PdfComment exposes author/text and hasThread', () {
      var doc = withRoot();
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'a reply', author: 'Bob', name: 'rX');
      });
      final thread = PdfCommentThread.forPage(doc, 0).single;
      expect(thread.root.hasThread, isTrue);
      expect(thread.root.author, 'Ann');
      final reply = thread.root.replies.single;
      expect(reply.author, 'Bob');
      expect(reply.text, 'a reply');
      expect(reply.hasThread, isFalse);
    });

    test('thread state picks the newest entry across comments', () {
      var doc = withRoot();
      // a reply, an older state on the root, a newer state on the reply
      doc = edited(doc, (e) {
        e.replyToAnnotation(0, e.document.page(0).annotations.single,
            'a reply', name: 'rX', createdAt: DateTime.utc(2030, 1, 1));
      });
      doc = edited(doc, (e) {
        final root = e.document.page(0).annotations
            .firstWhere((a) => a.name == 'root-1');
        e.setReviewState(0, root, PdfReviewState.rejected,
            author: 'Ann', at: DateTime.utc(2030, 1, 2));
      });
      doc = edited(doc, (e) {
        final reply =
            e.document.page(0).annotations.firstWhere((a) => a.name == 'rX');
        e.setReviewState(0, reply, PdfReviewState.accepted,
            author: 'Bob', at: DateTime.utc(2030, 1, 5));
      });
      final thread = PdfCommentThread.forPage(doc, 0).single;
      expect(thread.state!.state, PdfReviewState.accepted,
          reason: 'the later state on the reply wins');
      expect(thread.state!.author, 'Bob');
    });

    test('rootsWithThreadsOnly drops bare roots', () {
      // a root with no replies/state
      final doc = withRoot();
      expect(PdfCommentThread.forPage(doc, 0), hasLength(1));
      expect(
          PdfCommentThread.forPage(doc, 0, rootsWithThreadsOnly: true), isEmpty);
    });

    test('lenient parsing: orphan state and a dateless reply', () {
      final doc = PdfDocument.open(_threadEdgesPdf());
      final thread = PdfCommentThread.forPage(doc, 0).single;
      expect(thread.name, 'root-1');
      expect(thread.replyCount, 3);
      // the dateless replies sort ahead of the dated one (null date first),
      // keeping their insertion order
      expect(thread.root.replies.map((c) => c.name),
          ['rep-none-a', 'rep-none-b', 'rep-dated']);
      // the orphan state's /IRT dangled, so it attached to the root and
      // still surfaces as the thread's verdict
      expect(thread.isResolved, isTrue);
      expect(thread.state!.state, PdfReviewState.completed);
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

/// A hand-written PDF whose page carries a root markup, two replies (one
/// dated, one dateless), and an *orphan* state annotation whose /IRT
/// dangles - the lenient-parsing edges of [PdfCommentThread] that the
/// authoring API never produces. Object offsets are computed so the xref
/// is correct.
Uint8List _threadEdgesPdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Annots [4 0 R 5 0 R 6 0 R 7 0 R 8 0 R] >>',
    // 4: root markup
    '<< /Type /Annot /Subtype /Square /Rect [10 10 50 50] /NM (root-1) '
        '/Contents (please review) >>',
    // 5: a dated reply
    '<< /Type /Annot /Subtype /Text /Rect [10 10 50 50] /IRT 4 0 R /RT /R '
        '/NM (rep-dated) /Contents (dated) /CreationDate (D:20300102000000Z00\'00\') >>',
    // 6, 7: two dateless replies (so the sort comparator hits the null-date
    // branch on both sides)
    '<< /Type /Annot /Subtype /Text /Rect [10 10 50 50] /IRT 4 0 R /RT /R '
        '/NM (rep-none-a) /Contents (undated a) >>',
    '<< /Type /Annot /Subtype /Text /Rect [10 10 50 50] /IRT 4 0 R /RT /R '
        '/NM (rep-none-b) /Contents (undated b) >>',
    // 8: an orphan state annotation: /IRT dangles, so it falls back to the
    // thread root (/State and /StateModel are text strings per §12.5.6.2)
    '<< /Type /Annot /Subtype /Text /Rect [10 10 50 50] /IRT 99 0 R /RT /R '
        '/NM (st-orphan) /Contents () /State (Completed) /StateModel (Review) >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

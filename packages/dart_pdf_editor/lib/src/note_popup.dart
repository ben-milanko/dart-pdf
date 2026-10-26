import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';

import 'design/viewer_tokens.dart';
import 'l10n/pdf_l10n.dart';
import 'theme.dart';

/// Whether [annotation] is a sticky note whose text the viewer should
/// surface in a [PdfNotePopupCard]: a /Text annotation that is a thread's
/// root, not a reply or a review-state record (neither of which paints an
/// icon on the page).
bool pdfIsNotePopupTarget(PdfAnnotation annotation) =>
    annotation.subtype == 'Text' &&
    !annotation.isReply &&
    !annotation.isStateAnnotation;

/// A floating, read-only card showing a sticky note's text - author, date,
/// the note body and any replies - beside its icon on the page.
///
/// A note's icon carries none of its text, so without this the only place
/// to read it is the properties or annotation panel. [PdfViewer] shows the
/// card while the mouse rests on a note and keeps it up while a single note
/// is selected (which is how touch reaches it); see
/// [PdfViewer.showNotePopups].
class PdfNotePopupCard extends StatelessWidget {
  const PdfNotePopupCard({
    super.key,
    required this.note,
    this.replies = const [],
    this.maxWidth = 300,
    this.maxHeight = 260,
  });

  /// The note annotation itself.
  final PdfAnnotation note;

  /// The note's replies with their depth below the note (1 = a direct
  /// reply), in thread order.
  final List<(PdfComment, int)> replies;

  /// Bounds of the card; a long note scrolls inside them.
  final double maxWidth;
  final double maxHeight;

  /// The replies under [note] in [document]'s page [pageIndex], with their
  /// depth, in thread order (empty when it has none).
  static List<(PdfComment, int)> repliesOf(
      PdfDocument document, int pageIndex, PdfAnnotation note) {
    final thread = PdfCommentThread.of(document, pageIndex, note);
    if (thread == null) return const [];
    final out = <(PdfComment, int)>[];
    void walk(PdfComment comment, int depth) {
      for (final reply in comment.replies) {
        out.add((reply, depth));
        walk(reply, depth + 1);
      }
    }

    walk(thread.root, 1);
    return out;
  }

  static String _formatTime(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  static String _header(String? author, DateTime? at) => [
        if (author != null && author.isNotEmpty) author,
        if (_formatTime(at) case final time when time.isNotEmpty) time,
      ].join(' • ');

  @override
  Widget build(BuildContext context) {
    final viewerTheme = PdfViewerTheme.of(context);
    final background = viewerTheme.chip;
    final foreground = viewerTheme.chipForeground;
    final muted = foreground.withValues(alpha: 0.7);
    final rule = foreground.withValues(alpha: 0.25);
    final rgb = note.color;
    final accent = rgb == null ? foreground : Color(0xFF000000 | rgb);
    final header =
        _header(note.author, note.modificationDate ?? note.creationDate);
    final contents = note.contents ?? '';
    final base = DefaultTextStyle.of(context)
        .style
        .copyWith(color: foreground, fontSize: 14, height: 1.35);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: DecoratedBox(
        key: const ValueKey('pdf-note-popup'),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 4)),
            ),
            child: DefaultTextStyle(
              style: base,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      header.isEmpty ? pdfL10n(context).annotText : header,
                      style: base.copyWith(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contents.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(contents,
                          key: const ValueKey('pdf-note-popup-text')),
                    ],
                    for (final (reply, depth) in replies) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.only(left: (depth - 1) * 12.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            border:
                                Border(left: BorderSide(color: rule, width: 2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_header(reply.author, reply.createdAt)
                                  case final h when h.isNotEmpty)
                                Text(h,
                                    style: base.copyWith(
                                        fontSize: 11, color: muted)),
                              Text(reply.text,
                                  style: base.copyWith(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Places a [PdfNotePopupCard] beside [anchor] (the note icon, in the
/// layer's coordinates): to its right, flipped to its left when that would
/// run off the layer, top-aligned with it and clamped inside the layer.
class PdfNotePopupLayout extends SingleChildLayoutDelegate {
  const PdfNotePopupLayout(this.anchor, {this.gap = 8, this.margin = 8});

  final Rect anchor;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.right + gap;
    if (x + childSize.width > size.width - margin) {
      final left = anchor.left - gap - childSize.width;
      x = left >= margin ? left : size.width - margin - childSize.width;
    }
    final maxY = size.height - margin - childSize.height;
    final y = anchor.top.clamp(margin, maxY < margin ? margin : maxY);
    return Offset(x < margin ? margin : x, y);
  }

  @override
  bool shouldRelayout(PdfNotePopupLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.gap != gap ||
      oldDelegate.margin != margin;
}

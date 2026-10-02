/// An iOS-style presenter for the editor: `PdfCupertinoPresenter`.
///
/// ```dart
/// import 'package:dart_pdf_editor/cupertino.dart';
///
/// CupertinoApp(
///   home: CupertinoPageScaffold(
///     child: PdfEditorView(
///       bytes: bytes,
///       presenter: const PdfCupertinoPresenter(),
///     ),
///   ),
/// )
/// ```
///
/// A separate library so a Material host does not compile it: nothing in
/// `package:dart_pdf_editor/dart_pdf_editor.dart` imports it. It builds on
/// `package:cupertino_ui` (already a dependency of the editor) and draws no
/// `CupertinoIcons`, so it needs no `cupertino_icons` package; its few
/// glyphs are the Material Icons the stock chrome already bundles.
library;

export 'src/cupertino/cupertino_presenter.dart'
    show PdfCupertinoPresenter, pdfCupertinoTextContextMenu;

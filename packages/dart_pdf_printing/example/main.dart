import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_printing/dart_pdf_printing.dart';
import 'package:flutter/material.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

void main() => runApp(const PrintExample());

class PrintExample extends StatelessWidget {
  const PrintExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        localizationsDelegates: const [
          ...DartPdfPrintingLocalizations.localizationsDelegates,
          DartPdfEditorLocalizations.delegate,
        ],
        supportedLocales: DartPdfPrintingLocalizations.supportedLocales,
        home: const _DocumentScreen(),
      );
}

class _DocumentScreen extends StatefulWidget {
  const _DocumentScreen();
  @override
  State<_DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<_DocumentScreen> {
  late final editor = PdfEditingController(_samplePdf());
  final viewer = PdfViewerController();
  bool printing = false;

  Future<void> _print() async {
    setState(() => printing = true);
    // Commit edits before the preview takes its independent snapshot.
    FocusManager.instance.primaryFocus?.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    editor.finishInk();
    try {
      await printPdfWithPreview(context,
          document: editor.document,
          title: 'Example.pdf',
          currentPage: viewer.currentPage,
          selectedPages: editor.selectedPages);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not print: $error')));
      }
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  void dispose() {
    editor.dispose();
    viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Optional printing'), actions: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print),
            onPressed: printing ? null : _print,
          ),
        ]),
        body: PdfEditorView(controller: editor, viewerController: viewer),
      );
}

Uint8List _samplePdf() {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final parent = builder.add(pages);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': parent,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(612),
      const CosInteger(792),
    ]),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  final bytes = builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': parent,
  })));
  final editor = PdfEditor(PdfDocument.open(bytes));
  editor.stampPage(0, (stamp) {
    stamp.text('Add printing to your app', x: 72, y: 700, size: 24);
    stamp.text('Edit this page, then choose Print to preview the result.',
        x: 72, y: 660, size: 12);
  });
  return editor.save();
}

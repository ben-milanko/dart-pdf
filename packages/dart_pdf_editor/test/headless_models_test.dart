// The headless model types moved out of their Material dialog files into
// lib/src/editing/models/ (see tool/check_design_imports.dart). These pin
// what the move must not change for hosts.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dock panel icons are the Material glyphs they always were', () {
    // Plain const IconData now, so the enum stays on the widgets layer; they
    // must still compare equal to the Icons constants hosts may match on.
    expect(PdfDockablePanel.thumbnails.icon, Icons.grid_view);
    expect(PdfDockablePanel.search.icon, Icons.manage_search);
    expect(PdfDockablePanel.bookmarks.icon, Icons.bookmarks_outlined);
    expect(PdfDockablePanel.annotations.icon, Icons.list_alt);
    expect(PdfDockablePanel.properties.icon, Icons.tune);
    expect(PdfDockablePanel.annotationLibrary.icon,
        Icons.collections_bookmark_outlined);
  });

  testWidgets('dock panel labels still read the editor localizations',
      (tester) async {
    late String label;
    await tester.pumpWidget(Builder(builder: (context) {
      label = PdfDockablePanel.thumbnails.label(context);
      return const SizedBox();
    }));
    expect(label, 'Pages');
  });

  test('moved models keep their public names and behaviour', () {
    const scale = PdfMeasurementScale(unitsPerPoint: 1 / 72, unitLabel: 'in');
    expect(PdfMeasurementScale.decode(scale.encode()), scale);
    expect(scale.ratioLabel, '1 in = 1 in');
    expect(PdfStampDateFormat.iso.format(DateTime(2026, 3, 4)), '2026-03-04');
    expect(PdfStampTimeFormat.twelveHour.format(DateTime(2026, 1, 1, 13, 5)),
        '1:05 PM');
    const stamp = PdfCustomStamp(text: 'OK', color: 0x00AA00);
    expect(PdfCustomStamp.decode(stamp.encode()), stamp);
    expect(PdfColorFormat.cmyk.label, 'CMYK');
    expect(PdfPanelDock.left.gripSide, PdfSidebarSide.left);
    const event = PdfTrackpadSignatureEvent(PdfTrackpadSignaturePhase.up);
    expect(event.phase, PdfTrackpadSignaturePhase.up);
  });
}

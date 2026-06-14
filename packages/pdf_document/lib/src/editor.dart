import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'content_elements.dart';
import 'content_writer.dart';
import 'document.dart';
import 'form.dart';
import 'image.dart';
import 'measure.dart';
import 'page.dart';
import 'rect.dart';

part 'annotation_clipboard.dart';
part 'annotation_editor.dart';
part 'annotation_sync.dart';
part 'content_editor.dart';
part 'redaction.dart';
part 'form_admin.dart';
part 'form_editor.dart';
part 'ocr_editor.dart';
part 'page_editor.dart';
part 'signature_editor.dart';
part 'vector_snapshot.dart';

/// High-level editing session over a [PdfDocument].
///
/// Edits accumulate and [save] appends them as one incremental update, so
/// the original file content — including any digital signatures — survives.
class PdfEditor {
  PdfEditor(this.document) : _updater = CosIncrementalUpdater(document.cos);

  final PdfDocument document;
  final CosIncrementalUpdater _updater;

  /// Pages whose original content this session already wrapped in q/Q.
  final Set<CosDictionary> _wrappedPages = {};

  /// The document-default measurement scale, set by
  /// [PdfAnnotationEditing.setMeasurementScale]; [PdfAnnotationEditing.addMeasurement]
  /// uses it when no per-annotation override is given.
  PdfMeasure? _defaultMeasure;

  bool get hasChanges => _updater.hasChanges;

  /// Updates document information entries. Null leaves an entry unchanged.
  void setInfo({
    String? title,
    String? author,
    String? subject,
    String? keywords,
    String? creator,
    String? producer,
  }) {
    final cos = document.cos;
    final existingRef = cos.trailer['Info'];
    final existing = cos.resolve(existingRef);
    final dict = existing is CosDictionary
        ? CosDictionary({...existing.entries})
        : CosDictionary();

    void put(String key, String? value) {
      if (value != null) dict[key] = CosString.fromText(value);
    }

    put('Title', title);
    put('Author', author);
    put('Subject', subject);
    put('Keywords', keywords);
    put('Creator', creator);
    put('Producer', producer);

    if (existing is CosDictionary && existingRef is CosReference) {
      _updater.replaceObject(existingRef.objectNumber, dict);
    } else {
      _updater.setTrailerEntry('Info', _updater.addObject(dict));
    }
  }

  /// Adds [degrees] (a multiple of 90) to the page's display rotation.
  void rotatePage(int index, int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(
          degrees, 'degrees', 'must be a multiple of 90');
    }
    final page = document.page(index);
    final next = (page.rotation + degrees) % 360;
    page.dict['Rotate'] = CosInteger(next < 0 ? next + 360 : next);
    _updater.markChanged(page.dict);
  }

  /// The full bytes of the edited file (original + incremental update).
  Uint8List save() => _updater.save();
}

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

void main() {
  final dictionary = parseDictionary('h\ne\nl\no\n');
  final decoder = CtcDecoder(dictionary);

  // Vocabulary index 0 is blank. The remaining indices map to the dictionary:
  // h=1, e=2, l=3, o=4, space=5.
  final predictions = Float32List.fromList([
    0.01, 0.90, 0.03, 0.03, 0.02, 0.01, // h
    0.01, 0.02, 0.91, 0.03, 0.02, 0.01, // e
    0.01, 0.02, 0.02, 0.91, 0.03, 0.01, // l
    0.01, 0.02, 0.02, 0.90, 0.04, 0.01, // repeated l collapses
    0.92, 0.02, 0.02, 0.02, 0.01, 0.01, // blank
    0.01, 0.02, 0.02, 0.90, 0.04, 0.01, // l after blank is kept
    0.01, 0.02, 0.02, 0.03, 0.91, 0.01, // o
  ]);

  final result = decoder.decode(predictions, 7, 6);
  print('${result.text} (${result.confidence.toStringAsFixed(2)})');
}

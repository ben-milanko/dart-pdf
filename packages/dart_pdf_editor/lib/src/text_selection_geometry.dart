import 'dart:math' as math;

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

typedef _IndexedRect<T> = ({int index, PdfRect rect, T value});

class _LineBand<T> {
  _LineBand(_IndexedRect<T> first) : members = [first];

  final List<_IndexedRect<T>> members;
}

bool _validRect(PdfRect rect) =>
    rect.left.isFinite &&
    rect.bottom.isFinite &&
    rect.right.isFinite &&
    rect.top.isFinite &&
    rect.width > 0 &&
    rect.height > 0;

bool _sameLine(PdfRect a, PdfRect b) {
  final smaller = math.min(a.height, b.height);
  final larger = math.max(a.height, b.height);
  final overlap = math.max(
    0.0,
    math.min(a.top, b.top) - math.max(a.bottom, b.bottom),
  );
  final centerDelta = ((a.top + a.bottom) / 2 - (b.top + b.bottom) / 2).abs();
  return overlap >= smaller * 0.5 &&
      centerDelta <= smaller * 0.35 &&
      larger <= smaller * 2;
}

int _physicalOrder<T>(_IndexedRect<T> a, _IndexedRect<T> b) {
  final aCenter = (a.rect.top + a.rect.bottom) / 2;
  final bCenter = (b.rect.top + b.rect.bottom) / 2;
  var result = bCenter.compareTo(aCenter);
  if (result != 0) return result;
  result = a.rect.left.compareTo(b.rect.left);
  if (result != 0) return result;
  result = a.rect.right.compareTo(b.rect.right);
  if (result != 0) return result;
  result = a.rect.bottom.compareTo(b.rect.bottom);
  if (result != 0) return result;
  return a.index.compareTo(b.index);
}

List<_LineBand<T>> _lineBands<T>(
  List<T> input,
  PdfRect Function(T value) bounds,
) {
  final valid = <_IndexedRect<T>>[
    for (var i = 0; i < input.length; i++)
      if (_validRect(bounds(input[i])))
        (index: i, rect: bounds(input[i]), value: input[i]),
  ]..sort(_physicalOrder);
  final bands = <_LineBand<T>>[];
  for (final candidate in valid) {
    _LineBand<T>? eligible;
    for (final band in bands) {
      if (band.members.every(
        (member) => _sameLine(member.rect, candidate.rect),
      )) {
        eligible = band;
        break;
      }
    }
    if (eligible == null) {
      bands.add(_LineBand<T>(candidate));
    } else {
      eligible.members.add(candidate);
    }
  }
  bands.sort((a, b) => _earliest(a).compareTo(_earliest(b)));
  return bands;
}

int _earliest<T>(_LineBand<T> band) =>
    band.members.map((member) => member.index).reduce(math.min);

PdfRect _union<T>(_LineBand<T> band) {
  var left = band.members.first.rect.left;
  var bottom = band.members.first.rect.bottom;
  var right = band.members.first.rect.right;
  var top = band.members.first.rect.top;
  for (final member in band.members.skip(1)) {
    left = math.min(left, member.rect.left);
    bottom = math.min(bottom, member.rect.bottom);
    right = math.max(right, member.rect.right);
    top = math.max(top, member.rect.top);
  }
  return PdfRect(left, bottom, right, top);
}

/// Merges every fragment of one continuous selection into one rectangle per
/// near-horizontal visual line, including all horizontal space between runs.
List<PdfRect> normalizeTextSelectionRects(List<PdfRect> rects) =>
    [for (final band in _lineBands(rects, (rect) => rect)) _union(band)];

/// The live-selection counterpart of [normalizeTextSelectionRects]. A lone
/// quad stays byte-for-byte geometric, preserving rotated and vertical text.
List<PdfTextQuad> normalizeTextSelectionQuads(List<PdfTextQuad> quads) {
  final result = <PdfTextQuad>[];
  for (final band in _lineBands(quads, (quad) => quad.bounds)) {
    if (band.members.length == 1) {
      result.add(band.members.single.value);
      continue;
    }
    final rect = _union(band);
    result.add(PdfTextQuad([
      (rect.left, rect.bottom),
      (rect.right, rect.bottom),
      (rect.right, rect.top),
      (rect.left, rect.top),
    ]));
  }
  return result;
}

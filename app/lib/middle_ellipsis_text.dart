import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsConfiguration;

/// A single-line text label that removes characters from its centre when it
/// does not fit.
///
/// File names benefit from middle truncation because it keeps both the
/// identifying start of the name and its extension visible. Flutter's stock
/// [TextOverflow.ellipsis] only truncates the end.
class MiddleEllipsisText extends LeafRenderObjectWidget {
  const MiddleEllipsisText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  _MiddleEllipsisConfiguration _configuration(BuildContext context) =>
      _MiddleEllipsisConfiguration(
        data: data,
        style: DefaultTextStyle.of(context).style.merge(style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        textAlign: textAlign ?? TextAlign.start,
      );

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMiddleEllipsisText(_configuration(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderMiddleEllipsisText).configuration =
        _configuration(context);
  }
}

@immutable
class _MiddleEllipsisConfiguration {
  const _MiddleEllipsisConfiguration({
    required this.data,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.textAlign,
  });

  final String data;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final TextAlign textAlign;

  @override
  bool operator ==(Object other) =>
      other is _MiddleEllipsisConfiguration &&
      data == other.data &&
      style == other.style &&
      textDirection == other.textDirection &&
      textScaler == other.textScaler &&
      locale == other.locale &&
      textAlign == other.textAlign;

  @override
  int get hashCode => Object.hash(
        data,
        style,
        textDirection,
        textScaler,
        locale,
        textAlign,
      );
}

class _RenderMiddleEllipsisText extends RenderBox {
  _RenderMiddleEllipsisText(this._configuration);

  _MiddleEllipsisConfiguration _configuration;
  TextPainter? _painter;
  String _displayedText = '';

  set configuration(_MiddleEllipsisConfiguration value) {
    if (value == _configuration) return;
    final semanticsChanged = value.data != _configuration.data ||
        value.textDirection != _configuration.textDirection;
    _configuration = value;
    markNeedsLayout();
    if (semanticsChanged) markNeedsSemanticsUpdate();
  }

  // Read dynamically by the focused widget test without making the render
  // implementation part of the app's public API.
  String get debugDisplayedText => _displayedText;

  TextPainter _textPainter(String text) => TextPainter(
        text: TextSpan(text: text, style: _configuration.style),
        textDirection: _configuration.textDirection,
        textScaler: _configuration.textScaler,
        locale: _configuration.locale,
        textAlign: _configuration.textAlign,
        maxLines: 1,
      );

  double _naturalWidth(String text) {
    final painter = _textPainter(text)..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  void performLayout() {
    final natural = _textPainter(_configuration.data)..layout();
    final naturalSize = natural.size;
    final availableWidth = constraints.constrainWidth(naturalSize.width);
    _displayedText = naturalSize.width <= availableWidth
        ? _configuration.data
        : _middleEllipsize(
            _configuration.data,
            (candidate) => _naturalWidth(candidate) <= availableWidth,
          );
    natural.dispose();

    _painter?.dispose();
    _painter = _textPainter(_displayedText)
      ..layout(minWidth: availableWidth, maxWidth: availableWidth);
    size = constraints.constrain(Size(naturalSize.width, naturalSize.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter!.paint(context.canvas, offset);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _naturalWidth(_configuration.data);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _naturalWidth(_configuration.data);

  @override
  double computeMinIntrinsicHeight(double width) {
    final painter = _textPainter(_configuration.data)..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter!.computeDistanceToActualBaseline(baseline);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _configuration.data
      ..textDirection = _configuration.textDirection;
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}

String _middleEllipsize(
  String value,
  bool Function(String candidate) fits,
) {
  if (fits(value)) return value;
  const ellipsis = '…';
  if (!fits(ellipsis)) return '';

  final characters = value.runes.toList(growable: false);
  final lastDot = value.lastIndexOf('.');
  final extensionLength = lastDot > 0 && lastDot < value.length - 1
      ? value.substring(lastDot).runes.length
      : 0;
  // For file names, keep the complete extension whenever it can fit. This is
  // the useful part of Finder-style middle truncation: `drawing…ing.pdf` is
  // still recognisable as a PDF, unlike `drawing…pdf` or an end ellipsis.
  final minimumSuffix = extensionLength > 0 &&
          fits(ellipsis +
              String.fromCharCodes(
                characters.skip(characters.length - extensionLength),
              ))
      ? extensionLength
      : 0;
  var low = 0;
  var high = characters.length;
  var best = ellipsis;
  while (low <= high) {
    final kept = (low + high) ~/ 2;
    // Keep one extra character at the end when the split is uneven: for file
    // names this makes extensions slightly more resilient at very small widths.
    final suffixCount = math.min(
      kept,
      math.max(minimumSuffix, (kept + 1) ~/ 2),
    );
    final prefixCount = kept - suffixCount;
    final candidate = String.fromCharCodes(characters.take(prefixCount)) +
        ellipsis +
        String.fromCharCodes(characters.skip(characters.length - suffixCount));
    if (fits(candidate)) {
      best = candidate;
      low = kept + 1;
    } else {
      high = kept - 1;
    }
  }
  return best;
}

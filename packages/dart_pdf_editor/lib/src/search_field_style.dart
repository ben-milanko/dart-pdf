import 'package:flutter/material.dart';

/// The corner radius shared by search inputs across the viewer and app: a
/// stadium. A deliberately oversized radius keeps the ends fully rounded at
/// every supported field height.
///
/// A widgets-layer value, so any design system's field can use it; with
/// Material, `OutlineInputBorder(borderRadius: pdfSearchFieldBorderRadius)`.
const pdfSearchFieldBorderRadius = BorderRadius.all(Radius.circular(999));

/// The shared stadium border for search inputs across the viewer and app.
///
/// A deliberately oversized radius keeps the ends fully rounded at every
/// supported field height.
@Deprecated('Use OutlineInputBorder(borderRadius: pdfSearchFieldBorderRadius), '
    'or pdfSearchFieldBorderRadius with your own field border. Removed in '
    '7.0.0.')
const pdfSearchInputBorder = OutlineInputBorder(
  borderRadius: pdfSearchFieldBorderRadius,
);

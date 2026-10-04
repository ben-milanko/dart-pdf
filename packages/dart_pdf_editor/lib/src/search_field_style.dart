import 'package:flutter/painting.dart';

/// The corner radius shared by search inputs across the viewer and app: a
/// stadium. A deliberately oversized radius keeps the ends fully rounded at
/// every supported field height.
///
/// A widgets-layer value, so any design system's field can use it; with
/// Material, `OutlineInputBorder(borderRadius: pdfSearchFieldBorderRadius)`.
const pdfSearchFieldBorderRadius = BorderRadius.all(Radius.circular(999));

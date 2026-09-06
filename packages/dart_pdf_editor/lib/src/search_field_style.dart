import 'package:flutter/material.dart';

/// The shared stadium border for search inputs across the viewer and app.
///
/// A deliberately oversized radius keeps the ends fully rounded at every
/// supported field height.
const pdfSearchInputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(999)),
);

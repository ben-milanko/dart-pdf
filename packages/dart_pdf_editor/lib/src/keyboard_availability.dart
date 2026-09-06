import 'package:flutter/widgets.dart';

/// Whether a physical keyboard is available for shortcut hints and settings.
///
/// Place this above the Navigator (for example in MaterialApp.builder) so
/// menus and dialogs update too. Hosts supply their platform's connection
/// signal; without this scope, the editor retains its usual shortcut hints.
/// This affects presentation only, never the shortcut bindings themselves.
class PdfKeyboardAvailability extends InheritedWidget {
  const PdfKeyboardAvailability({
    super.key,
    required this.connected,
    required super.child,
  });

  final bool connected;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PdfKeyboardAvailability>()
          ?.connected ??
      true;

  @override
  bool updateShouldNotify(PdfKeyboardAvailability oldWidget) =>
      connected != oldWidget.connected;
}

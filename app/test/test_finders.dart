import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_tabs/dart_pdf_tabs.dart' show MiddleEllipsisText;
export 'package:dart_pdf_tabs/dart_pdf_tabs.dart' show MiddleEllipsisText;

/// Finds the filename widget by its complete source value, regardless of the
/// centre-ellipsized text currently painted for its layout width.
Finder findMiddleEllipsisText(String value) => find.byWidgetPredicate(
      (widget) => widget is MiddleEllipsisText && widget.data == value,
    );

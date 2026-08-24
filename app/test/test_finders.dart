import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/middle_ellipsis_text.dart';
export 'package:dart_pdf_editor_app/middle_ellipsis_text.dart'
    show MiddleEllipsisText;

/// Finds the filename widget by its complete source value, regardless of the
/// centre-ellipsized text currently painted for its layout width.
Finder findMiddleEllipsisText(String value) => find.byWidgetPredicate(
      (widget) => widget is MiddleEllipsisText && widget.data == value,
    );

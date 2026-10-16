import 'package:flutter/widgets.dart';

/// Dismisses the on-screen keyboard when the user touches outside the
/// focused text field.
///
/// Flutter's default only drops focus on a tap outside for desktop, web and
/// non-touch pointers; on a native phone the field keeps focus, so a
/// keyboard without a return key (iOS's number and decimal pads) can never
/// be closed. Place this above the app's [Navigator] (e.g. in
/// `MaterialApp.builder`) so dialogs and sheets are covered too. Fields
/// with their own `onTapOutside` are unaffected.
class PdfDismissKeyboardOnTapOutside extends StatelessWidget {
  const PdfDismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          EditableTextTapOutsideIntent:
              CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
        },
        child: child,
      );
}

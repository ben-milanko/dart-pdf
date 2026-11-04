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
///
/// Also normalizes a negative bottom keyboard inset before it reaches the
/// scaffold. The iOS keyboard spring can transiently undershoot zero; the
/// engine derives safe-area padding by subtracting that inset, turning the
/// undershoot into extra bottom padding. Only invalid negative values are
/// corrected; a visible keyboard retains its real inset and resizes normally.
class PdfDismissKeyboardOnTapOutside extends StatelessWidget {
  const PdfDismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final actions = Actions(
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
    if (media == null) return actions;
    // Keep the wrapper mounted even for valid metrics, so an inset change
    // does not recreate the navigator or drop a text field's focus.
    return MediaQuery(
      data: media.viewInsets.bottom < 0
          ? media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: 0),
              padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
            )
          : media,
      child: actions,
    );
  }
}

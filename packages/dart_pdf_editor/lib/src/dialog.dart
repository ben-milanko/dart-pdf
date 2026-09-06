import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Marks the primary button in a [showPdfDialog] as its Enter action.
///
/// Enter and numpad Enter invoke the button's current [ButtonStyleButton.onPressed]
/// callback, including its validation. A disabled button cannot be submitted.
/// Shift+Enter remains available for newlines in multiline text fields.
/// Only one submit button should be mounted in each dialog at a time.
class PdfDialogSubmit extends StatefulWidget {
  const PdfDialogSubmit({super.key, required this.child});

  final ButtonStyleButton child;

  @override
  State<PdfDialogSubmit> createState() => _PdfDialogSubmitState();
}

class _PdfDialogSubmitState extends State<PdfDialogSubmit> {
  _PdfDialogKeyboardScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach();
  }

  void _attach() {
    final scope =
        context.findAncestorStateOfType<_PdfDialogKeyboardScopeState>();
    if (identical(scope, _scope)) return;
    _detach();
    _scope = scope;
    assert(scope == null || scope.submit == null,
        'A dialog can only have one PdfDialogSubmit button.');
    scope?.submit = this;
  }

  void _detach() {
    if (identical(_scope?.submit, this)) _scope?.submit = null;
    _scope = null;
  }

  @override
  void activate() {
    super.activate();
    _attach();
  }

  @override
  void deactivate() {
    _detach();
    super.deactivate();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PdfDialogKeyboardScope extends StatefulWidget {
  const _PdfDialogKeyboardScope({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_PdfDialogKeyboardScope> createState() =>
      _PdfDialogKeyboardScopeState();
}

class _PdfDialogKeyboardScopeState extends State<_PdfDialogKeyboardScope> {
  // Let the dialog route retain control of Tab traversal at its edges.
  final _focus =
      FocusScopeNode(traversalEdgeBehavior: TraversalEdgeBehavior.parentScope);
  _PdfDialogSubmitState? submit;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (submit == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    // Focused buttons (including Cancel) keep their normal activation. A
    // segmented selector is a form value, so Enter still submits from there.
    var focusedButton = false;
    focusedContext?.visitAncestorElements((element) {
      if (element.widget is SegmentedButton) {
        focusedButton = false;
        return false;
      }
      if (element.widget is ButtonStyleButton) focusedButton = true;
      return element.widget is! AlertDialog;
    });
    if (focusedButton) return KeyEventResult.ignored;
    final field = focusedContext?.findAncestorWidgetOfExactType<EditableText>();
    final composing = field?.controller.value.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      // Let the input method confirm its candidate before submitting the form.
      return KeyEventResult.skipRemainingHandlers;
    }
    if (event is KeyDownEvent) submit?.widget.child.onPressed?.call();
    // Consume repeats as well, so holding Enter cannot submit a second time.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
        node: _focus,
        autofocus: ModalRoute.of(context)?.requestFocus ?? true,
        onKeyEvent: _onKeyEvent,
        child: Builder(builder: widget.builder),
      );
}

/// Shows a Material dialog inside the current Flutter view.
///
/// Flutter's experimental desktop windowing feature promotes [showDialog]
/// calls to native dialog windows. Those windows are not yet reliable enough
/// for editor workflows: on macOS they can be registered as an off-screen
/// sheet that blocks its parent without accepting input. DartPDF still uses
/// native [RegularWindow]s for real multi-window editing, while its modal
/// prompts stay attached to the navigator that opened them.
/// Wrap the primary action button in [PdfDialogSubmit] to submit with Enter.
Future<T?> showPdfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  assert(debugCheckHasMaterialLocalizations(context));

  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );

  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: (context) => _PdfDialogKeyboardScope(builder: builder),
      barrierColor: barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      themes: themes,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/services.dart';

import 'design/editor_presenter.dart';
import 'design/material_host.dart';
import 'l10n/pdf_l10n.dart';

/// Marks the primary action in a [showPdfDialog] as its Enter action.
///
/// ```dart
/// PdfDialogSubmit.action(
///   onSubmit: canSave ? save : null,
///   child: FilledButton(onPressed: canSave ? save : null, child: label),
/// )
/// ```
///
/// Enter and numpad Enter call [onSubmit] - pass the same callback the
/// button runs, validation included; null means the action is disabled and
/// Enter does nothing. [child] is any widget, from any design system: the
/// dialog finds the submit action through this marker, not through the
/// button's type. Shift+Enter remains available for newlines in multiline
/// text fields. Only one submit action should be mounted in each dialog at a
/// time.
///
/// While another control has keyboard focus, that control keeps Enter: a
/// focused button (Cancel, say - anything with button semantics) activates
/// itself. A value control - a segmented selector, a checkbox, radio or
/// switch, a dropdown or menu button (selected, checked, toggled, expanded or
/// mutually-exclusive-group semantics) - is a form field, so Enter still
/// submits from there.
class PdfDialogSubmit extends StatefulWidget {
  /// Marks [child], a Material button, as the submit action; Enter calls its
  /// current `onPressed`.
  @Deprecated('Use PdfDialogSubmit.action(onSubmit: ..., child: ...), which '
      'takes any widget. The ButtonStyleButton form is removed in 6.0.0.')
  const PdfDialogSubmit({super.key, required ButtonStyleButton this.child})
      : onSubmit = null,
        _submitsChild = true;

  /// Marks [child] as the submit action; Enter calls [onSubmit] (nothing,
  /// while it is null).
  const PdfDialogSubmit.action({
    super.key,
    required this.onSubmit,
    required this.child,
  }) : _submitsChild = false;

  /// The submit control as it is drawn.
  final Widget child;

  /// What Enter runs; null disables Enter submission. (For the deprecated
  /// default constructor, Enter runs the button's own `onPressed`.)
  final VoidCallback? onSubmit;

  final bool _submitsChild;

  VoidCallback? get _effectiveOnSubmit =>
      _submitsChild ? (child as ButtonStyleButton).onPressed : onSubmit;

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
    // value control (a segmented selector, a dropdown) is a form field, so
    // Enter still submits from there. Both are read from semantics roles, not
    // widget types, so controls from any design system classify the same.
    var focusedButton = false;
    final scope = context as Element;
    focusedContext?.visitAncestorElements((element) {
      if (identical(element, scope)) return false;
      final widget = element.widget;
      if (widget is PdfDialogSubmit) {
        // The submit control itself: Enter is its action either way.
        focusedButton = false;
        return false;
      }
      if (widget is Semantics) {
        final role = widget.properties;
        if (_isValueControl(role)) {
          focusedButton = false;
          return false;
        }
        if (role.button == true) focusedButton = true;
      }
      return true;
    });
    if (focusedButton) return KeyEventResult.ignored;
    final field = focusedContext?.findAncestorWidgetOfExactType<EditableText>();
    final composing = field?.controller.value.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      // Let the input method confirm its candidate before submitting the form.
      return KeyEventResult.skipRemainingHandlers;
    }
    if (event is KeyDownEvent) submit?.widget._effectiveOnSubmit?.call();
    // Consume repeats as well, so holding Enter cannot submit a second time.
    return KeyEventResult.handled;
  }

  /// Semantics that make a control a form value rather than a command:
  /// selection (segments, chips), check/toggle state (checkbox, radio,
  /// switch), a mutually exclusive group, or a disclosure that opens a
  /// picker (dropdowns, menu buttons). A command button announces only
  /// `button`.
  static bool _isValueControl(SemanticsProperties role) =>
      role.inMutuallyExclusiveGroup == true ||
      role.checked != null ||
      role.toggled != null ||
      role.expanded != null ||
      (role.selected != null && role.button != true);

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
///
/// The route carries the opening context's themes and its [PdfEditorScope]
/// (an [InheritedTheme]), so a dialog that opens another stock prompt still
/// asks the same [PdfEditorPresenter]. The barrier's semantic label comes
/// from the editor's own localizations, and whatever a non-Material host
/// lacks (Material and Cupertino localizations, a theme) is re-injected
/// inside the route ([PdfMaterialHost]), so it opens from any host.
///
/// This is the stock presentation: [PdfEditorPresenter.dialog] defaults to
/// it, and the editor's own dialogs go through the presenter.
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
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  // The capture already holds a scope that sits between [context] and the
  // navigator. One above the navigator (a host's app-wide scope) is still an
  // ancestor of the route, so either way the dialog sees the same presenter.
  final scope = PdfEditorScope.maybeOf(context, listen: false);

  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: (context) {
        // Whatever the host lacks (Material localizations, a theme) is
        // re-injected here, in the route's own context under the root
        // navigator - a pass-through under a Material host.
        final child =
            pdfHostRoute(context, _PdfDialogKeyboardScope(builder: builder));
        // Re-inject only when the route's own context lost it (a scope
        // between the root and a nested navigator that opened the dialog on
        // the root one is captured too; this is the belt to that brace).
        if (scope == null ||
            identical(PdfEditorScope.maybeOf(context, listen: false)?.presenter,
                scope.presenter)) {
          return child;
        }
        return PdfEditorScope(presenter: scope.presenter, child: child);
      },
      barrierColor: barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel ?? pdfL10n(context).dialogDismiss,
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

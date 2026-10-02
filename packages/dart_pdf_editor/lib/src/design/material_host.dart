// What lets the stock (Material) editor chrome run under any host - a
// MaterialApp, a CupertinoApp or a plain WidgetsApp: the wrapper the root
// widgets install, the re-injection routes and overlays need (they build
// under the root Navigator, outside the editor's subtree), the shared text
// context menu every editor text field uses, and the dropdown that replaced
// DropdownButton (whose menu route had no hook for any of this).
//
// Under a Material host (Theme + Material and Cupertino localizations in
// scope) every piece here is a pass-through: same widgets, same tree.

import 'package:flutter/cupertino.dart'
    show
        CupertinoLocalizations,
        CupertinoTheme,
        DefaultCupertinoLocalizations,
        InheritedCupertinoTheme;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'editor_presenter.dart';

/// Supplies what the editor's stock (Material) chrome needs when the host
/// app does not: Material and Cupertino localizations, a [Theme], and a
/// transparent [Material] for ink and text fields.
///
/// `PdfViewer`, `PdfReader`, `PdfEditorView` and `PdfComparisonView` put one
/// around their content, so they run under a `CupertinoApp` or a plain
/// `WidgetsApp` as well as a `MaterialApp`. Wrap any other stock widget you
/// mount on its own (a `PdfEditingToolbar` beside your own viewer, say) the
/// same way.
///
/// Under a host that already provides a [Theme] and both localizations it
/// adds nothing - [child] is built as is. Otherwise:
///
/// * missing `MaterialLocalizations` / `CupertinoLocalizations` come from
///   `flutter_localizations` for the ambient locale (English where it has no
///   translation); the editor's dialogs, sheets, notices and text-field
///   menus, which build under the root navigator, re-inject them;
/// * with no [Theme] above, one is derived from what the host does provide:
///   a `CupertinoTheme`'s primary colour and brightness, else the platform
///   brightness ([MediaQuery]) and the host's [DefaultSelectionStyle] cursor
///   colour and [IconTheme];
/// * a transparent [Material] gives ink splashes and text fields a surface.
class PdfMaterialHost extends StatelessWidget {
  /// Wraps [child] in whatever the host is missing.
  const PdfMaterialHost({super.key, required this.child}) : _surface = true;

  /// The route/overlay variant: no [Material] surface (route content brings
  /// its own - a dialog, a sheet, a menu).
  const PdfMaterialHost._route({required this.child}) : _surface = false;

  /// The editor content.
  final Widget child;

  final bool _surface;

  /// Whether [context] lacks something the stock chrome needs.
  static bool _needsHost(BuildContext context) =>
      Localizations.of<MaterialLocalizations>(
              context, MaterialLocalizations) ==
          null ||
      Localizations.of<CupertinoLocalizations>(
              context, CupertinoLocalizations) ==
          null ||
      context.findAncestorWidgetOfExactType<Theme>() == null;

  @override
  Widget build(BuildContext context) {
    if (!_needsHost(context)) return child;
    var result = child;
    if (_surface && Material.maybeOf(context) == null) {
      result = Material(type: MaterialType.transparency, child: result);
    }
    if (context.findAncestorWidgetOfExactType<Theme>() == null) {
      result = Theme(data: _derivedTheme(context), child: result);
    }
    if (Localizations.of<MaterialLocalizations>(
                context, MaterialLocalizations) ==
            null ||
        Localizations.of<CupertinoLocalizations>(
                context, CupertinoLocalizations) ==
            null) {
      result = _installLocalizations(context, result);
    }
    return result;
  }
}

/// Wraps route or overlay content built under the root navigator: whatever
/// [context] (the route's own) lacks is re-injected. A pass-through under a
/// Material host. [themesFrom], when given, is the context the content was
/// opened from; its themes (and the editor's scope) are captured first.
Widget pdfHostRoute(BuildContext context, Widget child,
    {BuildContext? themesFrom}) {
  if (!PdfMaterialHost._needsHost(context)) return child;
  final content = PdfMaterialHost._route(child: child);
  final from = themesFrom;
  if (from == null || !from.mounted) return content;
  return InheritedTheme.capture(from: from, to: null).wrap(content);
}

/// Installs the missing localizations. Not an [InheritedTheme]: captured
/// themes wrap overlay content (the text magnifier) that must stay a direct
/// child of the overlay's stack, and [Localizations] adds a render object.
/// Routes and overlays re-inject instead ([pdfHostRoute]).
Widget _installLocalizations(BuildContext context, Widget child) =>
    Localizations.override(
      context: context,
      delegates: _hostDelegates,
      child: child,
    );

const _hostDelegates = <LocalizationsDelegate<dynamic>>[
  _MaterialFallbackDelegate(),
  _CupertinoFallbackDelegate(),
];

/// `flutter_localizations`' Material strings for the locale, or the English
/// defaults for one it does not translate (never leaves them missing).
class _MaterialFallbackDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialFallbackDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.isSupported(locale)
          ? GlobalMaterialLocalizations.delegate.load(locale)
          : DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(_MaterialFallbackDelegate old) => false;
}

/// The Cupertino counterpart of [_MaterialFallbackDelegate] (iOS and macOS
/// text-selection menus read these).
class _CupertinoFallbackDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallbackDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.isSupported(locale)
          ? GlobalCupertinoLocalizations.delegate.load(locale)
          : DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_CupertinoFallbackDelegate old) => false;
}

// ThemeData is expensive to build; hosts present a handful of distinct
// signal combinations at most.
final _derivedThemes = <Object, ThemeData>{};

/// A Material theme for a host that has none, from the widgets-layer
/// signals it does provide.
ThemeData _derivedTheme(BuildContext context) {
  final platform = defaultTargetPlatform;
  final platformBrightness =
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  final cupertino =
      context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>();
  if (cupertino != null) {
    final data = CupertinoTheme.of(context);
    final brightness = data.brightness ?? platformBrightness;
    final primary = data.primaryColor;
    final onPrimary = data.primaryContrastingColor;
    final key = (
      'cupertino',
      platform,
      brightness,
      primary.toARGB32(),
      onPrimary.toARGB32()
    );
    return _cachedTheme(
        key,
        () => ThemeData(
              platform: platform,
              colorScheme: ColorScheme.fromSeed(
                seedColor: primary,
                brightness: brightness,
                primary: primary,
                onPrimary: onPrimary,
              ),
            ));
  }
  final seed = DefaultSelectionStyle.of(context).cursorColor;
  final hostIcons = context.getInheritedWidgetOfExactType<IconTheme>()?.data;
  final key =
      ('widgets', platform, platformBrightness, seed?.toARGB32(), hostIcons);
  return _cachedTheme(key, () {
    final base = ThemeData(
      platform: platform,
      brightness: platformBrightness,
      colorSchemeSeed: seed,
    );
    return hostIcons == null
        ? base
        : base.copyWith(iconTheme: base.iconTheme.merge(hostIcons));
  });
}

ThemeData _cachedTheme(Object key, ThemeData Function() build) {
  final cached = _derivedThemes[key];
  if (cached != null) return cached;
  if (_derivedThemes.length >= 16) _derivedThemes.clear();
  return _derivedThemes[key] = build();
}

// ---- text fields ------------------------------------------------------------

/// The context menu builder every editor text field uses: the platform's
/// stock menu (the system menu where the field supports it, else the
/// adaptive Material/Cupertino toolbar), with the localizations and theme it
/// needs re-injected. The menu is built in the root overlay, outside the
/// editor's subtree, so a host without Material localizations would
/// otherwise get an error widget on right-click or long-press.
///
/// Identical to `TextField`'s default under a Material host. Use it for text
/// fields in your own dialogs that may run under a non-Material host:
///
/// ```dart
/// TextField(contextMenuBuilder: pdfTextContextMenu)
/// ```
Widget pdfTextContextMenu(
        BuildContext context, EditableTextState editableTextState) =>
    pdfStockTextContextMenu(context, editableTextState);

/// [pdfTextContextMenu] with the editor's options: [systemMenu] false keeps
/// Flutter's own toolbar on iOS (the in-page editors, whose menu
/// [place]ment corrects for the viewer's zoom transform).
Widget pdfStockTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  bool systemMenu = true,
  Widget Function(EditableTextState state, Widget menu)? place,
}) {
  Widget menu =
      systemMenu && SystemContextMenu.isSupportedByField(editableTextState)
          ? SystemContextMenu.editableText(editableTextState: editableTextState)
          : AdaptiveTextSelectionToolbar.editableText(
              key: const ValueKey('pdf-text-context-menu'),
              editableTextState: editableTextState);
  if (place != null) menu = place(editableTextState, menu);
  return pdfHostRoute(context, menu, themesFrom: editableTextState.context);
}

// ---- dropdown ---------------------------------------------------------------

/// One option of a [PdfDropdown].
@immutable
class PdfDropdownItem<T> {
  /// The option [value], shown as [child] (or [label]).
  const PdfDropdownItem({
    this.key,
    required this.value,
    required this.label,
    this.child,
  });

  /// The key of the option's menu row.
  final Key? key;

  /// What picking the option selects.
  final T value;

  /// The option's text (presenters drawing their own menus use it).
  final String label;

  /// How the button and the stock menu draw the option; [label] when null.
  final Widget? child;
}

/// A drop-down picker in the look of Material's `DropdownButton` (or, with
/// [decoration], `DropdownButtonFormField`) whose options open through the
/// [PdfEditorPresenter]'s menu - a route the editor's scope reaches, so it
/// works under any host and a host presenter draws it too.
class PdfDropdown<T> extends StatefulWidget {
  /// A picker showing [value] among [items].
  const PdfDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.isDense = false,
    this.isExpanded = false,
    this.underline,
    this.decoration,
  });

  /// The options, in menu order.
  final List<PdfDropdownItem<T>> items;

  /// The selected option's value; null shows [hint].
  final T? value;

  /// Called with the picked option; null disables the picker.
  final ValueChanged<T>? onChanged;

  /// Shown while [value] matches no option.
  final Widget? hint;

  /// A compact (24px) button.
  final bool isDense;

  /// Whether the selection fills the button's width.
  final bool isExpanded;

  /// Replaces the hairline under the button (a `SizedBox.shrink()` hides
  /// it). Ignored with a [decoration].
  final Widget? underline;

  /// Draws the button as a form field with this decoration (a label, say).
  final InputDecoration? decoration;

  @override
  State<PdfDropdown<T>> createState() => _PdfDropdownState<T>();
}

class _PdfDropdownState<T> extends State<PdfDropdown<T>> {
  bool _open = false;
  bool _focused = false;
  bool _hovering = false;

  bool get _enabled => widget.onChanged != null && widget.items.isNotEmpty;

  int? get _selectedIndex {
    for (var i = 0; i < widget.items.length; i++) {
      if (widget.items[i].value == widget.value) return i;
    }
    return null;
  }

  Future<void> _openMenu() async {
    if (!_enabled || _open) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    // the menu rows are at least as wide as the button, like the
    // DropdownButton menu this replaces (popup rows pad 12 a side)
    final minWidth = (anchor.width - 24).clamp(0.0, double.infinity);
    setState(() => _open = true);
    final T? picked;
    try {
      picked = await PdfEditorPresenter.of(context).menu<T>(
        context,
        PdfMenuRequest<T>(anchor: anchor, entries: [
          for (final item in widget.items)
            PdfMenuItem<T>(
              key: item.key,
              value: item.value,
              label: item.label,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: item.child ?? Text(item.label),
              ),
            ),
        ]),
      );
    } finally {
      if (mounted) setState(() => _open = false);
    }
    if (picked != null && mounted) widget.onChanged?.call(picked as T);
  }

  Color _iconColor(BuildContext context) =>
      switch (Theme.brightnessOf(context)) {
        Brightness.light =>
          _enabled ? Colors.grey.shade700 : Colors.grey.shade400,
        Brightness.dark => _enabled ? Colors.white70 : Colors.white10,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium!;
    final decoration = widget.decoration;
    final dense = widget.isDense || decoration != null;
    final selected = _selectedIndex;
    final children = <Widget>[
      for (final item in widget.items)
        _PdfDropdownItemBox(
            dense: dense, child: item.child ?? Text(item.label)),
      if (widget.hint != null)
        DefaultTextStyle(
          style: textStyle.copyWith(color: theme.hintColor),
          child: IgnorePointer(
              child: _PdfDropdownItemBox(dense: dense, child: widget.hint!)),
        ),
    ];
    final index =
        selected ?? (widget.hint != null ? widget.items.length : null);
    final Widget inner = children.isEmpty || index == null
        ? const SizedBox.shrink()
        : IndexedStack(
            index: index,
            alignment: AlignmentDirectional.centerStart,
            children: children,
          );
    final icon = IconTheme(
      data: IconThemeData(color: _iconColor(context), size: 24),
      child: const Icon(Icons.arrow_drop_down),
    );
    final scale = MediaQuery.textScalerOf(context);
    final denseHeight = [
      scale.scale(textStyle.fontSize ?? 16) * (textStyle.height ?? 1.0),
      24.0,
    ].reduce((a, b) => a > b ? a : b);

    Widget result = DefaultTextStyle(
      style:
          _enabled ? textStyle : textStyle.copyWith(color: theme.disabledColor),
      child: SizedBox(
        height: dense ? denseHeight : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isExpanded) Expanded(child: inner) else inner,
            if (decoration == null) icon,
          ],
        ),
      ),
    );
    final cursor = WidgetStateProperty.resolveAs<MouseCursor>(
      WidgetStateMouseCursor.adaptiveClickable,
      {if (!_enabled) WidgetState.disabled},
    );

    if (decoration != null) {
      result = FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: cursor,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovering = v),
        actions: {
          ActivateIntent:
              CallbackAction<ActivateIntent>(onInvoke: (_) => _openMenu()),
        },
        child: GestureDetector(
          onTap: _enabled ? _openMenu : null,
          behavior: HitTestBehavior.opaque,
          child: InputDecorator(
            decoration: decoration.copyWith(
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
              suffixIcon: icon,
            ),
            isEmpty: selected == null && widget.hint == null,
            isFocused: _focused,
            isHovering: _hovering,
            child: result,
          ),
        ),
      );
    } else {
      result = Stack(children: [
        result,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: widget.underline ??
              Container(
                height: 1,
                decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Color(0xFFBDBDBD), width: 0)),
                ),
              ),
        ),
      ]);
      result = InkWell(
        mouseCursor: cursor,
        onTap: _enabled ? _openMenu : null,
        canRequestFocus: _enabled,
        focusColor: theme.focusColor,
        enableFeedback: false,
        child: result,
      );
    }
    // a value control (expanded semantics): Enter in a dialog submits from
    // here, as it did from the DropdownButton this replaces
    return Semantics(
      button: true,
      expanded: _open,
      child: result,
    );
  }
}

/// An option as the button shows it: at least a menu row tall unless dense,
/// start-aligned.
class _PdfDropdownItemBox extends StatelessWidget {
  const _PdfDropdownItemBox({required this.dense, required this.child});

  final bool dense;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints:
            BoxConstraints(minHeight: dense ? 0 : kMinInteractiveDimension),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      );
}

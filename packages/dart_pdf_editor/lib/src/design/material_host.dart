// What lets the stock (material_ui) editor chrome run under any host - a
// material_ui MaterialApp, a legacy package:flutter/material.dart MaterialApp,
// a CupertinoApp or a plain WidgetsApp: the wrapper the root widgets install,
// the re-injection routes and overlays need (they build under the root
// Navigator, outside the editor's subtree), the shared text context menu
// every editor text field uses, and the dropdown that replaced DropdownButton
// (whose menu route had no hook for any of this).
//
// Under a material_ui host (Theme + Material and Cupertino localizations in
// scope) every piece here is a pass-through: same widgets, same tree. A
// legacy MaterialApp provides none of those - its Theme and localizations
// are other types - so it gets the full wrapper, themed from the host's
// legacy theme through lib/src/legacy/legacy_host_bridge.dart.

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoLocalizations,
        CupertinoTheme,
        DefaultCupertinoLocalizations,
        GlobalCupertinoLocalizations,
        InheritedCupertinoTheme;
import 'package:material_ui/material_ui.dart';

import '../legacy/legacy_host_bridge.dart';
import 'editor_presenter.dart';
import 'editor_theme.dart';

/// Supplies what the editor's stock (material_ui) chrome needs when the host
/// app does not: Material and Cupertino localizations, a [Theme], and a
/// transparent [Material] for ink and text fields.
///
/// `PdfViewer`, `PdfReader`, `PdfEditorView` and `PdfComparisonView` put one
/// around their content, so they run under a material_ui `MaterialApp`, a
/// legacy `package:flutter/material.dart` `MaterialApp`, a `CupertinoApp` or
/// a plain `WidgetsApp`. Wrap any other stock widget you mount on its own (a
/// `PdfEditingToolbar` beside your own viewer, say) the same way.
///
/// Under a material_ui host that already provides a [Theme] and both
/// localizations it adds nothing - [child] is built as is. Otherwise:
///
/// * missing (material_ui / cupertino_ui) `MaterialLocalizations` and
///   `CupertinoLocalizations` come from `GlobalMaterialLocalizations` and
///   `GlobalCupertinoLocalizations` for the ambient locale (English where
///   they have no translation); the editor's dialogs, sheets, notices and
///   text-field menus, which build under the root navigator, re-inject them;
/// * the [Theme] comes from the first of: the [PdfEditorThemeData.primary] /
///   [PdfEditorThemeData.brightness] tokens of the enclosing
///   [PdfEditorScope]; a material_ui [Theme] above; a legacy
///   `package:flutter/material.dart` `Theme` above (its colour scheme, text
///   and icon themes, platform and density - see `kPdfLegacyMaterialBridge`);
///   a `CupertinoTheme`'s primary colour and brightness; else the platform
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
      _missingLocalizations(context) ||
      context.findAncestorWidgetOfExactType<Theme>() == null ||
      _colourTokens(context) != null;

  static bool _missingLocalizations(BuildContext context) =>
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) ==
          null ||
      Localizations.of<CupertinoLocalizations>(
              context, CupertinoLocalizations) ==
          null;

  /// The enclosing scope's tokens when they set the chrome's colours.
  static PdfEditorThemeData? _colourTokens(BuildContext context) {
    final tokens = PdfEditorScope.maybeOf(context)?.theme;
    return tokens != null &&
            (tokens.primary != null || tokens.brightness != null)
        ? tokens
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsHost(context)) return child;
    var result = child;
    if (_surface && Material.maybeOf(context) == null) {
      result = Material(type: MaterialType.transparency, child: result);
    }
    final tokens = _colourTokens(context);
    if (tokens != null) {
      result = Theme(data: _tokenTheme(context, tokens), child: result);
    } else if (context.findAncestorWidgetOfExactType<Theme>() == null) {
      final bridged = pdfLegacyHostTheme(context);
      if (bridged != null) {
        // Theme installs its own IconTheme; keep the host's (legacy widgets
        // placed inside the editor's slots draw with it)
        final hostIcons =
            context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data;
        result = Theme(
          data: bridged,
          child: hostIcons == null
              ? result
              : IconTheme(data: hostIcons, child: result),
        );
      } else {
        result = Theme(data: _derivedTheme(context), child: result);
      }
    }
    if (_missingLocalizations(context)) {
      result = _installLocalizations(context, result);
    }
    return result;
  }
}

/// Wraps route or overlay content built under the root navigator: whatever
/// [context] (the route's own) lacks is re-injected. A pass-through under a
/// material_ui host. [themesFrom], when given, is the context the content
/// was opened from; its themes (and the editor's scope) are captured first.
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

// material_ui's and cupertino_ui's localizations - never the legacy
// flutter_localizations ones, which are other types. Both, always: the iOS
// and macOS text-selection menus read the Cupertino strings.
const _hostDelegates = <LocalizationsDelegate<dynamic>>[
  _MaterialFallbackDelegate(),
  _CupertinoFallbackDelegate(),
];

/// material_ui's Material strings for the locale, or the English defaults
/// for one it does not translate (never leaves them missing). Plain or US
/// English gets the built-in defaults directly - the strings a material_ui
/// `MaterialApp` without delegates has - which skips initializing intl's
/// date data for every locale on the first frame.
class _MaterialFallbackDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialFallbackDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => !_usEnglish(locale) &&
          GlobalMaterialLocalizations.delegate.isSupported(locale)
      ? GlobalMaterialLocalizations.delegate.load(locale)
      : DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(_MaterialFallbackDelegate old) => false;
}

/// The cupertino_ui counterpart of [_MaterialFallbackDelegate] (iOS and
/// macOS text-selection menus read these).
class _CupertinoFallbackDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallbackDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) => !_usEnglish(locale) &&
          GlobalCupertinoLocalizations.delegate.isSupported(locale)
      ? GlobalCupertinoLocalizations.delegate.load(locale)
      : DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_CupertinoFallbackDelegate old) => false;
}

bool _usEnglish(Locale locale) =>
    locale.languageCode == 'en' &&
    (locale.countryCode == null ||
        locale.countryCode!.isEmpty ||
        locale.countryCode == 'US');

// ThemeData is expensive to build; hosts present a handful of distinct
// signal combinations at most.
final _derivedThemes = <Object, ThemeData>{};

/// The theme the [PdfEditorThemeData.primary]/[PdfEditorThemeData.brightness]
/// tokens ask for, over whatever the host provides for the rest (platform,
/// density).
ThemeData _tokenTheme(BuildContext context, PdfEditorThemeData tokens) {
  final base = context.findAncestorWidgetOfExactType<Theme>() != null
      ? Theme.of(context)
      : pdfLegacyHostTheme(context) ?? _derivedTheme(context);
  final brightness = tokens.brightness ?? base.brightness;
  final primary = tokens.primary;
  final seed = primary ?? base.colorScheme.primary;
  final key = (
    'tokens',
    base.platform,
    base.visualDensity,
    brightness,
    seed.toARGB32(),
    primary?.toARGB32(),
  );
  return _cachedTheme(
      key,
      () => ThemeData(
            platform: base.platform,
            visualDensity: base.visualDensity,
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: brightness,
              primary: primary,
            ),
          ));
}

/// A Material theme for a host that has none, from the widgets-layer
/// signals it does provide.
ThemeData _derivedTheme(BuildContext context) {
  final platform = PdfEditorScope.platformOf(context);
  final platformBrightness =
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
  final cupertino = _cupertinoHost(context);
  if (cupertino != null) {
    final brightness = cupertino.brightness ?? platformBrightness;
    final primary = cupertino.primary;
    final onPrimary = cupertino.onPrimary;
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

/// A cupertino_ui `CupertinoTheme`'s colours above [context], else a legacy
/// `package:flutter/cupertino.dart` one's (through the bridge), else null.
({Color primary, Color onPrimary, Brightness? brightness})? _cupertinoHost(
    BuildContext context) {
  if (context.dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>() !=
      null) {
    final data = CupertinoTheme.of(context);
    return (
      primary: data.primaryColor,
      onPrimary: data.primaryContrastingColor,
      brightness: data.brightness,
    );
  }
  return pdfLegacyCupertinoHost(context);
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

// The app menu on a phone: a bottom sheet instead of the popup.
//
// The popup lists every action as a row, which on a phone is fifteen rows and
// two screens of scrolling. The sheet keeps the same actions but gives them a
// shape a thumb can work with: a search field on top (the command palette, so
// nothing becomes unreachable), four large buttons for what people do most
// (New, Open, Print, Sign), the last few files inline rather than in a
// submenu, and everything rarer folded into two rows that open a page inside
// the sheet (Export, More tools).
//
// The editor screen decides which action lands where (`_MenuAction.sheet`);
// this file only lays them out. Every action row keeps the popup's
// `menu-<id>` key.
import 'package:material_ui/material_ui.dart';

import 'l10n/app_l10n.dart';
import 'middle_ellipsis_text.dart';

/// One tappable thing in the sheet.
@immutable
class AppMenuSheetEntry {
  const AppMenuSheetEntry({
    required this.key,
    required this.icon,
    required this.title,
    required this.run,
    this.subtitle,
    this.enabled = true,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback run;
  final bool enabled;
}

/// Shows the phone app menu and returns the action the user picked, to run
/// once the sheet is gone (the same contract as the popup's `onSelected`, so
/// a dialog an action opens never stacks on the closing sheet).
Future<VoidCallback?> showAppMenuSheet(
  BuildContext context, {
  required AppMenuSheetEntry search,
  required List<AppMenuSheetEntry> create,
  required List<AppMenuSheetEntry> primary,
  required List<AppMenuSheetEntry> recents,
  required AppMenuSheetEntry? seeAllRecents,
  required List<AppMenuSheetEntry> export,
  required List<AppMenuSheetEntry> moreTools,
  required bool? readOnly,
  required VoidCallback onToggleReadOnly,
  required List<AppMenuSheetEntry> app,
}) =>
    showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => AppMenuSheet(
        search: search,
        create: create,
        primary: primary,
        recents: recents,
        seeAllRecents: seeAllRecents,
        export: export,
        moreTools: moreTools,
        readOnly: readOnly,
        onToggleReadOnly: onToggleReadOnly,
        app: app,
      ),
    );

class AppMenuSheet extends StatefulWidget {
  const AppMenuSheet({
    super.key,
    required this.search,
    required this.create,
    required this.primary,
    required this.recents,
    required this.seeAllRecents,
    required this.export,
    required this.moreTools,
    required this.readOnly,
    required this.onToggleReadOnly,
    required this.app,
  });

  /// The search field: opens the command palette.
  final AppMenuSheetEntry search;

  /// What New offers. One entry runs straight away; more open a page.
  final List<AppMenuSheetEntry> create;

  /// The large buttons after New (Open, then Print and Sign with a document).
  final List<AppMenuSheetEntry> primary;

  final List<AppMenuSheetEntry> recents;
  final AppMenuSheetEntry? seeAllRecents;

  /// Folded groups. A group of one shows as its own row instead.
  final List<AppMenuSheetEntry> export;
  final List<AppMenuSheetEntry> moreTools;

  /// Null without a document (no switch to show).
  final bool? readOnly;
  final VoidCallback onToggleReadOnly;

  final List<AppMenuSheetEntry> app;

  @override
  State<AppMenuSheet> createState() => _AppMenuSheetState();
}

/// A page inside the sheet that a folded group opens.
typedef _SubPage = ({String id, String title, List<AppMenuSheetEntry> items});

class _AppMenuSheetState extends State<AppMenuSheet> {
  _SubPage? _page;

  void _pick(AppMenuSheetEntry entry) => Navigator.of(context).pop(entry.run);

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PopScope(
      // Back on a page returns to the menu; back on the menu closes it.
      canPop: page == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _page = null);
      },
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: page == null ? _buildMain(context) : _buildPage(page),
          ),
        ),
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final l = appL10n(context);
    final create = widget.create;
    final newButton = AppMenuSheetEntry(
      key: const ValueKey('menu-new'),
      icon: Icons.note_add_outlined,
      title: l.appMenuNew,
      run: create.length == 1 ? create.single.run : () {},
    );
    final document = [
      _group(
          'export', l.appMenuExport, Icons.ios_share_outlined, widget.export),
      _group('more-tools', l.appMenuMoreTools, Icons.handyman_outlined,
          widget.moreTools),
    ].expand((rows) => rows).toList();

    return Column(
      key: const ValueKey('app-menu-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(entry: widget.search, onTap: () => _pick(widget.search)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PrimaryButton(
                  entry: newButton,
                  onTap: create.length == 1
                      ? () => _pick(newButton)
                      : () => setState(() => _page =
                          (id: 'new', title: l.appMenuNew, items: create)),
                ),
              ),
              for (final entry in widget.primary)
                Expanded(
                  child: _PrimaryButton(
                    entry: entry,
                    onTap: entry.enabled ? () => _pick(entry) : null,
                  ),
                ),
            ],
          ),
        ),
        if (widget.recents.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(l.appMenuRecent),
          for (final entry in widget.recents) _row(entry, recent: true),
          if (widget.seeAllRecents case final seeAll?) _row(seeAll),
        ],
        if (document.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(l.editorMenuSectionDocument),
          ...document,
        ],
        const Divider(height: 17),
        if (widget.readOnly case final readOnly?)
          SwitchListTile(
            key: const ValueKey('menu-read-only'),
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(l.editorMenuReadOnly),
            value: readOnly,
            onChanged: (_) =>
                Navigator.of(context).pop(widget.onToggleReadOnly),
          ),
        for (final entry in widget.app) _row(entry),
      ],
    );
  }

  /// A folded group: one row that opens its page, or - for a group of one -
  /// that one action's own row, since a page holding a single row is a
  /// detour.
  List<Widget> _group(
      String id, String title, IconData icon, List<AppMenuSheetEntry> items) {
    if (items.isEmpty) return const [];
    if (items.length == 1) return [_row(items.single)];
    return [
      ListTile(
        key: ValueKey('menu-group-$id'),
        leading: Icon(icon),
        title: Text(title),
        // Naming what is inside answers "where did Print go?" without a tap.
        subtitle: Text(
          items.map((e) => _bare(e.title)).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            setState(() => _page = (id: id, title: title, items: items)),
      ),
    ];
  }

  Widget _buildPage(_SubPage page) => Column(
        key: ValueKey('app-menu-sheet-${page.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 16),
            child: Row(
              children: [
                const BackButton(),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    page.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          for (final entry in page.items) _row(entry),
        ],
      );

  Widget _row(AppMenuSheetEntry entry, {bool recent = false}) => ListTile(
        key: entry.key,
        enabled: entry.enabled,
        leading: Icon(entry.icon),
        title: recent
            ? MiddleEllipsisText(entry.title, hidePdfExtension: true)
            : Text(entry.title),
        subtitle: entry.subtitle == null
            ? null
            : recent
                ? MiddleEllipsisText(entry.subtitle!)
                : Text(entry.subtitle!),
        onTap: () => _pick(entry),
      );

  /// "Print…" reads as "Print" inside a list of names.
  static String _bare(String title) =>
      title.endsWith('…') ? title.substring(0, title.length - 1) : title;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.entry, required this.onTap});

  final AppMenuSheetEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: entry.key,
          onTap: onTap,
          child: Semantics(
            button: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(entry.icon, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A large icon-over-label button in the top row.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.entry, required this.onTap});

  final AppMenuSheetEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final foreground = enabled
        ? scheme.onSecondaryContainer
        : scheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      label: entry.title,
      excludeSemantics: true,
      child: InkWell(
        key: entry.key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: enabled
                      ? scheme.secondaryContainer
                      : scheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(entry.icon, color: foreground),
              ),
              const SizedBox(height: 6),
              Text(
                entry.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: enabled ? scheme.onSurface : foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same quiet 11px uppercase header the popup and tool sheet use.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

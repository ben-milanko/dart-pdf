// The app-wide command palette: one searchable index over everything the app
// can do - the app menu's actions, the editing tools in the dock, the panels,
// the view options and the recent files.
//
// The index is *derived* from the lists those surfaces already build (see
// `EditorScreen._paletteCommands`, which reads the same `_MenuAction`
// descriptors the menu renders and `pdfToolCatalog()` from the editor
// package), so a new tool or menu entry joins the palette without a second
// registration - that is the whole point of the thing.
//
// Every result carries the surface it came from ("Menu", "Shapes tool",
// "Panel"), because the palette is meant to *teach* where a command lives
// rather than become a second place to learn.
import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfKeyboardAvailability;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_l10n.dart';
import 'middle_ellipsis_text.dart';

/// One indexed command.
@immutable
class AppCommand {
  const AppCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.source,
    required this.run,
    this.shortcut,
    this.subtitle,
    this.enabled = true,
    this.disabledReason,
    this.selected = false,
  });

  /// Stable identity - also the widget key suffix, so tests can find a row.
  final String id;

  /// The localized name, exactly as the surface it comes from shows it.
  final String label;

  final IconData icon;

  /// Where it lives, localized: "Menu", "Shapes tool", "Panel", "View".
  final String source;

  /// Keyboard shortcut label ("⌘P"), when the command has one.
  final String? shortcut;

  /// A second line - the file path on a recent-file command.
  final String? subtitle;

  /// Unavailable commands stay listed (dimmed, with [disabledReason]) rather
  /// than vanishing: the palette should answer "where is it?", not hide the
  /// answer.
  final bool enabled;
  final String? disabledReason;

  /// A toggle that is currently on (a visible panel, an enabled view option).
  final bool selected;

  final VoidCallback run;
}

/// Opens the palette over [context]. Returns once it closes.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<AppCommand> commands,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => _CommandPalette(commands: commands),
    );

/// How well [label] answers [query], or null when it does not.
///
/// Ranked the way a reader expects: a whole-name match beats a name that
/// starts with the query, which beats a match at a word boundary, which beats
/// a match anywhere, which beats letters found in order (so "cpg" still
/// reaches "Cloud polygon").
@visibleForTesting
int? scoreCommand(String label, String query) {
  if (query.isEmpty) return 0;
  final l = label.toLowerCase();
  final q = query.toLowerCase();
  if (l == q) return 1000;
  if (l.startsWith(q)) return 900 - l.length;
  final wordStart = RegExp('(^|[^a-z0-9])${RegExp.escape(q)}').firstMatch(l);
  if (wordStart != null) return 800 - wordStart.start;
  final at = l.indexOf(q);
  if (at >= 0) return 700 - at;
  // Subsequence: every query letter in order, penalized by how far apart.
  var i = 0;
  var gaps = 0;
  var last = -1;
  for (var c = 0; c < l.length && i < q.length; c++) {
    if (l[c] == q[i]) {
      if (last >= 0) gaps += c - last - 1;
      last = c;
      i++;
    }
  }
  if (i < q.length) return null;
  return 400 - gaps.clamp(0, 300);
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.commands});

  final List<AppCommand> commands;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _field = TextEditingController();
  final _scroll = ScrollController();

  /// The handler hangs off the *field's own* focus node rather than an
  /// ancestor `Focus`: a node's own handler runs before the text-editing
  /// shortcuts above it, so ↑/↓/⏎ drive the result list instead of moving
  /// the caret.
  late final FocusNode _fieldFocus = FocusNode(
    debugLabel: 'command-palette-field',
    onKeyEvent: (node, event) => _onKey(event, _results),
  );
  String _query = '';
  int _selected = 0;

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  /// The matching commands, best first. With no query the list is the index
  /// in its natural order (menu, tools, panels, view, files), which is a
  /// reasonable "everything, browsable" default.
  List<AppCommand> get _results {
    if (_query.trim().isEmpty) return widget.commands;
    final scored = <({AppCommand command, int score, int index})>[];
    for (var i = 0; i < widget.commands.length; i++) {
      final c = widget.commands[i];
      final label = scoreCommand(c.label, _query.trim());
      // A source match ("panel") is a weaker signal than a name match, so it
      // ranks below every name hit rather than interleaving with them.
      final source = scoreCommand(c.source, _query.trim());
      final score = label ?? (source == null ? null : source ~/ 4);
      if (score != null) {
        scored.add((command: c, score: score, index: i));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return [for (final s in scored) s.command];
  }

  /// Keyboard navigation only ever lands on a runnable row.
  void _move(int delta, List<AppCommand> results) {
    if (results.isEmpty) return;
    var i = _selected;
    for (var step = 0; step < results.length; step++) {
      i = (i + delta) % results.length;
      if (i < 0) i += results.length;
      if (results[i].enabled) break;
    }
    setState(() => _selected = i);
    _revealSelected();
  }

  void _revealSelected() {
    if (!_scroll.hasClients) return;
    const rowHeight = _paletteRowHeight;
    final target = _selected * rowHeight;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    if (target < offset) {
      _scroll.jumpTo(target);
    } else if (target + rowHeight > offset + view) {
      _scroll.jumpTo((target + rowHeight - view)
          .clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  void _runAt(List<AppCommand> results, int index) {
    if (index < 0 || index >= results.length) return;
    final command = results[index];
    if (!command.enabled) return;
    Navigator.of(context).pop();
    command.run();
  }

  KeyEventResult _onKey(KeyEvent event, List<AppCommand> results) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1, results);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1, results);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _runAt(results, _selected);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = appL10n(context);
    final results = _results;
    if (_selected >= results.length) _selected = 0;

    return Dialog(
      key: const ValueKey('command-palette'),
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(context, results),
            const Divider(height: 1),
            Flexible(
              child: results.isEmpty
                  ? _buildEmpty(context)
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: results.length,
                      itemExtent: _paletteRowHeight,
                      itemBuilder: (context, i) => _CommandRow(
                        command: results[i],
                        selected: i == _selected,
                        onTap: () => _runAt(results, i),
                        onHover: () => setState(() => _selected = i),
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _query.trim().isEmpty
                        ? l.paletteCount(widget.commands.length)
                        : l.paletteCountFiltered(
                            results.length, widget.commands.length),
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  if (PdfKeyboardAvailability.of(context))
                    Text(
                      l.paletteKeyHints,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context, List<AppCommand> results) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
      child: Row(
        children: [
          Icon(Icons.search, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              key: const ValueKey('command-palette-field'),
              controller: _field,
              focusNode: _fieldFocus,
              autofocus: true,
              // Arrow keys and Enter belong to the result list, not the
              // field's own cursor movement, so they are intercepted before
              // the editable sees them.
              onChanged: (value) => setState(() {
                _query = value;
                _selected = 0;
              }),
              onSubmitted: (_) => _runAt(results, _selected),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: appL10n(context).paletteHint,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Text(
          appL10n(context).paletteNoMatch,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

const double _paletteRowHeight = 44;

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final AppCommand command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = command.enabled ? scheme.onSurface : scheme.onSurfaceVariant;
    final shortcut =
        PdfKeyboardAvailability.of(context) ? command.shortcut : null;
    final trailing =
        command.enabled ? shortcut : (command.disabledReason ?? shortcut);
    return MouseRegion(
      onEnter: command.enabled ? (_) => onHover() : null,
      child: Material(
        color: selected && command.enabled
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          key: ValueKey('palette-result-${command.id}'),
          onTap: command.enabled ? onTap : null,
          child: Opacity(
            opacity: command.enabled ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(
                    command.selected ? Icons.check : command.icon,
                    size: 22,
                    color: command.selected ? scheme.primary : fg,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          command.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: fg),
                        ),
                        if (command.subtitle != null)
                          MiddleEllipsisText(
                            command.subtitle!,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    command.source,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      trailing,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

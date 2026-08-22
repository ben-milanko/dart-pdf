import 'package:flutter/material.dart';

import 'l10n/app_l10n.dart';
import 'recent_files.dart';

/// Full recent-files browser opened from the app menu.
///
/// The menu remains a short, fast list; this screen exposes every remembered
/// file, supports case-insensitive filename search, and lets the user choose
/// between grid and list layouts.
class RecentFilesView extends StatefulWidget {
  const RecentFilesView({
    super.key,
    required this.store,
    required this.onOpen,
    this.excludedTitles = const {},
  });

  final RecentFilesStore store;
  final ValueChanged<RecentFile> onOpen;

  /// Files already open in tabs are not useful reopen targets.
  final Set<String> excludedTitles;

  @override
  State<RecentFilesView> createState() => _RecentFilesViewState();
}

enum _RecentFilesLayout { grid, list }

class _RecentFilesViewState extends State<RecentFilesView> {
  final _search = TextEditingController();
  _RecentFilesLayout _layout = _RecentFilesLayout.grid;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() => setState(() {});

  List<RecentFile> get _visibleFiles {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final file in widget.store.entries)
        if (!widget.excludedTitles.contains(file.title) &&
            (query.isEmpty || file.title.toLowerCase().contains(query)))
          file,
    ];
  }

  void _open(RecentFile file) {
    Navigator.of(context).pop();
    widget.onOpen(file);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.exRecentFiles),
        actions: [
          IconButton(
            key: const ValueKey('recent-files-grid-view'),
            tooltip: l10n.exGridView,
            onPressed: () => setState(() => _layout = _RecentFilesLayout.grid),
            icon: Icon(
              Icons.grid_view,
              color: _layout == _RecentFilesLayout.grid
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            key: const ValueKey('recent-files-list-view'),
            tooltip: l10n.exListView,
            onPressed: () => setState(() => _layout = _RecentFilesLayout.list),
            icon: Icon(
              Icons.view_list,
              color: _layout == _RecentFilesLayout.list
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => IconButton(
              key: const ValueKey('recent-files-clear'),
              tooltip: l10n.exClearRecentFiles,
              onPressed:
                  widget.store.entries.isEmpty ? null : widget.store.clear,
              icon: const Icon(Icons.clear_all),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final files = _visibleFiles;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const ValueKey('recent-files-search'),
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.exSearchRecentFiles,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('recent-files-search-clear'),
                            tooltip: l10n.clear,
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: files.isEmpty
                    ? _EmptyRecentFiles(
                        searching: _search.text.trim().isNotEmpty)
                    : switch (_layout) {
                        _RecentFilesLayout.grid => GridView.builder(
                            key: const ValueKey('recent-files-grid'),
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 240,
                              mainAxisExtent: 178,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: files.length,
                            itemBuilder: (context, index) =>
                                _RecentFileGridTile(
                              file: files[index],
                              onTap: () => _open(files[index]),
                            ),
                          ),
                        _RecentFilesLayout.list => ListView.separated(
                            key: const ValueKey('recent-files-list'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: files.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) =>
                                _RecentFileListTile(
                              file: files[index],
                              onTap: () => _open(files[index]),
                            ),
                          ),
                      },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyRecentFiles extends StatelessWidget {
  const _EmptyRecentFiles({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.history_toggle_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? appL10n(context).exNoMatchingRecentFiles
                  : appL10n(context).exNoRecentFiles,
            ),
          ],
        ),
      );
}

class _RecentFileGridTile extends StatelessWidget {
  const _RecentFileGridTile({required this.file, required this.onTap});

  final RecentFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('recent-file-${file.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 64,
                    color: scheme.primary,
                  ),
                ),
              ),
              Text(
                _displayTitle(context, file),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _fileDetails(context, file),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentFileListTile extends StatelessWidget {
  const _RecentFileListTile({required this.file, required this.onTap});

  final RecentFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        key: ValueKey('recent-file-${file.id}'),
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: Text(
          _displayTitle(context, file),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(_fileDetails(context, file)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

String _displayTitle(BuildContext context, RecentFile file) =>
    file.title.isEmpty ? appL10n(context).exUntitled : file.title;

String _fileDetails(BuildContext context, RecentFile file) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatCompactDate(file.openedAt);
  return '$date • ${_formatByteSize(file.size)}';
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
}

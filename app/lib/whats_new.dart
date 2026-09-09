// Ships the app's own release notes inside the build.
//
// `app/CHANGELOG.md` is declared as a Flutter asset (see app/pubspec.yaml), so
// the notes a user reads are always the ones that were written for the binary
// they are running - no network call, and nothing to keep in step with the
// GitHub release page. The parser below is deliberately small: the changelog
// is written to one shape (`## <version>` headings over `- ` bullets that wrap
// across lines, with `**bold**` and `` `code` `` inline), and a whole markdown
// package would be a dependency for four rules.
import 'dart:convert' show LineSplitter;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'app_info.dart';
import 'l10n/app_l10n.dart';

/// Asset key for the bundled changelog, relative to the app package root.
const appChangelogAsset = 'CHANGELOG.md';

/// Leading whitespace marks a wrapped continuation of the bullet above.
final _indented = RegExp(r'^\s');

/// One `## <version>` section of the changelog.
class ChangelogRelease {
  const ChangelogRelease({required this.version, required this.notes});

  /// The heading text as written - a version (`4.4.0`) in a released build,
  /// or `Unreleased` in a build cut before the section was rolled over.
  final String version;

  /// The section's bullets, each unwrapped back into a single line.
  final List<String> notes;
}

/// Parses the subset of markdown `app/CHANGELOG.md` is written in.
///
/// Anything above the first `## ` heading (the `# Changelog` title) is skipped.
/// A bullet runs until the next bullet, heading, or blank line, so the source's
/// hard-wrapped lines rejoin into one paragraph.
List<ChangelogRelease> parseChangelog(String source) {
  final releases = <ChangelogRelease>[];
  var notes = <String>[];
  String? version;

  void flush() {
    final heading = version;
    if (heading != null) {
      releases.add(ChangelogRelease(version: heading, notes: notes));
    }
    notes = <String>[];
  }

  for (final line in const LineSplitter().convert(source)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('## ')) {
      flush();
      version = trimmed.substring(3).trim();
      continue;
    }
    if (version == null) continue;
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      notes.add(trimmed.substring(2).trim());
    } else if (notes.isNotEmpty && line.startsWith(_indented)) {
      // A continuation of the wrapped bullet above it.
      notes[notes.length - 1] = '${notes.last} $trimmed';
    }
  }
  flush();

  return releases;
}

/// Splits a bullet into `**bold**` / `` `code` `` runs.
///
/// Returned in source order; an unterminated marker stays literal text rather
/// than swallowing the rest of the line.
List<InlineSpan> changelogSpans(
  String text, {
  required TextStyle? bold,
  required TextStyle? code,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();

  void flushPlain() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString()));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flushPlain();
        spans.add(TextSpan(text: text.substring(i + 2, end), style: bold));
        i = end + 2;
        continue;
      }
    } else if (text[i] == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        spans.add(TextSpan(text: text.substring(i + 1, end), style: code));
        i = end + 1;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flushPlain();

  return spans;
}

Future<List<ChangelogRelease>>? _cached;

/// Reads and parses the bundled changelog.
///
/// The result is cached for the default bundle, because the dialog is opened
/// from three places and the file never changes under a running build. A test
/// passing its own [bundle] always gets a fresh read.
Future<List<ChangelogRelease>> loadAppChangelog({AssetBundle? bundle}) {
  if (bundle != null) {
    return bundle.loadString(appChangelogAsset).then(parseChangelog);
  }
  return _cached ??=
      rootBundle.loadString(appChangelogAsset).then(parseChangelog);
}

@visibleForTesting
void debugResetChangelogCache() => _cached = null;

/// Opens the "What's new" dialog over [context].
Future<void> showWhatsNew(BuildContext context, {AssetBundle? bundle}) =>
    showPdfDialog<void>(
      context: context,
      builder: (context) => _WhatsNewDialog(bundle: bundle),
    );

/// The bundled release notes, newest first, with the running build's own
/// section badged so a reader can tell what they already have.
class _WhatsNewDialog extends StatefulWidget {
  const _WhatsNewDialog({this.bundle});

  final AssetBundle? bundle;

  @override
  State<_WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<_WhatsNewDialog> {
  late final Future<List<ChangelogRelease>> _releases =
      loadAppChangelog(bundle: widget.bundle);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('whats-new-dialog'),
      title: Text(appL10n(context).whatsNew),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<ChangelogRelease>>(
          future: _releases,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final releases = snapshot.data ?? const <ChangelogRelease>[];
            if (releases.isEmpty) {
              return Text(
                appL10n(context).whatsNewUnavailable,
                key: const ValueKey('whats-new-unavailable'),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, release) in releases.indexed) ...[
                    if (index > 0) const SizedBox(height: 20),
                    _ReleaseSection(release: release),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        PdfDialogSubmit(
            child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appL10n(context).close),
        )),
      ],
    );
  }
}

class _ReleaseSection extends StatelessWidget {
  const _ReleaseSection({required this.release});

  final ChangelogRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodySmall;
    final code = body?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier'],
      color: scheme.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(release.version, style: theme.textTheme.titleSmall),
            ),
            if (release.version == AppInfo.version) ...[
              const SizedBox(width: 8),
              // The running build's own section, so a reader can place
              // themselves in the list without checking About first.
              Container(
                key: const ValueKey('whats-new-installed'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  appL10n(context).whatsNewInstalled,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        for (final note in release.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: body),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: changelogSpans(
                        note,
                        bold: body?.copyWith(fontWeight: FontWeight.w600),
                        code: code,
                      ),
                    ),
                    style: body,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

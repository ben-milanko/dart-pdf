// Ships the app's own release notes inside the build.
//
// `app/CHANGELOG.md` is declared as a Flutter asset (see app/pubspec.yaml), so
// the notes a user reads are always the ones that were written for the binary
// they are running - no network call, and nothing to keep in step with the
// GitHub release page. The parser below is deliberately small: the changelog
// is written to one shape (`## <version>` headings over `- ` bullets that wrap
// across lines, with `**bold**` and `` `code` `` inline), and a whole markdown
// package would be a dependency for four rules.
//
// A nightly build adds one section the changelog can't carry: the tickets
// merged since the last published release. The nightly workflow writes them
// into the `app-nightly` GitHub release body
// (.github/scripts/nightly-release-tickets.py), so a nightly fetches that body
// when the dialog opens and parses the one section back out.
import 'dart:convert' show LineSplitter, jsonDecode;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'l10n/app_l10n.dart';
import 'update.dart' show dartPdfNightlyTag;

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

/// One merged pull request listed in a nightly's release notes.
@immutable
class NightlyTicket {
  const NightlyTicket({
    required this.title,
    required this.number,
    required this.url,
  });

  /// The squash-merge subject, without its trailing `(#123)`.
  final String title;
  final int number;
  final String url;
}

/// The "Tickets since [DartPDF x.y.z]" section of a nightly's release notes.
@immutable
class NightlyTickets {
  const NightlyTickets({
    required this.sinceVersion,
    required this.tickets,
    this.commitSha,
  });

  /// The published release the list counts from (`10.0.0`).
  final String sinceVersion;

  /// Newest first, as the workflow lists them. Empty when nothing has merged
  /// since [sinceVersion].
  final List<NightlyTicket> tickets;

  /// The `main` commit the nightly was built from, when the notes record it.
  final String? commitSha;
}

final _ticketsHeading = RegExp(r'^## Tickets since \[DartPDF ([^\]]+)\]');
final _ticketLine = RegExp(r'^- (.*) \(\[#(\d+)\]\(([^)\s]+)\)\)$');
final _nightlyCommit = RegExp(r'<!-- main-sha: ([0-9a-fA-F]{7,40}) -->');
final _escapedBracket = RegExp(r'\\([\[\]])');

/// Reads the ticket section back out of a nightly release body, or null when
/// the body has none (a nightly from before the section existed) or the
/// workflow could not compare against the release.
NightlyTickets? parseNightlyTickets(String body) {
  String? since;
  final tickets = <NightlyTicket>[];
  for (final line in const LineSplitter().convert(body)) {
    final trimmed = line.trim();
    if (since == null) {
      since = _ticketsHeading.firstMatch(trimmed)?.group(1);
      continue;
    }
    if (trimmed.startsWith('## ')) break;
    final match = _ticketLine.firstMatch(trimmed);
    if (match == null) continue;
    tickets.add(NightlyTicket(
      title:
          match.group(1)!.replaceAllMapped(_escapedBracket, (m) => m.group(1)!),
      number: int.parse(match.group(2)!),
      url: match.group(3)!,
    ));
  }
  if (since == null) return null;
  // A "different histories" note has no bullets and no comparison link; an
  // empty list there would wrongly claim nothing has merged.
  if (tickets.isEmpty && !body.contains('No new merged tickets')) return null;
  return NightlyTickets(
    sinceVersion: since,
    tickets: tickets,
    commitSha: _nightlyCommit.firstMatch(body)?.group(1)?.toLowerCase(),
  );
}

/// Fetches the body of the rolling nightly release, for [showWhatsNew].
typedef NightlyNotesFetcher = Future<String> Function();

/// The default [NightlyNotesFetcher]: the `app-nightly` release from the
/// GitHub API, the same endpoint the update checker reads.
Future<String> fetchNightlyReleaseNotes({http.Client? client}) async {
  final uri = Uri.https(
    'api.github.com',
    '/repos/ben-milanko/dart-pdf/releases/tags/$dartPdfNightlyTag',
  );
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c.get(uri, headers: const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'DartPDF-whats-new',
    });
    if (response.statusCode != 200) {
      throw http.ClientException(
          'GitHub returned HTTP ${response.statusCode}', uri);
    }
    final decoded = jsonDecode(response.body);
    final body = decoded is Map ? decoded['body'] : null;
    return body is String ? body : '';
  } finally {
    if (owned) c.close();
  }
}

/// Opens the "What's new" dialog over [context].
///
/// A nightly build also lists the tickets merged since the last release,
/// fetched with [nightlyNotes] (default [fetchNightlyReleaseNotes]); other
/// builds skip that section unless a test passes its own fetcher.
Future<void> showWhatsNew(
  BuildContext context, {
  AssetBundle? bundle,
  NightlyNotesFetcher? nightlyNotes,
}) =>
    showPdfDialog<void>(
      context: context,
      builder: (context) => _WhatsNewDialog(
        bundle: bundle,
        nightlyNotes: nightlyNotes ??
            (AppInfo.isNightly ? fetchNightlyReleaseNotes : null),
      ),
    );

/// The bundled release notes, newest first, with the running build's own
/// section badged so a reader can tell what they already have.
class _WhatsNewDialog extends StatefulWidget {
  const _WhatsNewDialog({this.bundle, this.nightlyNotes});

  final AssetBundle? bundle;
  final NightlyNotesFetcher? nightlyNotes;

  @override
  State<_WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<_WhatsNewDialog> {
  late final Future<List<ChangelogRelease>> _releases =
      loadAppChangelog(bundle: widget.bundle);
  late final Future<NightlyTickets?>? _tickets =
      widget.nightlyNotes?.call().then(parseNightlyTickets);

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
            final tickets = _tickets;
            if (releases.isEmpty && tickets == null) {
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
                  if (tickets != null) ...[
                    _NightlyTicketsSection(tickets: tickets),
                    if (releases.isNotEmpty) const SizedBox(height: 20),
                  ],
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
        PdfDialogSubmit.action(
            onSubmit: () => Navigator.of(context).pop(),
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
              const _InstalledBadge(),
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

/// The tickets merged into the nightly since the last published release.
class _NightlyTicketsSection extends StatelessWidget {
  const _NightlyTicketsSection({required this.tickets});

  final Future<NightlyTickets?> tickets;

  @override
  Widget build(BuildContext context) {
    final l = appL10n(context);
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall;
    return FutureBuilder<NightlyTickets?>(
      future: tickets,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            key: ValueKey('whats-new-nightly-loading'),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snapshot.hasError ? null : snapshot.data;
        if (data == null) {
          return Text(
            l.whatsNewNightlyUnavailable,
            key: const ValueKey('whats-new-nightly-unavailable'),
            style: body,
          );
        }
        final sha = data.commitSha;
        final installed = sha != null &&
            AppInfo.buildCommit.toLowerCase().startsWith(sha.substring(0, 7));
        return Column(
          key: const ValueKey('whats-new-nightly'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(l.whatsNewNightlyTickets(data.sinceVersion),
                      style: theme.textTheme.titleSmall),
                ),
                if (installed) ...[
                  const SizedBox(width: 8),
                  const _InstalledBadge(),
                ],
              ],
            ),
            if (sha != null && !installed) ...[
              const SizedBox(height: 4),
              // The rolling release is always the newest nightly, which can
              // be ahead of the one running.
              Text(
                l.whatsNewNightlyNewer(sha.substring(0, 7)),
                key: const ValueKey('whats-new-nightly-newer'),
                style:
                    body?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 6),
            if (data.tickets.isEmpty)
              Text(l.whatsNewNightlyNoTickets(data.sinceVersion), style: body),
            for (final ticket in data.tickets)
              _TicketRow(ticket: ticket, style: body),
          ],
        );
      },
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.style});

  final NightlyTicket ticket;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final link = style?.copyWith(color: Theme.of(context).colorScheme.primary);
    return InkWell(
      key: ValueKey('whats-new-ticket-${ticket.number}'),
      onTap: () => launchUrl(Uri.parse(ticket.url),
          mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: style),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${ticket.title} '),
                  TextSpan(text: '#${ticket.number}', style: link),
                ]),
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledBadge extends StatelessWidget {
  const _InstalledBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
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
    );
  }
}

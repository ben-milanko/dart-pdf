import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'build_channel.dart';
import 'l10n/app_l10n.dart';

/// The stable web app, deployed from every main push (deploy-app-web.yml).
const dartPdfWebAppUrl = 'https://app.dart-pdf.com/';

/// The nightly web app, rebuilt from main every night with
/// `PDF_BUILD_CHANNEL=nightly` (deploy-app-web-nightly.yml).
const dartPdfNightlyWebAppUrl = 'https://app-nightly.dart-pdf.com/';

/// The web app on the other channel from [nightly]: the nightly site from the
/// stable one, and back.
Uri otherWebChannelUri({bool nightly = kIsNightlyBuild}) =>
    Uri.parse(nightly ? dartPdfWebAppUrl : dartPdfNightlyWebAppUrl);

/// The web-only Settings row that hops between app.dart-pdf.com and
/// app-nightly.dart-pdf.com. It opens a new tab rather than navigating away:
/// the two sites are separate origins, so this tab's open documents, recents
/// and unsaved-changes mirror stay where they are.
class WebChannelSwitchTile extends StatelessWidget {
  const WebChannelSwitchTile({
    super.key,
    this.nightly = kIsNightlyBuild,
    this.launcher,
  });

  /// Whether the running build is the nightly (tests flip both channels).
  final bool nightly;

  /// Opens the URL; null uses `url_launcher` (tests inject a fake).
  final Future<bool> Function(Uri uri)? launcher;

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    return ListTile(
      key: const ValueKey('settings-web-channel'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(nightly ? Icons.verified_outlined : Icons.science_outlined),
      title: Text(nightly ? l10n.settingsWebStable : l10n.settingsWebNightly),
      subtitle: Text(nightly
          ? l10n.settingsWebStableSubtitle
          : l10n.settingsWebNightlySubtitle),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () {
        final uri = otherWebChannelUri(nightly: nightly);
        (launcher ?? launchUrl)(uri);
      },
    );
  }
}

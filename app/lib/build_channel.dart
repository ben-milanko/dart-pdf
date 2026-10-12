/// Which release channel produced this binary, supplied by CI through
/// `--dart-define=PDF_BUILD_CHANNEL=nightly`. Unset (stable releases, store
/// builds, `flutter run`) reads as the stable channel.
///
/// Kept import-free so the eagerly loaded window bootstrap can name the
/// product without pulling in the deferred [AppInfo] unit.
const kBuildChannel =
    String.fromEnvironment('PDF_BUILD_CHANNEL', defaultValue: 'stable');

/// Whether this binary is the rolling nightly build from `main`.
const kIsNightlyBuild = kBuildChannel == 'nightly';

/// The product name the running build identifies itself by: windows, the
/// About box, and the welcome hero. A nightly sits beside (or over) a stable
/// install, so it says which one it is.
const kProductDisplayName = kIsNightlyBuild ? 'DartPDF Nightly' : 'DartPDF';

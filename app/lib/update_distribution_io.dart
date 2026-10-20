import 'dart:io';

/// Flatpak and Snap set these variables for sandboxed processes. Those
/// installations update through their package manager, so the app must not
/// advertise a parallel AppImage download from GitHub.
bool get defaultStoreManagedUpdateChannel =>
    (Platform.environment['FLATPAK_ID']?.isNotEmpty ?? false) ||
    (Platform.environment['SNAP']?.isNotEmpty ?? false);

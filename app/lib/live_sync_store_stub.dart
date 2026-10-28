import 'live_sync.dart';

/// No file system to share a folder through: live sync is unavailable.
LiveSyncBackend? get platformLiveSyncBackend => null;

import 'unsaved_changes.dart';

/// No `dart:io` and no JS interop: there is nowhere durable to mirror unsaved
/// edits, so recovery is unavailable and the editor behaves exactly as it did
/// before the feature existed.
UnsavedChangesStore? openUnsavedChangesStore() => null;

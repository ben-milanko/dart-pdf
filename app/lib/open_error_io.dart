import 'dart:io';

/// A concise file-open failure that deliberately omits the source path,
/// exception type, and errno. The path remains available in diagnostics logs.
String openErrorSummary(Object error) {
  if (error is FileSystemException) {
    final parts = <String>[];
    final message = error.message.trim();
    final osMessage = error.osError?.message.trim();
    if (message.isNotEmpty) parts.add(message);
    if (osMessage != null &&
        osMessage.isNotEmpty &&
        !parts.any((part) => part.toLowerCase() == osMessage.toLowerCase())) {
      parts.add(osMessage);
    }
    if (parts.isNotEmpty) return parts.join(': ');
  }
  final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 180 ? text : '${text.substring(0, 177)}…';
}

/// A concise cross-platform fallback for errors from web/file-provider APIs.
String openErrorSummary(Object error) {
  final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 180 ? text : '${text.substring(0, 177)}…';
}

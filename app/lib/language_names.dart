import 'package:flutter/widgets.dart';

/// The native display name (autonym) for a UI [locale], shown in the Settings
/// language picker.
///
/// A language picker lists each language in its own script — a user hunting
/// for their language finds it regardless of the language the UI is currently
/// in. The table covers the shipped and planned i18n tier locales; anything
/// not listed falls back to the locale's own BCP-47 tag so a newly added ARB
/// still shows *something* sensible before its name is added here.
String languageDisplayName(Locale locale) {
  final tag = locale.toLanguageTag();
  return _autonyms[tag] ?? _autonyms[locale.languageCode] ?? tag;
}

// Keyed by BCP-47 tag first (so region/script variants can differ), then by
// bare language code as the fallback. Autonyms, deliberately — not English
// names.
const Map<String, String> _autonyms = {
  'en': 'English',
  'es': 'Español',
  'de': 'Deutsch',
  'fr': 'Français',
  'pt': 'Português',
  'pt-BR': 'Português (Brasil)',
  'ru': 'Русский',
  'hi': 'हिन्दी',
  'ar': 'العربية',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '中文',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'it': 'Italiano',
  'tr': 'Türkçe',
  'vi': 'Tiếng Việt',
  'id': 'Bahasa Indonesia',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'th': 'ไทย',
  'uk': 'Українська',
};

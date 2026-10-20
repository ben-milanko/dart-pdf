// Headless stamp models: the custom-stamp record, the stamp date/time formats
// and the import/export callback shapes, kept apart from the Material stamp
// picker and editor in editing_stamps.dart (which re-exports the public
// names), so the editing controller's import closure stays free of
// flutter/material. See tool/check_design_imports.dart.

import 'dart:convert';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:intl/intl.dart' as intl;
import 'package:pdf_document/pdf_document.dart' show PdfStampTemplate;

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _fourDigits(int value) => value.toString().padLeft(4, '0');

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The abbreviated month name for [month] (1-12) in [localeName], falling back
/// to the bundled English abbreviations.
///
/// `localeName == null` keeps the English default (the behavior for hosts that
/// never register the localization delegate). When a locale is given but its
/// `intl` date symbols aren't loaded yet - e.g. a plain unit test that never
/// registered `flutter_localizations` - the lookup throws and we fall back to
/// English rather than crash the stamp.
String _monthAbbr(int month, String? localeName) {
  if (localeName == null) return _monthNames[month - 1];
  try {
    return intl.DateFormat.MMM(localeName).format(DateTime(2000, month));
  } catch (_) {
    return _monthNames[month - 1];
  }
}

/// The localized AM/PM marker for [value] in [localeName], falling back to
/// English `AM`/`PM` (see [_monthAbbr] for the fallback rationale).
String _dayPeriod(DateTime value, String? localeName) {
  final fallback = value.hour < 12 ? 'AM' : 'PM';
  if (localeName == null) return fallback;
  try {
    return intl.DateFormat('a', localeName).format(value);
  } catch (_) {
    return fallback;
  }
}

/// Date formats used by the built-in `{{date}}` and `{{datetime}}` stamp
/// template fields.
enum PdfStampDateFormat {
  iso,
  dayMonthYear,
  monthDayYear,
  dayMonthNameYear,
  monthNameDayYear;

  /// Formats [value] for the stamp `{{date}}` field.
  ///
  /// [localeName] localizes the spelled-out month name (`dayMonthNameYear` /
  /// `monthNameDayYear`); null keeps English. Numeric shapes ([iso] and the
  /// slash forms) stay ASCII digits regardless - `iso` in particular is a
  /// fixed technical format, not a localized one.
  String format(DateTime value, {String? localeName}) {
    final year = _fourDigits(value.year);
    final month = _twoDigits(value.month);
    final day = _twoDigits(value.day);
    final monthName = _monthAbbr(value.month, localeName);
    return switch (this) {
      PdfStampDateFormat.iso => '$year-$month-$day',
      PdfStampDateFormat.dayMonthYear => '$day/$month/$year',
      PdfStampDateFormat.monthDayYear => '$month/$day/$year',
      PdfStampDateFormat.dayMonthNameYear => '${value.day} $monthName $year',
      PdfStampDateFormat.monthNameDayYear => '$monthName ${value.day}, $year',
    };
  }
}

/// Time formats used by the built-in `{{time}}` and `{{datetime}}` stamp
/// template fields.
enum PdfStampTimeFormat {
  twentyFourHour,
  twelveHour,
  twentyFourHourSeconds,
  twelveHourSeconds;

  /// Formats [value] for the stamp `{{time}}` field.
  ///
  /// [localeName] localizes the AM/PM marker on the 12-hour shapes; null keeps
  /// English. The 24-hour shapes carry no marker and are locale-independent.
  String format(DateTime value, {String? localeName}) {
    final hour = _twoDigits(value.hour);
    final minute = _twoDigits(value.minute);
    final second = _twoDigits(value.second);
    final suffix = _dayPeriod(value, localeName);
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return switch (this) {
      PdfStampTimeFormat.twentyFourHour => '$hour:$minute',
      PdfStampTimeFormat.twelveHour => '$hour12:$minute $suffix',
      PdfStampTimeFormat.twentyFourHourSeconds => '$hour:$minute:$second',
      PdfStampTimeFormat.twelveHourSeconds => '$hour12:$minute:$second $suffix',
    };
  }
}

/// A reusable rubber stamp: visual template plus optional app metadata.
///
/// Custom stamps are saved on the local device through
/// [PdfEditingPreferences.customStamps], so they survive app restarts and
/// are shared across documents. Host apps can also supply non-persisted stamps
/// through [PdfEditingController.providedCustomStamps] or the editor shell's
/// custom-stamps parameter. The stamp tool places the
/// [PdfEditingController.activeStamp] with a tap; with none active it falls
/// back to the classic flow (drag a box, type the caption).
///
/// Serializes to JSON so [PdfEditingPreferences] can persist it.
class PdfCustomStamp {
  const PdfCustomStamp({
    required this.text,
    required this.color,
    this.template,
    this.type,
    this.tags = const [],
  });

  /// The caption drawn inside the stamp's rounded border.
  final String text;

  /// RGB border and caption color.
  final int color;

  /// Editable vector template for newer stamps. Null means this is a legacy
  /// text-only stamp and should be rendered with the classic appearance.
  final PdfStampTemplate? template;

  /// App-defined stamp kind, e.g. "Approval", "Audit", or "Tested".
  final String? type;

  /// App-defined labels for filtering, grouping, or reporting stamps.
  final List<String> tags;

  bool hasTag(String tag) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return tags.any((value) => value.trim().toLowerCase() == normalized);
  }

  String encode() => jsonEncode({
        'text': text,
        'color': color,
        if (template != null) 'template': template!.toJson(),
        if (type != null && type!.trim().isNotEmpty) 'type': type,
        if (tags.isNotEmpty) 'tags': tags,
      });

  /// Parses [encode]'s output; null for anything malformed.
  static PdfCustomStamp? decode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return PdfCustomStamp(
        text: map['text'] as String,
        color: map['color'] as int,
        template: PdfStampTemplate.fromJson(map['template']),
        type: map['type'] is String ? map['type'] as String : null,
        tags: [
          if (map['tags'] is List)
            for (final tag in map['tags'] as List)
              if (tag is String && tag.trim().isNotEmpty) tag
        ],
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfCustomStamp &&
      other.text == text &&
      other.color == color &&
      other.template == template &&
      other.type == type &&
      _stringListEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(text, color, template, type,
      Object.hashAll(tags.map((tag) => tag.trim().toLowerCase())));
}

/// Saves user-managed custom stamps somewhere outside the editor package.
///
/// The stock picker passes only [PdfEditingController.savedCustomStamps];
/// host-provided stamps are managed by the host and are not exported here.
typedef PdfStampExportCallback = Future<void> Function(
  BuildContext context,
  List<PdfCustomStamp> stamps,
);

/// Loads user-managed custom stamps from somewhere outside the editor package.
///
/// Return null when the user cancels. Returned stamps are merged into the
/// saved custom stamp list, skipping exact duplicates already shown.
typedef PdfStampImportCallback = Future<List<PdfCustomStamp>?> Function(
  BuildContext context,
);

bool _stringListEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

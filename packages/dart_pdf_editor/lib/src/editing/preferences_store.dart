// Where PdfEditingPreferences keeps its values. The default is the device's
// shared_preferences store; a host can hand in its own (a settings database,
// a per-user profile, memory only in tests). No widgets here.

import 'package:shared_preferences/shared_preferences.dart';

/// The key-value storage behind [PdfEditingPreferences]
/// (`PdfEditingPreferences(store:)`).
///
/// Reads are synchronous (the preferences read every value once, when they
/// load); writes return a future the preferences do not wait on. Values are
/// the five shared_preferences types. Keys are namespaced by the
/// preferences (`dart_pdf_editor.editing.*`), so one store can be shared
/// with the host's own settings.
///
/// Implement it to keep the editor's preferences somewhere other than the
/// device default - [PdfMemoryPreferencesStore] is a ready in-memory one:
///
/// ```dart
/// final prefs = PdfEditingPreferences(store: MySettingsStore());
/// ```
abstract class PdfPreferencesStore {
  const PdfPreferencesStore();

  /// The device default: `SharedPreferences.getInstance()`, wrapped.
  static Future<PdfPreferencesStore> sharedPreferences() async =>
      PdfSharedPreferencesStore(await SharedPreferences.getInstance());

  bool? getBool(String key);
  int? getInt(String key);
  double? getDouble(String key);
  String? getString(String key);
  List<String>? getStringList(String key);

  /// Whether [key] holds any value.
  bool containsKey(String key);

  Future<bool> setBool(String key, bool value);
  Future<bool> setInt(String key, int value);
  Future<bool> setDouble(String key, double value);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);

  Future<bool> remove(String key);
}

/// A [PdfPreferencesStore] over a [SharedPreferences] instance - what
/// [PdfEditingPreferences] uses when no store is passed.
class PdfSharedPreferencesStore extends PdfPreferencesStore {
  const PdfSharedPreferencesStore(this.preferences);

  final SharedPreferences preferences;

  @override
  bool? getBool(String key) => preferences.getBool(key);
  @override
  int? getInt(String key) => preferences.getInt(key);
  @override
  double? getDouble(String key) => preferences.getDouble(key);
  @override
  String? getString(String key) => preferences.getString(key);
  @override
  List<String>? getStringList(String key) => preferences.getStringList(key);
  @override
  bool containsKey(String key) => preferences.containsKey(key);

  @override
  Future<bool> setBool(String key, bool value) =>
      preferences.setBool(key, value);
  @override
  Future<bool> setInt(String key, int value) => preferences.setInt(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      preferences.setDouble(key, value);
  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      preferences.setStringList(key, value);

  @override
  Future<bool> remove(String key) => preferences.remove(key);
}

/// A [PdfPreferencesStore] held in memory: nothing outlives the process.
/// For tests, kiosks and hosts that persist [values] themselves.
class PdfMemoryPreferencesStore extends PdfPreferencesStore {
  PdfMemoryPreferencesStore([Map<String, Object>? values])
      : values = {...?values};

  /// The stored values, by key. Lists are stored as `List<String>`.
  final Map<String, Object> values;

  T? _get<T>(String key) {
    final value = values[key];
    return value is T ? value : null;
  }

  Future<bool> _set(String key, Object value) {
    values[key] = value;
    return Future.value(true);
  }

  @override
  bool? getBool(String key) => _get<bool>(key);
  @override
  int? getInt(String key) => _get<int>(key);
  @override
  double? getDouble(String key) => _get<double>(key);
  @override
  String? getString(String key) => _get<String>(key);
  @override
  List<String>? getStringList(String key) => _get<List<String>>(key)?.toList();
  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _set(key, value);
  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, List<String>.of(value));

  @override
  Future<bool> remove(String key) {
    values.remove(key);
    return Future.value(true);
  }
}

// Self-driving build of the DartPDF app, used only to capture device
// screenshots of the real app screens (welcome, editor with the tab strip,
// light + dark). It steps through a fixed list of states, holding each one
// still and printing a marker line the host capture tool watches for:
//
//   @@SHOT@@ <name>     a scene is settled and on screen — grab it now
//   @@SHOT_DONE@@       all scenes done — the host can quit `flutter run`
//
// tool/screenshots.sh (shared with the example) drives it; or run by hand
// once a device is booted:
//
//   fvm flutter run -d <device> -t tool/screenshots_main.dart
//
// This entry lives under tool/ (not lib/) so it may import the example
// package as a dev dependency for its feature-showcase document. It mirrors
// the real app shell (app/lib/app.dart) — a prefs-driven MaterialApp around
// EditorScreen — but starts from an isolated, empty preferences store so a
// developer's real saved settings never bleed into a marketing shot.

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:pdf_viewer_example/demo_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

/// Milliseconds each scene is held on screen after its marker, giving the
/// host time to capture. Overridable: `--dart-define=SHOT_HOLD_MS=4000`.
const _holdMs = int.fromEnvironment('SHOT_HOLD_MS', defaultValue: 2600);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean slate: ignore whatever the developer has persisted locally so the
  // scenes are deterministic (default panels, light theme to start). This is a
  // screenshot harness, so the test-only seeding API is the right tool.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  runApp(const AppScreenshots());
}

class AppScreenshots extends StatefulWidget {
  const AppScreenshots({super.key});

  @override
  State<AppScreenshots> createState() => _AppScreenshotsState();
}

class _Scene {
  const _Scene(this.name,
      {this.themeMode = ThemeMode.light, this.thumbnails = false});
  final String name;
  final ThemeMode themeMode;

  /// Whether the page-thumbnail side panel is open for this scene.
  final bool thumbnails;
}

const _scenes = <_Scene>[
  // Hero: a real document open in the editor, clean (no side panels) so the
  // page itself is the focus.
  _Scene('01-welcome'),
  // The editor showing the page-thumbnail panel and the browser-style tab strip
  // — the full workspace.
  _Scene('02-editor', thumbnails: true),
  // The same editor in dark mode.
  _Scene('03-dark', themeMode: ThemeMode.dark, thumbnails: true),
];

class _AppScreenshotsState extends State<AppScreenshots> {
  final _prefs = PdfEditingPreferences();
  late final _doc = (bytes: buildDemoPdf(), title: 'Feature Showcase.pdf');

  _Scene _scene = _scenes.first;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _settle({bool heavy = false}) async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await Future<void>.delayed(Duration(milliseconds: heavy ? 2400 : 1300));
  }

  Future<void> _run() async {
    // Let the first frame, the preferences load, and the document open + render.
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    for (final scene in _scenes) {
      // Set the prefs first, THEN rebuild the editor under a per-scene key. The
      // shell reads panel visibility once at init, so flipping the pref on a
      // live shell won't collapse an open panel — re-keying forces a fresh read
      // (the theme still applies live through the prefs listenable).
      _prefs.themeMode = scene.themeMode;
      _prefs.showThumbnailSidebar = scene.thumbnails;
      if (mounted) setState(() => _scene = scene);
      await _settle(heavy: true);
      debugPrint('@@SHOT@@ ${scene.name}');
      await Future<void>.delayed(Duration(milliseconds: _holdMs));
    }
    debugPrint('@@SHOT_DONE@@');
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder mirrors app/lib/app.dart so the MaterialApp re-themes
    // the instant a scene flips the persisted theme mode. The editor is keyed
    // per scene so each one re-reads its panel-visibility prefs at init (and the
    // document reopens fresh, landing on page 1).
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'DartPDF',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: _prefs.themeMode,
        home: EditorScreen(
          key: ValueKey(_scene.name),
          prefs: _prefs,
          initialDocument: _doc,
        ),
      ),
    );
  }
}

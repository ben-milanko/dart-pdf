import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/windows_file_dialogs.dart';

/// Records the calls the runner would receive and replies with [reply], or
/// throws [MissingPluginException] when [reply] is null - the shape of a
/// runner that predates the dialog channel.
class _FakeRunner {
  _FakeRunner({this.reply});

  Map<String, Object?>? reply;
  final calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowsFileDialogChannel, (call) async {
      calls.add(call);
      if (reply == null) throw MissingPluginException(call.method);
      return reply;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsFileDialogChannel, null);
    });
  }

  Map<String, Object?> get lastArguments =>
      (calls.last.arguments as Map).cast<String, Object?>();
}

/// Stands in for the implementation [WindowsFileDialogs] displaces.
class _FallbackSelector extends FileSelectorPlatform {
  bool openedFile = false;
  bool openedFiles = false;
  bool savedLocation = false;
  bool pickedDirectory = false;
  bool pickedDirectories = false;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openedFile = true;
    return XFile(r'C:\fallback.pdf');
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    openedFiles = true;
    return [XFile(r'C:\fallback.pdf')];
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    savedLocation = true;
    return const FileSaveLocation(r'C:\fallback.pdf');
  }

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) async {
    pickedDirectory = true;
    return r'C:\fallback';
  }

  @override
  Future<List<String>> getDirectoryPathsWithOptions(
    FileDialogOptions options,
  ) async {
    pickedDirectories = true;
    return [r'C:\fallback'];
  }
}

const _pdf = XTypeGroup(label: 'PDF', extensions: ['pdf']);
const _images = XTypeGroup(label: 'Images', extensions: ['png', 'jpg']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openFile forwards the type filters and returns the pick', () async {
    final runner = _FakeRunner(reply: {
      'paths': [r'C:\docs\report.pdf'],
      'filterIndex': 1,
    });
    runner.install();
    final dialogs = WindowsFileDialogs();

    final file = await dialogs.openFile(
      acceptedTypeGroups: [_pdf, _images],
      initialDirectory: r'C:\docs',
      confirmButtonText: 'Open',
    );

    // Only the path is asserted: XFile derives `name` with the *host*
    // separator, so a Windows path only splits correctly on a Windows host.
    expect(file?.path, r'C:\docs\report.pdf');
    expect(runner.calls.single.method, 'openFile');
    expect(runner.lastArguments['initialDirectory'], r'C:\docs');
    expect(runner.lastArguments['confirmButtonText'], 'Open');
    expect(runner.lastArguments['acceptedTypeGroups'], [
      {
        'label': 'PDF',
        'extensions': ['pdf'],
      },
      {
        'label': 'Images',
        'extensions': ['png', 'jpg'],
      },
    ]);
  });

  test('a dismissed open dialog reads as a cancellation, not a failure',
      () async {
    final runner = _FakeRunner(reply: {'paths': <String>[], 'filterIndex': 0});
    runner.install();

    expect(
      await WindowsFileDialogs().openFile(acceptedTypeGroups: [_pdf]),
      isNull,
    );
    expect(
      await WindowsFileDialogs().openFiles(acceptedTypeGroups: [_pdf]),
      isEmpty,
    );
    expect(
      await WindowsFileDialogs().getSaveLocation(acceptedTypeGroups: [_pdf]),
      isNull,
    );
  });

  test('openFiles returns every pick in order', () async {
    final runner = _FakeRunner(reply: {
      'paths': [r'C:\a.pdf', r'C:\b.pdf'],
      'filterIndex': 1,
    });
    runner.install();

    final files = await WindowsFileDialogs().openFiles(
      acceptedTypeGroups: [_pdf],
    );

    expect(files.map((f) => f.path), [r'C:\a.pdf', r'C:\b.pdf']);
    expect(runner.calls.single.method, 'openFiles');
  });

  test('getSaveLocation passes the suggested name and reports the filter',
      () async {
    final runner = _FakeRunner(reply: {
      'paths': [r'C:\docs\out.pdf'],
      'filterIndex': 2,
    });
    runner.install();

    final location = await WindowsFileDialogs().getSaveLocation(
      acceptedTypeGroups: [_pdf, _images],
      options: const SaveDialogOptions(suggestedName: 'out.pdf'),
    );

    expect(location?.path, r'C:\docs\out.pdf');
    expect(location?.activeFilter, _images);
    expect(runner.calls.single.method, 'getSaveLocation');
    expect(runner.lastArguments['suggestedName'], 'out.pdf');
  });

  test('a filter index outside the groups we sent reports no active filter',
      () async {
    final runner = _FakeRunner(reply: {
      'paths': [r'C:\docs\out.pdf'],
      'filterIndex': 7,
    });
    runner.install();

    final location = await WindowsFileDialogs().getSaveLocation(
      acceptedTypeGroups: [_pdf],
    );

    expect(location?.activeFilter, isNull);
  });

  test('a runner without the channel falls back to the old implementation',
      () async {
    final runner = _FakeRunner();
    runner.install();
    final fallback = _FallbackSelector();
    final dialogs = WindowsFileDialogs(fallback: fallback);

    expect((await dialogs.openFile())?.path, r'C:\fallback.pdf');
    expect((await dialogs.openFiles()).single.path, r'C:\fallback.pdf');
    expect((await dialogs.getSaveLocation())?.path, r'C:\fallback.pdf');
    expect(
      await dialogs.getDirectoryPathWithOptions(const FileDialogOptions()),
      r'C:\fallback',
    );
    expect(
      await dialogs.getDirectoryPathsWithOptions(const FileDialogOptions()),
      [r'C:\fallback'],
    );
    expect(fallback.openedFile, isTrue);
    expect(fallback.openedFiles, isTrue);
    expect(fallback.savedLocation, isTrue);
    expect(fallback.pickedDirectory, isTrue);
    expect(fallback.pickedDirectories, isTrue);
  });

  test('a channel-less runner with no fallback cancels instead of throwing',
      () async {
    final runner = _FakeRunner();
    runner.install();
    final dialogs = WindowsFileDialogs();

    expect(await dialogs.openFile(), isNull);
    expect(await dialogs.openFiles(), isEmpty);
    expect(await dialogs.getSaveLocation(), isNull);
    expect(
      await dialogs.getDirectoryPathWithOptions(const FileDialogOptions()),
      isNull,
    );
    expect(
      await dialogs.getDirectoryPathsWithOptions(const FileDialogOptions()),
      isEmpty,
    );
  });

  test('a type group Windows cannot express is rejected up front', () async {
    final runner = _FakeRunner(reply: {'paths': <String>[], 'filterIndex': 0});
    runner.install();

    await expectLater(
      WindowsFileDialogs().openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Bad', mimeTypes: ['x/y'])
        ],
      ),
      throwsArgumentError,
    );
    expect(runner.calls, isEmpty);
  });

  test('directory picks route to the runner too', () async {
    final runner = _FakeRunner(reply: {
      'paths': [r'C:\docs'],
      'filterIndex': 0,
    });
    runner.install();
    final dialogs = WindowsFileDialogs();

    expect(
      await dialogs.getDirectoryPathWithOptions(const FileDialogOptions()),
      r'C:\docs',
    );
    expect(
      await dialogs.getDirectoryPathsWithOptions(const FileDialogOptions()),
      [r'C:\docs'],
    );
    expect(runner.calls.map((c) => c.method),
        ['getDirectoryPath', 'getDirectoryPaths']);
  });

  group('installIfNeeded', () {
    late FileSelectorPlatform original;

    setUp(() {
      original = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = original);
    });

    test('takes over the platform instance on Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(WindowsFileDialogs.installIfNeeded(), isTrue);
      expect(FileSelectorPlatform.instance, isA<WindowsFileDialogs>());

      // Idempotent: a second call must not wrap the instance in itself.
      final installed = FileSelectorPlatform.instance;
      expect(WindowsFileDialogs.installIfNeeded(), isTrue);
      expect(FileSelectorPlatform.instance, same(installed));
    });

    test('leaves every other platform alone', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(WindowsFileDialogs.installIfNeeded(), isFalse);
        expect(FileSelectorPlatform.instance, same(original));
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

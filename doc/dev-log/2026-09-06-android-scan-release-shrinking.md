# Android scan launch failure in the Play release

Reproduced on a Pixel 6 running Android 17 with the Play-installed DartPDF
4.2.0 (35). Both scan actions displayed "Couldn't scan the document" without
opening the scanner. The process log identified an earlier startup failure:

```text
ComponentDiscovery: Invalid component registrar.
Could not instantiate com.google.mlkit.common.internal.CommonComponentRegistrar
Caused by: java.lang.NoSuchMethodException:
  com.google.mlkit.common.internal.CommonComponentRegistrar.<init> []
```

`MlKitInitProvider` could not populate ML Kit's component registry. The first
`flutter_doc_scanner` call then threw a `NullPointerException` during scanner
client construction. The plugin also left its pending result set after this
synchronous exception, so later attempts failed immediately too.

The installed APK confirmed the cause: its manifest still listed
`CommonComponentRegistrar`, and its DEX still contained the named class and
component factory, but **no constructor**. The previous URI read-back and
image-to-PDF fixes run after capture and cannot repair SDK initialization.

AGP 9 enables `android.r8.strictFullModeForKeepRules`: keeping a class no longer
implicitly keeps its default constructor. See the [AGP 9 behavior changes](https://developer.android.com/build/releases/agp-9-0-0-release-notes#behavior-changes).
The app uses AGP 9.1.1, and Flutter enables release shrinking by default.

`app/android/app/proguard-rules.pro` now keeps ML Kit component registrar names
and their public no-argument constructors explicitly. Other code still shrinks
and optimizes normally. The release build explicitly includes the file.

`tool/check_android_scanner.py` reads the actual APK manifest with the SDK's
`apkanalyzer`, finds ML Kit's registered components, and checks their raw DEX
for the public constructors. It fails against the Play-installed broken APK.
The Android release workflow runs it before uploading artifacts. Widget tests
alone cannot cover this failure: they mock native scanning and do not run R8.

## Validation

- All 23 tests in `app/test/doc_scan_io_test.dart` and
  `app/test/doc_scan_menu_test.dart` pass.
- The checker rejects the APK pulled from the Pixel's Play installation and
  passes against the corrected, minified arm64 release APK. Disassembly shows
  `public constructor <init>()V` in `CommonComponentRegistrar` again.
- Installed a minified release test copy under
  `dev.milanko.dartpdf.scantest`, using a temporary Gradle init script to change
  only its application ID. This preserves the Play app's data and documents.
  Scan opened ML Kit's camera UI. Ben completed a scan, the app opened a
  one-page Untitled document, and he confirmed it works. The test app and its
  document were left installed; the Play app still needs the next release.

Fresh-worktree build note: run `flutter build apk --release` with its normal
pub/registration step. The first `--no-pub` build picked up a test-generated
`GeneratedPluginRegistrant` containing `integration_test`, which release mode
excludes from Gradle dependencies. Regenerating for release resolved that local
build failure; no plugin source patch was needed for this fix.

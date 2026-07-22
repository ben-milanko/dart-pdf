# dart_pdf_editor_assets

Optional bundled assets for [`dart_pdf_editor`](../dart_pdf_editor): the six
editor fonts offered by the font menu (and used as composite-text fallbacks) and
the prebuilt **web render worker**.

These assets add roughly **1.7 MB** to a build (about 1.26 MB of fonts and
0.48 MB of worker, compressed). They live in this separate package - not in
`dart_pdf_editor` - so an app that only *views* PDFs never bundles them: Flutter
includes a package's declared assets on every build target, so the only way to
make these opt-in is to keep them out of the package every consumer depends on.

## Full-featured editor (the historical default)

Add both packages and register the assets once at startup, before opening a
viewer:

```yaml
dependencies:
  dart_pdf_editor: ^2.1.0
  dart_pdf_editor_assets: ^2.1.0
```

```dart
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';

void main() {
  registerBundledEditorAssets();
  runApp(const MyApp());
}
```

That restores exactly what a `dart_pdf_editor` app got before the split: the
bundled font catalogue in every font menu, DejaVu fallbacks for composite-text
editing, and the off-main-thread web worker.

## Size-minimal viewer

Depend on `dart_pdf_editor` **only** and skip the registration call. The font
menu still offers the base-14 families, the fonts already embedded in the open
document, host/platform fonts, and any custom font the app loads; the web worker
falls back to main-thread rendering (or an app-supplied worker URL). See the
capability → asset matrix in the
[`dart_pdf_editor` README](../dart_pdf_editor/README.md#optional-bundled-assets).

## Selective registration

`registerBundledEditorAssets(fonts: false)` or `webWorker: false` registers only
one group - e.g. a web app that wants the worker but supplies its own font
catalogue, or a native app that wants the fonts but no worker asset.

## Licences

The font licences are in `assets/fonts/*-LICENSE.txt`. DejaVu is a permissive
Bitstream Vera / Arev licence; Fira Sans, Spectral and Lobster are the SIL Open
Font Licence.

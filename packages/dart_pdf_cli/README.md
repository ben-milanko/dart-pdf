# dart_pdf_cli

Pure-Dart command line and Model Context Protocol tools for inspecting PDFs
with the [dart-pdf](https://github.com/ben-milanko/dart-pdf) engine. The
`dartpdf` executable runs on the Dart VM and does not import Flutter or
`dart:ui`.

The CLI and MCP adapter call the same transport-independent
`DartPdfService` handlers. The MCP layer contains no duplicate PDF logic.

## Installation

From a checkout:

```sh
dart run packages/dart_pdf_cli/bin/dartpdf.dart --help
```

Once published, install the executable globally:

```sh
dart pub global activate dart_pdf_cli
dartpdf --help
```

The DartPDF desktop app also ships the same self-contained native executable:

| Desktop build | CLI/MCP executable |
|---|---|
| macOS app | `/Applications/DartPDF.app/Contents/MacOS/dartpdf-cli` |
| Windows installer | `%LOCALAPPDATA%\Programs\DartPDF\dartpdf.exe` |
| Windows portable | `dartpdf.exe` beside `dart_pdf_editor_app.exe` |
| Linux tarball / AppImage payload | `dartpdf-cli` beside `dart_pdf_editor_app` |
| Arch `dartpdf-bin` | `/usr/bin/dartpdf-cli` |
| Flatpak | `flatpak run --command=dartpdf-cli dev.milanko.dartpdf` |
| Snap | `dartpdf.cli` |

The macOS and Windows app installers do not modify the user's shell `PATH`;
use the explicit path above when registering their copy with an MCP host.

## Commands

All successful commands write JSON to stdout. Diagnostics go to stderr and
failures use non-zero exit codes. Output is indented by default; `--json`
selects compact JSON for scripts and agents.

```sh
dartpdf inspect input.pdf --json
dartpdf text input.pdf --pages 1-5,8 --json
dartpdf forms list input.pdf --json
dartpdf annotations list input.pdf --pages 1-5 --json
```

Page numbers are one-based. A missing page range reads at most the configured
page limit. An explicit range over that limit is rejected rather than silently
changed.

`inspect` returns the PDF version, information-dictionary metadata, page
count, encryption state, form and annotation counts, and compact signature
state. It does not perform trust-store validation.

`text`, `forms list`, and `annotations list` have hard result limits. The JSON
reports `truncated: true` when a page, character, field, annotation, or
annotation-text limit was reached. Password-form values are never returned.

## Passwords

Passwords are deliberately not accepted as process arguments, where they can
appear in shell history and process listings. Select at most one protected
source:

```sh
printf '%s\n' "$PDF_PASSWORD" | dartpdf inspect secured.pdf --password-stdin --json
dartpdf inspect secured.pdf --password-env PDF_PASSWORD --json
dartpdf inspect secured.pdf --password-file /secure/password.txt --json
```

Only one trailing line ending is removed from stdin or password-file input;
other whitespace remains part of the password.

## JSON compatibility

Every result carries `schemaVersion`. Version 1 has these compatibility rules:

- existing keys keep their meaning and type within the major schema version;
- new optional keys may be added;
- array order is deterministic and follows document/page order unless the
  requested page range specifies another order;
- consumers must check `truncated` before assuming a result is complete.

## MCP server

Run the stdio adapter with one or more allowed filesystem roots:

```sh
dartpdf mcp --root /work/pdfs --root /work/contracts
```

With no `--root`, only the current directory is accessible. Input PDF and
password-file paths are resolved through symlinks and rejected unless the
resolved file is inside an allowed root. Relative paths are tried against the
configured roots in command-line order. The server exposes four read-only,
idempotent tools:

- `inspect_pdf`
- `extract_pdf_text`
- `list_pdf_forms`
- `list_pdf_annotations`

Tools return structured JSON plus the MCP text fallback. They return paths and
metadata only; complete PDFs are never base64-encoded into responses.

Register a globally activated executable with Codex:

```sh
codex mcp add dartpdf -- dartpdf mcp --root "$PWD"
```

Or register the copy bundled with the macOS desktop app:

```sh
codex mcp add dartpdf -- \
  /Applications/DartPDF.app/Contents/MacOS/dartpdf-cli mcp --root "$PWD"
```

For a source checkout, register the Dart invocation instead:

```sh
codex mcp add dartpdf -- \
  dart run packages/dart_pdf_cli/bin/dartpdf.dart mcp --root "$PWD"
```

MCP password sources are `passwordEnv` or `passwordFile`; raw password tool
arguments are not accepted. Hosts can therefore apply their own approval and
secret policies without exposing the password in the server command.

## Scope

This first contract is read-only and VM-only. Editing commands can be added on
top of the same service boundary after the JSON contract settles. Page raster
export is intentionally outside this package until the pure-Dart software
renderer work in [#684](https://github.com/ben-milanko/dart-pdf/issues/684)
lands (the broader conversion roadmap is [#369](https://github.com/ben-milanko/dart-pdf/issues/369)).

# Changelog

## 0.5.1

- Update dependency constraints for the compatible dart-pdf 8.1.0 suite. No public API changes.

## 0.5.0

- Align dependency constraints with the dart-pdf 8.0.0 suite.


## 0.4.0

- Raise dependency constraints to the dart-pdf 7.0.0 package suite.

## 0.3.0

- Align dependency constraints with the dart-pdf 6.0.0 package suite.

## 0.2.2

- Align dependency constraints with the dart-pdf 5.1.1 package suite.

## 0.2.1

- Align dependency constraints with the dart-pdf 5.1.0 package suite.

## 0.2.0

- The forms listing reports the whole selection of a multi-select list box:
  such a field carries `multiSelect: true` and a `values` array alongside
  `value` (still the first selection), with `valuesTruncated` when the text
  budget cut the list short.
- Align dependency constraints with the dart-pdf 5.0.0 package suite.

## 0.1.8

- Align dependency constraints with the dart-pdf 4.5.0 package suite.

## 0.1.7

- Align dependency constraints with the dart-pdf 4.4.0 package suite.

## 0.1.6

- Align dependency constraints with the dart-pdf 4.3.0 package suite.

## 0.1.5

- Align the command-line and MCP sidecar with the 4.2.0 package suite. No
  command, JSON, or MCP protocol changes since 0.1.4.

## 0.1.4

- Align the command-line and MCP sidecar with the 4.1.0 package suite. No
  command, JSON, or MCP protocol changes since 0.1.3.

## 0.1.3

- Align the command-line and MCP sidecar with the 4.0.0 package suite. No
  command, JSON, or MCP protocol changes since 0.1.2.

## 0.1.2

- Align the command-line and MCP sidecar with the 3.8.0 package suite. No
  command or protocol changes since 0.1.1.

## 0.1.1

- Align the command-line and MCP sidecar with the 3.7.0 package suite.

## 0.1.0

- Add the VM-only `dartpdf` executable with JSON `inspect`, bounded `text`,
  `forms list`, and `annotations list` commands.
- Add a stdio MCP adapter exposing the same handlers as four read-only tools.
- Restrict MCP file access to configured roots and support passwords through
  stdin, environment variables, or protected files rather than process
  arguments.

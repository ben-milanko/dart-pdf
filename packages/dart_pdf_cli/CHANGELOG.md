# Changelog

## 0.1.1

- Align the command-line and MCP sidecar with the 3.7.0 package suite.

## 0.1.0

- Add the VM-only `dartpdf` executable with JSON `inspect`, bounded `text`,
  `forms list`, and `annotations list` commands.
- Add a stdio MCP adapter exposing the same handlers as four read-only tools.
- Restrict MCP file access to configured roots and support passwords through
  stdin, environment variables, or protected files rather than process
  arguments.

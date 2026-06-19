# Codex cloud environment

Configure the repository's Codex cloud environment with these scripts:

Setup script:

```bash
bash tool/codex/setup.sh
```

Maintenance script:

```bash
bash tool/codex/maintenance.sh
```

The setup script pins Flutter to `.fvmrc`, persists `FLUTTER_HOME` and `PATH`
for the agent phase, installs a small `fvm` compatibility shim for the commands
listed in `AGENTS.md`, creates the legacy `~/fvm/versions/<version>` SDK path
those instructions also mention, precaches Flutter web/Linux artifacts while
setup still has internet, and runs `flutter pub get` for the pub workspace.

The maintenance script is intended for resumed cached containers. It skips apt
package installation and refreshes the Flutter/FVM/Pub setup for the branch
checked out by the task.

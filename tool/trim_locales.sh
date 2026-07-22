#!/usr/bin/env bash
# Trim the localization bundles to a chosen set of locales so a release build
# compiles only those languages instead of every bundled one.
#
#   tool/trim_locales.sh <locale> [<locale> ...]   # keep only these (+ en)
#   tool/trim_locales.sh --restore                 # put the full set back
#   tool/trim_locales.sh --list                    # show bundled locales
#
# Why: a Flutter dependency that ships its own LocalizationsDelegate compiles
# ALL its locales into the app - the host's `supportedLocales` only affects
# runtime resolution, not what the AOT snapshot bundles. On web,
# `use-deferred-loading` (already set in each l10n.yaml) means only the active
# locale's JS chunk downloads, so trimming is optional there. On mobile/desktop
# AOT there is no such split, so this script is the lever for native size:
# regenerate the checked-in gen-l10n output for just the locales you ship.
#
# Workflow for a release:
#   tool/trim_locales.sh en es fr de     # keep English + Spanish/French/German
#   fvm flutter build <target> ...        # build with only those compiled in
#   tool/trim_locales.sh --restore        # regenerate the full set (or: git
#                                          # checkout the lib/l10n dirs)
#
# English (the template locale) is always kept - it is the fallback that the
# pdfL10n()/appL10n() wrappers construct directly. The script never deletes an
# .arb file; it only regenerates the produced Dart, so `--restore` (or a plain
# `flutter gen-l10n`) always brings every language back.
#
# See doc/i18n.md for the full picture, including the host-merge alternative
# for external apps that consume the published package.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

FLUTTER=flutter
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"
fi

# Each localization bundle: "<dir>|<arb-prefix>|<generated-prefix>".
# arb files are  <arb-prefix>_<locale>.arb  and gen-l10n emits
# <generated-prefix>.dart (the delegate) + <generated-prefix>_<locale>.dart.
BUNDLES=(
  "packages/dart_pdf_editor|dart_pdf_editor|dart_pdf_editor_localizations"
  "app|app|app_localizations"
  "packages/dart_pdf_editor/example|app|app_localizations"
)

readonly TEMPLATE_LOCALE="en"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

# Locale embedded in a "<prefix>_<locale>.<ext>" basename.
locale_of() { # <basename> <prefix>
  local base="$1" prefix="$2"
  base="${base%.*}"          # strip extension
  echo "${base#${prefix}_}"  # strip "<prefix>_"
}

list_locales() {
  for entry in "${BUNDLES[@]}"; do
    IFS='|' read -r dir arb_prefix _gen <<<"$entry"
    local arbdir="$ROOT/$dir/lib/l10n" locs=()
    for f in "$arbdir/${arb_prefix}"_*.arb; do
      [ -e "$f" ] || continue
      locs+=("$(locale_of "$(basename "$f")" "$arb_prefix")")
    done
    printf '%s: %s\n' "$dir" "${locs[*]:-(none)}"
  done
}

regenerate_all() { # --restore: rebuild every bundle from all its ARBs
  for entry in "${BUNDLES[@]}"; do
    IFS='|' read -r dir _arb _gen <<<"$entry"
    echo "restoring $dir ..."
    ( cd "$ROOT/$dir" && $FLUTTER gen-l10n >/dev/null )
  done
  echo "Full locale set regenerated."
}

trim() { # <keep-locale>...
  local keep=(" $TEMPLATE_LOCALE ")
  for l in "$@"; do keep+=(" $l "); done
  local keepstr="${keep[*]}"

  for entry in "${BUNDLES[@]}"; do
    IFS='|' read -r dir arb_prefix gen_prefix <<<"$entry"
    local arbdir="$ROOT/$dir/lib/l10n"
    local stash removed=()
    stash="$(mktemp -d)"
    # A trap per bundle guarantees the ARBs come back even on failure.
    # shellcheck disable=SC2064
    trap "mv \"$stash\"/*.arb \"$arbdir\"/ 2>/dev/null || true; rmdir \"$stash\" 2>/dev/null || true" RETURN

    # Move locales we are NOT keeping out of the arb-dir so gen-l10n omits them.
    for f in "$arbdir/${arb_prefix}"_*.arb; do
      [ -e "$f" ] || continue
      local loc; loc="$(locale_of "$(basename "$f")" "$arb_prefix")"
      case "$keepstr" in
        *" $loc "*) : ;;                    # keep
        *) mv "$f" "$stash/"; removed+=("$loc") ;;
      esac
    done

    ( cd "$ROOT/$dir" && $FLUTTER gen-l10n >/dev/null )

    # Restore the ARBs (source of truth stays intact) ...
    mv "$stash"/*.arb "$arbdir"/ 2>/dev/null || true
    rmdir "$stash" 2>/dev/null || true
    trap - RETURN

    # ... then drop the now-orphaned generated locale classes gen-l10n left
    # behind (it regenerates the delegate but never deletes stale outputs).
    for f in "$arbdir/${gen_prefix}"_*.dart; do
      [ -e "$f" ] || continue
      local loc; loc="$(locale_of "$(basename "$f")" "$gen_prefix")"
      case "$keepstr" in
        *" $loc "*) : ;;
        *) rm -f "$f" ;;
      esac
    done

    local kept_shown; kept_shown="$(echo "$keepstr" | xargs -n1 | awk '!seen[$0]++' | xargs)"
    printf '%s: kept [%s]' "$dir" "$kept_shown"
    [ ${#removed[@]} -gt 0 ] && printf ' - removed [%s]' "${removed[*]}"
    printf '\n'
  done

  echo
  echo "Generated output trimmed. Build now, then 'tool/trim_locales.sh"
  echo "--restore' (or 'git checkout' the lib/l10n dirs) to put them back."
}

case "${1:-}" in
  ""|-h|--help) usage; exit 0 ;;
  --list) list_locales; exit 0 ;;
  --restore) regenerate_all; exit 0 ;;
  -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
  *) trim "$@" ;;
esac

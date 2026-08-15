#!/bin/sh

# Prints 1 when Flutter's base64-encoded DART_DEFINES contains the windowing
# runtime feature, otherwise 0. macOS base64 uses -D; GNU base64 uses --decode.
if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 is required to decode Flutter's DART_DEFINES" >&2
  exit 69
fi

decode_base64() {
  if decoded=$(printf '%s' "$1" | base64 --decode 2>/dev/null); then
    printf '%s' "$decoded"
    return
  fi
  printf '%s' "$1" | base64 -D 2>/dev/null
}

old_ifs=$IFS
IFS=,
for encoded in $1; do
  decoded=$(decode_base64 "$encoded") || continue
  case "$decoded" in
    FLUTTER_ENABLED_FEATURE_FLAGS=*)
      flags=${decoded#FLUTTER_ENABLED_FEATURE_FLAGS=}
      for flag in $flags; do
        if [ "$flag" = windowing ]; then
          printf '1\n'
          exit 0
        fi
      done
      ;;
  esac
done
IFS=$old_ifs
printf '0\n'

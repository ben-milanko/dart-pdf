#!/usr/bin/env bash
#
# Cache-bust Flutter web URLs that are stable across builds.
#
# Run after `flutter build web ...` and before deploying or zipping build/web.
# Firebase Hosting can then cache JS/WASM/font files for a year while the small
# bootstrap/manifests are served no-store and point at fresh content hashes.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [build-web-dir]" >&2
  exit 64
fi

BUILD_DIR="${1:-build/web}"
if [[ "$BUILD_DIR" != /* ]]; then
  BUILD_DIR="$(pwd)/$BUILD_DIR"
fi
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

BOOTSTRAP="$BUILD_DIR/flutter_bootstrap.js"
MAIN_JS="$BUILD_DIR/main.dart.js"
FONT_MANIFEST="$BUILD_DIR/assets/FontManifest.json"
INDEX_HTML="$BUILD_DIR/index.html"

if [[ ! -f "$BOOTSTRAP" ]]; then
  echo "ERROR: $BOOTSTRAP not found. Run 'flutter build web' first." >&2
  exit 1
fi

hash_file() {
  local file="$1"
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$file" | cut -c1-12
  elif command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | awk '{print $1}' | cut -c1-12
  else
    echo "ERROR: neither md5 nor md5sum is available" >&2
    exit 1
  fi
}

perl_replace_string_url() {
  local file="$1"
  local path="$2"
  local hash="$3"

  [[ -f "$file" ]] || return 0
  CACHE_BUST_PATH="$path" CACHE_BUST_HASH="$hash" perl -0pi -e '
    my $path = $ENV{CACHE_BUST_PATH};
    my $hash = $ENV{CACHE_BUST_HASH};
    @ARGV = ();
    my $quoted = quotemeta($path);
    s/"$quoted(?:\?v=[0-9a-f]+)?"/"$path?v=$hash"/g;
  ' "$file"
}

replace_in_compiled_dart() {
  local path="$1"
  local hash="$2"

  while IFS= read -r -d '' js_file; do
    perl_replace_string_url "$js_file" "$path" "$hash"
  done < <(find "$BUILD_DIR" -maxdepth 1 \
    \( -name 'main.dart.js' -o -name 'main.dart.js_*.js' -o -name 'main.dart.mjs' \) \
    -type f -print0)
}

echo "Cache-busting Flutter web build in $BUILD_DIR"

for path in main.dart.wasm main.dart.mjs main.dart.js; do
  file="$BUILD_DIR/$path"
  [[ -f "$file" ]] || continue
  hash="$(hash_file "$file")"
  echo "  $path  ?v=$hash"
  perl_replace_string_url "$BOOTSTRAP" "$path" "$hash"
done

# The render-worker URLs must be rewritten BEFORE the deferred parts are hashed
# and renamed below. The app references the worker from `dart_pdf_editor`, which
# lives in a DEFERRED part rather than main.dart.js, and hashing a part before
# its contents are final breaks two ways:
#
#   * the content-addressed filename no longer matches the content, and
#   * a deploy that changes ONLY the worker leaves the part's hash - and so the
#     part URL - identical, so browsers keep the old part and the old worker URL.
#
# That is not hypothetical: for as long as the rename ran first, the worker URL
# was never busted at all (the rename left files ending `.<hash>.js`, which the
# old `main.dart.js_*.part.js` search no longer matched). Firebase serves
# assets/**.js with a year max-age precisely because it is assumed busted, so
# returning users kept one worker build across every deploy and no worker-side
# change reached them. See doc/dev-log/2026-07-26-record-image-decode-reuse-451.md.
if [[ -f "$MAIN_JS" ]]; then
  worker="$BUILD_DIR/pdf_render_worker.dart.js"
  if [[ -f "$worker" ]]; then
    hash="$(hash_file "$worker")"
    echo "  pdf_render_worker.dart.js  ?v=$hash"
    replace_in_compiled_dart "pdf_render_worker.dart.js" "$hash"
  fi
fi

asset_worker_path="assets/packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js"
asset_worker="$BUILD_DIR/$asset_worker_path"
if [[ -f "$asset_worker" ]]; then
  hash="$(hash_file "$asset_worker")"
  echo "  $asset_worker_path  ?v=$hash"
  replace_in_compiled_dart "$asset_worker_path" "$hash"
fi

# Only now, with every in-part URL final, hash and rename the deferred parts.
if [[ -f "$MAIN_JS" ]]; then
  while IFS= read -r -d '' file; do
    path="$(basename "$file")"
    hash="$(hash_file "$file")"
    hashed_path="${path%.js}.$hash.js"
    echo "  $path  -> $hashed_path"
    # dart2js resolves deferred-part names as URI *paths*. A query string in
    # the compiled literal is therefore escaped to `%3Fv=...`, making the
    # browser request a nonexistent file. Give deferred parts content-addressed
    # filenames instead; ordinary entrypoints can continue to use queries.
    mv "$file" "$BUILD_DIR/$hashed_path"
    CACHE_BUST_PATH="$path" CACHE_BUST_HASHED_PATH="$hashed_path" perl -0pi -e '
      my $path = quotemeta($ENV{CACHE_BUST_PATH});
      my $hashed = $ENV{CACHE_BUST_HASHED_PATH};
      s/"$path(?:\?v=[0-9a-f]+)?"/"$hashed"/g;
    ' "$MAIN_JS"
  done < <(find "$BUILD_DIR" -maxdepth 1 -name 'main.dart.js_*.part.js' -type f -print0 | sort -z)
fi

if grep -qE '"main\.dart\.(wasm|mjs|js)"' "$BOOTSTRAP"; then
  echo "ERROR: flutter_bootstrap.js still contains un-busted entrypoint references:" >&2
  grep -nE '"main\.dart\.(wasm|mjs|js)"' "$BOOTSTRAP" >&2
  exit 1
fi

if [[ -f "$MAIN_JS" ]] && grep -qE '"main\.dart\.js_[0-9]+\.part\.js"' "$MAIN_JS"; then
  echo "ERROR: main.dart.js still contains un-busted deferred part references:" >&2
  grep -nE '"main\.dart\.js_[0-9]+\.part\.js"' "$MAIN_JS" >&2
  exit 1
fi

# dart2wasm is outside everything above. Its string literals are not stored as
# plain UTF-8/UTF-16 in the module - a `dart compile wasm` of a program holding
# this very URL contains no byte sequence matching it in either encoding - so a
# wasm build's worker reference can be neither rewritten by the substitutions
# above nor detected by the assertion below. It would ship with the bare,
# stable URL that Firebase serves `max-age=31536000`, and every returning
# browser would keep whatever it cached first for a year: an old worker, or the
# committed placeholder, which throws on load and degrades the whole session to
# main-thread rendering (issue #699). That failure is silent by construction,
# which is exactly what this script exists to prevent - so refuse it here
# rather than deploy it.
if [[ -f "$BUILD_DIR/main.dart.wasm" && "${WORKER_URL_REVALIDATED:-0}" != "1" ]]; then
  echo "ERROR: this is a dart2wasm build (main.dart.wasm), whose render-worker" \
    "URL cannot be cache-busted by string substitution and cannot be" \
    "verified. Either build without --wasm, or serve" \
    "pdf_render_worker.dart.js with revalidation (Cache-Control: no-cache)" \
    "in the hosting config and re-run with WORKER_URL_REVALIDATED=1." >&2
  exit 1
fi

# The render worker is a separate ~1 MB bundle that the app fetches by URL. An
# un-busted reference is invisible - the app keeps working, on whatever worker
# build the browser cached first - so assert rather than trust. Checks every
# compiled unit, including the renamed deferred parts, because the reference
# lives in a part and not in main.dart.js.
while IFS= read -r -d '' js_file; do
  if grep -qE '"[^"]*pdf_render_worker\.dart\.js"' "$js_file"; then
    echo "ERROR: $(basename "$js_file") references the render worker without a" \
      "?v= hash. Browsers cache it for a year, so worker-side changes would" \
      "never reach a returning user:" >&2
    grep -oE '"[^"]*pdf_render_worker\.dart\.js"' "$js_file" | sort -u >&2
    exit 1
  fi
done < <(find "$BUILD_DIR" -maxdepth 1 \
  \( -name 'main.dart.js' -o -name 'main.dart.js_*.js' -o -name 'main.dart.mjs' \) \
  -type f -print0)

if [[ -f "$FONT_MANIFEST" ]]; then
  echo "Cache-busting fonts in assets/FontManifest.json"
  FONT_MANIFEST="$FONT_MANIFEST" INDEX_HTML="$INDEX_HTML" BUILD_DIR="$BUILD_DIR" perl <<'PERL'
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use JSON::PP qw(decode_json encode_json);

my $manifest_path = $ENV{FONT_MANIFEST};
my $index_path = $ENV{INDEX_HTML};
my $build_dir = $ENV{BUILD_DIR};

open my $fh, '<:raw', $manifest_path or die "open $manifest_path: $!";
my $json = do { local $/; <$fh> };
close $fh;

my $manifest = decode_json($json);
my %asset_hashes;

for my $family (@$manifest) {
  for my $font (@{$family->{fonts} // []}) {
    my $asset = $font->{asset} // next;
    $asset =~ s/\?v=[0-9a-f]+\z//;
    my $file = "$build_dir/assets/$asset";
    if (!-f $file) {
      warn "  WARNING: $asset is listed but missing at $file; skipping\n";
      next;
    }
    open my $ffh, '<:raw', $file or die "open $file: $!";
    my $bytes = do { local $/; <$ffh> };
    close $ffh;
    my $hash = substr(md5_hex($bytes), 0, 12);
    $asset_hashes{$asset} = $hash;
    $font->{asset} = "$asset?v=$hash";
    print "  $asset  ?v=$hash\n";
  }
}

open my $out, '>:raw', $manifest_path or die "write $manifest_path: $!";
print {$out} encode_json($manifest);
close $out;

if (-f $index_path && %asset_hashes) {
  open my $ifh, '<:raw', $index_path or die "open $index_path: $!";
  my $html = do { local $/; <$ifh> };
  close $ifh;
  for my $asset (keys %asset_hashes) {
    my $hash = $asset_hashes{$asset};
    my $quoted = quotemeta("assets/$asset");
    $html =~ s/($quoted)(?:\?v=[0-9a-f]+)?"/$1?v=$hash"/g;
  }
  open my $io, '>:raw', $index_path or die "write $index_path: $!";
  print {$io} $html;
  close $io;
}
PERL
else
  echo "WARNING: $FONT_MANIFEST not found; skipping font cache-busting" >&2
fi

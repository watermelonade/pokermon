#!/usr/bin/env bash
# Exports release builds of every preset in export_presets.cfg, headless:
#   build/linux/AFriendInNeed.x86_64 + .pck    (native on the Steam Deck)
#   build/windows/AFriendInNeed.exe + .pck     (Windows, and Proton on the Deck)
#
# Usage: scripts/export.sh [linux|windows|all] [--debug]
# Godot: $GODOT, else `godot` on PATH. The export templates for the exact
# same version must be installed (README.md "Building" says where).
#
# Godot's headless export prints errors but has exited 0 on some failures in
# past versions, so this checks that every expected file exists and isn't
# empty instead of trusting the exit code alone.
set -euo pipefail

cd "$(dirname "$0")/.."

target="all"
mode="--export-release"
for arg in "$@"; do
  case "$arg" in
    linux|windows|all) target="$arg" ;;
    --debug) mode="--export-debug" ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "export.sh: unknown argument '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

die() { echo "export.sh: $*" >&2; exit 1; }

G="${GODOT:-$(command -v godot || true)}"
if [ -z "$G" ] || [ ! -x "$G" ]; then
  die "no Godot found: set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 or put 'godot' on PATH"
fi

# "4.7.2.stable.official.abc123" -> "4.7.2.stable": the templates folder name.
version="$("$G" --headless --version 2>/dev/null | tail -n1 | cut -d. -f1-4)"
[ -n "$version" ] || die "couldn't read the version of $G"
case "$(uname -s)" in
  Darwin) tdir="$HOME/Library/Application Support/Godot/export_templates/$version" ;;
  MINGW*|MSYS*|CYGWIN*) tdir="${APPDATA:-}/Godot/export_templates/$version" ;;
  *) tdir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version" ;;
esac
[ -f "$tdir/version.txt" ] || die "no export templates for Godot $version in $tdir.
  Download Godot_v${version/.stable/-stable}_export_templates.tpz from
  https://github.com/godotengine/godot/releases and unzip its templates/ folder there."

[ -f export_presets.cfg ] || die "export_presets.cfg is missing"

# A fresh checkout has no .godot/ import cache; exporting without one can
# miss class_name scripts and imported resources.
echo "== Importing the project"
"$G" --headless --path . --import >/dev/null 2>&1 || die "import failed: run '$G --headless --path . --import' to see why"

export_one() {  # preset name, output path, template file
  local preset="$1" out="$2" template="$3"
  [ -f "$tdir/$template" ] || die "template $template missing from $tdir"
  mkdir -p "$(dirname "$out")"
  rm -f "$out" "${out%.*}.pck"
  echo "== Exporting '$preset' -> $out"
  local log
  log="$(mktemp)"
  if ! "$G" --headless --path . "$mode" "$preset" "$out" >"$log" 2>&1; then
    cat "$log" >&2; rm -f "$log"
    die "Godot failed to export '$preset' (log above)"
  fi
  if grep -qE "^(ERROR|SCRIPT ERROR)" "$log"; then
    grep -E -A2 "^(ERROR|SCRIPT ERROR)" "$log" >&2
    echo "export.sh: warning: Godot logged errors exporting '$preset' (above)" >&2
  fi
  rm -f "$log"
  for f in "$out" "${out%.*}.pck"; do
    [ -s "$f" ] || die "'$preset' didn't produce $f"
  done
  du -h "$out" "${out%.*}.pck" | sed 's/^/   /'
}

case "$target" in
  linux|all) export_one "Linux" build/linux/AFriendInNeed.x86_64 \
               "linux_$( [ "$mode" = --export-debug ] && echo debug || echo release).x86_64" ;;
esac
case "$target" in
  windows|all) export_one "Windows" build/windows/AFriendInNeed.exe \
                 "windows_$( [ "$mode" = --export-debug ] && echo debug || echo release)_x86_64.exe" ;;
esac
echo "== Done"

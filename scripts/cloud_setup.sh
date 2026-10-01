#!/usr/bin/env bash
# Session setup for Claude Code on the web (Linux, no display, no audio).
# Runs from the SessionStart hook in .claude/settings.json and does nothing
# on a local machine. Downloads the Godot version this project uses, puts it
# on PATH as `godot`, and imports the project so class_name scripts resolve.
# Idempotent; output goes to /tmp/cloud_setup.log.
[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/..}" || exit 0
LOG=/tmp/cloud_setup.log
VERSION=4.7.2-stable
DIR="$HOME/.local/godot-$VERSION"
BIN="$DIR/Godot_v${VERSION}_linux.x86_64"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  if curl -sSL --max-time 600 -o "$DIR/godot.zip" \
      "https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip" >>"$LOG" 2>&1 \
      && unzip -o -q "$DIR/godot.zip" -d "$DIR" >>"$LOG" 2>&1; then
    rm -f "$DIR/godot.zip"
  else
    echo "Cloud setup: couldn't download Godot $VERSION (see $LOG)"
    exit 0
  fi
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$BIN" "$HOME/.local/bin/godot"
[ -w /usr/local/bin ] && ln -sf "$BIN" /usr/local/bin/godot
"$BIN" --headless --path . --import >>"$LOG" 2>&1
echo "Cloud setup: Godot $VERSION ready as 'godot'."

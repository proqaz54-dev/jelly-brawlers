#!/usr/bin/env bash
# Build the Android APK locally without the Godot editor (Linux / macOS / WSL).
set -e

GODOT_VERSION=4.2.2-stable
SHORT_VERSION=4.2.2.stable
GODOT_BIN_DIR="$(dirname "$0")/.godot-bin"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPL_DIR="$HOME/.local/share/godot/export_templates/${SHORT_VERSION}"

mkdir -p "$GODOT_BIN_DIR"

if [ ! -x "$GODOT_BIN_DIR/godot" ]; then
  echo "== downloading Godot ${GODOT_VERSION} =="
  case "$(uname -m)" in
    aarch64|arm64) ARCH="arm64" ;;
    *)             ARCH="x86_64" ;;
  esac
  wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.${ARCH}.zip" -O /tmp/godot.zip
  unzip -q /tmp/godot.zip -d "$GODOT_BIN_DIR"
  mv "$GODOT_BIN_DIR"/Godot_v*_linux.${ARCH} "$GODOT_BIN_DIR/godot"
fi

if [ ! -f "$TEMPL_DIR/android_debug.apk" ]; then
  echo "== downloading export templates =="
  wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz" -O /tmp/templates.tpz
  mkdir -p /tmp/tps && cd /tmp/tps && unzip -q /tmp/templates.tpz
  mkdir -p "$(dirname "$TEMPL_DIR")"
  mv /tmp/tps/templates "$TEMPL_DIR"
fi

mkdir -p "$PROJECT_DIR/build"
cd "$PROJECT_DIR"

echo "== importing project =="
"$GODOT_BIN_DIR/godot" --headless --path "$PROJECT_DIR" --import

echo "== exporting APK =="
"$GODOT_BIN_DIR/godot" --headless --path "$PROJECT_DIR" \
  --export-debug "Android" build/jelly-brawlers.apk

echo "== done: $PROJECT_DIR/build/jelly-brawlers.apk =="
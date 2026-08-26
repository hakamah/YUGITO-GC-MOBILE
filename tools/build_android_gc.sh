#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-godot}"
OUT="build/android/YUGITO_GC_Mobile.apk"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  echo "ERREUR: Godot 4.7.2 introuvable. Définis GODOT_BIN=/chemin/vers/Godot."
  exit 2
fi

mkdir -p "$(dirname "$OUT")"
"$GODOT_BIN" --headless --path "$ROOT" --editor --quit-after 2
"$GODOT_BIN" --headless --path "$ROOT" --export-debug "Android YUGITO GC" "$OUT"

test -s "$OUT"
echo "APK créée: $OUT"
sha256sum "$OUT"

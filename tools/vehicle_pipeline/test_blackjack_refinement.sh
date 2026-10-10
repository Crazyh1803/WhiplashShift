#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN=${GODOT_BIN:-/home/crazyh/.local/share/godot-bin/4.6.3/Godot_v4.6.3-stable_linux.x86_64}
import_log=$(mktemp /tmp/blackjack-refined-import.XXXXXX)
timeout 120 "$GODOT_BIN" --headless --import --path godot > "$import_log" 2>&1 || { tail -n 28 "$import_log"; exit 1; }
if grep -Eq '(^ERROR:|SCRIPT ERROR:|Parse Error:)' "$import_log"; then
  tail -n 28 "$import_log"
  exit 1
fi
result=0
for scene in test_main cpu_main blackjack_refined_tests; do
  timeout 120 "$GODOT_BIN" --headless --fixed-fps 120 --path godot "res://tests/${scene}.tscn" || result=1
done
exit "$result"

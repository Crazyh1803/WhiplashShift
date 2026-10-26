#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN=${GODOT_BIN:-godot}
import_log=$(mktemp /tmp/blackjack-refined-import.XXXXXX)
timeout 120 "$GODOT_BIN" --headless --import --path godot > "$import_log" 2>&1 || { tail -n 28 "$import_log"; exit 1; }
if grep -Eq '(^ERROR:|SCRIPT ERROR:|Parse Error:)' "$import_log"; then
  tail -n 28 "$import_log"
  exit 1
fi
result=0
for scene in vehicle_audio_tests vehicle_feedback_tests vehicle_effects_tests test_main viscera_response_tests rubble_response_tests armor_response_tests coolant_response_tests effluent_response_tests ichor_response_tests track_visual_tests viscera_pit_tests boulder_motion_tests item_tests weapon_attachment_tests deployment_oil_tests racecraft_tests cpu_main race_tests course_cues_tests camera_tests corner_tests blackjack_refined_tests blackjack_blueprint_tests consolidation_tests nightshift_blueprint_tests ramjet_blueprint_tests boilerfang_blueprint_tests helix_blueprint_tests knifeedge_blueprint_tests; do
  # CPU coverage runs all difficulty tiers; race coverage drives three laps and a retry.
  # CPU coverage simulates 420 seconds per tier; Windows needs over 360 seconds for all tiers.
  scene_timeout=120
  case "$scene" in cpu_main|race_tests) scene_timeout=900 ;; esac
  scene_log=$(mktemp /tmp/whiplash-tests.XXXXXX)
  timeout "$scene_timeout" "$GODOT_BIN" --headless --fixed-fps 120 --path godot "res://tests/${scene}.tscn" > "$scene_log" 2>&1 || result=1
  cat "$scene_log"
  if grep -Eq '(^ERROR:|SCRIPT ERROR:|Parse Error:)' "$scene_log"; then result=1; fi
  rm -f "$scene_log"
done
exit "$result"

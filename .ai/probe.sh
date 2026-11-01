#!/usr/bin/env bash
# scratch: import then run one Godot scene (headless). Usage: bash .ai/probe.sh res://tests/x.tscn [extra user args]
scene="$1"; shift
godot --headless --import --path godot > .ai/probe-import.log 2>&1
godot --headless --fixed-fps 120 --path godot "$scene" "$@"

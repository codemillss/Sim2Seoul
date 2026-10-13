#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_mode=${1:-run}
case "$task_mode" in run|editor|observe) ;; *) echo "Usage: sh tools/run_movement_test.sh [run|editor|observe]" >&2; exit 1 ;; esac
if [ ! -x "$task_engine" ]; then echo "Install fixed Godot; see docs/environment.md" >&2; exit 1; fi
if [ "$("$task_engine" --version)" != "4.7.2.stable.official.ed1daf0bf" ]; then echo "P02 requires Godot 4.7.2.stable.official.ed1daf0bf" >&2; exit 1; fi
case "$task_mode" in
  run) exec "$task_engine" --path "$task_root/game" res://scenes/tests/movement_test.tscn ;;
  editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/tests/movement_test.tscn ;;
  observe)
    task_output="$task_root/data/cache/movement/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$task_output"
    exec "$task_engine" --path "$task_root/game" --script "$task_root/tests/game/check_movement_test.gd" --log-file "$task_output/run.log" -- "--suite=timing" "--render-fps=60" "--result=$task_output/engine.json" "--capture-prefix=$task_output/view"
    ;;
esac

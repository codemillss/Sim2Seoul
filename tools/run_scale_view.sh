#!/bin/sh
# E04 fixture launcher; source preparation happens outside the engine.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_python=${SIM2SEOUL_PYTHON:-python3}
task_mode=${1:-run}
case "$task_mode" in run|editor|observe) ;; *) echo "Usage: sh tools/run_scale_view.sh [run|editor|observe]" >&2; exit 1 ;; esac
if [ ! -x "$task_engine" ]; then echo "Install fixed Godot; see docs/environment.md" >&2; exit 1; fi
if [ "$("$task_engine" --version)" != "4.7.2.stable.official.ed1daf0bf" ]; then echo "E04 requires Godot 4.7.2.stable.official.ed1daf0bf" >&2; exit 1; fi
"$task_python" "$task_root/tools/prepare_game_data.py"
"$task_python" "$task_root/tools/prepare_scale_view.py"
case "$task_mode" in
  run) exec "$task_engine" --path "$task_root/game" res://scenes/tests/scale_view.tscn ;;
  editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/tests/scale_view.tscn ;;
  observe)
    task_output="$task_root/data/cache/scale/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$task_output"
    exec "$task_engine" --path "$task_root/game" --script "$task_root/tests/game/check_scale_view.gd" --log-file "$task_output/run.log" -- "--result=$task_output/engine.json" "--capture-prefix=$task_output/view"
    ;;
esac

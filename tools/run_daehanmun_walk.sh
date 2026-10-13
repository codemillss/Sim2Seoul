#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_python=${SIM2SEOUL_PYTHON:-python3}
task_mode=${1:-run}
case "$task_mode" in run|editor|observe) ;; *) echo "Usage: sh tools/run_daehanmun_walk.sh [run|editor|observe]" >&2; exit 1 ;; esac
if [ ! -x "$task_engine" ] || [ "$("$task_engine" --version)" != "4.7.2.stable.official.ed1daf0bf" ]; then echo "W01 requires fixed Godot; see docs/environment.md" >&2; exit 1; fi
"$task_python" "$task_root/tools/check_daehanmun_bundle.py"
case "$task_mode" in
 run) exec "$task_engine" --path "$task_root/game" res://scenes/tests/daehanmun_walk.tscn ;;
 editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/tests/daehanmun_walk.tscn ;;
 observe)
 task_output="$task_root/data/cache/daehanmun/$(date +%Y%m%d-%H%M%S)"
 mkdir -p "$task_output" "$task_root/game/test_support"
 cp "$task_root/tests/game/check_camera_test.gd" "$task_root/game/test_support/check_camera_test.gd"
 cp "$task_root/tests/game/daehanmun_probe_input.gd" "$task_root/game/test_support/daehanmun_probe_input.gd"
 exec "$task_engine" --path "$task_root/game" --script "$task_root/tests/game/check_daehanmun_walk.gd" --log-file "$task_output/run.log" -- --automatic-probe "--result=$task_output/engine.json" "--capture-prefix=$task_output/view" --suite=gpu --render-fps=60
 ;;
esac

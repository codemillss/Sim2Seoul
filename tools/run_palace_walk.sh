#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_python=${SIM2SEOUL_PYTHON:-python3}
task_mode=${1:-run}
case "$task_mode" in run|editor) ;; *) echo "Usage: sh tools/run_palace_walk.sh [run|editor]" >&2; exit 1 ;; esac
if [ ! -x "$task_engine" ] || [ "$("$task_engine" --version)" != "4.7.2.stable.official.ed1daf0bf" ]; then echo "W02 requires fixed Godot; see docs/environment.md" >&2; exit 1; fi
"$task_python" "$task_root/tools/check_palace_bundle.py"
case "$task_mode" in
 run) exec "$task_engine" --path "$task_root/game" res://scenes/world/palace_walk.tscn ;;
 editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/world/palace_walk.tscn ;;
esac

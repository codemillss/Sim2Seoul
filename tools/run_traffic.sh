#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_python=${SIM2SEOUL_PYTHON:-"$task_root/.venv-data/bin/python"}
task_mode=${1:-run}
case "$task_mode" in run|editor) ;; *) echo "Usage: sh tools/run_traffic.sh [run|editor]" >&2; exit 1 ;; esac
if [ "$("$task_engine" --version)" != "4.7.2.stable.official.ed1daf0bf" ]; then echo "See docs/environment.md" >&2; exit 1; fi
"$task_python" "$task_root/tools/check_public_bundle.py"
"$task_python" "$task_root/tools/prepare_city_landmarks.py" --check
"$task_python" "$task_root/tools/prepare_pedestrians.py" --check
"$task_python" "$task_root/tools/prepare_traffic.py" --check
case "$task_mode" in
 run) exec "$task_engine" --path "$task_root/game" res://scenes/world/traffic_walk.tscn ;;
 editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/world/traffic_walk.tscn ;;
esac

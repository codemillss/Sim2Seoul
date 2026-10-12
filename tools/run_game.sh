#!/bin/sh
# Prepare outside the engine; runtime uses only game/ resources.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_python=${SIM2SEOUL_PYTHON:-python3}
task_mode=${1:-run}
if [ ! -x "$task_engine" ]; then
  echo "Godot missing. See docs/environment.md." >&2
  exit 1
fi
task_version=$("$task_engine" --version)
if [ "$task_version" != "4.7.2.stable.official.ed1daf0bf" ]; then
  echo "Expected Godot 4.7.2.stable.official.ed1daf0bf, got: $task_version" >&2
  exit 1
fi
case "$task_mode" in run|editor|observe) ;; *) echo "Usage: sh tools/run_game.sh [run|editor|observe]" >&2; exit 1 ;; esac
"$task_python" "$task_root/tools/prepare_game_data.py"
case "$task_mode" in
  editor) exec "$task_engine" --editor --path "$task_root/game" --scene res://scenes/main.tscn ;;
  run) exec "$task_engine" --path "$task_root/game" ;;
  observe)
    task_output="$task_root/data/cache/game/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$task_output"
    echo "Local evidence: $task_output"
    exec "$task_engine" --path "$task_root/game" --log-file "$task_output/run.log" -- "--observe-prefix=$task_output/runtime" --auto-quit
    ;;
esac

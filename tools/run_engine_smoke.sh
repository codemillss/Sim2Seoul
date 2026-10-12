#!/bin/sh
# E01 only; run from any directory. Runtime evidence stays local.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
task_mode=${1:-run}
task_renderer=${2:-forward_plus}
if [ ! -x "$task_engine" ]; then
  echo "Godot executable missing. See docs/environment.md." >&2
  exit 1
fi
task_version=$("$task_engine" --version)
if [ "$task_version" != "4.7.2.stable.official.ed1daf0bf" ]; then
  echo "Expected Godot 4.7.2.stable.official.ed1daf0bf, got: $task_version" >&2
  exit 1
fi
case "$task_renderer" in
  forward_plus|mobile) task_driver=metal ;;
  gl_compatibility) task_driver=opengl3 ;;
  *) echo "Renderer: forward_plus, mobile, or gl_compatibility" >&2; exit 1 ;;
esac
case "$task_mode" in
  editor)
    exec "$task_engine" --editor --path "$task_root/tests/engine_smoke" --scene res://startup.tscn --rendering-method "$task_renderer" --rendering-driver "$task_driver"
    ;;
  run)
    exec "$task_engine" --path "$task_root/tests/engine_smoke" --rendering-method "$task_renderer" --rendering-driver "$task_driver" -- --stay-open
    ;;
  observe)
    task_output="$task_root/data/cache/engine_smoke/$(date +%Y%m%d-%H%M%S)-$task_renderer"
    mkdir -p "$task_output"
    echo "Local evidence: $task_output"
    exec "$task_engine" --path "$task_root/tests/engine_smoke" --rendering-method "$task_renderer" --rendering-driver "$task_driver" --log-file "$task_output/run.log" -- "--capture=$task_output/viewport.png" "--report=$task_output/runtime.json"
    ;;
  *) echo "Usage: sh tools/run_engine_smoke.sh [run|editor|observe] [renderer]" >&2; exit 1 ;;
esac

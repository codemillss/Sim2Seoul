#!/bin/sh
# Open the authored neutral-form comparison in the existing Godot project.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_engine=${SIM2SEOUL_GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
if [ ! -x "$task_engine" ]; then
  echo "Godot 실행 파일이 없습니다. docs/RUN_GUIDE.md를 확인하세요." >&2
  exit 1
fi
exec "$task_engine" --path "$task_root/game" res://scenes/study/resident_form_study.tscn "$@"

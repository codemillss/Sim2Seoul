#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_python=${SIM2SEOUL_PYTHON:-python3}
"$task_python" "$task_root/tools/prepare_walkable_itinerary.py" --check >/dev/null
exec sh "$task_root/tools/run_public_walk.sh" "${1:-run}"

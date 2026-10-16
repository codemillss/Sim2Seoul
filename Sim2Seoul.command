#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$task_root"
exec sh "$task_root/tools/run_exploration.sh" run

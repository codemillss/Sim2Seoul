#!/usr/bin/env bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
TASK_PYTHON="${SIM2SEOUL_PYTHON:-python3.14}"
if ! command -v "$TASK_PYTHON" >/dev/null 2>&1; then
  printf '%s\n' 'Python 3.14 is required. Install it first, or set SIM2SEOUL_PYTHON to its executable.' >&2
  exit 1
fi
"$TASK_PYTHON" -c 'import sys; assert sys.version_info[:2] == (3, 14), "Use Python 3.14 for the pinned data environment."'
"$TASK_PYTHON" tools/check_checkout.py
if [[ -e .venv-data && ! -x .venv-data/bin/python ]]; then
  printf '%s\n' 'Existing .venv-data is incomplete. Preserve or rename it before creating a new environment.' >&2
  exit 1
fi
if [[ ! -d .venv-data ]]; then
  "$TASK_PYTHON" -m venv .venv-data
fi
.venv-data/bin/python -c 'import sys; assert sys.version_info[:2] == (3, 14), "Existing .venv-data uses a different Python; preserve/rename it first."'
.venv-data/bin/python -m pip install -r requirements-data.txt
.venv-data/bin/python -m pip check
TASK_EXTRACT="$(.venv-data/bin/python -c 'import json; print(json.load(open("data/reports/extract_manifest.json"))["extract_file"])')"
.venv-data/bin/python tools/prepare_osm.py audit "$TASK_EXTRACT"
.venv-data/bin/python tools/check_coordinates.py
.venv-data/bin/python tools/prepare_features.py
.venv-data/bin/python tools/check_geometry.py
printf '%s\n' 'Setup complete. Continue from docs/WORK_STATUS.md and docs/SOL_HANDOFF.md.'

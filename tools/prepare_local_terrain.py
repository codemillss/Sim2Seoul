#!/usr/bin/env python3
"""Prepare a Mac-local TIN without replacing the shared acceptance evidence."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'data/reports/terrain_integration/20261018/mesh_preparation.json'
OUTPUT = ROOT / 'game/data/generated/terrain_surface.json'

def main():
    original = REPORT.read_bytes() if REPORT.is_file() else None
    try:
        result = subprocess.run([sys.executable, str(ROOT / 'tools/prepare_terrain_surface.py')], cwd=ROOT)
    finally:
        if original is not None and REPORT.read_bytes() != original:
            # Keep this Mac's audit next to its disposable runtime input. The
            # committed report remains the evidence from the accepted machine.
            local = OUTPUT.with_name('terrain_local_preparation.json')
            local.write_bytes(REPORT.read_bytes())
            REPORT.write_bytes(original)
    if result.returncode:
        raise SystemExit(result.returncode)
    if original is not None:
        expected = json.loads(original)['output_sha256']
        actual = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit('This Mac generated a different terrain. Shared evidence was preserved; inspect game/data/generated/terrain_local_preparation.json and validate before accepting it.')

if __name__ == '__main__':
    main()

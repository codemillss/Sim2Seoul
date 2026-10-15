#!/usr/bin/env python3
"""Regenerate L02 in a small prepared-input copy; no national maps or engine needed."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ['data/processed/landmark_spec.json', 'game/resources/world_geometry/world.json',
          'game/data/generated/daehanmun.json', 'game/assets/authored/landmarks/palace/recipes.json',
          'tools/prepare_palace_landmarks.py', 'tools/prepare_world.py']
OUTPUTS = ['game/data/generated/palace_landmarks.json', 'game/data/generated/palace_landmarks_manifest.json']


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(output):
    checks = []
    def ck(name, value, **details): checks.append({'name': name, 'passed': bool(value), **details})
    inputs = {p: digest(ROOT / p) for p in INPUTS}
    expected = {p: digest(ROOT / p) for p in OUTPUTS}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l02-prepared-') as temp:
        copy = Path(temp)
        for p in INPUTS:
            dest = copy / p; dest.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / p, dest)
        ck('copy.only_six_prepared_inputs', len(list(copy.rglob('*.*'))) == 6,
           bytes=sum((copy / p).stat().st_size for p in INPUTS))
        command = [sys.executable, '-E', '-B', str(copy / 'tools/prepare_palace_landmarks.py'), '--root', str(copy)]
        for iteration in (1, 2):
            ran = subprocess.run(command, capture_output=True, text=True)
            ck('generate.' + str(iteration), ran.returncode == 0 and
               {p: digest(copy / p) for p in OUTPUTS if (copy / p).exists()} == expected,
               output_hashes={p: digest(copy / p) for p in OUTPUTS if (copy / p).exists()})
        good = subprocess.run(command + ['--check'], capture_output=True, text=True)
        ck('check.fresh', good.returncode == 0)
        target = copy / OUTPUTS[0]
        target.write_text('{}\n')
        stale = subprocess.run(command + ['--check'], capture_output=True, text=True)
        ck('check.stale_runtime_rejected', stale.returncode != 0 and 'Missing/stale L02 runtime file' in stale.stderr)
        subprocess.run(command, capture_output=True, text=True, check=True)
        recipe_path = copy / INPUTS[3]
        recipe = json.loads(recipe_path.read_text()); recipe['palette']['tile'][0] += .01
        recipe_path.write_text(json.dumps(recipe))
        changed = subprocess.run(command + ['--check'], capture_output=True, text=True)
        ck('check.changed_authored_input_rejected', changed.returncode != 0 and 'Missing/stale L02 runtime file' in changed.stderr)
        ck('copy.no_raw_cache_engine_or_venv', not any((copy / p).exists() for p in
           ['data/raw', 'game/.godot', '.venv-data', 'data/cache']))
    ck('original_inputs_and_runtime_unchanged', inputs == {p: digest(ROOT / p) for p in INPUTS}
       and expected == {p: digest(ROOT / p) for p in OUTPUTS})
    report = {'task': 'L02', 'passed': all(c['passed'] for c in checks), 'checks': checks,
              'input_sha256': inputs, 'output_sha256': expected,
              'scope': 'Prepared six-input relocation/regeneration on current M1 interpreter; not full GIS rebuild, fresh dependency installation or another Mac test'}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print('L02 prepared regeneration', report['passed'], len(checks), 'checks')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/l02_portability.json')
    raise SystemExit(main(parser.parse_args().output))

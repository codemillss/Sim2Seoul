#!/usr/bin/env python3
"""Regenerate only W04 twice from a small, already-prepared copied bundle.

The subprocess disables Python site packages and environment configuration.
This is an existing-machine prepared-copy test, not a fresh GIS installation,
full source-data rebuild, engine walk, or second-Mac verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ('game/data/generated/walkable_itinerary.json',
           'game/data/generated/walkable_manifest.json')
PREPARED_PLANS = (
    OUTPUTS[0], 'game/data/generated/public_walk.json',
    'game/data/generated/palace_walk.json', 'game/data/generated/daehanmun.json',
    'game/resources/world_geometry/world.json', 'game/data/generated/scale_view.json',
)
EXTRA_INPUTS = {
    'game/data/generated/public_decision.json',
    'game/data/generated/public_manifest.json',
    'game/data/generated/palace_decision.json',
    'game/data/generated/palace_manifest.json',
    'game/data/generated/daehanmun_decision.json',
    'game/data/generated/daehanmun_manifest.json',
    'game/data/generated/region.json', 'game/data/generated/manifest.json',
    'game/resources/collision/rules.json', 'game/resources/collision/generated.json',
    'tools/check_public_bundle.py', 'tools/check_palace_bundle.py',
    'tools/check_daehanmun_bundle.py', 'tools/check_collision_bundle.py',
    'tools/prepare_game_data.py', 'tools/prepare_collision.py',
}
ALLOWED_RAW = {
    'data/raw/deoksugung_cityhall-v2.osm.pbf',
    'data/raw/supplemental/overture/2026-09-23.1/buildings.geojson',
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def json_read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def safe_input(name):
    path = Path(name)
    prohibited = {'.venv', '.venv-data', '.godot', '__pycache__', 'cache', 'geofabrik', 'builds'}
    if (path.is_absolute() or '..' in path.parts or not path.parts or
            any(part in prohibited or part.startswith('.env') for part in path.parts) or
            (name.startswith('data/raw/') and name not in ALLOWED_RAW)):
        raise ValueError('Non-small/cache/environment input requested: ' + name)
    return name


def source_inputs(root):
    """Follow only prepared plan provenance, never arbitrary file references."""
    inputs = set(EXTRA_INPUTS)
    for name in PREPARED_PLANS:
        if name not in OUTPUTS:
            inputs.add(name)
        provenance = json_read(root / name)['provenance']
        if isinstance(provenance, dict) and 'inputs' in provenance:
            inputs.update(entry['file'] for entry in provenance['inputs'])
        elif isinstance(provenance, dict):
            inputs.update(provenance)
        elif isinstance(provenance, list):
            inputs.update(entry['file'] for entry in provenance)
        else:
            raise ValueError('Unsupported prepared provenance: ' + name)
    if any(name in inputs for name in OUTPUTS):
        raise ValueError('The copied inputs must not contain W04 output files')
    return sorted(safe_input(name) for name in inputs)


def execute(python, root, check=False):
    command = [python, '-E', '-S', '-B', str(root / 'tools/prepare_walkable_itinerary.py')]
    if check:
        command.append('--check')
    started = time.perf_counter()
    run = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=60)
    result = {'returncode': run.returncode,
              'elapsed_seconds': round(time.perf_counter() - started, 6)}
    if run.returncode:
        result['message_tail'] = (run.stdout + run.stderr)[-3500:]
    else:
        result['builder_result'] = json.loads(run.stdout)
    return result


def main(report, root=ROOT):
    root, report = Path(root).resolve(), Path(report).resolve()
    inputs = source_inputs(root)
    originals = {name: sha(root / name) for name in inputs}
    expected = {name: sha(root / name) for name in OUTPUTS}
    if report == root / 'tools/check_walkable_portability.py' or report in {
            root / name for name in inputs + list(OUTPUTS)}:
        raise ValueError('Report path would overwrite an input or runtime output')
    python = str(Path(sys.executable).resolve())
    preflight = execute(python, root, check=True)
    runs, clean_start, copied_unchanged = [], False, False
    with tempfile.TemporaryDirectory(prefix='sim2seoul-w04-portable-') as temporary:
        copied = Path(temporary)
        for name in inputs:
            destination = copied / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / name, destination)
        clean_start = (not any((copied / name).exists() for name in OUTPUTS) and
                       not any((copied / name).exists() for name in
                               ('.venv', '.venv-data', 'game/.godot', 'data/cache')))
        for index in range(2):
            result = execute(python, copied)
            result['run'] = index + 1
            result['sha256'] = {name: sha(copied / name) for name in OUTPUTS
                                if (copied / name).is_file()}
            result['copied_inputs_unchanged'] = originals == {
                name: sha(copied / name) for name in inputs}
            runs.append(result)
        copied_unchanged = all(run['copied_inputs_unchanged'] for run in runs)
    originals_unchanged = (originals == {name: sha(root / name) for name in inputs} and
                           expected == {name: sha(root / name) for name in OUTPUTS})
    passed = (preflight['returncode'] == 0 and clean_start and originals_unchanged and
              copied_unchanged and all(run['returncode'] == 0 and
                                      run['sha256'] == expected for run in runs))
    result = {
        'schema_version': 1, 'task': 'W04', 'passed': passed,
        'milestone_id': 'W0-engineering-walk-v1',
        'plan_sha256': expected[OUTPUTS[0]], 'expected_runtime_sha256': expected,
        'two_generations_sha256': [run['sha256'].get(OUTPUTS[0]) for run in runs],
        'preflight': preflight, 'runs': runs,
        'copied_inputs': originals, 'copied_files': len(inputs),
        'copied_bytes': sum((root / name).stat().st_size for name in inputs),
        'clean_start': clean_start, 'original_inputs_unchanged': originals_unchanged,
        'copied_inputs_unchanged': copied_unchanged,
        'w04_sources': {name: sha(root / name) for name in (
            'tools/check_walkable_portability.py', 'tools/prepare_walkable_itinerary.py',
            'data/manual/walkable_milestone.json')},
        'interpreter': python, 'python_version': platform.python_version(),
        'python_flags': ['-E', '-S', '-B'],
        'machine': platform.machine(), 'operating_system': platform.platform(),
        'scope': ('W04-only regeneration from already-prepared small W01/W02/W03/E03/P04/E04 '
                  'inputs on the existing M1 Mac. Python environment/site packages and bytecode '
                  'writing disabled; no country maps, whole DSM, environment or starting caches '
                  'copied. Not a full G rebuild, fresh installation, engine walk or M4 test.'),
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'task': 'W04', 'passed': passed, 'copied_files': len(inputs),
                      'copied_bytes': result['copied_bytes'], 'report': str(report),
                      'report_sha256': sha(report)}, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--report', type=Path, default=ROOT / 'data/cache/walkable_portability.json')
    args = parser.parse_args()
    raise SystemExit(main(args.report, args.root))

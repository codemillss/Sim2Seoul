#!/usr/bin/env python3
"""W02-only regeneration from copied, already-prepared small inputs."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(report):
    plan_path = ROOT / 'game/data/generated/palace_walk.json'
    plan = json.loads(plan_path.read_text())
    w01 = json.loads((ROOT / 'game/data/generated/daehanmun.json').read_text())
    world = json.loads((ROOT / 'game/resources/world_geometry/world.json').read_text())
    inputs = set(plan['provenance']) | set(w01['provenance']) | {item['file'] for item in world['provenance']['inputs']}
    inputs |= {str(p.relative_to(ROOT)) for p in (ROOT / 'tools').glob('*.py')}
    inputs |= {'data/reports/coordinate_check.json', 'game/data/generated/region.json',
               'game/data/generated/manifest.json', 'game/resources/collision/rules.json',
               'game/resources/collision/generated.json', 'game/data/generated/daehanmun.json',
               'game/data/generated/daehanmun_decision.json', 'game/data/generated/daehanmun_manifest.json'}
    prohibited = [p for p in inputs if any(part in {'.venv-data', '.godot', 'cache', 'geofabrik'} or part.startswith('.env') for part in Path(p).parts)]
    if prohibited:
        raise ValueError('Non-small/cache/environment inputs requested: ' + repr(prohibited))
    originals = {p: sha(ROOT / p) for p in sorted(inputs)}
    expected = {name: sha(ROOT / 'game/data/generated' / name) for name in ['palace_walk.json', 'palace_decision.json', 'palace_manifest.json']}
    runs = []
    with tempfile.TemporaryDirectory(prefix='sim2seoul-w02-portable-') as temporary:
        copied = Path(temporary)
        for path in sorted(inputs):
            destination = copied / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, destination)
        clean_start = not (copied / '.venv-data').exists() and not (copied / 'game/.godot').exists() and not (copied / 'game/data/generated/palace_walk.json').exists()
        for run in range(2):
            executed = subprocess.run([str(ROOT / '.venv-data/bin/python'), str(copied / 'tools/prepare_palace_walk.py')], capture_output=True, text=True, timeout=300)
            measured = {name: sha(copied / 'game/data/generated' / name) for name in expected} if executed.returncode == 0 else {}
            runs.append({'run': run + 1, 'returncode': executed.returncode, 'sha256': measured,
                         'message_tail': (executed.stdout + executed.stderr)[-2500:] if executed.returncode else ''})
        unchanged = originals == {p: sha(ROOT / p) for p in sorted(inputs)} and expected == {name: sha(ROOT / 'game/data/generated' / name) for name in expected}
        passed = clean_start and unchanged and all(r['returncode'] == 0 and r['sha256'] == expected for r in runs)
    result = {'task': 'W02', 'passed': passed, 'connection_sha256': expected['palace_walk.json'],
              'expected_runtime_sha256': expected, 'two_generations_sha256': [r['sha256'].get('palace_walk.json') for r in runs],
              'runs': runs, 'copied_inputs': originals, 'clean_start': clean_start,
              'original_inputs_unchanged': unchanged, 'copied_files': len(inputs),
              'interpreter': str(ROOT / '.venv-data/bin/python'),
              'scope': 'W02-only regeneration from already-prepared small W01/W02/G/E03/P04 inputs using the existing M1 venv interpreter. No country maps, whole DSM, environment or starting caches copied. Not a full G rebuild, new installation or M4 test.'}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('W02 portability', passed, 'copied_files', len(inputs), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, default=ROOT / 'data/cache/palace_portability.json')
    args = parser.parse_args()
    raise SystemExit(main(args.report))

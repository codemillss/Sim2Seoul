#!/usr/bin/env python3
"""Run W02 observations in an isolated, offline, runtime-only game copy."""
import argparse
import fnmatch
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_daehanmun_contract import ASSETS as W01_ASSETS, FILES as W01_FILES

ROOT = Path(__file__).resolve().parents[1]
VERSION = '4.7.2.stable.official.ed1daf0bf'
FILES = [
    *W01_FILES,
    'scripts/palace_world.gd',
    'scripts/palace_walk.gd',
    'scripts/player/palace_player.gd',
    'scenes/world/palace_world.tscn',
    'scenes/world/palace_walk.tscn',
]
ASSETS = [
    *W01_ASSETS,
    'data/generated/palace_walk.json',
    'data/generated/palace_decision.json',
    'data/generated/palace_manifest.json',
]
HELPERS = [
    'tests/game/check_camera_test.gd',
    'tests/game/check_daehanmun_walk.gd',
    'tests/game/daehanmun_probe_input.gd',
]
PROBE = 'tests/game/check_palace_walk.gd'
CHECKER = 'tools/check_palace_evidence.py'
DRIVER = 'tools/check_palace_contract.py'
PROOF_FILES = [
    PROBE, CHECKER, DRIVER, *HELPERS,
    'tools/check_daehanmun_evidence.py',
    'tools/check_daehanmun_contract.py',
    'tools/check_collision_contract.py',
    'tools/check_palace_bundle.py',
    'tools/check_daehanmun_bundle.py',
    'tools/check_collision_bundle.py',
    'tests/game/offline.sb',
]
# A regression must fail a check related to its actual injected defect.
# Names/prefixes are explicit so unrelated failures never count as detection.
FAULT_EXPECTED = {
    'support_disabled': ('inventory.W02_support', '*.samplefloor*'),
    'preserved_wall_removed': ('inventory.osm:way:381755262:barrier', 'ray.preserved_retaining_wall'),
    'player_mask_zero': ('actual_player_contract',),
    'camera_mask_zero': ('actual_player_contract', '*.independent_samples'),
    'global_support_reenabled': ('inventory.actual_disabled_bodies',),
    'courtyard_hole_filled': ('inventory.census', 'ray.court_hole'),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def snapshot(paths):
    return {str(path): sha(path) for path in sorted(set(paths))}


def main(engine, output, mode):
    from check_palace_bundle import check as preflight

    # Freeze the scorer before observations: later edits cannot rescore this run.
    checker_path = ROOT / CHECKER
    checker_bytes = checker_path.read_bytes()
    checker_namespace = {'__name__': 'w02_checker_snapshot', '__file__': str(checker_path)}
    exec(compile(checker_bytes, str(checker_path), 'exec'), checker_namespace)
    audit = checker_namespace['audit']
    proof_hashes = {path: sha(ROOT / path) for path in PROOF_FILES}
    preflight(ROOT)

    engine = Path(engine).resolve()
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if version != VERSION:
        raise ValueError(f'W02 requires {VERSION}; received {version}')

    source_hashes = {path: sha(ROOT / 'game' / path) for path in FILES}
    asset_hashes = {path: sha(ROOT / 'game' / path) for path in ASSETS}
    plan_path = ROOT / 'game/data/generated/palace_walk.json'
    plan_hash = sha(plan_path)
    plan = read_json(plan_path)
    world = read_json(ROOT / 'game/resources/world_geometry/world.json')
    features = read_json(ROOT / 'data/processed/features.json')
    w01_plan = read_json(ROOT / 'game/data/generated/daehanmun.json')
    input_paths = [ROOT / name for name in set(plan['provenance']) | set(w01_plan['provenance'])]
    input_paths.extend([ROOT / 'data/processed/features.json', ROOT / 'game/resources/world_geometry/world.json'])
    input_hashes = snapshot(input_paths)
    checks = []
    faults = []

    def ck(name, passed, **details):
        checks.append({'name': name, 'passed': bool(passed), **details})

    ck('engine.version', version == VERSION, version=version)
    with tempfile.TemporaryDirectory(prefix='sim2seoul-w02-') as temporary:
        game = Path(temporary) / 'game'
        for path in FILES + ASSETS:
            destination = game / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / path, destination)
        for path in HELPERS:
            destination = game / 'test_support' / Path(path).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, destination)
        ck('copy.runtime_only', not (game / '.godot').exists() and not (game / 'data/raw').exists(),
           authored_files=len(FILES), runtime_files=len(ASSETS), helpers=HELPERS)

        def run(label, fault='normal', gpu=False, fps=60, suite='full'):
            result = output / (label + '.json')
            log = output / (label + '.log')
            result.parent.mkdir(parents=True, exist_ok=True)
            # Reject a missing fresh result instead of accepting an older record.
            result.unlink(missing_ok=True)
            log.unlink(missing_ok=True)
            (output / (label + '_check.json')).unlink(missing_ok=True)
            command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine)]
            if not gpu:
                command.extend(['--headless', '--fixed-fps', '60'])
            command.extend([
                '--path', str(game), '--script', str(ROOT / PROBE), '--log-file', str(log), '--',
                '--automatic-probe', '--result=' + str(result), '--suite=' + suite,
                '--case=' + fault, '--render-fps=' + str(fps),
            ])
            if gpu:
                command.append('--capture-prefix=' + str(output / ('view_30' if fps == 30 else 'view')))
            timeout = 200 if gpu and fps == 30 else 750 if gpu else 300
            try:
                execution = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            except subprocess.TimeoutExpired as error:
                write_json(output / (label + '_failure.json'), {
                    'task': 'W02', 'reason': 'timeout', 'timeout_seconds': timeout,
                    'suite': suite, 'fault': fault, 'fresh_result_present': result.exists(),
                })
                raise ValueError(f'W02 engine timeout: {label} ({timeout}s)') from error
            messages = re.sub(r'\x1b\[[0-9;]*m', '', execution.stdout + execution.stderr)
            log_messages = log.read_text(errors='replace') if log.exists() else ''
            if execution.returncode or 'ERROR:' in messages + log_messages or 'SCRIPT ERROR' in messages + log_messages or not result.exists():
                write_json(output / (label + '_failure.json'), {
                    'task': 'W02', 'reason': 'engine_error_or_missing_result',
                    'returncode': execution.returncode, 'suite': suite, 'fault': fault,
                    'fresh_result_present': result.exists(), 'message_tail': messages[-3000:],
                })
                raise ValueError(f'W02 engine failure: {label}: {messages[-2000:]}')
            raw = read_json(result)
            scored = audit(raw, plan, world, features)
            ck(label + '.plan_hash', raw['plan_sha256'] == plan_hash)
            write_json(output / (label + '_check.json'), scored)
            print('W02', label, scored['passed'], 'checks', len(scored['checks']), flush=True)
            if not scored['passed']:
                print('FAILED', [(item['name'], item.get('details')) for item in scored['checks'] if not item['passed']][:12], flush=True)
            return raw, scored

        if mode == 'contract':
            normal, scored = run('headless_engine')
            ck('normal.full', scored['passed'], count=len(scored['checks']))
            repeated, scored = run('repeat_engine')
            ck('repeat.full', scored['passed'], count=len(scored['checks']))
            ck('repeat.inventory', normal['inventory'] == repeated['inventory'])
            ck('repeat.paths', len(normal['cases']) == len(repeated['cases']) and all(
                first['name'] == second['name'] and first['samples'] == second['samples']
                for first, second in zip(normal['cases'], repeated['cases'])))
            for fault, expected in FAULT_EXPECTED.items():
                _, scored = run('regression/' + fault, fault=fault, suite='short')
                failed = [item['name'] for item in scored['checks'] if not item['passed']]
                related = [name for name in failed if any(fnmatch.fnmatchcase(name, pattern) or name.startswith(pattern + '.') for pattern in expected)]
                ck('actual_fault.' + fault, not scored['passed'] and bool(related), expected_failure_patterns=list(expected), related_failures=related)
                faults.append({'fault': fault, 'checker_passed': scored['passed'],
                               'expected_failure_patterns': list(expected), 'related_failures': related, 'failed_checks': failed})
        elif mode == 'trial':
            _, scored = run('trial_engine', suite='short')
            ck('trial.short', scored['passed'], count=len(scored['checks']))
        else:
            frame_rates = [30, 60] if mode == 'gpu' else [int(mode[-2:])]
            for fps in frame_rates:
                _, scored = run(f'gpu_{fps}_engine', gpu=True, fps=fps, suite='short' if fps == 30 else 'full')
                ck('gpu.' + str(fps), scored['passed'], count=len(scored['checks']))

        ck('sources_unchanged', source_hashes == {path: sha(ROOT / 'game' / path) for path in FILES})
        ck('assets_unchanged', asset_hashes == {path: sha(ROOT / 'game' / path) for path in ASSETS})
        ck('inputs_unchanged', input_hashes == snapshot(input_paths))
        ck('proof_unchanged', proof_hashes == {path: sha(ROOT / path) for path in PROOF_FILES})

    report = {
        'task': 'W02', 'mode': mode, 'passed': all(item['passed'] for item in checks),
        'checks': checks, 'sources': source_hashes, 'runtime_assets': asset_hashes,
        'input_sha256': input_hashes, 'proof_sha256': proof_hashes,
        'probe_sha256': proof_hashes[PROBE], 'checker_sha256': hashlib.sha256(checker_bytes).hexdigest(),
        'driver_sha256': proof_hashes[DRIVER], 'actual_faults': faults, 'network': 'deny network*',
        'scope': 'Automatic W02 bounded palace-route observations in an offline runtime-only copy using the existing M1 environment',
        'not_tested': ['surveyed terrain/gate dimensions/current access', 'building interiors',
                       'human handling/OS focus', 'M4', 'R2/R3 and W0/V0',
                       'NPC/vehicle controllers', 'city performance'],
    }
    write_json(output / (mode + '_check.json'), report)
    print('W02 driver', report['passed'], len(checks), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/palace_contract')
    parser.add_argument('--mode', choices=['contract', 'gpu30', 'gpu60', 'gpu', 'trial'], default='contract')
    arguments = parser.parse_args()
    raise SystemExit(main(arguments.engine, arguments.output, arguments.mode))

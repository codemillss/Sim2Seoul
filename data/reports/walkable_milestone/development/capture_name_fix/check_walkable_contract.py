#!/usr/bin/env python3
"""Frozen W04 observations in an offline runtime-only copy, without changing W03."""
import argparse
import fnmatch
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_public_contract import FILES, ASSETS as W03_ASSETS, HELPERS as W03_HELPERS, PROOF_FILES as W03_PROOF
from prepare_walkable_itinerary import prepare

ROOT = Path(__file__).resolve().parents[1]
VERSION = '4.7.2.stable.official.ed1daf0bf'
ASSETS = [*W03_ASSETS, 'data/generated/walkable_itinerary.json', 'data/generated/walkable_manifest.json']
HELPERS = [*W03_HELPERS, 'tests/game/check_public_walk.gd']
PROBE = 'tests/game/check_walkable_milestone.gd'
CHECKER = 'tools/check_walkable_evidence.py'
PROOF = list(dict.fromkeys([*W03_PROOF, PROBE, CHECKER, 'tools/check_walkable_contract.py',
                          'tools/prepare_walkable_itinerary.py', 'data/manual/walkable_milestone.json']))
FAULTS = {
    'seam_teleport': ('journey.step_bound', 'seam*', 'journey.no_recovery*'),
    'omit_court': ('stage_coverage', 'checkpoint_coverage', 'itinerary.coverage*'),
    'player_mask_zero': ('actual_player_contract',),
    'camera_mask_zero': ('actual_player_contract',),
}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(path):
    return json.loads(Path(path).read_text())

def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')

def main(output, mode, engine):
    preflight = prepare(ROOT, True)
    checker = None
    if mode != 'development':
        namespace = {'__file__': str(ROOT / CHECKER), '__name__': 'w04_frozen_checker'}
        exec(compile((ROOT / CHECKER).read_bytes(), str(ROOT / CHECKER), 'exec'), namespace)
        checker = namespace['audit']
    proof = {p: sha(ROOT / p) for p in PROOF if (ROOT / p).exists()}
    sources = {p: sha(ROOT / 'game' / p) for p in FILES}
    assets = {p: sha(ROOT / 'game' / p) for p in ASSETS}
    itinerary = read(ROOT / 'game/data/generated/walkable_itinerary.json')
    w03 = read(ROOT / 'game/data/generated/public_walk.json')
    world = read(ROOT / 'game/resources/world_geometry/world.json')
    features = read(ROOT / 'data/processed/features.json')
    inputs = {p: sha(ROOT / p) for p in set(itinerary['provenance']) | set(w03['provenance'])}
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if version != VERSION: raise ValueError('W04 requires ' + VERSION)
    output = output.resolve(); output.mkdir(parents=True, exist_ok=True)
    checks = []; fault_results = []
    def ck(name, passed, **details): checks.append({'name': name, 'passed': bool(passed), **details})
    with tempfile.TemporaryDirectory(prefix='sim2seoul-w04-') as temporary:
        game = Path(temporary) / 'game'
        for p in FILES + ASSETS:
            dest = game / p; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / p, dest)
        for p in HELPERS:
            dest = game / 'test_support' / Path(p).name; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / p, dest)
        ck('copy.runtime_only', not (game / '.godot').exists() and not (game / 'data/raw').exists(),
           authored=len(FILES), runtime=len(ASSETS), helpers=len(HELPERS))
        def run(label, fault='normal', gpu=False, suite='full'):
            result = output / (label + '.json'); log = output / (label + '.log')
            result.parent.mkdir(parents=True, exist_ok=True)
            for p in [result, log, output / (label + '_check.json')]: p.unlink(missing_ok=True)
            command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine)]
            if not gpu: command += ['--headless', '--fixed-fps', '60']
            command += ['--path', str(game), '--script', str(ROOT / PROBE), '--log-file', str(log), '--',
                        '--automatic-probe', '--result=' + str(result), '--suite=' + suite,
                        '--case=' + fault, '--render-fps=60']
            if gpu: command += ['--capture-prefix=' + str(output / 'view')]
            try:
                ran = subprocess.run(command, capture_output=True, text=True, timeout=1500 if gpu else 600)
            except subprocess.TimeoutExpired:
                write(output / (label + '_failure.json'), {'task': 'W04', 'reason': 'timeout', 'fresh_result': result.exists()})
                raise
            messages = re.sub(r'\x1b\[[0-9;]*m', '', ran.stdout + ran.stderr)
            logged = log.read_text(errors='replace') if log.exists() else ''
            if ran.returncode or 'ERROR:' in messages + logged or not result.exists():
                write(output / (label + '_failure.json'), {'task': 'W04', 'reason': 'engine_error_or_missing_fresh_result',
                      'returncode': ran.returncode, 'fresh_result': result.exists(), 'message_tail': messages[-3000:]})
                raise ValueError('W04 engine failed: ' + label + '\n' + messages[-2000:])
            raw = read(result)
            if checker:
                scored = checker(raw, itinerary, world, features)
                write(output / (label + '_check.json'), scored)
                print('W04', label, scored['passed'], 'checks', len(scored['checks']), flush=True)
                if not scored['passed']: print('FAILED', [c['name'] for c in scored['checks'] if not c['passed']][:14], flush=True)
            else:
                scored = {'passed': False, 'checks': [], 'status': 'development_observation_not_acceptance'}
                print('W04 development engine completed', len(raw['cases']), flush=True)
            ck(label + '.plan_hash', raw['plan_sha256'] == preflight['plan_sha256'])
            return raw, scored
        if mode == 'contract':
            normal, score = run('headless_engine'); ck('full.accepted', score['passed'])
            repeat, score = run('repeat_engine'); ck('repeat.accepted', score['passed'])
            ck('repeat.inventory', normal['inventory'] == repeat['inventory'])
            ck('repeat.paths', [c['samples'] for c in normal['cases']] == [c['samples'] for c in repeat['cases']])
            for fault, patterns in FAULTS.items():
                _, score = run('faults/' + fault, fault=fault, suite='full' if fault == 'omit_court' else 'short')
                failed = [c['name'] for c in score['checks'] if not c['passed']]
                related = [n for n in failed if any(fnmatch.fnmatchcase(n, p) or n.startswith(p + '.') for p in patterns)]
                ck('actual_fault.' + fault, not score['passed'] and bool(related), related_failures=related)
                fault_results.append({'fault': fault, 'checker_passed': score['passed'], 'failed_checks': failed, 'related_failures': related})
        elif mode == 'gpu':
            _, score = run('gpu_engine', gpu=True); ck('gpu.full.accepted', score['passed'])
        else:
            _, score = run('trial_engine', suite='short'); ck('trial.accepted', score['passed'])
        ck('sources_unchanged', sources == {p: sha(ROOT / 'game' / p) for p in FILES})
        ck('assets_unchanged', assets == {p: sha(ROOT / 'game' / p) for p in ASSETS})
        ck('inputs_unchanged', inputs == {p: sha(ROOT / p) for p in inputs})
        ck('proof_unchanged', proof == {p: sha(ROOT / p) for p in proof})
    report = {'task': 'W04', 'mode': mode, 'passed': mode != 'development' and all(c['passed'] for c in checks),
              'checks': checks, 'sources': sources, 'runtime_assets': assets, 'input_sha256': inputs,
              'proof_sha256': proof, 'actual_faults': fault_results, 'network': 'deny network*',
              'scope': 'One actual-engine automatic W04 itinerary on unchanged W03 engineering support; human handling/OS focus, real terrain/access, M4 and V0 unverified'}
    write(output / (mode + '_check.json'), report)
    return 0 if report['passed'] or mode == 'development' else 1

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/walkable_contract')
    parser.add_argument('--mode', choices=['development', 'trial', 'contract', 'gpu'], default='contract')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.mode, args.engine))

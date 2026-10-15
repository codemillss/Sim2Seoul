#!/usr/bin/env python3
"""L02 actual surfaces and frozen W04 route checks in an offline runtime-only copy."""
import argparse
import copy
import gzip
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_walkable_contract import FILES as BASE_FILES, ASSETS as BASE_ASSETS, HELPERS as BASE_HELPERS, PROOF as BASE_PROOF
from check_walkable_evidence import audit as audit_walk
from check_palace_landmarks_evidence import audit as audit_visuals

ROOT = Path(__file__).resolve().parents[1]
FILES = [*BASE_FILES, 'scripts/landmark_visuals.gd', 'scripts/landmark_walk.gd', 'scenes/world/palace_landmarks.tscn']
ASSETS = [*BASE_ASSETS, 'data/generated/palace_landmarks.json', 'data/generated/palace_landmarks_manifest.json']
HELPERS = [*BASE_HELPERS, 'tests/game/check_walkable_milestone.gd', 'tests/game/palace_visual_observation.gd']
PROOF = [*BASE_PROOF, 'tools/prepare_palace_landmarks.py', 'tools/check_palace_landmarks_evidence.py',
         'tools/check_palace_landmarks_contract.py', 'tests/game/check_palace_landmarks_walk.gd',
         'tests/game/check_palace_landmarks_views.gd', 'tests/game/palace_visual_observation.gd',
         'game/assets/authored/landmarks/palace/recipes.json']
HIDDEN_FRAGMENTS = ['W01_gate_side_0', 'W01_gate_side_1', 'W01_gate_lintel']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def archive(path, value):
    payload = (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()
    Path(path).write_bytes(gzip.compress(payload, mtime=0))


def main(output, mode, engine):
    output = output.resolve(); output.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(ROOT / '.venv-data/bin/python'), str(ROOT / 'tools/prepare_palace_landmarks.py'), '--check'], check=True)
    bundle = read(ROOT / 'game/data/generated/palace_landmarks.json')
    spec = read(ROOT / 'data/processed/landmark_spec.json')
    world = read(ROOT / 'game/resources/world_geometry/world.json')
    features = read(ROOT / 'data/processed/features.json')
    w01 = read(ROOT / 'game/data/generated/daehanmun.json')
    itinerary = read(ROOT / 'game/data/generated/walkable_itinerary.json')
    sources = {p: sha(ROOT / 'game' / p) for p in FILES}
    assets = {p: sha(ROOT / 'game' / p) for p in ASSETS}
    proof = {p: sha(ROOT / p) for p in dict.fromkeys(PROOF)}
    inputs = {p: sha(ROOT / p) for p in bundle['source_sha256']}
    checks = []
    def ck(name, ok, **details): checks.append({'name': name, 'passed': bool(ok), **details})
    ck('engine.version', subprocess.check_output([str(engine), '--version'], text=True).strip() == '4.7.2.stable.official.ed1daf0bf')
    manifest = read(ROOT / 'game/data/generated/palace_landmarks_manifest.json')
    ck('bundle.manifest', manifest['file']['sha256'] == assets['data/generated/palace_landmarks.json']
       and bundle['source_sha256'] == inputs and manifest['world_sha256'] == sha(ROOT / 'game/resources/world_geometry/world.json'))
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l02-') as tmp:
        game = Path(tmp) / 'game'
        for p in FILES + ASSETS:
            target = game / p; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / p, target)
        for p in HELPERS:
            target = game / 'test_support' / Path(p).name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / p, target)
        shutil.copy2(ROOT / 'data/processed/landmark_spec.json', game / 'test_support/landmark_spec.json')
        ck('copy.runtime_only', not (game / '.godot').exists() and not (game / 'data/raw').exists(), files=len(FILES), assets=len(ASSETS))
        def run(label, *, gpu=False, walk=False, suite='full', fault='normal'):
            result = Path(tmp) / (label + '.json')
            log = output / (label + '.log')
            probe = 'tests/game/check_palace_landmarks_walk.gd' if walk else 'tests/game/check_palace_landmarks_views.gd'
            command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine)]
            if not gpu: command += ['--headless', '--fixed-fps', '60']
            command += ['--path', str(game), '--script', str(ROOT / probe), '--log-file', str(log), '--',
                        '--automatic-probe', '--result=' + str(result), '--suite=' + suite,
                        '--case=' + fault, '--render-fps=60']
            if gpu: command += ['--capture-prefix=' + str(output / (label + '_view'))]
            ran = subprocess.run(command, capture_output=True, text=True, timeout=1500 if gpu else 600)
            messages = re.sub(r'\x1b\[[0-9;]*m', '', ran.stdout + ran.stderr)
            logged = log.read_text(errors='replace') if log.exists() else ''
            if ran.returncode or 'ERROR:' in messages + logged or not result.exists():
                write(output / (label + '_failure.json'), {'returncode': ran.returncode,
                      'fresh_result': result.exists(), 'messages': messages[-6000:]})
                raise RuntimeError('L02 engine failed: ' + label + '\n' + messages[-3000:])
            record = read(result)
            archive(output / (label + '.json.gz'), record)
            visuals = record['l02_visuals'] if walk else record['visuals']
            visual_score = audit_visuals(visuals, bundle, spec, w01)
            ck(label + '.actual_bundle_hash', visuals['bundle_sha256'] == assets['data/generated/palace_landmarks.json'])
            write(output / (label + '_visual_check.json'), visual_score)
            if walk:
                # Only the three deliberately replaced visual flags differ. Raw evidence
                # remains intact; original body faces, masks, layers and movement are audited.
                normalized = copy.deepcopy(record)
                changed = []
                for row in normalized['inventory']['fragments']:
                    if row['id'] in HIDDEN_FRAGMENTS:
                        changed.append({'id': row['id'], 'raw_visible': row['visible'], 'baseline_visible': True})
                        row['visible'] = True
                walk_score = audit_walk(normalized, itinerary, world, features)
                write(output / (label + '_walk_check.json'), walk_score)
                write(output / (label + '_visibility_delta.json'), {'intentional_visual_only_changes': changed,
                      'scope': 'Normalize only these flags for frozen W04; actual hidden flags independently audited; all physical observations unchanged'})
                ck(label + '.walk', walk_score['passed'])
                if not walk_score['passed']: print('WALK_FAILED', [c['name'] for c in walk_score['checks'] if not c['passed']][:20], flush=True)
            print('L02', label, 'visuals=', visual_score['passed'], 'checks=', len(visual_score['checks']), flush=True)
            if not visual_score['passed']: print('VISUAL_FAILED', [c['name'] for c in visual_score['checks'] if not c['passed']][:16], flush=True)
            return record, visual_score
        if mode == 'views':
            _, scored = run('views', gpu=True); ck('views.visuals', scored['passed'])
        elif mode in ('gpu', 'gpu_trial'):
            _, scored = run(mode, gpu=True, walk=True, suite='short' if mode == 'gpu_trial' else 'full')
            ck(mode + '.visuals', scored['passed'])
        else:
            _, scored = run('headless_visuals'); ck('headless_visuals.accepted', scored['passed'])
            expected_faults = {
                'roof_hidden': 'daehanmun.actual_visible_identity_material_and_front_culling',
                'visual_shift': 'daehanmun.actual_visible_identity_material_and_front_culling',
                'collision_added': 'scope.no_new_colliders_or_permissions',
                'gate_obstructed': 'gate.all_visible_geometry_below_3m_in_original_side_solids',
                'original_restored': 'engine.only_replaced_source_meshes_hidden',
            }
            for fault, expected in expected_faults.items():
                _, rejected = run('fault_' + fault, fault=fault)
                failed = [c['name'] for c in rejected['checks'] if not c['passed']]
                ck('fault.' + fault, not rejected['passed'] and expected in failed,
                   failed_checks=failed, required_related_failure=expected)
            _, scored = run('headless_walk', walk=True); ck('headless_walk.visuals', scored['passed'])
        ck('production_sources_unchanged', sources == {p: sha(ROOT / 'game' / p) for p in FILES})
        ck('runtime_assets_unchanged', assets == {p: sha(ROOT / 'game' / p) for p in ASSETS})
        ck('inputs_unchanged', inputs == {p: sha(ROOT / p) for p in inputs})
        ck('proof_unchanged', proof == {p: sha(ROOT / p) for p in proof})
    report = {'task': 'L02', 'mode': mode, 'passed': all(c['passed'] for c in checks), 'checks': checks,
              'source_sha256': sources, 'runtime_sha256': assets, 'input_sha256': inputs, 'proof_sha256': proof,
              'network': 'deny network*', 'scope': 'Actual L02 visuals and original W04 itinerary; human recognition/handling, field accuracy/access and M4 remain unverified'}
    write(output / (mode + '_check.json'), report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/l02_contract')
    parser.add_argument('--mode', choices=['contract', 'views', 'gpu_trial', 'gpu'], default='contract')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.mode, args.engine))

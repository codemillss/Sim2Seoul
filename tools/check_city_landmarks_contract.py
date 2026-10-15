#!/usr/bin/env python3
"""L03 actual surfaces and frozen W04 route checks in an offline runtime-only copy."""
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

from check_palace_landmarks_contract import FILES as BASE_FILES, ASSETS as BASE_ASSETS, HELPERS as BASE_HELPERS, PROOF as BASE_PROOF
from check_walkable_evidence import audit as audit_walk
from check_palace_landmarks_evidence import audit as audit_palace
from check_city_landmarks_evidence import audit as audit_visuals

ROOT = Path(__file__).resolve().parents[1]
FILES = [*BASE_FILES, 'scripts/city_visuals.gd', 'scripts/city_landmark_walk.gd', 'scenes/world/city_landmarks.tscn']
ASSETS = [*BASE_ASSETS, 'data/generated/city_landmarks.json', 'data/generated/city_landmarks_manifest.json',
          'assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb',
          'assets/vendor/kenney_city_kit_commercial/Textures/colormap.png',
          'assets/vendor/kenney_city_kit_commercial/License.txt']
HELPERS = list(dict.fromkeys([*BASE_HELPERS, 'tests/game/city_visual_observation.gd']))
PROOF = [*BASE_PROOF, 'tools/prepare_city_landmarks.py', 'tools/prepare_city_authored.py',
         'tools/check_city_landmarks_evidence.py', 'tools/check_city_landmarks_contract.py',
         'tests/game/check_city_landmarks_walk.gd', 'tests/game/check_city_landmarks_views.gd',
         'tests/game/city_visual_observation.gd', 'tests/game/inspect_city_reuse.gd',
         'game/assets/authored/landmarks/city/recipes.json', 'tools/run_city_landmarks.sh']
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
    subprocess.run([str(ROOT / '.venv-data/bin/python'), str(ROOT / 'tools/prepare_city_landmarks.py'), '--check'], check=True)
    bundle = read(ROOT / 'game/data/generated/city_landmarks.json')
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
    manifest = read(ROOT / 'game/data/generated/city_landmarks_manifest.json')
    ck('bundle.manifest', manifest['file']['sha256'] == assets['data/generated/city_landmarks.json']
       and bundle['source_sha256'] == inputs and manifest['world_sha256'] == sha(ROOT / 'game/resources/world_geometry/world.json'))
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l03-') as tmp:
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
            probe = 'tests/game/check_city_landmarks_walk.gd' if walk else 'tests/game/check_city_landmarks_views.gd'
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
                raise RuntimeError('L03 engine failed: ' + label + '\n' + messages[-3000:])
            record = read(result)
            archive(output / (label + '.json.gz'), record)
            visuals = record['l03_visuals'] if walk else record['visuals']
            visual_score = audit_visuals(visuals, bundle, spec, w01)
            ck(label + '.actual_bundle_hash', visuals['bundle_sha256'] == assets['data/generated/city_landmarks.json'])
            write(output / (label + '_visual_check.json'), visual_score)
            palace = copy.deepcopy(record['l02_visuals'])
            # City display flags are independently checked on the raw complete map.
            # Restore only the four L03 visual flags for the frozen L02 audit.
            for id in bundle['hidden_mesh_ids']: palace['all_source_visibility'][id] = True
            palace_bundle = read(ROOT / 'game/data/generated/palace_landmarks.json')
            palace_score = audit_palace(palace, palace_bundle, spec, w01)
            write(output / (label + '_palace_check.json'), palace_score)
            ck(label + '.palace_retained', palace_score['passed'])
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
                      'L02_city_visual_delta':[{'id':id,'raw_visible':record['l02_visuals']['all_source_visibility'][id],
                                              'L02_baseline_visible':True} for id in bundle['hidden_mesh_ids']],
                      'scope': 'Gate flags restored only for W04; four city source display flags restored only for L02; raw complete visibility independently audited; physical observations unchanged'})
                ck(label + '.walk', walk_score['passed'])
                if not walk_score['passed']: print('WALK_FAILED', [c['name'] for c in walk_score['checks'] if not c['passed']][:20], flush=True)
            print('L03', label, 'visuals=', visual_score['passed'], 'checks=', len(visual_score['checks']), flush=True)
            if not visual_score['passed']: print('VISUAL_FAILED', [c['name'] for c in visual_score['checks'] if not c['passed']][:16], flush=True)
            return record, visual_score
        if mode == 'views':
            _, scored = run('views', gpu=True); ck('views.visuals', scored['passed'])
        elif mode in ('gpu', 'gpu_trial'):
            _, scored = run(mode, gpu=True, walk=True, suite='short' if mode == 'gpu_trial' else 'full')
            ck(mode + '.visuals', scored['passed'])
        else:
            good, scored = run('headless_visuals'); ck('headless_visuals.accepted', scored['passed'])
            altered=copy.deepcopy(bundle)
            next(c for i in altered['landmarks'] if i['id']=='sfc' for c in i['components']
                 if c['feature_role']=='reused_model')['reuse_lineage'][0]['barycentric'][0][0] += .2
            rejected=audit_visuals(good['visuals'],altered,spec,w01)
            ck('fault.reuse_lineage_tamper',not rejected['passed'] and any(
                c['name']=='sfc.actual_external_model_triangle_lineage' and not c['passed'] for c in rejected['checks']))
            expected_faults = {
                'city_hidden': 'city_hall.actual_visible_identity_material_and_front_culling',
                'city_shift': 'city_hall.actual_visible_identity_material_and_front_culling',
                'city_collision': 'scope.no_new_colliders_or_permissions',
                'city_original': 'engine.only_replaced_source_meshes_hidden',
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
    report = {'task': 'L03', 'mode': mode, 'passed': all(c['passed'] for c in checks), 'checks': checks,
              'source_sha256': sources, 'runtime_sha256': assets, 'input_sha256': inputs, 'proof_sha256': proof,
              'network': 'deny network*', 'scope': 'Actual L03 visuals and original W04 itinerary; human recognition/handling, field accuracy/access and M4 remain unverified'}
    write(output / (mode + '_check.json'), report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/l03_contract')
    parser.add_argument('--mode', choices=['contract', 'views', 'gpu_trial', 'gpu'], default='contract')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.mode, args.engine))

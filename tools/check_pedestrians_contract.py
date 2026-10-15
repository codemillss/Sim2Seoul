#!/usr/bin/env python3
"""N02 offline runtime-only engine tests and independent observation audit."""
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

from check_city_landmarks_contract import FILES as BASE_FILES, ASSETS as BASE_ASSETS, HELPERS as BASE_HELPERS
from check_city_landmarks_evidence import audit as audit_city
from check_palace_landmarks_evidence import audit as audit_palace
from check_pedestrians_evidence import audit

ROOT = Path(__file__).resolve().parents[1]
FILES = [*BASE_FILES, 'scripts/npc/pedestrian.gd', 'scenes/npc/pedestrian.tscn',
         'scripts/pedestrian_walk.gd', 'scenes/world/pedestrian_walk.tscn']
ASSETS = [*BASE_ASSETS, 'data/generated/pedestrians.json', 'data/generated/pedestrians_manifest.json']
HELPERS = [*BASE_HELPERS, 'tests/game/check_walkable_milestone.gd']
PROOF = ['tests/game/check_pedestrians.gd', 'tools/check_pedestrians_evidence.py',
         'tools/check_pedestrians_contract.py', 'tools/prepare_pedestrians.py', 'tools/run_pedestrians.sh']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def archive(path, value):
    Path(path).write_bytes(gzip.compress((json.dumps(value, ensure_ascii=False,
        separators=(',', ':'), allow_nan=False) + '\n').encode(), mtime=0))


def main(output, mode, engine):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(ROOT / '.venv-data/bin/python'), str(ROOT / 'tools/prepare_pedestrians.py'), '--check'], check=True)
    bundle = read(ROOT / 'game/data/generated/pedestrians.json')
    public = read(ROOT / 'game/data/generated/public_walk.json')
    world = read(ROOT / 'game/resources/world_geometry/world.json')
    w01 = read(ROOT / 'game/data/generated/daehanmun.json')
    spec = read(ROOT / 'data/processed/landmark_spec.json')
    city_bundle = read(ROOT / 'game/data/generated/city_landmarks.json')
    palace_bundle = read(ROOT / 'game/data/generated/palace_landmarks.json')
    files = {p: sha(ROOT / 'game' / p) for p in FILES}
    assets = {p: sha(ROOT / 'game' / p) for p in ASSETS}
    inputs = {p: sha(ROOT / p) for p in bundle['source_sha256']}
    proof = {p: sha(ROOT / p) for p in PROOF}
    checks = []

    def ck(name, ok, **details):
        checks.append({'name': name, 'passed': bool(ok), **details})

    ck('engine.version', subprocess.check_output([str(engine), '--version'], text=True).strip() == '4.7.2.stable.official.ed1daf0bf')
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n02-') as tmp:
        game = Path(tmp) / 'game'
        for p in FILES + ASSETS:
            target = game / p
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / p, target)
        for p in HELPERS:
            target = game / 'test_support' / Path(p).name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / p, target)
        ck('copy.runtime_only', not (game / '.godot').exists() and not (game / 'data/raw').exists(), files=len(FILES), assets=len(ASSETS))

        def run(label, *, gpu=False, suite='full', fault='normal', rejection=False):
            result = Path(tmp) / (label + '.json')
            log = output / (label + '.log')
            command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine)]
            if not gpu:
                command += ['--headless', '--fixed-fps', '60']
            command += ['--path', str(game), '--script', str(ROOT / 'tests/game/check_pedestrians.gd'),
                        '--log-file', str(log), '--', '--automatic-probe', '--result=' + str(result),
                        '--suite=' + suite, '--case=' + fault, '--render-fps=60']
            if gpu:
                command += ['--capture-prefix=' + str(output / (label + '_view'))]
            try:
                ran = subprocess.run(command, capture_output=True, text=True, timeout=900 if gpu else 180)
            except subprocess.TimeoutExpired as exc:
                write(output / (label + '_failure.json'), {'timeout': exc.timeout, 'fresh_result': result.exists(),
                      'messages': (exc.stdout or b'').decode(errors='replace')[-6000:]})
                raise
            messages = re.sub(r'\x1b\[[0-9;]*m', '', ran.stdout + ran.stderr)
            logged = log.read_text(errors='replace') if log.exists() else ''
            if result.exists():
                archive(output / (label + '.json.gz'), read(result))
            if ran.returncode or (not rejection and 'ERROR:' in messages + logged) or not result.exists():
                write(output / (label + '_failure.json'), {'returncode': ran.returncode,
                      'fresh_result': result.exists(), 'messages': messages[-6000:]})
                raise RuntimeError('N02 engine failed: ' + label + '\n' + messages[-5000:])
            record = read(result)
            if rejection:
                ck(label + '.rejected_before_spawn', record.get('rejected') is True and record.get('npc_count') == 0, reason=record.get('reason'))
                return record, None
            scored = audit(record, bundle, public, world, w01)
            write(output / (label + '_pedestrian_check.json'), scored)
            city = audit_city(record['city_visuals'], city_bundle, spec, w01)
            palace_raw = copy.deepcopy(record['palace_visuals'])
            for identity in city_bundle['hidden_mesh_ids']:
                palace_raw['all_source_visibility'][identity] = True
            palace = audit_palace(palace_raw, palace_bundle, spec, w01)
            write(output / (label + '_city_check.json'), city)
            write(output / (label + '_palace_check.json'), palace)
            ck(label + '.city_retained', city['passed'])
            ck(label + '.palace_retained', palace['passed'])
            failed = [c['name'] for c in scored['checks'] if not c['passed']]
            print('N02', label, 'passed=', scored['passed'], 'checks=', len(scored['checks']), 'failed=', failed[:30], flush=True)
            return record, scored

        short = mode in ('short', 'gpu_short')
        normal, scored = run(mode, gpu=mode in ('gpu', 'gpu_short'), suite='short' if short else 'full')
        if short:
            ck(mode + '.development_checks', all(c['passed'] for c in scored['checks'] if c['name'] != 'acceptance.full_suite'))
        else:
            ck(mode + '.pedestrians', scored['passed'])
        if mode == 'contract' and scored['passed']:
            _, faulty = run('fault_npc_mask', suite='short', fault='npc_mask')
            failed = [c['name'] for c in faulty['checks'] if not c['passed']]
            ck('fault.actual_engine_mask_rejected', not faulty['passed'] and 'actors.plaza_front.capsule_contract' in failed, failed_checks=failed)
            # Mutations are applied to the retained engine record, never the production scene.
            for name, mutate in (
                ('missing_case', lambda r: r['cases'].pop()),
                ('duplicate_actor', lambda r: r['descriptors'].append(copy.deepcopy(r['descriptors'][0]))),
                ('missing_sample', lambda r: r['cases'][0]['samples'].pop(1)),
                ('pause_moved', lambda r: r['cases'][1]['end'][1]['position'].__setitem__(0, r['cases'][1]['end'][1]['position'][0] + 1.)),
            ):
                changed = copy.deepcopy(normal)
                mutate(changed)
                rejected = audit(changed, bundle, public, world, w01)
                write(output / ('fault_' + name + '_check.json'), rejected)
                ck('fault.retained_' + name, not rejected['passed'], failed_checks=[c['name'] for c in rejected['checks'] if not c['passed']])
            bundle_path = game / 'data/generated/pedestrians.json'
            manifest_path = game / 'data/generated/pedestrians_manifest.json'
            original_bundle = bundle_path.read_bytes()
            original_manifest = manifest_path.read_bytes()
            for fault in ('checksum', 'route_clone', 'coordinates', 'stale_support'):
                bundle_path.write_bytes(original_bundle)
                manifest_path.write_bytes(original_manifest)
                changed = read(bundle_path)
                manifest = read(manifest_path)
                if fault == 'checksum':
                    bundle_path.write_bytes(original_bundle + b' ')
                elif fault == 'stale_support':
                    manifest['public_sha256'] = '0' * 64
                    write(manifest_path, manifest)
                else:
                    if fault == 'route_clone':
                        changed['routes'][1] = copy.deepcopy(changed['routes'][0])
                    else:
                        changed['coordinate_system']['units'] = 'centimetres'
                    write(bundle_path, changed)
                    manifest['file']['sha256'] = sha(bundle_path)
                    manifest['file']['bytes'] = bundle_path.stat().st_size
                    write(manifest_path, manifest)
                run('loader_' + fault, suite='short', rejection=True)
        ck('production_sources_unchanged', files == {p: sha(ROOT / 'game' / p) for p in FILES})
        ck('runtime_assets_unchanged', assets == {p: sha(ROOT / 'game' / p) for p in ASSETS})
        ck('inputs_unchanged', inputs == {p: sha(ROOT / p) for p in inputs})
        ck('proof_unchanged', proof == {p: sha(ROOT / p) for p in proof})
    report = {'task': 'N02', 'mode': mode, 'passed': all(c['passed'] for c in checks), 'checks': checks,
              'source_sha256': files, 'runtime_sha256': assets, 'input_sha256': inputs, 'proof_sha256': proof,
              'network': 'deny network*', 'scope': 'Two N01 pedestrian routes and targeted dynamic contact; unchanged static/landmark inventory. No vehicle, human feel, field access, M4 or performance acceptance.'}
    write(output / (mode + '_check.json'), report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/n02_contract')
    parser.add_argument('--mode', choices=['short', 'contract', 'gpu_short', 'gpu'], default='contract')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.mode, args.engine))

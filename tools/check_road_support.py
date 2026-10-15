#!/usr/bin/env python3
"""N03 independent offline baseline/final road-support rays and box-drop audit."""
import argparse
import gzip
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from check_pedestrians_contract import FILES, ASSETS, HELPERS

ROOT = Path(__file__).resolve().parents[1]
PROOF = ['tests/game/check_road_support.gd', 'tools/check_road_support.py']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def at(route, station):
    remaining = min(max(station, 0.), route['length_m'])
    for index, (a, b) in enumerate(zip(route['xz'], route['xz'][1:])):
        length = math.dist(a, b)
        if remaining <= length or index == len(route['xz']) - 2:
            ratio = min(max(remaining / length, 0.), 1.)
            return [a[k] + (b[k] - a[k]) * ratio for k in range(2)], [(b[k] - a[k]) / length for k in range(2)], index
        remaining -= length
    raise ValueError('empty route')


def audit(record, routes, mode, support_ids):
    checks = []

    def ck(name, condition, **details):
        checks.append({'name': name, 'passed': bool(condition), **details})

    ck('engine.fixed_version', record['engine']['version'] == '4.7.2-stable (official)')
    ck('engine.headless_60_hz', record['engine']['display'] == 'headless' and record['engine']['physics_hz'] == 60 and record['engine']['render_fps'] == 60)
    ck('experiment.identity', record['task'] == 'N03' and record['experiment'] == 'road_support' and record['mode'] == mode and record['scene'] == 'res://scenes/world/pedestrian_walk.tscn')
    ck('inventory.originals_unchanged', record['inventory_before'] == record['inventory_after'])
    ck('ray.mask', record['ray_mask'] == (17 if mode == 'final' else 1))
    ck('support.test_only_count', len(record['added_supports']) == len(support_ids))
    if mode == 'final':
        ck('support.layer_mask_identity', all(r['layer'] == 16 and r['mask'] == 8 and r['identity'] and not r['disabled'] and r['shape'] == 'ConcavePolygonShape3D' for r in record['added_supports']))
    unsupported_rays = 0
    total_rays = 0
    expected_rows = []
    for route in routes['routes']:
        stations = [float(s) for s in range(0, math.ceil(route['length_m']), 5)] + [route['length_m']]
        expected_rows.extend((route, station) for station in stations)
    observations = record['station_observations']
    ck('rays.complete_stations', len(observations) == len(expected_rows), expected=len(expected_rows), observed=len(observations))
    for index, (route, station) in enumerate(expected_rows):
        if index >= len(observations):
            break
        row = observations[index]
        centre, tangent, segment = at(route, station)
        side = [-tangent[1], tangent[0]]
        offsets = [('centre', 0., 0.), ('front_left', 2.1, -.9), ('front_right', 2.1, .9), ('rear_left', -2.1, -.9), ('rear_right', -2.1, .9)]
        good_geometry = row['route_id'] == route['id'] and abs(row['station_m'] - station) < 1e-6 and row['segment'] == segment
        good_geometry &= len(row['rays']) == 5 and math.dist([row['centre'][0], row['centre'][2]], centre) < .0001
        for ray, (label, forward, across) in zip(row['rays'], offsets):
            point = [centre[k] + tangent[k] * forward + side[k] * across for k in range(2)]
            good_geometry &= ray['name'] == label and math.dist([ray['footprint_point'][0], ray['footprint_point'][2]], point) < .0001
            good_geometry &= ray['mask'] == record['ray_mask'] and abs(ray['from'][1] - route['ground_y_m'] - .5) < 1e-6 and abs(ray['to'][1] - route['ground_y_m'] + 1.) < 1e-6
            total_rays += 1
            supported = ray['hit'] and len(ray['position']) == 3 and abs(ray['position'][1] - route['ground_y_m']) <= .005 and ray['normal'][1] > .999
            if not supported:
                unsupported_rays += 1
            if mode == 'final':
                retained_ground = ray['id'] == 'W03_support' and ray['layer'] == 1 and ray['mask_observed'] == 14
                added_ground = ray['id'] in support_ids and ray['layer'] == 16 and ray['mask_observed'] == 8
                good_geometry &= supported and (retained_ground or added_ground)
        ck(f'rays.{route["id"]}.{station:.6f}', good_geometry)
    ck('rays.support_condition', unsupported_rays == 0 if mode == 'final' else unsupported_rays > 0, total=total_rays, unsupported=unsupported_rays)
    expected_drops = [(r, label, ratio * r['length_m']) for r in routes['routes'] for label, ratio in [('start', 0.), ('middle', .5), ('end', 1.)]]
    ck('drops.complete_six', len(record['drops']) == len(expected_drops))
    unsupported_drops = []
    for drop, (route, label, station) in zip(record['drops'], expected_drops):
        centre, tangent, _ = at(route, station)
        name = f'drop.{route["id"]}.{label}'
        ck(name + '.identity', drop['route_id'] == route['id'] and drop['label'] == label and abs(drop['station_m'] - station) < 1e-6 and math.dist(drop['centre_xz'], centre) < .0001)
        descriptor = drop['descriptor']
        ck(name + '.box_contract', math.dist(descriptor['size'], [1.8, 1.5, 4.2]) < 1e-6 and descriptor['shape_offset'] == [0., .75, 0.] and descriptor['layer'] == 8 and descriptor['mask'] == 31 and abs(descriptor['safe_margin'] - .001) < 1e-9 and abs(descriptor['floor_snap'] - .1) < 1e-6 and descriptor['gravity_mps2'] == 9.8)
        samples = drop['samples']
        ck(name + '.one_second_complete', drop['ticks'] == 60 and len(samples) == 60 and [s['step'] for s in samples] == list(range(1, 61)) and all(b['tick'] - a['tick'] == 1 for a, b in zip(samples, samples[1:])))
        ck(name + '.initial_setup', abs(drop['initial']['position'][1] - route['ground_y_m'] - .08) < 1e-6 and drop['initial']['velocity'] == [0., 0., 0.])
        end = drop['end']
        settled = end['on_floor'] and abs(end['position'][1] - route['ground_y_m']) <= .005
        if not settled:
            unsupported_drops.append({'route_id': route['id'], 'label': label, 'floor': end['on_floor'], 'foot_y_m': end['position'][1]})
        ck(name + '.horizontal_stationary', all(math.dist([s['position'][0], s['position'][2]], centre) <= .005 for s in samples))
        if mode == 'final':
            ck(name + '.supported', settled and all(s['on_floor'] and abs(s['position'][1] - route['ground_y_m']) <= .005 for s in samples[-30:]) and all(c['id'] in support_ids for s in samples for c in s['contacts']))
        else:
            ck(name + '.missing_support_observed', not end['on_floor'] and end['position'][1] < route['ground_y_m'] - 1. and not any(s['on_floor'] for s in samples))
    ck('drops.support_condition', not unsupported_drops if mode == 'final' else len(unsupported_drops) == 6, unsupported=unsupported_drops)
    return {'task': 'N03', 'mode': mode, 'passed': all(c['passed'] for c in checks), 'checks': checks, 'summary': {'station_count': len(observations), 'ray_count': total_rays, 'unsupported_rays': unsupported_rays, 'drop_count': len(record['drops']), 'unsupported_drops': unsupported_drops}}


def main(output, mode, engine, traffic_path):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    label = 'support_' + mode
    if (output / (label + '.json.gz')).exists():
        raise SystemExit('Evidence already exists; choose a fresh --output to preserve the previous run.')
    sources = {p: sha(ROOT / 'game' / p) for p in dict.fromkeys(FILES)}
    assets = {p: sha(ROOT / 'game' / p) for p in dict.fromkeys(ASSETS)}
    proof = {p: sha(ROOT / p) for p in PROOF}
    route_path = ROOT / 'data/processed/vehicle_routes.json'
    routes = read(route_path)
    inputs = {'data/processed/vehicle_routes.json': sha(route_path)}
    support_ids = []
    support_specs = []
    if mode == 'final':
        traffic_path = traffic_path.resolve()
        inputs[str(traffic_path.relative_to(ROOT)) if traffic_path.is_relative_to(ROOT) else str(traffic_path)] = sha(traffic_path)
        support_specs = read(traffic_path)['supports']
        support_ids = [s['id'] for s in support_specs]
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if version != '4.7.2.stable.official.ed1daf0bf':
        raise RuntimeError('Fixed Godot 4.7.2 required: ' + version)
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n03-support-') as tmp:
        game = Path(tmp) / 'game'
        for path in dict.fromkeys(FILES + ASSETS):
            target = game / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / path, target)
        for path in dict.fromkeys(HELPERS + [PROOF[0]]):
            target = game / 'test_support' / Path(path).name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, target)
        shutil.copy2(route_path, game / 'test_support/vehicle_routes.json')
        if mode == 'final':
            shutil.copy2(traffic_path, game / 'test_support/traffic.json')
        result = Path(tmp) / 'support.json'
        log = output / (label + '.log')
        command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine), '--headless', '--fixed-fps', '60', '--path', str(game), '--script', 'res://test_support/check_road_support.gd', '--log-file', str(log), '--', '--automatic-probe', '--result=' + str(result), '--case=' + mode, '--render-fps=60']
        ran = subprocess.run(command, capture_output=True, text=True, timeout=180)
        messages = re.sub(r'\x1b\[[0-9;]*m', '', ran.stdout + ran.stderr)
        logged = log.read_text(errors='replace') if log.exists() else ''
        if ran.returncode or 'ERROR:' in messages + logged or not result.exists():
            write(output / (label + '_failure.json'), {'returncode': ran.returncode, 'fresh_result': result.exists(), 'messages': messages[-10000:]})
            raise RuntimeError('N03 support engine failed\n' + messages[-10000:])
        record = read(result)
        archive = output / (label + '.json.gz')
        archive.write_bytes(gzip.compress((json.dumps(record, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode(), mtime=0))
        report = audit(record, routes, mode, support_ids)
        checks = report['checks']
        if mode == 'final':
            expected_faces = {s['id']: hashlib.sha256(struct.pack('<' + 'f' * len(s['vertices']), *s['vertices'])).hexdigest() for s in support_specs}
            observed_faces = {s['id']: s['face_sha256'] for s in record['added_supports']}
            checks.append({'name': 'supports.snapshot_faces_exact_float32', 'passed': len(set(support_ids)) == len(support_ids) and expected_faces == observed_faces})
            baseline_path = ROOT / 'data/reports/n03/support_baseline.json.gz'
            baseline_record = json.loads(gzip.decompress(baseline_path.read_bytes()))
            inputs['data/reports/n03/support_baseline.json.gz'] = sha(baseline_path)
            checks.append({'name': 'inventory.matches_retained_baseline', 'passed': baseline_record['inventory_before'] == record['inventory_before']})
        checks.extend([
            {'name': 'snapshot.route_sha256', 'passed': record['route_sha256'] == sha(route_path)},
            {'name': 'snapshot.traffic_sha256', 'passed': record['traffic_sha256'] == (sha(traffic_path) if mode == 'final' else '')},
            {'name': 'copy.runtime_only', 'passed': not (game / 'data/raw').exists() and not (game / '.venv-data').exists()},
            {'name': 'sources.production_unchanged', 'passed': sources == {p: sha(ROOT / 'game' / p) for p in sources}},
            {'name': 'assets.production_unchanged', 'passed': assets == {p: sha(ROOT / 'game' / p) for p in assets}},
            {'name': 'proof.unchanged', 'passed': proof == {p: sha(ROOT / p) for p in proof}},
        ])
        report.update({'passed': all(c['passed'] for c in checks), 'source_sha256': sources, 'runtime_sha256': assets, 'input_sha256': inputs, 'proof_sha256': proof, 'evidence_sha256': sha(archive), 'network': 'deny network*', 'scope': record['scope']})
        write(output / (label + '_check.json'), report)
    print(json.dumps({'mode': mode, 'passed': report['passed'], 'summary': report['summary'], 'failed': [c['name'] for c in checks if not c['passed']]}, ensure_ascii=False))
    return 0 if report['passed'] else 1


def audit_existing(output, mode, traffic_path):
    """Re-score retained engine evidence, preserving its execution-time proof hashes."""
    label = 'support_' + mode
    archive = output / (label + '.json.gz')
    previous_path = output / (label + '_check.json')
    previous = read(previous_path)
    backup = output / (label + '_check_float32_failure.json')
    if backup.exists():
        raise SystemExit('Previous audit already preserved; choose a fresh evidence directory.')
    if sha(archive) != previous['evidence_sha256']:
        raise RuntimeError('Retained raw engine evidence checksum changed')
    record = json.loads(gzip.decompress(archive.read_bytes()))
    route_path = ROOT / 'data/processed/vehicle_routes.json'
    if sha(route_path) != record['route_sha256']:
        raise RuntimeError('Current route differs from the retained engine snapshot')
    support_ids = [s['id'] for s in read(traffic_path)['supports']] if mode == 'final' else []
    if mode == 'final' and sha(traffic_path) != record['traffic_sha256']:
        raise RuntimeError('Current traffic differs from the retained engine snapshot')
    rescored = audit(record, read(route_path), mode, support_ids)
    extras = [c for c in previous['checks'] if c['name'].startswith(('snapshot.', 'copy.', 'sources.', 'assets.', 'proof.'))]
    rescored['checks'].extend(extras)
    shutil.copy2(previous_path, backup)
    for key in ['source_sha256', 'runtime_sha256', 'input_sha256', 'proof_sha256', 'evidence_sha256', 'network', 'scope']:
        rescored[key] = previous[key]
    rescored['audit_proof_sha256'] = {p: sha(ROOT / p) for p in PROOF}
    rescored['audit_correction'] = {'reason': 'BoxShape3D size stores float32 values; descriptor comparison now permits 1 micrometre float representation error. Physical support thresholds unchanged.', 'raw_engine_reused': True, 'original_check_sha256': sha(backup), 'original_check_path': str(backup.relative_to(ROOT)) if backup.is_relative_to(ROOT) else str(backup)}
    rescored['passed'] = all(c['passed'] for c in rescored['checks'])
    write(previous_path, rescored)
    print(json.dumps({'mode': mode, 'passed': rescored['passed'], 'summary': rescored['summary'], 'failed': [c['name'] for c in rescored['checks'] if not c['passed']]}, ensure_ascii=False))
    return 0 if rescored['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/reports/n03')
    parser.add_argument('--mode', choices=['baseline', 'final'], default='baseline')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--traffic', type=Path, default=ROOT / 'game/data/generated/traffic.json')
    parser.add_argument('--audit-existing', action='store_true', help='Re-score the retained raw engine result and preserve its original failed check.')
    args = parser.parse_args()
    raise SystemExit(audit_existing(args.output.resolve(), args.mode, args.traffic.resolve()) if args.audit_existing else main(args.output, args.mode, args.engine, args.traffic))

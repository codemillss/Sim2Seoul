#!/usr/bin/env python3
"""Re-audit saved R01 observations and replay precise retained-data controls.

Never launches Godot, rebuilds assets, polls hardware, or writes modified raw
observations. The existing R01 pure audit and memory audit remain authoritative;
this wrapper verifies their saved inputs, batch reconstruction and saved outputs.
Smoke remains diagnostic even when this reproducibility audit passes.
"""
import argparse
import bisect
import copy
import gzip
import hashlib
import json
from pathlib import Path

from measure_performance import PROFILES, audit as audit_measurement, memory_measurement


ROOT = Path(__file__).resolve().parents[1]


def byte_sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical_sha(value):
    return byte_sha((json.dumps(value, ensure_ascii=False, sort_keys=True,
                               separators=(',', ':'), allow_nan=False)+'\n').encode())


def label(path):
    path = Path(path).resolve()
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def write_fresh(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # An exclusive create prevents accidentally replacing earlier evidence.
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write('\n')


def load_inputs(record_path, plan_path, report_path, batches_path):
    inputs = {}; stored = {}
    for key, path in (('record', record_path), ('plan', plan_path),
                      ('report', report_path), ('frame_batches', batches_path)):
        raw = Path(path).read_bytes()
        decoded = gzip.decompress(raw) if str(path).endswith('.gz') else raw
        stored[key] = decoded
        inputs[key] = {'path': label(path), 'sha256': byte_sha(raw),
                       'decoded_sha256': byte_sha(decoded), 'bytes': len(raw),
                       'decoded_bytes': len(decoded)}
    record = json.loads(stored['record'])
    plan = json.loads(stored['plan'])
    report = json.loads(stored['report'])
    batches = [json.loads(line) for line in stored['frame_batches'].splitlines() if line.strip()]
    if not all(isinstance(batch, list) and all(isinstance(row, list) for row in batch) for batch in batches):
        raise ValueError('Expected JSONL arrays of per-frame arrays')
    frames = [row for batch in batches for row in batch]
    return record, plan, report, frames, inputs


def score(record, plan, report):
    """Only supplied values are read. This invokes no measurement side effects."""
    profile = record['profile']; smoke = report['diagnostic_only']
    checks, summary, windows, liveness = audit_measurement(record, plan, profile, smoke)
    memory = memory_measurement(report['rss_samples'], report['startup_log_receipt_events'],
                                record['duration_actual_s'])
    checks = copy.deepcopy(checks)
    checks.append({'name': 'memory.measurement_coverage', 'passed': memory['measurement_valid'],
                   'valid_sample_count': memory['valid_sample_count'],
                   'first_valid_offset_s': memory['first_valid_offset_s'],
                   'last_valid_offset_s': memory['last_valid_offset_s']})
    return {'checks': checks, 'summary': summary, 'windows': windows,
            'actor_liveness': liveness, 'memory_measurement': memory,
            'passed': all(c['passed'] for c in checks)}


def recheck(record, plan, report, batch_frames, inputs):
    checks = []

    def ck(name, okay, details=None):
        row = {'name': name, 'passed': bool(okay)}
        if details is not None:row['details'] = details
        checks.append(row)

    scored = score(record, plan, report)
    checks.extend(scored['checks'])
    profile = record['profile']; smoke = report['diagnostic_only']
    ck('saved.schema_and_profile', record['schema_version'] == 1 and record['task'] == report['task'] == 'R01'
       and profile in PROFILES and report['profile'] == PROFILES[profile] and isinstance(smoke, bool))
    ck('binding.raw_gzip_sha256', report['raw_sha256'] == inputs['record']['sha256'])
    ck('binding.camera_plan_archive_sha256', report['camera_plan_archive_sha256'] == inputs['plan']['sha256'])
    ck('binding.camera_plan_decoded_sha256', report['camera_plan_sha256'] == record['camera_plan_sha256']
       == inputs['plan']['decoded_sha256'])
    ck('binding.frame_batch_archive_sha256', report['frame_batches_sha256'] == inputs['frame_batches']['sha256'])
    ck('binding.frame_batch_decoded_sha256', record['frame_storage']['batch_file_sha256']
       == inputs['frame_batches']['decoded_sha256'])
    ck('binding.camera_source_record', record['camera_source']['record_sha256'] == plan['source_record_sha256']
       and record['camera_source']['source_duration_s'] == plan['source_duration_s']
       and record['camera_source']['stage_sample_counts'] == plan['stage_sample_counts']
       and record['camera_source']['source_leg_count'] == plan['source_leg_count'])
    ck('binding.saved_camera_plan_metadata', report['camera_plan'] == {k: v for k, v in plan.items() if k != 'poses'})
    ck('binding.saved_public_asset_sha256', record['public_sha256']
       == report['runtime_sha256']['data/generated/public_walk.json'])
    ck('frames.batch_reconstruction_exact', batch_frames == record['frames']
       and len(batch_frames) == record['frame_count'], {'frame_count': len(batch_frames)})
    # Reusing the pure audit after it changes would silently reinterpret old data.
    # The three small producer/proof files are checked; no large source assets or
    # N04 raw recordings are loaded/re-audited by this saved-data wrapper.
    for path in ('tools/measure_performance.py', 'tests/game/measure_performance.gd', 'tests/game/offline.sb'):
        ck('binding.current_producer_proof.'+path, path in report['proof_sha256']
           and (ROOT/path).is_file() and byte_sha((ROOT/path).read_bytes()) == report['proof_sha256'][path])
    ck('saved.summary_exact', scored['summary'] == report['summary'])
    ck('saved.windows_exact', scored['windows'] == report['windows'])
    ck('saved.actor_liveness_exact', scored['actor_liveness'] == report['actor_liveness'])
    ck('saved.memory_recalculation_exact', scored['memory_measurement'] == report['memory_measurement'])
    prior_checks = {c['name']: c for c in report['checks']}
    pure_checks = scored['checks'][:-1]
    ck('saved.pure_checks_exact', len(prior_checks) == len(report['checks'])
       and all(prior_checks.get(c['name']) == c for c in pure_checks))
    ck('saved.complete_producer_checks_passed', bool(report['checks'])
       and all(c['passed'] is True for c in report['checks']) and report['measurement_valid'] is True)
    expected_full = not smoke and report['measurement_valid'] and scored['memory_measurement']['measurement_valid']
    ck('saved.protocol_status_consistent', report['full_protocol_complete'] == report['passed'] == expected_full
       and report['memory_20minute_endurance_complete'] ==
           (expected_full and profile == 'B' and record['duration_actual_s'] >= 1200.))
    ck('saved.acceptance_scope', (smoke and plan['source_acceptance']['diagnostic_only'] is True)
       or (not smoke and plan['source_acceptance']['formal_accepted'] is True))
    return {'schema_version': 1, 'task': 'R01-saved-evidence', 'profile': profile,
            'diagnostic_only': smoke, 'passed': all(c['passed'] for c in checks),
            'full_protocol_complete': bool(expected_full and all(c['passed'] for c in checks)),
            'checks': checks, 'inputs': inputs,
            'checker_sha256': byte_sha(Path(__file__).read_bytes()),
            'recomputed': {k: scored[k] for k in ('summary', 'windows', 'actor_liveness', 'memory_measurement')},
            'scope': 'Saved observations re-audited with the byte-bound existing R01 pure audits. Raw/plan/batch SHA and exact batch reconstruction/summary/memory reproduction are checked. No engine or hardware sampling, no large historical N04 source reread, and no renewed historical rendering attestation. Smoke is diagnostic.'}


def pointer(parts):
    return '/'+ '/'.join(str(p).replace('~', '~0').replace('/', '~1') for p in parts)


def resolve(document, path):
    parts = [p.replace('~1', '/').replace('~0', '~') for p in path.split('/')[1:]]
    node = document
    for part in parts[:-1]:node = node[int(part)] if isinstance(node, list) else node[part]
    key = int(parts[-1]) if isinstance(node, list) else parts[-1]
    return node, key


def apply_patches(record, report, patches):
    documents = {'record': copy.deepcopy(record), 'report': copy.deepcopy(report)}
    for patch in patches:
        node, key = resolve(documents[patch['document']], patch['path'])
        if node[key] != patch['old']:
            raise ValueError('Patch old value differs: '+patch['document']+patch['path'])
        if patch['op'] == 'replace':node[key] = copy.deepcopy(patch['value'])
        elif patch['op'] == 'remove':del node[key]
        else:raise ValueError('Unsupported patch operation')
    return documents['record'], documents['report']


def build_controls(record, plan, report):
    controls = []

    def new(name, target, rationale):
        return {'name': name, 'target_check': target, 'rationale': rationale, 'patches': []}

    def replace(control, document, path, value):
        root = record if document == 'record' else report
        node = root
        for part in path:node = node[part]
        if node != value:
            control['patches'].append({'document': document, 'op': 'replace', 'path': pointer(path),
                                       'old': copy.deepcopy(node), 'value': copy.deepcopy(value)})

    columns = record['frame_columns']; middle = len(record['frames'])//2
    control = new('mid_measurement_3d_scale', 'render.every_frame_internal_3d_scale',
                  'Output texture remains 1920x1080 while one internal 3D scale becomes .5.')
    replace(control, 'record', ['frames', middle, columns.index('scaling_3d_scale')], .5)
    controls.append(control)

    control = new('first_frame_removed_count_adjusted', 'clock.actual_complete',
                  'Remove the first frame and adjust the declared count; the zero-time anchor and duration sum must reject it.')
    control['patches'].append({'document': 'record', 'op': 'remove', 'path': '/frames/0', 'old': record['frames'][0]})
    replace(control, 'record', ['frame_count'], record['frame_count']-1)
    controls.append(control)

    control = new('observation_and_actor_ticks_shifted', 'observations.exact_raw_frame_schedule_and_physics_join',
                  'Shift one light observation tick and all four actor counters together, preserving their mutual self-consistency but breaking the native-frame join.')
    sample_index = len(record['second_observations'])//2
    sample = record['second_observations'][sample_index]
    replace(control, 'record', ['second_observations', sample_index, 'physics_tick'], sample['physics_tick']+1)
    for kind in ('pedestrians', 'vehicles'):
        for i, body in enumerate(sample['actors'][kind]):
            replace(control, 'record', ['second_observations', sample_index, 'actors', kind, i, 'physics_steps'], body['physics_steps']+1)
    controls.append(control)

    control = new('double_speed_camera_with_consistent_source_poses', 'camera.every_frame_clock_bound_and_source_index',
                  'Double every recorded camera clock and consistently reselect all source pose fields; only the native rendering-time bound should make this invalid.')
    times = [row[0] for row in plan['poses']]

    def select(clock):
        return max(0, bisect.bisect_right(times, (clock % plan['period_s'])/plan['period_s']*plan['source_duration_s'])-1)

    ci = columns.index('camera_clock_s'); pi = columns.index('source_pose_index'); ti = columns.index('source_tick')
    for i, row in enumerate(record['frames']):
        clock = row[ci]*2; index = select(clock)
        replace(control, 'record', ['frames', i, ci], clock)
        replace(control, 'record', ['frames', i, pi], index)
        replace(control, 'record', ['frames', i, ti], plan['poses'][index][1])
    for i, sample in enumerate(record['second_observations']):
        clock = sample['camera_clock_s']*2; index = select(clock); pose = plan['poses'][index]
        values = {'camera_clock_s': clock, 'camera_loop_phase': (clock % plan['period_s'])/plan['period_s'],
                  'source_pose_index': index, 'source_tick': pose[1], 'source_t_s': pose[0],
                  'camera_position': pose[2], 'camera_basis_columns': pose[3], 'camera_fov': pose[4], 'camera_near': pose[5]}
        for key, value in values.items():replace(control, 'record', ['second_observations', i, key], value)
    controls.append(control)

    identity = record['second_observations'][0]['actors']['vehicles'][0]['route_id']
    control = new('vehicle_stopped_with_frozen_position_and_distance', 'actors.'+identity+'.measurable_route_motion',
                  'Keep two vehicles present but stop one actor and freeze its actual position/station/distance/tick observations.')
    initial = record['second_observations'][0]['actors']['vehicles'][0]
    for i, sample in enumerate(record['second_observations']):
        index = next(j for j, row in enumerate(sample['actors']['vehicles']) if row['route_id'] == identity)
        for key in ('position', 'station_m', 'actual_distance_m', 'physics_steps'):
            replace(control, 'record', ['second_observations', i, 'actors', 'vehicles', index, key], initial[key])
        replace(control, 'record', ['second_observations', i, 'actors', 'vehicles', index, 'running'], False)
    controls.append(control)

    control = new('all_rss_observations_unavailable', 'memory.measurement_coverage',
                  'Remove every process RSS observation while retaining all rendering observations; memory endurance must remain unmeasured.')
    for i, row in enumerate(report['rss_samples']):replace(control, 'report', ['rss_samples', i, 'rss_bytes'], None)
    controls.append(control)
    return controls


def replay_control(control, record, plan, report, inputs):
    if any(control['inputs'][key]['sha256'] != inputs[key]['sha256']
           for key in ('record', 'plan', 'report', 'frame_batches')):
        raise ValueError('Control input artifacts differ from its original four SHA bindings')
    if control['original_raw_gzip_sha256'] != inputs['record']['sha256']:
        raise ValueError('Control is bound to a different raw recording')
    if control['original_report_sha256'] != inputs['report']['sha256']:
        raise ValueError('Control is bound to a different measurement report')
    changed_record, changed_report = apply_patches(record, report, control['patches'])
    scored = score(changed_record, plan, changed_report)
    failed = [c['name'] for c in scored['checks'] if not c['passed']]
    result = dict(control)
    result.update({'changed_record_canonical_sha256': canonical_sha(changed_record),
                   'changed_report_canonical_sha256': canonical_sha(changed_report),
                   'rejected': not scored['passed'], 'failed_checks': failed,
                   'target_rejected': control['target_check'] in failed,
                   'checks': scored['checks']})
    result['passed'] = result['rejected'] and result['target_rejected']
    return result


def negative_controls(directory, record, plan, report, inputs):
    directory = Path(directory)
    if directory.exists() and any(directory.iterdir()):
        raise FileExistsError('Preserve prior controls; choose an empty output directory: '+str(directory))
    baseline = score(record, plan, report)
    if not baseline['passed']:
        raise ValueError('Controls require a passing original smoke measurement and valid RSS coverage')
    if record['profile'] != 'B':raise ValueError('These six controls require the observed B 2/2 profile')
    directory.mkdir(parents=True, exist_ok=True)
    results = []
    for control in build_controls(record, plan, report):
        control.update({'schema_version': 1, 'task': 'R01-retained-negative-control',
                        'inputs': inputs, 'original_raw_gzip_sha256': inputs['record']['sha256'],
                        'original_report_sha256': inputs['report']['sha256'],
                        'original_record_canonical_sha256': canonical_sha(record),
                        'original_report_canonical_sha256': canonical_sha(report),
                        'scope': 'Retained-data mutation only; no engine fault injection and no duplicated modified raw recording.'})
        result = replay_control(control, record, plan, report, inputs)
        path = directory/(control['name']+'.json'); write_fresh(path, result)
        results.append({'name': result['name'], 'passed': result['passed'],
                        'target_check': result['target_check'], 'failed_checks': result['failed_checks'],
                        'patch_count': len(result['patches']), 'path': label(path), 'sha256': byte_sha(path.read_bytes())})
    index = {'schema_version': 1, 'task': 'R01-retained-negative-controls',
             'passed': all(r['passed'] for r in results), 'inputs': inputs,
             'baseline_pure_check_count': len(baseline['checks']), 'baseline_passed': baseline['passed'],
             'checker_sha256': byte_sha(Path(__file__).read_bytes()), 'controls': results,
             'scope': 'Six small saved-observation controls from one unchanged B smoke recording. Each JSON records exact old/new patches and target failures. No engine execution or full performance acceptance.'}
    write_fresh(directory/'index.json', index)
    return index


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('record', 'plan', 'report', 'frame-batches', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--negative-controls', type=Path, help='Write the six patch-only controls into a new/empty directory')
    group.add_argument('--control', type=Path, help='Replay one saved exact-patch control against its bound original inputs')
    args = parser.parse_args()
    record, plan, report, frames, inputs = load_inputs(args.record, args.plan, args.report, args.frame_batches)
    if args.control:
        if not recheck(record, plan, report, frames, inputs)['passed']:
            raise ValueError('The original saved artifact baseline failed before control replay')
        result = replay_control(json.loads(args.control.read_text()), record, plan, report, inputs)
    else:
        result = recheck(record, plan, report, frames, inputs)
        if args.negative_controls:
            if not result['passed']:raise ValueError('Saved artifact baseline failed; do not generate negative controls')
            controls = negative_controls(args.negative_controls, record, plan, report, inputs)
            result['negative_controls'] = {'passed': controls['passed'], 'index': label(args.negative_controls/'index.json')}
            result['passed'] = result['passed'] and controls['passed']
    write_fresh(args.output, result)
    print(json.dumps({'passed': result['passed'], 'checks': len(result['checks']),
                      'failed': [c['name'] for c in result['checks'] if not c['passed']],
                      'negative_controls': result.get('negative_controls')}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

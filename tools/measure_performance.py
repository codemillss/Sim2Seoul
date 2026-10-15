#!/usr/bin/env python3
"""R01 native 1920x1080 rendering benchmark; full A=600s, B=1200s, smoke is diagnostic."""
import argparse
import bisect
import gzip
import hashlib
import json
import math
import platform
import re
import shutil
import statistics
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from check_vehicles_contract import FILES, ASSETS

ROOT = Path(__file__).resolve().parents[1]
PROOF = ['tests/game/measure_performance.gd', 'tools/measure_performance.py', 'tests/game/offline.sb']
PROFILES = {
    'A': {'id': 'R01-A-static-0NPC-0vehicle-v1', 'pedestrians': 0, 'vehicles': 0, 'duration_s': 600},
    'B': {'id': 'R01-B-V0-2NPC-2vehicle-v1', 'pedestrians': 2, 'vehicles': 2, 'duration_s': 1200},
}
API_SOURCES = {
    'performance': 'https://docs.godotengine.org/en/4.6/classes/class_performance.html',
    'rendering': 'https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html',
    'window': 'https://docs.godotengine.org/en/4.6/classes/class_window.html',
    'vsync': 'https://docs.godotengine.org/en/4.6/classes/class_displayserver.html',
    'viewport': 'https://docs.godotengine.org/en/4.6/classes/class_viewport.html',
    'sun': 'https://docs.godotengine.org/en/4.6/classes/class_directionallight3d.html',
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def probe(command, timeout=15):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return {'available': result.returncode == 0, 'command': command, 'returncode': result.returncode,
                'stdout': result.stdout.strip() or None, 'stderr': result.stderr.strip() or None}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'available': False, 'command': command, 'value': None, 'error': str(exc)}


def host_info():
    values = {key: probe(['/usr/sbin/sysctl', '-n', key]) for key in
              ('hw.model', 'hw.memsize', 'hw.physicalcpu', 'hw.logicalcpu', 'machdep.cpu.brand_string')}
    report = {'platform': platform.platform(), 'os': probe(['/usr/bin/sw_vers']), 'sysctl': values}
    profile = probe(['/usr/sbin/system_profiler', '-json', 'SPHardwareDataType', 'SPDisplaysDataType'], 30)
    # Do not publish machine serial numbers or hardware UUIDs in benchmark evidence.
    filtered = None
    if profile['available']:
        try:
            source = json.loads(profile['stdout'])
            hardware_keys = {'machine_name', 'machine_model', 'chip_type', 'number_processors', 'physical_memory'}
            gpu_keys = {'sppci_model', 'spdisplays_vendor', 'spdisplays_metal', 'spdisplays_cores', 'spdisplays_vram', '_spdisplays_vram'}
            filtered = {'SPHardwareDataType': [{k: v for k, v in row.items() if k in hardware_keys} for row in source.get('SPHardwareDataType', [])],
                        'SPDisplaysDataType': [{k: v for k, v in row.items() if k in gpu_keys} for row in source.get('SPDisplaysDataType', [])]}
        except (ValueError, TypeError):
            filtered = None
    report['system_profiler'] = {'available': filtered is not None, 'command': profile['command'],
                                 'returncode': profile.get('returncode'), 'selected_fields': filtered,
                                 'reason': None if filtered is not None else profile.get('error', 'No parseable supported fields')}
    return report


def system_state():
    return {'wall_unix_s': time.time(), 'swap': probe(['/usr/sbin/sysctl', 'vm.swapusage']),
            'memory_pressure_query': probe(['/usr/bin/memory_pressure', '-Q']),
            'power_source': probe(['/usr/bin/pmset', '-g', 'batt']),
            'power_settings': probe(['/usr/bin/pmset', '-g', 'custom']),
            'heavy_processes': heavy_processes()}


def heavy_processes():
    """Retain executable basenames and numeric load only, never arguments or paths."""
    try:
        result = subprocess.run(['/bin/ps', '-axo', 'pcpu=,rss=,comm='], capture_output=True, text=True, timeout=10)
        rows = []
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                try:
                    cpu, rss, command = line.split(maxsplit=2)
                    rows.append({'executable': Path(command).name, 'cpu_percent': float(cpu), 'rss_bytes': int(rss) * 1024})
                except ValueError:
                    continue
        return {'available': bool(rows), 'returncode': result.returncode,
                'top_cpu': sorted(rows, key=lambda row: row['cpu_percent'], reverse=True)[:12] if rows else None,
                'top_rss': sorted(rows, key=lambda row: row['rss_bytes'], reverse=True)[:12] if rows else None,
                'fields': 'ps comm basename, CPU percent and RSS only; no raw process output retained'}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'available': False, 'value': None, 'error_type': type(exc).__name__}


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    index = (len(ordered) - 1) * fraction
    low = int(math.floor(index)); high = int(math.ceil(index))
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def distribution(values):
    values = [v for v in values if isinstance(v, (float, int)) and math.isfinite(v)]
    if not values:
        return None
    return {'count': len(values), 'mean': statistics.fmean(values), 'min': min(values),
            'p50': percentile(values, .5), 'p95': percentile(values, .95), 'p99': percentile(values, .99), 'max': max(values)}


def frame_summary(rows, columns):
    index = columns.index('monotonic_frame_ms')
    elapsed = sum(row[index] for row in rows) / 1000.
    return {'frames': len(rows), 'covered_elapsed_s': elapsed,
            'average_fps': len(rows) / elapsed if elapsed > 0 else None,
            'frame_ms': distribution([row[index] for row in rows]),
            'monitors': {name: distribution([row[i] for row in rows]) for i, name in enumerate(columns)
                         if name not in ('t_end_s', 'monotonic_frame_ms', 'physics_tick', 'viewport_texture_width', 'viewport_texture_height', 'scaling_3d_scale', 'camera_clock_s', 'source_pose_index', 'source_tick')},
            'gpu_frame_time_ms': None}


def accepted_n04(path, motion_path, smoke):
    """Full measurement accepts the frozen N04 GPU evidence, never motion PASS alone."""
    bindings = {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p): sha(p)
                for p in (path, motion_path) if p.is_file()}
    if smoke:
        return {'formal_accepted': False, 'diagnostic_only': True, 'bound_files_sha256': bindings}
    canonical = ROOT / 'data/reports/n04/gpu.json.gz'
    report_path = ROOT / 'data/reports/n04/gpu_check.json'
    snapshot_path = ROOT / 'data/reports/n04/snapshot.json'
    if path.resolve() != canonical.resolve():
        raise ValueError('Full R01 requires the canonical frozen N04 GPU camera record')
    report = json.loads(report_path.read_text()); motion = json.loads(motion_path.read_text())
    snapshot = json.loads(snapshot_path.read_text())
    for value in (report, motion):
        checks = value.get('checks')
        if value.get('task') != 'N04' or value.get('passed') is not True or not isinstance(checks, list) or not checks or not all(c.get('passed') is True for c in checks):
            raise ValueError('Full N04 GPU and independent motion checks must both pass completely')
    named = {c.get('name'): c.get('passed') for c in report['checks']}
    if report.get('mode') != 'gpu' or not all(named.get(name) is True for name in ('source_unchanged', 'runtime_unchanged', 'proof_unchanged')):
        raise ValueError('N04 GPU report must include unchanged source, runtime and proof checks')
    for section, base in (('source_sha256', ROOT / 'game'), ('runtime_sha256', ROOT / 'game'), ('proof_sha256', ROOT)):
        table = report.get(section)
        if not isinstance(table, dict) or not table or any(not (base / p).is_file() or sha(base / p) != expected for p, expected in table.items()):
            raise ValueError('Current N04 producer bytes differ from the accepted GPU report: ' + section)
        bindings.update({str((base / p).relative_to(ROOT)): expected for p, expected in table.items()})
    if not (snapshot.get('schema_version') == 1 and snapshot.get('task') == 'N04' and snapshot.get('completed') is True and snapshot.get('next_task') == 'R01'):
        raise ValueError('Completed N04 snapshot handing off to R01 is required')
    evidence = snapshot.get('evidence_sha256', {})
    for bound in (path, motion_path, report_path):
        relative = str(bound.relative_to(ROOT))
        if evidence.get(relative) != sha(bound):
            raise ValueError('N04 snapshot does not bind the retained GPU raw/check bytes: ' + relative)
    bindings.update({str(p.relative_to(ROOT)): sha(p) for p in (report_path, snapshot_path)})
    return {'formal_accepted': True, 'diagnostic_only': False, 'bound_files_sha256': bindings,
            'acceptance': 'Complete GPU and independent motion PASS; current producer/runtime/proof bytes match; completed N04 snapshot binds all three GPU evidence files.'}


def camera_plan(path, smoke):
    """Extract only actual N04 journey camera poses; exclude recovery/injection phases."""
    source = json.loads(gzip.decompress(path.read_bytes()))
    journey = source['walk']['journey']; low = journey['first_physics_tick']; high = journey['last_physics_tick']
    samples = [s for s in source['timeline']['samples'] if low <= s['tick'] <= high]
    poses = [[(s['tick'] - low) / 60., s['tick'], s['walk']['rig']['camera'], s['walk']['rig']['basis'],
              s['walk']['rig']['fov'], s['walk']['rig']['near']] for s in samples]
    stages = {g['id']: sum(g['first_physics_tick'] <= s['tick'] <= g['last_physics_tick'] for s in samples)
              for g in journey['groups']}
    if source['task'] != 'N04' or source['suite'] != 'full' or len(stages) != 11 or not all(stages.values()):
        raise ValueError('Complete N04 record with all eleven journey stages required')
    if source['walk']['w03_sha256'] != sha(ROOT / 'game/data/generated/public_walk.json') or source['bundle_sha256'] != sha(ROOT / 'game/data/generated/traffic.json'):
        raise ValueError('Current W03/N03 runtime differs from the N04 source camera record')
    if len(source['walk']['cases']) != 334 or not poses or any(b[1] <= a[1] for a, b in zip(poses, poses[1:])):
        raise ValueError('N04 source leg/sample coverage is incomplete')
    checks_path = path.with_name(path.name.removesuffix('.json.gz') + '_motion_check.json')
    acceptance = accepted_n04(path, checks_path, smoke)
    if not smoke and (source['engine']['display'] == 'headless' or source.get('fault') != 'normal' or source.get('error') != ''):
        raise ValueError('Full benchmark requires the formally accepted rendered N04 camera trace')
    return {'id': 'R01-N04-actual-camera-discrete-300s-v1', 'period_s': 300., 'source_record': str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            'source_record_sha256': sha(path), 'source_check': str(checks_path.relative_to(ROOT)) if checks_path.is_relative_to(ROOT) else str(checks_path),
            'source_check_sha256': sha(checks_path) if checks_path.is_file() else None,
            'source_acceptance': acceptance,
            'source_engine': source['engine'], 'source_duration_s': journey['duration_s'], 'source_leg_count': 334,
            'source_first_tick': low, 'source_last_tick': high, 'stage_sample_counts': stages,
            'source_stage_ticks': {g['id']: [g['first_physics_tick'], g['last_physics_tick']] for g in journey['groups']},
            'pose_columns': ['source_t_s', 'source_tick', 'camera_position', 'basis_columns', 'fov_degrees', 'near_m'],
            'poses': poses, 'scope': 'Previous retained N04 camera pose without interpolation. All eleven actual W04 stages time-compressed to 300 seconds; current actors advance in real time, player remains at spawn. Original camera near-plane validation used the N04 source viewport; the wider benchmark viewport and time-compressed actor encounters are not walking/collision validation.'}


def audit(record, plan, profile, smoke):
    checks = []

    def ck(name, condition, **details):
        checks.append({'name': name, 'passed': bool(condition), **details})

    expected = PROFILES[profile]; rows = record['frames']; columns = record['frame_columns']
    ck('engine.native_metal_fixed', record['engine']['version'] == '4.7.2-stable (official)'
       and record['engine']['display'] != 'headless' and record['engine']['renderer'] == 'forward_plus'
       and record['engine']['driver'].lower() == 'metal')
    ck('engine.uncapped_60physics', record['engine']['max_fps'] == 0 and record['engine']['vsync_mode'] == 0
       and record['engine']['physics_hz'] == 60)
    ck('render.actual_1920x1080', all(v['width'] == 1920 and v['height'] == 1080 and v['scaling_3d_scale'] == 1.
       for v in record['resolution_proof'].values()))
    ck('render.actual_capture_saved', record['resolution_proof']['before'].get('png_save_error') == 0)
    width_index = columns.index('viewport_texture_width'); height_index = columns.index('viewport_texture_height')
    ck('render.every_frame_texture_size', bool(rows) and all(row[width_index] == 1920 and row[height_index] == 1080 for row in rows))
    scale_index = columns.index('scaling_3d_scale')
    ck('render.every_frame_internal_3d_scale', bool(rows) and all(row[scale_index] == 1. for row in rows))
    ck('clock.actual_complete', bool(rows) and record['duration_actual_s'] >= record['duration_requested_s']
       and len(rows) == record['frame_count']
       and all(len(row) == len(columns) for row in rows)
       and all(row[1] > 0 and math.isfinite(row[1]) for row in rows)
       and abs(rows[0][0] * 1000. - rows[0][1]) < .01
       and all(abs((b[0] - a[0]) * 1000. - b[1]) < .01 for a, b in zip(rows, rows[1:]))
       and abs(rows[-1][0] - record['duration_actual_s']) < 1e-6
       and abs(math.fsum(row[1] for row in rows) / 1000. - record['duration_actual_s']) < 1e-6)
    observations = record['second_observations']
    tick_index = columns.index('physics_tick')
    effective_hz = (record['last_physics_tick'] - record['first_physics_tick']) / record['duration_actual_s']
    ck('engine.actual_60physics', abs(effective_hz - 60.) <= .3 + 1. / record['duration_actual_s']
       and bool(rows) and rows[-1][tick_index] == record['last_physics_tick']
       and rows[0][tick_index] >= record['first_physics_tick']
       and all(b[tick_index] >= a[tick_index] for a, b in zip(rows, rows[1:])),
       effective_hz=effective_hz, tolerance_hz=.3 + 1. / record['duration_actual_s'])
    expected_observation_times = [0.]; next_second = 1.
    for row in rows:
        if row[0] >= next_second:
            expected_observation_times.append(row[0]); next_second = math.floor(row[0]) + 1.
    if rows and expected_observation_times[-1] < rows[-1][0]:
        expected_observation_times.append(rows[-1][0])
    frame_ticks_by_time = {row[0]: row[tick_index] for row in rows}
    ck('observations.exact_raw_frame_schedule_and_physics_join', bool(observations)
       and [s['t_s'] for s in observations] == expected_observation_times
       and observations[0]['physics_tick'] == record['first_physics_tick']
       and all(s['physics_tick'] == frame_ticks_by_time.get(s['t_s']) for s in observations[1:]))
    ck('render.observed_window_and_viewport_size', bool(observations) and all(s['window_size'] == [1920, 1080]
       and s['viewport_visible_size'] == [1920, 1080] for s in observations))
    conditions = record['render_conditions']
    ck('render.conditions_unchanged', conditions['before'] == conditions['after']
       and conditions['before']['scaling_3d_scale'] == 1.
       and all(s['camera_far'] == conditions['before']['camera_far_m'] for s in observations))
    ck('actors.actual_profile_count', bool(observations) and all(s['actors']['pedestrian_count'] == expected['pedestrians']
       and s['actors']['vehicle_count'] == expected['vehicles'] for s in observations))
    liveness = []
    if profile == 'B':
        for kind in ('pedestrians', 'vehicles'):
            ids = [body['route_id'] for body in observations[0]['actors'][kind]]
            cohort_ok = len(set(ids)) == 2 and all(set(body['route_id'] for body in s['actors'][kind]) == set(ids)
                for s in observations)
            ck('actors.' + kind + '.stable_unique_cohort', cohort_ok)
            if not cohort_ok:
                continue
            for identity in ids:
                track = [next(body for body in s['actors'][kind] if body['route_id'] == identity) for s in observations]
                counter_distance = track[-1]['actual_distance_m'] - track[0]['actual_distance_m']
                position_path = sum(math.dist(a['position'][::2], b['position'][::2]) for a, b in zip(track, track[1:])
                                    if kind != 'vehicles' or b['cycle_count'] == a['cycle_count'])
                # Cars may legally wait at endpoints until actual camera guards clear.
                # This is a liveness floor, not a required speed or cycle count.
                minimum = record['duration_requested_s'] * .2 if kind == 'pedestrians' else min(10., record['duration_requested_s'] * .2)
                row = {'kind': kind, 'route_id': identity, 'physics_steps_advanced': track[-1]['physics_steps'] - track[0]['physics_steps'],
                       'distance_counter_delta_m': counter_distance, 'position_path_excluding_recycle_jumps_m': position_path,
                       'station_range_m': max(s['station_m'] for s in track) - min(s['station_m'] for s in track),
                       'minimum_movement_m': minimum, 'endpoint_wait_sample_count': sum(s['state'] == 'endpoint_wait' for s in track)}
                liveness.append(row)
                ck('actors.' + identity + '.running_and_physics_advancing', all(s['running'] is True for s in track)
                   and len({s['instance_id'] for s in track}) == 1
                   and all(b['physics_steps'] > a['physics_steps'] for a, b in zip(track, track[1:]))
                   and all(b['physics_steps'] - a['physics_steps'] == ob['physics_tick'] - oa['physics_tick']
                           for a, b, oa, ob in zip(track, track[1:], observations, observations[1:])))
                ck('actors.' + identity + '.measurable_route_motion', counter_distance >= minimum and position_path >= minimum
                   and row['station_range_m'] >= .1
                   and all(b['actual_distance_m'] + .001 >= a['actual_distance_m'] for a, b in zip(track, track[1:])), **row)
    start = observations[0]['player_position']
    ck('setup.player_stationary_no_recovery', all(math.dist(s['player_position'][::2], start[::2]) <= .001
       and s['player_recoveries'] == 0 and not s['tree_paused'] for s in observations))
    ck('setup.actual_controls_and_spawn', record['setup']['input_disabled'] and record['setup']['interface_hidden']
       and record['setup']['camera_is_independent'] and record['setup']['traffic_camera_redirected'] == (profile == 'B')
       and math.dist(start[::2], record['setup']['source_spawn'][::2]) < .001)
    pose_times = [row[0] for row in plan['poses']]
    camera_clock_index = columns.index('camera_clock_s'); pose_index = columns.index('source_pose_index'); source_tick_index = columns.index('source_tick')
    # A physics-step camera pose may be one physics period plus the current
    # render interval behind post-draw time. It must never run ahead of time.
    frame_replay_ok = bool(rows)
    for row in rows:
        clock = row[camera_clock_index]
        index = max(0, bisect.bisect_right(pose_times, (clock % plan['period_s']) / plan['period_s'] * plan['source_duration_s']) - 1)
        frame_replay_ok &= (max(0., row[0] - row[1] / 1000. - 1. / 60. - .005) <= clock <= row[0] + .002
                            and row[pose_index] == index and row[source_tick_index] == plan['poses'][index][1])
    ck('camera.every_frame_clock_bound_and_source_index', frame_replay_ok
       and all(b[camera_clock_index] >= a[camera_clock_index] for a, b in zip(rows, rows[1:])),
       maximum_clock_lead_s=.002, lag_budget='current render interval + 1/60 second + 0.005 second')
    frame_by_time = {row[0]: row for row in rows}
    replay_ok = True
    for s in observations:
        phase = (s['camera_clock_s'] % plan['period_s']) / plan['period_s']
        index = max(0, bisect.bisect_right(pose_times, phase * plan['source_duration_s']) - 1)
        pose = plan['poses'][index]
        matching = frame_by_time.get(s['t_s'])
        sample_clock_bound = (s['t_s'] == 0. and s['camera_clock_s'] == 0.) or (matching is not None
            and s['camera_clock_s'] == matching[camera_clock_index] and s['source_pose_index'] == matching[pose_index]
            and s['source_tick'] == matching[source_tick_index])
        replay_ok &= (s['camera_current'] and 0. <= s['camera_clock_s'] <= s['t_s'] + .002
                      and sample_clock_bound
                      and s['source_pose_index'] == index and s['source_tick'] == pose[1]
                      and abs(s['source_t_s'] - pose[0]) < 1e-6 and math.dist(s['camera_position'], pose[2]) < .001
                      and all(math.dist(a, b) < .0001 for a, b in zip(s['camera_basis_columns'], pose[3]))
                      and abs(s['camera_fov'] - pose[4]) < .0001 and abs(s['camera_near'] - pose[5]) < 1e-7)
    ck('camera.actual_discrete_source_replay', replay_ok)
    ck('protocol.requested_duration', record['duration_requested_s'] == (5. if smoke else expected['duration_s'])
       and record['warmup_requested_s'] == (1. if smoke else 30.))
    ck('protocol.warmup_completed', record['warmup_actual_s'] >= record['warmup_requested_s'])
    summary = frame_summary(rows, columns)
    windows = []
    for index in range(math.ceil(record['duration_requested_s'] / 300.)):
        low, high = index * 300., min((index + 1) * 300., record['duration_requested_s'])
        chosen = [row for row in rows if low < row[0] <= high or (index == math.ceil(record['duration_requested_s'] / 300.) - 1 and row[0] > high)]
        observed_ticks = [s['source_tick'] for s in observations if low <= s['t_s'] < high]
        stages = [name for name, (a, b) in plan['source_stage_ticks'].items() if any(a <= tick <= b for tick in observed_ticks)]
        windows.append({'index': index + 1, 'nominal_start_s': low, 'nominal_end_s': high,
                        'source_stages_observed': stages, **frame_summary(chosen, columns)})
        if not smoke:
            ck(f'camera.window_{index + 1}.all_eleven_stages', len(stages) == 11)
    return checks, summary, windows, liveness


def memory_measurement(rss_rows, events, duration):
    starts = [e['since_process_spawn_s'] for e in events if e['line'].startswith('R01_MEASURE_START')]
    valid = []
    if len(starts) == 1:
        for row in rss_rows:
            offset = row['since_process_spawn_s'] - starts[0]
            if 0. <= offset <= duration and isinstance(row['rss_bytes'], (int, float)) and row['rss_bytes'] > 0:
                valid.append({'measurement_offset_s': offset, 'rss_bytes': row['rss_bytes']})
    margin = min(5., duration / 2.)
    first = valid[0]['measurement_offset_s'] if valid else None
    last = valid[-1]['measurement_offset_s'] if valid else None
    complete = (len(starts) == 1 and len(valid) >= max(2, math.floor(duration / 2.))
                and first <= margin and last >= duration - margin
                and all(b['measurement_offset_s'] - a['measurement_offset_s'] <= 5. for a, b in zip(valid, valid[1:])))
    edge_window = min(30., duration / 2.)
    return {'measurement_valid': complete, 'available': bool(valid), 'valid_sample_count': len(valid),
            'first_valid_offset_s': first, 'last_valid_offset_s': last,
            'rss_bytes_summary': distribution([s['rss_bytes'] for s in valid]),
            'start_rss_bytes_summary': distribution([s['rss_bytes'] for s in valid if s['measurement_offset_s'] <= edge_window]),
            'end_rss_bytes_summary': distribution([s['rss_bytes'] for s in valid if s['measurement_offset_s'] >= duration - edge_window]),
            'edge_window_s': edge_window, 'maximum_allowed_gap_s': 5., 'endpoint_margin_s': margin,
            'reason': None if complete else 'No complete valid RSS sample coverage across the measured interval; memory endurance is unmeasured.',
            'time_basis': 'ps sample start relative to monotonic receipt of R01_MEASURE_START. Excludes startup/warmup. Receipt and ps invocation add scheduling latency; this is periodic process RSS, not frame-synchronous memory.'}


def run_profile(profile, output, engine, smoke, plan, host):
    label = profile + ('_smoke' if smoke else '')
    raw_path = output / (label + '.json.gz')
    if raw_path.exists():
        raise RuntimeError('Preserve existing evidence; choose a fresh --output: ' + str(raw_path))
    source = {p: sha(ROOT / 'game' / p) for p in dict.fromkeys(FILES)}
    assets = {p: sha(ROOT / 'game' / p) for p in dict.fromkeys(ASSETS)}
    proof = {p: sha(ROOT / p) for p in PROOF}
    duration = 5 if smoke else PROFILES[profile]['duration_s']; warmup = 1 if smoke else 30
    state_before = system_state(); rss_rows = []; events = []; process_state = {'engine_pid': None}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-r01-') as temporary:
        game = Path(temporary) / 'game'
        for relative in dict.fromkeys(FILES + ASSETS):
            destination = game / relative; destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / relative, destination)
        helper = game / 'test_support/measure_performance.gd'; helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / PROOF[0], helper)
        plan_path = game / 'test_support/benchmark_camera.json'; write(plan_path, plan)
        plan_archive = output / (label + '_benchmark_camera.json.gz')
        plan_archive.write_bytes(gzip.compress(plan_path.read_bytes(), mtime=0))
        result_path = Path(temporary) / 'performance.json'
        runtime_only = not (game / '.godot').exists() and not (game / 'data/raw').exists() and not (game / '.venv-data').exists()
        command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine),
                   '--path', str(game), '--script', 'res://test_support/measure_performance.gd',
                   '--log-file', str(output / (label + '.log')), '--', '--automatic-probe', '--profile=' + profile,
                   '--result=' + str(result_path), '--capture=' + str(output / (label + '_render.png')),
                   '--duration=' + str(duration), '--warmup=' + str(warmup)]
        spawned = time.monotonic()
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

        def consume():
            with (output / (label + '.stdio.log')).open('w') as log:
                for line in process.stdout:
                    log.write(line); log.flush()
                    plain = re.sub(r'\x1b\[[0-9;]*m', '', line).strip()
                    match = re.match(r'R01_PID=(\d+)', plain)
                    if match:
                        process_state['engine_pid'] = int(match.group(1))
                    if plain.startswith(('R01_FIRST_FRAME', 'R01_READY', 'R01_MEASURE_START', 'R01_DONE')):
                        events.append({'line': plain, 'since_process_spawn_s': time.monotonic() - spawned,
                                       'meaning': 'Monotonic log-receipt time; includes process launch and log-delivery latency.'})
                    if plain.startswith(('R01_READY', 'R01_PROGRESS', 'R01_DONE')):
                        print(plain, flush=True)

        reader = threading.Thread(target=consume, daemon=True); reader.start()
        timed_out = False
        while process.poll() is None:
            elapsed = time.monotonic() - spawned
            pid = process_state['engine_pid']
            sample = {'since_process_spawn_s': elapsed, 'pid': pid, 'rss_bytes': None, 'ps_cpu_percent': None}
            if pid is not None:
                observation = probe(['/bin/ps', '-p', str(pid), '-o', 'rss=', '-o', '%cpu='], 5)
                sample['probe'] = observation
                if observation['available']:
                    try:
                        rss, cpu = observation['stdout'].split()
                        sample['rss_bytes'] = int(rss) * 1024; sample['ps_cpu_percent'] = float(cpu)
                    except (ValueError, AttributeError):
                        pass
            rss_rows.append(sample)
            if elapsed > duration + warmup + 180:
                timed_out = True; process.kill(); break
            time.sleep(1.)
        process.wait(); reader.join(timeout=10)
        process_elapsed = time.monotonic() - spawned
        batch_path = Path(str(result_path) + '.frames.jsonl')
        batch_archive = output / (label + '_frames.jsonl.gz')
        if batch_path.is_file():
            batch_archive.write_bytes(gzip.compress(batch_path.read_bytes(), mtime=0))
        record = json.loads(result_path.read_text()) if result_path.is_file() else None
        if record is not None:
            if not batch_path.is_file() or sha(batch_path) != record['frame_storage']['batch_file_sha256']:
                write(output / (label + '_frame_stream_failure.json'), {'engine_result': record,
                      'raw_frame_batches_retained': batch_archive.is_file(), 'frame_stream_sha256': sha(batch_path) if batch_path.is_file() else None})
                raise RuntimeError('R01 raw frame batch stream missing or changed: ' + label)
            record['frames'] = [row for line in batch_path.read_text().splitlines() for row in json.loads(line)]
            raw_path.write_bytes(gzip.compress((json.dumps(record, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode(), mtime=0))
        messages = (output / (label + '.stdio.log')).read_text(errors='replace')
        if record is None or process.returncode or timed_out or 'ERROR:' in messages:
            write(output / (label + '_failure.json'), {'returncode': process.returncode, 'timed_out': timed_out,
                  'fresh_result': record is not None, 'process_elapsed_s': process_elapsed, 'startup_events': events,
                  'system_before': state_before, 'system_after': system_state(), 'rss_samples': rss_rows,
                  'source_sha256': source, 'runtime_sha256': assets, 'proof_sha256': proof})
            raise RuntimeError('R01 engine failed; retained raw/log/failure: ' + label)
        checks, summary, windows, liveness = audit(record, plan, profile, smoke)
        checks.extend([
            {'name': 'copy.runtime_only_without_existing_cache', 'passed': runtime_only},
            {'name': 'camera.plan_checksum', 'passed': record['camera_plan_sha256'] == sha(plan_path)},
            {'name': 'engine.pid_matches_rss', 'passed': process_state['engine_pid'] == record['pid']},
            {'name': 'source.unchanged', 'passed': source == {p: sha(ROOT / 'game' / p) for p in source}},
            {'name': 'runtime.unchanged', 'passed': assets == {p: sha(ROOT / 'game' / p) for p in assets}},
            {'name': 'proof.unchanged', 'passed': proof == {p: sha(ROOT / p) for p in proof}},
            {'name': 'camera.source_record_unchanged', 'passed': sha(ROOT / plan['source_record']) == plan['source_record_sha256']},
            {'name': 'camera.source_check_unchanged', 'passed': plan['source_check_sha256'] is None
             or sha(ROOT / plan['source_check']) == plan['source_check_sha256']},
            {'name': 'camera.acceptance_binding_unchanged', 'passed': all((ROOT / p).is_file() and sha(ROOT / p) == expected
             for p, expected in plan['source_acceptance']['bound_files_sha256'].items())},
        ])
    memory = memory_measurement(rss_rows, events, record['duration_actual_s'])
    measurement_valid = all(c['passed'] for c in checks)
    report = {'task': 'R01', 'profile': PROFILES[profile], 'diagnostic_only': smoke,
              'measurement_valid': measurement_valid,
              'memory_measurement': memory,
              'memory_20minute_endurance_complete': not smoke and profile == 'B' and measurement_valid and memory['measurement_valid'] and record['duration_actual_s'] >= 1200.,
              'full_protocol_complete': not smoke and measurement_valid and memory['measurement_valid'], 'checks': checks,
              'summary': summary, 'windows': windows, 'actor_liveness': liveness, 'host': host, 'system_before': state_before,
              'physics_effective_hz': (record['last_physics_tick'] - record['first_physics_tick']) / record['duration_actual_s'],
              'system_after': system_state(), 'startup_log_receipt_events': events, 'process_elapsed_s': process_elapsed,
              'rss_samples': rss_rows, 'rss_bytes_summary': distribution([s['rss_bytes'] for s in rss_rows]),
              'rss_note': 'ps RSS is resident process memory; not total allocated, GPU memory, system memory pressure, or per-frame CPU time. Polls include startup/warmup and measurement. Per-frame data is streamed in short batches rather than retained throughout the benchmark; 1Hz actor/camera observations remain in memory.',
              'source_sha256': source, 'runtime_sha256': assets, 'proof_sha256': proof,
              'raw_sha256': sha(raw_path), 'frame_batches_sha256': sha(batch_archive), 'camera_plan': {k: v for k, v in plan.items() if k != 'poses'}, 'camera_plan_sha256': record['camera_plan_sha256'], 'camera_plan_archive_sha256': sha(plan_archive), 'api_sources': API_SOURCES,
              'target_proposal': {'p95_frame_ms': 33.3, 'met': summary['frame_ms']['p95'] <= 33.3, 'performance_target_adopted': False},
              'gpu_frame_time_ms': None, 'network': 'deny network*',
              'scope': 'Native engine outside editor; discrete replay of actual N04 camera poses, no physical walking validation. B is current V0 2/2, not the unsupported proposed 12/4 load. Full A two 300-second loops; full B four loops and 20-minute measured endurance. No exported package, human handling, installation or M4 acceptance.'}
    report['passed'] = report['full_protocol_complete']
    write(output / (label + '_performance.json'), report)
    print('R01', label, 'valid=', report['measurement_valid'], 'full_protocol=', report['full_protocol_complete'],
          'p95_ms=', summary['frame_ms']['p95'], 'failed=', [c['name'] for c in checks if not c['passed']], flush=True)
    return report['measurement_valid'] and memory['measurement_valid']


def main(args):
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([str(args.engine), '--version'], text=True).strip()
    if version != '4.7.2.stable.official.ed1daf0bf':
        raise RuntimeError('Fixed Godot 4.7.2 required: ' + version)
    plan = camera_plan(args.path_record.resolve(), args.smoke)
    host = host_info()
    profiles = ('A', 'B') if args.profile == 'all' else (args.profile,)
    results = [run_profile(profile, output, args.engine.resolve(), args.smoke, plan, host) for profile in profiles]
    return 0 if all(results) else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/reports/r01')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--profile', choices=['A', 'B', 'all'], default='all')
    parser.add_argument('--path-record', type=Path, default=ROOT / 'data/reports/n04/gpu.json.gz', help='Accepted N04 rendered record; smoke diagnostics may use a development headless record')
    parser.add_argument('--smoke', action='store_true', help='Five-second measurement after one-second warmup; never full R01 acceptance')
    raise SystemExit(main(parser.parse_args()))

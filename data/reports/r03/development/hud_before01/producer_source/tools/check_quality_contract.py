#!/usr/bin/env python3
"""R02 short V0 quality/UI regression in a fresh offline runtime-only copy."""
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

from check_vehicles_contract import FILES, ASSETS, HELPERS
from check_vehicles_evidence import STATIC_INVENTORY_SHA256, digest, finite
from check_urban_motion_evidence import Geometry, camera_ok, CAR_STEP, NPC_STEP, PLAYER_STEP, EPS

ROOT = Path(__file__).resolve().parents[1]
NEW_FILES = ['scripts/v0_walk.gd', 'scenes/world/v0_walk.tscn',
             'resources/quality_presets/standard.json', 'resources/quality_presets/low.json']
EXTRA_HELPERS = ['tests/game/check_vehicles.gd', 'tests/game/check_urban_motion.gd',
                 'tests/game/urban_motion_guidance.gd', 'tests/game/check_quality.gd']
PROOF = list(dict.fromkeys([*HELPERS, *EXTRA_HELPERS, 'tools/check_quality_contract.py',
    'tests/game/offline.sb', 'tools/check_urban_motion_evidence.py', 'tools/check_vehicles_evidence.py',
    'tools/check_palace_evidence.py', 'tools/check_walkable_evidence.py',
    'tests/game/measure_performance.gd', 'tools/measure_performance.py']))
SNAPSHOT = 'data/reports/n04/snapshot.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')


def quality(value, identity):
    return (value['preset_id'] == identity and value['runtime_ok'] is True
            and value['scaling_3d_scale'] == (1. if identity == 'standard' else .75)
            and value['sun_shadow_enabled'] is (identity == 'standard')
            and value['camera_far_m'] == 200. and value['pedestrian_count'] == value['vehicle_count'] == 2)


def audit(record, smoke):
    checks = []

    def ck(name, passed, **details):
        checks.append({'name': name, 'passed': bool(passed), **details})

    ck('record.identity_and_finite', record.get('task') == 'R02' and record.get('schema_version') == 1
       and record.get('error') == '' and finite(record))
    ck('engine.fixed', record['engine']['version'] == '4.7.2-stable (official)'
       and record['engine']['renderer'] == 'forward_plus' and record['engine']['physics_hz'] == 60)
    inventory = record['initial_inventory']
    ck('static.exact_frozen_inventory', digest(inventory, inventory=True) == STATIC_INVENTORY_SHA256
       and inventory == record['final_motion_inventory'])
    startup = record['startup_hud']
    for name, observed in [('before_capture', startup), ('after_capture', startup['after_capture'])]:
        x, y, width, height = observed['rect']; view_width, view_height = observed['viewport']
        ck('ui.startup_no_resize.' + name, observed['resize_calls'] == 0 and observed['viewport'] == [1152, 720]
           and quality(observed['quality'], 'standard') and width == 560 and 0 < height <= 200
           and abs(height - observed['combined_minimum'][1]) <= 1.
           and x >= 0 and y >= 0 and x + width <= view_width and y + height <= view_height
           and observed['overlaps_player'] is False, observation=observed)
    profiles = record['profiles']
    ck('profiles.both_present', [p['id'] for p in profiles] == ['standard', 'low'])
    geometry = Geometry(*[read(ROOT / p) for p in ('game/data/generated/traffic.json', 'game/data/generated/public_walk.json',
                        'game/resources/world_geometry/world.json', 'game/data/generated/daehanmun.json')])
    gate = read(ROOT / 'game/data/generated/daehanmun.json')['route_xz']
    original_instances = profiles[0]['instances_before'] if profiles else []
    for profile in profiles:
        identity = profile['id']; prefix = 'profile.' + identity
        ck(prefix + '.actual_display_and_signal', quality(profile['quality_after'], identity)
           and quality(profile['selection']['selected']['quality'], identity) and profile['selection']['signal_connected']
           and json.loads(profile['selection']['saved_text']) == {'schema_version': 1, 'preset_id': identity})
        ck(prefix + '.static_and_actor_identity_preserved', inventory == profile['before_inventory'] == profile['after_inventory']
           and profile['supports_before'] == profile['supports_after'] and len(profile['supports_before']) == 2
           and len(set(original_instances)) == 4 and original_instances == profile['instances_before'] == profile['instances_after'])
        timeline = profile['timeline']; stats = timeline['stats']; ticks = timeline['ticks']
        ck(prefix + '.clock_and_zero_reset', ticks == stats['ticks'] == timeline['last_tick'] - timeline['first_tick'] + 1
           and (ticks == 180 if smoke else 5400 <= ticks <= 6600)
           and stats['pose_calls'] == stats['recoveries'] == 0)
        ck(prefix + '.all_tick_physics_and_camera', stats['player_floor_ticks'] == ticks
           and stats['vehicle_floor_ticks'] == stats['npc_floor_ticks'] == ticks * 2
           and stats['vehicle_min_count'] == stats['vehicle_max_count'] == stats['npc_min_count'] == stats['npc_max_count'] == 2
           and stats['player_outside_ticks'] == stats['vehicle_human_contacts'] == 0
           and 0 <= stats['max_player_penetration_m'] <= EPS and 0 <= stats['max_camera_penetration_m'] <= EPS
           and 0 <= stats['max_npc_source_penetration_m'] <= EPS
           and 0 <= stats['max_player_step_m'] <= PLAYER_STEP and 0 <= stats['max_vehicle_step_m'] <= CAR_STEP
           and 0 <= stats['max_npc_step_m'] <= NPC_STEP
           and 0 <= stats['max_vehicle_y_m'] <= EPS and 0 <= stats['max_npc_y_m'] <= EPS
           and 0 <= stats['max_vehicle_speed_mps'] <= 5.01 and 0 <= stats['max_npc_speed_mps'] <= 1.2002
           and stats['max_camera_overlap_count'] == stats['max_near_hit_count'] == stats['max_tick_mismatch'] == 0
           and stats['max_follow_error_m'] <= .002 and stats['max_length_excess_m'] <= .002)
        samples = timeline['samples']
        ck(prefix + '.retained_actual_quality_unchanged', bool(samples) and all(quality(s['quality'], identity) for s in samples))
        ck(prefix + '.retained_source_geometry', bool(samples)
           and all(camera_ok(s['walk'], geometry, record['engine']['display'] != 'headless')
                   and all(geometry.car_ok(row)[0] for row in s['vehicles'])
                   and all(geometry.npc_ok(row)[0] for row in s['npcs']) for s in samples))
        ck(prefix + '.retained_tick_coverage', samples[0]['tick'] == timeline['first_tick']
           and samples[-1]['tick'] == timeline['last_tick']
           and all(1 <= b['tick'] - a['tick'] <= 6 for a, b in zip(samples, samples[1:])))
        for kind in ('npcs', 'vehicles'):
            for start in timeline['start'][kind]:
                end = next(row for row in timeline['end'][kind] if row['route_id'] == start['route_id'])
                track = [next(row for row in sample[kind] if row['route_id'] == start['route_id']) for sample in samples]
                path = sum(math.dist(a['position'][::2], b['position'][::2]) for a, b in zip(track, track[1:])
                           if kind != 'vehicles' or a['cycle_count'] == b['cycle_count'])
                delta = end['actual_distance_m'] - start['actual_distance_m']
                ck(prefix + '.' + start['route_id'] + '.actual_motion', delta >= .1 and path >= .1
                   and end['physics_steps'] - start['physics_steps'] == ticks and all(row['running'] is True for row in track),
                   counter_distance_m=delta, observed_path_m=path)
        if not smoke:
            legs = profile['legs']
            ck(prefix + '.entrance_both_directions', [r['name'] for r in legs] == [identity + '_gate_' + side + '_' + str(i)
               for side, indices in [('forward', [1, 2, 3]), ('reverse', [2, 1, 0])] for i in indices]
               and all(row['target_error_m'] <= .065 and row['recoveries'] == 0
                       and math.dist(row['target_xz'], gate[index]) <= .0002
                       and math.dist(row['end'][::2], gate[index]) <= .0652
                       for row, index in zip(legs, [1, 2, 3, 2, 1, 0])))
            requested = [s['walk']['rig']['requested_distance'] for s in samples]
            ck(prefix + '.near_far_camera_exercised', min(requested) <= 2.001 and max(requested) >= 5.999
               and any(s['walk']['rig']['distance'] + .1 < s['walk']['rig']['requested_distance'] for s in samples))
    ui = record['ui']
    ck('ui.esc_menu_pause_and_resume', ui['menu_open']['paused'] and ui['menu_open']['menu_visible']
       and not ui['menu_open']['camera_input_enabled'] and not ui['menu_open']['input_enabled']
       and ui['menu_drift_m'] <= .001 and not ui['resumed']['paused'] and not ui['resumed']['menu_visible']
       and ui['resumed']['camera_input_enabled'] and ui['resumed']['input_enabled'])
    for kind in ('npcs', 'vehicles'):
        ck('ui.' + kind + '.paused_and_switch_wiring',
           [v['physics_steps'] for v in ui['paused_actor_counters_before'][kind]] == [v['physics_steps'] for v in ui['menu_still'][kind]]
           and all(v['running'] is False for v in ui['switches_off'][kind] + ui['switches_off_resumed'][kind])
           and all(v['running'] is True for v in ui['switches_on'][kind])
           and all(math.dist(a['position'], b['position']) <= .001 for a, b in zip(ui['switches_off'][kind], ui['switches_off_resumed'][kind])))
        ck('ui.' + kind + '.actual_physics_resumed', all(b['physics_steps'] > a['physics_steps'] and b['running'] is True
           for a, b in zip(ui['switches_on'][kind], ui['resumed'][kind])))
    ck('ui.quality_signal_and_low_save', quality(ui['quality_low_signal']['quality'], 'low')
       and json.loads(ui['saved_low_text']) == {'schema_version': 1, 'preset_id': 'low'})
    ck('ui.popup_signal_escape_and_close_keep_menu_paused', ui['source_signal_connected']
       and ui['popup_open']['popup_visible'] and all(s['paused'] and s['menu_visible'] and not s['popup_visible']
       and not s['input_enabled'] for s in (ui['popup_escape'], ui['popup_button'], ui['popup_button_960'])))
    manual = ui['manual_recovery']
    ck('ui.separate_manual_recovery_button', manual['delta'] == 1 and manual['reason'] == 'manual_restart'
       and ui['manual_recovery_settled']['player']['floor'])
    layouts = record['layouts']
    ck('ui.both_viewport_sizes_recorded', [(r['name'], r['viewport']) for r in layouts]
       == [('menu_960', [960, 600]), ('popup_960', [960, 600]), ('popup_1152', [1152, 720]), ('hud_1152', [1152, 720])])
    for layout in layouts:
        width, height = layout['viewport']; controls = layout['controls']
        ck('ui.' + layout['name'] + '.all_visible_controls_inside', bool(controls) and all(
           x >= -.5 and y >= -.5 and w >= 0 and h >= 0 and x + w <= width + .5 and y + h <= height + .5
           for x, y, w, h in (row['rect'] for row in controls)), controls=controls)
        ck('ui.' + layout['name'] + '.readable_attribution_text',
           '© OpenStreetMap contributors, Overture Maps Foundation' in layout['attribution']
           and any(row.get('text') == layout['attribution'] for row in controls))
    menu_controls = layouts[0]['controls']
    ck('ui.required_menu_controls_visible', {'대한문 밖으로 복귀', '출처 보기', '종료', '화면 품질', '보행자 이동', '차량 이동', '돌아가기 · Esc'}
       .issubset({row.get('text') for row in menu_controls}) and any(row['class'] == 'OptionButton' for row in menu_controls))
    for layout in layouts[1:3]:
        popup_controls = layout['controls']
        ck('ui.' + layout['name'] + '.required_popup_controls_visible', any(row['path'].endswith('SourcesOverlay/SourcesPopup') for row in popup_controls)
           and any(row['path'].endswith('SourcesText') for row in popup_controls) and any(row.get('text') == '닫기 · Esc' for row in popup_controls))
    text = layouts[1]['source_display_text']
    ck('ui.sources_required_notices', all(value in text for value in ('Godot Engine', 'MIT', 'OpenStreetMap contributors',
       'Overture Maps Foundation', 'ODbL 1.0', 'Qian Shi et al. (2023)', '10.5281/zenodo.8174931', 'CC BY 4.0',
       '지역 조회', '좌표 변환', 'Kenney', 'City Kit Commercial 2.1', 'CC0 1.0', '수정', '추정', '실내', 'Copernicus', '보행 지면', '비공개', '접근 권한')))
    restarts = record['settings_restarts']
    ck('settings.explicit_restart_cases', [s['name'] for s in restarts] == ['fresh_standard', 'saved_low_restart', 'broken_json', 'unknown_id'])
    for row in restarts:
        identity = 'low' if row['name'] == 'saved_low_restart' else 'standard'
        ck('settings.' + row['name'], quality(row['state']['quality'], identity) and row['inventory'] == inventory
           and (row['name'] not in ('broken_json', 'unknown_id') or (row['state']['settings_recovered'] is True
                and '기본' in row['state']['notice'] and json.loads(row['recovered_saved_text']) == {'schema_version': 1, 'preset_id': 'standard'})))
    ck('settings.actor_recreation_confined_to_restart_phase', all(s['phase'] == 'settings_restart_only' for s in restarts)
       and len({tuple(s['state']['instances']) for s in restarts}) == len(restarts))
    return checks


def main(output, mode, engine, short=False):
    output = output.resolve()
    protected = [output / (mode + suffix) for suffix in ('.json.gz', '.log', '.stdio.log', '_check.json', '_failure.json')]
    if any(path.exists() for path in protected) or (output.exists() and any(output.glob(mode + '_view_*.png'))):
        raise RuntimeError('Preserve earlier evidence; select a fresh --output for this mode')
    output.mkdir(parents=True, exist_ok=True)
    snapshot = read(ROOT / SNAPSHOT)
    old_sources = snapshot['source_sha256']
    if snapshot.get('task') != 'N04' or snapshot.get('completed') is not True or any(not (ROOT / p).is_file() or sha(ROOT / p) != expected for p, expected in old_sources.items()):
        raise RuntimeError('Completed unchanged N04 source snapshot is required')
    core = {p: sha(ROOT / 'game' / p) for p in FILES}
    assets = {p: sha(ROOT / 'game' / p) for p in ASSETS}
    if any(snapshot.get('generated_sha256', {}).get('game/' + p) != expected for p, expected in assets.items()):
        raise RuntimeError('Prepared runtime differs from the accepted N04 snapshot')
    new_sources = {p: sha(ROOT / 'game' / p) for p in NEW_FILES}
    proof = {p: sha(ROOT / p) for p in PROOF}
    snapshot_sha = sha(ROOT / SNAPSHOT)
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if version != '4.7.2.stable.official.ed1daf0bf':raise RuntimeError('Fixed Godot 4.7.2 required')
    raw_path = output / (mode + '.json.gz'); log_path = output / (mode + '.log')
    with tempfile.TemporaryDirectory(prefix='sim2seoul-r02-') as temporary:
        game = Path(temporary) / 'game'
        for relative in dict.fromkeys(FILES + ASSETS + NEW_FILES):
            target = game / relative; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / relative, target)
        for relative in dict.fromkeys(HELPERS + EXTRA_HELPERS):
            target = game / 'test_support' / Path(relative).name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        runtime_only = not any((game / p).exists() for p in ('.godot', '.venv-data', 'data/raw'))
        result_path = Path(temporary) / 'quality.json'
        command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine)]
        if mode != 'gpu':command += ['--headless', '--fixed-fps', '60']
        diagnostic = mode == 'smoke' or short
        command += ['--path', str(game), '--script', 'res://test_support/check_quality.gd', '--log-file', str(log_path), '--',
                    '--automatic-probe', '--result=' + str(result_path), '--suite=' + ('smoke' if diagnostic else 'full'), '--render-fps=60']
        if mode == 'gpu':command += ['--capture-prefix=' + str(output / (mode + '_view'))]
        timed_out = False
        try:
            ran = subprocess.run(command, capture_output=True, text=True, timeout=900)
            messages = ran.stdout + ran.stderr; returncode = ran.returncode
        except subprocess.TimeoutExpired as exc:
            timed_out = True; returncode = None
            messages = ''.join(value.decode(errors='replace') if isinstance(value, bytes) else value
                               for value in (exc.stdout or '', exc.stderr or ''))
        (output / (mode + '.stdio.log')).write_text(messages)
        record = read(result_path) if result_path.is_file() else None
        if record is not None:
            raw_path.write_bytes(gzip.compress((json.dumps(record, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode(), mtime=0))
        messages = re.sub(r'\x1b\[[0-9;]*m', '', messages + (log_path.read_text(errors='replace') if log_path.is_file() else ''))
        if returncode or timed_out or record is None or 'ERROR:' in messages:
            write(output / (mode + '_failure.json'), {'task': 'R02', 'returncode': returncode, 'timed_out': timed_out,
                  'fresh_raw_retained': record is not None, 'core_sha256': core, 'new_source_sha256': new_sources, 'proof_sha256': proof})
            raise RuntimeError('R02 engine failure; raw and logs preserved in ' + str(output))
        checks = audit(record, diagnostic)
        for name, before, after in [('core_source_unchanged', core, {p: sha(ROOT / 'game' / p) for p in core}),
                                  ('runtime_unchanged', assets, {p: sha(ROOT / 'game' / p) for p in assets}),
                                  ('new_v0_source_unchanged', new_sources, {p: sha(ROOT / 'game' / p) for p in new_sources}),
                                  ('proof_unchanged', proof, {p: sha(ROOT / p) for p in proof})]:
            checks.append({'name': name, 'passed': before == after})
        checks.extend([{'name': 'copy.runtime_only', 'passed': runtime_only},
            {'name': 'frozen_n04_source_unchanged', 'passed': all((ROOT / p).is_file() and sha(ROOT / p) == expected for p, expected in old_sources.items())},
            {'name': 'frozen_n04_snapshot_unchanged', 'passed': snapshot_sha == sha(ROOT / SNAPSHOT)}])
        captures = {}
        if mode == 'gpu':
            for observed in record['captures']:
                image = output / (mode + '_view_' + observed['name'] + '.png')
                size = struct.unpack('>II', image.read_bytes()[16:24]) if image.is_file() else None
                captures[image.name] = {'sha256': sha(image) if image.is_file() else None, 'actual_png_size': size}
                checks.append({'name': 'capture.' + observed['name'], 'passed': size == (observed['width'], observed['height'])})
            checks.append({'name': 'capture.four_korean_ui_views', 'passed': [c['name'] for c in record['captures']] == ['startup_1152', 'menu_960', 'popup_1152', 'hud_1152']})
    valid = all(c['passed'] for c in checks)
    report = {'task': 'R02', 'mode': mode, 'short_requested': short, 'diagnostic_only': diagnostic, 'diagnostic_passed': valid,
              'passed': not diagnostic and valid, 'checks': checks, 'core_source_sha256': core,
              'runtime_sha256': assets, 'new_source_sha256': new_sources, 'proof_sha256': proof,
              'frozen_n04_snapshot_sha256': snapshot_sha, 'raw_sha256': sha(raw_path), 'captures': captures,
              'network': 'deny network*', 'visual_hangul_review_complete': False,
              'scope': 'Short V0 quality/UI regression with reused N04 geometry/camera observers. Full modes observe about 90 seconds per preset; smoke omits entrance legs and is diagnostic only. Actor recreation and manual recovery are explicit later phases. Original N04 full journey is not rerun or reaccepted; no performance improvement, twenty-minute endurance, human/M4 or package acceptance.'}
    write(output / (mode + '_check.json'), report)
    print('R02', mode, valid, len(checks), 'checks', [c['name'] for c in checks if not c['passed']], flush=True)
    return 0 if valid else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/r02_contract')
    parser.add_argument('--mode', choices=['smoke', 'contract', 'gpu'], default='contract')
    parser.add_argument('--short', action='store_true', help='Diagnostic three-second profiles with UI/startup checks; never full regression acceptance')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.mode, args.engine.resolve(), args.short))

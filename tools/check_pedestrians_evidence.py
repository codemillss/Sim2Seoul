#!/usr/bin/env python3
"""Independent N02 retained-trajectory audit, with no engine or generator imports.

Positions, stations, endpoint visits and contact clearance are independently
recomputed. Every-physics-tick extrema remain observer summaries, not raw traces.
The frozen static-inventory digest is from L04 gpu.json.gz inventory_before,
which preserves the accepted L03 692-created / 687-active static scene.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path

from check_daehanmun_evidence import number, vector, near, sub, norm, edges, volume_bounds
from check_palace_evidence import polygons, volume_from_mesh
from check_public_evidence import polygon_inside, indexed_penetration


STATIC_INVENTORY_SHA256 = '479a35612847e76a5660786355d85e30ebdaaf2c8ce461179fa578ef29bc3957'
# Horizontal request (.02m at 60Hz) with .2mm numerical tolerance.
# The earlier .021m contact allowance was rejected after floor-snap correction.
MAX_STEP_M = .0202
CASE_SECONDS = {'free_cycles': 280., 'manual_stop': 2., 'manual_resume': 3.,
                'brief_block': .8, 'clear_and_resume': 4., 'persistent_block': 5.,
                'player_push': 4., 'backoff': 2., 'escape': 6.}
SOURCE_ROUTES = {'palace_court': ('court_approach', 0, 11),
                 'plaza_front': ('city_plaza', 97, 98)}


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, list):
        return all(finite(v) for v in value)
    return True


def digest(value, *, pretty=False, sorted_keys=False):
    options = {'ensure_ascii': False, 'allow_nan': False, 'sort_keys': sorted_keys}
    options.update({'indent': 2} if pretty else {'separators': (',', ':')})
    return hashlib.sha256((json.dumps(value, **options)+'\n').encode()).hexdigest()


def inventory_digest(value):
    # This frozen historical digest used canonical JSON without a final newline.
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def project(point, line):
    """Nearest actual segment, returning distance and cumulative line station."""
    best = (math.inf, 0.)
    station = 0.
    for a, b in zip(line, line[1:]):
        d = sub(b, a)
        length = norm(d)
        if length <= 0:
            raise ValueError('zero-length route segment')
        fraction = max(0., min(1., sum(x*y for x, y in zip(sub(point, a), d))/length**2))
        distance = norm([point[i]-a[i]-fraction*d[i] for i in range(2)])
        if distance < best[0]:
            best = distance, station+fraction*length
        station += length
    return best


def angular_delta(a, b):
    return math.atan2(math.sin(b-a), math.cos(b-a))


def support_contains_capsule(point, support):
    """A horizontal radius .3 disk must fit inside one connected support polygon."""
    p = [point[0], point[2]]
    return any(polygon_inside(p, poly) and min(
        _edge_distance(p, a, b) for ring in poly for a, b in edges(ring)) >= .29998
        for poly in support)


def _edge_distance(p, a, b):
    d = sub(b, a)
    length2 = sum(v*v for v in d)
    t = max(0., min(1., sum(x*y for x, y in zip(sub(p, a), d))/length2)) if length2 else 0.
    return norm([p[i]-a[i]-t*d[i] for i in range(2)])


def audit(record, bundle, public, world, w01):
    """Pure in-memory audit; missing, malformed or non-finite evidence fails closed."""
    checks = []

    def ck(name, passed, details=None):
        item = {'name': name, 'passed': bool(passed)}
        if details is not None:
            item['details'] = details
        checks.append(item)

    try:
        ck('schema', record['schema_version'] == bundle['schema_version'] == 1
           and record['task'] == bundle['task'] == 'N02'
           and bundle['contract_id'] == 'N02-pedestrians-v1'
           and public['task'] == 'W03' and world['task'] == 'E03' and w01['task'] == 'W01')
        ck('finite_values', all(finite(v) for v in (record, bundle, public, world, w01)))
        ck('acceptance.full_suite', record['suite'] == 'full')
        ck('bundle.observed_sha256', record['bundle_sha256'] == digest(bundle, pretty=True))
        ck('bundle.source_geometry_hashes',
           bundle['source_sha256']['game/data/generated/public_walk.json'] == digest(public)
           and bundle['source_sha256']['game/resources/world_geometry/world.json'] == digest(world)
           and public['provenance']['game/data/generated/daehanmun.json'] == digest(w01))
        ck('bundle.coordinate_system', bundle['coordinate_system'] == world['coordinate_system'])
        ck('bundle.scope', bundle['scope'] == {
            'task': 'N02', 'pedestrians': 2, 'vehicles': 0, 'new_static_collision': 0,
            'source_permissions_unchanged': True, 'physical_terrain_access_verified': False,
            'human_handling_M4_verified': False})
        policy = bundle['policy']
        ck('bundle.policy', policy == {
            'speed_mps': 1.2, 'height_m': 1.7, 'radius_m': .3, 'gravity_mps2': 9.8,
            'end_dwell_s': .5, 'turn_radians_per_s': math.pi, 'clear_hold_s': .3,
            'retreat_after_s': 2., 'retreat_probe_m': .6, 'contact_margin_m': .1,
            'initial_phase': .5, 'initial_direction': 1, 'layer': 4, 'mask': 15})
        inventory = record['static_inventory']
        ck('static_inventory.exact_frozen_L03', inventory['created_body_count'] == 692
           and inventory['active_body_count'] == 687
           and inventory_digest(inventory) == STATIC_INVENTORY_SHA256)
        ck('static_inventory.after_unchanged', record['static_inventory_after'] == inventory)
        engine = record['engine']
        gpu = engine['display'].lower() != 'headless'
        ck('engine', engine['physics_hz'] == engine['render_fps'] == 60
           and bool(engine['version']) and bool(engine['display'])
           and (not gpu or engine['renderer'].lower() not in ('', 'headless')))

        parent = {r['id']: r for r in public['routes']}
        routes = {r['id']: r for r in bundle['routes']}
        ck('bundle.route_ids', len(bundle['routes']) == len(routes) == 2
           and set(routes) == set(SOURCE_ROUTES))
        for route_id, (parent_id, first, last) in SOURCE_ROUTES.items():
            route = routes[route_id]
            length = sum(norm(sub(b, a)) for a, b in zip(route['xz'], route['xz'][1:]))
            ck('bundle.'+route_id+'.source_line', route['xz'] == parent[parent_id]['xz'][first:last+1]
               and route['source_binding'] == {'parent_route': parent_id,
                    'first_vertex': first, 'last_vertex': last}
               and near(route['length_m'], length, 1e-8) and length > 1
               and route['ground_y_m'] == 0 and route['speed_mps'] == 1.2
               and route['repeat'] == 'ping_pong')
        descriptors = record['descriptors']
        ck('actors.count_and_routes', len(descriptors) == 2
           and {d['id'] for d in descriptors} == set(routes))
        for d in descriptors:
            ck('actors.'+d['id']+'.capsule_contract',
               near(d['height'], 1.7, 1e-6) and near(d['radius'], .3, 1e-6)
               and d['layer'] == 4 and d['mask'] == 15
               and near(d['safe_margin'], .001, 1e-6) and d['process_mode'] == 1)
        player = record['player_descriptor']
        ck('player.original_capsule_and_masks', near(player['height'], 1.7, 1e-6)
           and near(player['radius'], .3, 1e-6) and player['layer'] == 2
           and player['mask'] == 13 and player['camera_mask'] == 1)

        disabled = set(w01['disabled_source_ids'])
        solids = [m for m in world['meshes'] if m['role'] in ('Buildings', 'Barriers')
                  and m['id'] not in disabled]
        volumes = [v for mesh in solids for v in volume_from_mesh(mesh)]
        for obstacle in w01['volume_obstacles']:
            volumes.extend((poly, obstacle['bottom'], obstacle['top']) for poly in obstacle['rings'])
        movement = public['movement_rings']
        support = polygons(public['support']['geometry'])
        volumes.extend((poly, public['support']['bottom_y_m'], public['support']['top_y_m'])
                       for poly in support)
        bounds = volume_bounds(volumes)
        ck('independent_geometry.nonempty', bool(solids) and bool(volumes) and bool(movement)
           and bool(support))
        cases = {c['name']: c for c in record['cases']}
        ck('cases.complete_unique', len(cases) == len(record['cases'])
           and set(CASE_SECONDS).issubset(cases)
           and set(cases).issubset(set(CASE_SECONDS)|{'blocked_proxy'}))
        previous = None
        measured = {}
        for c in record['cases']:
            name = c['name']
            ticks = c['ticks']
            seconds = c['duration_s']
            samples = c['samples']
            stats = c['stats']
            ck(name+'.clock', type(ticks) is int and ticks > 0 and near(ticks/60, seconds, 1e-5)
               and c['last_tick']-c['first_tick']+1 == ticks
               and type(c['first_tick']) is int and c['first_tick'] > 0
               and c['wall_s'] > 0 and type(c['frames']) is int and c['frames'] >= 0
               and (name not in CASE_SECONDS or near(seconds,
                    12. if name == 'free_cycles' and record['suite'] == 'short'
                    else CASE_SECONDS[name], 1e-5)))
            expected_ticks = sorted({1, ticks, *range(6, ticks+1, 6)})
            ck(name+'.sample_clock', len(samples) == len(expected_ticks)
               and all(s['tick'] == c['first_tick']+tick-1 and near(s['t'], tick/60, 1e-5)
                       for s, tick in zip(samples, expected_ticks)))
            if previous is not None:
                ck(name+'.global_tick_order', c['first_tick'] > previous['last_tick'])
            if gpu:
                ck(name+'.real_clock', abs(c['wall_s']-seconds) <= .02*seconds
                   and abs(c['frames']/c['wall_s']-60) <= 12,
                   {'seconds': seconds, 'wall_s': c['wall_s'], 'frames': c['frames']})
            required_stats = ('min_npc_count', 'max_npc_count', 'max_step_m',
                'max_route_error_m', 'max_source_penetration_m', 'floor_ticks',
                'outside_ticks', 'min_player_distance_m', 'min_y', 'max_y', 'max_yaw_step_rad',
                'max_horizontal_velocity_mps', 'over_nominal_ticks')
            ck(name+'.all_tick_safety', all(number(stats[k]) for k in required_stats)
               and stats['min_npc_count'] == stats['max_npc_count'] == 2
               and 0 <= stats['max_step_m'] <= MAX_STEP_M
               and 0 <= stats['max_horizontal_velocity_mps'] <= 1.2002
               and 0 <= stats['max_route_error_m'] <= .005
               and 0 <= stats['max_source_penetration_m'] <= .005
               and stats['floor_ticks'] == 2*ticks and stats['outside_ticks'] == 0
               and stats['min_player_distance_m'] >= .595
               and -.005 <= stats['min_y'] <= stats['max_y'] <= .005
               and 0 <= stats['max_yaw_step_rad'] <= math.pi/60+.001)
            examples = stats['contact_examples']
            ck(name+'.contact_allowance_evidence', type(stats['over_nominal_ticks']) is int
               and 0 <= stats['over_nominal_ticks'] <= 2*ticks
               and len(examples) == min(stats['over_nominal_ticks'], 8)
               and (stats['max_step_m'] <= .0202 or bool(examples))
               and all(e['route_id'] in routes and .0202 < e['step_m'] <= MAX_STEP_M
                   and e['step_m'] <= stats['max_step_m']+.000001
                   and bool(e['contacts']) and all(vector(hit['normal'])
                       and near(norm(hit['normal']), 1., .002) and 0 <= hit['depth_m'] <= .005
                       for hit in e['contacts']) for e in examples))
            tracks = {id: [] for id in routes}
            failed = []
            for index, s in enumerate(samples):
                p = s['player']
                rows = s['npcs']
                player_point = p['position']
                player_penetration = indexed_penetration(
                    [player_point[0], player_point[1]+.85, player_point[2]], volumes, bounds, .3, .55)
                okay = (vector(p['position']) and vector(p['velocity']) and p['recoveries'] == 0
                        and p['floor'] is True and p['inside_movement'] is True
                        and p['camera_mask'] == 1 and abs(player_point[1]) <= .005
                        and any(polygon_inside(player_point[::2], poly) for poly in movement)
                        and player_penetration <= .005
                        and near(p['penetration_m'], player_penetration, .0001)
                        and len(rows) == 2 and {n['route_id'] for n in rows} == set(routes))
                for n in rows:
                    route = routes[n['route_id']]
                    point = n['position']
                    route_error, station = project(point[::2], route['xz'])
                    penetration = indexed_penetration([point[0], point[1]+.85, point[2]],
                                                       volumes, bounds, .3, .55)
                    distance = norm(sub(point[::2], p['position'][::2]))
                    okay = (okay and vector(point) and vector(n['velocity'])
                        and abs(point[1]) <= .005 and n['on_floor'] is True
                        and n['floor_id'] == 'W03_support' and n['inside_movement'] is True
                        and any(polygon_inside(point[::2], poly) for poly in movement)
                        and support_contains_capsule(point, support)
                        and route_error <= .005 and near(n['station_m'], station, .005)
                        and 0 <= n['station_m'] <= route['length_m']+.005
                        and n['direction'] in (-1, 1) and n['physics_steps'] > 0
                        and n['state'] in ('walking', 'waiting', 'blocked', 'dwell',
                                           'endpoint_wait', 'turning', 'paused')
                        and penetration <= .005 and near(n['penetration_m'], penetration, .0001)
                        and stats['max_source_penetration_m']+.0001 >= penetration
                        and stats['max_route_error_m']+.0001 >= route_error
                        and stats['min_player_distance_m'] <= distance+.0001
                        and stats['min_y']-.0001 <= point[1] <= stats['max_y']+.0001
                        and distance >= .595 and norm(n['velocity'][::2]) <= 1.2002
                        and norm(n['velocity'][::2]) <= stats['max_horizontal_velocity_mps']+.00002
                        and abs(n['velocity'][1]) <= .001)
                    tracks[n['route_id']].append((s, n, station))
                if not okay:
                    failed.append(index)
            ck(name+'.independent_samples', not failed, {'failed_sample_indices': failed[:25]})
            ck(name+'.player_continuous_within_case', all(
                norm(sub(b['player']['position'], a['player']['position']))
                    <= 3.5*(b['t']-a['t'])+.005
                for a, b in zip(samples, samples[1:])))
            for id, track in tracks.items():
                start = next(n for n in c['start'] if n['route_id'] == id)
                end = next(n for n in c['end'] if n['route_id'] == id)
                ck(name+'.'+id+'.case_endpoints', near(start['position'], track[0][1]['position'], MAX_STEP_M)
                   and near(end['position'], track[-1][1]['position'], .0001)
                   and end['physics_steps']-start['physics_steps'] == ticks
                   and all(n['physics_steps'] == start['physics_steps']+tick
                           for (_, n, _), tick in zip(track, expected_ticks)))
                distance_budget = 1.2*seconds+.005
                retained_distance = sum(norm(sub(b[1]['position'][::2], a[1]['position'][::2]))
                                        for a, b in zip(track, track[1:]))
                ck(name+'.'+id+'.cumulative_speed_budget',
                   0 <= end['actual_distance_m']-start['actual_distance_m'] <= distance_budget
                   and retained_distance <= distance_budget,
                   {'actual_distance_m': end['actual_distance_m']-start['actual_distance_m'],
                    'retained_distance_m': retained_distance, 'maximum_m': distance_budget})
                ck(name+'.'+id+'.retained_motion_bounds', all(
                    norm(sub(b[1]['position'][::2], a[1]['position'][::2]))
                        <= MAX_STEP_M*(b[0]['tick']-a[0]['tick'])+.00002
                    and norm(sub(b[1]['position'][::2], a[1]['position'][::2]))
                        <= (b[0]['tick']-a[0]['tick'])*stats['max_step_m']+.0002
                    and abs(b[2]-a[2]) <= 1.2*(b[0]['t']-a[0]['t'])+.005
                    and abs(angular_delta(a[1]['visual_yaw_rad'], b[1]['visual_yaw_rad']))
                        <= math.pi*(b[0]['t']-a[0]['t'])+.001
                    and abs(angular_delta(a[1]['visual_yaw_rad'], b[1]['visual_yaw_rad']))
                        <= (b[0]['tick']-a[0]['tick'])*stats['max_yaw_step_rad']+.001
                    and norm(sub(b[1]['position'][::2], a[1]['position'][::2]))-.0002
                        <= b[1]['actual_distance_m']-a[1]['actual_distance_m']
                        <= MAX_STEP_M*(b[0]['tick']-a[0]['tick'])+.00002
                    for a, b in zip(track, track[1:])))
            measured[name] = tracks
            previous = c

        # Continuity is physical. Scenario setup may move the player, never NPCs.
        for a, b in zip(record['cases'], record['cases'][1:]):
            ck(b['name']+'.npc_continuity', all(
                norm(sub(x['position'][::2], y['position'][::2])) <= MAX_STEP_M*max(
                    0, y['physics_steps']-x['physics_steps'])+.0001
                and y['physics_steps']-x['physics_steps'] == b['first_tick']-a['last_tick']-1
                for x, y in zip(a['end'], b['start'])))

        free = measured['free_cycles']
        initial = {n['route_id']: n for n in record['initial_npcs']}
        ck('actors.initial_count', len(initial) == len(record['initial_npcs']) == 2
           and set(initial) == set(routes))
        for id, track in free.items():
            length = routes[id]['length_m']
            visits = []
            end_groups = []
            group = []
            for sample, n, station in track:
                # Dwell/turn lasts much longer than the .1s retained interval,
                # so endpoint arrival must be observed within one centimetre.
                side = 0 if station <= .01 else 1 if station >= length-.01 else None
                if side is not None and (not visits or visits[-1] != side):
                    visits.append(side)
                if side is None:
                    if group:
                        end_groups.append(group)
                    group = []
                else:
                    group.append((sample, n, station))
            if group:
                end_groups.append(group)
            distance = sum(abs(b[2]-a[2]) for a, b in zip(track, track[1:]))
            start = next(n for n in cases['free_cycles']['start'] if n['route_id'] == id)
            initial_error, initial_station = project(initial[id]['position'][::2], routes[id]['xz'])
            ck('free_cycles.'+id+'.initial_phase', initial_error <= .005
               and near(initial_station, length*.5, .005)
               and near(initial[id]['station_m'], initial_station, .005)
               and initial[id]['direction'] == 1 and initial[id]['physics_steps'] == 0
               and start['physics_steps'] >= 0
               and norm(sub(start['position'], initial[id]['position']))
                   <= MAX_STEP_M*start['physics_steps']+.0001)
            if record['suite'] == 'short':
                continue
            ck('free_cycles.'+id+'.observed_two_cycles', len(visits) >= 4
               and distance >= 4*length-.5
               and track[-1][1]['end_events']-start['end_events'] >= 4
               and track[-1][1]['completed_cycles']-start['completed_cycles'] >= 2,
               {'alternating_endpoint_visits': visits, 'retained_station_distance_m': distance,
                'two_cycle_distance_m': 4*length})
            actual_turns = []
            for group in end_groups:
                angle = sum(abs(angular_delta(a[1]['visual_yaw_rad'], b[1]['visual_yaw_rad']))
                            for a, b in zip(group, group[1:]))
                still = sum(b[0]['t']-a[0]['t'] for a, b in zip(group, group[1:])
                            if norm(sub(b[1]['position'][::2], a[1]['position'][::2])) <= .0002)
                if angle >= 2.8 and still >= .4:
                    actual_turns.append({'angle_rad': angle, 'still_s': still})
            ck('free_cycles.'+id+'.observed_stop_then_turn', len(actual_turns) >= 4,
               {'observed_endpoint_turns': actual_turns})

        target_id = cases['brief_block']['target_route_id']
        ck('contact.target_route', target_id == 'plaza_front'
           and all(c['target_route_id'] == target_id for c in record['cases']))
        target = {name: rows[target_id] for name, rows in measured.items()}
        def travel(name):
            t = target[name]
            return sum(abs(b[2]-a[2]) for a, b in zip(t, t[1:]))
        def player_drift(name):
            samples = cases[name]['samples']
            start = samples[0]['player']['position']
            return max(norm(sub(s['player']['position'], start)) for s in samples)

        ck('manual_stop.actual_stationary', all(
            sum(abs(b[2]-a[2]) for a, b in zip(track, track[1:])) <= .005
            and all(norm(n['velocity']) <= .001 for _, n, _ in track)
            for track in measured['manual_stop'].values()))
        resume_start = next(n for n in cases['manual_resume']['start'] if n['route_id'] == target_id)
        resume_station = project(resume_start['position'][::2], routes[target_id]['xz'])[1]
        end_distance = routes[target_id]['length_m']-resume_station if resume_start['direction'] == 1 else resume_station
        # The source endpoint can legitimately consume .5s dwell + 1s rotation.
        minimum_resume = max(1.2*(3.-1.6), min(end_distance, 1.2*3.))-.1
        ck('manual_resume.actual_progress', travel('manual_resume') >= minimum_resume,
           {'retained_distance_m': travel('manual_resume'), 'minimum_source_feasible_m': minimum_resume})
        ck('brief_block.actual_stop_without_player_push', travel('brief_block') <= 1.
           and player_drift('brief_block') <= .005
           and any(n['state'] in ('waiting', 'blocked') and bool(n['blocked_reason'])
                   for _, n, _ in target['brief_block'])
           and norm(target['brief_block'][-1][1]['velocity']) <= .001)
        ck('clear_and_resume.actual_progress', travel('clear_and_resume') >= 3.)
        persistent = target['persistent_block']
        initial_direction = persistent[0][1]['direction']
        reverse_displacement = (persistent[-1][2]-persistent[0][2])*initial_direction
        ck('persistent_block.reverse_and_retreat', player_drift('persistent_block') <= .005
           and reverse_displacement <= -.5
           and any(n['direction'] == -initial_direction for _, n, _ in persistent)
           and any(n['state'] in ('waiting', 'blocked') for _, n, _ in persistent),
           {'signed_original_direction_displacement_m': reverse_displacement})
        push = cases['player_push']['samples']
        player_distance = sum(norm(sub(b['player']['position'], a['player']['position']))
                              for a, b in zip(push, push[1:]))
        ck('player_push.actual_approach_without_npc_displacement', player_distance >= .1
           and travel('player_push') <= .005
           and any(norm(s['player']['velocity'][::2]) > .1 for s in push))
        backoff = cases['backoff']['samples']
        backoff_delta = sub(backoff[-1]['player']['position'], backoff[0]['player']['position'])
        escape = cases['escape']['samples']
        escape_delta = sub(escape[-1]['player']['position'], escape[0]['player']['position'])
        player_distance = sum(norm(sub(b['player']['position'], a['player']['position']))
                              for a, b in zip(escape, escape[1:]))
        ck('escape.actual_backoff_then_forward', norm(backoff_delta) >= 2.
           and sum(a*b for a, b in zip(backoff_delta, escape_delta)) <= -1.)
        ck('escape.actual_player_and_npc_progress', player_distance >= 2.
           and norm(escape_delta) >= 1.
           and travel('escape') >= 2.)
        menu = record['menu_event']
        ck('menu_pause.engine_paused_and_still', menu['opened'] is True and menu['closed'] is True
           and menu['tree_paused'] is True and menu['wall_s'] > 0
           and (not gpu or menu['wall_s'] >= .2)
           and len(menu['hold_before']) == len(menu['after']) == 2
           and all(a['route_id'] == b['route_id'] and a['physics_steps'] == b['physics_steps']
                   and near(a['position'], b['position'], .0001)
                   for a, b in zip(menu['hold_before'], menu['after']))
           and near(menu['player_before']['position'], menu['player_after']['position'], .0001))
        spawn = record['spawn_event']
        ck('spawn.duplicate_rejected_no_leak', spawn['attempt_return'] is False
           and spawn['before'] == spawn['after'] == 2)
    except (KeyError, TypeError, ValueError, IndexError, ZeroDivisionError, OverflowError, StopIteration) as exc:
        ck('evidence_structure', False, {'error': type(exc).__name__+': '+str(exc)})
    return {'schema_version': 1, 'task': 'N02', 'passed': bool(checks) and all(c['passed'] for c in checks),
            'checks': checks, 'scope': 'Independent source geometry and retained trajectories; all-tick extrema are observer summaries. Human controls, visual quality, M4 hardware and N04 endurance remain separate.'}


def read(path):
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rt') as stream:
        return json.load(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('record', 'bundle', 'public', 'world', 'w01'):
        parser.add_argument('--'+name, required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = audit(*(read(getattr(args, name)) for name in ('record', 'bundle', 'public', 'world', 'w01')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print(json.dumps({'passed': result['passed'], 'checks': len(result['checks']),
                      'failed': [c['name'] for c in result['checks'] if not c['passed']]}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

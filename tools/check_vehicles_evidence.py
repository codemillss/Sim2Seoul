#!/usr/bin/env python3
"""Independent N03 retained-observation audit; no engine/controller/generator imports.

Whole oriented car footprints, source stations, support components, crossing
ownership and the raw frustum planes are recomputed. Physics-tick extrema are
observer summaries, not retained tick traces. Independent scenario resets are
explicit, and the short parser suite can never earn full acceptance.
"""
import argparse
import gzip
import hashlib
import json
import math
import struct
from pathlib import Path

from shapely import union_all
from shapely.errors import GEOSException
from shapely.geometry import LineString, Point, Polygon, shape
from shapely.prepared import prep
from shapely.strtree import STRtree

from check_palace_evidence import volume_from_mesh


STATIC_INVENTORY_SHA256 = '479a35612847e76a5660786355d85e30ebdaaf2c8ce461179fa578ef29bc3957'
# Frozen accepted N01 route payloads, including source binding/domain/conflicts.
# This prevents a caller replacing both a route and its observed stations.
ROUTE_SHA256 = {
    'sejong_south': 'a0455cd483d30f4f2d2a0d54d0bf9c0d5e19a7ab2a35e98e4dc58f51ec890b7c',
    'sejong_north': '44540d02879c29968f53dc277ccc0be6b34b6653125cf2736a7d5d1cecfe5d23',
}
CASE_SECONDS = {
    'free_cycles': 150., 'occupied_queue': 55., 'clear_short': .8,
    'release_fifo': 16., 'stale_hold': 3., 'fresh_resume': 6.,
    'late_human': 3., 'late_clear': 7., 'npc_obstacle': 22., 'npc_clear': 7.,
    'player_push': 12., 'player_backoff': 3., 'player_exit': 10.,
    'visible_guard': 70., 'near_human_guard': 2., 'entry_guard': 2.,
    'recycle_release': 3., 'manual_stop': 2., 'manual_resume': 3.,
}
MAX_STEP_M = 5. / 60. + .001
EPS = .005


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return all(finite(v) for v in value)
    return True


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def vector(value, n=3):
    return isinstance(value, list) and len(value) == n and all(number(v) for v in value)


def near(a, b, tolerance=1e-6):
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(near(x, y, tolerance) for x, y in zip(a, b))
    return number(a) and number(b) and abs(a-b) <= tolerance


def digest(value, *, pretty=False, inventory=False):
    options = {'ensure_ascii': False, 'allow_nan': False}
    options.update({'sort_keys': True, 'separators': (',', ':')} if inventory else
                   {'indent': 2} if pretty else {'separators': (',', ':')})
    payload = json.dumps(value, **options) + ('' if inventory else '\n')
    return hashlib.sha256(payload.encode()).hexdigest()


def project(point, line):
    """Closest actual source segment and cumulative arc station, independently."""
    best = (math.inf, 0.)
    station = 0.
    for a, b in zip(line, line[1:]):
        dx, dz = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dz)
        if length <= 0:
            raise ValueError('zero source segment')
        t = max(0., min(1., ((point[0]-a[0])*dx+(point[1]-a[1])*dz)/length**2))
        error = math.dist(point, [a[0]+dx*t, a[1]+dz*t])
        if error < best[0]:
            best = error, station+t*length
        station += length
    return best


def car_corners(position, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    return [[position[0]+c*x+s*z, position[1]+y, position[2]-s*x+c*z]
            for x in (-.9, .9) for y in (0., 1.5) for z in (-2.1, 2.1)]


def car_polygon(position, yaw):
    return Polygon([(p[0], p[2]) for p in car_corners(position, yaw)]).convex_hull


def portal_corners(route, ending):
    a, b = route['xz'][-2:] if ending else route['xz'][:2]
    p = route['xz'][-1] if ending else route['xz'][0]
    return car_corners([p[0], 0., p[1]], math.atan2(-(b[0]-a[0]), -(b[1]-a[1])))


def outside_frustum(corners, planes, reference):
    """A separating plane must put all eight corners outside the inside halfspace."""
    if len(planes) != 6 or len(corners) != 8 or not vector(reference):
        return False
    for plane in planes:
        n, d = plane['normal'], plane['d']
        if not vector(n) or not number(d) or not near(math.sqrt(sum(v*v for v in n)), 1., .0001):
            return False
    for plane in planes:
        n, d = plane['normal'], plane['d']
        inside = sum(x*y for x, y in zip(n, reference))-d
        sign = 1. if inside > 0 else -1. if inside < 0 else 0.
        if sign and all((sum(x*y for x, y in zip(n, p))-d)*sign < -.001 for p in corners):
            return True
    return False


def audit(record, bundle, public, world, w01):
    """Pure audit of supplied JSON values. Missing/non-finite evidence fails closed."""
    checks = []

    def ck(name, passed, details=None):
        row = {'name': name, 'passed': bool(passed)}
        if details is not None:
            row['details'] = details
        checks.append(row)

    try:
        ck('schema', record['schema_version'] == bundle['schema_version'] == 1
           and record['task'] == bundle['task'] == 'N03'
           and bundle['contract_id'] == 'N03-traffic-v1'
           and public['task'] == 'W03' and world['task'] == 'E03' and w01['task'] == 'W01')
        ck('finite_values', all(finite(v) for v in (record, bundle, public, world, w01)))
        ck('acceptance.full_suite', record['suite'] == 'full')
        ck('bundle.observed_sha256', record['bundle_sha256'] == digest(bundle, pretty=True))
        ck('bundle.source_geometry_hashes',
           bundle['source_sha256']['game/data/generated/public_walk.json'] == digest(public)
           and bundle['source_sha256']['game/resources/world_geometry/world.json'] == digest(world)
           and public['provenance']['game/data/generated/daehanmun.json'] == digest(w01))
        ck('bundle.coordinate_system', bundle['coordinate_system'] == world['coordinate_system'])
        ck('bundle.scope', bundle['scope'] == {'task': 'N03', 'vehicles': 2, 'pedestrians': 2,
           'new_vehicle_supports': 2, 'player_boundary_changed': False,
           'physical_terrain_access_verified': False})
        actor = bundle['actor']
        ck('bundle.actor', actor == {'length_m': 4.2, 'width_m': 1.8, 'height_m': 1.5,
           'swept_radius_m': 2.6, 'speed_mps': 5., 'acceleration_mps2': 1.5,
           'gravity_mps2': 9.8, 'safe_margin_m': .001, 'layer': 8, 'mask': 31})
        policy = bundle['policy']
        ck('bundle.policy', policy['priority'] == ['player_and_pedestrian', 'vehicle_already_inside', 'fifo_waiting_vehicle']
           and policy['brake_mps2'] == 3. and policy['reaction_s'] == .5
           and policy['stop_margin_m'] == 1. and policy['crossing_clearance_m'] == .35
           and policy['clear_hold_s'] == 1. and policy['max_observation_age_s'] == .1
           and policy['unknown_occupancy'] == 'stop' and policy['zone_vehicle_capacity'] == 1
           and policy['timeout_forced_entry'] is False
           and policy['vehicle_recycle'] == {'both_portals_outside_actual_camera_frustum': True,
               'minimum_human_distance_m': 30., 'dynamic_entry_envelope_empty': True,
               'hold_until_eligible': True, 'spatial_connection_between_portals': False})
        ck('bundle.collision_extension', bundle['rules']['vehicle'] == {'layer': 8, 'mask': 31}
           and bundle['rules']['vehicle_support'] == {'layer': 16, 'mask': 8}
           and bundle['rules']['unchanged'] == {'player_mask': 13, 'pedestrian_mask': 15, 'camera_mask': 1})

        inventory = record['initial_inventory']
        ck('static_inventory.exact_frozen_L03', inventory['created_body_count'] == 692
           and inventory['active_body_count'] == 687 and digest(inventory, inventory=True) == STATIC_INVENTORY_SHA256)
        sessions = {s['index']: s for s in record['sessions']}
        ck('sessions.unique_and_inventory_unchanged', len(sessions) == len(record['sessions'])
           and all(s['inventory_after'] == inventory for s in sessions.values()))
        engine = record['engine']
        gpu = engine['display'].lower() != 'headless'
        ck('engine', engine['physics_hz'] == engine['render_fps'] == 60
           and bool(engine['version']) and bool(engine['display'])
           and (not gpu or engine['renderer'].lower() not in ('', 'headless')))
        routes = {r['id']: r for r in bundle['routes']}
        ck('bundle.route_ids', len(routes) == len(bundle['routes']) == 2 and set(routes) == set(ROUTE_SHA256))
        for id, route in routes.items():
            ck('bundle.'+id+'.frozen_N01_source', digest(route) == ROUTE_SHA256[id])
        descriptors = record['descriptors']
        ck('actors.count_and_routes', len(descriptors) == 2 and {d['id'] for d in descriptors} == set(routes))
        for d in descriptors:
            ck('actors.'+d['id']+'.body', near(d['size'], [1.8, 1.5, 4.2], 1e-5)
               and d['layer'] == 8 and d['mask'] == 31 and d['priority'] == 1
               and near(d['safe_margin'], .001, 1e-6))

        original_support = shape(public['support']['geometry'])
        supports = {s['route_id']: s for s in bundle['supports']}
        ck('supports.exact_count', len(supports) == len(bundle['supports']) == 2 and set(supports) == set(routes))
        for id, support in supports.items():
            g = shape(support['geometry'])
            expected = shape(routes[id]['swept_geometry']).difference(original_support)
            vertices = support['vertices']
            caps = []
            for i in range(0, len(vertices), 9):
                tri = [vertices[i+j:i+j+3] for j in (0, 3, 6)]
                if all(near(p[1], 0.) for p in tri):
                    caps.append(Polygon([(p[0], p[2]) for p in tri]))
            mesh_cap = union_all(caps)
            ck('supports.'+id+'.limited_geometry', g.is_valid and not g.is_empty
               and g.symmetric_difference(expected).area < 1e-7
               and mesh_cap.symmetric_difference(g).area < .0002
               and g.intersection(original_support).area < 1e-7
               and support['id'] == 'N03_support_'+id and support['layer'] == 16 and support['mask'] == 8
               and support['bottom_y_m'] == -.2 and support['top_y_m'] == 0
               and all(number(v) for v in vertices) and len(vertices) >= 9 and len(vertices) % 9 == 0
               and all(near(vertices[j], 0.) or near(vertices[j], -.2) for j in range(1, len(vertices), 3)))
        support_descriptors = {d['id']: d for d in record['support_descriptors']}
        ck('supports.actual_body_count', len(record['support_descriptors']) == len(support_descriptors) == 2
           and set(support_descriptors) == {s['id'] for s in supports.values()})
        for id, support in supports.items():
            descriptor = support_descriptors[support['id']]
            # Godot's observed PackedVector3Array byte hash uses little-endian
            # float32 components on the accepted M1 runtime, independently packed.
            vertices = support['vertices']
            expected_face_sha = hashlib.sha256(struct.pack('<'+str(len(vertices))+'f', *vertices)).hexdigest()
            ck('supports.'+id+'.actual_body_faces_and_mask', descriptor['layer'] == 16
               and descriptor['mask'] == 8 and descriptor['identity'] is True
               and descriptor['shape'] == 'ConcavePolygonShape3D' and descriptor['backface'] is True
               and descriptor['disabled'] is False and descriptor['face_sha256'] == expected_face_sha)
        floor = union_all([original_support, *[shape(s['geometry']) for s in supports.values()]])
        movement = union_all([Polygon(p[0], p[1:]) for p in public['movement_rings']])
        private = union_all([Polygon(p[0], p[1:]) for p in public['private_rings']])
        supported_car = prep(floor.buffer(.00003))
        supported_person = prep(original_support.buffer(-.29998))
        player_movement = prep(movement.buffer(1e-6))
        road_domains = {id: prep(shape(r['road_domain']).buffer(EPS)) for id, r in routes.items()}
        # Floor surfaces never enter the obstacle set. Source height is retained.
        solids = []
        disabled = set(w01['disabled_source_ids'])
        for mesh in world['meshes']:
            if mesh['role'] in ('Buildings', 'Barriers') and mesh['id'] not in disabled:
                for poly, bottom, top in volume_from_mesh(mesh):
                    if bottom < 1.495 and top > .005:
                        solids.append(Polygon(poly[0], poly[1:]))
        for v in w01['volume_obstacles']:
            if v['bottom'] < 1.495 and v['top'] > .005:
                solids.extend(Polygon(p[0], p[1:]) for p in v['rings'])
        solid_tree = STRtree(solids)
        ck('independent_geometry.nonempty', bool(solids) and not floor.is_empty and not movement.is_empty)
        cross = next(c for c in bundle['crossings'] if c['id'] == 'sejong_marked')
        human_zone = shape(cross['human_occupancy_geometry'])
        ck('crossings.source_binding', len(bundle['crossings']) == 3
           and {c['id'] for c in bundle['crossings']} == {'sejong_marked', 'side_street', 'west_junction'}
           and human_zone.symmetric_difference(shape(cross['geometry']).buffer(.35)).area < 1e-7
           and cross['source_xz'] == next(c for c in public['crossings'] if c['id'] == 'sejong_marked')['source_xz'])

        def guard_valid(guard, id, require_allowed=False):
            route = routes[id]
            before = guard['before']
            before_ok = (vector(before['position']) and vector(before['velocity'])
                         and near(before['position'][::2], route['xz'][-1], .0002)
                         and abs(before['position'][1]) <= EPS
                         and near(before['station_m'], route['length_m'], .0002)
                         and 0 <= before['speed_mps'] <= .001
                         and math.sqrt(sum(v*v for v in before['velocity'])) <= .001
                         and before['on_floor'] is True and before['state'] == 'endpoint_wait')
            corners_ok = all(near(guard[key], portal_corners(route, ending), .0001)
                             for key, ending in [('start_corners', False), ('end_corners', True)])
            start_out = outside_frustum(guard['start_corners'], guard['planes'], guard['inside_reference'])
            end_out = outside_frustum(guard['end_corners'], guard['planes'], guard['inside_reference'])
            separation = min(math.dist(h['position'][::2], p)-2.9
                             for h in guard['humans'] for p in (route['xz'][0], route['xz'][-1]))
            return (before_ok and corners_ok and guard['route_id'] == id and guard['start_outside'] == start_out
                    and guard['end_outside'] == end_out
                    and near(guard['minimum_human_surface_distance_m'], separation, .0001)
                    and guard['entry_clear'] == (guard['entry_contacts'] == 0)
                    and (not guard['allowed'] or (guard['fresh'] and start_out and end_out
                         and separation >= 30. and guard['entry_clear']))
                    and (not require_allowed or guard['allowed']))

        cases = {c['name']: c for c in record['cases']}
        expected_cases = CASE_SECONDS if record['suite'] == 'full' else {
            'free_cycles': 12., 'manual_stop': 2., 'manual_resume': 3.}
        ck('cases.complete_unique', len(cases) == len(record['cases'])
           and list(cases) == list(expected_cases))
        previous_case = {}
        all_guards = []
        for name, case in cases.items():
            session = case['session']
            ticks, seconds = case['ticks'], case['duration_s']
            ck(name+'.duration_ticks', name in expected_cases and near(seconds, expected_cases[name])
               and ticks == round(seconds*60) and case['last_tick']-case['first_tick']+1 == ticks
               and session in sessions)
            if gpu:
                ck(name+'.gpu_wall_and_render', abs(case['wall_s']/seconds-1) <= .02
                   and abs(case['frames']/(seconds*60)-1) <= .2)
            stats = case['stats']
            ck(name+'.all_tick_summary', stats['floor_ticks'] == 2*ticks
               and stats['min_count'] == stats['max_count'] == 2 and stats['human_contacts'] == 0
               and 0 <= stats['max_y_m'] <= EPS and 0 <= stats['max_step_m'] <= MAX_STEP_M
               and 0 <= stats['max_speed_mps'] <= 5.01 and 0 <= stats['max_command_mps'] <= 5.0002)
            expected_ticks = sorted({1, ticks, *range(6, ticks+1, 6)})
            samples = case['samples']
            ck(name+'.retained_sampling', len(samples) == len(expected_ticks)
               and all(s['tick'] == case['first_tick']+tick-1 and near(s['t'], tick/60., 1e-6)
                       for s, tick in zip(samples, expected_ticks)))
            start = {v['route_id']: v for v in case['start']}
            end = {v['route_id']: v for v in case['end']}
            ck(name+'.endpoints_count', len(case['start']) == len(case['end']) == 2
               and set(start) == set(end) == set(routes))
            if session in previous_case:
                prev = previous_case[session]
                ck(name+'.same_session_no_car_pose', case['first_tick'] == prev['last_tick']+1
                   and all(all(start[id][key] == next(v for v in prev['end'] if v['route_id'] == id)[key]
                               for key in ('position', 'station_m', 'physics_steps', 'cycle_count', 'actual_distance_m'))
                           for id in routes))
            previous_case[session] = case
            tracks = {id: [] for id in routes}
            failures = []
            for index, s in enumerate(samples):
                p = s['player']
                point = p['position']
                okay = (vector(point) and abs(point[1]) <= EPS and p['floor'] is True
                        and p['inside_movement'] is True and p['recoveries'] == 0 and p['camera_mask'] == 1
                        and player_movement.covers(Point(point[::2])) and p['penetration_m'] <= EPS)
                npcs = s['npcs']
                okay = okay and len(npcs) == 2 and {n['route_id'] for n in npcs} == {'palace_court', 'plaza_front'}
                for n in npcs:
                    point = n['position']
                    okay = (okay and vector(point) and abs(point[1]) <= EPS and n['on_floor'] is True
                            and n['inside_movement'] is True and n['floor_id'] == 'W03_support'
                            and n['penetration_m'] <= EPS and n['layer'] == 4 and n['mask'] == 15
                            and supported_person.covers(Point(point[::2])))
                traffic = s['traffic']
                age = (traffic['tick']-traffic['last_observation_tick'])/60.
                present = any(human_zone.covers(Point(h['position'][::2])) for h in traffic['humans'])
                okay = (okay and traffic['tick'] == s['tick'] and near(traffic['observation_age_s'], age)
                        and traffic['human_present'] == present and len(set(traffic['queue'])) == len(traffic['queue'])
                        and all(id in routes for id in traffic['queue']) and traffic['owner'] in ('', *routes)
                        and not (present and traffic['clear_s'] > 1e-6))
                rows = s['vehicles']
                okay = okay and len(rows) == 2 and {v['route_id'] for v in rows} == set(routes)
                for v in rows:
                    id = v['route_id']; route = routes[id]; point = v['position']
                    error, station = project(point[::2], route['xz'])
                    box = car_polygon(point, v['yaw_rad'])
                    shrunken = box.buffer(-EPS, join_style='mitre')
                    obstacle_clear = all(shrunken.intersection(solids[int(j)]).area <= 1e-9
                                         for j in solid_tree.query(shrunken))
                    permission = v['permission']
                    fresh = bool(traffic['valid']) and age <= .1
                    okay = (okay and vector(point) and vector(v['velocity']) and abs(point[1]) <= EPS
                            and v['on_floor'] is True and v['floor_id'] in ('W03_support', 'N03_support_'+id)
                            and supported_car.covers(box) and road_domains[id].covers(box)
                            and shrunken.intersection(private).area <= 1e-9 and obstacle_clear
                            and error <= EPS and near(v['station_m'], station, EPS)
                            and 0 <= station <= route['length_m']+EPS and v['direction'] == 1
                            and v['layer'] == 8 and v['mask'] == 31 and v['physics_priority'] == 1
                            and near(v['body_yaw_rad'], v['yaw_rad'], .0001)
                            and near(v['visual_yaw_rad'], v['yaw_rad'], .0001)
                            and 0 <= v['speed_mps'] <= 5.01 and 0 <= v['command_speed_mps'] <= 5.0002
                            and abs(v['velocity'][1]) <= .001 and v['max_route_offset_m'] <= EPS
                            and v['max_step_m'] <= MAX_STEP_M and v['decel_mps2'] == 3.
                            and v['crossing_speed_limit_mps'] == 2.)
                    # A reentry clears permission for its current frame by design.
                    recycled_now = v['last_recycle_tick'] == s['tick']
                    if not recycled_now and v['running']:
                        okay = (okay and permission['tick'] == s['tick']
                                and permission['fresh'] == fresh and near(permission['observation_age_s'], age)
                                and (not permission['allow_crossing'] or
                                     (fresh and not present and traffic['owner'] == id)))
                    conflict = route['conflicts'][0]
                    if conflict['enter_s_m'] <= station <= conflict['exit_s_m']:
                        okay = okay and v['speed_mps'] <= 2.01
                    if v['can_recycle']:
                        okay = okay and v['at_end'] and v['speed_mps'] <= .001 and near(station, route['length_m'], .0002)
                    # Distance from the complete car footprint to every recorded person.
                    for human in traffic['humans']:
                        okay = okay and box.distance(Point(human['position'][::2])) >= .295
                    tracks[id].append((s, v, station))
                for id, guard in traffic['guards'].items():
                    okay = okay and guard_valid(guard, id)
                    all_guards.append((name, id, guard))
                if not okay:
                    failures.append(index)
            ck(name+'.independent_samples', not failures, {'failed_sample_indices': failures[:25]})
            for id, track in tracks.items():
                seq = [(case['first_tick']-1, start[id], start[id]['station_m'])]
                seq += [(s['tick'], v, station) for s, v, station in track]
                continuity = True
                distance = 0.
                max_accel = 0.
                max_brake = 0.
                for (ta, a, sa), (tb, b, sb) in zip(seq, seq[1:]):
                    cycles = b['cycle_count']-a['cycle_count']
                    delta = sb-sa+cycles*routes[id]['length_m']
                    continuity = continuity and cycles in (0, 1) and delta >= -EPS and delta <= 5.01*(tb-ta)/60.+EPS
                    if not cycles:
                        continuity = continuity and math.dist(a['position'][::2], b['position'][::2]) <= 5.01*(tb-ta)/60.+EPS
                        if a['running'] and b['running']:
                            dt = (tb-ta)/60.
                            max_accel = max(max_accel, (b['speed_mps']-a['speed_mps'])/dt)
                            max_brake = max(max_brake, (a['speed_mps']-b['speed_mps'])/dt)
                    if cycles:
                        history = [h for h in b['recycle_history'] if ta < h['tick'] <= tb]
                        continuity = continuity and len(history) == 1 and all(guard_valid(h['guard'], id, True) for h in history)
                    distance += max(0., delta)
                ck(name+'.'+id+'.source_station_continuity', continuity
                   and end[id]['physics_steps']-start[id]['physics_steps'] == ticks
                   and all(v['physics_steps'] == start[id]['physics_steps']+tick for (_, v, _), tick in zip(track, expected_ticks))
                   and track[-1][1] == end[id] and distance <= 5.01*seconds+EPS
                   and near(project(start[id]['position'][::2], routes[id]['xz'])[1], start[id]['station_m'], EPS)
                   and near(end[id]['actual_distance_m']-start[id]['actual_distance_m'], distance, EPS))
                # .03m/s² covers the recorded float32 difference of achieved
                # speeds at 60Hz; the nominal 1.5/3 bounds remain explicit.
                ck(name+'.'+id+'.retained_acceleration_and_brake', max_accel <= 1.53
                   and max_brake <= 3.03, {'maximum_acceleration_mps2': max_accel,
                                         'maximum_deceleration_mps2': max_brake})
                for h in end[id]['endpoint_history']:
                    ck(name+'.'+id+'.endpoint_tick_'+str(h['tick']),
                       near(h['position'][::2], routes[id]['xz'][-1], .0002)
                       and near(h['station_m'], routes[id]['length_m'], .0002)
                       and near(h['cycle_distance_m'], routes[id]['length_m'], .02))
                for h in end[id]['recycle_history']:
                    ck(name+'.'+id+'.guarded_reentry_tick_'+str(h['tick']),
                       h['tick'] == h['guard']['tick'] and guard_valid(h['guard'], id, True)
                       and near(h['from'], h['guard']['before']['position'], .0001)
                       and near(h['from'][::2], routes[id]['xz'][-1], .0002)
                       and near(h['to'][::2], routes[id]['xz'][0], .0002)
                       and any(e['tick'] <= h['tick'] for e in end[id]['endpoint_history']))

        # The event ledger is checked independently of final controller counters.
        for session, row in sessions.items():
            pending = []; owner = ''; last_tick = -1; failures = []
            for i, event in enumerate(row['events']):
                id = event['route_id']; tick = event['tick']; kind = event['type']
                okay = id in routes and tick >= last_tick
                if kind == 'queued':
                    okay = okay and id not in pending and id != owner
                    conflict = routes[id]['conflicts'][0]
                    okay = okay and conflict['stop_s_m']-.25-EPS <= event['station_m'] <= conflict['exit_s_m']+.005
                    pending.append(id)
                elif kind == 'grant':
                    okay = okay and owner == '' and bool(pending) and pending[0] == id
                    okay = okay and event['clear_s'] >= 1.-1e-7 and event['human_present'] is False
                    if pending and pending[0] == id:pending.pop(0)
                    owner = id
                elif kind == 'release':
                    okay = okay and owner == id and event['station_m'] > routes[id]['conflicts'][0]['exit_s_m']+.005
                    owner = ''
                elif kind == 'recycle':
                    okay = okay and event['guard']['tick'] == tick and guard_valid(event['guard'], id, True)
                else:
                    okay = False
                if not okay:failures.append(i)
                last_tick = tick
            ck('session.'+str(session)+'.FIFO_ledger', not failures, {'failed_event_indices': failures[:25]})
            # The ledger must describe the owner/queue actually retained by the
            # separate per-case observer, rather than being an unrelated story.
            samples = sorted([s for c in cases.values() if c['session'] == session
                              for s in c['samples']], key=lambda s: s['tick'])
            pending = []; owner = ''; index = 0; mismatch = []
            for sample in samples:
                while index < len(row['events']) and row['events'][index]['tick'] <= sample['tick']:
                    event = row['events'][index]; id = event['route_id']
                    if event['type'] == 'queued':pending.append(id)
                    elif event['type'] == 'grant':
                        if pending:pending.pop(0)
                        owner = id
                    elif event['type'] == 'release':owner = ''
                    index += 1
                if sample['traffic']['owner'] != owner or sample['traffic']['queue'] != pending:
                    mismatch.append(sample['tick'])
            ck('session.'+str(session)+'.ledger_matches_retained_owner_queue', not mismatch,
               {'failed_ticks': mismatch[:25]})

        def row_end(name, id):
            return next(v for v in cases[name]['end'] if v['route_id'] == id)

        if set(CASE_SECONDS).issubset(cases):
            for id in routes:
                free = cases['free_cycles']; start = next(v for v in free['start'] if v['route_id'] == id)
                final = row_end('free_cycles', id)
                endpoints = [h for h in final['endpoint_history'] if h['tick'] >= free['first_tick']]
                reentries = [h for h in final['recycle_history'] if h['tick'] >= free['first_tick']]
                ck('free_cycles.'+id+'.two_actual_cycles', len(endpoints) >= 2 and len(reentries) >= 2
                   and final['cycle_count']-start['cycle_count'] == len(reentries)
                   and final['actual_distance_m']-start['actual_distance_m'] >= 2*routes[id]['length_m']-EPS
                   and max(v['speed_mps'] for s in free['samples'] for v in s['vehicles'] if v['route_id'] == id) >= 4.99)
                stopped = row_end('occupied_queue', id)
                ck('occupied_queue.'+id+'.before_stop_line', stopped['speed_mps'] <= .001
                   and routes[id]['conflicts'][0]['stop_s_m']-EPS <= stopped['station_m'] <= routes[id]['conflicts'][0]['stop_s_m']+EPS)
            ck('clear_short.no_early_grant', all(s['traffic']['owner'] == ''
               and s['traffic']['clear_s'] < 1. for s in cases['clear_short']['samples']))
            fifo_case = cases['release_fifo']; events = sessions[fifo_case['session']]['events']
            grants = [e['route_id'] for e in events if e['type'] == 'grant' and fifo_case['first_tick'] <= e['tick'] <= fifo_case['last_tick']]
            ck('release_fifo.two_in_order', grants == ['sejong_south', 'sejong_north'])
            stale = cases['stale_hold']['samples']
            ck('stale_hold.no_entry', all(not s['traffic']['observations_enabled']
               and s['traffic']['owner'] == '' and s['traffic']['clear_s'] == 0.
               and all(v['speed_mps'] <= .001 for v in s['vehicles'])
               for s in stale if s['t'] > .8)
               and stale[-1]['traffic']['observation_age_s'] > .1)
            fresh = cases['fresh_resume']['samples']
            ck('fresh_resume.resumed', all(s['traffic']['observations_enabled'] and s['traffic']['observation_age_s'] <= .1 for s in fresh)
               and any(v['speed_mps'] > 1. for v in fresh[-1]['vehicles']))
            injection = cases['late_human']['injection']
            ck('late_human.explicit_after_entry', near(injection['human_position'][::2], [80.5415013, -194.6255234], EPS)
               and injection['vehicle_before']['station_m'] >= routes['sejong_south']['conflicts'][0]['enter_s_m']+.09
               and any(s['traffic']['human_present'] for s in cases['late_human']['samples'])
               and row_end('late_human', 'sejong_south')['speed_mps'] <= .001)
            ck('late_clear.resumed', row_end('late_clear', 'sejong_south')['station_m'] > row_end('late_human', 'sejong_south')['station_m']+1.)
            blocked = row_end('npc_obstacle', 'sejong_south')
            ck('npc_obstacle.stationary_layer4_fixture_stop', blocked['speed_mps'] <= .001
               and blocked['station_m'] < 50.-2.1-.3
               and any(h['layer'] == 4 and 'ContactFixture' in h['id'] for s in cases['npc_obstacle']['samples'] for h in s['traffic']['humans']))
            ck('npc_clear.resumed', row_end('npc_clear', 'sejong_south')['station_m'] > blocked['station_m']+1.)
            pushed = cases['player_push']
            stopped = next(v for v in pushed['start'] if v['route_id'] == 'sejong_south')
            ck('player_push.actual_contact_without_car_motion',
               any(any(hit['layer'] & 8 for hit in s['player']['contacts']) for s in pushed['samples'])
               and all(near(v['position'], stopped['position'], .0001) and not v['running']
                       for s in pushed['samples'] for v in s['vehicles'] if v['route_id'] == 'sejong_south')
               and math.dist(pushed['samples'][0]['player']['position'][::2],
                             pushed['samples'][-1]['player']['position'][::2]) > 1.)
            ck('player_backoff.released_contact', math.dist(
               cases['player_backoff']['samples'][0]['player']['position'][::2],
               cases['player_backoff']['samples'][-1]['player']['position'][::2]) > 1.)
            ck('player_exit.car_resumed', row_end('player_exit', 'sejong_south')['station_m'] > stopped['station_m']+1.)
            for name, key in [('visible_guard', 'visible'), ('near_human_guard', 'near'), ('entry_guard', 'entry')]:
                guards = [g for n, id, g in all_guards if n == name and id == 'sejong_north']
                if key == 'visible':condition = lambda g: not (g['start_outside'] and g['end_outside'])
                elif key == 'near':condition = lambda g: g['minimum_human_surface_distance_m'] < 30. and g['start_outside'] and g['end_outside'] and g['entry_clear']
                else:condition = lambda g: not g['entry_clear'] and g['start_outside'] and g['end_outside'] and g['minimum_human_surface_distance_m'] >= 30.
                ck(name+'.north_isolated_guard', bool(guards) and all(not g['allowed'] and condition(g) for g in guards)
                   and row_end(name, 'sejong_north')['cycle_count'] == 0)
            ck('recycle_release.north_reentered', row_end('recycle_release', 'sejong_north')['cycle_count'] >= 1)
            manual = cases['manual_stop']
            ck('manual_stop.no_motion', all(not v['running'] and v['state'] == 'paused' and v['speed_mps'] <= .001
               and near(v['position'], next(a for a in manual['start'] if a['route_id'] == v['route_id'])['position'], .0001)
               for s in manual['samples'] for v in s['vehicles']))
            ck('manual_resume.running', all(v['running'] for v in cases['manual_resume']['end'])
               and any(v['speed_mps'] > .1 for s in cases['manual_resume']['samples'] for v in s['vehicles']))
            ck('manual_stop.human_observation_continues', all(s['traffic']['valid'] and s['traffic']['human_present']
               and s['traffic']['clear_s'] == 0. and s['traffic']['last_observation_tick'] == s['tick']
               for s in manual['samples']))
            ck('manual_resume.clear_hold_restarts', 0. < cases['manual_resume']['samples'][0]['traffic']['clear_s'] < .1)
        menu = record['menu']
        ck('menu.actual_tree_pause', menu['tree_paused'] is True and menu['closed'] is True
           and menu['wall_s'] >= (.5 if gpu else .000001) and menu['hold'] == menu['after']
           and all(math.dist(a['position'], b['position']) <= MAX_STEP_M
                   for a, b in zip(menu['before'], menu['hold'])))
        ck('spawn.duplicate_rejected', record['duplicate_spawn_return'] is False)
        if gpu:
            ck('captures.present', {c['name'] for c in record['captures']} >= {'menu', 'traffic'}
               and all(c['width'] > 0 and c['height'] > 0 for c in record['captures']))
    except (KeyError, TypeError, ValueError, IndexError, ZeroDivisionError, OverflowError, StopIteration, GEOSException) as exc:
        ck('evidence_structure', False, {'error': type(exc).__name__+': '+str(exc)})
    return {'schema_version': 1, 'task': 'N03', 'passed': bool(checks) and all(c['passed'] for c in checks),
            'checks': checks, 'scope': 'Independent retained source geometry, car footprints, stations, FIFO and raw-plane guards. Tick extrema remain observer summaries; full GPU and headless runs, support probes, N04 endurance, people/OS/M4 and performance are separate evidence.'}


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

#!/usr/bin/env python3
"""Independently audit one continuous N04 physical urban-motion timeline.

No controller/generator imports or engine invocation. Source geometry, retained
positions and raw-plane guards are recomputed; every-tick extrema remain observer
summaries. Warmup is outside the timeline. Short runs never establish acceptance.
"""
import argparse
import bisect
import gzip
import hashlib
import json
import math
import struct
from pathlib import Path

from shapely import union_all
from shapely.errors import GEOSException
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.prepared import prep
from shapely.strtree import STRtree

from check_vehicles_evidence import (STATIC_INVENTORY_SHA256, ROUTE_SHA256,
    finite, number, vector, near, digest, project, car_polygon, portal_corners,
    outside_frustum)
from check_palace_evidence import volume_from_mesh
from check_walkable_evidence import RECIPE

EPS = .005
CAR_STEP = 5./60.+.001
NPC_STEP = .0202
PLAYER_STEP = 3.5/60.+EPS
NPC_SOURCES = {'palace_court': ('court_approach', 0, 11),
               'plaza_front': ('city_plaza', 97, 98)}


def distance_xz(a, b):
    return math.dist(a[::2], b[::2])


def rows_by_id(rows):
    result = {r['route_id']: r for r in rows}
    if len(result) != len(rows):
        raise ValueError('duplicate actor route_id')
    return result


def strip_histories(row):
    return {k: v for k, v in row.items() if k not in ('endpoint_history', 'recycle_history')}


class Geometry:
    """Cached Shapely source volumes; no generated movement policy is imported."""
    def __init__(self, bundle, public, world, w01):
        self.routes = {r['id']: r for r in bundle['routes']}
        self.public = public
        self.old_floor = shape(public['support']['geometry'])
        self.floor = union_all([self.old_floor, *[shape(s['geometry']) for s in bundle['supports']]])
        self.car_support = prep(self.floor.buffer(.00003))
        self.npc_support = prep(self.old_floor.buffer(-.29998))
        self.movement = prep(union_all([Polygon(p[0], p[1:]) for p in public['movement_rings']]).buffer(1e-6))
        self.private = union_all([Polygon(p[0], p[1:]) for p in public['private_rings']])
        self.domains = {id: prep(shape(r['road_domain']).buffer(EPS)) for id, r in self.routes.items()}
        self.crossings = {c['id']: shape(c['geometry']) for c in public['crossings']}
        self.human_zone = shape(next(c for c in bundle['crossings'] if c['id'] == 'sejong_marked')['human_occupancy_geometry'])
        parent = {r['id']: r for r in public['routes']}
        self.npc_lines = {id: parent[rid]['xz'][a:b+1] for id, (rid, a, b) in NPC_SOURCES.items()}
        self.volumes = []
        for mesh in world['meshes']:
            if mesh['role'] in ('Buildings', 'Barriers') and mesh['id'] not in w01['disabled_source_ids']:
                for p, low, high in volume_from_mesh(mesh):
                    self.volumes.append((Polygon(p[0], p[1:]), low, high))
        for v in w01['volume_obstacles']:
            if v['top'] > 0:
                self.volumes.extend((Polygon(p[0], p[1:]), v['bottom'], v['top']) for p in v['rings'])
        self.car_solids = [p for p, lo, hi in self.volumes if lo < 1.495 and hi > .005]
        self.car_tree = STRtree(self.car_solids)
        self.volumes.append((self.old_floor, -.2, 0.))
        self.volume_tree = STRtree([p for p, _, _ in self.volumes])

    def penetration(self, centre, radius, axis_half=0.):
        point = Point(centre[::2]); worst = 0.
        for index in self.volume_tree.query(box(centre[0]-radius, centre[2]-radius,
                                               centre[0]+radius, centre[2]+radius)):
            poly, lo, hi = self.volumes[int(index)]
            vertical = max(lo-centre[1]-axis_half, centre[1]-axis_half-hi, 0.)
            if vertical < radius:
                worst = max(worst, radius-math.hypot(poly.distance(point), vertical))
        return max(0., worst)

    def car_ok(self, row):
        p = row['position']; id = row['route_id']; route = self.routes[id]
        error, station = project(p[::2], route['xz'])
        footprint = car_polygon(p, row['yaw_rad'])
        interior = footprint.buffer(-EPS, join_style='mitre')
        clear = (interior.intersection(self.private).area <= 1e-9
                 and all(interior.intersection(self.car_solids[int(i)]).area <= 1e-9
                         for i in self.car_tree.query(interior)))
        return (vector(p) and vector(row['velocity']) and abs(p[1]) <= EPS
                and row['on_floor'] is True and row['floor_id'] in ('W03_support', 'N03_support_'+id)
                and self.car_support.covers(footprint) and self.domains[id].covers(footprint) and clear
                and error <= EPS and near(row['station_m'], station, EPS)
                and 0 <= station <= route['length_m']+EPS and row['direction'] == 1
                and row['layer'] == 8 and row['mask'] == 31 and row['physics_priority'] == 1
                and near(row['body_yaw_rad'], row['yaw_rad'], .0001)
                and near(row['visual_yaw_rad'], row['yaw_rad'], .0001)
                and row['running'] is True and 0 <= row['speed_mps'] <= 5.01
                and 0 <= row['command_speed_mps'] <= 5.0002 and abs(row['velocity'][1]) <= .001
                and row['max_step_m'] <= CAR_STEP and row['max_route_offset_m'] <= EPS
                and (not route['conflicts'][0]['enter_s_m'] <= station <= route['conflicts'][0]['exit_s_m']
                     or row['speed_mps'] <= 2.01)), station, footprint

    def npc_ok(self, row):
        p = row['position']; line = self.npc_lines[row['route_id']]
        error, station = project(p[::2], line)
        pp = self.penetration([p[0], p[1]+.85, p[2]], .3, .55)
        return (vector(p) and vector(row['velocity']) and abs(p[1]) <= EPS
                and row['on_floor'] is True and row['floor_id'] == 'W03_support'
                and row['inside_movement'] is True and self.movement.covers(Point(p[::2]))
                and self.npc_support.covers(Point(p[::2])) and pp <= EPS
                and near(row['penetration_m'], pp, .0001) and error <= EPS
                and near(row['station_m'], station, EPS) and row['direction'] in (-1, 1)
                and row['layer'] == 4 and row['mask'] == 15 and row['running'] is True
                and math.hypot(row['velocity'][0], row['velocity'][2]) <= 1.2002
                and abs(row['velocity'][1]) <= .001 and row['max_step_m'] <= NPC_STEP), station


def guard_ok(guard, route):
    before = guard['before']
    corners_ok = all(near(guard[key], portal_corners(route, ending), .0001)
                     for key, ending in [('start_corners', False), ('end_corners', True)])
    a = outside_frustum(guard['start_corners'], guard['planes'], guard['inside_reference'])
    b = outside_frustum(guard['end_corners'], guard['planes'], guard['inside_reference'])
    separation = min(math.dist(h['position'][::2], p)-2.9
                     for h in guard['humans'] for p in (route['xz'][0], route['xz'][-1]))
    return (corners_ok and guard['route_id'] == route['id']
            and vector(before['position']) and vector(before['velocity'])
            and near(before['position'][::2], route['xz'][-1], .0002)
            and abs(before['position'][1]) <= EPS and near(before['station_m'], route['length_m'], .0002)
            and before['on_floor'] is True and before['state'] == 'endpoint_wait'
            and 0 <= before['speed_mps'] <= .001 and math.sqrt(sum(v*v for v in before['velocity'])) <= .001
            and guard['start_outside'] == a and guard['end_outside'] == b
            and near(guard['minimum_human_surface_distance_m'], separation, .0001)
            and guard['entry_clear'] == (guard['entry_contacts'] == 0)
            and (not guard['allowed'] or (guard['fresh'] and a and b and separation >= 30. and guard['entry_clear'])))


def camera_ok(walk, g, gpu=False):
    p = walk['player']; rig = walk['rig']; camera = rig['camera']; basis = rig['basis']
    pivot = [p[0], p[1]+1.3, p[2]]; corners = walk['near_corners']
    if not (len(corners) == 4 and len(basis) == 3 and all(vector(v) for v in corners+basis)):
        return False
    local = [[sum((corner[j]-camera[j])*col[j] for j in range(3)) for col in basis] for corner in corners]
    hw = max(abs(v[0]) for v in local); hh = max(abs(v[1]) for v in local)
    fhalf = rig['near']*math.tan(math.radians(rig['fov'])/2)
    plane = (all(near(math.sqrt(sum(v*v for v in col)), 1., .002) for col in basis)
             and all(abs(sum(a*b for a, b in zip(basis[j], basis[k]))) <= .002 for j, k in ((0, 1), (0, 2), (1, 2)))
             and near([pivot[j]+basis[2][j]*rig['distance'] for j in range(3)], camera, .002)
             and max(math.dist(corner, camera) for corner in corners) <= .200001
             and len({(1 if v[0] > 0 else -1, 1 if v[1] > 0 else -1) for v in local}) == 4
             and all(near(v[2], -rig['near'], .0001) and near(abs(v[0]), hw, .0001) and near(abs(v[1]), hh, .0001) for v in local)
             and hh > 0 and near(hw/hh, rig['aspect'], .002)
             and (near(hw, fhalf, .0001) or near(hh, fhalf, .0001))
             and near(rig['near'], .05, 1e-6) and near(rig['fov'], 65., 1e-6))
    pp = g.penetration([p[0], p[1]+.85, p[2]], .3, .55)
    pc = g.penetration(camera, .2)
    corner_clear = True
    for corner in corners:
        q = Point(corner[::2])
        for index in g.volume_tree.query(q):
            poly, lo, hi = g.volumes[int(index)]
            if lo < corner[1] < hi and poly.contains(q):
                corner_clear = False
                break
    return (plane and corner_clear and pp <= EPS and pc <= EPS
            and near(walk['player_penetration_m'], pp, .0001) and near(walk['camera_penetration_m'], pc, .0001)
            and walk['floor'] is True and walk['floor_id'] == 'W03_support'
            and near(walk['floor_normal'], [0., 1., 0.], .002)
            and walk['camera_overlap'] == walk['near_ray_hits'] == []
            and near(rig['pivot'], pivot, .002) and rig['mask'] == 1 and near(rig['probe_radius'], .2)
            and rig['follow_ticks'] == rig['observed_ticks']
            and rig['input_enabled'] is True and rig['mouse_mode'] == (2 if gpu else 0)
            and math.radians(-55)-1e-6 <= rig['pitch'] <= math.radians(15)+1e-6
            and 0 <= rig['distance'] <= rig['hit_length']+.002 <= rig['requested_distance']+.004
            and 2 <= rig['requested_distance'] <= 6 and near(math.dist(camera, pivot), rig['distance'], .002))


def audit(record, traffic_bundle, itinerary, public, world, w01):
    """Pure six-input audit. No filesystem reads occur inside this function."""
    checks = []

    def ck(name, passed, details=None):
        row = {'name': name, 'passed': bool(passed)}
        if details is not None:row['details'] = details
        checks.append(row)

    try:
        bundle = traffic_bundle
        ck('schema', record['task'] == 'N04' and record['schema_version'] == 1
           and bundle['task'] == 'N03' and bundle['contract_id'] == 'N03-traffic-v1'
           and itinerary['task'] == 'W04' and public['task'] == 'W03' and world['task'] == 'E03' and w01['task'] == 'W01')
        ck('finite_values', all(finite(v) for v in (record, bundle, itinerary, public, world, w01)))
        ck('acceptance.full_suite', record['suite'] == 'full')
        ck('execution.no_unresolved_error', record['error'] == '')
        ck('input.observed_bytes', record['bundle_sha256'] == digest(bundle, pretty=True)
           and record['plan_sha256'] == digest(itinerary)
           and bundle['source_sha256']['game/data/generated/public_walk.json'] == digest(public)
           and bundle['source_sha256']['game/resources/world_geometry/world.json'] == digest(world)
           and public['provenance']['game/data/generated/daehanmun.json'] == digest(w01)
           and bundle['coordinate_system'] == world['coordinate_system'])
        ck('bundle.source_routes', len(bundle['routes']) == 2
           and {r['id'] for r in bundle['routes']} == set(ROUTE_SHA256)
           and all(digest(r) == ROUTE_SHA256[r['id']] for r in bundle['routes']))
        ck('bundle.scope_and_collision', bundle['scope'] == {'task': 'N03', 'vehicles': 2, 'pedestrians': 2,
           'new_vehicle_supports': 2, 'player_boundary_changed': False, 'physical_terrain_access_verified': False}
           and bundle['rules']['vehicle'] == {'layer': 8, 'mask': 31}
           and bundle['rules']['vehicle_support'] == {'layer': 16, 'mask': 8}
           and bundle['rules']['unchanged'] == {'player_mask': 13, 'pedestrian_mask': 15, 'camera_mask': 1})
        policy = bundle['policy']
        ck('bundle.unchanged_physical_and_priority_policy', bundle['actor'] == {
            'length_m': 4.2, 'width_m': 1.8, 'height_m': 1.5, 'swept_radius_m': 2.6,
            'speed_mps': 5., 'acceleration_mps2': 1.5, 'gravity_mps2': 9.8,
            'safe_margin_m': .001, 'layer': 8, 'mask': 31}
           and policy['priority'] == ['player_and_pedestrian', 'vehicle_already_inside', 'fifo_waiting_vehicle']
           and policy['brake_mps2'] == 3. and policy['reaction_s'] == .5
           and policy['stop_margin_m'] == 1. and policy['crossing_clearance_m'] == .35
           and policy['clear_hold_s'] == 1. and policy['max_observation_age_s'] == .1
           and policy['unknown_occupancy'] == 'stop' and policy['zone_vehicle_capacity'] == 1
           and policy['timeout_forced_entry'] is False
           and policy['vehicle_recycle'] == {'both_portals_outside_actual_camera_frustum': True,
               'minimum_human_distance_m': 30., 'dynamic_entry_envelope_empty': True,
               'hold_until_eligible': True, 'spatial_connection_between_portals': False})
        ck('inventory.frozen_before_after', digest(record['initial_inventory'], inventory=True) == STATIC_INVENTORY_SHA256
           and record['final_inventory'] == record['initial_inventory'])
        support_by_id = {s['id']: s for s in bundle['supports']}
        descriptors = {d['id']: d for d in record['support_descriptors']}
        old_floor = shape(public['support']['geometry'])
        ck('supports.count', len(descriptors) == len(record['support_descriptors']) == len(support_by_id) == 2)
        route_map = {r['id']: r for r in bundle['routes']}
        for id, support in support_by_id.items():
            descriptor = descriptors[id]; vertices = support['vertices']
            expected = shape(route_map[support['route_id']]['swept_geometry']).difference(old_floor)
            cap = union_all([Polygon([(vertices[i+j], vertices[i+j+2]) for j in (0, 3, 6)])
                             for i in range(0, len(vertices), 9)
                             if all(near(vertices[i+j+1], 0.) for j in (0, 3, 6))])
            actual_sha = hashlib.sha256(struct.pack('<'+str(len(vertices))+'f', *vertices)).hexdigest()
            ck('supports.'+id+'.limited_actual_geometry', shape(support['geometry']).symmetric_difference(expected).area < 1e-7
               and cap.symmetric_difference(expected).area < .0002 and descriptor['face_sha256'] == actual_sha
               and descriptor['layer'] == 16 and descriptor['mask'] == 8 and descriptor['identity'] is True
               and descriptor['shape'] == 'ConcavePolygonShape3D' and descriptor['backface'] is True
               and descriptor['disabled'] is False and support['bottom_y_m'] == -.2 and support['top_y_m'] == 0)
        ck('actors.vehicle_descriptors', len(record['descriptors']) == 2
           and {d['id'] for d in record['descriptors']} == set(route_map)
           and all(near(d['size'], [1.8, 1.5, 4.2], 1e-5) and d['layer'] == 8 and d['mask'] == 31
                   and d['priority'] == 1 and near(d['safe_margin'], .001) for d in record['descriptors']))
        ck('actors.npc_descriptors', len(record['npc_descriptors']) == 2
           and {d['id'] for d in record['npc_descriptors']} == set(NPC_SOURCES)
           and all(near(d['height'], 1.7, 1e-6) and near(d['radius'], .3, 1e-6)
                   and d['layer'] == 4 and d['mask'] == 15 and near(d['safe_margin'], .001)
                   for d in record['npc_descriptors']))
        player_contract = record['walk']['actor']
        ck('actors.original_player_camera', all(near(player_contract[k], v, 1e-6) for k, v in {
            'height': 1.7, 'radius': .3, 'layer': 2, 'mask': 13, 'walk_mps': 1.4,
            'run_mps': 3.5, 'gravity': 9.8, 'safe_margin': .001,
            'camera_mask': 1, 'camera_probe_radius': .2}.items())
           and player_contract['player_camera_path_matches'] is True
           and player_contract['boundary_script'] == 'res://scripts/player/public_player.gd')
        boundary = record['walk']['boundary']
        ck('boundary.original_resource', boundary['contract_id'] == 'W03-play-boundary-v1'
           and boundary['runtime_path'] == 'res://data/generated/public_walk.json'
           and boundary['movement_edge_margin_m'] == .4 and boundary['road_center_exclusion_m'] == .5)
        engine = record['engine']; gpu = engine['display'].lower() != 'headless'
        ck('engine', engine['physics_hz'] == engine['render_fps'] == 60 and bool(engine['version'])
           and (not gpu or engine['renderer'].lower() not in ('', 'headless')))
        timeline = record['timeline']; ticks = timeline['ticks']; first = timeline['first_tick']; last = timeline['last_tick']
        ck('timeline.clock_and_duration', ticks > 0 and last-first+1 == ticks
           and near(timeline['duration_s'], ticks/60., .0001)
           and timeline['wall_s'] > 0 and timeline['duration_s'] >= (600. if record['suite'] == 'full' else 0.))
        if gpu:
            ck('timeline.gpu_real_clock', abs(timeline['wall_s']/timeline['duration_s']-1) <= .02
               and abs(timeline['frames']/(60*timeline['wall_s'])-1) <= .2)
        stats = timeline['stats']
        ck('timeline.all_tick_summary', stats['ticks'] == ticks
           and stats['vehicle_min_count'] == stats['vehicle_max_count'] == stats['npc_min_count'] == stats['npc_max_count'] == 2
           and stats['vehicle_floor_ticks'] == stats['npc_floor_ticks'] == 2*ticks
           and stats['player_floor_ticks'] == ticks and stats['player_outside_ticks'] == 0
           and 0 <= stats['max_vehicle_step_m'] <= CAR_STEP and 0 <= stats['max_npc_step_m'] <= NPC_STEP
           and 0 <= stats['max_player_step_m'] <= PLAYER_STEP
           and 0 <= stats['max_vehicle_y_m'] <= EPS and 0 <= stats['max_npc_y_m'] <= EPS
           and 0 <= stats['max_vehicle_speed_mps'] <= 5.01 and 0 <= stats['max_npc_speed_mps'] <= 1.2002
           and 0 <= stats['max_player_penetration_m'] <= EPS and 0 <= stats['max_camera_penetration_m'] <= EPS
           and stats['vehicle_human_contacts'] == stats['pose_calls'] == stats['recoveries'] == 0)
        ck('timeline.all_tick_camera_and_npc_geometry',
           0 <= stats['max_npc_source_penetration_m'] <= EPS
           and stats['max_camera_overlap_count'] == stats['max_near_hit_count'] == stats['max_tick_mismatch'] == 0
           and 0 <= stats['max_follow_error_m'] <= .002 and stats['max_length_excess_m'] <= .002)
        g = Geometry(bundle, public, world, w01)
        samples = timeline['samples']; sample_ticks = [s['tick'] for s in samples]
        ck('timeline.retained_clock', bool(samples) and sample_ticks == sorted(set(sample_ticks))
           and first <= sample_ticks[0] <= first+1 and sample_ticks[-1] == last
           and all(0 < b-a <= 6 for a, b in zip(sample_ticks, sample_ticks[1:]))
           and all(near(s['t'], (s['tick']-first+1)/60., .0001) for s in samples))
        initial_cars = rows_by_id(timeline['start']['vehicles']); initial_npcs = rows_by_id(timeline['start']['npcs'])
        final_cars = rows_by_id(record['final_vehicles']); final_npcs = rows_by_id(record['final_npcs'])
        ck('timeline.actor_ids', set(initial_cars) == set(final_cars) == set(route_map)
           and set(initial_npcs) == set(final_npcs) == set(NPC_SOURCES))
        car_tracks = {id: [] for id in route_map}; npc_tracks = {id: [] for id in NPC_SOURCES}
        bad_samples = []; guard_cache = {}; bad_guards = []
        for index, sample in enumerate(samples):
            point = sample['player']['position']; player = sample['player']; walk = sample['walk']
            okay = (vector(point) and vector(player['velocity']) and abs(point[1]) <= EPS
                    and player['floor'] is True and player['inside_movement'] is True
                    and player['recoveries'] == 0 and player['camera_mask'] == 1
                    and g.movement.covers(Point(point[::2])) and g.npc_support.covers(Point(point[::2]))
                    and near(walk['player'], point, .0001) and camera_ok(walk, g, gpu))
            cars = rows_by_id(sample['vehicles']); npcs = rows_by_id(sample['npcs'])
            okay = okay and set(cars) == set(route_map) and set(npcs) == set(NPC_SOURCES)
            traffic = sample['traffic']; age = (traffic['tick']-traffic['last_observation_tick'])/60.
            present = any(g.human_zone.covers(Point(h['position'][::2])) for h in traffic['humans'])
            okay = (okay and traffic['tick'] == sample['tick'] and near(traffic['observation_age_s'], age)
                    and traffic['valid'] is True and traffic['observations_enabled'] is True and age <= .1
                    and traffic['human_present'] == present and traffic['owner'] in ('', *route_map)
                    and len(traffic['queue']) == len(set(traffic['queue']))
                    and not (present and traffic['clear_s'] > .000001))
            human_points = [point, *[n['position'] for n in npcs.values()]]
            okay = (okay and len(traffic['humans']) == 3
                    and all(any(near(h['position'], p, EPS) for p in human_points) for h in traffic['humans'])
                    and all(any(near(h['position'], p, EPS) for h in traffic['humans']) for p in human_points))
            for id, npc in npcs.items():
                valid, station = g.npc_ok(npc); okay = okay and valid
                okay = okay and npc['physics_steps']-initial_npcs[id]['physics_steps'] == sample['tick']-first+1
                okay = okay and distance_xz(point, npc['position']) >= .595
                npc_tracks[id].append((sample, npc, station))
            for id, car in cars.items():
                valid, station, footprint = g.car_ok(car); okay = okay and valid
                conflict = route_map[id]['conflicts'][0]
                # Tie the abstract FIFO ledger to actual spatial occupancy.
                # One owner string therefore cannot authorize both source lanes.
                if conflict['enter_s_m'] <= station <= conflict['exit_s_m']+.005:
                    okay = okay and traffic['owner'] == id
                permission = car['permission']
                if car['last_recycle_tick'] != sample['tick']:
                    okay = (okay and permission['tick'] == sample['tick'] and permission['fresh'] is True
                            and near(permission['observation_age_s'], age)
                            and (not permission['allow_crossing'] or (not present and traffic['owner'] == id)))
                okay = okay and car['physics_steps']-initial_cars[id]['physics_steps'] == sample['tick']-first+1
                okay = okay and all(footprint.distance(Point(p[::2])) >= .295 for p in human_points)
                car_tracks[id].append((sample, car, station))
            for id, guard in traffic['guards'].items():
                key = (id, guard['tick'])
                if key not in guard_cache:
                    guard_cache[key] = guard
                    if not guard_ok(guard, route_map[id]):bad_guards.append(key)
                elif guard != guard_cache[key]:bad_guards.append(key)
            if not okay:bad_samples.append(index)
        ck('timeline.independent_source_samples', not bad_samples, {'failed_sample_indices': bad_samples[:50]})
        ck('timeline.independent_cached_guards', not bad_guards, {'failed_guard_keys': bad_guards[:25]})
        ck('timeline.player_continuity', all(distance_xz(a['player']['position'], b['player']['position'])
           <= 3.5*(b['tick']-a['tick'])/60.+EPS for a, b in zip(samples, samples[1:]))
           and distance_xz(timeline['start']['player']['position'], samples[0]['player']['position']) <= PLAYER_STEP+.0001
           and near(timeline['end']['player']['position'], samples[-1]['player']['position'], .0001))

        for id, track in car_tracks.items():
            route = route_map[id]; length = route['length_m']
            seq = [(first-1, initial_cars[id], project(initial_cars[id]['position'][::2], route['xz'])[1])]
            seq += [(s['tick'], row, station) for s, row, station in track]
            distance = 0.; bad = []; max_accel = 0.; max_brake = 0.
            for (ta, a, sa), (tb, b, sb) in zip(seq, seq[1:]):
                cycles = b['cycle_count']-a['cycle_count']; dt = (tb-ta)/60.
                ds = sb-sa+cycles*length
                okay = (cycles in (0, 1) and -EPS <= ds <= 5.01*dt+EPS
                        and near(b['actual_distance_m']-a['actual_distance_m'], ds, EPS))
                if not cycles:
                    okay = okay and distance_xz(a['position'], b['position']) <= 5.01*dt+EPS
                    max_accel = max(max_accel, (b['speed_mps']-a['speed_mps'])/dt)
                    max_brake = max(max_brake, (a['speed_mps']-b['speed_mps'])/dt)
                else:
                    histories = [h for h in final_cars[id]['recycle_history'] if ta < h['tick'] <= tb]
                    okay = okay and len(histories) == 1 and histories[0]['guard']['allowed'] is True
                    if histories:okay = okay and guard_ok(histories[0]['guard'], route)
                if not okay:bad.append(tb)
                distance += max(0., ds)
            ck('cars.'+id+'.physical_continuity', not bad and max_accel <= 1.53 and max_brake <= 3.03,
               {'failed_ticks': bad[:25], 'maximum_acceleration_mps2': max_accel, 'maximum_deceleration_mps2': max_brake})
            actual = final_cars[id]
            endpoints = [h for h in actual['endpoint_history'] if first <= h['tick'] <= last]
            reentries = [h for h in actual['recycle_history'] if first <= h['tick'] <= last]
            event_bad = []
            for h in endpoints:
                if not (near(h['position'][::2], route['xz'][-1], .0002)
                        and near(h['station_m'], length, .0002) and near(h['cycle_distance_m'], length, .02)):
                    event_bad.append(h['tick'])
            for h in reentries:
                if not (guard_ok(h['guard'], route) and h['guard']['allowed'] is True
                        and h['tick'] == h['guard']['tick'] and near(h['from'], h['guard']['before']['position'], .0001)
                        and near(h['from'][::2], route['xz'][-1], .0002)
                        and near(h['to'][::2], route['xz'][0], .0002)
                        and any(e['tick'] <= h['tick'] for e in endpoints)):
                    event_bad.append(h['tick'])
            ck('cars.'+id+'.endpoint_and_reentry_geometry', not event_bad, {'failed_ticks': event_bad[:25]})
            ck('cars.'+id+'.two_actual_cycles', len(endpoints) >= 2 and len(reentries) >= 2
               and actual['cycle_count']-initial_cars[id]['cycle_count'] == len(reentries)
               and distance >= 2*length-EPS,
               {'actual_endpoint_visits': len(endpoints), 'guarded_reentries': len(reentries), 'source_distance_m': distance})
            ck('cars.'+id+'.final_alignment', all(near(actual[k], track[-1][1][k], .0001)
               for k in ('position', 'station_m', 'actual_distance_m', 'cycle_count', 'physics_steps'))
               and actual['physics_steps']-initial_cars[id]['physics_steps'] == ticks
               and near(actual['position'], next(v for v in timeline['end']['vehicles'] if v['route_id'] == id)['position'], .0001))

        for id, track in npc_tracks.items():
            line = g.npc_lines[id]; length = sum(math.dist(a, b) for a, b in zip(line, line[1:]))
            seq = [(first-1, initial_npcs[id], project(initial_npcs[id]['position'][::2], line)[1])]
            seq += [(s['tick'], row, station) for s, row, station in track]
            visits = []; distance = 0.; bad = []; max_yaw_rate = 0.
            for (ta, a, sa), (tb, b, sb) in zip(seq, seq[1:]):
                dt = (tb-ta)/60.; moved = distance_xz(a['position'], b['position'])
                yaw = abs(math.atan2(math.sin(b['visual_yaw_rad']-a['visual_yaw_rad']),
                                     math.cos(b['visual_yaw_rad']-a['visual_yaw_rad'])))
                max_yaw_rate = max(max_yaw_rate, yaw/dt)
                okay = (moved <= 1.2*dt+EPS and abs(sb-sa) <= 1.2*dt+EPS
                        and 0 <= b['actual_distance_m']-a['actual_distance_m'] <= 1.2*dt+EPS
                        and near(b['actual_distance_m']-a['actual_distance_m'], abs(sb-sa), EPS)
                        and yaw <= math.pi*dt+.001)
                if not okay:bad.append(tb)
                distance += abs(sb-sa)
                side = 0 if sb <= .01 else 1 if sb >= length-.01 else None
                if side is not None and (not visits or visits[-1] != side):visits.append(side)
            actual = final_npcs[id]
            for h in actual['endpoint_history']:
                target = 0 if h['station_m'] < length*.5 else -1
                if not (near(h['position'][::2], line[target], .01)
                        and (h['station_m'] <= .01 or h['station_m'] >= length-.01)):
                    bad.append('invalid_endpoint')
            ck('npcs.'+id+'.physical_continuity_and_turns', not bad,
               {'failed_ticks': bad[:25], 'maximum_yaw_rate_radps': max_yaw_rate})
            ck('npcs.'+id+'.two_actual_roundtrips', len(visits) >= 4 and distance >= 4*length-.5
               and actual['completed_cycles']-initial_npcs[id]['completed_cycles'] >= 2,
               {'alternating_endpoint_visits': visits, 'retained_source_distance_m': distance, 'two_roundtrip_distance_m': 4*length})
            ck('npcs.'+id+'.final_alignment', all(near(actual[k], track[-1][1][k], .0001)
               for k in ('position', 'station_m', 'actual_distance_m', 'physics_steps'))
               and actual['physics_steps']-initial_npcs[id]['physics_steps'] == ticks
               and near(actual['position'], next(n for n in timeline['end']['npcs'] if n['route_id'] == id)['position'], .0001))

        # Reconstruct the full original W04 itinerary from unchanged source routes.
        parents = {r['id']: r for r in public['routes']}; expected_points = []; specs = []
        for stage_id, rid, direction, start, end in RECIPE:
            step = 1 if end > start else -1
            indices = list(range(start, end+step, step)); points = [parents[rid]['xz'][i] for i in indices]
            ck('walk.source_seam.'+stage_id, not expected_points or expected_points[-1] == points[0])
            expected_points.extend(points[1:] if expected_points else points)
            for i, (a, b) in enumerate(zip(points, points[1:])):
                specs.append({'name': stage_id+'_'+str(i), 'stage_id': stage_id, 'from_xz': a, 'to_xz': b})
        ck('walk.itinerary_source_and_counts', itinerary['points_xz'] == expected_points
           and len(specs) == len(itinerary['segment_specs']) == 334
           and near(itinerary['total_length_m'], sum(math.dist(s['from_xz'], s['to_xz']) for s in specs), 1e-7)
           and all(all(actual[k] == expected[k] for k in expected)
                   for actual, expected in zip(itinerary['segment_specs'], specs)))
        walk_record = record['walk']; journey = walk_record['journey']; legs = walk_record['cases']
        ck('walk.full334_coverage', len(legs) == len(specs) == 334
           and [c['name'] for c in legs] == [s['name'] for s in specs])
        ck('walk.same_global_session', first <= journey['first_physics_tick'] <= journey['last_physics_tick'] <= last
           and journey['last_physics_tick']-journey['first_physics_tick']+1 == journey['ticks']
           and journey['stats']['pose_calls'] == journey['stats']['recoveries'] == 0
           and all(first <= c['first_physics_tick'] <= c['last_physics_tick'] <= last for c in legs)
           and all(a['last_physics_tick'] < b['first_physics_tick'] for a, b in zip(legs, legs[1:]))
           and near(legs[0]['start'][::2], public['spawn'][::2], .07)
           and near(legs[-1]['end'][::2], public['spawn'][::2], .07))
        if gpu:
            ck('walk.gpu_real_clock', abs(journey['wall_s']/journey['duration_s']-1) <= .02
               and abs(journey['frames']/(60*journey['wall_s'])-1) <= .2)
        retained = {s['tick']: s for s in samples}
        yield_sample_count = 0; bad_guidance = []
        for spec, leg in zip(specs, legs):
            start_tick = leg['first_physics_tick']; end_tick = leg['last_physics_tick']
            selected = samples[bisect.bisect_left(sample_ticks, start_tick):bisect.bisect_right(sample_ticks, end_tick)]
            bad = []
            for sample in selected:
                point = sample['player']['position']; guidance = sample['walk'].get('guidance', {})
                mode = guidance.get('mode', 'source')
                line_error, _ = project(point[::2], [spec['from_xz'], spec['to_xz']])
                if mode in ('yield', 'yield_wait', 'yield_return'):
                    yield_sample_count += 1
                    npc_id = guidance['npc_id']; target = guidance['target']
                    okay = (guidance['source_leg'] == spec['name'] and npc_id in NPC_SOURCES
                            and vector(target) and abs(target[1]) <= EPS and line_error <= 1.05
                            and g.movement.covers(Point(target[::2])) and g.npc_support.covers(Point(target[::2]))
                            and g.penetration([target[0], target[1]+.85, target[2]], .3, .55) <= EPS)
                    if mode == 'yield_return':okay = okay and near(target[::2], spec['to_xz'], .0001)
                    if not okay:bad_guidance.append(sample['tick'])
                elif mode == 'source':
                    okay = line_error <= .18
                else:
                    okay = False
                if not okay:bad.append(sample['tick'])
            aligned = (end_tick in retained and near(retained[end_tick]['player']['position'], leg['end'], .0001))
            ck('walk.'+spec['name']+'.actual_source_arrival', leg['stage_id'] == spec['stage_id']
               and math.dist(leg['end'][::2], spec['to_xz']) <= .065 and bool(selected) and aligned and not bad,
               {'failed_ticks': bad[:10]})
        ck('walk.yield_guidance_valid', not bad_guidance, {'yield_samples': yield_sample_count, 'failed_ticks': bad_guidance[:25]})
        yield_events = walk_record['yield_events']
        source_specs = {s['name']: s for s in specs}
        yield_starts = {}; yield_ends = {}; bad_yield_events = []
        for event_index, event in enumerate(yield_events):
            name = event['source_leg']; tick = event['tick']; npc_id = event['npc_id']
            key = (name, tick if event['type'] == 'yield_start' else event['start_tick'])
            okay = name in source_specs and npc_id in NPC_SOURCES
            if not okay:
                bad_yield_events.append(event_index)
                continue
            spec = source_specs[name]; dx = spec['to_xz'][0]-spec['from_xz'][0]; dz = spec['to_xz'][1]-spec['from_xz'][1]
            length = math.hypot(dx, dz); forward = [dx/length, dz/length]; normal = [-forward[1], forward[0]]
            origin = event['origin']; waypoint = event['waypoint']
            offset = [waypoint[0]-origin[0], waypoint[2]-origin[2]]
            lateral = sum(a*b for a, b in zip(offset, normal)); advance = sum(a*b for a, b in zip(offset, forward))
            corridor = LineString([origin[::2], waypoint[::2]])
            okay = (okay and vector(origin) and vector(waypoint)
                    and near(abs(lateral), .85, .0002) and near(advance, .25, .0002)
                    and project(origin[::2], [spec['from_xz'], spec['to_xz']])[0] <= .18
                    and g.old_floor.buffer(.00003).covers(corridor.buffer(.3))
                    and g.movement.covers(corridor))
            if event['type'] == 'yield_start':
                okay = okay and key not in yield_starts
                yield_starts[key] = event
                position = bisect.bisect_left(sample_ticks, tick)
                closest = samples[min(position, len(samples)-1)]
                npc = next(n for n in closest['npcs'] if n['route_id'] == npc_id)
                dt = abs(closest['tick']-tick)/60.
                okay = (okay and dt <= .1 and distance_xz(origin, closest['player']['position']) <= 3.5*dt+EPS
                        and distance_xz(origin, npc['position']) <= 1.8+1.2*dt+EPS)
            elif event['type'] == 'yield_end':
                okay = okay and key in yield_starts and key not in yield_ends
                yield_ends[key] = event
                error, _ = project(event['position'][::2], [spec['from_xz'], spec['to_xz']])
                okay = (okay and tick >= event['start_tick'] and near(event['source_error_m'], error, .0001)
                        and error <= .18 and event['reason'] in ('npc_clear_distance', 'npc_passed_behind',
                            'wait_limit_elapsed', 'source_leg_changed')
                        and event['return_tick'] >= event['start_tick'])
            else:okay = False
            if not okay:bad_yield_events.append(event_index)
        # A guidance label cannot manufacture permission for a wider corridor.
        for sample in samples:
            guidance = sample['walk'].get('guidance', {})
            if guidance.get('source_leg') not in source_specs or guidance.get('mode') == 'source':continue
            key = (guidance['source_leg'], guidance['yield_start_tick'])
            if key not in yield_starts or guidance['npc_id'] != yield_starts[key]['npc_id']:
                bad_yield_events.append(sample['tick'])
        ck('walk.yield_events_source_capsule_and_actor_binding', not bad_yield_events
           and set(yield_starts) == set(yield_ends), {'failed_indices_or_ticks': bad_yield_events[:25], 'actual_yields': len(yield_starts)})
        extra_specs = walk_record['extra_specs']
        source_corridors = prep(union_all([LineString(r['xz']).buffer(.07) for r in public['routes']]))
        city_points = parents['city_plaza']['xz']
        safe_fraction = [city_points[22][i]+.8*(city_points[23][i]-city_points[22][i]) for i in range(2)]
        source_targets = [p for r in public['routes'] for p in r['xz']]+[safe_fraction]
        ck('exercises.extra_waypoints_are_preserved_source', all(
            any(near(row['to_xz'], p, .0001) for p in source_targets)
            and source_corridors.covers(LineString([row['from_xz'], row['to_xz']]))
            for row in extra_specs.values()), {'allowed_source_fraction': safe_fraction})
        ck('post_timeline_recovery_injections_separate',
           walk_record['events_start_physics_tick'] >= last
           and walk_record['events_end_physics_tick'] > walk_record['events_start_physics_tick'])

        # Event order must agree with the separate retained owner/queue timeline.
        events = record['traffic_events']; pending = []; owner = ''; bad_events = []; states = []; previous_tick = -1
        for i, event in enumerate(events):
            kind = event['type']; id = event['route_id']; tick = event['tick']
            okay = id in route_map and tick >= previous_tick
            if kind == 'queued':
                okay = okay and id not in pending and owner != id
                pending.append(id)
            elif kind == 'grant':
                okay = okay and owner == '' and bool(pending) and pending[0] == id
                okay = okay and event['clear_s'] >= 1.-1e-7 and event['human_present'] is False
                if pending:pending.pop(0)
                owner = id
            elif kind == 'release':
                okay = okay and owner == id and event['station_m'] > route_map[id]['conflicts'][0]['exit_s_m']+.005
                owner = ''
            elif kind == 'recycle':
                okay = okay and guard_ok(event['guard'], route_map[id]) and event['guard']['allowed'] is True
                okay = okay and event['guard']['tick'] == tick
            else:okay = False
            if not okay:bad_events.append(i)
            states.append((tick, owner, list(pending))); previous_tick = tick
        ck('traffic.FIFO_and_current_guard_events', not bad_events, {'failed_event_indices': bad_events[:25]})
        index = 0; owner = ''; pending = []; bad = []
        for sample in samples:
            while index < len(states) and states[index][0] <= sample['tick']:
                _, owner, pending = states[index]; index += 1
            if sample['traffic']['owner'] != owner or sample['traffic']['queue'] != pending:bad.append(sample['tick'])
        ck('traffic.events_match_retained_owner_queue', not bad, {'failed_ticks': bad[:25]})

        exercises = record['exercises']; previous_end = journey['last_physics_tick']; exercise_bad = []
        crossing_exercises = [e for e in exercises if e['kind'] == 'crossing']
        npc_exercises = [e for e in exercises if e['kind'] == 'npc_block']
        ck('exercises.three_crossing_and_three_npc_block', len(exercises) == 6
           and len(crossing_exercises) == len(npc_exercises) == 3
           and [e['index'] for e in crossing_exercises] == [0, 1, 2]
           and [e['index'] for e in npc_exercises] == [0, 1, 2])
        for index, exercise in enumerate(crossing_exercises):
            a = exercise['start_tick']; hold = exercise['hold_tick']; clear = exercise['clear_tick']; end = exercise['end_tick']
            stopped = exercise['car_stopped']; released = exercise['car_released']; before = exercise['car_before']
            occupied = exercise['player_occupied']; empty = exercise['player_clear']
            occupied = occupied['position'] if isinstance(occupied, dict) else occupied
            empty = empty['position'] if isinstance(empty, dict) else empty
            conflict = route_map['sejong_south']['conflicts'][0]
            okay = (previous_end <= a <= hold < clear < end <= last
                    and stopped['route_id'] == released['route_id'] == before['route_id'] == 'sejong_south'
                    and stopped['speed_mps'] <= .001 and conflict['stop_s_m']-EPS <= stopped['station_m'] <= conflict['stop_s_m']+EPS
                    and released['station_m'] > conflict['exit_s_m']+.005
                    and released['cycle_count'] == stopped['cycle_count']
                    and g.human_zone.covers(Point(occupied[::2])) and not g.human_zone.covers(Point(empty[::2]))
                    and g.movement.covers(Point(occupied[::2])) and g.movement.covers(Point(empty[::2])))
            held_samples = samples[bisect.bisect_left(sample_ticks, hold):bisect.bisect_right(sample_ticks, clear)]
            clear_samples = samples[bisect.bisect_left(sample_ticks, clear):bisect.bisect_right(sample_ticks, end)]
            okay = (okay and bool(held_samples) and bool(clear_samples)
                    and any(s['traffic']['human_present'] and any(v['route_id'] == 'sejong_south' and v['speed_mps'] <= .001
                            and v['station_m'] <= conflict['stop_s_m']+EPS for v in s['vehicles']) for s in held_samples)
                    and any(e['type'] == 'grant' and e['route_id'] == 'sejong_south' and clear <= e['tick'] <= end for e in events))
            okay = (okay and any(any(v['route_id'] == 'sejong_south' and v['station_m'] > conflict['exit_s_m']+.005
                                    and v['cycle_count'] == stopped['cycle_count'] for v in s['vehicles']) for s in clear_samples)
                    and project(stopped['position'][::2], route_map['sejong_south']['xz'])[0] <= EPS
                    and near(project(stopped['position'][::2], route_map['sejong_south']['xz'])[1], stopped['station_m'], EPS)
                    and near(project(released['position'][::2], route_map['sejong_south']['xz'])[1], released['station_m'], EPS))
            if not okay:exercise_bad.append(index)
            previous_end = end
        ck('exercises.observed_human_crossing_stop_and_release', not exercise_bad, {'failed_exercise_indices': exercise_bad})
        block_bad = []
        for index, exercise in enumerate(npc_exercises):
            a = exercise['start_tick']; hold = exercise['hold_tick']; clear = exercise['clear_tick']; end = exercise['end_tick']
            stopped = exercise['npc_stopped']; released = exercise['npc_released']; before = exercise['npc_before']
            line = g.npc_lines['palace_court']
            occupied = exercise['player_occupied']; empty = exercise['player_clear']
            occupied = occupied['position'] if isinstance(occupied, dict) else occupied
            empty = empty['position'] if isinstance(empty, dict) else empty
            okay = (previous_end <= a <= hold < clear < end <= last
                    and stopped['route_id'] == released['route_id'] == before['route_id'] == 'palace_court'
                    and stopped['state'] in ('waiting', 'endpoint_wait') and stopped['blocked_reason'] == 'body:Player'
                    and math.hypot(stopped['velocity'][0], stopped['velocity'][2]) <= .001
                    and distance_xz(occupied, stopped['position']) >= .595
                    and g.movement.covers(Point(occupied[::2])) and g.movement.covers(Point(empty[::2]))
                    and released['actual_distance_m'] > stopped['actual_distance_m']+1.
                    and project(stopped['position'][::2], line)[0] <= EPS
                    and near(project(stopped['position'][::2], line)[1], stopped['station_m'], EPS))
            held = samples[bisect.bisect_left(sample_ticks, hold-6):bisect.bisect_right(sample_ticks, clear)]
            after = samples[bisect.bisect_left(sample_ticks, clear):bisect.bisect_right(sample_ticks, end)]
            okay = (okay and any(any(n['route_id'] == 'palace_court' and n['blocked_reason'] == 'body:Player'
                                    and math.hypot(n['velocity'][0], n['velocity'][2]) <= .001 for n in s['npcs']) for s in held)
                    and any(any(n['route_id'] == 'palace_court' and n['actual_distance_m'] >= stopped['actual_distance_m']+.9
                                for n in s['npcs']) for s in after))
            if not okay:block_bad.append(index)
            previous_end = end
        ck('exercises.observed_npc_block_and_recovery', not block_bad, {'failed_exercise_indices': block_bad})
    except (KeyError, TypeError, ValueError, IndexError, ZeroDivisionError, OverflowError, StopIteration, GEOSException) as exc:
        ck('evidence_structure', False, {'error': type(exc).__name__+': '+str(exc)})
    return {'schema_version': 1, 'task': 'N04', 'passed': bool(checks) and all(c['passed'] for c in checks),
            'checks': checks, 'scope': 'One continuous automatic physical journey with two pedestrians and two vehicles. Source/retained geometry is independently checked; tick extrema are observer summaries. Three vehicle crossing stop/release and three separate NPC blockage/recovery exercises remain inside this timeline. Human controls/OS/M4, real terrain/access and city performance remain unverified.'}


def read(path):
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rt') as stream:return json.load(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('record', 'bundle', 'itinerary', 'public', 'world', 'w01'):
        parser.add_argument('--'+key, required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = audit(*(read(getattr(args, key)) for key in ('record', 'bundle', 'itinerary', 'public', 'world', 'w01')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print(json.dumps({'passed': result['passed'], 'checks': len(result['checks']),
                      'failed': [c['name'] for c in result['checks'] if not c['passed']]}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

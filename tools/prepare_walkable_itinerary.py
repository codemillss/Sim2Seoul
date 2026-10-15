#!/usr/bin/env python3
"""Prepare the fixed W04 journey by copying unchanged W03 route legs.

Only Python's standard library is needed. Preparation checks W03/E04 freshness
and exact route seams; it does not establish engine completion or real access.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import time

from check_public_bundle import check as check_w03

ROOT = Path(__file__).resolve().parents[1]
INPUT = 'data/manual/walkable_milestone.json'
OUT = 'game/data/generated/walkable_itinerary.json'
MANIFEST = 'game/data/generated/walkable_manifest.json'
SOURCE = 'game/data/generated/public_walk.json'
MILESTONE_ID = 'W0-engineering-walk-v1'
EXPECTED_STAGES = [
    ('entrance_forward', 'entrance', 'forward', 0, 3),
    ('palace_loop_prefix', 'palace_loop', 'forward', 0, 5),
    ('court_forward', 'court_approach', 'forward', 0, 11),
    ('court_reverse', 'court_approach', 'reverse', 11, 0),
    ('palace_loop_suffix', 'palace_loop', 'forward', 5, 24),
    ('palace_loop_reverse', 'palace_loop', 'reverse', 24, 0),
    ('city_forward', 'city_plaza', 'forward', 0, 98),
    ('city_reverse', 'city_plaza', 'reverse', 98, 0),
    ('stonewall_forward', 'stonewall', 'forward', 0, 31),
    ('stonewall_reverse', 'stonewall', 'reverse', 31, 0),
    ('entrance_reverse', 'entrance', 'reverse', 3, 0),
]
PROVENANCE = [
    INPUT, SOURCE, 'game/data/generated/public_manifest.json',
    'data/manual/public_walk.json', 'tools/prepare_public_walk.py',
    'tools/prepare_walkable_itinerary.py', 'config/region.json',
    'config/scale_view.json', 'game/data/generated/scale_view.json',
    'game/data/generated/scale_manifest.json',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def encode(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'),
                       allow_nan=False) + '\n').encode('utf-8')


def finite_point(point):
    return (isinstance(point, list) and len(point) == 2 and
            all(isinstance(v, (int, float)) and not isinstance(v, bool) and
                math.isfinite(v) for v in point))


def ring_location(point, ring):
    """Return -1 outside, 0 on the boundary, or 1 inside a source ring."""
    x, z = point
    inside = False
    for a, b in zip(ring, ring[1:] + ring[:1]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        cross = (x - a[0]) * dz - (z - a[1]) * dx
        if (abs(cross) <= 1e-10 * max(1., math.hypot(dx, dz)) and
                min(a[0], b[0]) - 1e-10 <= x <= max(a[0], b[0]) + 1e-10 and
                min(a[1], b[1]) - 1e-10 <= z <= max(a[1], b[1]) + 1e-10):
            return 0
        if (a[1] > z) != (b[1] > z):
            if x < a[0] + (z - a[1]) * dx / dz:
                inside = not inside
    return 1 if inside else -1


def covers(point, polygons):
    return any(ring_location(point, poly[0]) >= 0 and
               all(ring_location(point, hole) <= 0 for hole in poly[1:])
               for poly in polygons)


def check_scale_bundle(root):
    manifest = read_json(root / 'game/data/generated/scale_manifest.json')
    scale = read_json(root / 'game/data/generated/scale_view.json')
    require(manifest['schema_version'] == scale['schema_version'] == 1 and
            manifest['task'] == scale['task'] == 'E04', 'Invalid E04 schema/task')
    require(manifest['file'] == 'res://data/generated/scale_view.json' and
            manifest['sha256'] == sha(root / 'game/data/generated/scale_view.json'),
            'Stale E04 runtime plan')
    require(manifest['world_sha256'] == scale['world_sha256'] ==
            sha(root / 'game/resources/world_geometry/world.json'), 'Stale E04 world')
    require(scale['coordinate_contract_sha256'] == sha(root / 'config/region.json'),
            'Stale E04 coordinate contract')
    for entry in scale['provenance']:
        require(sha(root / entry['file']) == entry['sha256'],
                'Stale E04 input: ' + entry['file'])
    region = read_json(root / 'config/region.json')
    require(region['meters_per_world_unit'] == scale['meters_per_world_unit'] == 1 and
            region['world_axes'] == {'x': 'east', 'y': 'up', 'z': 'south'},
            'W04 requires the unchanged one metre world contract')


def prepare(root=ROOT, check_only=False):
    started = time.perf_counter()
    root = Path(root)
    check_w03(root)
    check_scale_bundle(root)
    recipe, source = read_json(root / INPUT), read_json(root / SOURCE)
    require(recipe['schema_version'] == 1 and recipe['task'] == 'W04' and
            recipe['milestone_id'] == MILESTONE_ID, 'Invalid W04 recipe identity')
    scope = recipe['scope']
    require(all(scope[key] is False for key in (
        'physical_terrain_verified', 'real_world_access_verified',
        'human_operation_verified', 'm4_verified')), 'W04 scope exceeds recorded evidence')
    recipe_stages = [(s['id'], s['route_id'], s['direction'],
                      s['source_start_index'], s['source_end_index'])
                     for s in recipe['stages']]
    require(recipe_stages == EXPECTED_STAGES, 'W04 fixed journey recipe changed')
    routes = {route['id']: route for route in source['routes']}
    require(len(routes) == len(source['routes']) == 5 and
            set(routes) == {'entrance', 'palace_loop', 'court_approach',
                            'city_plaza', 'stonewall'}, 'Unexpected W03 route set')
    require(len(source['checkpoints']) == 8, 'W04 requires all eight W03 checkpoints')
    anchor = recipe['court_anchor']
    require(anchor == {'route_id': 'palace_loop', 'runtime_index': 5,
                       'checkpoint_index': 2, 'source_node': 921242850},
            'Unexpected court source anchor')
    court_start = routes['court_approach']['xz'][0]
    require(court_start == routes['palace_loop']['xz'][anchor['runtime_index']] ==
            source['checkpoints'][anchor['checkpoint_index']]['xz'] and
            source['checkpoints'][anchor['checkpoint_index']]['source_node'] ==
            anchor['source_node'] and
            anchor['source_node'] in routes['palace_loop']['source_node_ids'],
            'Court approach is not anchored at the original loop source node')
    require(source['spawn'][::2] == routes['entrance']['xz'][0],
            'The original outside spawn is not the entrance start')
    require(routes['palace_loop']['xz'][0] == routes['palace_loop']['xz'][-1],
            'The palace route is not closed')
    require(routes['city_plaza']['city_checkpoint_index'] == 46 and
            routes['city_plaza']['xz'][46] == source['checkpoints'][5]['xz'],
            'City interior checkpoint is missing')

    stages, points, segments, events = [], [], [], []
    checkpoints = [dict(checkpoint, checkpoint_index=i, event_indices=[])
                   for i, checkpoint in enumerate(source['checkpoints'])]
    for stage_recipe in recipe['stages']:
        stage = dict(stage_recipe)
        route = routes[stage['route_id']]
        start, end = stage['source_start_index'], stage['source_end_index']
        step = 1 if stage['direction'] == 'forward' else -1
        require(0 <= start < len(route['xz']) and 0 <= end < len(route['xz']) and
                (end - start) * step > 0, 'Invalid source bounds: ' + stage['id'])
        indices = list(range(start, end + step, step))
        stage_points = [route['xz'][index] for index in indices]
        require(all(finite_point(point) and covers(point, source['movement_rings'])
                    for point in stage_points), 'Point outside W03 movement: ' + stage['id'])
        require(not points or points[-1] == stage_points[0],
                'Disconnected exact route seam: ' + stage['id'])
        first_point_index = len(points) - 1 if points else 0
        points.extend(stage_points[1:] if points else stage_points)
        stage.update(source_indices=indices, xz=stage_points,
                     length_m=sum(math.dist(a, b) for a, b in zip(stage_points, stage_points[1:])),
                     start_point_index=first_point_index,
                     end_point_index=len(points) - 1, checkpoint_end_indices=[])
        stage_segments = []
        for local_leg, (a, b) in enumerate(zip(stage_points, stage_points[1:])):
            require(a != b, 'Zero length source leg: ' + stage['id'])
            segment = {
                'name': stage['id'] + '_' + str(local_leg), 'stage_id': stage['id'],
                'route_id': stage['route_id'], 'direction': stage['direction'],
                'source_leg_index': min(indices[local_leg:local_leg + 2]),
                'local_leg_index': local_leg,
                'from_point_index': first_point_index + local_leg,
                'to_point_index': first_point_index + local_leg + 1,
                'from_xz': a, 'to_xz': b, 'length_m': math.dist(a, b),
                'checkpoint_end_indices': [],
            }
            stage_segments.append(segment)
            segments.append(segment)
        for local_index, point in enumerate(stage_points):
            # A seam is one point/event. Attribute it to the arriving stage.
            if local_index == 0 and stages:
                continue
            for checkpoint in checkpoints:
                if point != checkpoint['xz']:
                    continue
                event_index = len(events)
                checkpoint_index = checkpoint['checkpoint_index']
                segment = stage_segments[local_index - 1] if local_index else None
                events.append({
                    'event_index': event_index, 'checkpoint_index': checkpoint_index,
                    'name': checkpoint['name'], 'point_index': first_point_index + local_index,
                    'stage_id': stage['id'], 'local_point_index': local_index,
                    'source_point_index': indices[local_index],
                    'segment_name': segment['name'] if segment else None, 'xz': point,
                })
                checkpoint['event_indices'].append(event_index)
                if segment:
                    segment['checkpoint_end_indices'].append(checkpoint_index)
                    stage['checkpoint_end_indices'].append(checkpoint_index)
        stages.append(stage)
    require(all(checkpoint['event_indices'] for checkpoint in checkpoints),
            'The integrated journey misses a W03 checkpoint')
    require(points[0] == points[-1] == source['spawn'][::2],
            'The integrated journey does not return to the original outside spawn')
    require(len(segments) == len(points) - 1 and all(
        a['to_xz'] == b['from_xz'] for a, b in zip(segments, segments[1:])),
        'The integrated journey is not continuous')
    # Each of the five original route legs must be copied once in each direction.
    copied = {(rid, direction, leg): 0 for rid, route in routes.items()
              for direction in ('forward', 'reverse') for leg in range(len(route['xz']) - 1)}
    for segment in segments:
        copied[(segment['route_id'], segment['direction'], segment['source_leg_index'])] += 1
    require(all(count == 1 for count in copied.values()),
            'W04 route coverage is not exactly once in each direction')
    provenance = {name: sha(root / name) for name in PROVENANCE}
    plan = {
        'schema_version': 1, 'task': 'W04', 'milestone_id': MILESTONE_ID,
        'recipe_sha256': provenance[INPUT], 'w03_sha256': provenance[SOURCE],
        'provenance': provenance, 'scope': scope,
        'boundary_contract_id': source['boundary']['contract_id'],
        'meters_per_world_unit': 1, 'spawn': source['spawn'],
        'court_anchor': anchor, 'stages': stages, 'points_xz': points,
        'segment_specs': segments, 'checkpoints': checkpoints,
        'checkpoint_events': events,
        'total_length_m': sum(segment['length_m'] for segment in segments),
        'counts': {'stages': len(stages), 'points': len(points), 'segments': len(segments),
                   'source_routes': len(routes), 'checkpoints': len(checkpoints),
                   'checkpoint_events': len(events), 'teleport_links': 0,
                   'new_coordinate_points': 0},
    }
    blob = encode(plan)
    manifest = {
        'schema_version': 1, 'task': 'W04', 'milestone_id': MILESTONE_ID,
        'plan_sha256': hashlib.sha256(blob).hexdigest(), 'w03_sha256': provenance[SOURCE],
        'recipe_sha256': provenance[INPUT], 'source_provenance': provenance,
        'files': {'itinerary': {'path': 'res://data/generated/walkable_itinerary.json',
                                'sha256': hashlib.sha256(blob).hexdigest()}},
    }
    for name, content in ((OUT, blob), (MANIFEST, encode(manifest))):
        path = root / name
        if check_only:
            require(path.exists() and path.read_bytes() == content, 'Missing/stale W04 bundle: ' + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    return {'task': 'W04', 'passed': True, 'milestone_id': MILESTONE_ID,
            'plan_sha256': manifest['plan_sha256'], 'counts': plan['counts'],
            'total_length_m': plan['total_length_m'],
            'elapsed_seconds': round(time.perf_counter() - started, 6)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.root, args.check), ensure_ascii=False, indent=2))

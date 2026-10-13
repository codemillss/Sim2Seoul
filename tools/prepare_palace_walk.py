#!/usr/bin/env python3
"""W02 source footway loop, clipped courtyard and explicit local flat support."""
import argparse
import hashlib
import heapq
import json
import math
from pathlib import Path

from shapely.geometry import LineString, Point, mapping, shape
from shapely.ops import nearest_points, unary_union
from prepare_world import encode, mesh_polygon, polygons
from prepare_daehanmun import rings
from check_daehanmun_bundle import check as check_w01

ROOT = Path(__file__).resolve().parents[1]
INPUT = 'data/manual/palace_walk.json'
OUT = 'game/data/generated/palace_walk.json'
DECISION = 'game/data/generated/palace_decision.json'
MANIFEST = 'game/data/generated/palace_manifest.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def nearest_inside(domain, point):
    p = Point(point)
    q = p if domain.covers(p) else nearest_points(p, domain)[1]
    return list(q.coords[0])


def shortest_inside(domain, a, b):
    """Visibility graph confined to the eligible source-derived local domain."""
    a, b = list(a), list(b)
    if domain.covers(LineString([a, b])):
        return [a, b]
    parts = [p for p in polygons(domain) if p.buffer(1e-8).covers(Point(a)) and p.buffer(1e-8).covers(Point(b))]
    if len(parts) != 1:
        raise ValueError('Local route endpoints are not in one eligible component')
    poly = parts[0]
    vertices = [a, b]
    for ring in [poly.exterior, *poly.interiors]:
        vertices.extend([list(p) for p in list(ring.coords)[:-1]])
    # Numerical tolerance only. The routing domain is already 1cm inside movement bounds.
    covered = poly.buffer(1e-8)
    graph = [[] for _ in vertices]
    for i, p in enumerate(vertices):
        for j in range(i):
            q = vertices[j]
            if covered.covers(LineString([p, q])):
                distance = math.dist(p, q)
                graph[i].append((j, distance))
                graph[j].append((i, distance))
    distances = [math.inf] * len(vertices)
    distances[0] = 0
    previous = {}
    queue = [(0, 0)]
    while queue:
        distance, i = heapq.heappop(queue)
        if distance != distances[i]:
            continue
        if i == 1:
            break
        for j, step in graph[i]:
            candidate = distance + step
            if candidate < distances[j]:
                distances[j] = candidate
                previous[j] = i
                heapq.heappush(queue, (candidate, j))
    if not math.isfinite(distances[1]):
        raise ValueError('No eligible route around source exclusions')
    indices = [1]
    while indices[-1] != 0:
        indices.append(previous[indices[-1]])
    return [vertices[i] for i in reversed(indices)]


def prepare(root=ROOT, check_only=False):
    root = Path(root)
    check_w01(root)
    d = json.loads((root / INPUT).read_text())
    assert d['task'] == 'W02' and d['schema_version'] == 1
    assert d['path_width_m'] == 2.4 and d['ground_y_m'] == 0
    assert d['scope']['physical_terrain_verified'] is False and d['scope']['global_playable_boundary'] is None
    features = json.loads((root / 'data/processed/features.json').read_text())
    by = {f['feature_id']: f for f in features['features']}
    world = json.loads((root / 'game/resources/world_geometry/world.json').read_text())
    w01 = json.loads((root / 'game/data/generated/daehanmun.json').read_text())
    outbound, returned = by[d['loop_outbound_way']], by[d['loop_return_way']]
    for f in [outbound, returned]:
        assert f['source_tags']['highway'] == 'footway' and f['source_tags']['access'] == 'permissive'
    start = outbound['source_topology']['node_ids'].index(d['loop_start_node'])
    join = returned['source_topology']['node_ids'].index(d['loop_join_node'])
    finish = returned['source_topology']['node_ids'].index(d['loop_start_node'])
    source = outbound['geometry']['coordinates'][start:] + list(reversed(returned['geometry']['coordinates'][finish:join]))
    node_ids = outbound['source_topology']['node_ids'][start:] + list(reversed(returned['source_topology']['node_ids'][finish:join]))
    assert source[0] == source[-1] == w01['route_xz'][-1]
    original_loop = LineString(source)
    court = shape(by[d['court_source']]['geometry'])
    assert by[d['court_source']]['source_tags']['highway'] == 'pedestrian'
    corridor = original_loop.buffer(d['path_width_m'] / 2, join_style='mitre')
    entrance_floor = shape(w01['fragments'][-1]['geometry'])
    raw_floor = unary_union([corridor, court, entrance_floor])
    exclusions = []
    solids = []
    for m in world['meshes']:
        if m['id'] in w01['disabled_source_ids'] or m['role'] not in ['Buildings', 'Barriers']:
            continue
        f = by[m['metadata']['feature_id']]
        g = shape(f['geometry'])
        if g.geom_type in ['LineString', 'MultiLineString']:
            g = g.buffer(world['display']['barrier_thickness_m'] / 2, cap_style='flat', join_style='mitre')
        if g.distance(raw_floor) < 6:
            solids.append({'id': m['id'], 'geometry': mapping(g), 'bottom': m['bottom_y_m'], 'top': m['top_y_m']})
        if g.intersects(raw_floor):
            exclusions.append({'id': m['id'], 'reason': 'source solid footprint', 'geometry': mapping(g.buffer(d['solid_exclusion_margin_m']))})
    for f in w01['fragments'][:-1]:
        solids.append({'id': f['id'], 'geometry': f['geometry'], 'bottom': f['bottom_y_m'], 'top': f['top_y_m']})
    for f in features['features']:
        g, tags = shape(f['geometry']), f['source_tags']
        if g.geom_type in ['Polygon', 'MultiPolygon'] and (tags.get('landuse') == 'grass' or tags.get('natural') == 'water' or tags.get('amenity') == 'fountain'):
            if g.intersects(raw_floor):
                exclusions.append({'id': f['feature_id'], 'reason': 'source lawn/water/fountain', 'geometry': mapping(g)})
        elif tags.get('highway') == 'steps' and tags.get('access') == 'no':
            g = g.buffer(d['path_width_m'] / 2, cap_style='flat', join_style='mitre')
            if g.intersects(raw_floor):
                exclusions.append({'id': f['feature_id'], 'reason': 'source restricted stairs; vertical geometry unresolved', 'geometry': mapping(g)})
    floor = raw_floor.difference(unary_union([shape(e['geometry']) for e in exclusions]))
    # Keep only the component reached from the original W01 spawn; disconnected scraps aren't playable.
    spawn_point = Point(w01['spawn'][0], w01['spawn'][2])
    connected = [p for p in polygons(floor) if p.covers(spawn_point)]
    if len(connected) != 1:
        raise ValueError('No unique connected entrance floor')
    floor = connected[0]
    movement = floor.buffer(-d['movement_edge_margin_m'], join_style='mitre')
    routing = movement.buffer(-d['routing_extra_margin_m'], join_style='mitre')
    if not routing.covers(spawn_point):
        raise ValueError('Source spawn has insufficient support clearance')
    anchors = [nearest_inside(routing, p) for p in source]
    adjusted = []
    route = [anchors[0]]
    for i in range(len(source) - 1):
        local = routing.intersection(LineString(source[i:i+2]).buffer(d['max_path_adjustment_m'], cap_style='square', join_style='mitre'))
        points = shortest_inside(local, anchors[i], anchors[i+1])
        if not LineString(points).buffer(.32).disjoint(unary_union([shape(s['geometry']) for s in solids if s['bottom'] < 1.7])):
            raise ValueError('Runtime loop intersects a preserved solid')
        deviation = LineString(points).hausdorff_distance(LineString(source[i:i+2]))
        if deviation > d['max_path_adjustment_m'] + 1e-7:
            raise ValueError('Runtime correction exceeds explicit local bound')
        adjusted.append({'leg': i, 'source_nodes': node_ids[i:i+2], 'source_xz': source[i:i+2], 'runtime_xz': points, 'maximum_deviation_m': deviation, 'basis': 'source unchanged; local clearance against clipped eligible support'})
        route.extend(points[1:])
    court_target = d['court_viewpoint_xz']
    assert court.covers(Point(court_target)) and routing.covers(Point(court_target))
    join_index = node_ids.index(d['loop_join_node'])
    court_domain = routing.intersection(court.buffer(.5))
    court_path = shortest_inside(court_domain, anchors[join_index], court_target)
    meshes = mesh_polygon(floor, -d['support_depth_m'], d['ground_y_m'])
    support = {'id': 'W02_support', 'material': 'support', 'role': 'Ground', 'source_id': None, 'geometry': mapping(floor), **meshes}
    volumes = [{'id': s['id'], 'rings': rings(shape(s['geometry'])), 'bottom': s['bottom'], 'top': s['top']} for s in solids]
    volumes.append({'id': 'W02_support', 'rings': rings(floor), 'bottom': -d['support_depth_m'], 'top': d['ground_y_m']})
    routes = [
        {'id': 'entrance', 'name': '대한문 밖↔경내 입구', 'xz': w01['route_xz'], 'source_length_m': w01['route_length_m'], 'length_m': w01['route_length_m']},
        {'id': 'palace_loop', 'name': '경내 순환', 'xz': route, 'source_xz': source, 'source_node_ids': node_ids, 'source_length_m': original_loop.length, 'length_m': LineString(route).length},
        {'id': 'court_approach', 'name': '중화전 앞마당 외부', 'xz': court_path, 'length_m': LineString(court_path).length, 'basis': 'route within source pedestrian area excluding its holes/restricted steps'}
    ]
    seok_index = node_ids.index(3851434705)
    checkpoints = [
        {'name': '대한문 밖', 'xz': w01['route_xz'][0], 'source_node': w01['source_nodes']['start'], 'route': 'entrance'},
        {'name': '경내 입구', 'xz': anchors[0], 'source_node': d['loop_start_node'], 'route': 'palace_loop'},
        {'name': '중화전 측면', 'xz': anchors[join_index], 'source_node': d['loop_join_node'], 'route': 'palace_loop'},
        {'name': '석조전 계단 아래', 'xz': anchors[seok_index], 'source_node': 3851434705, 'route': 'palace_loop'},
        {'name': '중화전 앞마당', 'xz': court_target, 'source_node': None, 'basis': d['court_viewpoint_basis'], 'route': 'court_approach'}
    ]
    inputs = [INPUT, 'data/processed/features.json', 'data/processed/heights.json', 'data/processed/walkable_areas.json', 'data/manual/movement_review.json', 'config/region.json', 'game/resources/world_geometry/world.json', 'game/data/generated/daehanmun.json', 'game/data/generated/daehanmun_manifest.json', 'game/resources/collision/generated.json', 'tools/prepare_palace_walk.py', 'tools/prepare_world.py']
    provenance = {p: sha(root / p) for p in inputs}
    data = {'schema_version': 1, 'task': 'W02', 'scope': d['scope'], 'assumption_id': d['assumption_id'], 'provenance': provenance,
            'support': support, 'movement_rings': rings(movement), 'routes': routes, 'source_leg_corrections': adjusted,
            'exclusions': exclusions, 'checkpoints': checkpoints, 'volume_obstacles': volumes,
            'spawn': w01['spawn'], 'route_xz': w01['route_xz'], 'direction_xz': w01['direction_xz'], 'normal_xz': w01['normal_xz'], 'passage_length_m': w01['passage_length_m'],
            'counts': {'source_bodies': 685, 'active_source_bodies': 682, 'retained_gate_wall_fragments': 4, 'active_bodies': 687, 'created_bodies': 691, 'support_triangles': len(support['vertices']) // 9},
            'diagnostics': {'support_area_m2': floor.area, 'support_holes': len(floor.interiors), 'maximum_loop_adjustment_m': max(c['maximum_deviation_m'] for c in adjusted)}}
    blob, decision = encode(data), (root / INPUT).read_bytes()
    manifest = {'schema_version': 1, 'task': 'W02', 'world_sha256': provenance['game/resources/world_geometry/world.json'], 'w01_sha256': provenance['game/data/generated/daehanmun.json'], 'region_sha256': provenance['config/region.json'],
                'files': {'connection': {'path': 'res://data/generated/palace_walk.json', 'sha256': hashlib.sha256(blob).hexdigest()}, 'decision': {'path': 'res://data/generated/palace_decision.json', 'sha256': hashlib.sha256(decision).hexdigest()}}}
    for name, content in {OUT: blob, DECISION: decision, MANIFEST: encode(manifest)}.items():
        path = root / name
        if check_only:
            if not path.exists() or path.read_bytes() != content:
                raise ValueError('Missing/stale W02 generated file: ' + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    return {'task': 'W02', 'passed': True, 'connection_sha256': hashlib.sha256(blob).hexdigest(), 'routes': [{k: v for k, v in r.items() if k not in ['xz', 'source_xz', 'source_node_ids']} for r in routes], 'counts': data['counts'], 'diagnostics': data['diagnostics']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.root, args.check), ensure_ascii=False, indent=2))

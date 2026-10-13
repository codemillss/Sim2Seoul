#!/usr/bin/env python3
"""Independent, standard-library P04 evidence audit. Does not execute Godot.

All city probes isolate one collider. Surface hits do not prove closed volumes,
city walking, permission, measured terrain, gate traversal or NPC controllers.
Retained samples permit independent capsule/box checks; per-tick extrema remain
engine-produced bounds between the retained approximately 10 Hz samples.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import check_camera_evidence

IDENTITY = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]]
ROLES = {'static_world': (1, 14), 'player': (2, 13),
         'pedestrian': (4, 15), 'vehicle': (8, 15)}
SCOPE = {'runtime_permission': None, 'walkability_verified': False,
         'physical_terrain_verified': False, 'playable_boundary': None,
         'spawn': None, 'gate_openings': 'W01_pending',
         'support_plane': 'G03 temporary engineering plane only'}


def number(v):
    return isinstance(v, (float, int)) and not isinstance(v, bool) and math.isfinite(v)


def vector(v, size=3):
    return isinstance(v, list) and len(v) == size and all(number(x) for x in v)


def near(a, b, tolerance=.002):
    if isinstance(b, list):
        return isinstance(a, list) and len(a) == len(b) and all(near(x, y, tolerance) for x, y in zip(a, b))
    return number(a) and abs(a-b) <= tolerance


def same(a, b):
    if isinstance(b, dict):
        return isinstance(a, dict) and set(a) == set(b) and all(same(a[k], b[k]) for k in b)
    if isinstance(b, list):
        return isinstance(a, list) and len(a) == len(b) and all(same(x,y) for x,y in zip(a,b))
    if number(b):
        return near(a,b,1e-9)
    return type(a) is type(b) and a == b


def sub(a, b):
    return [x-y for x, y in zip(a, b)]


def add(a, b):
    return [x+y for x, y in zip(a, b)]


def norm(v):
    return math.sqrt(sum(x*x for x in v))


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def ring_inside(point, ring):
    x, z = point
    inside = False
    for a, b in zip(ring, ring[1:]):
        if (a[1] > z) != (b[1] > z) and x < (b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside


def polygons(feature):
    g = feature['geometry']
    return [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']


def inside(point, feature):
    return any(ring_inside(point, p[0]) and not any(ring_inside(point, h) for h in p[1:]) for p in polygons(feature))


def edge_distance(point, a, b):
    d = sub(b, a)
    t = max(0, min(1, dot(sub(point, a), d)/dot(d, d))) if dot(d, d) else 0
    return norm(sub(point, [a[i]+t*d[i] for i in range(2)]))


def ray_triangle(start, end, tri):
    """Moller-Trumbore segment intersection, accepting both triangle faces."""
    a, b, c = tri
    direction = sub(end, start)
    e1, e2 = sub(b, a), sub(c, a)
    p = cross(direction, e2)
    det = dot(e1, p)
    if abs(det) < 1e-10:
        return None
    tvec = sub(start, a)
    u = dot(tvec, p)/det
    q = cross(tvec, e1)
    v = dot(direction, q)/det
    t = dot(e2, q)/det
    if u < -1e-7 or v < -1e-7 or u+v > 1+1e-7 or not 0 <= t <= 1:
        return None
    return [start[i]+t*direction[i] for i in range(3)]


def audit(record, world, plan, features):
    checks = []
    def check(name, condition, details=None):
        item = {'name': name, 'passed': bool(condition)}
        if details is not None:
            item['details'] = details
        checks.append(item)

    def finite(value):
        if isinstance(value, float):
            return math.isfinite(value)
        if isinstance(value, dict):
            return all(finite(x) for x in value.values())
        if isinstance(value, list):
            return all(finite(x) for x in value)
        return True

    try:
        check('finite_values', all(finite(x) for x in (record, world, plan, features)))
        if not checks[-1]['passed']:
            raise ValueError('Non-finite evidence or source')
        check('schema', record['schema_version'] == 1 and record['task'] == 'P04'
              and isinstance(record['fault'], str) and world['task'] == 'E03'
              and plan['task'] == 'P04' and features['task_id'] == 'G02')
        check('source_world_sha256', record['source_world_sha256'] == plan['world_sha256'])
        encoded = (json.dumps(plan, ensure_ascii=False, separators=(',', ':'), allow_nan=False)+'\n').encode()
        check('source_collision_sha256', record['source_collision_sha256'] == hashlib.sha256(encoded).hexdigest())
        check('scope', plan['scope'] == SCOPE and record['rules']['scope'] == SCOPE and record['city']['scope'] == SCOPE)
        rules = record['rules']
        check('rules', rules['schema_version'] == 1 and rules['task'] == 'P04'
              and rules['body_roles'] == {k: {'layer': v[0], 'mask': v[1], 'layer_number': i+1} for i, (k,v) in enumerate(ROLES.items())}
              and rules['camera_query'] == {'layer': None, 'mask': 1, 'exclude_player_rid': True}
              and rules['static_selection'] == {'roles': ['Buildings','Barriers'], 'ground_ids': ['temporary_support'], 'shape': 'ConcavePolygonShape3D', 'backface_collision': True})
        camera = record['camera_fixture']
        check('camera_fixture.structure', len(camera['cases']) == 37 and camera['engine'] == record['engine'] and camera['case'] == 'normal')
        checks.extend({'name': 'camera_fixture.'+x['name'], 'passed': x['passed'], **({'details': x['details']} if 'details' in x else {})} for x in check_camera_evidence.audit(camera)['checks'])
        matrix = record['matrix']
        check('matrix.actual_player', matrix['player_layer'] == 2 and matrix['player_mask'] == 13)
        rows = matrix['pairs']
        wanted = {(a,b) for a in ('player','pedestrian','vehicle') for b in ROLES}
        check('matrix.pair_coverage', len(rows) == 12 and {(x['moving_role'],x['target_role']) for x in rows} == wanted)
        for i, row in enumerate(rows):
            ml, mm = ROLES[row['moving_role']]; tl, tm = ROLES[row['target_role']]
            expected = bool(mm & tl or tm & ml)
            check(f'matrix.pair[{i}]', row['moving_layer'] == ml and row['moving_mask'] == mm and row['target_layer'] == tl and row['target_mask'] == tm and row['motion'] == [4,0,0] and row['hit'] is expected and row['collider'] == ('MatrixTarget' if expected else ''))
        rows = matrix['camera']
        check('matrix.camera_coverage', len(rows) == 4 and {r['target_role'] for r in rows} == set(ROLES))
        for row in rows:
            expected = row['target_role'] == 'static_world'
            check('matrix.camera.'+row['target_role'], row['mask'] == 1 and row['hit'] is expected and row['collider'] == ('MatrixTarget' if expected else ''))
        masks = matrix['fixture_masks']
        check('matrix.fixture_masks', len(masks) == 14 and len({x['name'] for x in masks}) == 14 and all(x['layer'] == 1 and x['mask'] == 14 for x in masks))

        extra = record['fixture_extra']
        names = {f'{stem}_{pace}' for stem in ('wall','wall_oblique','wall_corner','building') for pace in ('walk','run')}
        check('fixture_extra.coverage', len(extra) == 8 and {x['name'] for x in extra} == names)
        boxes = camera['fixtures']
        for case in extra:
            title = 'fixture_extra.'+case['name']
            stats = case['player_all_tick_stats']; samples = case['samples']
            check(title+'.clock', case['ticks'] == 120 and near(case['duration_s'], 2, 1e-6) and case['recoveries'] == 0 and number(case['wall_s']) and case['wall_s'] > 0 and number(case['frames']) and case['frames'] >= 0)
            check(title+'.all_ticks', stats['ticks'] == 120 and number(stats['max_box_penetration_m']) and 0 <= stats['max_box_penetration_m'] <= .005 and number(stats['solid_contact_ticks']) and 0 < stats['solid_contact_ticks'] <= 120)
            camera_stats = case['all_tick_stats']
            check(title+'.camera_all_ticks', camera_stats['ticks'] == 120 and camera_stats['max_camera_overlap_count'] == 0 and camera_stats['max_near_hit_count'] == 0 and 0 <= camera_stats['max_follow_error_m'] <= .002 and 0 <= camera_stats['max_length_excess_m'] <= .002 and camera_stats['max_tick_mismatch'] == 0 and 0 <= camera_stats['floor_ticks'] <= 120 and 0 <= camera_stats['min_distance'] <= camera_stats['max_distance'] <= 6.002)
            times = [s['t'] for s in samples]
            check(title+'.samples', len(samples) >= 20 and len(samples) <= 121 and all(number(t) for t in times) and 0 <= times[0] <= .02 and near(times[-1], 2, 1e-6) and all(0 < b-a <= .11 for a,b in zip(times,times[1:])) and near(case['end'],samples[-1]['player']) and norm(sub(case['start'],samples[0]['player'])) <= .07)
            if camera['suite'] == 'gpu':
                check(title+'.actual_clock', abs(case['wall_s']-2) <= .04 and abs(case['frames']/case['wall_s']-record['engine']['render_cap_fps']) <= .2*record['engine']['render_cap_fps'])
            for i, sample in enumerate(samples):
                rig = sample['rig']
                camera_pos = rig['camera']; pivot = rig['pivot']; corners = sample['near_corners']
                check(title+f'.sample[{i}].camera', vector(camera_pos) and vector(pivot) and isinstance(corners,list) and len(corners) == 4 and all(vector(c) for c in corners) and sample['camera_overlap'] == [] and sample['near_ray_hits'] == [] and rig['mask'] == 1 and rig['follow_ticks'] == rig['observed_ticks'] and near(pivot,add(sample['player'],[0,1.3,0])) and 0 <= rig['distance'] <= rig['hit_length']+.002 <= rig['requested_distance']+.004 and 2 <= rig['requested_distance'] <= 6 and near(norm(sub(camera_pos,pivot)),rig['distance']) and near(rig['probe_radius'],.2) and all(norm([max(b['lo'][j]-camera_pos[j],0,camera_pos[j]-b['hi'][j]) for j in range(3)]) >= .198 for b in boxes) and not any(all(b['lo'][j]+.002 < c[j] < b['hi'][j]-.002 for j in range(3)) for b in boxes for c in corners) and camera_stats['min_distance']-.002 <= rig['distance'] <= camera_stats['max_distance']+.002)
                point = sample['player']
                if not vector(point):
                    raise ValueError('Invalid retained player vector')
                penetration = max([0]+[.3-math.sqrt(max(b['lo'][0]-point[0],point[0]-b['hi'][0],0)**2+max(b['lo'][2]-point[2],point[2]-b['hi'][2],0)**2+max(b['lo'][1]-(point[1]+1.4),point[1]+.3-b['hi'][1],0)**2) for b in boxes])
                check(title+f'.sample[{i}].capsule_box', number(sample['player_box_penetration_m']) and near(sample['player_box_penetration_m'], penetration, .0001) and penetration <= .005 and stats['max_box_penetration_m']+.0001 >= penetration)

        meshes = {m['id']: m for m in world['meshes']}
        check('world.unique', len(meshes) == len(world['meshes']) == 1233)
        selected = {key for key,m in meshes.items() if m['role'] in ('Buildings','Barriers') or key == 'temporary_support'}
        entries = {e['mesh_id']: e for e in plan['entries']}
        excluded = {e['mesh_id']: e for e in plan['excluded']}
        check('plan.selection', len(entries) == len(plan['entries']) == 685 and set(entries) == selected and len(excluded) == len(plan['excluded']) == 548 and set(excluded) == set(meshes)-selected)
        counts = {'colliders':685,'roles':{'Ground':1,'Buildings':635,'Barriers':49},'triangles':sum(len(meshes[x]['vertices'])//9 for x in selected),'excluded':548}
        check('plan.counts', plan['counts'] == counts and record['city']['counts'] == counts and Counter(meshes[x]['role'] for x in selected) == counts['roles'])
        items = record['city']['inventory']
        inventory = {x['mesh_id']: x for x in items}
        check('city.inventory_coverage', len(items) == len(inventory) == 1233 and set(inventory) == set(meshes))
        for key, mesh in meshes.items():
            item = inventory[key]
            bodies = item['bodies']
            check('city.'+key+'.source', item['role'] == mesh['role'] and 'source_permission' in item and item['source_permission'] is None and mesh['metadata']['runtime_permission'] is None and mesh['metadata']['collision_generated'] is False and near(item['mesh_transform'],IDENTITY,1e-6) and item['body_count'] == len(bodies) == (1 if key in selected else 0))
            if key not in selected:
                check('excluded.'+key, excluded[key]['role'] == mesh['role'])
                continue
            entry = entries[key]
            check('plan.'+key, entry['role'] == mesh['role'] and entry['layer'] == 1 and entry['mask'] == 14 and entry['shape'] == 'ConcavePolygonShape3D' and entry['backface_collision'] is True and entry['runtime_permission'] is None and entry['holes'] == mesh['topology']['holes'] and entry['triangles'] == len(mesh['vertices'])//9 and entry['face_sha256'] == hashlib.sha256(json.dumps(mesh['vertices'],separators=(',',':')).encode()).hexdigest())
            if len(bodies) != 1:
                continue
            body = bodies[0]
            shapes = body['shapes']
            check('city.'+key+'.body', body['type'] == 'StaticBody3D' and body['layer'] == 1 and body['mask'] == 14 and body['has_scope'] is True and 'permission' in body and body['permission'] is None and near(body['transform'],IDENTITY,1e-6) and len(shapes) == 1)
            digest = hashlib.sha256(struct.pack('<'+str(len(mesh['vertices']))+'f',*mesh['vertices'])).hexdigest()
            for shape in shapes:
                check('city.'+key+'.shape', shape['type'] == 'ConcavePolygonShape3D' and shape['disabled'] is False and shape['backface_collision'] is True and shape['face_count'] == len(mesh['vertices'])//3 and shape['faces_float32_sha256'] == digest and near(shape['transform'],IDENTITY,1e-6))
        city = record['city']
        check('city.mode', city['runtime_ok'] is True and city['fixture_inactive'] is True and city['player_physics_inactive'] is True and city['camera_input_disabled'] is True and city['active_mode'] in ('city','city_palace'))
        gates = [{'mesh_id': k, 'name': m['metadata']['name'], 'opening':'not_created_W01_pending'} for k,m in meshes.items() if m['metadata']['name'] in ('대한문','중화문') and k in selected]
        check('gates_pending', len(gates) == 2 and plan['gates_pending'] == gates and city['gates_pending'] == gates)
        by_feature = {f['feature_id']: f for f in features['features']}
        for category, expected_count in (('surface_probes',44),('hole_probes',24),('capsule_moves',8)):
            specs = plan[category]; results = city[category]
            canonical = lambda s: json.dumps(s,sort_keys=True,separators=(',',':'))
            check(category+'.coverage', len(specs) == len(results) == expected_count and len({canonical(s) for s in specs}) == expected_count and same([r['spec'] for r in results], specs))
            for i,result in enumerate(results):
                spec = result['spec']; mesh = meshes[spec['mesh_id']]
                prefix = category+f'[{i}]'
                check(prefix+'.scope', 'other colliders excluded' in result['scope'])
                if category == 'surface_probes':
                    check(prefix+'.triangle_index', number(spec['triangle_index']) and spec['triangle_index'] == int(spec['triangle_index']) and 0 <= spec['triangle_index'] < len(mesh['vertices'])//9)
                    index = int(spec['triangle_index'])*9
                    values = mesh['vertices'][index:index+9]
                    tri = [values[j:j+3] for j in (0,3,6)]
                    centre = [sum(v[j] for v in tri)/3 for j in range(3)]
                    normal = cross(sub(tri[1],tri[0]),sub(tri[2],tri[0])); normal = [x/norm(normal) for x in normal]
                    n = spec['normal']
                    hit = ray_triangle(spec['from'],spec['to'],tri)
                    check(prefix+'.source_triangle', len(values) == 9 and near(spec['point'],centre,1e-6) and vector(n) and near(norm(n),1,1e-6) and abs(dot(n,normal)) >= .999999 and near(norm(sub(spec['from'],centre)),.5,1e-6) and near(add(spec['from'],spec['to']),[2*x for x in centre],1e-6) and hit is not None and near(hit,centre,1e-6))
                    vertices = mesh['vertices']
                    ray_hits = [p for j in range(0,len(vertices),9) if (p := ray_triangle(spec['from'],spec['to'],[vertices[j+k:j+k+3] for k in (0,3,6)])) is not None]
                    nearest_hit = min(ray_hits,key=lambda p:norm(sub(p,spec['from']))) if ray_hits else None
                    check(prefix+'.actual_hit', spec['expected_hit'] is True and result['hit'] is True and result['collider_id'] == spec['mesh_id'] and nearest_hit is not None and near(result['position'],nearest_hit) and vector(result['normal']) and near(norm(result['normal']),1))
                elif category == 'hole_probes':
                    point = [spec['from'][0],spec['from'][2]]
                    feature = by_feature[spec['mesh_id']]
                    check(prefix+'.source_hole', spec['kind'] == 'hole_cap_clear' and any(ring_inside(point,h) for p in polygons(feature) for h in p[1:]) and not inside(point,feature) and near(spec['from'][1],mesh['top_y_m']+.5,1e-6) and near(spec['to'],[point[0],mesh['bottom_y_m']+.05,point[1]],1e-6))
                    verts = mesh['vertices']
                    check(prefix+'.source_cap_clear', not any(ray_triangle(spec['from'],spec['to'],[verts[j+k:j+k+3] for k in (0,3,6)]) is not None for j in range(0,len(verts),9)))
                    check(prefix+'.actual_clear', spec['expected_hit'] is False and result['hit'] is False and result['collider_id'] == '' and result['position'] == [] and result['normal'] == [])
                else:
                    feature = by_feature[spec['mesh_id']]; n = spec['outward_normal']; mid = spec['edge_midpoint']; start = spec['start']; motion = spec['motion']
                    horizontal = lambda v:[v[0],v[2]]
                    edges = [(a,b) for p in polygons(feature) for a,b in zip(p[0],p[0][1:])]
                    nearest = min(edge_distance(horizontal(mid),a,b) for a,b in edges)
                    check(prefix+'.source_geometry', spec['kind'] == 'external_wall_capsule_sweep' and near(norm(n),1,1e-6) and n[1] == 0 and nearest <= 1e-6 and near(mid[1],mesh['bottom_y_m']+.85,1e-6) and near(start,[mid[0]+n[0]*.8,mesh['bottom_y_m']+.08,mid[2]+n[2]*.8],1e-6) and near(motion,[-1.6*x for x in n],1e-6) and not inside(horizontal(start),feature) and inside(horizontal(add(start,motion)),feature) and min(edge_distance(horizontal(start),a,b) for a,b in edges) >= .35)
                    travel = result['travel']
                    check(prefix+'.actual_stop', result['hit'] is True and result['collider_id'] == spec['mesh_id'] and near(result['start'],start) and near(result['end'],add(result['start'],travel)) and near(add(travel,result['remainder']),motion) and .45 <= norm(travel) <= .53 and near(travel,[motion[j]*norm(travel)/1.6 for j in range(3)]) and near(result['height'],1.7,1e-6) and near(result['radius'],.3,1e-6) and result['mask'] == 13 and not inside(horizontal(result['end']),feature) and .295 <= dot(sub(result['end'],mid),n) <= .32)
    except (ValueError, TypeError, KeyError, IndexError, AttributeError, ZeroDivisionError, OverflowError, struct.error) as exc:
        check('read_or_schema', False, str(exc))
    anomalies = [x for x in checks if not x['passed']]
    return {'passed': bool(checks) and not anomalies, 'checks': checks, 'anomalies': anomalies,
            'scope': 'P04 synthetic fixture and isolated city shell evidence only; city walking, gate openings, permissions, terrain and NPC controllers unverified'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--world', type=Path, default=Path('game/resources/world_geometry/world.json'))
    parser.add_argument('--plan', type=Path, default=Path('game/resources/collision/generated.json'))
    parser.add_argument('--features', type=Path, default=Path('data/processed/features.json'))
    args = parser.parse_args()
    try:
        record, world, plan, features = [json.loads(p.read_text(encoding='utf-8')) for p in (args.input,args.world,args.plan,args.features)]
        result = audit(record,world,plan,features)
        matched = record['source_world_sha256'] == hashlib.sha256(args.world.read_bytes()).hexdigest() and record['source_collision_sha256'] == hashlib.sha256(args.plan.read_bytes()).hexdigest()
        result['checks'].append({'name':'source_file_bytes','passed':matched})
        if not matched:
            result['anomalies'].append(result['checks'][-1]); result['passed'] = False
    except (OSError,ValueError,TypeError,KeyError) as exc:
        result = {'passed':False,'checks':[{'name':'read_or_schema','passed':False,'details':str(exc)}]}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

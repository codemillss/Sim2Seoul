#!/usr/bin/env python3
"""Independently inspect L02 instantiated exterior surfaces, not recognition.

The caller supplies bytes-bound engine observations and prepared inputs. This
module does not import the producer, infer walkability from a picture, or replace
the existing continuous walking/camera audit. Full projected triangles, including
edges across concavities and holes, must remain in their original source volume.
"""
import argparse
import json
import math
import re
import struct
from collections import Counter
from pathlib import Path

from shapely.geometry import MultiPoint, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    'daehanmun': 'osm:way:377289797:building',
    'junghwajeon': 'osm:way:181574577:building',
    'junghwamun': 'osm:way:181574580:building',
    'seokjojeon': 'osm:relation:19357693:building',
    'dondeokjeon': 'osm:way:517072312:building',
    'jeonggwanheon': 'osm:way:381755268:building',
}
FRAGMENTS = ['W01_gate_side_0', 'W01_gate_side_1', 'W01_gate_lintel']
ROLES = {'roof', 'column', 'podium', 'backing', 'window', 'pediment', 'railing', 'beam'}
# Source vertices are rounded to micrometres. Godot uses float32 positions, whose
# spacing reaches 0.0000153 m around this site's +/-250 m coordinates.
ENGINE_TOLERANCE_M = .00004


def finite_numbers(values):
    return (isinstance(values, list) and all(type(v) in (int, float) and
            math.isfinite(v) for v in values))


def float32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def float32_equal(actual, source):
    return (finite_numbers(actual) and finite_numbers(source) and
            len(actual) == len(source) and
            all(abs(a - float32(b)) < 1e-9 for a, b in zip(actual, source)))


def triangles(flat):
    return [[flat[i+j:i+j+3] for j in (0, 3, 6)] for i in range(0, len(flat), 9)]


def projected(points):
    # Convex hull preserves projected line/point faces too; vertices alone would
    # miss a triangle cutting over a footprint hole or concave notch.
    return MultiPoint([(p[0], p[2]) for p in points]).convex_hull


def clipped_below(points, ceiling):
    result = []
    for a, b in zip(points, points[1:] + points[:1]):
        inside_a, inside_b = a[1] < ceiling, b[1] < ceiling
        if inside_a:
            result.append(a)
        if inside_a != inside_b:
            t = (ceiling-a[1])/(b[1]-a[1])
            result.append([a[i]+t*(b[i]-a[i]) for i in range(3)])
    return result


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0]]


def norm(v):
    return math.sqrt(sum(n*n for n in v))


def centre(component):
    v = component['vertices']
    return [(min(v[i::3])+max(v[i::3]))/2 for i in range(3)]


def audit(record, bundle, spec, w01):
    """Return {passed, checks, ...} from actual MeshInstance3D observations.

    File SHA binding is the driver's responsibility: dict inputs cannot reproduce
    original file bytes. The observation reader must be frozen before execution.
    """
    checks = []
    def ck(name, passed, details=None):
        checks.append({'name': name, 'passed': bool(passed),
                       **({'details': details} if details is not None else {})})
    try:
        items = bundle['landmarks']
        by = {r['id']: r for r in items}
        references = {r['id']: r for r in spec['landmarks'] if r['phase'] == 'L02'}
        actual_rows = record['components']
        actual = {r['id']: r for r in actual_rows}
        entries = [(item['id'], c) for item in items for c in item['components']]
        generated = {c['id']: (id, c) for id, c in entries}
        ck('scope.six_unique_source_bound_landmarks', bundle.get('schema_version') == 1 and
           bundle.get('task') == 'L02' and len(items) == len(by) == 6 and
           set(by) == set(TARGETS) == set(references) and
           all(by[id]['feature_id'] == fid for id, fid in TARGETS.items()))
        ck('scope.no_new_colliders_or_permissions', record.get('collision_objects') == 0 and
           all(row.get('collision_generated') is False and row.get('runtime_permission') is None
               for row in items) and bundle['counts']['new_collision_bodies'] == 0 and
           bundle['counts']['new_routes'] == 0 and bundle['counts']['imported_media_files'] == 0)
        ck('engine.loaded_visible_overlay', record.get('loaded') is True and
           record.get('visible') is True and bool(re.fullmatch('[a-f0-9]{64}', record.get('bundle_sha256', ''))))
        ck('engine.unique_complete_component_inventory', len(actual_rows) == len(actual) ==
           len(entries) == len(generated) and set(actual) == set(generated) and bool(entries))
        expected_hidden = {r['spatial_binding']['current_visual_mesh_id'] for r in references.values()}
        part_ids = set(references['seokjojeon']['spatial_binding']['height_component_ids'])
        world_path = ROOT / 'game/resources/world_geometry/world.json'
        if world_path.exists():
            world = json.loads(world_path.read_text())
            expected_hidden.update(m['id'] for m in world['meshes'] if
                                   m.get('metadata', {}).get('feature_id') in part_ids)
        ck('engine.only_replaced_source_meshes_hidden', set(bundle['hidden_mesh_ids']) == expected_hidden and
           len(bundle['hidden_mesh_ids']) == len(expected_hidden) and
           set(record['hidden_sources']) == expected_hidden and
           all(v is False for v in record['hidden_sources'].values()))
        ck('engine.only_gate_fragments_hidden', bundle['hidden_fragment_ids'] == FRAGMENTS and
           set(record['hidden_fragments']) == set(FRAGMENTS) and
           all(v is False for v in record['hidden_fragments'].values()))
        ck('gate.original_opening_and_route_retained', bundle['protected_gate'] == spec['protected_gate'] and
           bundle['protected_gate']['opening_m'] == w01['opening'] == {'width': 3.0, 'height': 3.0} and
           bundle['protected_gate']['route_xz'] == w01['route_xz'] and
           bundle['protected_gate']['physical_dimensions_verified'] is False)
        sides = unary_union([shape({'type': 'MultiPolygon', 'coordinates': v['rings']})
                             for v in w01['volume_obstacles'] if v['id'] in FRAGMENTS[:2]])
        gate_offenders = []
        summaries = []
        for id, item in by.items():
            prefix = id + '.'
            ref = references[id]
            binding = ref['spatial_binding']
            footprint = shape(binding['geometry'])
            ck(prefix+'exact_L01_spatial_and_height_binding', item['source_binding'] == binding and
               item['source_name'] == ref['source_name'] and item['minimum_features'] == ref['minimum_features'])
            o = item['orientation']; u, v, origin = o['u_axis_xz'], o['v_axis_xz'], o['origin_xz_m']
            ck(prefix+'metre_unit_axes_and_documented_orientation', finite_numbers(u+v+origin) and
               len(u) == len(v) == len(origin) == 2 and abs(norm(u)-1) < 1e-8 and
               abs(norm(v)-1) < 1e-8 and abs(sum(a*b for a,b in zip(u,v))) < 1e-8 and
               bool(o.get('basis')) and o.get('front_side') in ('positive_v', 'negative_v') and
               footprint.buffer(ENGINE_TOLERANCE_M).covers(projected([[origin[0],0,origin[1]]])))
            if id == 'daehanmun':
                ck(prefix+'original_passage_axis', u == w01['normal_xz'] and v == w01['direction_xz'])
            valid, arrays, surface, containment, envelope, winding = [], [], [], [], [], []
            degenerate, geometric, sloped_area, material_area = [], [], 0.0, Counter()
            live = []
            for source in item['components']:
                cid = source['id']; observed = actual.get(cid, {})
                verts, normals = observed.get('vertices'), observed.get('normals')
                okay = (finite_numbers(verts) and finite_numbers(normals) and
                        len(verts) >= 9 and len(verts) % 9 == 0 and len(verts) == len(normals))
                valid.append(okay)
                arrays.append(okay and float32_equal(verts, source.get('vertices')) and
                              float32_equal(normals, source.get('normals')))
                surface.append(observed.get('identity') is True and observed.get('visible') is True and
                               observed.get('landmark_id') == id and observed.get('feature_role') == source.get('feature_role') and
                               source.get('feature_role') in ROLES and observed.get('primitive') == 3 and
                               observed.get('cull_mode') == 0 and
                               float32_equal(observed.get('material_rgb'), bundle['palette'][source['material']]))
                if not okay:
                    continue
                live.append(observed)
                low, high = min(verts[1::3]), max(verts[1::3])
                if low < binding['current_bottom_y_m']-ENGINE_TOLERANCE_M or high > binding['current_top_y_m']+ENGINE_TOLERANCE_M:
                    envelope.append(cid)
                for n, triangle in enumerate(triangles(verts)):
                    if not footprint.buffer(ENGINE_TOLERANCE_M).covers(projected(triangle)):
                        containment.append([cid, n])
                    if id == 'daehanmun':
                        clipped = clipped_below(triangle, 3.0-ENGINE_TOLERANCE_M)
                        if clipped and not sides.buffer(ENGINE_TOLERANCE_M).covers(projected(clipped)):
                            gate_offenders.append([cid, n])
                    a,b,c = triangle
                    face = [-q for q in cross([b[j]-a[j] for j in range(3)], [c[j]-a[j] for j in range(3)])]
                    area2 = norm(face)
                    if area2 < 1e-10:
                        degenerate.append([cid, n]); continue
                    geometric.append(area2/2)
                    ns = normals[n*9:n*9+9]
                    if any(abs(norm(ns[j:j+3])-1) > .00001 or
                           sum(face[k]*ns[j+k] for k in range(3))/area2 < .99 for j in (0,3,6)):
                        winding.append([cid,n])
                    material_area[source['material']] += area2/2
                    if source['feature_role'] == 'roof' and .03 < face[1]/area2 < .999:
                        sloped_area += area2/2
            ck(prefix+'actual_finite_triangle_arrays', bool(valid) and all(valid))
            ck(prefix+'actual_float32_arrays_match_bundle', bool(arrays) and all(arrays))
            ck(prefix+'actual_visible_identity_material_and_front_culling', bool(surface) and all(surface))
            ck(prefix+'full_projected_triangles_inside_original_footprint', not containment,
               {'offenders': containment[:12], 'tolerance_m': ENGINE_TOLERANCE_M})
            ck(prefix+'actual_vertical_envelope_preserved', not envelope, envelope[:12])
            ck(prefix+'clockwise_faces_and_unit_consistent_normals', not winding and not degenerate and bool(geometric),
               {'bad_normals': winding[:12], 'collapsed_faces': degenerate[:12]})
            roles = Counter(row['feature_role'] for row in live)
            roofs = [row for row in live if row['feature_role'] == 'roof']
            columns = [row for row in live if row['feature_role'] == 'column' and 'railing_post' not in row['id'] and 'cap' not in row['id']]
            backings = [row for row in live if row['feature_role'] == 'backing']
            ck(prefix+'nonempty_roof_and_closed_backing_geometry', bool(roofs) and bool(backings) and
               all(max(c['vertices'][1::3])-min(c['vertices'][1::3]) > .1 for c in backings))
            if id in {'daehanmun', 'junghwajeon', 'junghwamun', 'jeonggwanheon'}:
                us = [sum((centre(c)[j*2]-origin[j])*u[j] for j in range(2)) for c in columns]
                span = max(us)-min(us) if us else 0
                bounds = o['local_bounds_m']
                ck(prefix+'geometric_sloped_roof_and_separated_column_rhythm', sloped_area > 1 and
                   len(columns) >= 4 and span > .4*(bounds[2]-bounds[0]),
                   {'sloped_roof_area_m2': sloped_area, 'columns': len(columns), 'column_u_span_m': span})
            if id in {'junghwajeon', 'junghwamun'}:
                ck(prefix+'stone_podium_and_closed_gate_or_hall', roles['podium'] > 0 and bool(backings))
            if id == 'seokjojeon':
                pediments = [r for r in live if r['feature_role'] == 'pediment']
                steps = [r for r in live if r['feature_role'] == 'podium' and 'stair_relief' in r['id']]
                step_heights = sorted({round(max(r['vertices'][1::3]), 4) for r in steps})
                ck(prefix+'light_classical_columns_and_raised_pediment', len(columns) >= 4 and bool(pediments) and
                   material_area['light_stone'] > 10 and any(max(p['vertices'][1::3])-min(p['vertices'][1::3]) > .3 for p in pediments),
                   {'columns':len(columns), 'pediments':len(pediments)})
                ck(prefix+'actual_multi_height_stair_relief', len(steps) >= 3 and len(step_heights) >= 3,
                   {'steps':len(steps), 'top_heights_m':step_heights})
            if id == 'dondeokjeon':
                windows = [r for r in live if r['feature_role'] == 'window']
                levels = sorted({round(centre(r)[1],3) for r in windows})
                accents = [r for r in roofs if 'corner_roof' in r['id']]
                ck(prefix+'brick_teal_contrast_two_actual_window_levels_and_corner_roofs',
                   material_area['brick'] > 10 and material_area['teal_window'] > 1 and
                   len(levels) == 2 and levels[1]-levels[0] > 1 and len(accents) >= 2,
                   {'window_centre_y_m':levels,'corner_roofs':len(accents)})
            if id == 'jeonggwanheon':
                rails = [r for r in live if r['feature_role'] == 'railing']
                ck(prefix+'low_selected_body_and_actual_railings', binding['height_m'] == 6 and len(rails) >= 2 and
                   len(columns) >= 4 and bool(backings))
            summaries.append({'id':id, 'components':len(live), 'triangles':sum(len(c['vertices'])//9 for c in live),
                              'roles':dict(roles), 'sloped_roof_area_m2':sloped_area})
        ck('gate.all_visible_geometry_below_3m_in_original_side_solids', not gate_offenders,
           {'offenders':gate_offenders[:12], 'tolerance_m':ENGINE_TOLERANCE_M})
        ck('counts.actual_geometry_matches_bundle', bundle['counts']['landmarks'] == 6 and
           bundle['counts']['components'] == len(actual) and bundle['counts']['triangles'] ==
           sum(len(r.get('vertices',[]))//9 for r in actual_rows))
    except (KeyError, TypeError, ValueError, IndexError, OverflowError) as error:
        ck('observation.complete_parseable_contract', False, str(error))
        summaries = []
    return {'task':'L02', 'passed':all(c['passed'] for c in checks), 'checks':checks,
            'target_summary':summaries, 'scope':'Actual visible surfaces and source-volume preservation only; '
            'recognition, continuous walking/camera, human handling, performance and M4 need separate evidence.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('record', type=Path)
    parser.add_argument('--bundle', type=Path, default=ROOT/'game/data/generated/palace_landmarks.json')
    parser.add_argument('--spec', type=Path, default=ROOT/'data/processed/landmark_spec.json')
    parser.add_argument('--gate', type=Path, default=ROOT/'game/data/generated/daehanmun.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    read = lambda p: json.loads(p.read_text())
    result = audit(read(args.record), read(args.bundle), read(args.spec), read(args.gate))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    print('L02 actual exterior',result['passed'],'checks',len(result['checks']))
    if not result['passed']: print([c for c in result['checks'] if not c['passed']])
    raise SystemExit(0 if result['passed'] else 1)

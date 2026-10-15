#!/usr/bin/env python3
"""Independently audit L03 engine surfaces and their original source volumes.

This is a geometric/material/lineage audit, not a human recognition judgement.
The caller must bind the observation to the executed files by their byte hashes
and run the unchanged walking/camera audit separately. No producer is imported.
"""
import argparse
import hashlib
import json
import math
import re
import struct
from collections import Counter, defaultdict
from pathlib import Path

from shapely.geometry import shape
from shapely.ops import unary_union

from check_palace_landmarks_evidence import (
    ENGINE_TOLERANCE_M, FRAGMENTS, cross, finite_numbers, float32_equal,
    norm, packed_normals_equal, projected, triangles,
)

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    'city_hall': 'osm:way:198561926:building',
    'library': 'osm:relation:10757525:building',
    'plaza': 'osm:way:370019676:land_area',
    'sfc': 'osm:way:332565592:building',
}
REQUIRED_ROLES = {
    'city_hall': {'curved_roof', 'glass', 'frame'},
    'library': {'stone', 'window', 'central_facade'},
    'plaza': {'grass', 'paving'},
    'sfc': {'reused_model'},
}
ROLES = set().union(*REQUIRED_ROLES.values()) | {'stone'}
ALLOWED_ROLES = {
    'city_hall': {'stone', 'glass', 'frame', 'curved_roof'},
    'library': {'stone', 'window', 'central_facade', 'roof'},
    # Frame marks are independently authored relief, not claimed GLB lineage.
    'plaza': {'grass', 'paving'}, 'sfc': {'reused_model', 'stone', 'frame'},
}
ROLE_ALIASES = {
    'curved_glass_mass': 'glass', 'glass_grid': 'frame',
    'long_eave': 'curved_roof', 'low_stone_mass': 'stone',
    'stone_bands': 'stone', 'base': 'stone',
    'vertical_window_rhythm': 'window',
    'grass_surface': 'grass', 'paving_surface': 'paving',
}
REUSE_SOURCE = 'game/assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb'


def canonical_role(landmark, role):
    if role == 'roof' and landmark == 'city_hall':
        return 'curved_roof'
    return ROLE_ALIASES.get(role, role)


def read_glb_mesh(path):
    """Read GLB positions/indices with struct, independently of Godot/importer.

    Only the indexed TRIANGLES mesh used in this experiment is accepted. Strided
    accessors and unsigned byte/short/int indices are supported. External buffers,
    sparse data, non-float positions, and scene transforms are not silently used.
    """
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    if magic != 0x46546c67 or version != 2 or length != len(raw):
        raise ValueError('Invalid GLB 2 header')
    chunks = {}; offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        if offset+size > len(raw) or kind in chunks:
            raise ValueError('Invalid/duplicate GLB chunk')
        chunks[kind] = raw[offset:offset+size]; offset += size
    doc = json.loads(chunks[0x4e4f534a])
    binary = chunks[0x004e4942]
    if len(doc['buffers']) != 1 or 'uri' in doc['buffers'][0]:
        raise ValueError('Expected one embedded GLB geometry buffer')
    for node in doc.get('nodes', []):
        if any(key in node for key in ('matrix', 'translation', 'rotation', 'scale')):
            raise ValueError('Source node transforms need an explicit independent implementation')

    def accessor(index, position=False):
        a = doc['accessors'][index]
        if a.get('sparse') or a.get('normalized'):
            raise ValueError('Unsupported sparse/normalized source accessor')
        fmt, width = {5121: ('B', 1), 5123: ('H', 2),
                      5125: ('I', 4), 5126: ('f', 4)}[a['componentType']]
        count = {'SCALAR': 1, 'VEC3': 3}[a['type']]
        if position and (a['componentType'] != 5126 or a['type'] != 'VEC3'):
            raise ValueError('Source POSITION must be float VEC3')
        if not position and (a['componentType'] == 5126 or count != 1):
            raise ValueError('Source indices must be unsigned integers')
        view = doc['bufferViews'][a['bufferView']]
        if view['buffer'] != 0:
            raise ValueError('Unexpected source buffer')
        start = view.get('byteOffset', 0)+a.get('byteOffset', 0)
        stride = view.get('byteStride', width*count)
        end = start+(a['count']-1)*stride+width*count if a['count'] else start
        if (stride < width*count or end > len(binary) or
                end > view.get('byteOffset', 0)+view['byteLength']):
            raise ValueError('Source accessor exceeds its buffer view')
        values = [list(struct.unpack_from('<'+fmt*count, binary, start+i*stride))
                  for i in range(a['count'])]
        return values if position else [v[0] for v in values]

    source_triangles = []
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            if primitive.get('mode', 4) != 4:
                raise ValueError('Source primitive is not TRIANGLES')
            positions = accessor(primitive['attributes']['POSITION'], True)
            if not positions or any(not finite_numbers(p) for p in positions):
                raise ValueError('Nonfinite/empty source POSITION array')
            indices = accessor(primitive['indices'])
            if len(indices) % 3 or any(i >= len(positions) for i in indices):
                raise ValueError('Invalid source triangle indices')
            for i in range(0, len(indices), 3):
                # GLTFDocument's native indexed winding is [a,c,b]. Lineage
                # weights are explicitly defined against that native ordering.
                source_triangles.append([positions[indices[i+j]] for j in (0, 2, 1)])
    return raw, source_triangles


def reuse_geometry(bundle):
    reuse = bundle['reuse']; t = reuse['transform']
    if reuse['source_path'] != REUSE_SOURCE or reuse['method'] != 'nonuniform_fit_then_footprint_prism_clip':
        raise ValueError('Unexpected external source or reuse method')
    raw, source = read_glb_mesh(ROOT / REUSE_SOURCE)
    if hashlib.sha256(raw).hexdigest() != reuse['source_sha256']:
        raise ValueError('External source SHA mismatch')
    actual_bounds = [[min(p[k] for tri in source for p in tri),
                      max(p[k] for tri in source for p in tri)] for k in range(3)]
    bounds = reuse['source_bounds']
    if (len(bounds) != 3 or any(not finite_numbers(b) or len(b) != 2 for b in bounds) or
            any(abs(bounds[k][i]-actual_bounds[k][i]) > 1e-7 for k in range(3) for i in range(2))):
        raise ValueError('External source bounds mismatch')
    origin, u, v = t['origin_xz_m'], t['u_axis_xz'], t['v_axis_xz']
    centre, scales = t['local_center_uv'], t['scale_xyz']
    if (any(not finite_numbers(x) or len(x) != 2 for x in (origin, u, v, centre)) or
            not finite_numbers(scales) or len(scales) != 3 or min(scales) <= 0 or
            not finite_numbers([t['bottom_y_m']]) or abs(norm(u)-1) > 1e-8 or
            abs(norm(v)-1) > 1e-8 or abs(sum(a*b for a, b in zip(u, v))) > 1e-8):
        raise ValueError('Invalid external source fit transform')

    def transform(p):
        a = (p[0]-(bounds[0][0]+bounds[0][1])/2)*scales[0]+centre[0]
        b = (p[2]-(bounds[2][0]+bounds[2][1])/2)*scales[2]+centre[1]
        return [origin[0]+u[0]*a+v[0]*b,
                t['bottom_y_m']+(p[1]-bounds[1][0])*scales[1],
                origin[1]+u[1]*a+v[1]*b]
    return source, transform


def lineage_matches(component, source, transform):
    lineage = component.get('reuse_lineage', [])
    faces = triangles(component['vertices'])
    if not lineage or len(lineage) != len(faces):
        return False
    for face, row in zip(faces, lineage):
        ordinal, weights = row['source_triangle'], row['barycentric']
        if (type(ordinal) is not int or not 0 <= ordinal < len(source) or len(weights) != 3):
            return False
        for actual, bary in zip(face, weights):
            if (not finite_numbers(bary) or len(bary) != 3 or
                    abs(sum(bary)-1) > 1e-7 or min(bary) < -1e-7 or max(bary) > 1+1e-7):
                return False
            p = [sum(bary[j]*source[ordinal][j][k] for j in range(3)) for k in range(3)]
            if any(abs(a-b) > 1e-6 for a, b in zip(actual, transform(p))):
                return False
    return True


def role_metrics(rows):
    points, faces, normals, projections = [], [], set(), []
    surface_area = horizontal_area = vertical_area = 0.0
    for row in rows:
        for tri in triangles(row['vertices']):
            a, b, c = tri
            face = [-x for x in cross([b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)])]
            area2 = norm(face)
            if area2 <= 1e-10:
                continue
            n = [x/area2 for x in face]
            surface_area += area2/2
            horizontal_area += area2/2*abs(n[1])
            vertical_area += area2/2*(1-abs(n[1]))
            if n[1] > .02:
                normals.add(tuple(round(x, 2) for x in n))
            points.extend(tri); faces.append(tri); projections.append(projected(tri))
    if not points:
        return {'area_m2': 0.0, 'horizontal_area_m2': 0.0, 'vertical_area_m2': 0.0,
                'y_span_m': 0.0, 'xz_span_m': 0.0, 'y_levels': 0,
                'upward_normal_directions': 0, 'triangles': 0, 'projected_area_m2': 0.0}
    spans = [max(p[k] for p in points)-min(p[k] for p in points) for k in range(3)]
    return {'area_m2': surface_area, 'horizontal_area_m2': horizontal_area,
            'vertical_area_m2': vertical_area, 'y_span_m': spans[1],
            'xz_span_m': max(spans[0], spans[2]),
            'y_levels': len({round(p[1], 3) for p in points}),
            'upward_normal_directions': len(normals), 'triangles': len(faces),
            'projected_area_m2': unary_union(projections).area}


def separated_patches(rows):
    """Connected triangle patches, so a role name alone cannot prove rhythm."""
    parent, keys, points = [], {}, []
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for row in rows:
        for tri in triangles(row['vertices']):
            i = len(parent); parent.append(i); points.append(tri)
            for p in tri:
                key = tuple(round(v, 3) for v in p)
                if key in keys:
                    parent[find(i)] = find(keys[key])
                keys[key] = i
    groups = defaultdict(list)
    for i, tri in enumerate(points):
        groups[find(i)].extend(tri)
    result = []
    for vertices in groups.values():
        low = [min(p[k] for p in vertices) for k in range(3)]
        high = [max(p[k] for p in vertices) for k in range(3)]
        if high[1]-low[1] > .3:
            result.append([(a+b)/2 for a, b in zip(low, high)])
    return result


def facade_curve_metrics(rows, footprint, bottom, top):
    """Measure actual front profiles; a flat or tilted box has zero residual.

    Derive the long axis from the retained footprint rather than producer
    metadata. At three positions across it, cut the observed glass triangles
    by a vertical plane, then read the outer south-facing depth at seven
    heights. Nonlinearity relative to the first/last depth rejects a single
    sloping plane even when the mesh happens to have many triangles/normals.
    This tests a faceted front curve, not surveyed architectural fidelity.
    """
    rectangle = list(footprint.minimum_rotated_rectangle.exterior.coords)
    edge = max(([b[0]-a[0], b[1]-a[1]] for a, b in zip(rectangle, rectangle[1:])), key=norm)
    u = [x/norm(edge) for x in edge]
    v = [-u[1], u[0]]
    if v[1] < 0:
        v = [-x for x in v]
    along = [p[0]*u[0]+p[1]*u[1] for p in rectangle]
    low, high = min(along), max(along)
    heights = [bottom+(top-bottom)*fraction for fraction in (.18, .30, .42, .54, .66, .78, .90)]
    profiles = []
    for fraction in (.35, .50, .65):
        cut = low+(high-low)*fraction
        segments = []
        for row in rows:
            for tri in triangles(row['vertices']):
                distances = [p[0]*u[0]+p[2]*u[1]-cut for p in tri]
                if all(abs(d) < 1e-7 for d in distances):
                    segments.extend(zip(tri, tri[1:]+tri[:1])); continue
                points = []
                for index, (a, b) in enumerate(zip(tri, tri[1:]+tri[:1])):
                    da, db = distances[index], distances[(index+1) % 3]
                    if abs(da) < 1e-7:
                        points.append(a)
                    if da*db < 0:
                        t = da/(da-db)
                        points.append([a[k]+t*(b[k]-a[k]) for k in range(3)])
                unique = {tuple(round(x, 8) for x in p): p for p in points}
                if len(unique) >= 2:
                    ps = list(unique.values())
                    segments.append(max(((a, b) for a in ps for b in ps), key=lambda pair: math.dist(*pair)))
        depths = []
        for y in heights:
            candidates = []
            for a, b in segments:
                if abs(b[1]-a[1]) < 1e-8:
                    if abs(a[1]-y) < 1e-7:
                        candidates.extend(p[0]*v[0]+p[2]*v[1] for p in (a, b))
                elif min(a[1], b[1])-1e-7 <= y <= max(a[1], b[1])+1e-7:
                    t = (y-a[1])/(b[1]-a[1])
                    candidates.append((a[0]+t*(b[0]-a[0]))*v[0]+(a[2]+t*(b[2]-a[2]))*v[1])
            if not candidates:
                break
            depths.append(max(candidates))
        if len(depths) != len(heights):
            profiles.append({'long_axis_fraction': fraction, 'complete': False}); continue
        residual = max(abs(d-(depths[0]+(depths[-1]-depths[0])*(y-heights[0])/(heights[-1]-heights[0])))
                       for y, d in zip(heights, depths))
        slopes = [(b-a)/(yb-ya) for a, b, ya, yb in zip(depths, depths[1:], heights, heights[1:])]
        profiles.append({'long_axis_fraction': fraction, 'complete': True,
                         'sample_y_m': heights, 'front_depth_m': depths,
                         'depth_range_m': max(depths)-min(depths),
                         'nonlinear_residual_m': residual,
                         'distinct_section_slopes': len({round(x, 2) for x in slopes})})
    minimum_depth = max(.5, .02*(top-bottom))
    minimum_residual = max(.25, .01*(top-bottom))
    qualifying = sum(p.get('complete') and p['depth_range_m'] > minimum_depth and
                     p['nonlinear_residual_m'] > minimum_residual and
                     p['distinct_section_slopes'] >= 3 for p in profiles)
    return {'qualifying_profiles': qualifying, 'profiles': profiles,
            'minimum_depth_range_m': minimum_depth,
            'minimum_nonlinear_residual_m': minimum_residual}


def audit(record, bundle, spec, w01):
    """Return passed/checks/summaries from actual L03 MeshInstance observations."""
    checks, summaries = [], []
    def ck(name, passed, details=None):
        checks.append({'name': name, 'passed': bool(passed),
                       **({'details': details} if details is not None else {})})
    try:
        items = bundle['landmarks']; by = {r['id']: r for r in items}
        refs = [r for r in spec['landmarks'] if r['phase'] == 'L03']
        references = {r['id']: r for r in refs}
        rows = record['components']; actual = {r['id']: r for r in rows}
        entries = [(item['id'], c) for item in items for c in item['components']]
        generated = {c['id']: (id, c) for id, c in entries}
        ck('scope.four_unique_source_bound_city_landmarks', bundle.get('schema_version') == 1 and
           bundle.get('task') == 'L03' and len(items) == len(by) == len(refs) == len(references) == 4 and
           set(by) == set(references) == set(TARGETS) and
           all(by[id]['feature_id'] == fid for id, fid in TARGETS.items()))
        ck('scope.no_new_colliders_or_permissions', record.get('collision_objects') == 0 and
           all(r.get('collision_generated') is False and r.get('runtime_permission') is None for r in items) and
           all(type(bundle['counts'][key]) is int and bundle['counts'][key] == 0
               for key in ('new_collision_bodies', 'new_routes')))
        ck('engine.loaded_visible_overlay', record.get('loaded') is True and record.get('visible') is True and
           bool(re.fullmatch('[a-f0-9]{64}', record.get('bundle_sha256', ''))))
        ck('engine.unique_complete_component_inventory', len(rows) == len(actual) == len(entries) == len(generated) and
           set(actual) == set(generated) and bool(entries))
        ck('materials.finite_rgb_palette', bool(bundle['palette']) and all(
           finite_numbers(rgb) and len(rgb) == 3 and all(0 <= x <= 1 for x in rgb)
           for rgb in bundle['palette'].values()))

        world = json.loads((ROOT/'game/resources/world_geometry/world.json').read_text())
        palace = json.loads((ROOT/'game/data/generated/palace_landmarks.json').read_text())
        world_ids = {m['id'] for m in world['meshes']}
        palace_refs = [r for r in spec['landmarks'] if r['phase'] == 'L02']
        palace_parts = {p for r in palace_refs for p in r['spatial_binding']['height_component_ids']}
        palace_hidden = {r['spatial_binding']['current_visual_mesh_id'] for r in palace_refs}
        palace_hidden.update(m['id'] for m in world['meshes'] if m.get('metadata', {}).get('feature_id') in palace_parts)
        ck('dependencies.current_L02_hidden_inventory_retained', palace.get('task') == 'L02' and
           set(palace['hidden_mesh_ids']) == palace_hidden and len(palace['hidden_mesh_ids']) == len(palace_hidden) and
           palace['hidden_fragment_ids'] == FRAGMENTS)
        city_hidden = {r['spatial_binding']['current_visual_mesh_id'] for r in refs}
        ck('engine.only_replaced_source_meshes_hidden', len(city_hidden) == 4 and
           set(bundle['hidden_mesh_ids']) == city_hidden and len(bundle['hidden_mesh_ids']) == 4 and
           set(record['hidden_sources']) == city_hidden and
           all(v is False for v in record['hidden_sources'].values()))
        ck('engine.no_additional_fragment_hiding', bundle.get('hidden_fragment_ids', []) == [] and record['hidden_fragments'] == {})
        hidden = city_hidden | palace_hidden | set(w01['disabled_source_ids'])
        sources = record['all_source_visibility']
        ck('engine.all_source_mesh_visibility_exact', bool(world_ids) and set(sources) == world_ids and all(
           sources[id] is (id not in hidden) for id in world_ids),
           {'expected_total': len(world_ids), 'expected_hidden': sorted(hidden)})
        fragment_ids = {r['id'] for r in w01['fragments']} | {'W02_support', 'W03_support'}
        disabled_fragments = set(palace['hidden_fragment_ids']) | {'W01_support', 'W02_support'}
        fragments = record['all_fragment_visibility']
        ck('engine.all_L02_fragment_visibility_exact', set(fragments) == fragment_ids and all(
           fragments[id] is (id not in disabled_fragments) for id in fragment_ids),
           {'expected_total': len(fragment_ids), 'expected_hidden': sorted(disabled_fragments)})

        source_triangles, source_transform = reuse_geometry(bundle)
        ck('reuse.actual_external_GLB_source_and_transform_parseable', len(source_triangles) == 1292)
        for id, item in by.items():
            prefix = id+'.'; binding = references[id]['spatial_binding']
            footprint = shape(binding['geometry']); allowed = footprint.buffer(ENGINE_TOLERANCE_M)
            ck(prefix+'exact_L01_spatial_and_height_binding', item['source_binding'] == binding)
            ck(prefix+'nonempty_unique_source_components', bool(item['components']) and
               len({c['id'] for c in item['components']}) == len(item['components']))
            valid, arrays, surfaces, containment, envelope, bad_normals, collapsed = [], [], [], [], [], [], []
            live, live_by_role = [], defaultdict(list)
            lineage = []
            for source in item['components']:
                cid = source['id']; observed = actual.get(cid, {})
                verts, normals = observed.get('vertices'), observed.get('normals')
                okay = (finite_numbers(verts) and finite_numbers(normals) and len(verts) >= 9 and
                        len(verts) % 9 == 0 and len(verts) == len(normals))
                valid.append(okay)
                arrays.append(okay and float32_equal(verts, source.get('vertices')) and
                              packed_normals_equal(normals, source.get('normals')))
                role = source.get('feature_role')
                semantic_role = canonical_role(id, role)
                surfaces.append(observed.get('identity') is True and observed.get('visible') is True and
                                observed.get('landmark_id') == id and semantic_role in ALLOWED_ROLES[id] and
                                observed.get('feature_role') == role and observed.get('primitive') == 3 and
                                observed.get('cull_mode') == 0 and float32_equal(observed.get('material_rgb'),
                                bundle['palette'][source['material']]))
                if not okay:
                    continue
                live.append(observed); live_by_role[semantic_role].append(observed)
                low, high = min(verts[1::3]), max(verts[1::3])
                bottom = binding['current_bottom_y_m']
                top = binding['current_top_y_m']
                # A land surface has no vertical extrusion authority: top=null
                # means the original flat surface, never an unbounded column.
                if top is None:
                    top = bottom
                if low < bottom-ENGINE_TOLERANCE_M or high > top+ENGINE_TOLERANCE_M:
                    envelope.append(cid)
                if role == 'reused_model':
                    lineage.append(id == 'sfc' and lineage_matches(source, source_triangles, source_transform))
                for n, tri in enumerate(triangles(verts)):
                    if not allowed.covers(projected(tri)):
                        containment.append([cid, n])
                    a, b, c = tri
                    face = [-x for x in cross([b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)])]
                    area2 = norm(face)
                    if area2 < 1e-10:
                        collapsed.append([cid, n]); continue
                    ns = normals[n*9:n*9+9]
                    if any(abs(norm(ns[j:j+3])-1) > .00001 or
                           sum(face[k]*ns[j+k] for k in range(3))/area2 < .99 for j in (0, 3, 6)):
                        bad_normals.append([cid, n])
            ck(prefix+'actual_finite_triangle_arrays', bool(valid) and all(valid))
            ck(prefix+'actual_float32_arrays_match_bundle', bool(arrays) and all(arrays),
               {'vertices': 'source float32; tolerance 1e-9 m',
                'normals': 'independent octahedral uint16x2 float32 round trip; tolerance 1e-9'})
            ck(prefix+'actual_visible_identity_material_and_front_culling', bool(surfaces) and all(surfaces))
            ck(prefix+'full_projected_triangles_inside_original_footprint', not containment,
               {'offenders': containment[:12], 'tolerance_m': ENGINE_TOLERANCE_M})
            ck(prefix+'actual_vertical_envelope_preserved', not envelope,
               {'offenders': envelope[:12], 'flat_source_if_top_null': binding['current_top_y_m'] is None})
            ck(prefix+'clockwise_faces_and_unit_consistent_normals', bool(live) and not bad_normals and not collapsed,
               {'bad_normals': bad_normals[:12], 'collapsed_faces': collapsed[:12]})
            metrics = {role: role_metrics(rs) for role, rs in live_by_role.items()}
            ck(prefix+'required_roles_have_positive_geometry', REQUIRED_ROLES[id] <= set(metrics) and
               all(metrics.get(role, {}).get('area_m2', 0) > .1 for role in REQUIRED_ROLES[id]))
            extent = max(footprint.bounds[2]-footprint.bounds[0], footprint.bounds[3]-footprint.bounds[1])
            height = (binding['current_top_y_m'] or binding['current_bottom_y_m'])-binding['current_bottom_y_m']
            if id == 'city_hall':
                roof, glass, frame = [metrics.get(role, {}) for role in ('curved_roof', 'glass', 'frame')]
                curve = facade_curve_metrics(live_by_role['glass'], footprint,
                                             binding['current_bottom_y_m'], binding['current_top_y_m'])
                ck(prefix+'geometric_faceted_curve_and_long_roofline', roof.get('horizontal_area_m2', 0) > 50 and
                   roof.get('xz_span_m', 0) > .5*extent and roof.get('y_span_m', 0) > .25 and
                   roof.get('y_levels', 0) >= 3 and glass.get('upward_normal_directions', 0) >= 3 and
                   curve['qualifying_profiles'] >= 2,
                   {'roof': roof, 'glass_upward_normal_directions': glass.get('upward_normal_directions', 0),
                    'glass_front_curve': curve,
                    'meaning': 'Long retained roof/eave plus nonlinear glass-front depth; roof curvature is not required'})
                ck(prefix+'broad_glass_and_spread_frame_geometry', glass.get('vertical_area_m2', 0) > 100 and
                   glass.get('y_span_m', 0) > .25*height and glass.get('xz_span_m', 0) > .4*extent and
                   frame.get('area_m2', 0) > 5 and frame.get('xz_span_m', 0) > .25*extent and
                   frame.get('y_levels', 0) >= 3, {'glass': glass, 'frame': frame})
            elif id == 'library':
                stone, window, central = [metrics.get(role, {}) for role in ('stone', 'window', 'central_facade')]
                patches = separated_patches(live_by_role['window'])
                patch_span = max((max(p[k] for p in patches)-min(p[k] for p in patches) for k in (0, 2)), default=0) if patches else 0
                ck(prefix+'low_stone_mass_and_actual_vertical_window_rhythm', stone.get('area_m2', 0) > 50 and
                   stone.get('y_span_m', 0) > .4*height and window.get('vertical_area_m2', 0) > 10 and
                   window.get('y_span_m', 0) > .25*height and len(patches) >= 4 and patch_span > .25*extent,
                   {'stone': stone, 'window': window, 'separated_window_patches': len(patches), 'patch_span_m': patch_span})
                rectangle = list(footprint.minimum_rotated_rectangle.exterior.coords)
                edge = max(([b[0]-a[0], b[1]-a[1]] for a, b in zip(rectangle, rectangle[1:])), key=norm)
                axis = [x/norm(edge) for x in edge]
                fp_along = [p[0]*axis[0]+p[1]*axis[1] for p in rectangle]
                central_along = [p[0]*axis[0]+p[2]*axis[1] for row in live_by_role['central_facade'] for tri in triangles(row['vertices']) for p in tri]
                central_span = max(central_along)-min(central_along) if central_along else 0
                centre_error = abs((max(central_along)+min(central_along)-max(fp_along)-min(fp_along))/2) if central_along else math.inf
                ck(prefix+'geometric_emphasized_central_facade', central.get('vertical_area_m2', 0) > 5 and
                   central.get('y_span_m', 0) > .25*height and .05*norm(edge) < central_span < .65*norm(edge) and
                   centre_error < .2*norm(edge), {'central': central, 'long_axis_span_m': central_span, 'centre_error_m': centre_error})
            elif id == 'plaza':
                grass, paving = [metrics.get(role, {}) for role in ('grass', 'paving')]
                union = unary_union([projected(tri) for row in live for tri in triangles(row['vertices'])])
                ck(prefix+'actual_grass_and_paving_cover_original_outline',
                   grass.get('projected_area_m2', 0) > .05*footprint.area and
                   paving.get('projected_area_m2', 0) > .01*footprint.area and
                   footprint.symmetric_difference(union).area < .005*footprint.area,
                   {'grass': grass, 'paving': paving, 'outline_difference_m2': footprint.symmetric_difference(union).area})
            elif id == 'sfc':
                reused = metrics.get('reused_model', {})
                ck(prefix+'actual_external_model_triangle_lineage', bool(lineage) and all(lineage),
                   {'source': REUSE_SOURCE, 'source_triangles': len(source_triangles), 'tolerance_m': 1e-6,
                    'meaning': 'Every clipped vertex reconstructed from an original external GLB triangle'})
                ck(prefix+'tall_nontrivial_reused_geometry', reused.get('triangles', 0) >= 100 and
                   reused.get('area_m2', 0) > 50 and reused.get('y_span_m', 0) > .8*height and
                   reused.get('xz_span_m', 0) > .25*extent, reused)
            if id != 'sfc':
                roles = REQUIRED_ROLES[id]
                colours = {role: {tuple(bundle['palette'][c['material']]) for c in item['components'] if canonical_role(id, c['feature_role']) == role} for role in roles}
                ck(prefix+'required_material_roles_have_actual_colour_contrast', len(set().union(*colours.values())) >= 2, {k: sorted(v) for k, v in colours.items()})
            summaries.append({'id': id, 'components': len(live),
                              'triangles': sum(len(r['vertices'])//9 for r in live),
                              'roles': dict(Counter(r['feature_role'] for r in live)), 'geometry': metrics})
        totals = {'landmarks': 4, 'components': len(actual),
                  'triangles': sum(len(r.get('vertices', []))//9 for r in rows)}
        ck('counts.actual_geometry_matches_declared_counts', all(bundle['counts'].get(k, v) == v for k, v in totals.items()), totals)
    except (KeyError, TypeError, ValueError, IndexError, OverflowError, ZeroDivisionError,
            AttributeError, OSError, struct.error) as error:
        ck('observation.complete_parseable_contract', False, str(error))
    return {'task': 'L03', 'passed': bool(checks) and all(c['passed'] for c in checks),
            'checks': checks, 'summaries': summaries,
            'scope': 'Actual visible arrays/materials, full source-volume containment, numerical feature presence, '
                     'and external-model triangle lineage. Geometric feature thresholds are development diagnostics, '
                     'not human landmark recognition or surveyed exterior accuracy. Byte-hash binding of executed '
                     'files, unchanged collision bodies/routes, continuous walking/camera, rendered visibility, '
                     'human handling, performance and M4 require separate evidence.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('record', type=Path)
    parser.add_argument('--bundle', type=Path, default=ROOT/'game/data/generated/city_landmarks.json')
    parser.add_argument('--spec', type=Path, default=ROOT/'data/processed/landmark_spec.json')
    parser.add_argument('--gate', type=Path, default=ROOT/'game/data/generated/daehanmun.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    read = lambda p: json.loads(p.read_text())
    result = audit(read(args.record), read(args.bundle), read(args.spec), read(args.gate))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print('L03 actual exterior', result['passed'], 'checks', len(result['checks']))
    if not result['passed']:
        print([c for c in result['checks'] if not c['passed']])
    raise SystemExit(0 if result['passed'] else 1)

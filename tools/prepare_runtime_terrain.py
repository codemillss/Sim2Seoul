#!/usr/bin/env python3
"""EXP21: deterministic local terrain from retained official contours and spots.

No source elevations, source geometry or existing world document are modified.
The sampled surface and inferred building pads are game reconstruction, not a
surveyed DEM. Requires the existing numpy/Shapely data environment, no SciPy.
"""
import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import shapely
from shapely.geometry import LineString, MultiPoint, Point, Polygon, box, mapping, shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'data/raw/supplemental/seoul_terrain/20261018/terrain_source_controls_local.json'
OUTPUT = 'game/assets/authored/terrain_heightfield.json'
REPORT = 'data/reports/terrain_integration/20261018/source_quality.json'
INPUTS = [SOURCE, 'config/region.json', 'data/processed/features.json',
          'game/resources/world_geometry/world.json']
CELL = 5.0
DOMAIN = (-540., -540., 540., 540.)
PLATEAU_MARGIN = .6
MIN_BLEND = 8.


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()


def rounded(value, digits=6):
    if isinstance(value, dict):
        return {k: rounded(v, digits) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [rounded(v, digits) for v in value]
    if isinstance(value, (float, np.floating)):
        return round(float(value), digits)
    return value


class Tin:
    """Indexed Delaunay triangles with affine barycentric interpolation.

    Contours are densified to at most 5m while retaining every original bend.
    Delaunay is deliberately *not* called constrained: equal-height contours can
    cross triangle edges; independent mid-segment residuals expose that limit.
    """
    def __init__(self, controls):
        vertices = {}
        duplicate_count = 0
        for x, z, height in controls:
            key = (round(float(x), 7), round(float(z), 7))
            if key in vertices:
                if abs(vertices[key] - height) > 1e-6:
                    raise ValueError(f'Conflicting coincident source heights: {key}')
                duplicate_count += 1
            vertices[key] = float(height)
        keys = sorted(vertices)
        self.points = np.array(keys, dtype=float)
        self.heights = np.array([vertices[k] for k in keys], dtype=float)
        self.duplicate_count = duplicate_count
        self.hull = MultiPoint(keys).convex_hull
        triangles = list(shapely.delaunay_triangles(MultiPoint(keys)).geoms)
        triangles.sort(key=lambda t: tuple(sorted(t.exterior.coords)[:3]))
        self.triangles = triangles
        self.index = STRtree(triangles)
        self.xy = np.array([list(t.exterior.coords)[:3] for t in triangles])
        self.y = np.array([[vertices[(round(x, 7), round(z, 7))] for x, z in list(t.exterior.coords)[:3]]
                           for t in triangles])
        self.edge1 = self.xy[:, 1] - self.xy[:, 0]
        self.edge2 = self.xy[:, 2] - self.xy[:, 0]
        self.det = self.edge1[:, 0] * self.edge2[:, 1] - self.edge1[:, 1] * self.edge2[:, 0]
        if np.any(np.abs(self.det) < 1e-12):
            raise ValueError('Degenerate TIN triangle')

    def sample(self, points):
        points = np.asarray(points, dtype=float).reshape((-1, 2))
        selected = np.full(len(points), len(self.triangles), dtype=int)
        matches = self.index.query(shapely.points(points), predicate='intersects')
        if matches.shape[1]:
            np.minimum.at(selected, matches[0], matches[1])
        if np.any(selected == len(self.triangles)):
            missing = points[selected == len(self.triangles)]
            raise ValueError(f'Height query outside retained source convex hull: {missing[:3].tolist()}')
        a = points - self.xy[selected, 0]
        e1, e2, det = self.edge1[selected], self.edge2[selected], self.det[selected]
        b = (a[:, 0] * e2[:, 1] - a[:, 1] * e2[:, 0]) / det
        c = (e1[:, 0] * a[:, 1] - e1[:, 1] * a[:, 0]) / det
        h = self.y[selected]
        return h[:, 0] + b * (h[:, 1] - h[:, 0]) + c * (h[:, 2] - h[:, 0])


class SourceSurface:
    """Continuous inverse-square distance from whole original observations.

    A contour contributes once as a complete retained polyline, not thousands
    of highly correlated vertices. Every map spot contributes once. Distances
    are 2D projected metres; exact observations have an explicit limiting value.
    The original hull remains a hard domain constraint. No invented controls,
    vertical offsets, source deletion or extrapolation are used.
    """
    def __init__(self, source, held_spots=()):
        held_spots = set(held_spots)
        self.observations = [LineString(r['line_xz_m']) for r in source['layers']['contours']]
        self.heights = [r['height_m'] for r in source['layers']['contours']]
        vertices = [p for r in source['layers']['contours'] for p in r['line_xz_m']]
        for row in source['layers']['spot_heights']:
            if row['id'] not in held_spots:
                self.observations.append(Point(row['point_xz_m']))
                self.heights.append(row['height_m'])
                vertices.append(row['point_xz_m'])
        self.heights = np.asarray(self.heights, dtype=float)
        self.hull = MultiPoint(vertices).convex_hull

    def sample(self, points):
        points = np.asarray(points, dtype=float).reshape((-1, 2))
        geometries = shapely.points(points)
        if not np.all(shapely.covers(self.hull.buffer(1e-8), geometries)):
            raise ValueError('Height query outside retained source convex hull')
        result = np.empty(len(points))
        for start in range(0, len(points), 8192):
            end = min(start+8192, len(points))
            distances = np.array([shapely.distance(geometries[start:end], g) for g in self.observations])
            exact = distances <= 1e-7
            for i in np.flatnonzero(exact.any(axis=0)):
                if np.ptp(self.heights[exact[:, i]]) > 1e-5:
                    raise ValueError('Conflicting exact source observations')
            distances = np.maximum(distances, 1e-8)
            weights = (distances.min(axis=0)[None, :]/distances)**2
            result[start:end] = np.sum(weights*self.heights[:, None], axis=0)/weights.sum(axis=0)
            for i in np.flatnonzero(exact.any(axis=0)):
                result[start+i] = self.heights[np.flatnonzero(exact[:, i])[0]]
        return result


def control_rows(source, held_spots=()):
    controls = []
    held_spots = set(held_spots)
    for row in source['layers']['contours']:
        for x, z in shapely.segmentize(LineString(row['line_xz_m']), 5.).coords:
            controls.append((x, z, row['height_m']))
    for row in source['layers']['spot_heights']:
        if row['id'] not in held_spots:
            controls.append((*row['point_xz_m'], row['height_m']))
    return controls


def metrics(errors):
    values = np.asarray(errors, dtype=float)
    return {'count': len(values), 'mae_m': float(np.mean(np.abs(values))),
            'rmse_m': float(np.sqrt(np.mean(values ** 2))),
            'absolute_p95_m': float(np.quantile(np.abs(values), .95)),
            'absolute_max_m': float(np.max(np.abs(values))),
            'signed_min_m': float(values.min()), 'signed_max_m': float(values.max())}


def sample_boundary(geometry, spacing=2.):
    points = []
    for polygon in [geometry] if geometry.geom_type == 'Polygon' else geometry.geoms:
        for ring in [polygon.exterior, *polygon.interiors]:
            for x, z in shapely.segmentize(LineString(ring.coords), spacing).coords:
                points.append((x, z))
    return points


def polygonal(geometry):
    if geometry.geom_type in ('Polygon', 'MultiPolygon'):
        return geometry
    if hasattr(geometry, 'geoms'):
        items = [polygonal(g) for g in geometry.geoms if not g.is_empty and
                 (g.geom_type in ('Polygon', 'MultiPolygon', 'GeometryCollection'))]
        return shapely.union_all(items)
    return Polygon()


def foundations(world, features, tin, zero):
    """Join intersecting/touching source bodies, not unrelated expanded pads.

    An inferred constant base is sampled at the original union centroid. Whole
    source height/min-height spans remain the responsibility of rigid runtime
    building translation. Pad margins that overlap are blended in the grid and
    reported, rather than silently flattening an entire city block.
    """
    rows = [r for r in world['meshes'] if r['role'] == 'Buildings']
    rows.sort(key=lambda r: r['id'])
    geometries = [shape(features[r['id']]['geometry']) for r in rows]
    if any(not g.is_valid or g.is_empty for g in geometries):
        raise ValueError('Invalid source building polygon; no implicit repair')
    parents = list(range(len(rows)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    index = STRtree(geometries)
    for i, geometry in enumerate(geometries):
        for j in index.query(geometry, predicate='intersects'):
            if j > i:
                a, b = find(i), find(j)
                parents[max(a, b)] = min(a, b)
    groups = defaultdict(list)
    for i in range(len(rows)):
        groups[find(i)].append(i)
    records = []
    for members in groups.values():
        geometry = shapely.union_all([geometries[i] for i in members])
        centroid = geometry.centroid
        anchor = [centroid.x, centroid.y]
        base_absolute = float(tin.sample([anchor])[0])
        boundary = sample_boundary(geometry)
        heights = tin.sample(boundary)
        deviation = float(np.max(np.abs(heights - base_absolute)))
        # This is a blend-distance rule, not a claim that the final combined
        # terrain is universally <=16% grade. The report audits final gradients.
        blend = max(MIN_BLEND, deviation / .12)
        ids = [rows[i]['id'] for i in members]
        records.append({'id': ids[0], 'source_ids': ids, 'anchor_xz_m': anchor,
                        'base_y_m': base_absolute - zero,
                        'base_source_height_m': base_absolute,
                        'base_height_kind': 'inferred_constant_selected_surface_at_source_union_centroid',
                        'geometry': mapping(geometry),
                        'plateau_margin_m': PLATEAU_MARGIN, 'blend_m': blend,
                        'source_boundary_range_m': [float(heights.min()), float(heights.max())],
                        'max_source_boundary_adjustment_m': deviation,
                        'source_geometry_preserved': True})
    records.sort(key=lambda r: r['id'])
    # Extra aprons must never meet another rigid base at an artificial seam.
    # Remove the *entire* extra apron from both members of any close pair.
    # Existing source cores stay untouched; inaccessible gaps narrower than
    # 0.5m between real separate source outlines are explicitly reported.
    cores = [shape(r['geometry']) for r in records]
    core_index = STRtree(cores)
    keep_clearance = 2.*PLATEAU_MARGIN+.5
    for i, record in enumerate(records):
        core = cores[i]
        close = [j for j in core_index.query(core.buffer(keep_clearance), predicate='intersects')
                 if j != i and core.distance(cores[j]) < keep_clearance]
        margin = 0. if close else PLATEAU_MARGIN
        plateau = core if margin == 0. else core.buffer(margin, quad_segs=2)
        plateau = shapely.set_precision(polygonal(plateau), 1e-6, mode='valid_output')
        record['plateau_geometry'] = mapping(plateau)
        record['plateau_margin_m'] = margin
        record['plateau_partition'] = 'Actual core preserved; entire extra apron omitted if any other source core is closer than1.7m, leaving at least0.5m between artificial aprons'
        record['apron_omitted_near_other_core'] = bool(close)
        record['minimum_artificial_apron_gap_m'] = .5
    return records


def pad_surface(points, raw_values, records):
    """Order-independent smooth blend; exact source overlap groups share a base.

    Only intersecting *source* footprints are grouped. Conflicting expanded pads
    use their continuous weighted mean, not ID/order precedence. Their residual
    to rigid building bases is measured explicitly for runtime support caps.
    """
    points = np.asarray(points, dtype=float)
    numerator = np.zeros(len(points))
    denominator = np.zeros(len(points))
    strongest = np.zeros(len(points))
    shapes = shapely.points(points)
    for record in records:
        geometry = shape(record['geometry'])
        left, bottom, right, top = geometry.bounds
        limit = record['plateau_margin_m'] + record['blend_m']
        keep = np.flatnonzero((points[:, 0] >= left-limit) & (points[:, 0] <= right+limit)
                             & (points[:, 1] >= bottom-limit) & (points[:, 1] <= top+limit))
        if not len(keep):
            continue
        distances = shapely.distance(shapes[keep], geometry)
        t = np.clip((distances - record['plateau_margin_m']) / record['blend_m'], 0., 1.)
        weight = 1. - t*t*(3.-2.*t)
        numerator[keep] += weight * record['base_y_m']
        denominator[keep] += weight
        strongest[keep] = np.maximum(strongest[keep], weight)
    result = np.array(raw_values, dtype=float)
    used = denominator > 1e-12
    result[used] = (1.-strongest[used]) * result[used] + strongest[used] * numerator[used] / denominator[used]
    return result


def grid_sample(points, values, cell=CELL):
    points = np.asarray(points, dtype=float)
    q = (points - np.array(DOMAIN[:2])) / cell
    w = values.shape[1]
    d = values.shape[0]
    if np.any(q < 0.) or np.any(q[:, 0] > w-1) or np.any(q[:, 1] > d-1):
        raise ValueError('Query outside runtime heightfield; no clamp/extrapolation')
    i = np.minimum(np.floor(q).astype(int), [w-2, d-2])
    frac = q-i
    x, z = i[:, 0], i[:, 1]
    u, v = frac[:, 0], frac[:, 1]
    return (1-v)*((1-u)*values[z, x]+u*values[z, x+1])+v*((1-u)*values[z+1, x]+u*values[z+1, x+1])


def generate(root=ROOT):
    inputs = {p: digest(root / p) for p in INPUTS}
    source, region, features_doc, world = [json.loads((root / p).read_text()) for p in INPUTS]
    for row in [*source['layers']['contours'], *source['layers']['spot_heights']]:
        if not math.isfinite(row['height_m']):
            raise ValueError('Nonfinite source height')
    features = {r['feature_id']: r for r in features_doc['features']}
    assert source['coordinate_system']['origin_lon_lat'] == region['origin_lon_lat']
    assert source['coordinate_system']['metric_crs'] == region['metric_crs']
    assert region['meters_per_world_unit'] == 1.
    controls = control_rows(source)
    tin = Tin(controls)
    surface = SourceSurface(source)
    exact_region = Polygon(source['region_polygon_xz_m'])
    assert exact_region.difference(tin.hull).area < 1e-8
    assert box(*DOMAIN).difference(tin.hull).area < 1e-8
    zero = float(surface.sample([[0., 0.]])[0])
    records = foundations(world, features, surface, zero)
    width = int(round((DOMAIN[2]-DOMAIN[0])/CELL))+1
    depth = int(round((DOMAIN[3]-DOMAIN[1])/CELL))+1
    xs = DOMAIN[0] + CELL*np.arange(width)
    zs = DOMAIN[1] + CELL*np.arange(depth)
    xx, zz = np.meshgrid(xs, zs)
    points = np.column_stack((xx.ravel(), zz.ravel()))
    raw = surface.sample(points)-zero
    final = pad_surface(points, raw, records)
    grid = np.around(final.reshape((depth, width)), 4)

    # Every spot is predicted once while absent from its fold's source input.
    spots = sorted(source['layers']['spot_heights'], key=lambda r: (*r['point_xz_m'], r['id']))
    cross_validation = []
    for fold in range(5):
        held = spots[fold::5]
        trial = SourceSurface(source, [r['id'] for r in held])
        predicted = trial.sample([r['point_xz_m'] for r in held])
        for row, prediction in zip(held, predicted):
            cross_validation.append({'id': row['id'], 'fold': fold,
                                     'height_m': row['height_m'], 'predicted_m': float(prediction),
                                     'error_m': float(prediction-row['height_m'])})
    cross_validation.sort(key=lambda r: r['id'])
    contour_points, contour_heights = [], []
    for row in source['layers']['contours']:
        line = LineString(row['line_xz_m'])
        for distance in np.arange(1.25, line.length, 2.5):
            p = line.interpolate(float(distance))
            contour_points.append((p.x, p.y))
            contour_heights.append(row['height_m'])
    contour_errors = surface.sample(contour_points) - np.array(contour_heights)
    rejected_tin_contour_errors = tin.sample(contour_points) - np.array(contour_heights)
    spot_exact_errors = surface.sample([r['point_xz_m'] for r in spots])-np.array([r['height_m'] for r in spots])
    nearest = STRtree([Point(x, z) for x, z in tin.points])
    nearest_ids = nearest.nearest(shapely.points(points))
    distances = np.linalg.norm(points-tin.points[nearest_ids], axis=1)
    gradients = np.hypot(*np.gradient(grid, CELL))
    raw_gradients = np.hypot(*np.gradient(raw.reshape((depth, width)), CELL))

    boundary_gaps, inside_errors = [], []
    for record in records:
        geometry = shape(record['geometry'])
        boundary = np.array(sample_boundary(geometry, 1.))
        keep = ((boundary[:, 0] >= DOMAIN[0]) & (boundary[:, 1] >= DOMAIN[1])
                & (boundary[:, 0] <= DOMAIN[2]) & (boundary[:, 1] <= DOMAIN[3]))
        gaps = grid_sample(boundary[keep], grid) - record['base_y_m']
        boundary_gaps.append({'id': record['id'], 'source_ids': record['source_ids'],
                              **metrics(gaps)})
        inside_errors.extend(gaps)
    source_building_polygons = [shape(features[r['id']]['geometry']) for r in world['meshes'] if r['role']=='Buildings']
    building_index = STRtree(source_building_polygons)
    spot_building_matches = building_index.query(shapely.points([r['point_xz_m'] for r in spots]), predicate='intersects')
    source_code_counts = {kind: dict(Counter(r['source_properties']['SCLS'] for r in rows))
                          for kind, rows in source['layers'].items()}
    geometry_shapes = [shape(r['geometry']) for r in records]
    pads = [g.buffer(PLATEAU_MARGIN) for g in geometry_shapes]
    pad_index = STRtree(pads)
    conflicts = []
    for i, pad in enumerate(pads):
        for j in pad_index.query(pad, predicate='intersects'):
            if j > i:
                area = pad.intersection(pads[j]).area
                if area > .001:
                    conflicts.append({'a': records[i]['id'], 'b': records[j]['id'],
                                      'area_m2': area, 'base_difference_m': abs(records[i]['base_y_m']-records[j]['base_y_m'])})
    plateau_shapes = [shape(r['plateau_geometry']) for r in records]
    plateau_index = STRtree(plateau_shapes)
    plateau_overlap_area = 0.
    for i, plateau in enumerate(plateau_shapes):
        for j in plateau_index.query(plateau, predicate='intersects'):
            if j > i:
                plateau_overlap_area += plateau.intersection(plateau_shapes[j]).area
    core_lost_area = sum(g.difference(plateau).area for g, plateau in zip(geometry_shapes, plateau_shapes))
    outside_surface_rejected, outside_grid_rejected, duplicate_conflict_rejected = False, False, False
    try:
        surface.sample([[100000., 100000.]])
    except ValueError:
        outside_surface_rejected = True
    try:
        grid_sample([[-541., 0.]], grid)
    except ValueError:
        outside_grid_rejected = True
    try:
        Tin([(0., 0., 1.), (0., 0., 2.)])
    except ValueError:
        duplicate_conflict_rejected = True
    grid_contract_error = abs(float(grid_sample([[-537.5, -537.5]], np.array([[0., 5.], [10., 15.]]))[0])-7.5)
    spot_structure_records = []
    for spot_index in sorted(set(spot_building_matches[0].tolist())):
        row = spots[spot_index]
        spot_structure_records.append({'id': row['id'], 'height_m': row['height_m'],
                                       'point_xz_m': row['point_xz_m'],
                                       'decision': 'Retained official map spot; current OSM footprint overlap is insufficient evidence to reclassify as rooftop or delete.'})
    checks = {'all_41_contours_96_spots_retained': len(source['layers']['contours']) == 41 and len(spots) == 96,
              'exact_region_and_runtime_rectangle_in_source_hull': exact_region.difference(tin.hull).area < 1e-8 and box(*DOMAIN).difference(tin.hull).area < 1e-8,
              'selected_source_contour_reproduction_max_1um': float(np.max(np.abs(contour_errors))) <= 1e-6,
              'selected_all_source_spots_reproduced': float(np.max(np.abs(spot_exact_errors))) <= 1e-6,
              'source_core_area_preserved_within_1um_serialization': core_lost_area < sum(g.length for g in geometry_shapes)*1e-6,
              'resolved_exact_plateaus_do_not_overlap_in_area': plateau_overlap_area < sum(g.length for g in geometry_shapes)*1e-6,
              'serialized_plateau_geometry_valid': all(shape(rounded(r['plateau_geometry'])).is_valid for r in records),
              'all_635_runtime_buildings_have_foundation': sum(len(r['source_ids']) for r in records) == 635,
              'grid_values_finite': bool(np.isfinite(grid).all()),
              'outside_source_hull_rejected': outside_surface_rejected,
              'outside_grid_rejected_without_clamp': outside_grid_rejected,
              'conflicting_exact_duplicate_rejected': duplicate_conflict_rejected,
              'known_bilinear_grid_contract': grid_contract_error < 1e-12}
    report = {
        'schema_version': 1, 'task': 'EXP21_SOURCE_AND_SURFACE_QUALITY',
        'scope': 'Software interpolation and inferred pad audit; not independent survey accuracy, gameplay, or terrain integration acceptance.',
        'inputs_sha256': inputs, 'generator_sha256': digest(Path(__file__)),
        'libraries': {'numpy': np.__version__, 'shapely': shapely.__version__},
        'source_counts': {k: len(v) for k, v in source['layers'].items()},
        'source_code_counts': source_code_counts,
        'source_codes_policy': 'Retain all advertised contour and map spot rows. F0017111 ordinary contour, F0017114 index contour, F0017121 depression ordinary contour, F0027217 spot. Depression contour retains its explicit HEIGHT; no arbitrary sign or vertical correction. Source pack has no road/bridge/tunnel/cut/water layer to classify such structures.',
        'source_code_reference': {'publisher': 'Korea Forest Service', 'title': '재해위험성검토의견서 실무매뉴얼', 'section': 'p33 table6 TIN source layers',
                                  'url': 'https://fgis.forest.go.kr/newkfsweb/cmm/fms/BoardFileDown.do?atchFileId=FILE_000000020062501&bbsId=BBSMSTR_1031&dwldHistYn=N&fileSn=1'},
        'spot_points_inside_source_building_footprints': len(set(spot_building_matches[0].tolist())),
        'spot_source_building_overlap_review': spot_structure_records,
        'structure_limitation': 'Map spot heights do not identify current OSM indoor floors or roof/road-deck structures. Current building overlap is reported, not evidence that a point is a roof. TIN does not create bridge/tunnel separation.',
        'duplicate_equal_height_vertices_collapsed': tin.duplicate_count,
        'conflicting_coincident_height_vertices': 0,
        'tin_controls': len(tin.points), 'tin_triangles': len(tin.triangles),
        'exact_region_outside_controls_hull_m2': exact_region.difference(tin.hull).area,
        'runtime_rectangle_outside_controls_hull_m2': box(*DOMAIN).difference(tin.hull).area,
        'nearest_source_vertex_distance_grid_m': {'max': float(distances.max()), 'p95': float(np.quantile(distances, .95)),
                                                'max_point_xz_m': points[int(np.argmax(distances))].tolist()},
        'spot_five_fold_held_out': {'method': 'Spatially sorted X,Z deterministic round-robin five folds; each of all96 spots excluded once. Nearby contour observations remain, so this tests interpolation consistency, not independent terrain truth.',
                                  **metrics([r['error_m'] for r in cross_validation]), 'observations': cross_validation},
        'contour_midsegment_reproduction': {'method': 'At1.25m then every2.5m station along every original contour, distinct from retained original/densified vertices.', **metrics(contour_errors)},
        'all_source_spot_reproduction': metrics(spot_exact_errors),
        'rejected_unconstrained_TIN_comparison': {'reason': 'Very close nonintersecting contours can cross Delaunay triangle edges. Large local contour residual rejected this surface for runtime; all source inputs were retained.', **metrics(rejected_tin_contour_errors)},
        'datum': {'source_height_at_fixed_origin_m': zero, 'absolute_vertical_datum': None,
                  'relative_zero_xz_m': [0., 0.], 'conversion': 'runtime y = interpolated source height - selected surface at fixed source origin; no geoid conversion'},
        'grid': {'cell_size_m': CELL, 'nodes': len(points), 'width': width, 'depth': depth,
                 'source_interpolated_y_range_m': [float(raw.min()), float(raw.max())],
                 'inferred_padded_y_range_m': [float(grid.min()), float(grid.max())],
                 'source_gradient_p95_p99_max': np.quantile(raw_gradients, [.95,.99,1.]).tolist(),
                 'padded_gradient_p95_p99_max': np.quantile(gradients, [.95,.99,1.]).tolist(),
                 'meaning': '5m sampling lattice of an interpolated surface, not a measured5m DEM or5m accuracy'},
        'foundation_count': len(records), 'rigid_source_buildings': sum(len(r['source_ids']) for r in records),
        'foundation_policy': 'Only actual intersecting/touching source polygons share an anchor. .6m margins do not group buildings. Extra aprons are omitted for all close source pairs; actual cores remain intact and artificial aprons have at least.5m transition gaps. Smoothstep weights are combined independently of record order. Rigid bodies/doors need base_y_m and native support caps where edge audit disagrees.',
        'expanded_pad_conflicts': rounded(conflicts),
        'resolved_plateaus': {'overlap_area_m2': plateau_overlap_area, 'lost_source_core_area_m2': core_lost_area, 'plateau_serialization_grid_m': 1e-6,
                              'types': dict(Counter(g.geom_type for g in plateau_shapes)), 'extra_aprons_omitted_near_other_core': sum(r['apron_omitted_near_other_core'] for r in records),
                              'max_rigid_anchor_vs_source_boundary_adjustment_m': max(r['max_source_boundary_adjustment_m'] for r in records)},
        'foundation_boundary_grid_deviation': {**metrics(inside_errors), 'per_foundation': rounded(boundary_gaps)},
        'checks': checks, 'passed': all(checks.values()),
        'limitations': ['Unknown original vertical datum; use only relative heights within this source pack.',
                       'No independent survey/surface truth; no measured curb, threshold or interior slab elevation.',
                       'Selected inverse-square line/spot distance interpolation is a reconstruction. The rejected unconstrained TIN comparison and sparse source regions are exposed in the report.',
                       'Foundation adjustments are inferred reconstruction. Nearby pads and bilinear cell edges can differ from rigid source building base; native support caps/skirt and door journeys must be verified separately.',
                       'Outside rectangle returns missing; no nearest-edge extrapolation or false citywide source coverage.',
                       'Existing authored museum3m hill must be replaced rather than added onto these source-relative heights.']}
    payload = {'schema_version': 1, 'task': 'EXP21_RUNTIME_RELATIVE_TERRAIN',
               'provenance': {'inputs_sha256': inputs, 'generator_sha256': digest(Path(__file__)),
                              'source_catalogue': 'https://data.seoul.go.kr/dataList/OA-22241/F/1/datasetView.do',
                              'license': 'KOGL Type1; original source2023, download2025-03-20; interpolation and inferred foundations bySim2Seoul'},
               'coordinate_system': {**source['coordinate_system'],
                                     'heights': 'Interpolated runtime relative Y metres; original source height_m retained separately in source pack',
                                     'vertical_assignment': 'relative to selected surface sampled at fixed technical origin; inferred foundations explicitly separate'},
               'datum': rounded(report['datum']),
               'domain_xz_m': list(DOMAIN), 'exact_region_polygon_xz_m': source['region_polygon_xz_m'],
               'outside_domain': 'missing; reject query; no clamp or extrapolation',
               'grid': {'origin_xz_m': list(DOMAIN[:2]), 'cell_size_m': CELL,
                        'width': width, 'depth': depth, 'ordering': 'row-major z then x; bilinear interpolation',
                        'values_y_m': grid.ravel().tolist()},
               'foundations': rounded(records),
               'classification': {'source': 'Official source height_m retained separately in source pack',
                                  'interpolation': 'Continuous inverse-square projected distance from each retained whole contour polyline and individual map spot; exact observations retained',
                                  'game_reconstruction': 'Constant building foundation anchors, .6m apron, adaptive smooth8m+ blend',
                                  'accuracy': 'Not a measured5m DEM; inspect source_quality.json for validation limits'}}
    return encode(payload), encode(rounded(report))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Regenerate in memory and compare committed source-conditioned artifacts')
    args = parser.parse_args()
    payload, report = generate()
    artifacts = [(OUTPUT, payload), (REPORT, report)]
    for relative, content in artifacts:
        path = ROOT / relative
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise SystemExit('STALE ' + relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    summary = json.loads(report)
    print(json.dumps({'passed': True, 'check_only': args.check,
                      'artifacts': {p: len(c) for p, c in artifacts},
                      'source_counts': summary['source_counts'],
                      'nodes': summary['grid']['nodes'], 'foundations': summary['foundation_count'],
                      'cv_rmse_m': summary['spot_five_fold_held_out']['rmse_m'],
                      'contour_abs_max_m': summary['contour_midsegment_reproduction']['absolute_max_m']}, ensure_ascii=False))


if __name__ == '__main__':
    main()

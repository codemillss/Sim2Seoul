#!/usr/bin/env python3
"""Independent EXP25 planar source/display checks; not rendered/native acceptance."""
import argparse
import hashlib
import json
from pathlib import Path

from shapely.geometry import LineString, Polygon, Point, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text())


def footprint(mesh):
    v = mesh['vertices']
    return unary_union([Polygon([(v[i], v[i + 2]), (v[i + 3], v[i + 5]),
                                 (v[i + 6], v[i + 8])]) for i in range(0, len(v), 9)])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        raise SystemExit('Refusing to overwrite existing road evidence')
    world = read('game/resources/world_geometry/world.json')
    plan = read('game/assets/authored/road_furniture.json')
    meshes = {row['id']: row for row in world['meshes']}
    drive = unary_union([footprint(row) for row in world['meshes'] if row['material'] == 'drive'])
    solids = unary_union([footprint(row) for row in world['meshes'] if row['material'] in
                          ['building', 'historic', 'civic', 'barrier']]).buffer(.25)
    private = shape(read('game/assets/authored/neighborhood_greenery.json')['private_polygons'])
    domain = drive.difference(solids.union(private))
    masks = {row['node_id']: row for row in plan['surface_masks']}
    before, after, changed_outside = [], [], []
    errors = []
    for row in world['meshes']:
        if row['material'] != 'walk':
            continue
        original = footprint(row)
        before.append(original.intersection(domain))
        if row['id'] in masks:
            entry = masks[row['id']]
            v = entry['retained_triangles_xz']
            displayed = unary_union([Polygon(v[i:i + 3]) for i in range(0, len(v), 3)])
            changed_outside.append(displayed.symmetric_difference(original.difference(domain)))
            if abs(entry['source_y_m'] - row['vertices'][1]) > 1e-8:
                errors.append(row['id'])
        else:
            displayed = original
        after.append(displayed.intersection(domain))
    before_area = unary_union(before).area
    after_area = unary_union(after).area
    outside_area = sum(g.area for g in changed_outside)
    invalid_paint = [row['id'] for row in plan['paint'] if not Polygon(row['xz']).is_valid]
    whites = unary_union([Polygon(row['xz']) for row in plan['paint'] if row['kind'] in ['lane', 'edge']])
    routes = read('game/data/generated/traffic.json')['routes'] + read('game/assets/authored/neighborhood_population.json')['vehicle_routes']
    route_rows = []
    for route in routes:
        overlap = whites.intersection(LineString(route['xz']).buffer(.91, cap_style=2)).area
        route_rows.append({'route_id': route['id'], 'white_line_body_overlap_m2': overlap})
    yellow = unary_union([Polygon(row['xz']) for row in plan['paint'] if row['color'] == 'yellow'])
    turn_gap = unary_union([Polygon(ring) for ring in plan.get("loop_turn_paint_openings",{}).get("mask_rings_xz",[])])
    south = []
    for z, x in [(150,51.23),(200,35.32),(250,19.45),(350,-11.55),(400,-28.12),(450,-45.04),(470,-53.73)]:
        section = yellow.intersection(LineString([(x-1,z),(x+1,z)]))
        parts = [section] if section.geom_type == 'LineString' and not section.is_empty else list(getattr(section,'geoms',[]))
        south.append({'z':z,'x':x,'stripe_count':len(parts),'expected_count':0 if turn_gap.contains(Point(x,z)) else 2,'widths_m':[part.length for part in parts]})
    turn_paint=unary_union([Polygon(row['xz']) for row in plan['paint'] if row['kind'] in ['lane','centre','paired_centre']])
    checks = [
        {'name':'game_loop_turns_clear_solid_lane_paint','passed':turn_paint.intersection(turn_gap).area<.001,'evidence':{'overlap_m2':turn_paint.intersection(turn_gap).area,'full_bus_samples':plan.get('loop_turn_paint_openings',{}).get('full_bus_box_samples',0),'game_permission_only':True}},
        {'name':'south_asymmetric_road_has_one_shared_double_yellow','passed':all(row['stripe_count']==row['expected_count'] and all(.13<w<.19 for w in row['widths_m']) for row in south),'evidence':{'source_sections':south,'intersection_gaps_expected':True}},
        {'name': 'retained_walk_has_no_valid_drive_render_overlap', 'passed': after_area < .0001,
         'evidence': {'before_m2': before_area, 'after_m2': after_area, 'source_walk_y_m': .055,
                      'source_drive_y_m': .035, 'paint_y_m': .052}},
        {'name': 'walk_outside_road_and_source_height_retained', 'passed': outside_area < .0001 and not errors,
         'evidence': {'symmetric_difference_m2': outside_area, 'wrong_height_nodes': errors}},
        {'name': 'all_paint_contours_are_valid', 'passed': not invalid_paint,
         'evidence': {'invalid': invalid_paint, 'polygons': len(plan['paint'])}},
        {'name': 'white_boundaries_clear_original_car_footprints',
         'passed': all(row['white_line_body_overlap_m2'] < .001 for row in route_rows), 'evidence': {'routes': route_rows}},
        {'name': 'unchanged_source_inputs', 'passed': all(hashlib.sha256((ROOT / 'game' / key.removeprefix('res://')).read_bytes()).hexdigest() == value
         for key, value in plan['source_hashes'].items()), 'evidence': {'inputs': plan['source_hashes']}},
        {'name': 'bounded_game_policies_explicit', 'passed': plan['policy']['authored_lane_cadence_m'] == 3.2 and
         plan['policy']['real_schedule'] is False and plan['policy']['source_geometry_changed'] is False,
         'evidence': {'lane_plans': [{'source_feature_id': row['source_feature_id'], 'source_lanes': row['source_lanes'],
                                    'lane_anchor_offset_m': row['lane_anchor_offset_m'], 'lane_centres_m': row['lane_centres_m']}
                                   for row in plan['corridors']]}}
    ]
    report = {'task': 'EXP25_ROAD_PLAN', 'result': 'PASS' if all(row['passed'] for row in checks) else 'FAIL',
              'checks': checks, 'scope': 'Independent Shapely source/display geometry; actual GPU appearance, source roadway surveying, and controller journeys are separate.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'result': report['result'], 'checks': len(checks), 'failed': [row['name'] for row in checks if not row['passed']],
                      'walk_before_m2': before_area, 'walk_after_m2': after_area, 'outside_change_m2': outside_area}, ensure_ascii=False))
    raise SystemExit(0 if report['result'] == 'PASS' else 1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Bind authored L01 exterior decisions to unchanged prepared spatial inputs.

Produces a local specification, never meshes, collision, permissions or a game scene.
Standard library only; no network access and no source-data reconstruction.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUTS = [
    'data/manual/landmark_plan.json', 'data/manual/landmark_references.json',
    'data/processed/features.json', 'data/processed/heights.json',
    'game/resources/world_geometry/world.json', 'config/region.json',
    'config/height_rules.json', 'config/data_usage.json',
    'data/manual/height_review_decisions.json',
    'game/data/generated/daehanmun.json', 'game/data/generated/public_walk.json',
    'game/data/generated/walkable_itinerary.json',
    'data/reports/walkable_milestone/snapshot.json', 'data/reports/w04_verification.json',
    'tools/prepare_landmark_spec.py',
]
OUTPUT = 'data/processed/landmark_spec.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(root, name):
    return json.loads((root / name).read_text())


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()


def build(root):
    plan, refs = (read(root, p) for p in INPUTS[:2])
    features = {x['feature_id']: x for x in read(root, 'data/processed/features.json')['features']}
    heights = {x['feature_id']: x for x in read(root, 'data/processed/heights.json')['records']}
    world = read(root, 'game/resources/world_geometry/world.json')
    meshes = {x['metadata']['feature_id']: x for x in world['meshes'] if x.get('metadata', {}).get('feature_id')}
    route = read(root, 'game/data/generated/walkable_itinerary.json')
    gate = read(root, 'game/data/generated/daehanmun.json')
    baseline = read(root, 'data/reports/walkable_milestone/snapshot.json')
    if plan['task'] != refs['task'] or plan['task'] != 'L01' or baseline['milestone_id'] != 'W0-engineering-walk-v1':
        raise ValueError('L01 authored inputs and completed W04 milestone required')
    # A new spec may not quietly change the spatial baseline it describes.
    for field, prefix in [('sources', 'game'), ('runtime_assets', 'game'), ('inputs', ''), ('proof', '')]:
        for name, digest in baseline[field].items():
            if Path(name).is_absolute() or sha(root / prefix / name) != digest:
                raise ValueError('W04 frozen spatial/proof input changed: ' + name)
    sources = {x['id']: x for x in refs['sources']}
    claims = {c['id']: {**c, 'source_id': s['id']} for s in refs['sources'] for c in s['claims']}
    items = []
    for choice in plan['landmarks']:
        fid = choice['feature_id']; f, h, mesh = features[fid], heights[fid], meshes[fid]
        if f['source_tags'].get('name') != choice['source_name']:
            raise ValueError('OSM identity differs: ' + fid)
        item = dict(choice)
        geometry = f['geometry']
        polys = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
        points = [p for poly in polys for ring in poly for p in ring]
        xs, zs = [p[0] for p in points], [p[1] for p in points]
        item['spatial_binding'] = {
            'geometry': geometry, 'geometry_sha256': hashlib.sha256(encoded(geometry)).hexdigest(),
            'source_refs': f['source_refs'], 'osm_name': f['source_tags']['name'],
            'bbox_xz_m': [min(xs), min(zs), max(xs), max(zs)],
            'bbox_centre_xz_m': [(min(xs)+max(xs))/2, (min(zs)+max(zs))/2],
            'anchor_semantics': 'Source envelope centre for visual placement only; not a surveyed entrance, centroid or player spawn',
            'source_generation_role': f['generation']['role'],
            'current_visual_mesh_id': mesh['id'], 'current_visual_role': mesh['role'],
            'current_mesh_vertices_sha256': hashlib.sha256(encoded(mesh['vertices'])).hexdigest(),
            'current_bottom_y_m': mesh['bottom_y_m'], 'current_top_y_m': mesh['top_y_m'],
            'height_m': h['height_m'], 'height_class': h['height_class'],
            'height_assumption_id': h['assumption_id'], 'source_levels': h['source_levels'],
            'height_component_ids': h['component_evidence_ids'],
            'independent_height_accuracy': h['independent_height_accuracy'],
            'physical_ground_elevation_m': None,
            'runtime_permission_from_reference': None,
        }
        item['evidence'] = [{'claim_id': cid, 'source_id': claims[cid]['source_id']} for cid in choice['claim_ids']]
        item['source_ids'] = sorted({c['source_id'] for c in item['evidence']})
        if any(sources[s]['asset_import_approved'] for s in item['source_ids']):
            raise ValueError('L01 references must not become imported assets')
        items.append(item)
    return {
        'schema_version': 1, 'task': 'L01', 'status': 'exterior_specification_only_not_implemented',
        'base_commit': plan['base_commit'], 'reference_review_date': refs['review_date'],
        'coordinate_contract': read(root, 'config/region.json'),
        'baseline_milestone': baseline['milestone_id'], 'baseline_snapshot_sha256': baseline['snapshot_sha256'],
        'provenance': {p: sha(root / p) for p in INPUTS},
        'policy': plan['policy'], 'reference_policy': refs['policy'],
        'landmarks': items, 'sources': refs['sources'], 'conflicts': plan['conflicts'],
        'protected_gate': {'source': 'game/data/generated/daehanmun.json',
                           'opening_m': gate['opening'], 'route_xz': gate['route_xz'],
                           'direction_xz': gate['direction_xz'],
                           'physical_dimensions_verified': False},
        'review_views': [{**v, 'player_xz_m': route['checkpoints'][v['checkpoint_index']]['xz'],
                          'position_basis': 'Existing W04 checkpoint, not a new camera or surveyed position'}
                         for v in plan['review_views']],
        'counts': {'landmarks': len(items), 'sources': len(sources),
                   'claims': len(claims), 'new_meshes': 0, 'new_collision_bodies': 0,
                   'imported_media_files': 0, 'new_routes': 0},
    }


def main(root, check=False):
    root = Path(root).resolve(); result = encoded(build(root)); target = root / OUTPUT
    if check:
        if not target.exists() or target.read_bytes() != result:
            raise ValueError('Missing/stale landmark specification; regenerate from reviewed authored inputs')
    else:
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(result)
    value = json.loads(result)
    print(json.dumps({'task': 'L01', 'passed': True, 'output': OUTPUT,
                      'sha256': hashlib.sha256(result).hexdigest(), 'counts': value['counts']}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    main(args.root, args.check)

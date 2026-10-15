#!/usr/bin/env python3
"""N03 source-bound road support and runtime traffic bundle; no player expansion."""
import argparse
import hashlib
import json
from pathlib import Path
from shapely.geometry import shape, mapping
from prepare_world import mesh_polygon
from prepare_routes import prepare as prepare_routes
from prepare_pedestrians import prepare as prepare_pedestrians
from check_routes import audit

ROOT = Path(__file__).resolve().parents[1]
OUT = 'game/data/generated/traffic.json'
MANIFEST = 'game/data/generated/traffic_manifest.json'
INPUTS = ['data/processed/vehicle_routes.json', 'data/processed/npc_routes.json',
          'game/data/generated/public_walk.json', 'game/data/generated/pedestrians.json',
          'game/resources/world_geometry/world.json', 'game/data/generated/region.json',
          'game/resources/collision/rules.json', 'game/resources/collision/traffic_rules.json',
          'tools/prepare_traffic.py', 'tools/prepare_world.py']


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def encode(value): return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n').encode()


def prepare(root=ROOT, check_only=False):
    root = Path(root)
    prepare_routes(root, True); prepare_pedestrians(root, True)
    vehicle = read(root/INPUTS[0]); npc = read(root/INPUTS[1])
    if not audit(root, npc, vehicle)['passed']: raise ValueError('N01 contract rejected')
    public = read(root/INPUTS[2]); floor = shape(public['support']['geometry'])
    supports = []
    for route in vehicle['routes']:
        envelope = shape(route['swept_geometry'])
        if not shape(route['road_domain']).buffer(1e-7).covers(envelope): raise ValueError('Support outside source road')
        missing = envelope.difference(floor)
        if missing.is_empty or not missing.is_valid: raise ValueError('Invalid road support complement')
        mesh = mesh_polygon(missing, -.2, 0)
        supports.append({'id': 'N03_support_'+route['id'], 'route_id': route['id'],
            'geometry': mapping(missing), **mesh, 'layer': 16, 'mask': 8,
            'basis': 'N01 continuous 2.6m swept envelope minus unchanged W03 support; flat y0 assumption, no new player permission',
            'area_m2': missing.area, 'overlap_existing_support_m2': missing.intersection(floor).area})
    scope = {'task': 'N03', 'vehicles': 2, 'pedestrians': 2, 'new_vehicle_supports': 2,
             'player_boundary_changed': False, 'physical_terrain_access_verified': False}
    bundle = {'schema_version': 1, 'task': 'N03', 'contract_id': 'N03-traffic-v1',
        'coordinate_system': vehicle['coordinate_system'], 'scope': scope,
        'source_sha256': {p: sha(root/p) for p in INPUTS}, 'policy': vehicle['policy'],
        'actor': {**vehicle['actor'], 'acceleration_mps2': 1.5, 'gravity_mps2': 9.8, 'safe_margin_m': .001,
                  'layer': 8, 'mask': 31},
        'routes': vehicle['routes'], 'crossings': vehicle['crossings'], 'supports': supports,
        'rules': read(root/INPUTS[7])}
    payload = encode(bundle)
    manifest = {'schema_version': 1, 'task': 'N03', 'contract_id': bundle['contract_id'], 'scope': scope,
        'file': {'path': 'res://data/generated/traffic.json', 'sha256': hashlib.sha256(payload).hexdigest(), 'bytes': len(payload)},
        'runtime_sha256': {('res://'+p.removeprefix('game/')): sha(root/p) for p in INPUTS[2:8]}}
    for name, content in [(OUT,payload),(MANIFEST,encode(manifest))]:
        dest=root/name
        if check_only:
            if not dest.exists() or dest.read_bytes()!=content: raise ValueError('Stale N03 runtime: '+name)
        else:
            dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(content)
    return bundle


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=ROOT);parser.add_argument('--check',action='store_true')
    args=parser.parse_args(); b=prepare(args.root,args.check)
    print('N03', 'checked' if args.check else 'prepared', 'supports=',len(b['supports']),'vehicles=',len(b['routes']))

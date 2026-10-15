#!/usr/bin/env python3
"""N02 small offline pedestrian bundle, bound to N01 and unchanged W03 support."""
import argparse
import hashlib
import json
from pathlib import Path
from prepare_routes import prepare as check_routes_source
from check_routes import audit

ROOT=Path(__file__).resolve().parents[1]
OUT='game/data/generated/pedestrians.json'
MANIFEST='game/data/generated/pedestrians_manifest.json'
INPUTS=['data/processed/npc_routes.json','data/manual/urban_routes.json','tools/prepare_pedestrians.py',
        'game/data/generated/public_walk.json','game/resources/world_geometry/world.json',
        'game/data/generated/region.json','game/resources/collision/rules.json']
def read(p):return json.loads(Path(p).read_text())
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def encode(v):return (json.dumps(v,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode()

def prepare(root=ROOT,check_only=False):
    root=Path(root);check_routes_source(root,True)
    npc=read(root/INPUTS[0]);cars=read(root/'data/processed/vehicle_routes.json')
    if not audit(root,npc,cars)['passed']:raise ValueError('N01 source contract not accepted')
    policy={'speed_mps':1.2,'height_m':1.7,'radius_m':.3,'gravity_mps2':9.8,'end_dwell_s':.5,
            'turn_radians_per_s':3.141592653589793,'clear_hold_s':.3,'retreat_after_s':2.,'retreat_probe_m':.6,
            'contact_margin_m':.1,'initial_phase':.5,'initial_direction':1,'layer':4,'mask':15}
    routes=[{k:r[k] for k in ('id','name','xz','ground_y_m','length_m','source_binding','repeat','speed_mps')} for r in npc['routes']]
    scope={'task':'N02','pedestrians':2,'vehicles':0,'new_static_collision':0,'source_permissions_unchanged':True,
           'physical_terrain_access_verified':False,'human_handling_M4_verified':False}
    bundle={'schema_version':1,'task':'N02','contract_id':'N02-pedestrians-v1','coordinate_system':npc['coordinate_system'],
            'source_sha256':{p:sha(root/p) for p in INPUTS},'policy':policy,'scope':scope,'routes':routes}
    payload=encode(bundle)
    manifest={'schema_version':1,'task':'N02','contract_id':bundle['contract_id'],'scope':scope,
              'file':{'path':'res://data/generated/pedestrians.json','sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload)},
              'public_sha256':sha(root/INPUTS[3]),'world_sha256':sha(root/INPUTS[4]),'region_sha256':sha(root/INPUTS[5])}
    for name,data in [(OUT,payload),(MANIFEST,encode(manifest))]:
        p=root/name
        if check_only:
            if not p.exists() or p.read_bytes()!=data:raise ValueError('Stale N02 runtime bundle: '+name)
        else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
    return bundle

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args()
    bundle=prepare(a.root,a.check);print('N02', 'checked' if a.check else 'prepared',len(bundle['routes']),'pedestrians; vehicles0')

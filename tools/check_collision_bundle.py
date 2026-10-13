#!/usr/bin/env python3
"""P04 standard-library runtime-bundle check, without recreating map geometry."""
import argparse,hashlib,json
from pathlib import Path
from prepare_game_data import prepare
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(root=ROOT):
 root=Path(root);prepare(root,check_only=True)
 world=json.loads((root/'game/resources/world_geometry/world.json').read_text());rules=json.loads((root/'game/resources/collision/rules.json').read_text());plan=json.loads((root/'game/resources/collision/generated.json').read_text())
 paths={'world_sha256':'game/resources/world_geometry/world.json','rules_sha256':'game/resources/collision/rules.json','region_sha256':'config/region.json','generator_sha256':'tools/prepare_collision.py'}
 for field,path in paths.items():
  if plan.get(field)!=sha(root/path):raise ValueError('Stale collision input:'+path)
 expected={m['id']:m for m in world['meshes'] if m['role'] in ['Buildings','Barriers'] or m['id']=='temporary_support'}
 if len(plan['entries'])!=len(expected) or len({e['mesh_id'] for e in plan['entries']})!=len(expected):raise ValueError('Collider count/IDs differ')
 for e in plan['entries']:
  m=expected[e['mesh_id']]
  if e!={'mesh_id':m['id'],'role':m['role'],'face_sha256':hashlib.sha256(json.dumps(m['vertices'],separators=(',',':')).encode()).hexdigest(),'triangles':len(m['vertices'])//9,'holes':m['topology']['holes'],'layer':1,'mask':14,'shape':'ConcavePolygonShape3D','backface_collision':True,'runtime_permission':None}:raise ValueError('Collision entry differs:'+e['mesh_id'])
 excluded={m['id'] for m in world['meshes']} - set(expected)
 if {e['mesh_id'] for e in plan['excluded']}!=excluded or len(plan['excluded'])!=len(excluded):raise ValueError('Excluded IDs differ')
 if plan['scope']!=rules['scope'] or plan['scope']['runtime_permission'] is not None or plan['scope']['walkability_verified'] or plan['scope']['gate_openings']!='W01_pending':raise ValueError('Permission/door scope differs')
 return {'task':'P04','passed':True,'counts':plan['counts'],'inputs':{p:sha(root/p) for p in paths.values()},'collision_sha256':sha(root/'game/resources/collision/generated.json')}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);a=p.parse_args();print(json.dumps(check(a.root),ensure_ascii=False,indent=2))

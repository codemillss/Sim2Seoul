#!/usr/bin/env python3
"""W01 stdlib freshness/provenance check; no geometry regeneration at launch."""
import argparse,hashlib,json
from pathlib import Path
from check_collision_bundle import check as check_p04
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def check(root=ROOT):
 root=Path(root);check_p04(root)
 p=json.loads((root/'game/data/generated/daehanmun.json').read_text());m=json.loads((root/'game/data/generated/daehanmun_manifest.json').read_text())
 for path,h in p['provenance'].items():
  if sha(root/path)!=h:raise ValueError('Stale W01 input:'+path)
 for key,path in [('connection','game/data/generated/daehanmun.json'),('decision','game/data/generated/daehanmun_decision.json')]:
  if m['files'][key]['path']!='res://'+path.removeprefix('game/') or sha(root/path)!=m['files'][key]['sha256']:raise ValueError('W01 runtime checksum mismatch:'+path)
 if (root/'game/data/generated/daehanmun_decision.json').read_bytes()!=(root/'data/manual/daehanmun_connection.json').read_bytes():raise ValueError('Manual source/copy mismatch')
 for key,path in [('world_sha256','game/resources/world_geometry/world.json'),('collision_sha256','game/resources/collision/generated.json'),('region_sha256','config/region.json')]:
  if m[key]!=sha(root/path):raise ValueError('W01 base source mismatch')
 if p['task']!='W01' or p['scope']['physical_terrain_verified'] or p['scope']['measured_gate_dimensions'] or p['scope']['global_playable_boundary'] is not None:raise ValueError('W01 scope differs')
 return {'task':'W01','passed':True,'connection_sha256':sha(root/'game/data/generated/daehanmun.json'),'counts':p['counts']}
if __name__=='__main__':
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--root',type=Path,default=ROOT);p=a.parse_args();print(json.dumps(check(p.root),indent=2))

#!/usr/bin/env python3
"""W03 standard-library freshness preflight; engine needs no source maps/GIS."""
import hashlib
import json
from pathlib import Path
from check_palace_bundle import check as check_w02
ROOT=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def check(root=ROOT):
    root=Path(root);check_w02(root)
    m=json.loads((root/'game/data/generated/public_manifest.json').read_text());p=json.loads((root/'game/data/generated/public_walk.json').read_text());d=(root/'data/manual/public_walk.json').read_bytes()
    assert m['task']==p['task']=='W03' and m['schema_version']==p['schema_version']==1
    for key,path in [('connection','data/generated/public_walk.json'),('decision','data/generated/public_decision.json')]:
        assert m['files'][key]['path']=='res://'+path and m['files'][key]['sha256']==sha(root/'game'/path)
    assert d==(root/'game/data/generated/public_decision.json').read_bytes()
    assert p['scope']==json.loads(d)['scope'] and p['scope']['physical_terrain_verified'] is False
    assert p['boundary']['finalized_for_scene'] is True and p['boundary']['contract_id']=='W03-play-boundary-v1'
    assert all(sha(root/name)==value for name,value in p['provenance'].items())
    assert m['world_sha256']==sha(root/'game/resources/world_geometry/world.json') and m['w02_sha256']==sha(root/'game/data/generated/palace_walk.json')
    assert m['boundary_resource_sha256']==sha(root/'game/resources/play_boundary.tres')
    return {'task':'W03','passed':True,'connection_sha256':sha(root/'game/data/generated/public_walk.json'),'counts':p['counts']}
if __name__=='__main__':print(json.dumps(check(),ensure_ascii=False,indent=2))

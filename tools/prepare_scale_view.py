#!/usr/bin/env python3
"""Package preserved G01 references for an E04 fixed scene; standard library only."""
import argparse
import hashlib
import json
from pathlib import Path
from prepare_game_data import prepare

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_scale(root=ROOT, check_only=False):
    root = Path(root)
    prepare(root, check_only=True)
    report = json.loads((root/'data/reports/coordinate_check.json').read_text())
    reference = json.loads((root/'data/processed/coordinate_reference.json').read_text())
    if not report['passed'] or reference != report['coordinate_reference']:
        raise ValueError('G01 local reference differs from validated snapshot; rerun G01 before E04')
    config = json.loads((root/'config/scale_view.json').read_text())
    region = json.loads((root/'config/region.json').read_text())
    if reference['provenance']['config_sha256'] != sha(root/'config/region.json'):
        raise ValueError('G01 region drift')
    if config['expected_cardinal_vectors'] != {r['id']:r['expected_world_xyz_m'] for r in reference['synthetic_10m_controls']}:
        raise ValueError('E04 synthetic controls differ from G01')
    world_file = root/'game/resources/world_geometry/world.json'
    world = json.loads(world_file.read_text())
    ids = {entry['metadata']['feature_id'] for entry in world['meshes']}
    anchors = []
    for source_id, point in reference['landmark_points'].items():
        entity = 'osm:'+source_id.replace('w/','way:').replace('r/','relation:')
        fid = entity + (':land_area' if point['name']=='서울광장' else ':building')
        if fid not in ids: raise ValueError(f'E03 selected feature missing: {fid}')
        anchors.append({'id':source_id,'feature_id':fid, **point})
    inputs = ['config/region.json','config/scale_view.json','data/reports/coordinate_check.json',
              'data/processed/coordinate_reference.json','game/resources/world_geometry/world.json','tools/prepare_scale_view.py']
    data = {'schema_version':1,'task':'E04','coordinate_contract_sha256':sha(root/'config/region.json'),
            'world_sha256':sha(world_file),'settings':config,'anchors':anchors,
            'distance_pairs':report['distance_pairs'],'controls':reference['synthetic_10m_controls'],
            'origin_xyz_m':[0,0,0],'meters_per_world_unit':region['meters_per_world_unit'],
            'provenance':[{'file':name,'sha256':sha(root/name)} for name in inputs],
            'scope':'source vertices and straight-line horizontal distances; synthetic y/axes/cube; not entrances/spawn/walking/physical accuracy'}
    content = (json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode()
    manifest = {'schema_version':1,'task':'E04','file':'res://data/generated/scale_view.json',
                'sha256':hashlib.sha256(content).hexdigest(),'bytes':len(content),'world_sha256':sha(world_file)}
    payloads = {'scale_view.json':content, 'scale_manifest.json':(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()}
    output=root/'game/data/generated'
    for name, value in payloads.items():
        if check_only:
            if not (output/name).exists() or (output/name).read_bytes()!=value:
                raise ValueError(f'E04 bundle stale/missing: {name}')
        else: (output/name).write_bytes(value)
    return {'task':'E04','check_only':check_only,'anchors':len(anchors),'pairs':len(data['distance_pairs']),
            'controls':len(data['controls']),'files':[{'file':str((output/name).relative_to(root)),
                'bytes':len(value),'sha256':hashlib.sha256(value).hexdigest()} for name,value in payloads.items()]}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    print(json.dumps(prepare_scale(check_only=parser.parse_args().check),ensure_ascii=False,indent=2))

#!/usr/bin/env python3
"""Standard-library W02 freshness check; no GIS packages needed to launch."""
import hashlib
import json
from pathlib import Path
from check_daehanmun_bundle import check as check_w01

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(root=ROOT):
    root = Path(root)
    check_w01(root)
    manifest = json.loads((root / 'game/data/generated/palace_manifest.json').read_text())
    plan = json.loads((root / 'game/data/generated/palace_walk.json').read_text())
    decision = (root / 'data/manual/palace_walk.json').read_bytes()
    assert manifest['task'] == plan['task'] == 'W02'
    assert manifest['schema_version'] == plan['schema_version'] == 1
    expected = {'connection': 'data/generated/palace_walk.json', 'decision': 'data/generated/palace_decision.json'}
    for key, path in expected.items():
        assert manifest['files'][key]['path'] == 'res://' + path
        assert manifest['files'][key]['sha256'] == sha(root / 'game' / path)
    assert decision == (root / 'game/data/generated/palace_decision.json').read_bytes()
    assert plan['scope'] == json.loads(decision)['scope']
    assert plan['scope']['physical_terrain_verified'] is False and plan['scope']['global_playable_boundary'] is None
    assert all(sha(root / name) == value for name, value in plan['provenance'].items())
    assert manifest['world_sha256'] == sha(root / 'game/resources/world_geometry/world.json')
    assert manifest['w01_sha256'] == sha(root / 'game/data/generated/daehanmun.json')
    assert manifest['region_sha256'] == sha(root / 'config/region.json')
    return {'task': 'W02', 'passed': True, 'connection_sha256': sha(root / 'game/data/generated/palace_walk.json'), 'counts': plan['counts']}


if __name__ == '__main__':
    print(json.dumps(check(), ensure_ascii=False, indent=2))

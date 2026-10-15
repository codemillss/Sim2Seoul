#!/usr/bin/env python3
"""Audit L01 evidence/bindings and reproduce its spec in a prepared relocated copy.

No engine execution. This does not test rendered recognition, access or usability.
"""
import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '1922c70c6e1a569b0f980beaaf5742906b7de340'
SPEC = 'data/processed/landmark_spec.json'
EXPECTED = {
    'daehanmun': ('osm:way:377289797:building', 'L02'),
    'junghwajeon': ('osm:way:181574577:building', 'L02'),
    'junghwamun': ('osm:way:181574580:building', 'L02'),
    'seokjojeon': ('osm:relation:19357693:building', 'L02'),
    'dondeokjeon': ('osm:way:517072312:building', 'L02'),
    'jeonggwanheon': ('osm:way:381755268:building', 'L02'),
    'city_hall': ('osm:way:198561926:building', 'L03'),
    'library': ('osm:relation:10757525:building', 'L03'),
    'plaza': ('osm:way:370019676:land_area', 'L03'),
    'sfc': ('osm:way:332565592:building', 'L03'),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(name):
    return json.loads((ROOT / name).read_text())


def finite(x):
    if isinstance(x, float): return math.isfinite(x)
    if isinstance(x, dict): return all(finite(v) for v in x.values())
    if isinstance(x, list): return all(finite(v) for v in x)
    return True


def main(output):
    checks = []
    def ck(name, passed, details=None):
        checks.append({'name': name, 'passed': bool(passed), **({'details': details} if details is not None else {})})
    spec = read(SPEC); plan = read('data/manual/landmark_plan.json'); references = read('data/manual/landmark_references.json')
    world = read('game/resources/world_geometry/world.json'); baseline = read('data/reports/walkable_milestone/snapshot.json')
    features = {f['feature_id']: f for f in read('data/processed/features.json')['features']}
    heights = {h['feature_id']: h for h in read('data/processed/heights.json')['records']}
    source_by = {s['id']: s for s in references['sources']}
    claim_by = {c['id']: (s['id'], c) for s in references['sources'] for c in s['claims']}
    rows = {r['id']: r for r in spec['landmarks']}
    ck('schema_and_scope', spec['schema_version'] == 1 and spec['task'] == plan['task'] == references['task'] == 'L01' and
       spec['status'] == 'exterior_specification_only_not_implemented' and finite(spec))
    ck('unique_complete_targets', len(rows) == len(spec['landmarks']) == 10 and set(rows) == set(EXPECTED) and
       len({r['feature_id'] for r in rows.values()}) == 10 and
       all((rows[k]['feature_id'], rows[k]['phase']) == v for k, v in EXPECTED.items()))
    ck('sources_unique_and_linkable', len(source_by) == len(references['sources']) == 11 and
       len(claim_by) == sum(len(s['claims']) for s in references['sources']) and
       all(s['url'].startswith('https://') and s['publisher'] and s['access_method'] and s['locator'] for s in source_by.values()))
    ck('dates_not_inferred', all(s['photo_capture_date'] is None and s['date_semantics'] for s in source_by.values()) and
       source_by['P04']['page_date'] == '2023-09-25' and source_by['C05']['page_date'] == '2026-10-06')
    ck('media_not_approved', references['policy']['media_downloaded'] is False and
       references['policy']['asset_import_approved'] is False and all(s['asset_import_approved'] is False and s['rights_observation'] for s in source_by.values()))
    policy = spec['policy']
    ck('no_runtime_or_interior_authority', all(policy[k] is False for k in ('game_changes_in_L01', 'interiors_in_scope', 'collision_changes_approved', 'route_changes_approved')) and
       policy['runtime_permission_from_reference'] is None and spec['counts'] == dict(landmarks=10, sources=11, claims=len(claim_by), new_meshes=0, new_collision_bodies=0, imported_media_files=0, new_routes=0))
    ck('current_provenance', all(not Path(p).is_absolute() and sha(ROOT / p) == h for p, h in spec['provenance'].items()))
    summary = []
    for id, r in rows.items():
        fid = r['feature_id']; f = features[fid]; h = heights[fid]; b = r['spatial_binding']
        mesh = next(m for m in world['meshes'] if m.get('metadata', {}).get('feature_id') == fid)
        ck(id + '.identity_geometry', b['geometry'] == f['geometry'] and b['source_refs'] == f['source_refs'] and
           b['osm_name'] == r['source_name'] == f['source_tags']['name'] and b['current_visual_mesh_id'] == mesh['id'])
        ck(id + '.height_semantics', b['height_m'] == h['height_m'] and b['height_class'] == h['height_class'] and
           b['height_assumption_id'] == h['assumption_id'] and b['height_component_ids'] == h['component_evidence_ids'] and
           b['current_top_y_m'] == mesh['top_y_m'] and b['current_bottom_y_m'] == mesh['bottom_y_m'] and
           b['independent_height_accuracy'] == 'unverified' and b['physical_ground_elevation_m'] is None and
           b['runtime_permission_from_reference'] is None and (id == 'plaza' or h['emit_coarse_body'] is True))
        ck(id + '.actionable_minimum', len(r['minimum_features']) >= 2 and bool(r['authored_design']) and bool(r['preserve']) and
           bool(r['omit']) and bool(r['fallback']) and bool(r['orientation_basis']) and bool(r['review_view_ids']))
        ck(id + '.claim_links', bool(r['claim_ids']) and all(c in claim_by for c in r['claim_ids']) and
           r['evidence'] == [{'claim_id': c, 'source_id': claim_by[c][0]} for c in r['claim_ids']] and
           set(r['source_ids']) == {claim_by[c][0] for c in r['claim_ids']})
        summary.append({'id': id, 'feature_id': fid, 'phase': r['phase'], 'height_m': b['height_m'],
                        'height_class': b['height_class'], 'source_ids': r['source_ids'],
                        'geometry_sha256': b['geometry_sha256'], 'minimum_features': r['minimum_features']})
    gate = read('game/data/generated/daehanmun.json'); closed = rows['junghwamun']; selected = rows['jeonggwanheon']
    ck('gate_and_overlap_contracts', spec['protected_gate']['opening_m'] == gate['opening'] == dict(width=3.0, height=3.0) and
       spec['protected_gate']['route_xz'] == gate['route_xz'] and spec['protected_gate']['physical_dimensions_verified'] is False and
       any('CLOSED' in s for s in closed['preserve']) and closed['spatial_binding']['height_m'] == 5 and
       selected['feature_id'] == 'osm:way:381755268:building' and selected['spatial_binding']['current_visual_mesh_id'] == selected['feature_id'])
    ck('roof_tier_not_eave_construction', 'single_roof_tier_tile_silhouette' in rows['daehanmun']['minimum_features'] and
       not any('single_eave' in f for f in rows['daehanmun']['minimum_features']) and
       any('eave construction' in s for s in rows['daehanmun']['omit']))
    conflicts = {c['id']: c for c in spec['conflicts']}
    ck('conflicts_not_silent_overrides', set(conflicts) == {'plaza_currentness', 'sfc_height_identity', 'dondeokjeon_period'} and
       claim_by['C07-height'][1]['reported_height_m'] == 130 and rows['sfc']['spatial_binding']['height_m'] == 124 and
       features[rows['sfc']['feature_id']]['source_tags']['addr:housenumber'] == '36' and
       all(c['resume_task'] in ('L02', 'L03') and c['decision'] and c['resume_evidence'] for c in conflicts.values()))
    views = {v['id']: v for v in spec['review_views']}; cps = read('game/data/generated/walkable_itinerary.json')['checkpoints']
    ck('views_are_existing_candidates', len(views) == len(spec['review_views']) == 6 and
       all(v['state'] == 'planned_not_rendered' and v['player_xz_m'] == cps[v['checkpoint_index']]['xz'] and
           set(v['targets']) <= set(rows) for v in views.values()) and
       all(set(r['review_view_ids']) <= set(views) and all(r['id'] in views[v]['targets'] for v in r['review_view_ids']) for r in rows.values()))
    copied = set(spec['provenance'])
    baseline_checks = {}
    for field, prefix in [('sources', 'game'), ('runtime_assets', 'game'), ('inputs', ''), ('proof', '')]:
        ok = True
        for name, digest in baseline[field].items():
            p = str(Path(prefix) / name) if prefix else name
            ok = ok and not Path(name).is_absolute() and sha(ROOT / p) == digest
            copied.add(p)
        baseline_checks[field] = ok
        ck('W04.frozen_' + field, ok)
    ck('W04.prerequisite_passed', read('data/reports/w04_verification.json')['passed'] and
       spec['baseline_snapshot_sha256'] == baseline['snapshot_sha256'])
    # Reproduce from prepared local inputs only, in a directory without Git/GIS/engine/cache/output.
    input_hashes = {p: sha(ROOT / p) for p in sorted(copied)}
    portable_runs = []
    expected = sha(ROOT / SPEC)
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l01-') as temporary:
        target = Path(temporary)
        for name in copied:
            if Path(name).is_absolute() or '..' in Path(name).parts or name.startswith(('data/raw/geofabrik/', '.venv', 'data/cache/')):
                raise ValueError('Not a prepared small input: ' + name)
            destination = target / name; destination.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / name, destination)
        ck('portable.clean_start', not (target / SPEC).exists() and all(not (target / p).exists() for p in ('.git', '.venv-data', 'game/.godot', 'data/cache')))
        for i in range(2):
            result = subprocess.run([sys.executable, '-E', '-S', '-B', str(target / 'tools/prepare_landmark_spec.py'), '--root', str(target)], capture_output=True, text=True, timeout=60)
            digest = sha(target / SPEC) if (target / SPEC).exists() else None
            portable_runs.append({'run': i+1, 'returncode': result.returncode, 'spec_sha256': digest,
                                  'output': result.stdout.strip(), 'error': result.stderr.strip()})
            ck('portable.reproduce_' + str(i+1), result.returncode == 0 and digest == expected)
        ck('portable.input_bytes_unchanged', all(sha(target / p) == h for p, h in input_hashes.items()))
    ck('original_input_bytes_unchanged', all(sha(ROOT / p) == h for p, h in input_hashes.items()))
    # Compare old authored/spatial files with the exact start commit; new L01 files are separate.
    preserved = {}
    old = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    for name in old:
        if not name.startswith(('game/', 'tools/', 'tests/', 'config/', 'data/manual/', 'data/raw/')): continue
        original = hashlib.sha256(subprocess.check_output(['git', 'show', BASE + ':' + name], cwd=ROOT)).hexdigest()
        preserved[name] = original
    ck('previous_authored_spatial_sources_unchanged', all(sha(ROOT / p) == h for p, h in preserved.items()))
    for name in ('tools/prepare_landmark_spec.py', 'tools/check_landmark_spec.py'):
        compile((ROOT / name).read_bytes(), name, 'exec')
    ck('new_python_syntax', True)
    result = {'task': 'L01', 'passed': all(c['passed'] for c in checks), 'base_commit': BASE,
              'spec_sha256': expected, 'checks': checks, 'target_summary': summary,
              'sources_sha256': sha(ROOT / 'data/manual/landmark_references.json'),
              'plan_sha256': sha(ROOT / 'data/manual/landmark_plan.json'),
              'tools_sha256': {p: sha(ROOT / p) for p in ('tools/prepare_landmark_spec.py', 'tools/check_landmark_spec.py')},
              'portable': {'copied_files': len(copied), 'copied_bytes': sum((ROOT/p).stat().st_size for p in copied),
                           'copied_inputs': input_hashes, 'runs': portable_runs,
                           'python_flags': ['-E', '-S', '-B'],
                           'scope': 'L01-only from prepared existing-M1 inputs; no fullGIS rebuild/new installation/engine/M4 test'},
              'previous_authored_and_spatial_sources': preserved,
              'scope': 'Reference/exterior specification acceptance only. No new model, image asset, rendered recognition, walking regression, current-world measurement, human handling, M4 or V0 acceptance.'}
    output.parent.mkdir(parents=True, exist_ok=True); output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print('L01 spec', result['passed'], 'checks', len(checks), 'prepared copied files', len(copied))
    if not result['passed']: print([c for c in checks if not c['passed']])
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/reports/landmarks/l01_validation.json')
    args = parser.parse_args()
    raise SystemExit(main(args.output.resolve()))

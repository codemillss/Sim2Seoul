#!/usr/bin/env python3
"""Verify retained W02 evidence against this checkout; run from any directory."""
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from check_palace_contract import FILES, ASSETS
from check_palace_bundle import check as preflight

BASE = 'f26390c2f1b1654e9174ef55a5079b16f4a54528'
REPORTS = ROOT / 'data/reports/palace'
checks = []


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(name):
    return json.loads((REPORTS / name).read_text())


def ck(name, passed, details=None):
    row = {'name': name, 'passed': bool(passed)}
    if details is not None:
        row['details'] = details
    checks.append(row)


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite(v) for v in value)
    if isinstance(value, dict):
        return all(finite(v) for v in value.values())
    return True


preflight_result = preflight(ROOT)
ck('runtime.fresh', preflight_result['passed'])
contract, gpu = read('contract_check.json'), read('gpu_check.json')
rejection, portability = read('rejections/rejection_check.json'), read('portability_check.json')
review, native = read('independent_review.json'), read('native_production.json')
for name, report in [('contract', contract), ('gpu', gpu), ('rejections', rejection),
                     ('portability', portability), ('independent_review', review), ('native', native)]:
    ck(name + '.passed', report['passed'])
for key in ['sources', 'runtime_assets', 'input_sha256', 'proof_sha256']:
    ck('contract_gpu.' + key, contract[key] == gpu[key])
for prefix, hashes in [('sources', contract['sources']), ('runtime', contract['runtime_assets'])]:
    ck('current.' + prefix, all(sha(ROOT / 'game' / p) == digest for p, digest in hashes.items()))
saved_root = Path(portability['interpreter']).parents[2]
def checkout_path(path):
    value = Path(path)
    return ROOT / value.relative_to(saved_root) if value.is_absolute() else ROOT / value
for key in ['input_sha256', 'proof_sha256']:
    ck('current.' + key, all(sha(checkout_path(p)) == digest for p, digest in contract[key].items()))
ck('source_copy.count', len(FILES) == 32 and len(ASSETS) == 10)
ck('actual_faults.six', len(contract['actual_faults']) == 6 and all(
    f['checker_passed'] is False and f['related_failures'] for f in contract['actual_faults']))
ck('actual_rejection.fifteen', len(rejection['cases']) == 15 and all(c['passed'] for c in rejection['cases']))
ck('portability.prepared_only', portability['copied_files'] == 85 and portability['clean_start'] and
   portability['original_inputs_unchanged'] and len(portability['runs']) == 2)
ck('portability.current_inputs', all(sha(ROOT / p) == h for p, h in portability['copied_inputs'].items()))
old_paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
preserved = {}
for p in old_paths:
    if not p.startswith(('game/', 'tests/', 'tools/', 'config/', 'data/manual/', 'data/raw/')):
        continue
    original = subprocess.check_output(['git', 'show', BASE + ':' + p], cwd=ROOT)
    digest = hashlib.sha256(original).hexdigest()
    preserved[p] = digest
    ck('baseline.' + p, sha(ROOT / p) == digest)
observations = {}
for name, required in [('headless_engine', 1237), ('repeat_engine', 1237),
                       ('gpu_30_engine', 854), ('gpu_60_engine', 1252)]:
    raw, scored = read(name + '.json'), read(name + '_check.json')
    ck(name + '.accepted', scored['passed'] and len(scored['checks']) == required)
    ck(name + '.input_hash', raw['plan_sha256'] == preflight_result['connection_sha256'])
    observations[name] = {'cases': len(raw['cases']), 'ticks': sum(c['ticks'] for c in raw['cases']),
                          'checks': len(scored['checks']), 'engine': raw['engine'],
                          'max_player_penetration_m': max(c['W02_stats']['max_player_penetration_m'] for c in raw['cases']),
                          'max_camera_penetration_m': max(c['W02_stats']['max_camera_penetration_m'] for c in raw['cases']),
                          'unintended_recoveries': sum(c['recoveries'] for c in raw['cases']),
                          'max_target_error_m': max([g['maximum_target_error_m'] for g in raw['route_groups']] or [0]),
                          'external_movement_events_ignored': raw['external_movement_events_ignored']}
    for capture in raw['captures']:
        prefix = 'view_30_' if raw['engine']['render_fps'] == 30 else 'view_'
        file = REPORTS / (prefix + capture['name'] + '.png')
        ck('capture.' + name + '.' + capture['name'], file.exists() and file.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
new_python = ['tools/check_palace_bundle.py', 'tools/check_palace_contract.py', 'tools/check_palace_evidence.py',
              'tools/check_palace_portability.py', 'tools/check_palace_rejections.py', 'tools/prepare_palace_walk.py']
for p in new_python:
    compile((ROOT / p).read_bytes(), p, 'exec')
ck('new_python.syntax', True)
ck('launcher.syntax', subprocess.run(['sh', '-n', str(ROOT / 'tools/run_palace_walk.sh')]).returncode == 0)
ck('reports.finite_json', all(finite(json.loads(p.read_text())) for p in REPORTS.rglob('*.json')))
documents = ['README.md', 'docs/PROJECT_CONTEXT.md', 'docs/WORK_STATUS.md', 'docs/SOL_HANDOFF.md',
             'docs/IMPLEMENTATION_TASKS.md', 'docs/TECHNICAL_CONTRACTS.md', 'docs/VALIDATION_PLAN.md',
             'docs/CROSS_MAC.md', 'docs/GAME_PROJECT.md', 'docs/EXECUTION_LOG.md',
             'docs/evidence/W03_INPUT_REVIEW.md', 'data/reports/palace_walk.md']
for name in documents:
    file = ROOT / name
    broken = []
    for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', file.read_text()):
        if re.match(r'^[a-z]+://', target) or target.startswith('#'):
            continue
        path = target.split('#', 1)[0]
        if path and not (file.parent / path).exists():
            broken.append(target)
    ck('document.links.' + name, not broken, broken)
status = (ROOT / 'docs/WORK_STATUS.md').read_text()
plan = (ROOT / 'docs/IMPLEMENTATION_TASKS.md').read_text()
ck('status.next_task', '## 다음 작업: W03' in status and 'W0는 미완료' in status)
ck('plan.W02_checked_W03_unchecked', '### [x] W02 ' in plan and '### [ ] W03 ' in plan)
ck('native.production_only', native['automatic_probe'] is False and native['returncode'] == 0 and
   'W02_READY' in native['stdout'] and 'ERROR:' not in native['stdout'] + native['stderr'] and
   native['log_sha256'] == sha(REPORTS / 'native_production.log'))
result = {'task': 'W02', 'passed': all(c['passed'] for c in checks), 'base_commit': BASE, 'next_task': 'W03',
          'checks': checks, 'sources': contract['sources'], 'runtime_assets': contract['runtime_assets'],
          'previous_authored_and_source_inputs_unchanged': preserved, 'observations': observations,
          'actual_fault_required_failures': contract['actual_faults'], 'rejected_inputs': 15,
          'portable_prepared_inputs': 85, 'handoff_script_sha256': sha(Path(__file__)), 'review_sha256': sha(REPORTS / 'independent_review.json'),
          'native_preview_sha256': sha(REPORTS / 'native_production.json'),
          'document_sha256': {p: sha(ROOT / p) for p in documents},
          'failure_history_sha256': {str(p.relative_to(ROOT)): sha(p) for p in (REPORTS / 'development_failure').iterdir()},
          'scope': 'Automatic W02 palace loop and courtyard acceptance on existing M1 engineering flat support. No human/OS handling, real access/terrain, M4, W03/W04/W0/V0, city performance or NPC/vehicle acceptance.'}
(ROOT / 'data/reports/w02_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print('W02 handoff', result['passed'], 'checks', len(checks))
if not result['passed']:
    print([c for c in checks if not c['passed']])
raise SystemExit(0 if result['passed'] else 1)

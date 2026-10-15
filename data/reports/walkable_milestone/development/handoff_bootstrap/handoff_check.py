#!/usr/bin/env python3
"""Verify the W04 engineering snapshot; --freeze records its first exact identity."""
import argparse
import hashlib
import json
import math
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from prepare_walkable_itinerary import prepare

BASE = 'b4216b78e1a549e8d7ca5870fe2ed3570c026a86'
REPORTS = ROOT / 'data/reports/walkable_milestone'
DOCUMENTS = ['README.md', 'docs/PROJECT_CONTEXT.md', 'docs/WORK_STATUS.md',
             'docs/SOL_HANDOFF.md', 'docs/IMPLEMENTATION_TASKS.md', 'docs/MASTER_PLAN.md',
             'docs/TECHNICAL_CONTRACTS.md', 'docs/VALIDATION_PLAN.md', 'docs/CROSS_MAC.md',
             'docs/GAME_PROJECT.md', 'docs/EXECUTION_LOG.md', 'docs/WALKABLE_CHECKLIST.md',
             'data/reports/walkable_milestone.md']
NEW_SOURCES = ['tools/prepare_walkable_itinerary.py', 'tools/check_walkable_contract.py',
               'tools/check_walkable_evidence.py', 'tools/check_walkable_portability.py',
               'tools/run_walkable_milestone.sh', 'tests/game/check_walkable_milestone.gd',
               'data/manual/walkable_milestone.json']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(name):
    return json.loads((REPORTS / name).read_text())


def finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, (list, dict)):
        return all(finite(v) for v in (value.values() if isinstance(value, dict) else value))
    return True


def png_valid(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return False
    offset, dimensions, ended = 8, None, False
    while offset < len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        kind, payload = data[offset+4:offset+8], data[offset+8:offset+8+length]
        crc = struct.unpack_from('>I', data, offset+8+length)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            return False
        if kind == b'IHDR':
            dimensions = struct.unpack_from('>II', payload)
        offset += length + 12
        if kind == b'IEND':
            ended = True
            break
    return ended and offset == len(data) and dimensions == (1152, 720)


def main(freeze=False):
    checks = []
    def ck(name, passed, details=None):
        checks.append({'name': name, 'passed': bool(passed), **({'details': details} if details is not None else {})})
    preflight = prepare(ROOT, True)
    ck('runtime.fresh', preflight['passed'])
    contract, gpu, trial = (read(n + '_check.json') for n in ('contract', 'gpu', 'gpu_trial'))
    portability, relocation, review = (read(n + '.json') for n in ('portability_check', 'relocation_check', 'independent_review'))
    for name, result in [('contract', contract), ('gpu', gpu), ('gpu_trial', trial),
                         ('portability', portability), ('relocation', relocation), ('independent_review', review)]:
        ck(name + '.passed', result['passed'])
    ck('relocation.exact_evidence', relocation['checker_sha256'] == sha(ROOT / 'tools/check_walkable_evidence.py') and
       relocation['raw_sha256'] == sha(ROOT / relocation['raw']) and
       relocation['relocated']['original_absolute_access_attempts'] == [] and relocation['relocated']['identical_result'])
    for field, prefix in [('sources', 'game'), ('runtime_assets', 'game'), ('input_sha256', ''), ('proof_sha256', '')]:
        ck('frozen.' + field, contract[field] == gpu[field] == trial[field])
        ck('current.' + field, all(not Path(p).is_absolute() and sha(ROOT / prefix / p) == h for p, h in contract[field].items()))
    ck('copy.count', len(contract['sources']) == 39 and len(contract['runtime_assets']) == 15)
    ck('actual_faults.four', len(contract['actual_faults']) == 4 and all(
        f['checker_passed'] is False and f['related_failures'] for f in contract['actual_faults']))
    ck('portability.prepared_only', portability['copied_files'] == 65 and portability['clean_start'] and
       portability['original_inputs_unchanged'] and portability['copied_inputs_unchanged'] and len(portability['runs']) == 2)
    ck('portability.current_inputs', all(sha(ROOT / p) == h for p, h in portability['copied_inputs'].items()))
    ck('portability.current_tools', all(sha(ROOT / p) == h for p, h in portability['w04_sources'].items()))
    old_paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    preserved = {}
    for p in old_paths:
        if not p.startswith(('game/', 'tests/', 'tools/', 'config/', 'data/manual/', 'data/raw/')):
            continue
        digest = hashlib.sha256(subprocess.check_output(['git', 'show', BASE + ':' + p], cwd=ROOT)).hexdigest()
        preserved[p] = digest
        ck('baseline.' + p, sha(ROOT / p) == digest)
    observations = {}
    for name in ('headless_engine', 'repeat_engine', 'gpu_trial_engine', 'gpu_engine'):
        raw, score = read(name + '.json'), read(name + '_check.json')
        ck(name + '.passed', score['passed'] and all(c['passed'] for c in score['checks']))
        ck(name + '.plan', raw['plan_sha256'] == preflight['plan_sha256'])
        journey = raw['journey']
        full = name != 'gpu_trial_engine'
        ck(name + '.coverage', len(raw['cases']) == (334 if full else 8) and
           len(journey['groups']) == (11 if full else 2) and
           len(journey['checkpoint_events']) == (21 if full else 3))
        ck(name + '.no_skip', journey['stats']['pose_calls'] == journey['stats']['recoveries'] == 0 and
           journey['stats']['outside_movement_ticks'] == 0 and journey['stats']['floor_support_ticks'] == journey['ticks'])
        observations[name] = {k: journey[k] for k in ('ticks', 'duration_s', 'wall_s', 'frames', 'movement_ticks', 'checkpoint_dwell_ticks')}
        observations[name].update(cases=len(raw['cases']), stages=len(journey['groups']),
            checks=len(score['checks']), stats=journey['stats'], engine=raw['engine'],
            max_target_error_m=max(g['maximum_target_error_m'] for g in journey['groups']))
        for capture in raw['captures']:
            prefix = 'trial_view_' if name == 'gpu_trial_engine' else 'view_'
            ck('capture.' + name + '.' + capture['name'], png_valid(REPORTS / (prefix + capture['name'] + '.png')))
    for p in NEW_SOURCES:
        if p.endswith('.py'):
            compile((ROOT / p).read_bytes(), p, 'exec')
    compile(Path(__file__).read_bytes(), str(__file__), 'exec')
    ck('new_python.syntax', True)
    ck('launcher.syntax', subprocess.run(['sh', '-n', str(ROOT / 'tools/run_walkable_milestone.sh')]).returncode == 0)
    ck('reports.finite_json', all(finite(json.loads(p.read_text())) for p in REPORTS.rglob('*.json')))
    for name in DOCUMENTS:
        file = ROOT / name
        broken = []
        for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', file.read_text()):
            if re.match(r'^[a-z]+://', target) or target.startswith('#'):
                continue
            path = target.split('#', 1)[0]
            if path and not (file.parent / path).exists():
                broken.append(target)
        ck('document.links.' + name, not broken, broken)
    status, plan = ((ROOT / p).read_text() for p in ('docs/WORK_STATUS.md', 'docs/IMPLEMENTATION_TASKS.md'))
    ck('status.next_L01', '## 다음 작업: L01' in status and 'W0-engineering-walk-v1' in status)
    ck('plan.scoped_W04', '### [x] W04 ' in plan and '### [ ] L01 ' in plan and '직접 조작 미검증' in plan)
    evidence = {str(p.relative_to(ROOT)): sha(p) for p in sorted(REPORTS.rglob('*'))
                if p.is_file() and p.name != 'snapshot.json' and '__pycache__' not in p.parts}
    body = {'schema_version': 1, 'milestone_id': 'W0-engineering-walk-v1', 'base_commit': BASE,
            'sources': contract['sources'], 'runtime_assets': contract['runtime_assets'],
            'inputs': contract['input_sha256'], 'proof': contract['proof_sha256'],
            'new_sources': {p: sha(ROOT / p) for p in NEW_SOURCES},
            'documents': {p: sha(ROOT / p) for p in DOCUMENTS}, 'evidence': evidence,
            'previous_authored_and_small_source_inputs': preserved,
            'scope': 'Automatic continuous engine acceptance on M1 with existing W03 temporary support. Human handling, OS focus, M4, real access/terrain, detailed landmarks, NPC/vehicles and V0 remain unverified.'}
    identity = hashlib.sha256(json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    snapshot = {**body, 'snapshot_sha256': identity}
    destination = REPORTS / 'snapshot.json'
    if freeze and not destination.exists() and all(c['passed'] for c in checks):
        destination.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
    ck('snapshot.exact_identity', destination.exists() and read('snapshot.json') == snapshot)
    result = {'task': 'W04', 'passed': all(c['passed'] for c in checks), 'base_commit': BASE,
              'milestone_id': body['milestone_id'], 'snapshot_sha256': identity, 'next_task': 'L01',
              'checks': checks, 'observations': observations, 'scope': body['scope'],
              'snapshot_file_sha256': sha(destination) if destination.exists() else None}
    (ROOT / 'data/reports/w04_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('W04 handoff', result['passed'], 'checks', len(checks), 'snapshot', identity)
    if not result['passed']:
        print([c for c in checks if not c['passed']])
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--freeze', action='store_true')
    raise SystemExit(main(parser.parse_args().freeze))

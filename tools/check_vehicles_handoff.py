#!/usr/bin/env python3
"""Verify saved N03 handoff source, documentation, and independent evidence bytes."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = 'data/reports/n03/snapshot.json'
OUTPUT = 'data/reports/n03_verification.json'
AUXILIARY = (
    ('support.baseline', 'data/reports/n03/support_baseline_check.json'),
    ('support.final', 'data/reports/n03/support_final_check.json'),
    ('prepared_copy.portability', 'data/reports/n03/portability.json'),
    ('source_preservation', 'data/reports/n03/source_preservation.json'),
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(prepared=False):
    checks = []

    def ck(name, passed, **details):
        checks.append({'name': name, 'passed': bool(passed), **details})

    def read(name):
        try:
            value = json.loads((ROOT / name).read_text())
            if not isinstance(value, dict):
                raise ValueError('JSON object required')
            return value
        except (OSError, ValueError) as exc:
            ck('read:' + name, False, error=str(exc))
            return {}

    def table(name, values, base=ROOT):
        ck(name + '.nonempty', isinstance(values, dict) and bool(values))
        if not isinstance(values, dict):
            return
        for relative, expected in values.items():
            path = base / relative
            ck(name + ':' + relative, path.is_file() and sha(path) == expected)

    def passed_report(name, value):
        rows = value.get('checks')
        ck(name, value.get('task') == 'N03' and value.get('passed') is True
           and isinstance(rows, list) and bool(rows)
           and all(isinstance(row, dict) and row.get('passed') is True for row in rows))

    snapshot = read(SNAPSHOT)
    ck('snapshot.identity', snapshot.get('schema_version') == 1 and snapshot.get('task') == 'N03'
       and snapshot.get('completed') is True and snapshot.get('next_task') == 'N04')
    for section in ('source_sha256', 'evidence_sha256', 'documentation_sha256'):
        table(section, snapshot.get(section))
    sources = snapshot.get('source_sha256', {})
    evidence = snapshot.get('evidence_sha256', {})
    ck('snapshot.includes_handoff_checker', isinstance(sources, dict)
       and 'tools/check_vehicles_handoff.py' in sources)
    if prepared:
        table('prepared', snapshot.get('generated_sha256'))

    required_evidence = {path for _, path in AUXILIARY}
    for mode in ('contract', 'gpu'):
        result_path = f'data/reports/n03/{mode}_check.json'
        physics_path = f'data/reports/n03/{mode}_vehicles_check.json'
        required_evidence.update((result_path, physics_path,
                                  f'data/reports/n03/{mode}.json.gz', f'data/reports/n03/{mode}.log'))
        result = read(result_path)
        passed_report(mode + '.passed', result)
        ck(mode + '.identity', result.get('mode') == mode)
        table(mode + '.engine_source', result.get('source_sha256'), ROOT / 'game')
        table(mode + '.engine_proof', result.get('proof_sha256'))
        if prepared:
            table(mode + '.engine_runtime', result.get('runtime_sha256'), ROOT / 'game')
            table(mode + '.engine_inputs', result.get('input_sha256'))
        physics = read(physics_path)
        passed_report(mode + '.independent_passed', physics)
        ck(mode + '.full_suite', any(row.get('name') == 'acceptance.full_suite' and row.get('passed') is True
           for row in physics.get('checks', []) if isinstance(row, dict)))
    for name, path in AUXILIARY:
        result = read(path)
        passed_report(name, result)
        if name.startswith('support.'):
            mode = name.removeprefix('support.')
            ck(name + '.identity', result.get('mode') == mode)
            raw_path = f'data/reports/n03/support_{mode}.json.gz'
            required_evidence.update((raw_path, f'data/reports/n03/support_{mode}.log'))
            raw = ROOT / raw_path
            ck(name + '.retained_raw_hash', raw.is_file() and sha(raw) == result.get('evidence_sha256'))
        if name == 'source_preservation':
            table(name + '.original_source', result.get('sha256'))
            ck(name + '.base_commit', bool(snapshot.get('base_commit'))
               and result.get('base_commit') == snapshot.get('base_commit'))
    ck('snapshot.includes_required_evidence', isinstance(evidence, dict)
       and required_evidence.issubset(evidence),
       missing=sorted(required_evidence - set(evidence)) if isinstance(evidence, dict) else sorted(required_evidence))
    result = {
        'task': 'N03', 'passed': all(check['passed'] for check in checks), 'checks': checks,
        'snapshot': SNAPSHOT, 'prepared_runtime_checked': prepared,
        'scope': ('Byte verification of saved N03 source, documentation, full headless/GPU traffic evidence, '
                  'baseline/final support observations, prepared-input portability, and original source preservation. '
                  'Generated runtime hashes are optional. Does not rerun Godot, recreate GIS, validate human controls, '
                  'test another Mac/M4, or accept N04 endurance or performance.'),
    }
    (ROOT / OUTPUT).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    failed = [check['name'] for check in checks if not check['passed']]
    print('N03 handoff', result['passed'], len(checks), 'checks', failed)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', action='store_true', help='Also verify regenerated local runtime/input bytes')
    raise SystemExit(main(parser.parse_args().prepared))

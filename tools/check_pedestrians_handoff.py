#!/usr/bin/env python3
"""Verify the saved N02 handoff against local source and evidence bytes."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(prepared=False):
    snapshot = json.loads((ROOT / 'data/reports/n02/snapshot.json').read_text())
    checks = [{'name': 'snapshot.identity', 'passed': snapshot['task'] == 'N02'
               and snapshot['completed'] is True and snapshot['next_task'] == 'N03'}]
    for section in ('source_sha256', 'evidence_sha256', 'documentation_sha256'):
        for name, expected in snapshot[section].items():
            path = ROOT / name
            checks.append({'name': section + ':' + name, 'passed': path.is_file() and sha(path) == expected})
    if prepared:
        for name, expected in snapshot['generated_sha256'].items():
            path = ROOT / name
            checks.append({'name': 'prepared:' + name, 'passed': path.is_file() and sha(path) == expected})
    for mode in ('contract', 'gpu'):
        result = json.loads((ROOT / f'data/reports/n02/{mode}_check.json').read_text())
        checks.append({'name': mode + '.passed', 'passed': result['passed'] is True})
        for name, expected in result['source_sha256'].items():
            path = ROOT / 'game' / name
            checks.append({'name': mode + '.engine_source:' + name,
                           'passed': path.is_file() and sha(path) == expected})
        for name, expected in result['proof_sha256'].items():
            path = ROOT / name
            checks.append({'name': mode + '.engine_proof:' + name,
                           'passed': path.is_file() and sha(path) == expected})
        if prepared:
            for name, expected in result['runtime_sha256'].items():
                path = ROOT / 'game' / name
                checks.append({'name': mode + '.engine_runtime:' + name,
                               'passed': path.is_file() and sha(path) == expected})
        physics = json.loads((ROOT / f'data/reports/n02/{mode}_pedestrian_check.json').read_text())
        checks.append({'name': mode + '.independent_passed', 'passed': physics['passed'] is True})
    portable = json.loads((ROOT / 'data/reports/n02/portability.json').read_text())
    checks.append({'name': 'prepared_copy.portability', 'passed': portable['passed'] is True})
    result = {'task': 'N02', 'passed': all(c['passed'] for c in checks), 'checks': checks,
              'snapshot': 'data/reports/n02/snapshot.json', 'prepared_runtime_checked': prepared,
              'scope': 'Byte verification of saved N02 source, documentation and engine evidence. Does not rerun Godot, validate human controls, or test M4.'}
    (ROOT / 'data/reports/n02_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    failed = [c['name'] for c in checks if not c['passed']]
    print('N02 handoff', result['passed'], len(checks), 'checks', failed)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', action='store_true', help='Also check regenerated local runtime bytes')
    raise SystemExit(main(parser.parse_args().prepared))

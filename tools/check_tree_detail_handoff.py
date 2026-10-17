#!/usr/bin/env python3
"""Validate the EXP22 shared handoff, not another Mac's engine acceptance."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', action='store_true')
    args = parser.parse_args()
    data = json.loads((ROOT / 'data/reports/tree_detail/20261018/summary.json').read_text())
    generated = {row['path'] for row in data['files'] if row['kind'] == 'generated_runtime_input'}
    failures, deferred = [], set()
    for row in data['files']:
        if row['path'] in generated and not args.prepared:
            deferred.add(row['path'])
            continue
        path = ROOT / row['path']
        if not path.is_file() or path.stat().st_size != row['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
            failures.append({'path': row['path'], 'reason': 'missing_or_changed'})
    report = json.loads((ROOT / data['current_acceptance_report']).read_text())
    if report['result'] != 'PASS' or report['summary']['failed'] != 0:
        failures.append({'reason': 'current_engine_report_not_pass'})
    for resource, expected in report['source_sha256'].items():
        path = (ROOT / 'game' / resource.removeprefix('res://')).resolve()
        if not path.is_relative_to(ROOT):
            failures.append({'path': resource, 'reason': 'source_outside_project'})
            continue
        relative = path.relative_to(ROOT).as_posix()
        if relative in generated and not args.prepared:
            deferred.add(relative)
        elif not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            failures.append({'path': relative, 'reason': 'acceptance_source_changed'})
    print(json.dumps({'result': 'FAIL' if failures else 'PASS', 'files': len(data['files']), 'deferred': sorted(deferred), 'failures': failures, 'scope': 'Stored EXP22 inputs/code/evidence integrity only; baseline and EXP21 remain historical. No engine rerun, M4/export or performance acceptance.'}, ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

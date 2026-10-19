#!/usr/bin/env python3
"""Check the shared EXP23 manifest; this does not rerun Godot on this Mac."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = ROOT / 'data/reports/street_detail/20261019/summary.json'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', action='store_true')
    args = parser.parse_args()
    data = json.loads(SUMMARY.read_text())
    generated = {row['path'] for row in data['files'] if row['kind'] == 'generated_runtime_input'}
    failures, deferred = [], set()
    for row in data['files']:
        relative = row['path']
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT):
            failures.append({'path': relative, 'reason': 'outside_project'})
        elif relative in generated and not args.prepared:
            deferred.add(relative)
        elif not path.is_file() or path.stat().st_size != row['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
            failures.append({'path': relative, 'reason': 'missing_or_changed'})
    for relative in data['current_engine_reports']:
        report_path = (ROOT / relative).resolve()
        if not report_path.is_relative_to(ROOT) or not report_path.is_file():
            failures.append({'path': relative, 'reason': 'report_missing_or_outside_project'})
            continue
        report = json.loads(report_path.read_text())
        checks = report.get('checks', [])
        if not checks or not all(row.get('passed') is True for row in checks):
            failures.append({'path': relative, 'reason': 'engine_checks_not_pass'})
        for resource, expected in report.get('source_sha256', report.get('source_hashes', {})).items():
            path = ((ROOT / 'game' / resource.removeprefix('res://')) if resource.startswith('res://') else (ROOT / resource)).resolve()
            if not path.is_relative_to(ROOT):
                failures.append({'path': resource, 'reason': 'source_outside_project'})
                continue
            source_relative = path.relative_to(ROOT).as_posix()
            if source_relative in generated and not args.prepared:
                deferred.add(source_relative)
            elif not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                failures.append({'path': source_relative, 'reason': 'acceptance_source_changed'})
    print(json.dumps({'result': 'FAIL' if failures else 'PASS', 'files': len(data['files']), 'deferred': sorted(deferred), 'failures': failures, 'scope': 'Stored EXP23 code, inputs and evidence integrity only. No engine rerun, other Mac/export, measured road accuracy or sustained performance acceptance.'}, ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

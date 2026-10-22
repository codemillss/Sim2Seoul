#!/usr/bin/env python3
"""Check a shared street-detail manifest; this does not rerun Godot."""
import argparse
import hashlib
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = ROOT / 'data/reports/real_scale/20261022/summary.json'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', action='store_true')
    parser.add_argument('--summary', type=Path, default=SUMMARY,
                        help='Manifest to check; defaults to the latest real-scale/civic revision.')
    args = parser.parse_args()
    summary = args.summary.resolve()
    if not summary.is_relative_to(ROOT) or not summary.is_file():
        parser.error('summary must be an existing project manifest')
    data = json.loads(summary.read_text())
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
        declared_pass = report.get('result') == 'PASS' or (report.get('result') is None and report.get('passed') == len(checks) and report.get('total') == len(checks))
        if not declared_pass or not checks or not all(row.get('passed') is True for row in checks):
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
    # A GDScript exception can skip a check yet leave a numeric PASS report.
    # New manifests bind an expected denominator and the unmodified engine log.
    for run in data.get('current_engine_runs', []):
        relative, log_relative = run['report'], run['log']
        report_path, log_path = (ROOT / relative).resolve(), (ROOT / log_relative).resolve()
        if not report_path.is_relative_to(ROOT) or not log_path.is_relative_to(ROOT) or not report_path.is_file() or not log_path.is_file():
            failures.append({'path': relative, 'reason': 'run_or_log_missing_or_outside_project'})
            continue
        report = json.loads(report_path.read_text())
        if len(report.get('checks', [])) != run['expected_checks']:
            failures.append({'path': relative, 'reason': 'unexpected_check_denominator'})
        for binding in run.get('input_hash_bindings', []):
            source_path = (ROOT / binding['path']).resolve()
            if not source_path.is_relative_to(ROOT) or not source_path.is_file() or hashlib.sha256(source_path.read_bytes()).hexdigest() != report.get(binding['field']):
                failures.append({'path': binding['path'], 'reason': 'component_report_input_changed'})
        raw_log = gzip.decompress(log_path.read_bytes()) if log_path.suffix == '.gz' else log_path.read_bytes()
        log_text = raw_log.decode('utf-8', errors='replace')
        if any(marker in log_text for marker in ['SCRIPT ERROR:', 'Parse Error:', 'Failed to load script']):
            failures.append({'path': log_relative, 'reason': 'engine_script_error_even_if_report_passed'})
    print(json.dumps({'result': 'FAIL' if failures else 'PASS', 'files': len(data['files']), 'deferred': sorted(deferred), 'failures': failures, 'scope': 'Stored street code, inputs and evidence integrity only. No engine rerun, other Mac/export, measured road accuracy or sustained performance acceptance.'}, ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

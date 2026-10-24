#!/usr/bin/env python3
"""Check a shared street-detail manifest; this does not rerun Godot."""
import argparse
import hashlib
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = ROOT / 'data/reports/authored_character_combat/20261024/summary.json'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepared', action='store_true')
    parser.add_argument('--summary', type=Path, default=SUMMARY,
                        help='Manifest to check; defaults to the authored character, dispatch and optional pool revision.')
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
        result = report.get('result')
        declared_pass = result == 'PASS' or (result is None and report.get('passed') == len(checks) and report.get('total') == len(checks))
        if isinstance(result, dict):
            declared_pass = result.get('status') in ('PASS', 'pass') and result.get('failed') == 0 and result.get('passed') == len(checks) and result.get('total') == len(checks)
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
        if run.get('metadata'):
            metadata_path = (ROOT / run['metadata']).resolve()
            if not metadata_path.is_relative_to(ROOT) or not metadata_path.is_file():
                failures.append({'path': relative, 'reason': 'run_metadata_missing_or_outside_project'})
            else:
                metadata = json.loads(metadata_path.read_text())
                code = next((metadata[key] for key in ('actual_returncode', 'returncode', 'actual_exit_code', 'executor_returncode') if key in metadata), None)
                if code != 0:
                    failures.append({'path': relative, 'reason': 'actual_engine_returncode_not_zero'})
                if metadata.get('source_changes_during_run'):
                    failures.append({'path': relative, 'reason': 'production_changed_during_run'})
                for source, expected in metadata.get('source_sha256', {}).items():
                    path = (ROOT / source).resolve()
                    if not path.is_relative_to(ROOT) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                        failures.append({'path': source, 'reason': 'run_start_source_binding_changed'})
        for binding in run.get('input_hash_bindings', []):
            source_path = (ROOT / binding['path']).resolve()
            if not source_path.is_relative_to(ROOT) or not source_path.is_file() or hashlib.sha256(source_path.read_bytes()).hexdigest() != report.get(binding['field']):
                failures.append({'path': binding['path'], 'reason': 'component_report_input_changed'})
        raw_log = gzip.decompress(log_path.read_bytes()) if log_path.suffix == '.gz' else log_path.read_bytes()
        log_text = raw_log.decode('utf-8', errors='replace')
        if any(marker in log_text for marker in ['SCRIPT ERROR:', 'Parse Error:', 'Failed to load script']):
            failures.append({'path': log_relative, 'reason': 'engine_script_error_even_if_report_passed'})
    # Historical acceptance remains tied to its exact old UI sources. It must
    # never be counted as a fresh run after the ordinary-OS popup correction.
    if data.get('prior_functional_cohort'):
        prior_path = (ROOT / data['prior_functional_cohort']['path']).resolve()
        if not prior_path.is_relative_to(ROOT) or not prior_path.is_file():
            failures.append({'path': str(prior_path), 'reason': 'historical_cohort_missing'})
        else:
            prior = json.loads(prior_path.read_text())
            snapshots = prior['preserved_ui_sources']
            replaced = set()
            for source, expected in prior['source_sha256_before_ui_fix'].items():
                path = (ROOT / source).resolve()
                if not path.is_relative_to(ROOT) or not path.is_file():
                    failures.append({'path': source, 'reason': 'historical_source_missing'})
                elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    snapshot = (ROOT / snapshots.get(source, '')).resolve()
                    if not snapshot.is_relative_to(ROOT) or not snapshot.is_file() or hashlib.sha256(snapshot.read_bytes()).hexdigest() != expected:
                        failures.append({'path': source, 'reason': 'historical_source_not_preserved'})
                    replaced.add(source)
            if replaced != set(data['prior_functional_cohort']['replaced_bindings']):
                failures.append({'path': str(prior_path), 'reason': 'historical_replacement_scope_changed'})
            for run in prior['runs']:
                for field, digest in [('report', 'report_sha256'), ('metadata', 'metadata_sha256')]:
                    path = (ROOT / run[field]).resolve()
                    if not path.is_relative_to(ROOT) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != run[digest]:
                        failures.append({'path': run[field], 'reason': 'historical_report_or_metadata_changed'})
    normal_path = data.get('normal_launch')
    if data.get('task') == 'EXP33_AUTHORED_CHARACTER_DISPATCH_OPTIONAL_POOL_CUSTOMIZATION':
        path = (ROOT / (normal_path or '')).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            failures.append({'path': normal_path, 'reason': 'ordinary_launch_missing'})
        else:
            normal = json.loads(path.read_text())
            if normal.get('result') != 'PASS_BOUNDED_OS' or not all(normal.get(key) for key in ['ready', 'ordinary_process_alive_at_record', 'preferences_unchanged']) or normal.get('script_errors'):
                failures.append({'path': normal_path, 'reason': 'ordinary_launch_not_accepted'})
            for source, expected in normal.get('source_sha256', {}).items():
                path = (ROOT / source).resolve()
                if not path.is_relative_to(ROOT) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    failures.append({'path': source, 'reason': 'ordinary_launch_source_changed'})
    print(json.dumps({'result': 'FAIL' if failures else 'PASS', 'files': len(data['files']), 'deferred': sorted(deferred), 'failures': failures, 'scope': 'Stored source, prepared inputs, current runs, explicitly preserved historical UI sources and bounded OS evidence integrity only. No new engine/OS run, other Mac/export, measured road accuracy or sustained performance acceptance.'}, ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()

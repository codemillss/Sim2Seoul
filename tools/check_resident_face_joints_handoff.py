#!/usr/bin/env python3
"""Read-only EXP37 saved-evidence/current-byte audit; never launch an engine.

The EXP35 Audit primitives are reused without changing its historical checker.
Both this file and that helper must be bound by the selected summary.
"""
import argparse
import json
from pathlib import Path

from check_resident_form_handoff import Audit, ROOT, SHA256, TEXT_SUFFIXES


DEFAULT_SUMMARY = 'data/reports/resident_face_joints/20261025/summary.json'
RUN_CONTRACTS = {'headless': (85, 0), 'native': (141, 44)}
POSES = {'a_pose', 'arm_raise', 'deep_squat', 'single_support'}
VIEWS = {'front', 'right', 'back', 'oblique'}
REQUIRED_CURRENT_FILES = {
    'tools/check_resident_face_joints_handoff.py',
    'tools/check_resident_form_handoff.py',
    'tools/run_resident_form_study_acceptance.py',
    'tests/game/check_resident_form_study.gd',
    'game/scripts/study/resident_form_study.gd',
    'game/scenes/study/resident_form_study.tscn',
    'art/characters/resident_form_m01.blend',
    'game/assets/original/resident_study/resident_form_m01.glb',
    'game/assets/original/resident_study/resident_form_m01.glb.import',
    'game/assets/original/resident_study/resident_form_m01_previous.glb',
    'game/assets/original/resident_study/resident_form_m01_previous.glb.import',
    'game/assets/original/resident_study/FORM_STUDY_MANIFEST.json',
    'game/assets/original/resident_study/FORM_STUDY_PREVIOUS_MANIFEST.json',
}
PREFERENCE_NAMES = {
    'sim2seoul_exploration.json', 'sim2seoul_exploration.json.time.json',
    'sim2seoul_character.json', 'sim2seoul_quality.json',
}


def positive_int(value):
    return type(value) is int and value > 0


def require_bound(audit, bindings, names, owner):
    for name in names:
        path = audit.path(str(name))
        audit.require(audit.label(path) in bindings, owner,
                      'required selected/current file missing from bound_files: '+audit.label(path))


def check_run(audit, selected):
    report_path, report = audit.load(selected['report'])
    runner_path, runner = audit.load(selected['runner'])
    label = audit.label(report_path)
    mode = runner.get('mode')
    expected, capture_count = selected['expected_checks'], selected['captures']
    audit.require(mode in RUN_CONTRACTS and
                  RUN_CONTRACTS.get(mode) == (expected, capture_count) and
                  type(expected) is int and type(capture_count) is int,
                  label, 'EXP37 requires headless85/0 and native141/44')
    checks, captures = report.get('checks', []), report.get('captures', [])
    audit.require(report.get('task') == 'EXP37_RESIDENT_FACE_JOINTS' and
                  report.get('result') == 'PASS' and isinstance(checks, list) and
                  len(checks) == expected and all(c.get('passed') is True for c in checks),
                  label, 'selected EXP37 report must contain the exact all-passed checks')
    summary = report.get('summary', {})
    audit.require(summary.get('captures') == capture_count and summary.get('checks') == expected and
                  summary.get('failed') == 0 and len(captures) == capture_count and
                  summary.get('whole_body_captures') == (32 if mode == 'native' else 0) and
                  summary.get('focused_detail_captures') == (12 if mode == 'native' else 0),
                  label, 'report denominator/whole-body/focused capture counts mismatch')
    audit.require(runner.get('task') == 'EXP37_FACE_JOINTS' and
                  runner.get('expected_checks') == runner.get('actual_checks') == expected and
                  runner.get('expected_captures') == runner.get('actual_captures') == capture_count and
                  runner.get('actual_engine_returncode') == runner.get('returncode') == 0 and
                  runner.get('engine_errors') == [] and runner.get('capture_errors') == [] and
                  runner.get('source_changes_during_run') == [], audit.label(runner_path),
                  'strict actual exit/count/capture/error/source-change gate failed')
    audit.require((mode == 'headless') == (report.get('display') == 'headless'),
                  label, 'native/headless display does not match selected mode')
    audit.hashes(runner.get('source_sha256'), audit.label(runner_path))
    snapshot = audit.path(runner['text_source_snapshot'])
    audit.require(snapshot.is_dir(), audit.label(snapshot), 'missing exact text source snapshot')
    for name, digest in runner['source_sha256'].items():
        source = audit.path(name)
        if source.suffix in TEXT_SUFFIXES:
            saved = snapshot/source.relative_to(ROOT)
            audit.snapshots_checked.add(audit.label(saved))
            audit.require(saved.is_file() and audit.sha(saved) == digest, audit.label(saved),
                          'saved text source differs from run source hash')
    audit.require(report.get('source_sha256') == report.get('source_after'), label,
                  'internal before/after source maps differ')
    audit.hashes(report.get('source_sha256'), label)
    log_paths = [report_path.with_suffix('.console.log'), report_path.with_suffix('.log')]
    audit.logs(log_paths)
    entry = next((c for c in checks if c.get('name') == 'default_is_new_original_in_separate_scene'), {})
    audit.require(entry.get('passed') is True and
                  entry.get('evidence', {}).get('entered_from_paused_menu') is True and
                  entry.get('evidence', {}).get('tree_paused_after_ready') is False,
                  label, 'actual paused-entry precondition/result missing')
    paths, whole_grid, detail_grid, paired = [], set(), set(), {}
    for capture in captures:
        image = audit.path(capture['file']);paths.append(audit.label(image))
        kind, focus = capture.get('capture_kind'), capture.get('focus')
        is_whole = kind == 'whole_body' and focus == 'whole'
        is_detail = kind == 'focused_detail' and focus in ('face', 'shoulders', 'pelvis')
        frame = capture.get('projected_frame' if is_whole else 'focus_frame', {})
        audit.require((is_whole or is_detail) and capture.get('save_error') == 0 and
                      capture.get('actual_visible_meshes', 0) > 0 and
                      capture.get('palette', {}).get('valid') is True and
                      frame.get('inside_unobscured_frame') is True and
                      frame.get('finite') is True and frame.get('referenced_vertices', 0) > 0,
                      audit.label(image), 'capture visibility/palette/selected-interest frame/save gate failed')
        if is_detail:
            audit.require(frame.get('focus') == focus and bool(frame.get('source_rest_roi')) and
                          bool(frame.get('intentional_cutoff')) and
                          capture.get('shared_focus_framing', {}).get('focus') == focus,
                          audit.label(image), 'focused capture must disclose real ROI and intentional body cutoffs')
            detail_grid.add((capture.get('model'), focus, capture.get('pose'), capture.get('view')))
        else:
            whole_grid.add((capture.get('model'), capture.get('pose'), capture.get('view')))
        comparison_key = (focus, capture.get('pose'), capture.get('view'))
        comparison = {k: capture.get(k) for k in ('camera', 'camera_fov', 'lighting_contract', 'shared_focus_framing')}
        audit.require(bool(comparison['lighting_contract']) and bool(comparison['shared_focus_framing']),
                      audit.label(image), 'actual focus camera and complete lighting readback required')
        if comparison_key in paired:
            audit.require(comparison == paired[comparison_key], audit.label(image),
                          'new/previous capture camera or actual lighting differs for same pose/focus/view')
        else:
            paired[comparison_key] = comparison
        audit.png(str(image), {'bytes': image.stat().st_size, 'sha256': capture['sha256']},
                  capture['image_size'])
        audit.source(capture['actual_glb_path'], capture['actual_glb_sha256'])
        audit.source(capture['actual_manifest_path'], capture['actual_manifest_sha256'])
    expected_whole = {(m, p, v) for m in ('new', 'previous') for p in POSES for v in VIEWS}
    detail_configs = [('face', 'a_pose', 'front'), ('face', 'a_pose', 'right'),
                      ('shoulders', 'arm_raise', 'front'), ('shoulders', 'arm_raise', 'back'),
                      ('pelvis', 'deep_squat', 'right'), ('pelvis', 'deep_squat', 'back')]
    expected_details = {(m, f, p, v) for m in ('new', 'previous') for f, p, v in detail_configs}
    audit.require(len(paths) == len(set(paths)), label, 'duplicate capture paths')
    audit.require(whole_grid == (expected_whole if mode == 'native' else set()) and
                  detail_grid == (expected_details if mode == 'native' else set()),
                  label, 'expected 32 whole-body and 12 distinct focused native captures required')
    observations = report.get('focus_observations', [])
    audit.require(isinstance(observations, list) and len(observations) == 12 and
                  {(r.get('model'), r.get('configuration', {}).get('focus'),
                    r.get('configuration', {}).get('pose'), r.get('configuration', {}).get('view'))
                   for r in observations} == expected_details,
                  label, 'all twelve measured focus configurations must exist in both modes')
    return {'mode': mode, 'expected_checks': expected, 'captures': capture_count,
            'report': label, 'runner': audit.label(runner_path),
            'report_sha256': audit.sha(report_path), 'runner_sha256': audit.sha(runner_path),
            'capture_paths': paths, 'log_paths': [audit.label(p) for p in log_paths]}


def check_export(audit, name, counts):
    path, data = audit.load(name);label = audit.label(path)
    checks = data.get('checks', [])
    total, passed = data.get('total'), data.get('passed')
    audit.require(data.get('status') == 'PASS' and positive_int(total) and
                  type(passed) is int and passed == total == len(checks) and
                  all(c.get('passed') is True for c in checks), label,
                  'export audit status/passed/total/exact all-passed checks disagree')
    audit.require(counts.get('independent_glb_checks') == total, label,
                  'summary independent_glb_checks differs from actual export audit total')
    before, after = data.get('bound_files_before'), data.get('bound_files_after')
    audit.require(isinstance(before, dict) and bool(before) and before == after, label,
                  'export audit input before/after bindings differ or are absent')
    for source, binding in before.items():
        audit.file(source, binding)
    # No vertex, face, candidate version or fixed27-check target is imposed.
    # The independent reviewer can add criteria; its declared current total
    # must agree with the checks and selected summary.
    audit.require(data.get('art_acceptance', data.get('full_art_target_met')) is False,
                  label, 'export audit must retain explicit art-unaccepted scope')
    return set(before)


def check_normal(audit, name, counts):
    path, data = audit.load(name);label = audit.label(path)
    audit.require(data.get('status') == 'PASS' and data.get('process_alive_at_record') is True and
                  data.get('game_ready') is True and data.get('engine_errors') == [],
                  label, 'root ordinary OS record readiness/error contract failed')
    audit.hashes(data.get('source_sha256'), label)
    before, after = data.get('preferences_before'), data.get('preferences_after')
    audit.require(isinstance(before, dict) and set(before) == PREFERENCE_NAMES and before == after and
                  data.get('preferences_unchanged') is True, label,
                  'all four recorded preference states must remain exactly equal')
    for preference, state in before.items():
        audit.require(type(state.get('exists')) is bool and (state['exists'] is False or
                      (type(state.get('bytes')) is int and state['bytes'] >= 0 and
                       isinstance(state.get('sha256'), str) and bool(SHA256.fullmatch(state['sha256'])))),
                      preference, 'malformed recorded preference existence/size/hash')
    extra_records = set()
    for suffix, recorded in [('before', before), ('after', after)]:
        saved_path = path.with_name('user_preferences_'+suffix+'.json')
        if saved_path.exists():
            _, saved = audit.load(str(saved_path))
            audit.require(saved == recorded, audit.label(saved_path),
                          'saved preference snapshot differs from root OS record')
            extra_records.add(audit.label(saved_path))
    screenshots = data.get('screenshots', {})
    expected = counts.get('actual_os_jpeg')
    audit.require(positive_int(expected) and isinstance(screenshots, dict) and len(screenshots) == expected,
                  label, 'root OS screenshot count differs from summary actual_os_jpeg')
    for image, binding in screenshots.items():
        audit.os_image(image, binding)
    actions = data.get('actual_os_actions', [])
    audit.require(isinstance(actions, list) and bool(actions) and
                  all(isinstance(s, str) and s.strip() for s in actions),
                  label, 'root ordinary OS action record is missing')
    logs = data.get('logs', {})
    audit.require(isinstance(logs, dict) and len(logs) == 2, label,
                  'two immutable ordinary OS log bindings required')
    for log, binding in logs.items():
        audit.file(log, binding)
    audit.logs(list(logs))
    audit.require(data.get('art_acceptance') is False and data.get('continuous_motion_acceptance') is False and
                  data.get('normal_game_avatar_replaced') is False, label,
                  'ordinary OS record must retain art/motion/production replacement limits')
    return {'path': label, 'sha256': audit.sha(path),
            'required_records': set(screenshots) | set(logs) | extra_records}


def check_visual(audit, name, runs, normal):
    path, data = audit.load(name);label = audit.label(path)
    disposition = data.get('disposition', {})
    audit.require(data.get('current_selection') is True and disposition.get('art_acceptance') is False and
                  disposition.get('fully_realistic_character') is False and
                  disposition.get('continuous_motion_acceptance') is False,
                  label, 'visual review must preserve current prototype/art-unaccepted status')
    by_mode = {r['mode']: r for r in runs}
    expected_images = sum(r['captures'] for r in runs)
    counts = data.get('counts', {})
    audit.require(counts.get('headless_checks') == by_mode.get('headless', {}).get('expected_checks') and
                  counts.get('native_checks') == by_mode.get('native', {}).get('expected_checks') and
                  counts.get('native_original_pngs') == counts.get('actually_opened_current_original_pngs') == expected_images and
                  counts.get('whole_body_original_pngs') == 32 and counts.get('focused_detail_original_pngs') == 12,
                  label, 'visual review denominators differ from selected runs')
    audit.hashes(data.get('current_source_sha256'), label)
    expected_paths = {p for r in runs for p in r['capture_paths']}
    opened = data.get('actual_opened_original_files', []);actual_paths = set()
    opened_flags = ('actual_original_opened_in_this_review', 'opened_actual_original',
                    'actual_original_opened_in_current_review')
    for row in opened:
        image = audit.path(row['file']);actual_paths.add(audit.label(image))
        audit.require(any(row.get(flag) is True for flag in opened_flags), audit.label(image),
                      'current original is not explicitly recorded as actually opened')
        audit.png(str(image), {'bytes': image.stat().st_size, 'sha256': row['sha256']})
    audit.require(len(opened) == len(actual_paths) == expected_images and actual_paths == expected_paths,
                  label, 'visual review must bind every selected native original exactly once')
    bindings = {r['mode']: r for r in data.get('run_bindings', [])}
    audit.require(set(bindings) == set(by_mode), label, 'visual run binding modes differ from selection')
    for run in runs:
        saved = bindings.get(run['mode'], {})
        audit.require(saved.get('report_sha256') == run['report_sha256'] and
                      saved.get('wrapper_sha256') == run['runner_sha256'], label,
                      'visual report/runner hash differs from selected '+run['mode'])
    os_review = data.get('ordinary_os_root_record_review', {})
    audit.require(normal is not None and os_review.get('record_sha256') == normal['sha256'] and
                  audit.label(audit.path(os_review.get('record'))) == normal['path'], label,
                  'visual root-OS record reference/hash differs from selected ordinary record')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summary', default=DEFAULT_SUMMARY,
                        help='Repository-relative saved EXP37 summary')
    args = parser.parse_args();audit = Audit();runs = [];extra_records = set()
    loaded = audit.section(args.summary, lambda: audit.load(args.summary))
    if loaded:
        summary_path, summary = loaded;label = audit.label(summary_path)
        bindings = summary.get('bound_files', {})
        audit.require(isinstance(bindings, dict) and bool(bindings), label, 'nonempty bound_files required')
        if not isinstance(bindings, dict): bindings = {}
        audit.require(label not in bindings, label, 'summary must not bind its own hash')
        for name, binding in bindings.items():
            audit.section(name, lambda n=name, b=binding: audit.file(n, b))
        audit.require(summary.get('art_acceptance') is False, label, 'summary art_acceptance must be false')
        rows = summary.get('selected_runs', [])
        audit.require(isinstance(rows, list) and len(rows) == 2, label,
                      'exactly one selected headless and one native run required')
        if isinstance(rows, list):
            for row in rows:
                run = audit.section(str(row.get('report', label)) if isinstance(row, dict) else label,
                                    lambda r=row: check_run(audit, r))
                if run: runs.append(run)
        audit.require(len(runs) == 2 and {r['mode'] for r in runs} == set(RUN_CONTRACTS),
                      label, 'selected run modes incomplete or duplicated')
        counts = summary.get('counts', {})
        audit.require(isinstance(counts, dict), label, 'summary counts must be an object')
        if not isinstance(counts, dict): counts = {}
        audit.require(counts.get('engine_runs') == len(runs) == 2 and
                      counts.get('overlapping_engine_assertions') == sum(r['expected_checks'] for r in runs) and
                      counts.get('native_original_png') == sum(r['captures'] for r in runs) and
                      counts.get('whole_body_original_png') == 32 and counts.get('focused_detail_original_png') == 12,
                      label, 'summary engine/assertion/native capture totals disagree with selected metadata')
        export_inputs = audit.section(str(summary.get('export_audit_file', label)),
                                      lambda: check_export(audit, summary['export_audit_file'], counts))
        if export_inputs: extra_records.update(export_inputs)
        normal = audit.section(str(summary.get('normal_launch_file', label)),
                               lambda: check_normal(audit, summary['normal_launch_file'], counts))
        if normal: extra_records.update(normal['required_records'])
        audit.section(str(summary.get('visual_review_file', label)),
                      lambda: check_visual(audit, summary['visual_review_file'], runs, normal))
        required = REQUIRED_CURRENT_FILES | extra_records | audit.sources_checked | audit.snapshots_checked
        required |= audit.pngs_checked | audit.os_screenshots_checked
        for key in ('export_audit_file', 'normal_launch_file', 'visual_review_file'):
            value = summary.get(key)
            audit.require(isinstance(value, str) and bool(value), label, key+' must be a nonempty path')
            if isinstance(value, str) and value: required.add(value)
        required |= {r[k] for r in runs for k in ('report', 'runner')}
        required |= {p for r in runs for p in r['log_paths']}
        audit.section(label, lambda: require_bound(audit, bindings, required, label))
    print(json.dumps({'result': 'FAIL' if audit.failures else 'PASS',
                      'files_checked': len(audit.files_checked),
                      'current_source_files_checked': len(audit.sources_checked),
                      'source_snapshots_checked': len(audit.snapshots_checked),
                      'native_pngs_checked': len(audit.pngs_checked),
                      'os_jpegs_checked': len(audit.os_screenshots_checked),
                      'selected_runs': [{'mode': r['mode'], 'checks': r['expected_checks'], 'captures': r['captures']} for r in runs],
                      'failures': audit.failures,
                      'scope': 'Saved evidence integrity/current bytes only. No engine, gameplay or OS input is rerun. Root OS evidence is checked as a saved record; human realism/art/continuous-motion quality is not accepted.'},
                     ensure_ascii=False))
    raise SystemExit(1 if audit.failures else 0)


if __name__ == '__main__':
    main()

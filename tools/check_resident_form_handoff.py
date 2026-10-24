#!/usr/bin/env python3
"""Verify saved EXP35 evidence and current bytes; never launch an engine."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUMMARY = 'data/reports/resident_form_study/20261025/summary.json'
TEXT_SUFFIXES = {'.py', '.gd', '.tscn', '.import', '.json', '.godot'}
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
SHA256 = re.compile(r'^[0-9a-f]{64}$')
ERROR_MARKERS = ('ERROR:', 'Parse Error:', 'Failed to load script')


class Audit:
    def __init__(self):
        self.failures = []
        self.files_checked = set()
        self.pngs_checked = set()
        self.os_screenshots_checked = set()
        self.sources_checked = set()
        self.snapshots_checked = set()

    def require(self, condition, path, reason):
        if not condition:
            self.failures.append({'path': str(path), 'reason': reason})
        return bool(condition)

    def path(self, value):
        if not isinstance(value, str) or not value:
            raise ValueError('nonempty file path required')
        if value.startswith('res://'):
            value = str(ROOT/'game'/value[6:])
        path = Path(value)
        path = (path if path.is_absolute() else ROOT/path).resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError('evidence path escapes repository: '+value)
        return path

    def label(self, path):
        return str(path.relative_to(ROOT))

    def load(self, value):
        path = self.path(value)
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            raise ValueError('JSON object required: '+self.label(path))
        return path, data

    def sha(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def file(self, name, expected):
        path = self.path(name);label = self.label(path)
        self.files_checked.add(label)
        if not self.require(isinstance(expected, dict), label, 'file binding must contain bytes and sha256'):
            return path
        if not self.require(path.is_file(), label, 'missing bound file'):
            return path
        self.require(type(expected.get('bytes')) is int and expected['bytes'] >= 0 and
                     path.stat().st_size == expected['bytes'], label, 'byte length differs from recorded binding')
        digest = expected.get('sha256')
        self.require(isinstance(digest, str) and bool(SHA256.fullmatch(digest)) and
                     self.sha(path) == digest, label, 'SHA256 differs from recorded binding')
        return path

    def source(self, name, expected):
        path = self.path(name);label = self.label(path)
        self.sources_checked.add(label)
        self.require(path.is_file() and isinstance(expected, str) and bool(SHA256.fullmatch(expected)) and
                     self.sha(path) == expected, label, 'current source SHA256 differs from run')
        return path

    def png(self, name, expected, dimensions=None):
        path = self.file(name, expected);label = self.label(path)
        if not path.is_file():
            return
        self.pngs_checked.add(label)
        data = path.read_bytes()
        valid = len(data) >= 33 and data[:8] == PNG_SIGNATURE and data[12:16] == b'IHDR' and struct.unpack_from('>I', data, 8)[0] == 13
        if not self.require(valid, label, 'invalid PNG signature or IHDR'):
            return
        width, height = struct.unpack_from('>II', data, 16)
        self.require(width > 0 and height > 0, label, 'PNG has empty dimensions')
        if dimensions is not None:
            self.require(dimensions == [width, height], label, 'PNG dimensions differ from report')

    def os_image(self, name, expected):
        """Preserve CUA's actual JPEG bytes; native captures remain strict PNG."""
        path = self.path(name);label = self.label(path)
        self.os_screenshots_checked.add(label)
        path = self.file(name, expected)
        if not path.is_file():
            return
        data = path.read_bytes()
        if not self.require(path.suffix.lower() in ('.jpg', '.jpeg') and data[:2] == b'\xff\xd8' and
                            data[-2:] == b'\xff\xd9', label, 'OS screenshot extension/signature must match actual JPEG bytes'):
            return
        offset, dimensions = 2, None
        while offset < len(data):
            if data[offset] != 0xff:
                raise ValueError('Malformed JPEG marker: '+label)
            while offset < len(data) and data[offset] == 0xff:
                offset += 1
            marker = data[offset];offset += 1
            if marker in (0xd9, 0xda):
                break
            if marker == 0x01 or 0xd0 <= marker <= 0xd8:
                continue
            length = struct.unpack_from('>H', data, offset)[0]
            if length < 2 or offset+length > len(data):
                raise ValueError('Truncated JPEG segment: '+label)
            if marker in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
                height, width = struct.unpack_from('>HH', data, offset+3)
                dimensions = (width, height)
            offset += length
        self.require(dimensions is not None and all(n > 0 for n in dimensions), label, 'JPEG screenshot lacks valid SOF dimensions')

    def hashes(self, values, owner):
        if not self.require(isinstance(values, dict) and bool(values), owner, 'nonempty source_sha256 map required'):
            return
        for name, digest in values.items():
            self.source(name, digest)

    def logs(self, names):
        for name in names:
            path = self.path(str(name));label = self.label(path)
            if not self.require(path.is_file(), label, 'missing strict engine log'):
                continue
            errors = [line for line in path.read_text(errors='replace').splitlines() if any(marker in line for marker in ERROR_MARKERS)]
            self.require(not errors, label, 'strict engine log contains error markers: '+repr(errors[:3]))

    def section(self, name, function):
        try:
            return function()
        except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError, struct.error) as error:
            self.failures.append({'path': name, 'reason': str(error)})
            return None


def check_run(audit, row):
    report_path, report = audit.load(row['report'])
    runner_path, runner = audit.load(row['runner'])
    label = audit.label(report_path)
    expected = row['expected_checks'];expected_captures = row['captures']
    mode = runner.get('mode')
    audit.require((mode, expected, expected_captures) in [('headless', 56, 0), ('native', 71, 11)] and
                  type(expected) is int and type(expected_captures) is int, label, 'selected run must be exact headless56/0 or native71/11 cohort')
    checks, captures = report.get('checks', []), report.get('captures', [])
    audit.require(report.get('result') == 'PASS' and len(checks) == expected and
                  all(c.get('passed') is True for c in checks), label, 'report must contain the exact all-passed checks')
    audit.require(report.get('summary') == {'captures': expected_captures, 'checks': expected, 'failed': 0} and
                  len(captures) == expected_captures, label, 'actual summary/capture count differs from selected denominator')
    audit.require(runner.get('expected_checks') == runner.get('actual_checks') == expected and
                  runner.get('actual_engine_returncode') == runner.get('returncode') == 0 and
                  runner.get('engine_errors') == [] and runner.get('source_changes_during_run') == [],
                  audit.label(runner_path), 'strict runner exit/count/errors/source-change contract failed')
    audit.hashes(runner.get('source_sha256'), audit.label(runner_path))
    snapshot = audit.path(runner['text_source_snapshot'])
    audit.require(snapshot.is_dir(), audit.label(snapshot), 'missing source snapshot directory')
    for name, digest in runner['source_sha256'].items():
        source = audit.path(name)
        if source.suffix in TEXT_SUFFIXES:
            saved = snapshot/source.relative_to(ROOT)
            audit.snapshots_checked.add(audit.label(saved))
            audit.require(saved.is_file() and audit.sha(saved) == digest, audit.label(saved), 'text snapshot differs from exact run source')
    audit.require(report.get('source_sha256') == report.get('source_after'), label, 'internal source before/after differs')
    audit.hashes(report.get('source_sha256'), label)
    # The report itself also binds original avatar adapter inputs that the
    # wrapper does not load; both independent source maps remain required.
    audit.logs([report_path.with_suffix('.console.log'), report_path.with_suffix('.log')])
    paths = []
    for capture in captures:
        path = audit.path(capture['file']);paths.append(audit.label(path))
        audit.require(capture.get('save_error') == 0, audit.label(path), 'capture save reported an error')
        audit.png(str(path), {'bytes': path.stat().st_size, 'sha256': capture['sha256']}, capture['image_size'])
        audit.source(capture['actual_glb_path'], capture['actual_glb_sha256'])
    audit.require(len(paths) == len(set(paths)), label, 'capture paths are duplicated')
    return {'mode': mode, 'expected_checks': expected, 'captures': expected_captures,
            'report': audit.label(report_path), 'runner': audit.label(runner_path),
            'report_sha256': audit.sha(report_path), 'runner_sha256': audit.sha(runner_path),
            'capture_paths': paths}


def check_export(audit, name):
    path, data = audit.load(name);label = audit.label(path)
    checks = data.get('checks', [])
    audit.require(data.get('status') == 'PASS' and data.get('passed') == data.get('total') == len(checks) == 27 and
                  all(c.get('passed') is True for c in checks), label, 'export audit must be actual27/27')
    before, after = data.get('bound_files_before'), data.get('bound_files_after')
    audit.require(isinstance(before, dict) and bool(before) and before == after, label, 'export audit input bindings changed or missing')
    for name, binding in before.items():
        audit.file(name, binding)
    subdivision = data.get('subdivision_contract', {})
    audit.require(subdivision.get('selected_candidate') == 'v04' and subdivision.get('level') == 2 and
                  subdivision.get('same_level_2_support_render_export') is True and
                  sum(p['vertices'] for p in data.get('primitives', [])) == 53654,
                  label, 'selected v04 level2/53654-vertex export contract differs')
    audit.require(data.get('full_art_target_met') is False, label, 'export file must preserve art-unaccepted scope')


def check_normal(audit, name):
    path, data = audit.load(name);label = audit.label(path)
    audit.require(data.get('status') == 'PASS' and data.get('process_alive_at_record') is True and
                  data.get('game_ready') is True and data.get('engine_errors') == [], label, 'ordinary saved launch readiness/error contract failed')
    audit.hashes(data.get('source_sha256'), label)
    before, after = data.get('preferences_before'), data.get('preferences_after')
    expected_names = {'sim2seoul_exploration.json', 'sim2seoul_exploration.json.time.json', 'sim2seoul_character.json', 'sim2seoul_quality.json'}
    audit.require(isinstance(before, dict) and set(before) == expected_names and before == after and
                  data.get('preferences_unchanged') is True, label, 'all four recorded preference states must remain exactly equal')
    for preference, state in before.items():
        audit.require(type(state.get('exists')) is bool and (state['exists'] is False or
                      (type(state.get('bytes')) is int and state['bytes'] >= 0 and isinstance(state.get('sha256'), str) and bool(SHA256.fullmatch(state['sha256'])))),
                      preference, 'invalid recorded preference existence/size/hash state')
    for suffix, recorded in [('before', before), ('after', after)]:
        saved_path, saved = audit.load(str(path.with_name('user_preferences_'+suffix+'.json')))
        audit.require(saved == recorded, audit.label(saved_path), 'preference snapshot differs from ordinary OS record')
    screenshots = data.get('screenshots', {})
    required = {'menu_entry', 'new_front', 'new_squat_side', 'new_arm_raise_front',
                'previous_original_front', 'previous_original_back', 'returned_world', 'final_open_oblique'}
    audit.require(isinstance(screenshots, dict) and len(screenshots) == 8 and {Path(n).stem for n in screenshots} == required,
                  label, 'ordinary OS record must bind all eight entry/control/return/reentry screenshots')
    for name, binding in screenshots.items():
        audit.os_image(name, binding)
    actions = data.get('actual_os_actions', [])
    audit.require(isinstance(actions, list) and len(actions) >= 7 and all(isinstance(s, str) and s.strip() for s in actions),
                  label, 'ordinary OS action record incomplete')
    logs = data.get('logs', {})
    audit.require(isinstance(logs, dict) and len(logs) == 2, label, 'two immutable ordinary OS logs required')
    for name, binding in logs.items():
        audit.file(name, binding)
    audit.logs(list(logs))
    audit.require(data.get('art_acceptance') is False and data.get('continuous_motion_acceptance') is False and
                  data.get('normal_game_avatar_replaced') is False, label, 'ordinary record must preserve art/motion/production replacement limits')


def check_visual(audit, name, runs):
    path, data = audit.load(name);label = audit.label(path)
    disposition = data.get('disposition', {})
    audit.require(data.get('current_selection') is True and disposition.get('art_acceptance') is False and
                  disposition.get('fully_realistic_character') is False and disposition.get('continuous_motion_acceptance') is False,
                  label, 'visual record must retain current prototype/art-unaccepted status')
    audit.require(data.get('counts', {}).get('headless_checks') == 56 and data['counts'].get('native_checks') == 71 and
                  data['counts'].get('native_original_pngs') == data['counts'].get('actually_opened_current_original_pngs') == 11,
                  label, 'visual review counts do not match selected final cohort')
    audit.hashes(data.get('current_source_sha256'), label)
    expected = {name for run in runs for name in run['capture_paths']}
    opened = data.get('actual_opened_original_files', [])
    actual = set()
    for row in opened:
        image = audit.path(row['file']);actual.add(audit.label(image))
        audit.require(row.get('actual_original_opened_in_this_final02_review') is True, audit.label(image), 'current original not recorded as directly opened')
        audit.png(str(image), {'bytes': image.stat().st_size, 'sha256': row['sha256']})
    audit.require(len(opened) == 11 and actual == expected, label, 'visual review does not bind all11 selected native originals')
    bindings = {row['mode']: row for row in data.get('run_bindings', [])}
    for run in runs:
        saved = bindings.get(run['mode'], {})
        audit.require(saved.get('report_sha256') == run['report_sha256'] and saved.get('wrapper_sha256') == run['runner_sha256'],
                      label, 'visual review report/runner hashes differ from selected '+run['mode'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summary', default=DEFAULT_SUMMARY, help='Repository-relative saved EXP35 summary')
    args = parser.parse_args();audit = Audit()
    loaded = audit.section(args.summary, lambda: audit.load(args.summary))
    runs = []
    if loaded:
        summary_path, summary = loaded;label = audit.label(summary_path)
        bindings = summary.get('bound_files')
        audit.require(isinstance(bindings, dict) and bool(bindings), label, 'nonempty bound_files map required')
        if isinstance(bindings, dict):
            audit.require(label not in bindings, label, 'summary must not contain its own hash')
            for name, binding in bindings.items():
                audit.section(name, lambda n=name, b=binding: audit.file(n, b))
        audit.require(summary.get('art_acceptance') is False, label, 'summary art_acceptance must remain false')
        rows = summary.get('selected_runs', [])
        audit.require(isinstance(rows, list) and len(rows) == 2, label, 'exactly headless and native selected_runs required')
        if isinstance(rows, list):
            for row in rows:
                run = audit.section(str(row.get('report', label)) if isinstance(row, dict) else label,
                                    lambda r=row: check_run(audit, r))
                if run:
                    runs.append(run)
        audit.require({r['mode'] for r in runs} == {'headless', 'native'}, label, 'selected modes incomplete or duplicated')
        for key, function in [('export_audit_file', check_export), ('normal_launch_file', check_normal)]:
            audit.section(str(summary.get(key, label)), lambda k=key, f=function: f(audit, summary[k]))
        audit.section(str(summary.get('visual_review_file', label)), lambda: check_visual(audit, summary['visual_review_file'], runs))
        required_records = [summary.get(k) for k in ('export_audit_file', 'normal_launch_file', 'visual_review_file')]
        required_records += [r[k] for r in runs for k in ('report', 'runner')]
        if isinstance(bindings, dict):
            for name in required_records:
                if name:
                    audit.section(str(name), lambda n=name: audit.require(audit.label(audit.path(n)) in bindings, n, 'selected record missing from summary bound_files'))
    print(json.dumps({'result': 'FAIL' if audit.failures else 'PASS', 'files_checked': len(audit.files_checked),
                      'current_source_files_checked': len(audit.sources_checked), 'source_snapshots_checked': len(audit.snapshots_checked),
                      'pngs_checked': len(audit.pngs_checked), 'os_screenshots_checked': len(audit.os_screenshots_checked),
                      'selected_runs': [{'mode': r['mode'], 'checks': r['expected_checks'], 'captures': r['captures']} for r in runs],
                      'failures': audit.failures,
                      'scope': 'Saved evidence integrity and current file hashes only. Does not launch Godot/Blender, rerun gameplay, prove ordinary input independently, or accept human/art quality.'}, ensure_ascii=False))
    raise SystemExit(1 if audit.failures else 0)


if __name__ == '__main__':
    main()

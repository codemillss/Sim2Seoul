"""Tiny synthetic sites only; never reads or changes a real export."""
import gzip
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[2] / 'tools/rechunk_web_asset.py'
SPEC = importlib.util.spec_from_file_location('rechunk_asset', SOURCE)
MODULE = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MODULE)


class RechunkTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve(); site = root / 'site'; dist = site / 'dist'
        (dist / 'game').mkdir(parents=True); (dist / 'chunks').mkdir()
        manifest = {'webRelease': 'before', 'chunkBytes': 32, 'engineVersion': '4.7.2', 'buildCommit': 'test', 'files': {}}
        for kind, pieces in [('wasm', [b'\0asm' * 8]), ('pck', [bytes(range(i, i + 32)) for i in (0, 32, 64)])]:
            rows = []
            for index, raw in enumerate(pieces):
                path = f'chunks/{kind}-{index}-{MODULE.sha(raw)[:16]}.gz'; packed = gzip.compress(raw, compresslevel=6, mtime=0)
                (dist / path).write_bytes(packed)
                rows.append({'path': path, 'bytes': len(raw), 'transferBytes': len(packed), 'sha256': MODULE.sha(raw), 'encoding': 'gzip'})
            manifest['files'][kind] = {'path': 'game/index.' + kind, 'bytes': sum(map(len, pieces)), 'sha256': MODULE.sha(b''.join(pieces)), 'chunks': rows}
        (dist / 'game/manifest.json').write_text(json.dumps(manifest))
        (dist / 'chunks/unrelated.gz').write_bytes(b'unrelated generated evidence')
        return site, dist, manifest, root / 'report.json'

    @staticmethod
    def snapshot(dist):
        return {str(path.relative_to(dist)): path.read_bytes() for path in dist.rglob('*') if path.is_file()}

    def reject_unchanged(self, site, dist, chunk, report, part_bytes=16, release='delivery01'):
        before = self.snapshot(dist)
        with self.assertRaises((ValueError, OSError, EOFError)):
            MODULE.rechunk(site, chunk, part_bytes, release, report)
        self.assertEqual(before, self.snapshot(dist))

    def test_first_middle_last_preserve_every_other_row_url_and_byte(self):
        for index in range(3):
            with self.subTest(index=index):
                site, dist, original, report = self.fixture(); target = original['files']['pck']['chunks'][index]['path']
                before = self.snapshot(dist); old_rows = original['files']['pck']['chunks']
                result = MODULE.rechunk(site, target, 16, 'delivery01', report)
                updated = json.loads((dist / 'game/manifest.json').read_bytes())
                replacement_rows = [{key: value for key, value in part.items() if key != 'compressed_sha256'} for part in result['replacements']]
                self.assertEqual(old_rows[:index] + replacement_rows + old_rows[index + 1:], updated['files']['pck']['chunks'])
                self.assertEqual(original['files']['wasm'], updated['files']['wasm'])
                self.assertEqual(result['whole_files_before'], MODULE.verify(dist, updated)[0])
                for kind in ('wasm', 'pck'):
                    expected = b''.join(gzip.decompress(before[part['path']]) for part in original['files'][kind]['chunks'])
                    actual = b''.join(gzip.decompress((dist / part['path']).read_bytes()) for part in updated['files'][kind]['chunks'])
                    self.assertEqual(expected, actual)
                self.assertEqual(2, len(result['replacements'])); self.assertFalse((dist / target).exists())
                for path, content in before.items():
                    if path not in (target, 'game/manifest.json'): self.assertEqual(content, (dist / path).read_bytes())
                self.assertEqual(result, json.loads(report.read_bytes()))
                self.assertEqual(MODULE.sha(before['game/manifest.json']), result['previous_manifest_sha256'])
                self.assertEqual(MODULE.sha((dist / 'game/manifest.json').read_bytes()), result['new_manifest_sha256'])

    def test_corrupt_target_non_target_and_whole_hash_fail_before_writes(self):
        for mode in ('target', 'other', 'whole'):
            site, dist, manifest, report = self.fixture(); target = manifest['files']['pck']['chunks'][0]['path']
            if mode == 'whole':
                manifest['files']['wasm']['sha256'] = '0' * 64; (dist / 'game/manifest.json').write_text(json.dumps(manifest))
            else:
                path = dist / (target if mode == 'target' else manifest['files']['wasm']['chunks'][0]['path'])
                path.write_bytes(path.read_bytes()[:-1])
            self.reject_unchanged(site, dist, target, report)

    def test_path_release_size_and_missing_target_validation(self):
        site, dist, manifest, report = self.fixture(); target = manifest['files']['pck']['chunks'][0]['path']
        for bad in ('../x.gz', '/chunks/x.gz', 'chunks/../x.gz', 'chunks\\x.gz', 'https://x/x.gz', 'chunks/x.gz?x', 'chunks/x.gz#x', 'chunks/missing.gz'):
            self.reject_unchanged(site, dist, bad, report)
        for bad in ('../escape', 'bad/release', '', 'bad.release'):
            self.reject_unchanged(site, dist, target, report, release=bad)
        for bad in (0, -1, True, 1, 32, 64):
            self.reject_unchanged(site, dist, target, report, part_bytes=bad)
        self.reject_unchanged(site, dist, target, dist / 'oops.json')

    def test_duplicate_target_symlink_and_output_collision_fail_without_changes(self):
        for mode in ('duplicate', 'symlink', 'collision'):
            site, dist, manifest, report = self.fixture(); target = manifest['files']['pck']['chunks'][0]['path']
            if mode == 'duplicate':
                manifest['files']['pck']['chunks'].append(manifest['files']['pck']['chunks'][0].copy()); (dist / 'game/manifest.json').write_text(json.dumps(manifest))
            elif mode == 'symlink':
                outside = report.parent / 'outside.gz'; outside.write_bytes((dist / target).read_bytes()); (dist / target).unlink(); (dist / target).symlink_to(outside)
            else:
                raw = gzip.decompress((dist / target).read_bytes())[:16]
                name = f'{Path(target).stem}-part0-{MODULE.sha(raw)[:16]}.gz'
                (dist / 'chunks' / name).write_bytes(b'collision')
            self.reject_unchanged(site, dist, target, report)

    def test_manifest_replace_failure_retains_original_and_removes_only_new_parts(self):
        site, dist, manifest, report = self.fixture(); target = manifest['files']['pck']['chunks'][0]['path']
        before = self.snapshot(dist)
        with mock.patch.object(MODULE.os, 'replace', side_effect=OSError('injected atomic replace failure')):
            with self.assertRaises(OSError): MODULE.rechunk(site, target, 16, 'delivery01', report)
        self.assertEqual(before, self.snapshot(dist)); self.assertFalse(report.exists())

    def test_second_part_write_failure_cleans_only_the_created_first_part(self):
        site, dist, manifest, report = self.fixture(); target = manifest['files']['pck']['chunks'][0]['path']
        before = self.snapshot(dist); original_open = Path.open
        def fail_second(path, *args, **kwargs):
            if args and args[0] == 'xb' and '-part1-' in path.name:
                raise OSError('injected second part write failure')
            return original_open(path, *args, **kwargs)
        with mock.patch.object(Path, 'open', fail_second):
            with self.assertRaises(OSError): MODULE.rechunk(site, target, 16, 'delivery01', report)
        self.assertEqual(before, self.snapshot(dist)); self.assertFalse(report.exists())


if __name__ == '__main__':
    unittest.main()

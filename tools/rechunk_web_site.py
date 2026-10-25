#!/usr/bin/env python3
"""Split an already checked Godot export without rebuilding or changing it."""
import argparse, datetime, hashlib, json, shutil
from pathlib import Path
from build_web_site import ROOT, WEB_CHUNK_BYTES, chunk_file, digest

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--site', type=Path, required=True)
    parser.add_argument('--export', dest='export_dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--release', required=True)
    args = parser.parse_args()
    site = args.site.resolve()
    report = args.report.resolve()
    assert not report.exists(), 'Preserve earlier evidence; choose a fresh report.'
    manifest_path = site / 'dist/game/manifest.json'
    previous = manifest_path.read_bytes()
    manifest = json.loads(previous)
    # The old whole-file hashes identify the already-validated game bytes.
    for kind in ('wasm', 'pck'):
        path = args.export_dir / ('index.' + kind)
        assert digest(path) == manifest['files'][kind]['sha256'], kind
        assert path.stat().st_size == manifest['files'][kind]['bytes'], kind
    chunks = site / 'dist/chunks'
    manifest['chunkBytes'] = WEB_CHUNK_BYTES
    manifest['webRelease'] = args.release
    for kind in ('wasm', 'pck'):
        manifest['files'][kind] = chunk_file(args.export_dir / ('index.' + kind), kind, chunks)
    desired = {Path(c['path']).name for f in manifest['files'].values() for c in f['chunks']}
    # Remove obsolete generated chunks only after all replacement chunks exist.
    for path in chunks.glob('*.gz'):
        if path.name not in desired:
            path.unlink()
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    row = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'release': args.release, 'chunk_bytes': WEB_CHUNK_BYTES,
           'unchanged_game_bytes': True, 'previous_manifest_sha256': hashlib.sha256(previous).hexdigest(),
           'new_manifest_sha256': digest(manifest_path), 'files': manifest['files'],
           'total_chunks': len(desired),
           'transfer_bytes': sum(c['transferBytes'] for f in manifest['files'].values() for c in f['chunks']),
           'largest_transfer_bytes': max(c['transferBytes'] for f in manifest['files'].values() for c in f['chunks'])}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(row, indent=2) + '\n')
    report.with_name(report.stem + '_previous_manifest.json').write_bytes(previous)
    print(json.dumps({k: v for k, v in row.items() if k != 'files'}))

if __name__ == '__main__':
    main()

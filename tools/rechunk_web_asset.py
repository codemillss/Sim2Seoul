#!/usr/bin/env python3
"""Replace exactly one validated gzip asset with two smaller raw-byte parts."""
import argparse
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def asset(dist, relative):
    require(isinstance(relative, str) and re.fullmatch(r'chunks/[A-Za-z0-9][A-Za-z0-9._-]*\.gz', relative), 'Unsafe chunk path')
    path = dist / relative
    require(path.resolve().is_relative_to(dist) and not path.is_symlink(), 'Chunk escapes dist or is a symlink')
    return path


def verify(dist, manifest):
    require(set(manifest['files']) == {'wasm', 'pck'}, 'Expected wasm and pck')
    whole, compressed, seen = {}, {}, set()
    for kind, row in manifest['files'].items():
        require(row['path'] == 'game/index.' + kind and row['chunks'], 'Invalid whole-file path/chunks')
        digest, size = hashlib.sha256(), 0
        for part in row['chunks']:
            require(part['path'] not in seen and part['encoding'] == 'gzip', 'Duplicate path or non-gzip chunk')
            seen.add(part['path'])
            packed = asset(dist, part['path']).read_bytes()
            raw = gzip.decompress(packed)
            require(len(packed) == part['transferBytes'] and len(raw) == part['bytes'] and sha(raw) == part['sha256'], 'Chunk integrity mismatch: ' + part['path'])
            require(type(part['bytes']) is int and part['bytes'] > 0 and type(part['transferBytes']) is int and part['transferBytes'] > 0, 'Invalid chunk size')
            digest.update(raw); size += len(raw)
            compressed[part['path']] = sha(packed)
        require(size == row['bytes'] and digest.hexdigest() == row['sha256'], 'Whole-file integrity mismatch: ' + kind)
        whole[kind] = {'bytes': size, 'sha256': digest.hexdigest()}
    return whole, compressed


def atomic_write(path, data):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.' + path.name + '-', delete=False) as stream:
            temporary = Path(stream.name); stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def rechunk(site, chunk, part_bytes, release, report):
    site, report = Path(site).resolve(), Path(report).resolve()
    dist = (site / 'dist').resolve()
    require(dist.is_relative_to(site) and dist.is_dir(), 'dist must stay inside site')
    require(type(part_bytes) is int and part_bytes > 0, 'part-bytes must be positive')
    require(isinstance(release, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,95}', release), 'Unsafe release')
    require(not report.exists() and not report.is_relative_to(dist), 'Report must be fresh and outside dist')
    target = asset(dist, chunk)
    manifest_path = dist / 'game/manifest.json'
    require(manifest_path.resolve().is_relative_to(dist) and not manifest_path.is_symlink(), 'Unsafe manifest path')
    previous = manifest_path.read_bytes(); manifest = json.loads(previous)
    before_whole, before_compressed = verify(dist, manifest)
    matches = [(row, index, part) for row in manifest['files'].values() for index, part in enumerate(row['chunks']) if part['path'] == chunk]
    require(len(matches) == 1, 'Target must occur exactly once')
    original = matches[0][2]; raw = gzip.decompress(target.read_bytes())
    require((len(raw) + part_bytes - 1) // part_bytes == 2, 'Target must split into exactly two parts')
    updated = copy.deepcopy(manifest); replacements, payloads = [], {}
    for index, offset in enumerate(range(0, len(raw), part_bytes)):
        data = raw[offset:offset + part_bytes]; packed = gzip.compress(data, compresslevel=6, mtime=0)
        name = f'chunks/{target.stem}-part{index}-{sha(data)[:16]}.gz'
        require(name not in before_compressed and name not in payloads, 'Replacement URL must be distinct')
        path = asset(dist, name)
        require(not path.exists() or path.read_bytes() == packed, 'Replacement filename collision')
        payloads[name] = packed
        replacements.append({'path': name, 'bytes': len(data), 'transferBytes': len(packed), 'sha256': sha(data), 'encoding': 'gzip'})
    for row in updated['files'].values():
        row['chunks'] = [replacement for part in row['chunks'] for replacement in (replacements if part['path'] == chunk else [part])]
    updated['webRelease'] = release
    created, committed = [], False
    try:
        report.parent.mkdir(parents=True, exist_ok=True)
        for name, packed in payloads.items():
            path = asset(dist, name)
            if not path.exists():
                with path.open('xb') as stream:
                    created.append(path); stream.write(packed)
        after_whole, after_compressed = verify(dist, updated)
        require(before_whole == after_whole, 'Whole game bytes changed')
        require(all(after_compressed[name] == value for name, value in before_compressed.items() if name != chunk), 'Unrelated compressed chunk changed')
        new_manifest = (json.dumps(updated, indent=2) + '\n').encode()
        record = {'release': release, 'previous_manifest_sha256': sha(previous), 'new_manifest_sha256': sha(new_manifest), 'target': {**original, 'compressed_sha256': before_compressed[chunk]}, 'replacements': [{**part, 'compressed_sha256': after_compressed[part['path']]} for part in replacements], 'transfer_delta_bytes': sum(part['transferBytes'] for part in replacements) - original['transferBytes'], 'whole_files_before': before_whole, 'whole_files_after': after_whole, 'whole_sha256_unchanged': True, 'unrelated_compressed_chunks_unchanged': True, 'target_deleted': True}
        require(manifest_path.read_bytes() == previous, 'Manifest changed concurrently')
        atomic_write(manifest_path, new_manifest); committed = True
        require(chunk not in {part['path'] for row in updated['files'].values() for part in row['chunks']}, 'Target still referenced')
        target.unlink()  # Only this formerly referenced generated asset is deleted.
        atomic_write(report, (json.dumps(record, indent=2) + '\n').encode())
        return record
    except Exception as error:
        if not committed:
            for path in created:
                path.unlink(missing_ok=True)
        else:
            raise RuntimeError('Manifest committed; inspect target cleanup/report state: ' + str(error)) from error
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site', type=Path, required=True); parser.add_argument('--chunk', required=True)
    parser.add_argument('--part-bytes', type=int, required=True); parser.add_argument('--release', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(rechunk(args.site, args.chunk, args.part_bytes, args.release, args.report)))


if __name__ == '__main__':
    main()

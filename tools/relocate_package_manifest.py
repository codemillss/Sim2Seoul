#!/usr/bin/env python3
"""Bind an immutable R03 package to local paths; never run or re-export it.

The app must already have been extracted separately from the unchanged ZIP.
Only five path fields/key names change. The existing package runner remains
responsible for source hashes, signatures, resources and actual game execution.
"""
import argparse
import copy
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from export_macos import ROOT, app_inventory, describe, read_json, write_json_new


def serialized(value, *, sorted_keys=False):
    return json.dumps(value, ensure_ascii=False, sort_keys=sorted_keys,
                      separators=(',', ':'), allow_nan=False)


def at(value, path):
    for key in path:
        value = value[key]
    return value


def path_patches(original, catalog, app, archive):
    replacements = [(('catalog', 'path'), catalog),
                    (('outputs', 'app', 'path'), app),
                    (('outputs', 'zip', 'path'), archive)]
    for path, new in replacements:
        old = at(original, path)
        if not isinstance(old, str) or not isinstance(new, str) or not all(Path(p).is_absolute() for p in (old, new)):
            raise ValueError('Manifest bindings must be absolute paths')
    old_key = 'evidence_catalog:' + original['catalog']['path']
    new_key = 'evidence_catalog:' + catalog
    patches = [{'op': 'replace', 'path': list(path), 'old': at(original, path), 'new': new}
               for path, new in replacements]
    for section in ('before', 'after'):
        parent = original['source_preservation'][section]
        if old_key not in parent or (new_key != old_key and new_key in parent):
            raise ValueError('Missing or colliding evidence catalog key')
        patches.append({'op': 'rename_key', 'path': ['source_preservation', section],
                        'old': old_key, 'new': new_key})
    return patches


def apply_patches(value, patches, *, reverse=False):
    result = copy.deepcopy(value)
    for patch in reversed(patches) if reverse else patches:
        old, new = (patch['new'], patch['old']) if reverse else (patch['old'], patch['new'])
        if patch['op'] == 'replace':
            parent = at(result, patch['path'][:-1]); key = patch['path'][-1]
            if parent[key] != old:
                raise ValueError('Path patch precondition failed')
            parent[key] = new
        elif patch['op'] == 'rename_key':
            parent = at(result, patch['path'])
            if old not in parent or (new != old and new in parent):
                raise ValueError('Key patch precondition failed')
            renamed = {new if key == old else key: item for key, item in parent.items()}
            parent.clear(); parent.update(renamed)
        else:
            raise ValueError('Unsupported path patch')
    return result


def validate_derivation(original, derived, patches):
    expected = path_patches(original, derived['catalog']['path'], derived['outputs']['app']['path'],
                            derived['outputs']['zip']['path'])
    if serialized(patches, sorted_keys=True) != serialized(expected, sorted_keys=True):
        raise ValueError('Only the five declared path bindings may change')
    if serialized(apply_patches(original, patches)) != serialized(derived):
        raise ValueError('Derived manifest contains an undeclared change')
    if serialized(apply_patches(derived, patches, reverse=True)) != serialized(original):
        raise ValueError('Inverse patches did not restore the exact original JSON')


def relocate(manifest, archive, app, catalog, output, *, repository=ROOT):
    requested_output = Path(output).expanduser()
    if requested_output.exists() or requested_output.is_symlink():
        raise FileExistsError('A fresh output directory is required')
    manifest, archive, app, catalog, output = [Path(p).expanduser().resolve()
                                               for p in (manifest, archive, app, catalog, output)]
    if output.exists():
        raise FileExistsError('A fresh output directory is required')
    if output.is_relative_to(app):
        raise ValueError('Output must not be inside the input app')
    if not catalog.is_relative_to(Path(repository).resolve()):
        raise ValueError('Catalog must belong to the current clone')
    inputs = {'original_manifest': manifest, 'zip': archive, 'catalog': catalog}
    before = {name: describe(path) for name, path in inputs.items()}
    original = read_json(manifest)
    if (original.get('schema_version') != 1 or original.get('task') != 'R03'
            or original.get('stage') != 'local_export_static_validation'
            or original.get('passed') is not True or original.get('source_preservation', {}).get('passed') is not True):
        raise ValueError('A passed original R03 export manifest is required')
    if app.name != 'Sim2Seoul.app' or Path(original['outputs']['app']['path']).name != app.name or not app.is_dir():
        raise ValueError('The extracted app must retain the name Sim2Seoul.app')
    for name, expected in [('zip', original['outputs']['zip']), ('catalog', original['catalog'])]:
        if before[name] != {key: expected[key] for key in ('bytes', 'sha256')}:
            raise ValueError('Unchanged ' + name + ' bytes/SHA-256 are required')
    catalog_key = 'evidence_catalog:' + original['catalog']['path']
    for section in ('before', 'after'):
        if original['source_preservation'][section].get(catalog_key) != before['catalog']:
            raise ValueError('Catalog does not match original preservation binding')
    inventory = app_inventory(app)
    if any(inventory[key] != original['outputs']['app'][key] for key in ('files', 'bytes', 'tree_sha256')):
        raise ValueError('App file bytes, modes or symlinks differ from the original inventory')
    packs = [item for name, item in inventory['files'].items() if name.endswith('.pck')]
    if len(packs) != 1 or {key: packs[0][key] for key in ('bytes', 'sha256')} != original['pck']['file']:
        raise ValueError('Original PCK binding differs from the extracted app')
    patches = path_patches(original, str(catalog), str(app), str(archive))
    derived = apply_patches(original, patches)
    validate_derivation(original, derived, patches)
    output.mkdir(parents=True, exist_ok=False)
    destination = output / 'derived_manifest.json'
    write_json_new(destination, derived)
    validate_derivation(original, read_json(destination), patches)
    after = {name: describe(path) for name, path in inputs.items()}
    final_inventory = app_inventory(app)
    if before != after or serialized(inventory) != serialized(final_inventory):
        raise ValueError('An original input changed during path rebinding')
    binding = {'schema_version': 1, 'task': 'R04', 'stage': 'package_path_rebinding_only',
        'path_binding_valid': True, 'original_manifest': {'path': str(manifest), **before['original_manifest']},
        'derived_manifest': {'path': destination.name, **describe(destination)}, 'path_patches': patches,
        'zip': {'path': str(archive), **before['zip']}, 'catalog': {'path': str(catalog), **before['catalog']},
        'app': {'path': str(app), 'bytes': inventory['bytes'], 'tree_sha256': inventory['tree_sha256'],
                'file_count': len(inventory['files']), 'pck': original['pck']['file']},
        'original_inputs_unchanged': True, 'inverse_original_json_exact': True,
        'relative_source_hashes_checked': False, 'engine_execution_performed': False,
        'game_execution_performed': False, 'm4_execution_performed': False,
        'scope': 'Path rebinding only. Historical engine/template/PCK/log paths and every non-path value remain unchanged. Run the existing package contract next for source hashes and game evidence; this is not M4 or game acceptance.'}
    write_json_new(output / 'binding.json', binding)
    return {'path_binding_valid': True, 'derived_manifest': str(destination),
            'binding': str(output / 'binding.json'), 'derived_sha256': binding['derived_manifest']['sha256']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path, help='Immutable original export manifest')
    parser.add_argument('--zip', dest='archive', required=True, type=Path)
    parser.add_argument('--app', required=True, type=Path, help='Separately extracted Sim2Seoul.app')
    parser.add_argument('--catalog', type=Path, default=ROOT / 'data/reports/n04/gpu_check.json')
    parser.add_argument('--output', required=True, type=Path, help='Fresh directory for the two metadata files')
    args = parser.parse_args()
    print(json.dumps(relocate(args.manifest, args.archive, args.app, args.catalog, args.output), ensure_ascii=False))

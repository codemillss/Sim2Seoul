#!/usr/bin/env python3
"""Rebuild N03 twice from relocated prepared inputs using existing Python/Shapely."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import shapely

from check_routes import INPUTS as ROUTE_AUDIT_INPUTS
from prepare_routes import INPUTS as ROUTE_INPUTS, OUTPUTS as ROUTE_OUTPUTS
from prepare_pedestrians import INPUTS as PEDESTRIAN_INPUTS, OUT as PEDESTRIAN_OUT, MANIFEST as PEDESTRIAN_MANIFEST
from prepare_traffic import INPUTS as TRAFFIC_INPUTS, OUT, MANIFEST

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (OUT, MANIFEST)
FORBIDDEN_PARTS = {'.venv', '.venv-data', '.godot', '.git', '__pycache__'}
MODULES = ('prepare_world', 'prepare_routes', 'prepare_pedestrians', 'check_routes')
MARKER = 'N03_PORTABILITY_RUNTIME '
BOOTSTRAP = (
    "import runpy, sys, json; from pathlib import Path; import shapely; "
    "sys.path.insert(0, str(Path.cwd() / 'tools')); "
    "runpy.run_path(str(Path.cwd() / 'tools/prepare_traffic.py'), run_name='__main__'); "
    "print('N03_PORTABILITY_RUNTIME ' + json.dumps({"
    "'python': sys.version.split()[0], 'python_executable': sys.executable, "
    "'shapely': shapely.__version__, 'shapely_path': shapely.__file__, "
    "'modules': {name: sys.modules[name].__file__ for name in "
    "('prepare_world', 'prepare_routes', 'prepare_pedestrians', 'check_routes')}}, sort_keys=True))"
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hashes(root, paths):
    return {path: sha(root / path) if (root / path).is_file() else None for path in paths}


def files(root):
    return sorted(path.relative_to(root).as_posix() for path in root.rglob('*') if path.is_file())


def forbidden(root):
    return sorted(path.relative_to(root).as_posix() for path in root.rglob('*')
                  if any(part in FORBIDDEN_PARTS for part in path.relative_to(root).parts))


def main(output):
    public = json.loads((ROOT / 'game/data/generated/public_walk.json').read_text())
    paths = sorted(set(ROUTE_INPUTS) | set(ROUTE_AUDIT_INPUTS) | set(ROUTE_OUTPUTS)
                   | set(PEDESTRIAN_INPUTS) | {PEDESTRIAN_OUT, PEDESTRIAN_MANIFEST}
                   | set(TRAFFIC_INPUTS) | set(public['provenance']) | {'tools/check_routes.py'})
    before = hashes(ROOT, paths)
    expected = hashes(ROOT, OUTPUTS)
    proof = {'tools/check_traffic_portability.py': sha(__file__)}
    checks = []

    def ck(name, passed, **details):
        checks.append({'name': name, 'passed': bool(passed), **details})

    ck('all_reference_files_exist', all(value is not None for value in [*before.values(), *expected.values()]))
    ck('copy.plan_excludes_environment_editor_and_cache', all(not FORBIDDEN_PARTS.intersection(Path(path).parts) for path in paths))
    ck('copy.plan_only_small_local_osm_extract', [p for p in paths if p.startswith('data/raw/')] == ['data/raw/deoksugung_cityhall-v2.osm.pbf'])
    runs = []
    observations = []
    if checks[0]['passed']:
        reference_bytes = {path: (ROOT / path).read_bytes() for path in OUTPUTS}
        with tempfile.TemporaryDirectory(prefix='sim2seoul-n03-prepared-') as temporary:
            copy = Path(temporary) / 'prepared-copy'
            for path in paths:
                destination = copy / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / path, destination)
            copied_files = files(copy)
            ck('copy.only_prepared_inputs', copied_files == paths, files=len(copied_files))
            ck('copy.inputs_match_original', hashes(copy, paths) == before)
            ck('copy.no_environment_editor_or_cache', not forbidden(copy), unexpected=forbidden(copy))
            for iteration in (1, 2):
                if iteration == 2:
                    relocated = Path(temporary) / 'relocated-copy'
                    copy.rename(relocated)
                    copy = relocated
                    for path in OUTPUTS:
                        (copy / path).unlink(missing_ok=True)
                ck(f'run_{iteration}.starts_without_n03_outputs', not any((copy / path).exists() for path in OUTPUTS))
                command = [sys.executable, '-I', '-B', '-c', BOOTSTRAP, '--root', str(copy)]
                observation = {'iteration': iteration, 'folder': copy.name, 'relocated': iteration == 2,
                               'generated_outputs_deleted_before_run': iteration == 2}
                runtime = None
                try:
                    result = subprocess.run(command, cwd=copy, env={}, capture_output=True, text=True, timeout=120)
                    observation.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
                    ck(f'run_{iteration}.exit', result.returncode == 0, messages=(result.stdout + result.stderr)[-3000:])
                    metadata = [line[len(MARKER):] for line in result.stdout.splitlines() if line.startswith(MARKER)]
                    if len(metadata) == 1:
                        runtime = json.loads(metadata[0])
                except subprocess.TimeoutExpired as exc:
                    observation.update(returncode=None, timeout_s=exc.timeout,
                                       stdout=(exc.stdout or b'').decode(errors='replace'),
                                       stderr=(exc.stderr or b'').decode(errors='replace'))
                    ck(f'run_{iteration}.exit', False, messages='N03 generation exceeded 120 seconds')
                except (ValueError, OSError) as exc:
                    observation.update(returncode=None, error=str(exc))
                    ck(f'run_{iteration}.exit', False, messages=str(exc))
                observation['runtime'] = runtime
                ck(f'run_{iteration}.existing_python_shapely', runtime is not None
                   and runtime['python'] == sys.version.split()[0]
                   and Path(runtime['python_executable']).resolve() == Path(sys.executable).resolve()
                   and runtime['shapely'] == shapely.__version__
                   and Path(runtime['shapely_path']).resolve() == Path(shapely.__file__).resolve()
                   and not Path(runtime['shapely_path']).resolve().is_relative_to(copy.resolve()))
                ck(f'run_{iteration}.helpers_loaded_from_current_copy', runtime is not None
                   and {name: str(Path(path).resolve()) for name, path in runtime['modules'].items()}
                   == {name: str((copy / 'tools' / (name + '.py')).resolve()) for name in MODULES})
                actual = hashes(copy, OUTPUTS)
                runs.append(actual)
                observation['output_sha256'] = actual
                observations.append(observation)
                ck(f'run_{iteration}.identical_output_hashes', actual == expected, output_sha256=actual)
                ck(f'run_{iteration}.identical_output_bytes', all((copy / path).is_file()
                   and (copy / path).read_bytes() == reference_bytes[path] for path in OUTPUTS))
                ck(f'run_{iteration}.copied_inputs_unchanged', hashes(copy, paths) == before)
                unexpected = sorted(set(files(copy)) - set(paths) - set(OUTPUTS))
                ck(f'run_{iteration}.no_cache_or_extra_files', not unexpected and not forbidden(copy),
                   unexpected_files=unexpected, forbidden_paths=forbidden(copy))
            ck('relocated_repeat_identical', len(runs) == 2 and runs[0] == runs[1] == expected)
            ck('final_copied_inputs_unchanged', hashes(copy, paths) == before)
    ck('original_inputs_unchanged', hashes(ROOT, paths) == before)
    ck('original_n03_outputs_unchanged', hashes(ROOT, OUTPUTS) == expected)
    ck('proof_unchanged', proof == {'tools/check_traffic_portability.py': sha(__file__)})
    report = {
        'task': 'N03', 'passed': all(check['passed'] for check in checks), 'checks': checks,
        'prepared_files': len(paths),
        'prepared_bytes': sum((ROOT / path).stat().st_size for path in paths if (ROOT / path).is_file()),
        'input_sha256': before, 'output_sha256': expected, 'proof_sha256': proof, 'runs': observations,
        'runtime': {'python': sys.version.split()[0], 'shapely': shapely.__version__,
                    'python_is_existing_installation': True, 'subprocess_flags': ['-I', '-B'],
                    'subprocess_environment': {}, 'workspace_import_path': 'current copied root/tools'},
        'scope': ('Existing local Python/Shapely; N03-only generation twice from prepared N01/N02 inputs '
                  'and their current output snapshots, second run after folder relocation and N03 output deletion. '
                  'Copied only listed prepared data and proof/helper sources, including the small local OSM extract; '
                  'no environment/editor/cache or national map copied. No installation, download, full GIS regeneration, '
                  'Godot, driving, fresh Mac or M4 validation. N01/N02 prepared outputs are checked without rewriting them.'),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print('N03 portability', report['passed'], len(checks), 'checks', len(paths), 'prepared files')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/reports/n03/portability.json')
    raise SystemExit(main(parser.parse_args().output))

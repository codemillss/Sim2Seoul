#!/usr/bin/env python3
"""Rebuild N02 twice from relocated prepared inputs, using existing Python/Shapely."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import shapely

from prepare_routes import INPUTS as ROUTE_INPUTS, OUTPUTS as ROUTE_OUTPUTS
from prepare_pedestrians import INPUTS as PEDESTRIAN_INPUTS, OUT, MANIFEST

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (OUT, MANIFEST)
BOOTSTRAP = (
    "import runpy, sys; from pathlib import Path; "
    "sys.path.insert(0, str(Path.cwd() / 'tools')); "
    "runpy.run_path(str(Path.cwd() / 'tools/prepare_pedestrians.py'), run_name='__main__')"
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hashes(root, paths):
    return {path: sha(root / path) if (root / path).is_file() else None for path in paths}


def main(output):
    public = json.loads((ROOT / "game/data/generated/public_walk.json").read_text())
    paths = sorted(set(ROUTE_INPUTS) | set(ROUTE_OUTPUTS) | set(PEDESTRIAN_INPUTS)
                   | set(public["provenance"]) | {"tools/check_routes.py"})
    before = hashes(ROOT, paths)
    expected = hashes(ROOT, OUTPUTS)
    reference_bytes = {path: (ROOT / path).read_bytes() for path in OUTPUTS}
    checks = []

    def ck(name, passed, **details):
        checks.append({"name": name, "passed": bool(passed), **details})

    ck("all_reference_files_exist", all(value is not None for value in [*before.values(), *expected.values()]))
    runs = []
    with tempfile.TemporaryDirectory(prefix="sim2seoul-n02-prepared-") as temporary:
        copy = Path(temporary) / "prepared-copy"
        for path in paths:
            destination = copy / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, destination)
        copied_files = sorted(path.relative_to(copy).as_posix() for path in copy.rglob("*") if path.is_file())
        ck("copy.only_prepared_inputs", copied_files == paths, files=len(copied_files))
        ck("copy.inputs_match_original", hashes(copy, paths) == before)
        for iteration in (1, 2):
            if iteration == 2:
                relocated = Path(temporary) / "relocated-copy"
                copy.rename(relocated)
                copy = relocated
                for path in OUTPUTS:
                    (copy / path).unlink(missing_ok=True)
            ck(f"run_{iteration}.starts_without_n02_outputs", not any((copy / path).exists() for path in OUTPUTS))
            command = [sys.executable, "-I", "-B", "-c", BOOTSTRAP, "--root", str(copy)]
            try:
                result = subprocess.run(command, cwd=copy, env={}, capture_output=True, text=True, timeout=120)
                ck(f"run_{iteration}.exit", result.returncode == 0,
                   messages=(result.stdout + result.stderr)[-2000:])
            except subprocess.TimeoutExpired:
                ck(f"run_{iteration}.exit", False, messages="N02 generation exceeded 120 seconds")
            actual = hashes(copy, OUTPUTS)
            runs.append(actual)
            ck(f"run_{iteration}.identical_output_hashes", actual == expected, output_sha256=actual)
            ck(f"run_{iteration}.identical_output_bytes",
               all((copy / path).is_file() and (copy / path).read_bytes() == reference_bytes[path]
                   for path in OUTPUTS))
            ck(f"run_{iteration}.copied_inputs_unchanged", hashes(copy, paths) == before)
            unexpected = sorted(path.relative_to(copy).as_posix() for path in copy.rglob("*")
                                if path.is_file() and path.relative_to(copy).as_posix() not in paths
                                and path.relative_to(copy).as_posix() not in OUTPUTS)
            ck(f"run_{iteration}.no_cache_or_extra_files", not unexpected, unexpected_files=unexpected)
        ck("relocated_repeat_identical", len(runs) == 2 and runs[0] == runs[1] == expected)
        ck("final_copied_inputs_unchanged", hashes(copy, paths) == before)
    ck("original_inputs_unchanged", hashes(ROOT, paths) == before)
    ck("original_n02_outputs_unchanged", hashes(ROOT, OUTPUTS) == expected)
    report = {
        "task": "N02", "passed": all(check["passed"] for check in checks), "checks": checks,
        "prepared_files": len(paths), "prepared_bytes": sum((ROOT / path).stat().st_size for path in paths),
        "input_sha256": before, "output_sha256": expected,
        "runtime": {"python": sys.version.split()[0], "shapely": shapely.__version__, "python_is_existing_installation": True,
                    "subprocess_flags": ["-I", "-B"], "subprocess_environment": {},
                    "workspace_import_path": "current copied root/tools"},
        "scope": ("Existing local Python/Shapely; N02-only generation twice from prepared N01 inputs and "
                  "current N01 output snapshots, second run after folder relocation and output deletion. "
                  "No copied environment/editor/cache, install, network, full GIS regeneration, Godot, "
                  "fresh Mac or M4 validation. N01 is checked without rewriting its prepared outputs."),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print("N02 portability", report["passed"], len(checks), "checks", len(paths), "prepared files")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "data/reports/n02/portability.json")
    raise SystemExit(main(parser.parse_args().output))

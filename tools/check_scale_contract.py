#!/usr/bin/env python3
"""E04 reproducible checks: actual engine mutations, bundle rejection and preparation.

Runs offline in separate game-only copies, using the installed fixed engine.
The preparation copy reuses validated G01/E03 outputs, not a new raw-data audit.
"""
import argparse
import copy
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_scale_view import audit
from prepare_scale_view import prepare_scale

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2.stable.official.ed1daf0bf"
MUTATIONS = {
    "world_scaled": "world_transform.basis",
    "world_moved": "world_transform.origin",
    "world_rotated": "world_transform.basis",
    "world_z_flipped": "world_transform.basis",
    "world_y_scaled": "world_transform.basis",
    "anchors_moved": "anchor_parent_transform.origin",
    "controls_scaled": "control_parent_transform.basis",
    "root_moved": "engine.origin",
    "ruler_shortened": "control.grid_east_10m.length_3d",
    "cube_wrong_size": "cube.edge_axis_1",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+"\n")


def game_copy(target):
    shutil.copytree(ROOT/"game", target,
                    ignore=shutil.ignore_patterns(".godot", "*.gd.uid"))


def main(engine, output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    checks, mutations, bundles, preparation = [], [], [], []

    def check(name, passed, **detail):
        checks.append({"name": name, "passed": bool(passed), **detail})

    def probe(game, script, result_path=None, variant=None):
        command = ["/usr/bin/sandbox-exec", "-f", str(ROOT/"tests/game/offline.sb"),
                   str(engine), "--headless", "--path", str(game), "--script", str(ROOT/script)]
        if result_path is not None:
            command += ["--", "--result="+str(result_path), "--case="+variant]
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        log = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout+result.stderr)
        if result.returncode or "SCRIPT ERROR" in log or "Parse Error" in log:
            raise ValueError(f"Engine probe failed ({script}, {variant}): {log[:1800]}")
        return log

    check("engine.version", subprocess.check_output([str(engine), "--version"], text=True).strip()==VERSION)
    before = sha(ROOT/"game/resources/world_geometry/world.json")
    prepare_scale(check_only=True)
    check("preparation.current_bundle", True)
    with tempfile.TemporaryDirectory(prefix="sim2seoul-e04-check-") as temporary:
        temp = Path(temporary)
        runtime = temp/"standalone/game"
        game_copy(runtime)
        check("runtime.game_only", set(p.name for p in runtime.parent.iterdir())=={"game"})
        check("runtime.no_import_cache", not (runtime/".godot").exists())
        normal_path = output/"headless_engine.json"
        probe(runtime, "tests/game/check_scale_view.gd", normal_path, "normal")
        normal = json.loads(normal_path.read_text())
        normal_check = audit(normal["measurements"])
        write_json(output/"headless_check.json", normal_check)
        check("engine.normal", normal_check["passed"], checks=len(normal_check["checks"]))
        repeat_path = temp/"repeat.json"
        probe(runtime, "tests/game/check_scale_view.gd", repeat_path, "normal")
        repeat = json.loads(repeat_path.read_text())
        check("engine.fixed_scene_repeat", normal["measurements"]==repeat["measurements"])
        for case, expected_failure in MUTATIONS.items():
            path = output/"regression"/(case+".json")
            path.parent.mkdir(parents=True, exist_ok=True)
            probe(runtime, "tests/game/check_scale_view.gd", path, case)
            record = json.loads(path.read_text())
            scored = audit(record["measurements"])
            failures = [c["name"] for c in scored["checks"] if not c["passed"]]
            detected = not scored["passed"] and any(n.startswith(expected_failure) for n in failures)
            mutations.append({"case": case, "engine_exit": 0, "checker_passed": scored["passed"],
                              "expected_failure_prefix": expected_failure, "failed_checks": failures,
                              "measurement_file": str(path.relative_to(output)), "sha256": sha(path)})
            check("regression."+case, detected)
        print("E04 actual engine: normal/repeat and 10 scene mutations checked.", flush=True)

        data_path = runtime/"data/generated/scale_view.json"
        manifest_path = runtime/"data/generated/scale_manifest.json"
        original_data, original_manifest = data_path.read_bytes(), manifest_path.read_bytes()
        good = json.loads(original_data)
        manifest = json.loads(original_manifest)
        for case in ["normal", "missing_manifest", "missing_data", "checksum", "external_path", "stale_world",
                     "source_point_kind", "duplicate_anchor", "control_direction", "missing_view", "cube_size", "invalid_camera"]:
            data_path.write_bytes(original_data)
            manifest_path.write_bytes(original_manifest)
            data, m = copy.deepcopy(good), copy.deepcopy(manifest)
            if case=="missing_manifest": manifest_path.unlink()
            elif case=="missing_data": data_path.unlink()
            elif case=="checksum": data_path.write_bytes(original_data+b" ")
            elif case=="external_path":
                m["file"]="../scale_view.json"
                write_json(manifest_path,m)
            elif case!="normal":
                if case=="stale_world": data["world_sha256"]="0"*64; m["world_sha256"]="0"*64
                elif case=="source_point_kind": data["anchors"][0]["source_point_kind"]="entrance"
                elif case=="duplicate_anchor": data["anchors"][1]["id"]=data["anchors"][0]["id"]
                elif case=="control_direction": data["controls"][2]["expected_world_xyz_m"]=[0,0,10]
                elif case=="missing_view": del data["settings"]["views"]["map"]
                elif case=="cube_size": data["settings"]["cube"]["edge_m"]=9
                elif case=="invalid_camera": data["settings"]["views"]["axes"]["size_m"]=0
                write_json(data_path,data)
                m["sha256"]=sha(data_path); m["bytes"]=data_path.stat().st_size
                write_json(manifest_path,m)
            log = probe(runtime, "tests/game/check_scale_bundle.gd")
            record = json.loads(next(line.removeprefix("E04_BUNDLE_RESULT ") for line in log.splitlines()
                                    if line.startswith("E04_BUNDLE_RESULT ")))
            bundles.append({"case":case,"reader":record,"expected_ok":case=="normal"})
            check("bundle."+case, record["ok"]==(case=="normal"))
        print("E04 runtime bundle: normal and 11 rejected fixtures checked.", flush=True)

        # Small isolated preparation copy: include E03's hashed required inputs.
        prepared = temp/"prepared"
        world = json.loads((ROOT/"game/resources/world_geometry/world.json").read_text())
        inputs = {p["file"] for p in world["provenance"]["inputs"]}
        inputs.update({"tools/prepare_scale_view.py", "config/scale_view.json", "config/region.json",
                       "data/processed/coordinate_reference.json", "data/reports/coordinate_check.json",
                       "game/resources/world_geometry/world.json", "tools/prepare_world.py"})
        for name in ("region.json", "manifest.json", "scale_view.json", "scale_manifest.json"):
            inputs.add("game/data/generated/"+name)
        for name in inputs:
            target=prepared/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/name,target)
        prepare_scale(prepared)
        generated = [prepared/"game/data/generated"/n for n in ("scale_view.json","scale_manifest.json")]
        first = [p.read_bytes() for p in generated]
        prepare_scale(prepared)
        check("preparation.two_generations_equal", first==[p.read_bytes() for p in generated])
        prepare_scale(prepared,check_only=True)
        check("preparation.copy_matches_current", first==[(ROOT/p.relative_to(prepared)).read_bytes() for p in generated])
        for case, name in [("reference_drift","data/processed/coordinate_reference.json"),
                           ("config_drift","config/scale_view.json"),
                           ("world_drift","game/resources/world_geometry/world.json"),
                           ("bundle_drift","game/data/generated/scale_view.json")]:
            path=prepared/name
            original=path.read_bytes()
            value=json.loads(original)
            if case=="reference_drift": value["origin_lon_lat"][0]+=0.0001
            elif case=="config_drift": value["views"]["map"]["size_m"]+=1
            elif case=="world_drift": value["meshes"][0]["vertices"][0]+=1
            elif case=="bundle_drift": value["scope"]="changed"
            write_json(path,value)
            rejected=False
            try: prepare_scale(prepared,check_only=True)
            except ValueError as exc:
                rejected=True
                preparation.append({"case":case,"rejected":True,"reason":str(exc)})
            finally: path.write_bytes(original)
            check("preparation."+case,rejected)
        check("preparation.no_large_source", not (prepared/"data/raw/geofabrik").exists())
    check("city_world_unchanged",before==sha(ROOT/"game/resources/world_geometry/world.json"),sha256=before)
    report={"task":"E04","passed":all(c["passed"] for c in checks),"checks":checks,
            "engine_mutations":mutations,"bundle_fixtures":bundles,"preparation_rejections":preparation,
            "checker_sha256":sha(Path(__file__)),"independent_checker_sha256":sha(ROOT/"tools/check_scale_view.py"),
            "scope":"current M1, existing interpreter; actual offline game-only engine copy and validated G01/E03 preparation inputs",
            "unverified":["new dependency installation","M4 Pro","physical survey","walking","native keyboard/mouse"]}
    write_json(output/"contract_check.json",report)
    print(f"E04 contract: {len(checks)} checks, passed={report['passed']}")
    return 0 if report["passed"] else 1


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine",type=Path,default=Path("/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--output",type=Path,default=ROOT/"data/cache/scale_contract")
    args=parser.parse_args()
    raise SystemExit(main(args.engine,args.output))

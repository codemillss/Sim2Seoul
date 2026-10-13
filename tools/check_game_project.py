#!/usr/bin/env python3
"""Exercise the real Godot input/project contract and corrupted local bundles."""
import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from prepare_game_data import prepare

ROOT = Path(__file__).resolve().parents[1]
ENGINE = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")


def run_script(project, script, marker):
    result = subprocess.run([ENGINE, "--headless", "--path", str(project), "--script", str(script)],
                            capture_output=True, text=True, timeout=30)
    matches = re.findall(re.escape(marker) + r" (.*)", result.stdout)
    if result.returncode or not matches:
        raise ValueError(f"Godot test did not complete: {result.stdout}\n{result.stderr}")
    if "SCRIPT ERROR" in result.stderr or "Parse Error" in result.stderr:
        raise ValueError(result.stderr)
    return json.loads(matches[-1])


def main(report_path):
    version = subprocess.check_output([ENGINE, "--version"], text=True).strip()
    if version != "4.7.2.stable.official.ed1daf0bf":
        raise ValueError(f"Unsupported engine: {version}")
    prepared = prepare()
    check_prepared = prepare(check_only=True)
    second = prepare()
    if prepared["runtime_files"] != second["runtime_files"]:
        raise ValueError("Runtime bundle is not deterministic")
    project_result = run_script(ROOT / "game", ROOT / "tests/game/check_project.gd", "E03_TEST_RESULT")
    geometry_result = run_script(ROOT / "game", ROOT / "tests/game/check_world.gd", "E03_WORLD_TEST_RESULT")
    bundle_result = run_script(ROOT / "game", ROOT / "tests/game/check_bundle.gd", "E03_BUNDLE_RESULT")
    if not bundle_result["ok"]:
        raise ValueError(bundle_result)
    cases = ["missing_manifest", "missing_region", "bad_json", "checksum_mismatch", "units_changed",
             "axes_changed", "spawn_origin", "final_boundary", "external_manifest", "traversal_region",
             "remote_region", "wrong_schema", "external_asset", "malformed_source", "nonnumeric_origin", "missing_world", "world_checksum", "world_stage", "world_permission", "world_nan", "world_arrays", "world_duplicate", "world_axes"]
    rejections = []
    with tempfile.TemporaryDirectory(prefix="sim2seoul-e03-check-") as temp:
        temp = Path(temp)
        failed_exit = subprocess.run([ENGINE,"--headless","--path",str(ROOT/"game"),"--script",str(ROOT/"tests/game/check_observation_exit.gd"),"--",f"--failure-prefix={temp}/missing_directory/runtime"],capture_output=True,text=True,timeout=30)
        if failed_exit.returncode != 1 or "E03_EXPECTED_OBSERVATION_FAILURE" not in failed_exit.stdout or "Cannot save E03 observation record" not in failed_exit.stderr or "SCRIPT ERROR" in failed_exit.stderr:
            raise ValueError("Observation write failure did not preserve failed exit code")
        for case in cases:
            game = temp / case / "game"
            shutil.copytree(ROOT / "game", game, ignore=shutil.ignore_patterns(".godot", "*.gd.uid"))
            manifest_path = game / "data/generated/manifest.json"
            region_path = game / "data/generated/region.json"
            manifest = json.loads(manifest_path.read_text())
            region = json.loads(region_path.read_text())
            world_path = game / "resources/world_geometry/world.json"
            world = json.loads(world_path.read_text())
            rewrite_world = False
            rewrite_region = False
            if case == "missing_manifest": manifest_path.unlink()
            elif case == "missing_region": region_path.unlink()
            elif case == "bad_json": region_path.write_text("{broken"); rewrite_region = True
            elif case == "checksum_mismatch": region_path.write_bytes(region_path.read_bytes()+b"\n")
            elif case == "units_changed": region["meters_per_world_unit"] = 2; rewrite_region = True
            elif case == "axes_changed": region["world_axes"]["z"] = "north"; rewrite_region = True
            elif case == "spawn_origin": region["origin_role"] = "spawn"; rewrite_region = True
            elif case == "final_boundary": region["playable_boundary"] = []; rewrite_region = True
            elif case == "external_manifest":
                p = game / "resources/world_config.tres"
                p.write_text(p.read_text().replace("res://data/generated/manifest.json", "/tmp/manifest.json"))
            elif case == "traversal_region": manifest["region_file"] = "res://../config/region.json"
            elif case == "remote_region": manifest["region_file"] = "https://example.com/region.json"
            elif case == "wrong_schema": manifest["schema_version"] = 99
            elif case == "external_asset": manifest["assets"][0]["path"] = "res://../data/raw/country.pbf"
            elif case == "malformed_source": manifest["source_contract"] = []
            elif case == "nonnumeric_origin": region["origin_lon_lat"] = ["126.97625",37.5651]; rewrite_region = True
            if case == "missing_world": world_path.unlink()
            elif case == "world_checksum": world_path.write_bytes(world_path.read_bytes()+b"\n")
            elif case == "world_stage": world["task"]="E02"; rewrite_world=True
            elif case == "world_permission": world["meshes"][0]["metadata"]["runtime_permission"]=True; rewrite_world=True
            elif case == "world_nan": world["meshes"][0]["vertices"][0]="NaN"; rewrite_world=True
            elif case == "world_arrays": world["meshes"][0]["normals"]=[]; rewrite_world=True
            elif case == "world_duplicate": world["meshes"][1]["id"]=world["meshes"][0]["id"]; rewrite_world=True
            elif case == "world_axes": world["coordinate_system"]["world_axes"]["z"]="north"; rewrite_world=True
            if rewrite_world:
                world_path.write_text(json.dumps(world))
                manifest["assets"][0]["sha256"]=hashlib.sha256(world_path.read_bytes()).hexdigest()
                manifest["assets"][0]["bytes"]=world_path.stat().st_size
            if rewrite_region:
                if case != "bad_json": region_path.write_text(json.dumps(region))
                manifest["source_contract"]["sha256"] = hashlib.sha256(region_path.read_bytes()).hexdigest()
            if case != "missing_manifest": manifest_path.write_text(json.dumps(manifest))
            result = run_script(game, ROOT / "tests/game/check_bundle.gd", "E03_BUNDLE_RESULT")
            if result.get("ok") or not result.get("error"):
                raise ValueError(f"Invalid bundle accepted: {case}")
            rejections.append({"case":case,"rejected":True,"error":result["error"]})
        # Exercise source drift and stale runtime detection without altering repository inputs.
        fixture = temp / "prepare_source"
        (fixture / "config").mkdir(parents=True)
        (fixture / "data/reports").mkdir(parents=True)
        shutil.copy2(ROOT / "config/region.json",fixture / "config/region.json")
        shutil.copy2(ROOT / "data/reports/coordinate_check.json",fixture / "data/reports/coordinate_check.json")
        for record in json.loads((ROOT / "game/resources/world_geometry/world.json").read_text())["provenance"]["inputs"]:
            path = record["file"]
            (fixture / path).parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT / path,fixture / path)
        for path in ["game/resources/world_geometry/world.json","tools/prepare_world.py"]:
            (fixture / path).parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT / path,fixture / path)
        prepare(fixture)
        (fixture / "game/data/generated/region.json").write_text("{}")
        try: prepare(fixture,check_only=True)
        except ValueError: rejections.append({"case":"stale_prepared_bundle","rejected":True})
        else: raise ValueError("Stale prepared bundle accepted")
        altered = copy.deepcopy(bundle_result["region"])
        altered["origin_lon_lat"][0] += 0.001
        (fixture / "config/region.json").write_text(json.dumps(altered))
        try: prepare(fixture)
        except ValueError: rejections.append({"case":"source_changed_after_G01","rejected":True})
        else: raise ValueError("Unvalidated source change accepted")
        # Required provenance and source drift are checked before packaging.
        shutil.copy2(ROOT / "config/region.json",fixture / "config/region.json")
        fixture_world = fixture / "game/resources/world_geometry/world.json"
        original_world = fixture_world.read_bytes()
        altered_world = json.loads(original_world)
        altered_world["provenance"]["inputs"] = []
        fixture_world.write_text(json.dumps(altered_world))
        try: prepare(fixture)
        except ValueError: rejections.append({"case":"world_provenance_omitted","rejected":True})
        else: raise ValueError("Missing world provenance accepted")
        fixture_world.write_bytes(original_world)
        (fixture / "data/processed/driveable_areas.json").write_text("{}")
        try: prepare(fixture)
        except ValueError: rejections.append({"case":"movement_source_changed_after_world","rejected":True})
        else: raise ValueError("Stale world source accepted")
    evidence = {"task":"E03","engine":version,"scope":"headless structure/input/data tests, not GPU or walking acceptance",
                "project_checks":project_result,"normal_bundle_loaded":bundle_result["ok"],
                "geometry_engine_checks":geometry_result,"observation_write_failure_exit_code":failed_exit.returncode,
                "deterministic_preparation":True,"check_mode_passed":check_prepared["check_only"],
                "runtime_files":prepared["runtime_files"],"invalid_bundle_rejections":rejections,"result":"passed"}
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n")
    print(f"E03: {project_result['passed']} project/input checks, {len(rejections)} invalid/stale bundle rejections passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=ROOT / "data/cache/game/contract_check.json")
    main(parser.parse_args().report)

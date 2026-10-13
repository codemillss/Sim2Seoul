#!/usr/bin/env python3
"""Regenerate E03 in a separate small-source copy with the current Mac interpreter."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(report):
    interpreter = ROOT / ".venv-data/bin/python"
    files = subprocess.check_output(["git","ls-files","--cached","--others","--exclude-standard"],cwd=ROOT,text=True).splitlines()
    # Git may quote Korean paths; all tracked repo paths currently use ASCII.
    manual_before = {p:sha(ROOT/p) for p in files if p.startswith("data/manual/")}
    results = []
    with tempfile.TemporaryDirectory(prefix="sim2seoul-e03-portable-") as temporary:
        copy_root = Path(temporary)
        for path in files:
            target = copy_root / path
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/path,target)
        if (copy_root / "data/processed").exists() or (copy_root / "game/resources/world_geometry").exists():
            raise ValueError("Generated data accidentally present in shared payload")
        commands = [
            ["tools/prepare_osm.py","audit","data/raw/deoksugung_cityhall-v2.osm.pbf"],
            ["tools/check_coordinates.py"], ["tools/prepare_features.py"], ["tools/check_geometry.py"],
            ["tools/prepare_heights.py"], ["tools/check_heights.py"], ["tools/prepare_movement.py"],
            ["tools/check_movement.py"], ["tools/prepare_world.py"], ["tools/prepare_game_data.py"],
            ["tools/check_world_geometry.py","--report","data/cache/portable_world_check.json"]]
        for command in commands:
            completed = subprocess.run([str(interpreter),*command],cwd=copy_root,capture_output=True,text=True,timeout=90)
            if completed.returncode:
                raise ValueError(f"Portable regeneration failed: {command}\n{completed.stdout}\n{completed.stderr}")
            results.append({"tool":command[0],"exit_code":completed.returncode})
        world_path = copy_root / "game/resources/world_geometry/world.json"
        first = sha(world_path)
        subprocess.run([str(interpreter),"tools/prepare_world.py"],cwd=copy_root,check=True,capture_output=True,timeout=30)
        subprocess.run([str(interpreter),"tools/prepare_game_data.py","--check"],cwd=copy_root,check=True,capture_output=True,timeout=30)
        if first != sha(world_path): raise ValueError("Portable generation not deterministic")
        local = json.loads((ROOT / "game/resources/world_geometry/world.json").read_text())
        portable = json.loads(world_path.read_text())
        if local["meshes"] != portable["meshes"] or local["source_decisions"] != portable["source_decisions"]:
            raise ValueError("Portable source decisions/geometry differ from current world")
        for path,before in manual_before.items():
            if sha(copy_root/path) != before: raise ValueError(f"Manual input modified: {path}")
        source_check = json.loads((copy_root/"data/cache/portable_world_check.json").read_text())
        record = {"task":"E03","passed":True,"scope":"fresh small-source file copy on current M1, existing interpreter; not new environment or M4 validation",
                  "checker_sha256":sha(Path(__file__)),"steps":results,"source_check":source_check,
                  "country_map_present":False,"full_dsm_present":False,"generated_data_initially_present":False,
                  "manual_inputs_unchanged":True,"two_generations_equal":True,"current_meshes_equal":True,
                  "portable_world_sha256":first,"current_world_sha256":sha(ROOT/"game/resources/world_geometry/world.json"),
                  "different_report_hashes_allowed":True,"note":"G-stage report environment/provenance bytes may differ; geometry and decisions compared independently"}
    report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n")
    print("E03 portability: 11 preparation/audit steps, deterministic triangles and unchanged manual inputs passed.")


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=ROOT/"data/cache/e03_portability_check.json")
    main(parser.parse_args().report)

#!/usr/bin/env python3
"""Package E03's already generated local world; standard library, no network."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD_REQUIRED_INPUTS = {
    "config/region.json", "config/world_display.json", "data/reports/coordinate_check.json",
    "data/processed/features.json", "data/processed/heights.json", "data/processed/terrain.json",
    "data/processed/walkable_areas.json", "data/processed/driveable_areas.json",
    "data/reports/geometry_check.json", "data/reports/height_check.json", "data/reports/movement_check.json",
    "config/geometry_rules.json", "config/data_usage.json", "config/height_rules.json", "config/movement_rules.json",
    "data/manual/review_queue.json", "data/manual/height_review_decisions.json", "data/manual/movement_review.json",
    "data/reports/g03_official_evidence.json", "data/reports/g04_official_route_evidence.json",
    "tools/prepare_features.py", "tools/coordinate_system.py", "tools/prepare_heights.py", "tools/prepare_movement.py", "tools/prepare_world.py",
    "data/processed/osm_preview.geojson",
    "data/raw/deoksugung_cityhall-v2.osm.pbf",
    "data/raw/supplemental/overture/2026-09-23.1/buildings.geojson"
}


def sha(content):
    return hashlib.sha256(content).hexdigest()


def prepare(root=ROOT, check_only=False):
    root = Path(root)
    region_bytes = (root / "config/region.json").read_bytes()
    region = json.loads(region_bytes)
    reference = json.loads((root / "data/reports/coordinate_check.json").read_text())
    if reference["provenance"]["config_sha256"] != sha(region_bytes):
        raise ValueError("region.json changed after G01; validate coordinates before preparing game data")
    if not reference["passed"] or reference["coordinate_reference"]["coordinate_contract_version"] != region["coordinate_contract_version"]:
        raise ValueError("G01 coordinate check is not valid for this contract")
    world_path = root / "game/resources/world_geometry/world.json"
    if not world_path.is_file():
        raise ValueError("E03 world is missing; run .venv-data/bin/python tools/prepare_world.py first")
    world_bytes = world_path.read_bytes()
    world = json.loads(world_bytes)
    if world.get("coordinate_contract_sha256") != sha(region_bytes):
        raise ValueError("World coordinate contract is stale")
    if world.get("task") != "E03" or world.get("schema_version") != 1:
        raise ValueError("Unsupported generated world")
    if world["provenance"]["generator_sha256"] != sha((root / "tools/prepare_world.py").read_bytes()):
        raise ValueError("World generator changed; regenerate world")
    supplied = [record["file"] for record in world["provenance"]["inputs"]]
    if not WORLD_REQUIRED_INPUTS.issubset(supplied) or len(set(supplied)) != len(supplied):
        raise ValueError("World provenance omits or duplicates required source inputs")
    for record in world["provenance"]["inputs"]:
        path = Path(record["file"])
        if path.is_absolute() or ".." in path.parts or path.parts[0] not in ["config", "data", "tools"]:
            raise ValueError("Unsupported world provenance path")
        if not (root / path).is_file() or sha((root / path).read_bytes()) != record["sha256"]:
            raise ValueError(f"World input changed: {path}; regenerate its G stage and E03")
    manifest = {
        "schema_version": 2,
        "stage": "E03_display_only",
        "region_file": "res://data/generated/region.json",
        "source_contract": {"file": "config/region.json", "sha256": sha(region_bytes)},
        "coordinate_evidence": {"file": "data/reports/coordinate_check.json", "sha256": sha((root / "data/reports/coordinate_check.json").read_bytes())},
        "assets": [{"path":"res://resources/world_geometry/world.json", "sha256":sha(world_bytes), "bytes":len(world_bytes)}],
        "geometry_status": "display_only_no_collision_or_permission",
        "generator": "tools/prepare_game_data.py",
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    output = root / "game/data/generated"
    payloads = {"region.json": region_bytes, "manifest.json": manifest_bytes}
    if check_only:
        for name, expected in payloads.items():
            if not (output / name).is_file() or (output / name).read_bytes() != expected:
                raise ValueError(f"Stale or missing runtime contract: {name}; run prepare_game_data.py")
    else:
        output.mkdir(parents=True, exist_ok=True)
        for name, content in payloads.items():
            (output / name).write_bytes(content)
    return {"stage": manifest["stage"], "check_only": check_only,
            "runtime_files": [{"file": str((output / n).relative_to(root)), "bytes": len(c), "sha256": sha(c)} for n, c in payloads.items()],
            "map_assets": 1, "world_counts":world["counts"], "source_contract_sha256": sha(region_bytes)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(check_only=args.check), ensure_ascii=False, indent=2))

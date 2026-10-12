#!/usr/bin/env python3
"""Prepare E02's small local contract bundle; no map conversion or network."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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
    manifest = {
        "schema_version": 1,
        "stage": "E02_structure_only",
        "region_file": "res://data/generated/region.json",
        "source_contract": {"file": "config/region.json", "sha256": sha(region_bytes)},
        "coordinate_evidence": {"file": "data/reports/coordinate_check.json", "sha256": sha((root / "data/reports/coordinate_check.json").read_bytes())},
        "assets": [],
        "geometry_status": "not_imported",
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
            "map_assets": 0, "source_contract_sha256": sha(region_bytes)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(prepare(check_only=args.check), ensure_ascii=False, indent=2))

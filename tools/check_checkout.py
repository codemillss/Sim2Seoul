#!/usr/bin/env python3
"""Validate the small shared map using only Python's standard library."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / "data/reports/extract_manifest.json").read_text())
    versions = [manifest]
    previous_manifest = manifest.get("previous_manifest")
    if previous_manifest:
        versions.append(json.loads((ROOT / previous_manifest).read_text()))
    checked = []
    for record in versions:
        path = ROOT / record["extract_file"]
        if not path.is_file():
            raise SystemExit(f"Missing shared regional map: {record['extract_file']}. Check that the clone is complete.")
        content = path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if len(content) != record["extract_bytes"] or digest != record["extract_sha256"]:
            raise SystemExit(f"Regional map checksum mismatch: {record['extract_file']}")
        checked.append({"file": record["extract_file"], "bytes": len(content), "sha256": digest})
    supplemental = []
    for manifest_path, key in [
        ("data/reports/overture_acquisition-2026-09-23.1.json", "artifact"),
        ("data/reports/copernicus_acquisition-20261012.json", "regional_artifact"),
    ]:
        path = ROOT / manifest_path
        if not path.exists():
            continue
        artifact = json.loads(path.read_text())[key]
        source = ROOT / artifact["file"]
        if not source.exists():
            raise SystemExit(f"Missing shared D03 reference: {artifact['file']}")
        if source.stat().st_size != artifact["bytes"] or hashlib.sha256(source.read_bytes()).hexdigest() != artifact["sha256"]:
            raise SystemExit(f"D03 reference checksum mismatch: {artifact['file']}")
        supplemental.append(artifact)
    print(json.dumps({"regional_maps": checked, "country_source_available": (ROOT / manifest["source_file"]).is_file(),
        "supplemental_reference_files": supplemental,
        "country_source_required_for_local_audit": False, "result": "passed"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

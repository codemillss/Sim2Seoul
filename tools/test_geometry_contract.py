#!/usr/bin/env python3
"""G02 regression checks for corruption that can break later height/mesh work.

Requires the current generated features.json and data interpreter. All mutated
inputs/reports live in a temporary directory; no source/manual edits.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from coordinate_system import ROOT
from prepare_features import canonical, load, save, sha


def target(document, identity, kind="building"):
    fid = canonical(identity) + ":" + kind
    return next(f for f in document["features"] if f["feature_id"] == fid)


def missing_groups(document):
    document["diagnostics"]["building_groups"] = []
    for f in document["features"]:
        f["building_group_refs"] = []


def changed_height(document):
    target(document, "r/10757525")["building"]["height_raw"] = "999"


def changed_source_crs(document):
    target(document, "r/10757525")["source_geometry"]["crs"] = "EPSG:3857"


def changed_rules(document):
    document["geometry_rules"]["overlap_report_min_area_m2"] = 1e9


def changed_coordinate_contract(document):
    document["coordinate_system"]["origin_lon_lat"][0] += 0.01


def filled_courtyard(document):
    target(document, "r/10754689", "highway_area")["geometry"]["coordinates"][0] = [
        target(document, "r/10754689", "highway_area")["geometry"]["coordinates"][0][0]]


def changed_vertex(document):
    target(document, "w/377289797")["geometry"]["coordinates"][0][0][0][0] += 0.25


def duplicate_emission(document):
    document["coarse_body_feature_ids"].append(document["coarse_body_feature_ids"][0])


def independent_part(document):
    part = next(f for f in document["features"] if f["source_kind"] == "building_part")
    part["generation"]["role"] = "primary_footprint"
    document["coarse_body_feature_ids"].append(part["feature_id"])


CASES = [("removed_groups_and_reverse_links", missing_groups, "all_raw_building_groups_and_reverse_links_present"),
    ("altered_height_raw", changed_height, "downstream_raw_height_roof_road_and_access_attributes_match_source"),
    ("altered_source_crs", changed_source_crs, "raw_tags_topology_coordinates_and_ids_preserved"),
    ("altered_embedded_rules", changed_rules, "embedded_rules_match_current_configuration"),
    ("altered_coordinate_metadata", changed_coordinate_contract, "document_coordinate_contract_and_schema_match"),
    ("filled_courtyard_hole", filled_courtyard, "junghwajeon_courtyard_hole_not_filled"),
    ("shifted_daehanmun_vertex", changed_vertex, "valid_finite_topology_winding_and_shape_preserved"),
    ("duplicated_coarse_emission", duplicate_emission, "coarse_plan_contains_only_primary_building_footprints"),
    ("part_as_independent_body", independent_part, "parts_and_roofs_are_not_independent_coarse_volumes")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="data/reports/g02_regression_check.json")
    args = parser.parse_args()
    original = load(ROOT / "data/processed/features.json")
    results = []
    with tempfile.TemporaryDirectory(prefix="sim2seoul-g02-regression-") as folder:
        folder = Path(folder)
        baseline = folder / "baseline.json"
        result = subprocess.run([sys.executable, str(ROOT / "tools/check_geometry.py"), "--report", str(baseline)],
                                cwd=ROOT, capture_output=True, text=True)
        if result.returncode or not load(baseline)["passed"]:
            raise SystemExit("Baseline geometry must pass before corruption tests")
        for name, mutate, required_check in CASES:
            altered = copy.deepcopy(original)
            mutate(altered)
            input_path, output_path = folder / (name + ".json"), folder / (name + "-check.json")
            save(input_path, altered)
            result = subprocess.run([sys.executable, str(ROOT / "tools/check_geometry.py"), "--input", str(input_path),
                                     "--report", str(output_path)], cwd=ROOT, capture_output=True, text=True)
            report = load(output_path) if output_path.exists() else {}
            caught = result.returncode != 0 and report.get("checks", {}).get(required_check) is False
            results.append({"case": name, "rejected": caught, "required_failed_check": required_check,
                "failed_checks": [k for k, v in report.get("checks", {}).items() if not v],
                "exit_code": result.returncode, "error": result.stderr.strip() or None})
    report = {"task_id": "G02", "baseline_passed": True, "input_sha256": sha(ROOT / "data/processed/features.json"),
        "checker_sha256": sha(ROOT / "tools/check_geometry.py"), "regression_tool_sha256": sha(Path(__file__)),
        "cases": results, "passed": all(r["rejected"] for r in results),
        "scope": "Nine malformed derived-input cases; no source/manual changes or game tests"}
    save(ROOT / args.report, report)
    print(json.dumps({"passed": report["passed"], "rejected_cases": sum(r["rejected"] for r in results), "cases": len(results)}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

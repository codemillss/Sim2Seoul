#!/usr/bin/env python3
"""G03 malformed derived-input checks; source/manual files stay unchanged."""
from __future__ import annotations

import argparse
import copy
from pathlib import Path
import subprocess
import sys
import tempfile

from coordinate_system import ROOT
from prepare_features import canonical, load, save, sha


def record(document, identity):
    return next(r for r in document["records"] if r["feature_id"] == canonical(identity) + ":building")


def source_top(h, t):
    r = record(h, "r/10757525")
    r["height_m"] += r["roof_height_m"] or 1
    r["vertical_span_m"] = r["height_m"] - r["min_height_m"]


def invented_bottom(h, t):
    r = record(h, "r/10658335")
    assert r["source_tags"].get("min_height") is None and r["emit_coarse_body"]
    r["min_height_m"] = 3
    r["vertical_span_m"] = r["height_m"] - 3


def false_measurement(h, t):
    r = record(h, "r/10658335")
    r["height_raw_status"] = r["min_height_status"] = "independently_measured"


def missing_decisions(h, t):
    h["overlap_decisions"] = []


def shifted_surface_outer(h, t):
    t["source_surface_references"][0]["local_xz_geometry"]["coordinates"][0][0][0][0] += 10


def filled_surface_hole(h, t):
    polygon = t["source_surface_references"][0]["local_xz_geometry"]["coordinates"][0]
    del polygon[1:]


def flat_exception(h, t):
    r = next(r for r in t["records"] if r["reasons"])
    r["ground_y_m"] = 0


def invented_sea_datum(h, t):
    t["temporary_support_plane"]["physical_vertical_datum"] = "EGM2008"


def independent_tower(h, t):
    r = record(h, "w/1128365153")
    r["emit_coarse_body"] = True
    h["coarse_body_feature_ids"].append(r["feature_id"])


def changed_estimate(h, t):
    r = record(h, "w/198561926")
    r["height_m"] = 12
    r["vertical_span_m"] = 12


def guessed_compound(h, t):
    r = record(h, "r/15100454")
    r["height_class"], r["height_m"], r["vertical_span_m"] = "source_tag", 26.3, 26.3


def granted_access(h, t):
    next(r for r in t["records"] if not r["reasons"])["walkable_permission"] = True


CASES = [
    ("roof_added_again_to_source_top", source_top, "top_bottom_span_and_height_priority_values_valid"),
    ("invented_missing_source_bottom", invented_bottom, "top_bottom_span_and_height_priority_values_valid"),
    ("false_measured_status", false_measurement, "source_tags_levels_roof_and_estimation_labels_preserved"),
    ("deleted_overlap_evidence", missing_decisions, "manual_decision_evidence_and_overlap_areas_complete"),
    ("shifted_surface_outer_vertex", shifted_surface_outer, "surface_reference_ids_and_entire_source_local_geometry_match_raw"),
    ("filled_surface_inner_hole", filled_surface_hole, "jeonggwanheon_sand_relation_inner_hole_retained"),
    ("flattened_vertical_exception", flat_exception, "vertical_exceptions_not_flattened_or_granted_access"),
    ("invented_sea_level_datum", invented_sea_datum, "local_plane_not_sea_level_dsm_or_play_boundary"),
    ("higher_outline_as_independent_body", independent_tower, "one_coarse_plan_matches_height_ground_and_manual_decisions"),
    ("storey_count_as_metres", changed_estimate, "top_bottom_span_and_height_priority_values_valid"),
    ("compound_height_first_value", guessed_compound, "compound_height_stays_raw_and_held"),
    ("temporary_ground_grants_walk_permission", granted_access, "vertical_exceptions_not_flattened_or_granted_access"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="data/reports/g03_regression_check.json")
    args = parser.parse_args()
    original_h = load(ROOT / "data/processed/heights.json")
    original_t = load(ROOT / "data/processed/terrain.json")
    results = []
    with tempfile.TemporaryDirectory(prefix="sim2seoul-g03-regression-") as folder:
        folder = Path(folder)
        baseline = folder / "baseline.json"
        result = subprocess.run([sys.executable, str(ROOT / "tools/check_heights.py"), "--report", str(baseline)],
            cwd=ROOT, capture_output=True, text=True)
        if result.returncode or not load(baseline)["passed"]:
            raise SystemExit("Baseline heights/ground must pass before corruption tests")
        for name, mutate, required_check in CASES:
            h, t = copy.deepcopy(original_h), copy.deepcopy(original_t)
            mutate(h, t)
            hp, tp, rp = [folder / (name + suffix) for suffix in ["-heights.json", "-terrain.json", "-check.json"]]
            save(hp, h); save(tp, t)
            result = subprocess.run([sys.executable, str(ROOT / "tools/check_heights.py"), "--heights", str(hp),
                "--terrain", str(tp), "--report", str(rp)], cwd=ROOT, capture_output=True, text=True)
            report = load(rp) if rp.exists() else {}
            results.append({"case": name, "rejected": result.returncode != 0 and report.get("checks", {}).get(required_check) is False,
                "required_failed_check": required_check, "failed_checks": [k for k,v in report.get("checks", {}).items() if not v],
                "exit_code": result.returncode, "error": result.stderr.strip() or None})
    report = {"task_id": "G03", "baseline_passed": True, "passed": all(r["rejected"] for r in results),
        "heights_sha256": sha(ROOT / "data/processed/heights.json"), "terrain_sha256": sha(ROOT / "data/processed/terrain.json"),
        "checker_sha256": sha(ROOT / "tools/check_heights.py"), "regression_tool_sha256": sha(Path(__file__)),
        "cases": results, "scope": "Twelve derived-input corruptions; no source/manual changes or game tests"}
    save(ROOT / args.report, report)
    print({"passed": report["passed"], "rejected_cases": sum(r["rejected"] for r in results), "cases": len(results)})
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

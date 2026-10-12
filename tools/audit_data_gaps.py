#!/usr/bin/env python3
"""Inspect the current OSM attributes for D04; no geometry or game changes."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / name).read_text())


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_height(raw):
    if raw is None:
        return None, "missing"
    # Current snapshot: plain metres or explicit m. Preserve other forms for review.
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(?:m)?\s*", raw)
    if not match:
        return None, "unparsed_or_multiple_values"
    value = float(match[1])
    if not math.isfinite(value) or value <= 0:
        return None, "nonpositive_or_nonfinite"
    return value, "numeric_source_tag_not_independent_measurement"


def parse_levels(raw):
    if raw is None:
        return None, "missing"
    if not re.fullmatch(r"\s*\d+\s*", raw) or int(raw) <= 0:
        return None, "unparsed_or_nonpositive"
    return int(raw), "source_levels_not_height"


def summarize_buildings(features):
    counts = Counter()
    review = []
    heights = []
    for feature in features:
        properties = feature["properties"]
        tags = properties["tags"]
        height, height_status = parse_height(tags.get("height"))
        levels, levels_status = parse_levels(tags.get("building:levels"))
        counts["height_tag_present"] += "height" in tags
        counts["levels_tag_present"] += "building:levels" in tags
        counts["height_numeric_positive"] += height is not None
        counts["levels_positive_integer"] += levels is not None
        if height is not None:
            category = "source_height_candidate"
            heights.append(height)
        elif "height" in tags:
            category = "ambiguous_height_hold"
        elif levels is not None:
            category = "levels_estimate_candidate"
        else:
            category = "temporary_height_missing"
        counts[category] += 1
        if ("height" in tags and height is None) or ("building:levels" in tags and levels is None):
            review.append({"osm_id": properties["osm_id"], "height_raw": tags.get("height"),
                "height_status": height_status, "levels_raw": tags.get("building:levels"),
                "levels_status": levels_status, "decision": "preserve raw; no split/max/min/automatic scalar selection"})
    return {"denominator": len(features), "denominator_kind": "OSM preview shapes, not unique physical buildings",
        "counts": dict(counts), "numeric_height_range_m": [min(heights), max(heights)] if heights else None,
        "missing_numeric_height_count": len(features) - counts["height_numeric_positive"],
        "missing_numeric_height_fraction": (len(features) - counts["height_numeric_positive"]) / len(features) if features else None,
        "requires_attribute_review": review}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="data/reports/d04_data_audit.json")
    args = parser.parse_args()
    manifest = load("data/reports/extract_manifest.json")
    audit = load("data/reports/osm_audit.json")
    preview_record = audit["preview_artifact"]
    preview = ROOT / preview_record["file"]
    checks = {
        "current_osm_hash": sha256(ROOT / manifest["extract_file"]) == manifest["extract_sha256"],
        "preview_source_hash": audit["extract_sha256"] == manifest["extract_sha256"],
        "preview_size_and_hash": preview.stat().st_size == preview_record["bytes"] and sha256(preview) == preview_record["sha256"],
        "preview_config_binding": sha256(ROOT / "config/region.json") == preview_record["config_sha256"],
    }
    if not all(checks.values()):
        raise SystemExit("Current source/preview provenance mismatch; regenerate the current OSM audit first")
    features = json.loads(preview.read_text())["features"]
    groups = {}
    for feature in features:
        groups.setdefault(feature["properties"]["feature_kind"], []).append(feature)
    buildings = summarize_buildings(groups["building"])
    parts = summarize_buildings(groups["building_part"])
    checks["building_height_categories_cover_denominator"] = sum(buildings["counts"].get(k, 0) for k in
        ["source_height_candidate", "ambiguous_height_hold", "levels_estimate_candidate", "temporary_height_missing"]) == buildings["denominator"]
    road_lines = groups["highway_line"]
    exceptions = []
    flags = Counter()
    for feature in road_lines:
        properties = feature["properties"]
        tags = properties["tags"]
        reasons = []
        if tags.get("tunnel") not in (None, "no"):
            reasons.append("tunnel_or_building_passage")
        if tags.get("bridge") not in (None, "no"):
            reasons.append("bridge")
        if tags.get("highway") == "steps":
            reasons.append("steps")
        if tags.get("access") == "no":
            reasons.append("generic_access_no_requires_specific_mode_review")
        try:
            negative_layer = float(tags.get("layer", "0")) < 0
        except ValueError:
            negative_layer = False
            reasons.append("unparsed_layer")
        if negative_layer:
            reasons.append("negative_layer_not_a_metric_elevation")
        flags.update(reasons)
        if reasons:
            exceptions.append({"osm_id": properties["osm_id"], "reasons": reasons,
                "tags": {key: tags[key] for key in ["highway", "layer", "bridge", "tunnel", "access", "foot", "width"] if key in tags}})
    targets = {"w/377289797": "대한문", "w/181574577": "중화전", "r/19357693": "석조전",
               "w/517072312": "돈덕전", "w/198561926": "서울시청", "r/10757525": "서울도서관",
               "w/370019676": "서울광장"}
    landmarks = []
    for feature in features:
        identity = feature["properties"]["osm_id"]
        if identity not in targets:
            continue
        tags = feature["properties"]["tags"]
        height, state = parse_height(tags.get("height"))
        levels, _ = parse_levels(tags.get("building:levels"))
        landmarks.append({"osm_id": identity, "name": targets[identity],
            "kind": feature["properties"]["feature_kind"], "height_m_source_candidate": height,
            "height_state": state, "levels_source": levels,
            "manual_review": "height/proportions/access; no implicit interior or gate collision opening"})
    checks["seven_landmarks_present"] = len(landmarks) == len(targets)
    report = {"task_id": "D04", "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "Source attribute triage, not height estimation, geometry cleanup or route simulation",
        "source_file": manifest["extract_file"], "source_sha256": manifest["extract_sha256"],
        "preview_artifact": preview_record, "checks": checks, "passed": all(checks.values()),
        "preview_shape_counts": {kind: len(items) for kind, items in groups.items()},
        "buildings": buildings, "building_parts": parts,
        "highway_lines": {"denominator": len(road_lines),
            "width_tag_present": sum("width" in f["properties"]["tags"] for f in road_lines),
            "flag_counts_not_additive": dict(flags), "distinct_flagged_features": len(exceptions),
            "exceptions": exceptions, "rule": "Do not flatten or permit access from absence of tags"},
        "landmarks": landmarks,
        "limitations": ["No independent regional ground truth for positional/coverage completeness",
            "Numeric source height is not verified real-world measured height",
            "Building parts may overlap parent footprints; not separate building counts",
            "No estimated heights, widths, terrain, manual coordinates or final routes created"]}
    output = ROOT / args.report
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks),
        "height_categories": {k: buildings["counts"].get(k, 0) for k in
            ["source_height_candidate", "levels_estimate_candidate", "temporary_height_missing", "ambiguous_height_hold"]},
        "flagged_highway_lines": len(exceptions), "report": args.report}, ensure_ascii=False))


if __name__ == "__main__":
    main()

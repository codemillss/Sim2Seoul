#!/usr/bin/env python3
"""G03 source heights, explicit proxy assumptions and temporary ground states."""
from __future__ import annotations

import argparse
from collections import Counter
import math
from pathlib import Path
import re

import osmium
from shapely import wkb
from shapely.geometry import mapping, shape

from coordinate_system import CoordinateSystem, ROOT
from prepare_features import canonical, load, local_geometry, save, sha


def metres(raw, allow_zero=False):
    if raw is None:
        return None, "missing"
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(m)?\s*", raw)
    if not match:
        return None, "unparsed_or_multiple_values"
    value = float(match[1])
    if not math.isfinite(value) or value < 0 or (value == 0 and not allow_zero):
        return None, "nonpositive_or_nonfinite"
    return value, "single_source_metres_not_independently_measured"


def levels(raw):
    if raw is None or not re.fullmatch(r"\d+", raw.strip()) or int(raw) <= 0:
        return None
    return int(raw)


def ground_reasons(feature):
    tags = feature["source_tags"]
    reasons = []
    if tags.get("highway") == "steps":
        reasons.append("steps_not_flat_ground")
    for key in ["bridge", "tunnel"]:
        if tags.get(key) not in (None, "no"):
            reasons.append(key + "_vertical_context")
    if "layer" in tags:
        try:
            value = float(tags["layer"])
            if not math.isfinite(value) or value != 0:
                reasons.append("layer_not_metric_elevation")
        except ValueError:
            reasons.append("unparsed_layer")
    if tags.get("location") == "underground" or tags.get("building:part") == "underground":
        reasons.append("underground_context")
    if tags.get("natural") in ("water", "wetland") or tags.get("waterway"):
        reasons.append("water_context_not_walkable_ground")
    return reasons


def classify_height(feature, document, rules):
    tags = feature["source_tags"]
    identity = feature["source_refs"][0]["object_id"]
    top, status = metres(tags.get("height"))
    bottom, bottom_status = metres(tags.get("min_height"), allow_zero=True)
    roof, roof_status = metres(tags.get("roof:height"), allow_zero=True)
    count = levels(tags.get("building:levels"))
    building = feature["source_kind"] in ("building", "building_part")
    barrier = feature["source_kind"] in ("barrier", "barrier_area")
    kind, evidence, assumption = "not_dimensional_geometry", [], None
    if building or barrier:
        if tags.get("height") is not None and top is None:
            kind = "held_ambiguous_height"
        elif top is not None:
            kind = "source_tag"
        elif feature["source_kind"] == "building_part" or tags.get("building") == "roof":
            kind = "held_reference_missing_total_height"
        elif identity in rules["derived_part_top_groups"]:
            group_id = rules["derived_part_top_groups"][identity]
            group = next(g for g in document["diagnostics"]["building_groups"] if g["group_id"] == group_id)
            by_id = {f["feature_id"]: f for f in document["features"]}
            evidence = [fid for fid in group["part_feature_ids"] if metres(by_id[fid]["source_tags"].get("height"))[0] is not None]
            if evidence:
                top = max(metres(by_id[fid]["source_tags"].get("height"))[0] for fid in evidence)
                kind = "derived_explicit_component_top_envelope"
            else:
                kind = "held_no_valid_explicit_component_top"
        elif identity in rules["landmark_proxy_height_m"]:
            top, kind = rules["landmark_proxy_height_m"][identity], "temporary_landmark_proxy"
            assumption = rules["assumption_id"]
        elif count is not None:
            roof_allowance = roof if roof is not None else rules["levels_missing_roof_allowance_m"]
            top = count * rules["levels_metres_per_storey"] + roof_allowance
            kind, assumption = "estimated_from_above_ground_levels", rules["assumption_id"]
        elif barrier:
            top = rules["default_barrier_height_m"][tags["barrier"]]
            kind, assumption = "temporary_barrier_default", rules["assumption_id"]
        else:
            top = (rules["default_historic_proxy_height_m"] if "historic" in tags else
                rules["default_building_height_m"].get(tags.get("building"), rules["default_unlisted_building_height_m"]))
            kind, assumption = "temporary_purpose_default", rules["assumption_id"]
        if bottom is None and tags.get("min_height") is None:
            bottom, bottom_status = 0.0, "implicit_local_bottom_reference_not_observed_ground"
        if tags.get("min_height") is not None and bottom is None or top is not None and bottom is not None and bottom >= top:
            kind = "held_invalid_vertical_span"
            top = None
    else:
        top, bottom = None, None
    return {"feature_id": feature["feature_id"], "source_object_id": identity,
        "source_tags": tags, "source_role_G02": feature["generation"]["role"],
        "height_class": kind, "height_m": top, "min_height_m": bottom,
        "vertical_span_m": top - bottom if top is not None and bottom is not None else None,
        "height_raw_status": status, "min_height_status": bottom_status,
        "roof_height_m": roof, "roof_height_status": roof_status, "roof_height_included_in_total_not_added_twice": True,
        "source_levels": count, "assumption_id": assumption, "component_evidence_ids": evidence,
        "independent_height_accuracy": "unverified", "emit_coarse_body": False,
        "emission_reason": "source/reference/non-body role; selected separately after ground checks"}


class SurfaceReference(osmium.SimpleHandler):
    def __init__(self, identities, system):
        super().__init__()
        self.identities, self.system, self.surfaces = set(identities), system, []
        self.factory = osmium.geom.WKBFactory()

    def area(self, area):
        identity = ("w/" if area.from_way() else "r/") + str(area.orig_id())
        if identity in self.identities:
            original = wkb.loads(self.factory.create_multipolygon(area), hex=True)
            self.surfaces.append({"source_object_id": identity, "source_crs": "EPSG:4326",
                "source_geometry": mapping(original), "local_xz_geometry": mapping(local_geometry(original, self.system)),
                "status": "source_surface_reference_only; holes retained; not automatically walkable"})


def prepare():
    document = load(ROOT / "data/processed/features.json")
    geometry_report = load(ROOT / "data/reports/geometry_check.json")
    rules = load(ROOT / "config/height_rules.json")
    decisions = load(ROOT / "data/manual/height_review_decisions.json")
    system = CoordinateSystem()
    if not geometry_report["passed"] or geometry_report["input_sha256"] != sha(ROOT / "data/processed/features.json"):
        raise ValueError("Current G02 geometry checks required before heights")
    if (geometry_report["checker_sha256"] != sha(ROOT / "tools/check_geometry.py")
            or geometry_report["provenance"] != document["provenance"]):
        raise ValueError("Geometry checker or input binding changed; rerun G02 checks")
    bindings = {"source_sha256": document["provenance"]["source_file"], "policy_sha256": "config/data_usage.json",
        "manual_queue_sha256": "data/manual/review_queue.json", "config_sha256": "config/region.json",
        "rules_sha256": "config/geometry_rules.json", "generator_sha256": "tools/prepare_features.py",
        "coordinate_module_sha256": "tools/coordinate_system.py"}
    if not all(sha(ROOT / name) == document["provenance"][key] for key, name in bindings.items()) or decisions["source_sha256"] != document["provenance"]["source_sha256"]:
        raise ValueError("G03 input/config/manual provenance mismatch")
    positive_rules = [rules["levels_metres_per_storey"], rules["default_unlisted_building_height_m"],
        rules["default_historic_proxy_height_m"], *rules["default_building_height_m"].values(),
        *rules["landmark_proxy_height_m"].values(), *rules["default_barrier_height_m"].values()]
    if not all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v > 0 for v in positive_rules):
        raise ValueError("Height assumptions must be finite positive metre values")
    if rules["schema_version"] != 1 or rules["temporary_ground_y_m"] != 0.0 or rules["levels_missing_roof_allowance_m"] < 0 or rules["support_plane_padding_m"] < 0:
        raise ValueError("Unsupported G03 engineering datum or parameter range")
    features = document["features"]
    by_id = {f["feature_id"]: f for f in features}
    by_source = {f["source_refs"][0]["object_id"]: f for f in features if f["source_kind"] == "building"}
    selected = set(document["coarse_body_feature_ids"])
    review_results = []
    for decision in decisions["decisions"]:
        body, reference = by_source[decision["selected_body"]], by_source[decision["reference_only"]]
        body_geom, ref_geom = shape(body["geometry"]), shape(reference["geometry"])
        overlap = body_geom.intersection(ref_geom).area
        if overlap / min(body_geom.area, ref_geom.area) < 0.99:
            raise ValueError("Manual overlap decision no longer matches source geometry")
        selected.add(body["feature_id"])
        selected.discard(reference["feature_id"])
        review_results.append({**decision, "body_area_m2": body_geom.area, "reference_area_m2": ref_geom.area,
            "overlap_area_m2": overlap, "decision_kind": "provisional_single_coarse_proxy_not_surveyed_correction"})
    heights, ground = [], []
    for feature in features:
        fid = feature["feature_id"]
        reasons = ground_reasons(feature)
        ground.append({"feature_id": fid, "ground_class": "vertical_or_nonwalkable_review" if reasons else "temporary_support_plane_reference",
            "ground_y_m": None if reasons else rules["temporary_ground_y_m"], "reasons": reasons,
            "physical_elevation_m": None, "walkable_permission": None, "terrain_shape_verified": False})
        h = classify_height(feature, document, rules)
        if fid in selected:
            h["emit_coarse_body"] = h["height_m"] is not None and h["vertical_span_m"] > 0 and not reasons
            h["emission_reason"] = "single coarse proxy with explicit temporary ground" if h["emit_coarse_body"] else "held height or unresolved vertical ground context"
        elif feature["source_kind"] in ("building", "building_part"):
            h["emission_reason"] = "retained roof/part/overlap reference; not a second independent coarse body"
        heights.append(h)
    geoms = [shape(f["geometry"]) for f in features]
    padding = rules["support_plane_padding_m"]
    extent = [min(g.bounds[0] for g in geoms) - padding, min(g.bounds[1] for g in geoms) - padding,
              max(g.bounds[2] for g in geoms) + padding, max(g.bounds[3] for g in geoms) + padding]
    surface_ids = [d["relation_surface_hole"] for d in decisions["decisions"] if d["relation_surface_hole"]]
    surfaces = SurfaceReference(surface_ids, system)
    surfaces.apply_file(ROOT / document["provenance"]["source_file"], locations=True)
    if {s["source_object_id"] for s in surfaces.surfaces} != set(surface_ids):
        raise ValueError("Missing referenced surface relation; do not discard the ground hole")
    provenance = {"features_sha256": sha(ROOT / "data/processed/features.json"),
        "geometry_report_sha256": sha(ROOT / "data/reports/geometry_check.json"),
        "height_rules_sha256": sha(ROOT / "config/height_rules.json"),
        "decisions_sha256": sha(ROOT / "data/manual/height_review_decisions.json"),
        "official_evidence_sha256": sha(ROOT / "data/reports/g03_official_evidence.json"),
        "generator_sha256": sha(Path(__file__)), "source_file": document["provenance"]["source_file"],
        "source_sha256": document["provenance"]["source_sha256"]}
    base = {"schema_version": 1, "task_id": "G03", "provenance": provenance, "coordinate_system": document["coordinate_system"]}
    height_document = {**base, "rules": rules, "records": heights, "overlap_decisions": review_results,
        "height_class_counts": dict(sorted(Counter(h["height_class"] for h in heights).items())),
        "coarse_body_feature_ids": [h["feature_id"] for h in heights if h["emit_coarse_body"]],
        "not_generated": "No mesh/collision, no detailed part reconstruction, no measured height claim"}
    terrain_document = {**base, "temporary_support_plane": {"ground_y_m": rules["temporary_ground_y_m"],
        "local_xz_extent": extent, "physical_vertical_datum": None, "is_playable_boundary": False,
        "access_granted_by_plane": False, "source": "explicit engineering assumption, not DSM/observed terrain"},
        "records": ground, "source_surface_references": surfaces.surfaces,
        "ground_class_counts": dict(sorted(Counter(g["ground_class"] for g in ground).items())),
        "not_generated": "No terrain mesh; exceptions need G04/W grounding before play"}
    return height_document, terrain_document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--heights", default="data/processed/heights.json")
    parser.add_argument("--terrain", default="data/processed/terrain.json")
    args = parser.parse_args()
    heights, terrain = prepare()
    save(ROOT / args.heights, heights)
    save(ROOT / args.terrain, terrain)
    print({"height_classes": heights["height_class_counts"], "coarse_bodies": len(heights["coarse_body_feature_ids"]), "ground_classes": terrain["ground_class_counts"]})


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check G03 classification, source semantics, proxy selection and ground holds."""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path

from shapely import STRtree
from shapely.geometry import Polygon, shape

from coordinate_system import CoordinateSystem, ROOT
from prepare_features import canonical, load, save, sha, SourceIndex
from prepare_heights import metres, levels, ground_reasons, SurfaceReference


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--heights", default="data/processed/heights.json")
    parser.add_argument("--terrain", default="data/processed/terrain.json")
    parser.add_argument("--report", default="data/reports/height_check.json")
    args = parser.parse_args()
    heights, terrain = load(ROOT / args.heights), load(ROOT / args.terrain)
    features_doc = load(ROOT / "data/processed/features.json")
    features = {f["feature_id"]: f for f in features_doc["features"]}
    p = heights["provenance"]
    bindings = {"features_sha256": "data/processed/features.json", "geometry_report_sha256": "data/reports/geometry_check.json",
        "height_rules_sha256": "config/height_rules.json", "decisions_sha256": "data/manual/height_review_decisions.json",
        "official_evidence_sha256": "data/reports/g03_official_evidence.json", "generator_sha256": "tools/prepare_heights.py",
        "source_sha256": p["source_file"]}
    checks = {"current_input_rule_manual_and_generator_hashes": all(sha(ROOT / name) == p[key] for key, name in bindings.items()),
        "terrain_and_height_provenance_match": terrain["provenance"] == p}
    if not all(checks.values()):
        raise SystemExit("G03 provenance mismatch; review changes and regenerate height/terrain together")
    rules = load(ROOT / "config/height_rules.json")
    decisions = load(ROOT / "data/manual/height_review_decisions.json")
    hs = {h["feature_id"]: h for h in heights["records"]}
    gs = {g["feature_id"]: g for g in terrain["records"]}
    checks["all_source_features_have_unique_height_and_ground_states"] = len(hs) == len(heights["records"]) == len(features) and len(gs) == len(terrain["records"]) == len(features) and set(hs) == set(gs) == set(features)
    checks["coordinate_schema_and_embedded_rules_match"] = heights["rules"] == rules and heights["coordinate_system"] == terrain["coordinate_system"] == features_doc["coordinate_system"] and heights["schema_version"] == terrain["schema_version"] == 1
    attribute_errors, numeric_errors, ground_errors = [], [], []
    for fid, f in features.items():
        h, g, tags = hs[fid], gs[fid], f["source_tags"]
        if h["source_tags"] != tags or h["source_object_id"] != f["source_refs"][0]["object_id"] or h["source_role_G02"] != f["generation"]["role"]:
            attribute_errors.append(fid)
        top, bottom, roof = h["height_m"], h["min_height_m"], h["roof_height_m"]
        kind = h["height_class"]
        source_top, top_status = metres(tags.get("height"))
        source_bottom, bottom_status = metres(tags.get("min_height"), allow_zero=True)
        source_roof, roof_status = metres(tags.get("roof:height"), allow_zero=True)
        count = levels(tags.get("building:levels"))
        if roof != source_roof or h["source_levels"] != count:
            attribute_errors.append(fid)
        if kind == "source_tag" and top != source_top:
            numeric_errors.append(fid)
        dimensional = f["source_kind"] in ("building", "building_part", "barrier", "barrier_area")
        expected_bottom = (0.0 if tags.get("min_height") is None else source_bottom) if dimensional else None
        if dimensional and tags.get("min_height") is None:
            bottom_status = "implicit_local_bottom_reference_not_observed_ground"
        if bottom != expected_bottom:
            numeric_errors.append(fid)
        if h["height_raw_status"] != top_status or h["min_height_status"] != bottom_status or h["roof_height_status"] != roof_status:
            attribute_errors.append(fid)
        if not dimensional:
            expected_class = "not_dimensional_geometry"
        elif tags.get("height") is not None:
            expected_class = "source_tag" if source_top is not None else "held_ambiguous_height"
        elif f["source_kind"] == "building_part" or tags.get("building") == "roof":
            expected_class = "held_reference_missing_total_height"
        elif identity := f["source_refs"][0]["object_id"]:
            expected_class = ("derived_explicit_component_top_envelope" if identity in rules["derived_part_top_groups"] else
                "temporary_landmark_proxy" if identity in rules["landmark_proxy_height_m"] else
                "estimated_from_above_ground_levels" if count is not None else
                "temporary_barrier_default" if f["source_kind"] in ("barrier", "barrier_area") else "temporary_purpose_default")
        expected_top = source_top
        identity = f["source_refs"][0]["object_id"]
        if expected_class == "temporary_landmark_proxy":
            expected_top = rules["landmark_proxy_height_m"][identity]
        elif expected_class == "estimated_from_above_ground_levels":
            expected_top = count * rules["levels_metres_per_storey"] + (source_roof if source_roof is not None else rules["levels_missing_roof_allowance_m"])
        elif expected_class == "temporary_barrier_default":
            expected_top = rules["default_barrier_height_m"][tags["barrier"]]
        elif expected_class == "temporary_purpose_default":
            expected_top = rules["default_historic_proxy_height_m"] if "historic" in tags else rules["default_building_height_m"].get(tags.get("building"), rules["default_unlisted_building_height_m"])
        elif expected_class == "derived_explicit_component_top_envelope":
            group = next(g for g in features_doc["diagnostics"]["building_groups"] if g["group_id"] == rules["derived_part_top_groups"][identity])
            component_tops = [metres(features[fid]["source_tags"].get("height"))[0] for fid in group["part_feature_ids"]]
            expected_top = max((v for v in component_tops if v is not None), default=None)
            if expected_top is None:
                expected_class = "held_no_valid_explicit_component_top"
        if dimensional and ((tags.get("min_height") is not None and source_bottom is None)
                or expected_top is not None and expected_bottom is not None and expected_bottom >= expected_top):
            expected_class = "held_invalid_vertical_span"
        if kind != expected_class:
            numeric_errors.append(fid)
        if kind == "estimated_from_above_ground_levels" and (count is None or top != count * rules["levels_metres_per_storey"] + (source_roof if source_roof is not None else rules["levels_missing_roof_allowance_m"])):
            numeric_errors.append(fid)
        identity = f["source_refs"][0]["object_id"]
        if kind == "temporary_landmark_proxy" and top != rules["landmark_proxy_height_m"].get(identity):
            numeric_errors.append(fid)
        if kind == "temporary_purpose_default":
            expected = rules["default_historic_proxy_height_m"] if "historic" in tags else rules["default_building_height_m"].get(tags.get("building"), rules["default_unlisted_building_height_m"])
            if top != expected:
                numeric_errors.append(fid)
        if kind == "temporary_barrier_default" and top != rules["default_barrier_height_m"].get(tags.get("barrier")):
            numeric_errors.append(fid)
        if top is None and h["vertical_span_m"] is not None:
            numeric_errors.append(fid)
        if kind.startswith("held_") and (top is not None or h["emit_coarse_body"]):
            numeric_errors.append(fid)
        if kind.startswith("temporary_") or kind == "estimated_from_above_ground_levels":
            if h["assumption_id"] != rules["assumption_id"]:
                attribute_errors.append(fid)
        if h["independent_height_accuracy"] != "unverified" or not h["roof_height_included_in_total_not_added_twice"]:
            attribute_errors.append(fid)
        if top is not None and (not math.isfinite(top) or top <= 0 or bottom is None or not math.isfinite(bottom) or bottom < 0 or bottom >= top or h["vertical_span_m"] != top - bottom):
            numeric_errors.append(fid)
        reasons = ground_reasons(f)
        if g["reasons"] != reasons or g["ground_y_m"] != (None if reasons else rules["temporary_ground_y_m"]) or g["ground_class"] != ("vertical_or_nonwalkable_review" if reasons else "temporary_support_plane_reference") or g["physical_elevation_m"] is not None or g["walkable_permission"] is not None or g["terrain_shape_verified"]:
            ground_errors.append(fid)
        if h["emit_coarse_body"] and reasons:
            ground_errors.append(fid)
    checks["source_tags_levels_roof_and_estimation_labels_preserved"] = not attribute_errors
    checks["top_bottom_span_and_height_priority_values_valid"] = not numeric_errors
    checks["vertical_exceptions_not_flattened_or_granted_access"] = not ground_errors
    checks["height_and_ground_class_counts_match_records"] = heights["height_class_counts"] == dict(Counter(h["height_class"] for h in hs.values())) and terrain["ground_class_counts"] == dict(Counter(g["ground_class"] for g in gs.values()))
    selected = set(features_doc["coarse_body_feature_ids"])
    expected_decisions = []
    for d in decisions["decisions"]:
        selected.add(canonical(d["selected_body"]) + ":building")
        selected.discard(canonical(d["reference_only"]) + ":building")
        body = shape(features[canonical(d["selected_body"]) + ":building"]["geometry"])
        reference = shape(features[canonical(d["reference_only"]) + ":building"]["geometry"])
        expected_decisions.append({**d, "body_area_m2": body.area, "reference_area_m2": reference.area,
            "overlap_area_m2": body.intersection(reference).area,
            "decision_kind": "provisional_single_coarse_proxy_not_surveyed_correction"})
    checks["manual_decision_evidence_and_overlap_areas_complete"] = heights["overlap_decisions"] == expected_decisions
    expected_emitted = {fid for fid in selected if hs[fid]["height_m"] is not None and not gs[fid]["reasons"]}
    emitted = heights["coarse_body_feature_ids"]
    checks["one_coarse_plan_matches_height_ground_and_manual_decisions"] = len(emitted) == len(set(emitted)) and set(emitted) == expected_emitted == {fid for fid,h in hs.items() if h["emit_coarse_body"]}
    checks["parts_roofs_and_reference_outlines_not_independent_bodies"] = all(features[fid]["source_kind"] == "building" and features[fid]["source_tags"].get("building") != "roof" for fid in emitted) and all(canonical(d["reference_only"])+":building" not in emitted for d in decisions["decisions"])
    tree = STRtree([shape(features[fid]["geometry"]) for fid in emitted])
    overlaps = []
    for n, fid in enumerate(emitted):
        for k in tree.query(shape(features[fid]["geometry"]), predicate="intersects"):
            if k > n and shape(features[fid]["geometry"]).intersection(shape(features[emitted[k]]["geometry"])).area > .01:
                overlaps.append([fid, emitted[k]])
    checks["no_duplicate_footprint_volume_in_coarse_body_plan"] = not overlaps
    compound = hs[canonical("r/15100454")+":building"]
    checks["compound_height_stays_raw_and_held"] = compound["source_tags"]["height"] == "26.3;17.2" and compound["height_class"] == "held_ambiguous_height" and compound["height_m"] is None
    seok = hs[canonical("r/19357693")+":building"]
    group = next(g for g in features_doc["diagnostics"]["building_groups"] if g["group_id"] == "osm:relation:19357702")
    expected_parts = [fid for fid in group["part_feature_ids"] if metres(features[fid]["source_tags"].get("height"))[0] is not None]
    checks["seokjojeon_envelope_uses_only_explicit_single_component_tops"] = seok["height_class"] == "derived_explicit_component_top_envelope" and set(seok["component_evidence_ids"]) == set(expected_parts) and seok["height_m"] == max(metres(features[fid]["source_tags"]["height"])[0] for fid in expected_parts)
    source_index = SourceIndex(); source_index.apply_file(ROOT / p["source_file"])
    surfaces = terrain["source_surface_references"]
    surface_ids = [d["relation_surface_hole"] for d in decisions["decisions"] if d["relation_surface_hole"]]
    expected_surfaces = SurfaceReference(surface_ids, CoordinateSystem())
    expected_surfaces.apply_file(ROOT / p["source_file"], locations=True)
    checks["surface_reference_ids_and_entire_source_local_geometry_match_raw"] = (len(surfaces) == len(surface_ids)
        and {s["source_object_id"] for s in surfaces} == set(surface_ids)
        and json.dumps(surfaces, sort_keys=True) == json.dumps(expected_surfaces.surfaces, sort_keys=True))
    surface = next((s for s in surfaces if s["source_object_id"] == "r/10757318"), None)
    hole_record = features[canonical("w/776767573")+":building"]
    holes = [Polygon(r) for poly in shape(surface["local_xz_geometry"]).geoms for r in poly.interiors] if surface else []
    hole_geom = shape(hole_record["geometry"])
    checks["jeonggwanheon_sand_relation_inner_hole_retained"] = surface is not None and any(
        m["object_id"] == "w/776767573" and m["role"] == "inner" for m in source_index.objects["r/10757318"]["members"]) and any(
        hole.equals(hole_geom.geoms[0]) for hole in holes)
    tower = hs[canonical("w/1128365153")+":building"]
    checks["sangdong_higher_candidate_retained_without_invented_start_height"] = tower["height_m"] == 52.1 and tower["min_height_m"] == 0 and tower["source_tags"].get("min_height") is None and not tower["emit_coarse_body"]
    plane = terrain["temporary_support_plane"]
    checks["local_plane_not_sea_level_dsm_or_play_boundary"] = plane["ground_y_m"] == 0 and plane["physical_vertical_datum"] is None and plane["is_playable_boundary"] is False and plane["access_granted_by_plane"] is False
    geometries = [shape(f["geometry"]) for f in features.values()]
    pad = rules["support_plane_padding_m"]
    checks["temporary_plane_extent_matches_declared_technical_envelope"] = plane["local_xz_extent"] == [
        min(g.bounds[0] for g in geometries)-pad, min(g.bounds[1] for g in geometries)-pad,
        max(g.bounds[2] for g in geometries)+pad, max(g.bounds[3] for g in geometries)+pad]
    checks = {k: bool(v) for k,v in checks.items()}
    report = {"task_id":"G03","scope":"Height/ground classification and provisional single-body overlap decisions; not physical validation",
        "provenance":p,"checker_sha256":sha(Path(__file__)),"heights_sha256":sha(ROOT/args.heights),"terrain_sha256":sha(ROOT/args.terrain),
        "checks":checks,"passed":all(checks.values()),"record_count":len(hs),"height_class_counts":heights["height_class_counts"],
        "ground_class_counts":terrain["ground_class_counts"],"coarse_body_count":len(emitted),"overlap_decisions":heights["overlap_decisions"],
        "attribute_errors":attribute_errors,"numeric_errors":numeric_errors,"ground_errors":ground_errors,"coarse_overlap_pairs":overlaps,
        "unresolved_ground_feature_ids":[fid for fid,g in gs.items() if g["reasons"]],
        "not_run":["Independent measured height/ground","Detailed component vertical mesh reconstruction","G04 route/width/boundary","Godot collision/walking","M4 Pro"]}
    save(ROOT/args.report,report)
    print({"passed":report["passed"],"checks":len(checks),"records":len(hs),"coarse_bodies":len(emitted)})
    if not report["passed"]:raise SystemExit(1)


if __name__ == "__main__":main()

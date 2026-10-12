#!/usr/bin/env python3
"""Independently check the G02 local shapes, source links and emission roles."""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import platform

import shapely
from shapely import STRtree, get_coordinates
from shapely.geometry import Polygon, shape

from coordinate_system import CoordinateSystem, ROOT
from prepare_features import SourceIndex, canonical, load, save, sha, topology_stats


def transformed_coordinates(value, system):
    if isinstance(value[0], (int, float)):
        x, _, z = system.to_world(*value)
        return [x, z]
    return [transformed_coordinates(child, system) for child in value]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="data/processed/features.json")
    parser.add_argument("--report", default="data/reports/geometry_check.json")
    args = parser.parse_args()
    document = load(ROOT / args.input)
    system = CoordinateSystem()
    p = document["provenance"]
    current_audit = load(ROOT / "data/reports/osm_audit.json")
    bindings = {
        "source_sha256": p["source_file"], "config_sha256": "config/region.json",
        "rules_sha256": "config/geometry_rules.json", "policy_sha256": "config/data_usage.json",
        "manual_queue_sha256": "data/manual/review_queue.json", "overture_sha256": p["overture_file"],
        "coordinate_report_sha256": "data/reports/coordinate_check.json",
        "generator_sha256": "tools/prepare_features.py", "coordinate_module_sha256": "tools/coordinate_system.py",
    }
    checks = {"input_provenance_matches_current_files": all(sha(ROOT / name) == p[key] for key, name in bindings.items()),
        "preview_provenance_is_current": p["preview_artifact"] == current_audit["preview_artifact"] and
            sha(ROOT / p["preview_artifact"]["file"]) == p["preview_artifact"]["sha256"]}
    if not all(checks.values()):
        raise SystemExit("G02 derived-input provenance mismatch; regenerate after reviewing source changes")
    current_rules = load(ROOT / "config/geometry_rules.json")
    checks["embedded_rules_match_current_configuration"] = document["geometry_rules"] == current_rules
    checks["document_coordinate_contract_and_schema_match"] = (
        document["schema_version"] == 1 and document["task_id"] == "G02"
        and document["format"] == "Sim2Seoul local-XZ feature document; NOT RFC7946 GeoJSON"
        and document["coordinate_system"] == {"projected_crs": system.config["metric_crs"],
            "origin_lon_lat": list(system.origin_lon_lat), "origin_projected_east_north_m": list(system.origin_east_north),
            "geometry_axis_order": ["x", "z"], "world_axes": system.config["world_axes"], "unit": "metre",
            "vertical_assignment": "absent; not synthetic ground or sea level"})
    originals = load(ROOT / p["preview_artifact"]["file"])["features"]
    by_original = {f["id"]: f for f in originals}
    features = document["features"]
    by_id = {f["feature_id"]: f for f in features}
    raw = SourceIndex()
    raw.apply_file(ROOT / p["source_file"])
    geometries = {}
    geometry_failures, source_failures, attribute_failures = [], [], []
    max_inverse_error, max_shape_error = 0, 0
    original_holes, result_holes = 0, 0
    for f in features:
        fid = f["feature_id"]
        source = f["source_refs"][0]
        identity = source["object_id"]
        original = by_original[identity + ":" + f["source_kind"]]
        if not (source["snapshot_sha256"] == p["source_sha256"] and source["file"] == p["source_file"]
                and f["source_tags"] == raw.objects[identity]["tags"]
                and f["source_geometry"]["geometry"] == original["geometry"]
                and f["source_geometry"]["crs"] == "EPSG:4326" and f["source_geometry"]["axis_order"] == ["longitude", "latitude"]
                and f["feature_id"] == canonical(identity) + ":" + f["source_kind"]
                and f["source_topology"] == {k: raw.objects[identity][k] for k in ("node_ids", "members") if k in raw.objects[identity]}):
            source_failures.append(fid)
        tags = raw.objects[identity]["tags"]
        if "building" in f and not (f["building"]["height_raw"] == tags.get("height")
                and f["building"]["min_height_raw"] == tags.get("min_height")
                and f["building"]["levels_raw"] == tags.get("building:levels")
                and f["building"]["roof_tags"] == {k: v for k, v in tags.items() if k.startswith("roof:")}):
            attribute_failures.append(fid)
        if "road" in f and not all(f["road"][key] == tags.get(raw_key) for key, raw_key in [
                ("width_raw", "width"), ("lanes_raw", "lanes"), ("oneway", "oneway"),
                ("layer_raw", "layer"), ("bridge", "bridge"), ("tunnel", "tunnel")]):
            attribute_failures.append(fid)
        if f["access"]["source_tags"] != {k: tags[k] for k in ("access", "foot", "vehicle", "motor_vehicle", "bicycle", "opening_hours") if k in tags}:
            attribute_failures.append(fid)
        expected = shape({"type": original["geometry"]["type"],
            "coordinates": transformed_coordinates(original["geometry"]["coordinates"], system)})
        actual = shape(f["geometry"])
        geometries[fid] = actual
        a_stats, b_stats = topology_stats(expected), topology_stats(actual)
        original_holes += a_stats["hole_count"]
        result_holes += b_stats["hole_count"]
        shape_error = actual.hausdorff_distance(expected)
        max_shape_error = max(max_shape_error, shape_error)
        polygons = list(actual.geoms) if actual.geom_type == "MultiPolygon" else [actual] if actual.geom_type == "Polygon" else []
        coords = get_coordinates(actual)
        lon, lat = system.inverse.transform(coords[:, 0] + system.origin_east_north[0],
                                             system.origin_east_north[1] - coords[:, 1], errcheck=True)
        source_coords = get_coordinates(shape(original["geometry"]))
        inverse_set = Counter((round(x, 10), round(y, 10)) for x, y in zip(lon, lat))
        source_set = Counter((round(x, 10), round(y, 10)) for x, y in source_coords)
        # Measure all source vertices directly, independent of canonical ring order.
        for x, y in source_coords:
            reverse = system.to_lon_lat(*system.to_world(x, y))
            max_inverse_error = max(max_inverse_error, abs(reverse[0] - x), abs(reverse[1] - y))
        if (actual.is_empty or not actual.is_valid or not all(math.isfinite(v) for v in coords.flat)
                or actual.geom_type != expected.geom_type or a_stats["hole_count"] != b_stats["hole_count"]
                or a_stats["polygon_count"] != b_stats["polygon_count"] or shape_error > 1e-6
                or abs(actual.area - expected.area) > max(1e-7, expected.area * 1e-9)
                or inverse_set != source_set or any(not poly.exterior.is_ccw or any(r.is_ccw for r in poly.interiors) for poly in polygons)
                or f["geometry"]["coordinate_space"] != "local_xz" or f["geometry"]["axis_order"] != ["x", "z"]
                or f["geometry"]["unit"] != "metre"):
            geometry_failures.append(fid)
    checks["all_source_shapes_retained_with_unique_ids"] = len(features) == len(originals) == len(by_id) and {
        f["source_refs"][0]["object_id"] + ":" + f["source_kind"] for f in features} == set(by_original)
    checks["raw_tags_topology_coordinates_and_ids_preserved"] = not source_failures
    checks["downstream_raw_height_roof_road_and_access_attributes_match_source"] = not attribute_failures
    checks["valid_finite_topology_winding_and_shape_preserved"] = not geometry_failures
    checks["all_vertices_roundtrip_within_1e_minus_8_degrees"] = max_inverse_error <= 1e-8
    checks["all_holes_preserved"] = original_holes == result_holes
    checks["no_automatic_repairs_or_bbox_clipping"] = not document["diagnostics"]["automatic_repairs"] and not document["diagnostics"]["bbox_clipped_features"]
    primary = document["coarse_body_feature_ids"]
    checks["coarse_plan_contains_only_primary_building_footprints"] = len(primary) == len(set(primary)) and set(primary) == {
        f["feature_id"] for f in features if f["generation"]["role"] == "primary_footprint"} and all(
        by_id[i]["source_kind"] == "building" and by_id[i]["source_tags"].get("building") != "roof" for i in primary)
    threshold = current_rules["overlap_report_min_area_m2"]
    tree = STRtree([geometries[i] for i in primary])
    active_overlap = []
    for n, fid in enumerate(primary):
        for k in tree.query(geometries[fid], predicate="intersects"):
            if k > n and geometries[fid].intersection(geometries[primary[k]]).area > threshold:
                active_overlap.append([fid, primary[k]])
    checks["no_unexplained_overlap_in_coarse_body_plan"] = not active_overlap
    checks["parts_and_roofs_are_not_independent_coarse_volumes"] = all(
        f["feature_id"] not in primary for f in features if f["source_kind"] == "building_part" or f["source_tags"].get("building") == "roof")
    group_failures = []
    expected_groups = {}
    expected_backlinks = {f["feature_id"]: set() for f in features}
    for identity, obj in raw.objects.items():
        if obj["tags"].get("type") != "building":
            continue
        outlines, parts = set(), set()
        for member in obj["members"]:
            kind = {"outline": "building", "part": "building_part"}.get(member["role"])
            fid = canonical(member["object_id"]) + ":" + str(kind)
            if kind and fid in by_id:
                (outlines if kind == "building" else parts).add(fid)
        if outlines or parts:
            gid = canonical(identity)
            expected_groups[gid] = (outlines, parts)
            for fid in outlines | parts:
                expected_backlinks[fid].add(gid)
    groups = document["diagnostics"]["building_groups"]
    checks["all_raw_building_groups_and_reverse_links_present"] = len(groups) == len(expected_groups) and {
        g["group_id"] for g in groups} == set(expected_groups) and all(
        set(f["building_group_refs"]) == expected_backlinks[f["feature_id"]] for f in features)
    for group in document["diagnostics"]["building_groups"]:
        gid = group["group_id"]
        source_rel = "r/" + gid.rsplit(":", 1)[1]
        members = raw.objects[source_rel]["members"]
        for role, field in [("outline", "outline_feature_ids"), ("part", "part_feature_ids")]:
            expected_ids = {f["feature_id"] for m in members if m["role"] == role for f in features
                if f["source_refs"][0]["object_id"] == m["object_id"] and f["source_kind"] == ("building" if role == "outline" else "building_part")}
            if set(group[field]) != expected_ids or any(gid not in by_id[i]["building_group_refs"] for i in expected_ids):
                group_failures.append(gid)
        if group["source_members"] != members:
            group_failures.append(gid)
    checks["explicit_building_relations_link_all_available_outline_parts"] = not group_failures
    building_ids = [f["feature_id"] for f in features if f["source_kind"] == "building"]
    body_tree = STRtree([geometries[i] for i in building_ids])
    role_failures = []
    for n, fid in enumerate(building_ids):
        for k in body_tree.query(geometries[fid], predicate="intersects"):
            other = building_ids[k]
            if k <= n or geometries[fid].intersection(geometries[other]).area <= threshold:
                continue
            if by_id[fid]["source_tags"].get("building") == "roof" or by_id[other]["source_tags"].get("building") == "roof":
                continue
            alias = any(by_id[i]["generation"]["role"] in {"exact_geometry_alias", "relation_member_reference"} for i in [fid, other])
            if not alias and any(by_id[i]["generation"]["role"] != "body_overlap_hold" for i in [fid, other]):
                role_failures.append([fid, other])
    for f in features:
        if f["generation"]["role"] == "exact_geometry_alias":
            original = by_id.get(f["generation"].get("primary_feature_id"))
            if not original or original["source_kind"] != f["source_kind"] or original["source_tags"] != f["source_tags"] or not geometries[f["feature_id"]].equals(geometries[original["feature_id"]]):
                role_failures.append([f["feature_id"], "invalid alias"])
    checks["overlap_holds_and_exact_aliases_have_geometry_semantic_basis"] = not role_failures
    outer_violations = []
    for f in features:
        if f["source_kind"] not in ("building", "building_part"):
            continue
        for m in f["source_topology"].get("members", []):
            other = canonical(m["object_id"]) + ":" + f["source_kind"]
            if m["role"] in ("outer", "") and other in by_id and other in primary:
                outer_violations.append([f["feature_id"], other])
    checks["relation_outer_members_not_second_independent_bodies"] = not outer_violations
    checks["barrier_line_area_not_double_wall_plan"] = all(
        by_id[pair["area"]]["generation"]["role"] == "boundary_area_reference"
        for pair in document["diagnostics"]["barrier_same_entity_representations"])
    policy = load(ROOT / "config/data_usage.json")
    candidates = document["diagnostics"]["overture_candidates"]
    checks["all_22_overture_candidates_reviewed_and_held"] = {f["overture_id"] for f in candidates} == set(
        policy["supplemental_buildings"]["candidate_ids_not_automatically_approved"]) and len(candidates) == 22 and all(
        f["geometry_valid"] and f["status"] == "held_not_in_base_feature_set" for f in candidates)
    checks["height_ground_width_and_access_not_invented"] = all(
        f["quality"]["height"] == "pending_G03" and f["quality"]["ground"] == "pending_G03"
        and f["access"]["game_permission"] is None
        and ("building" not in f or all(f["building"][key] is None for key in ["height_m", "min_height_m", "height_assumption_id"]))
        and ("road" not in f or f["road"]["width_m"] is None and f["road"]["pedestrian_allowed"] is None) for f in features)
    targets = {"w/377289797": "building", "w/181574577": "building", "r/19357693": "building",
        "w/517072312": "building", "w/198561926": "building", "r/10757525": "building", "w/370019676": "land_area"}
    checks["seven_landmarks_retained_and_six_bodies_not_held"] = all(
        canonical(i) + ":" + kind in by_id and (kind != "building" or canonical(i) + ":" + kind in primary) for i, kind in targets.items())
    courtyard = geometries[canonical("r/10754689") + ":highway_area"]
    hall = geometries[canonical("w/181574577") + ":building"]
    holes = [Polygon(r) for poly in courtyard.geoms for r in poly.interiors]
    checks["junghwajeon_courtyard_hole_not_filled"] = courtyard.intersection(hall).area <= 1e-6 and any(
        hole.intersection(hall).area / hall.area >= 0.99 for hole in holes)
    checks["compound_height_raw_preserved"] = by_id[canonical("r/15100454") + ":building"]["building"]["height_raw"] == "26.3;17.2"
    queue = load(ROOT / "data/manual/review_queue.json")
    checks["manual_review_not_overwritten_or_implicitly_approved"] = all(f["override_ref"] is None for f in features) and all(
        item["approved_geometry_or_value"] is None for item in queue["items"])
    checks["reported_kind_and_role_counts_match_records"] = document["kind_counts"] == dict(Counter(f["source_kind"] for f in features)) and document["generation_role_counts"] == dict(Counter(f["generation"]["role"] for f in features))
    checks = {name: bool(value) for name, value in checks.items()}
    report = {"task_id": "G02", "scope": "Horizontal source-preserving geometry and conservative generation roles; no game assets",
        "input_file": args.input, "input_sha256": sha(ROOT / args.input), "input_bytes": (ROOT / args.input).stat().st_size,
        "provenance": p, "checker_sha256": sha(Path(__file__)), "environment": {"python": platform.python_version(),
            "shapely": shapely.__version__, "geos": shapely.geos_version_string, "machine": platform.machine()},
        "checks": checks, "passed": all(checks.values()), "feature_count": len(features), "kind_counts": document["kind_counts"],
        "generation_role_counts": document["generation_role_counts"], "original_holes": original_holes, "result_holes": result_holes,
        "max_roundtrip_error_degrees": max_inverse_error, "max_shape_hausdorff_error_m": max_shape_error,
        "geometry_failures": geometry_failures, "source_failures": source_failures, "group_failures": group_failures,
        "attribute_failures": attribute_failures, "role_failures": role_failures,
        "active_coarse_body_overlap_pairs": active_overlap, "relation_outer_emission_violations": outer_violations,
        "diagnostics": document["diagnostics"],
        "not_run": ["Independent surveyed accuracy or current physical completeness", "Authoritative domestic building original comparison",
            "G03 height/ground and detailed part vertical composition", "G04 widths/playable boundary/routes",
            "Godot meshes, normals, collision or walking", "M4 Pro execution"],
        "official_implementation_references": ["https://shapely.readthedocs.io/en/stable/reference/shapely.orient_polygons.html",
            "https://shapely.readthedocs.io/en/stable/strtree.html"]}
    save(ROOT / args.report, report)
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "features": len(features),
        "holes": result_holes, "active_coarse_bodies": len(primary), "max_inverse_error_degrees": max_inverse_error}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

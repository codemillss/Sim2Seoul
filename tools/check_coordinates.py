#!/usr/bin/env python3
"""Reproduce G01 from the small OSM snapshot; no network or game generation."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform

import osmium
import pyproj
from pyproj import Geod, Proj

from coordinate_system import CoordinateSystem, ROOT

TARGETS = {
    "w/377289797": "대한문", "w/181574577": "중화전", "r/19357693": "석조전",
    "w/517072312": "돈덕전", "w/198561926": "서울시청", "r/10757525": "서울도서관",
    "w/370019676": "서울광장",
}
PAIRS = [
    ("w/377289797", "w/181574577"), ("r/19357693", "w/517072312"),
    ("w/370019676", "w/198561926"), ("w/181574577", "w/198561926"),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def selected_vertex(geometry):
    # Only exterior rings. Stable lexicographic selection, never a claimed doorway.
    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    if geometry["type"] not in ("Polygon", "MultiPolygon"):
        raise ValueError("Expected landmark polygon")
    candidates = [(tuple(point), [polygon_index, 0, vertex_index])
                  for polygon_index, polygon in enumerate(polygons)
                  for vertex_index, point in enumerate(polygon[0][:-1])]
    if not candidates:
        raise ValueError("Empty landmark outer ring")
    return min(candidates)


class MatchingNodes(osmium.SimpleHandler):
    def __init__(self, coordinates):
        super().__init__()
        self.matches = {tuple(round(v, 7) for v in coordinate): [] for coordinate in coordinates}

    def node(self, node):
        if node.location.valid():
            key = (round(node.lon, 7), round(node.lat, 7))
            if key in self.matches:
                self.matches[key].append({"osm_node_id": node.id, "lon_lat": [node.lon, node.lat]})


def angle_difference(a, b):
    return (a - b + 180) % 360 - 180


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="data/reports/coordinate_check.json")
    parser.add_argument("--reference", default="data/processed/coordinate_reference.json")
    args = parser.parse_args()
    system = CoordinateSystem()
    c = system.config
    manifest = load(ROOT / "data/reports/extract_manifest.json")
    audit = load(ROOT / "data/reports/osm_audit.json")
    preview_record = audit["preview_artifact"]
    preview_path = ROOT / preview_record["file"]
    source = ROOT / manifest["extract_file"]
    checks = {
        "source_hash_and_size": sha(source) == manifest["extract_sha256"] and source.stat().st_size == manifest["extract_bytes"],
        "preview_source_hash": audit["extract_sha256"] == manifest["extract_sha256"],
        "preview_hash_and_size": sha(preview_path) == preview_record["sha256"] and preview_path.stat().st_size == preview_record["bytes"],
        "preview_config_binding": sha(system.config_path) == preview_record["config_sha256"],
    }
    if not all(checks.values()):
        raise SystemExit("Source/preview/config mismatch: run the current OSM audit before G01")
    features = load(preview_path)["features"]
    selected = {}
    for identity, name in TARGETS.items():
        candidates = [f for f in features if f["properties"]["osm_id"] == identity]
        if len(candidates) != 1:
            raise SystemExit(f"Expected one source landmark geometry: {identity}")
        point, path = selected_vertex(candidates[0]["geometry"])
        selected[identity] = {"name": name, "source_feature_id": identity,
            "source_point_kind": "lexicographically_first_outer_ring_vertex_not_entrance_centroid_or_spawn",
            "geometry_polygon_ring_vertex_indices": path, "lon_lat": list(point)}
    nodes = MatchingNodes([p["lon_lat"] for p in selected.values()])
    nodes.apply_file(source)
    for point in selected.values():
        key = tuple(round(v, 7) for v in point["lon_lat"])
        point["coincident_raw_nodes"] = sorted(nodes.matches[key], key=lambda n: n["osm_node_id"])
        point["projected_east_north_m"] = list(system.project(*point["lon_lat"]))
        point["world_xyz_m"] = list(system.to_world(*point["lon_lat"]))
        point["y_status"] = "synthetic_0_for_horizontal_check_not_observed_ground"
    checks["seven_landmarks_and_raw_node_coordinates"] = len(selected) == 7 and all(
        p["coincident_raw_nodes"] and any(n["lon_lat"] == p["lon_lat"] for n in p["coincident_raw_nodes"])
        for p in selected.values())
    west, south, east, north = c["bbox_west_south_east_north"]
    bbox_points = [(west, south), (east, south), (east, north), (west, north)]
    area = system.metric_crs.area_of_use
    checks["investigation_bbox_within_projection_area"] = all(
        area.west <= lon <= area.east and area.south <= lat <= area.north for lon, lat in bbox_points)
    roundtrips = []
    test_points = [("origin", system.origin_lon_lat)] + [(f"bbox_corner_{i}", p) for i, p in enumerate(bbox_points)]
    test_points += [(identity, p["lon_lat"]) for identity, p in selected.items()]
    for identity, lon_lat in test_points:
        world = system.to_world(*lon_lat)
        reverse = system.to_lon_lat(*world)
        errors = [abs(a - b) for a, b in zip(lon_lat, reverse)]
        roundtrips.append({"point_id": identity, "lon_lat": list(lon_lat), "world_xyz_m": list(world),
            "inverse_lon_lat": list(reverse), "absolute_errors_degrees": errors})
    checks["roundtrip_within_1e_minus_8_degrees"] = all(
        max(p["absolute_errors_degrees"]) <= c["coordinate_validation"]["roundtrip_max_error_degrees"] for p in roundtrips)
    checks["fixed_origin_is_zero"] = system.to_world(*system.origin_lon_lat) == (0.0, 0.0, 0.0)
    geod = Geod(ellps="WGS84")
    projection = Proj(system.metric_crs)
    distances = []
    for start, end in PAIRS:
        a, b = selected[start], selected[end]
        azimuth, _, geodesic = geod.inv(*a["lon_lat"], *b["lon_lat"])
        ae, an = a["projected_east_north_m"]
        be, bn = b["projected_east_north_m"]
        projected = math.hypot(be - ae, bn - an)
        aw, bw = a["world_xyz_m"], b["world_xyz_m"]
        local = math.hypot(bw[0] - aw[0], bw[2] - aw[2])
        grid_bearing = math.degrees(math.atan2(be - ae, bn - an)) % 360
        local_bearing = math.degrees(math.atan2(bw[0] - aw[0], -(bw[2] - aw[2]))) % 360
        distances.append({"from": start, "to": end, "names": [a["name"], b["name"]],
            "projected_distance_m": projected, "local_distance_m": local, "geodesic_distance_m": geodesic,
            "absolute_distance_difference_m": abs(projected - geodesic),
            "relative_distance_difference": abs(projected - geodesic) / geodesic,
            "grid_bearing_degrees": grid_bearing, "local_bearing_degrees": local_bearing,
            "geodesic_initial_bearing_degrees": azimuth % 360,
            "grid_minus_geodesic_bearing_degrees_informational": angle_difference(grid_bearing, azimuth),
            "start_meridian_convergence_degrees": projection.get_factors(*a["lon_lat"]).meridian_convergence})
    checks["four_nonzero_pairs_distance_within_0_2_percent"] = len(distances) >= 3 and all(
        p["geodesic_distance_m"] > 0 and p["relative_distance_difference"] <=
        c["coordinate_validation"]["projected_geodesic_max_relative_difference"] for p in distances)
    checks["local_distances_and_bearings_preserve_projected_plane"] = all(
        abs(p["local_distance_m"] - p["projected_distance_m"]) <= 1e-9 and
        abs(angle_difference(p["local_bearing_degrees"], p["grid_bearing_degrees"])) <= 1e-9 for p in distances)
    controls = []
    oe, on = system.origin_east_north
    for label, de, dn, y, expected in [
        ("grid_east_10m", 10, 0, 0, [10, 0, 0]), ("grid_west_10m", -10, 0, 0, [-10, 0, 0]),
        ("grid_north_10m", 0, 10, 0, [0, 0, -10]), ("grid_south_10m", 0, -10, 0, [0, 0, 10]),
        ("local_up_10m", 0, 0, 10, [0, 10, 0]),
    ]:
        lon_lat = system.inverse.transform(oe + de, on + dn, errcheck=True)
        actual = system.to_world(*lon_lat, y)
        controls.append({"id": label, "kind": "synthetic_projected_or_local_control",
            "lon_lat": list(lon_lat), "expected_world_xyz_m": expected, "actual_world_xyz_m": list(actual),
            "max_error_m": max(abs(a - b) for a, b in zip(actual, expected))})
    checks["five_10m_axis_controls"] = all(p["max_error_m"] <=
        c["coordinate_validation"]["synthetic_axis_max_error_m"] for p in controls)
    cardinal = []
    for label, az, coordinate_index, sign in [("geodetic_east", 90, 0, 1), ("geodetic_north", 0, 2, -1)]:
        lon, lat, _ = geod.fwd(*system.origin_lon_lat, az, 10)
        world = system.to_world(lon, lat)
        cardinal.append({"id": label, "world_xyz_m": list(world),
            "primary_axis_sign_passed": world[coordinate_index] * sign > 0,
            "cross_axis_note": "Grid and geodetic north differ; cross component need not be zero"})
    checks["true_east_north_primary_axis_signs"] = all(p["primary_axis_sign_passed"] for p in cardinal)
    rejected = []
    for label, action in [("nonfinite_lon", lambda: system.to_world(float("nan"), 37)),
                          ("swapped_lon_lat", lambda: system.to_world(37, 126)),
                          ("nonfinite_height", lambda: system.to_world(*system.origin_lon_lat, float("inf"))),
                          ("nonfinite_world", lambda: system.to_lon_lat(0, 0, float("nan")))]:
        try:
            action()
            rejected.append({"case": label, "rejected": False})
        except ValueError:
            rejected.append({"case": label, "rejected": True})
    checks["invalid_inputs_rejected"] = all(p["rejected"] for p in rejected)
    provenance = {"source_file": manifest["extract_file"], "source_sha256": manifest["extract_sha256"],
        "preview_artifact": preview_record, "config_file": "config/region.json", "config_sha256": sha(system.config_path),
        "generators": {f"tools/{name}": sha(ROOT / "tools" / name) for name in ["coordinate_system.py", "check_coordinates.py"]}}
    reference = {"task_id": "G01", "coordinate_contract_version": c["coordinate_contract_version"],
        "provenance": provenance, "horizontal_source_crs": c["source_crs"], "metric_crs": c["metric_crs"],
        "origin_lon_lat": list(system.origin_lon_lat), "origin_projected_east_north_m": list(system.origin_east_north),
        "world_axes": c["world_axes"], "meters_per_world_unit": c["meters_per_world_unit"],
        "vertical_datum": c["vertical_datum"], "vertical_coordinate_rule": c["vertical_coordinate_rule"],
        "landmark_points": selected, "synthetic_10m_controls": controls,
        "usage": "Horizontal reference only. Source vertices are not entrances, spawn points or walking route endpoints."}
    report = {"task_id": "G01", "scope": "Fixed horizontal transform and local units; not engine or field validation",
        "provenance": provenance, "environment": {"python": platform.python_version(), "pyproj": pyproj.__version__,
            "proj": pyproj.proj_version_str, "platform": platform.system(), "machine": platform.machine(),
            "proj_network_enabled": system.forward.is_network_enabled},
        "checks": checks, "passed": all(checks.values()), "tolerances": c["coordinate_validation"],
        "coordinate_reference": reference, "roundtrips": roundtrips, "distance_pairs": distances,
        "true_cardinal_controls": cardinal, "invalid_input_checks": rejected,
        "direction_interpretation": "Grid/local bearings must agree. Geodesic initial bearings differ due to meridian convergence and projection; difference is informational, not an equal-bearing test.",
        "not_run": {"independent_position_accuracy": "no independent surveyed coordinates",
            "godot_transfer_distance_and_axis_check": "E04; engine not installed or started",
            "observed_vertical_datum_or_ground": "G03; synthetic y=0 only, no DSM elevation conversion",
            "walking_route_length_or_gate_access": "G04/W; source-vertex straight lines only",
            "M4_Pro_execution": "this run used the current M1 environment"},
        "official_implementation_references": ["https://pyproj4.github.io/pyproj/stable/api/transformer.html",
            "https://pyproj4.github.io/pyproj/stable/api/proj.html",
            "https://proj.org/en/stable/operations/projections/utm.html"]}
    save(ROOT / args.reference, reference)
    save(ROOT / args.report, report)
    print(json.dumps({"passed": report["passed"], "checks": len(checks),
        "max_roundtrip_error_degrees": max(max(p["absolute_errors_degrees"]) for p in roundtrips),
        "max_distance_difference_percent": 100 * max(p["relative_distance_difference"] for p in distances)}, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

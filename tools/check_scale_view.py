#!/usr/bin/env python3
"""E04: independently score actual Godot global measurements against G01.

No screenshot inference, geographic survey, terrain or walking validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from pyproj import Geod, Transformer

ROOT = Path(__file__).resolve().parents[1]
ABS_M = 0.05
SNAPSHOT_M = 1e-6
IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
PAIRS = [("w/377289797", "w/181574577"), ("r/19357693", "w/517072312"),
         ("w/370019676", "w/198561926"), ("w/181574577", "w/198561926")]
CONTROL = {"grid_east_10m": [10, 0, 0], "grid_west_10m": [-10, 0, 0],
           "grid_north_10m": [0, 0, -10], "grid_south_10m": [0, 0, 10],
           "local_up_10m": [0, 10, 0]}


def vector(value, n=3):
    if not isinstance(value, list) or len(value) != n:
        raise ValueError(f"Expected finite {n}-component vector")
    if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in value):
        raise ValueError("Nonfinite or nonnumeric vector")
    return value


def distance(a, b, axes=(0, 1, 2)):
    vector(a); vector(b)
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in axes))


def audit(measurements, root=ROOT):
    root = Path(root)
    checks, pair_results, max_errors = [], [], {}

    def check(name, passed, **detail):
        checks.append({"name": name, "passed": bool(passed), **detail})

    def error(name, value, tolerance, group):
        max_errors[group] = max(max_errors.get(group, 0.0), value)
        check(name, value <= tolerance, error=value, tolerance=tolerance)

    def position(name, actual, expected, axes=(0, 1, 2), tolerance=ABS_M, group="absolute_position_m"):
        error(name, distance(actual, expected, axes), tolerance, group)

    def transform(name, actual, origin=(0, 0, 0), basis=IDENTITY):
        position(name + ".origin", actual["origin"], list(origin), tolerance=1e-5, group="transform_origin_m")
        rows = actual["basis"]
        if not isinstance(rows, list) or len(rows) != 3:
            raise ValueError("Invalid transform basis")
        for i in range(3):
            position(f"{name}.basis.{i}", rows[i], basis[i], tolerance=1e-6, group="transform_basis")

    def indexed(entries, key, expected, name):
        ids = [entry[key] for entry in entries]
        check(name, len(ids) == len(set(ids)) and set(ids) == set(expected), actual=ids)
        return {entry[key]: entry for entry in entries}

    try:
        ref = json.loads((root / "data/processed/coordinate_reference.json").read_text())
        prior = json.loads((root / "data/reports/coordinate_check.json").read_text())
        check("snapshot.reference_copy", ref == prior["coordinate_reference"])
        check("snapshot.landmark_ids", set(ref["landmark_points"]) == {
            "w/377289797", "w/181574577", "r/19357693", "w/517072312",
            "w/198561926", "r/10757525", "w/370019676"})
        project = Transformer.from_crs(4326, 32652, always_xy=True)
        geod = Geod(ellps="WGS84")
        oe, on = project.transform(*ref["origin_lon_lat"], errcheck=True)
        position("snapshot.origin_projected", [oe, 0, on], [ref["origin_projected_east_north_m"][0], 0,
                 ref["origin_projected_east_north_m"][1]], tolerance=SNAPSHOT_M, group="snapshot_m")
        check("snapshot.contract", ref["horizontal_source_crs"] == "EPSG:4326" and
              ref["metric_crs"] == "EPSG:32652" and ref["meters_per_world_unit"] == 1 and
              ref["world_axes"] == {"x": "east", "y": "up", "z": "south"})
        expected = {}
        for fid, point in ref["landmark_points"].items():
            e, n = project.transform(*point["lon_lat"], errcheck=True)
            xyz = [e - oe, 0, -(n - on)]
            expected[fid] = xyz
            check(f"snapshot.{fid}.definition", point["source_feature_id"] == fid and
                  point["source_point_kind"] == "lexicographically_first_outer_ring_vertex_not_entrance_centroid_or_spawn" and
                  point["geometry_polygon_ring_vertex_indices"] == [0, 0, 0] and
                  point["y_status"] == "synthetic_0_for_horizontal_check_not_observed_ground")
            position(f"snapshot.{fid}.world", point["world_xyz_m"], xyz, tolerance=SNAPSHOT_M, group="snapshot_m")
            position(f"snapshot.{fid}.projected", [e, 0, n], [point["projected_east_north_m"][0], 0,
                     point["projected_east_north_m"][1]], tolerance=SNAPSHOT_M, group="snapshot_m")
        controls_ref = indexed(ref["synthetic_10m_controls"], "id", CONTROL, "snapshot.controls.ids")
        for cid, xyz in CONTROL.items():
            e, n = project.transform(*controls_ref[cid]["lon_lat"], errcheck=True)
            position(f"snapshot.{cid}.reprojected", [e - oe, xyz[1], -(n - on)], xyz,
                     tolerance=SNAPSHOT_M, group="snapshot_m")
            position(f"snapshot.{cid}.expected", controls_ref[cid]["expected_world_xyz_m"], xyz,
                     tolerance=SNAPSHOT_M, group="snapshot_m")
            position(f"snapshot.{cid}.actual", controls_ref[cid]["actual_world_xyz_m"], xyz,
                     tolerance=SNAPSHOT_M, group="snapshot_m")

        world_path = root / "game/resources/world_geometry/world.json"
        world = json.loads(world_path.read_text())
        anchors = indexed(measurements["anchors"], "id", expected, "engine.anchors.ids")
        check("engine.anchors.marker_ids_unique", len({a["id"] for a in measurements["anchors"]}) == len(expected))
        for fid, xyz in expected.items():
            a = anchors[fid]
            source_meshes = [mesh["id"] for mesh in world["meshes"] if any(
                source.get("object_id") == fid for source in mesh["metadata"]["source_refs"])]
            check(f"anchor.{fid}.source_mesh", len(source_meshes) == 1 and a["feature_id"] == source_meshes[0],
                  actual=a["feature_id"], expected=source_meshes)
            check(f"anchor.{fid}.name", a["name"] == ref["landmark_points"][fid]["name"])
            position(f"anchor.{fid}.xz", a["anchor_global_xyz"], xyz, (0, 2))
            position(f"anchor.{fid}.synthetic_y", a["anchor_global_xyz"], xyz, (1,))
            position(f"mesh.{fid}.xz", a["mesh_global_xyz"], xyz, (0, 2), group="mesh_absolute_xz_m")
            check(f"mesh.{fid}.vertices", isinstance(a["mesh_vertex_count"], int) and a["mesh_vertex_count"] > 0)
            transform(f"mesh.{fid}.transform", a["mesh_transform"])

        prior_pairs = {(p["from"], p["to"]): p for p in prior["distance_pairs"]}
        check("snapshot.pairs.ids", len(prior["distance_pairs"]) == 4 and set(prior_pairs) == set(PAIRS))
        runtime_pairs = {(p["from"], p["to"]): p for p in measurements["pairs"]}
        check("engine.pairs.ids", len(measurements["pairs"]) == 4 and set(runtime_pairs) == set(PAIRS))
        for start, end in PAIRS:
            d = distance(expected[start], expected[end], (0, 2))
            _, _, gd = geod.inv(*ref["landmark_points"][start]["lon_lat"], *ref["landmark_points"][end]["lon_lat"])
            p = prior_pairs[start, end]
            for field, value in [("projected_distance_m", d), ("local_distance_m", d), ("geodesic_distance_m", gd)]:
                error(f"snapshot.pair.{start}.{end}.{field}", abs(p[field] - value), SNAPSHOT_M, "snapshot_m")
            check(f"snapshot.pair.{start}.{end}.projection_geodesic", abs(d - gd) / gd <= 0.002)
            tolerance = max(ABS_M, d * 0.001)
            line = runtime_pairs[start, end]["line_global_xyz"]
            if len(line) != 2:
                raise ValueError("Pair line requires two actual endpoints")
            position(f"line.{start}.{end}.start", line[0], expected[start])
            position(f"line.{start}.{end}.end", line[1], expected[end])
            actuals = {"anchor_xz_m": distance(anchors[start]["anchor_global_xyz"], anchors[end]["anchor_global_xyz"], (0, 2)),
                       "mesh_xz_m": distance(anchors[start]["mesh_global_xyz"], anchors[end]["mesh_global_xyz"], (0, 2)),
                       "line_xz_m": distance(line[0], line[1], (0, 2)), "line_3d_m": distance(line[0], line[1])}
            for kind, actual in actuals.items():
                error(f"pair.{start}.{end}.{kind}", abs(actual - d), tolerance, "pair_distance_m")
            pair_results.append({"from": start, "to": end, "expected_xz_m": d, "geodesic_m": gd,
                                 "tolerance_m": tolerance, **actuals,
                                 "mesh_3d_m_informational": distance(anchors[start]["mesh_global_xyz"], anchors[end]["mesh_global_xyz"])})
        position("engine.origin", measurements["origin_global_xyz"], [0, 0, 0])
        controls = indexed(measurements["controls"], "id", CONTROL, "engine.controls.ids")
        for cid, xyz in CONTROL.items():
            c = controls[cid]
            position(f"control.{cid}.marker", c["marker_global_xyz"], xyz)
            line = c["line_global_xyz"]
            if len(line) != 2:
                raise ValueError("Control line requires two actual endpoints")
            position(f"control.{cid}.line_start", line[0], [0, 0, 0])
            position(f"control.{cid}.line_end", line[1], xyz)
            position(f"control.{cid}.direction", [line[1][i] - line[0][i] for i in range(3)], xyz)
            error(f"control.{cid}.length_3d", abs(distance(*line) - 10), ABS_M, "control_length_m")
        cube = measurements["cube_global_vertices"]
        for v in cube:
            vector(v)
        check("cube.vertices", len(cube) >= 8)
        bounds = [(min(v[i] for v in cube), max(v[i] for v in cube)) for i in range(3)]
        for i, (lo, hi) in enumerate(bounds):
            error(f"cube.edge_axis_{i}", abs(hi - lo - 10), ABS_M, "cube_edge_m")
        corners = {tuple(0 if abs(v[i] - bounds[i][0]) <= ABS_M else 1 if abs(v[i] - bounds[i][1]) <= ABS_M else 2
                         for i in range(3)) for v in cube}
        check("cube.actual_eight_corners", corners == {(x, y, z) for x in (0, 1) for y in (0, 1) for z in (0, 1)})
        for key in ("world_transform", "anchor_parent_transform", "control_parent_transform"):
            transform(key, measurements[key])
        check("engine.world_sha256", measurements["world_sha256"] == hashlib.sha256(world_path.read_bytes()).hexdigest())
        # Scene has one actual MeshInstance3D for each generated geometry entry.
        geometry = world.get("meshes")
        if geometry is not None:
            check("engine.loaded_geometry_count", measurements["loaded_geometry_count"] == len(geometry))
        else:
            raise ValueError("Unknown world geometry schema; cannot check engine count")
        cam = measurements["camera"]
        check("camera.map_config", cam["view"] == "map" and cam["projection"] == 1 and cam["keep_aspect"] == 1
              and cam["viewport"] == [1152, 720] and abs(cam["size_m"] - 650) <= 1e-6)
        transform("camera.transform", cam["global_transform"], (-25, 900, -100), [[1, 0, 0], [0, 0, -1], [0, 1, 0]])
        origin, east, north = [vector(cam[k], 2) for k in ("origin_pixel", "east_pixel", "north_pixel")]
        expected_px = 10 * 720 / 650
        for name, endpoint, delta in [("east", east, [expected_px, 0]), ("north", north, [0, -expected_px])]:
            actual_delta = [endpoint[i] - origin[i] for i in range(2)]
            error(f"camera.{name}.pixel_delta", math.dist(actual_delta, delta), 0.05, "camera_pixel_error")
        expected_origin = [1152 / 2 + 25 * 720 / 650, 720 / 2 + 100 * 720 / 650]
        error("camera.origin_pixel", math.dist(origin, expected_origin), 0.05, "camera_pixel_error")
    except (KeyError, ValueError, TypeError, IndexError, OSError, ZeroDivisionError) as exc:
        check("schema_or_input_error", False, error=str(exc))
    return {"checks": checks, "passed": bool(checks) and all(c["passed"] for c in checks),
            "pair_results": pair_results, "max_errors": max_errors,
            "scope": "G01 source vertices versus actual Godot global ArrayMesh/markers/lines; horizontal straight-line distances",
            "unverified": ["external geographic accuracy", "physical survey", "terrain", "walk routes", "human visual/keyboard validation"],
            "gpu_evidence": "Recorded separately by the engine driver; this checker does not infer GPU rendering from measurements."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        wrapper = json.loads(args.input.read_text())
        report = audit(wrapper["measurements"])
        report["case"] = wrapper.get("case")
        report["engine_display_server"] = wrapper.get("display_server", wrapper.get("engine_display_server"))
    except (OSError, ValueError, KeyError, TypeError) as exc:
        report = {"passed": False, "checks": [{"name": "input_error", "passed": False, "error": str(exc)}]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

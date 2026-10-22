"""Independent source geometry audit; never imports a game authoring mutator.

Run from the repository root with .venv-data/bin/python <this file> <new.json>.
This certifies current authored geometry, not official Seoul stop surveying.
"""
import hashlib
import json
import math
from pathlib import Path
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "tools"))
from city_bus_stop_placement import source_context, certify_stop, frame, rectangle


def read(path):
    return json.loads((ROOT / path).read_text())


def main():
    destination = Path(sys.argv[1]).resolve()
    if destination.exists():
        raise SystemExit("Refusing to overwrite retained placement evidence")
    paths = ["game/resources/world_geometry/world.json", "data/processed/features.json",
             "game/assets/authored/road_furniture.json", "game/assets/authored/bus_service.json",
             "game/data/generated/traffic.json", "game/assets/authored/neighborhood_population.json",
             "game/assets/authored/street_curbs.json", "game/scripts/city_bus_service.gd",
             "tools/city_bus_stop_placement.py", str(Path(__file__).relative_to(ROOT))]
    inputs = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}
    features = {r["feature_id"]: r for r in read("data/processed/features.json")["features"]}
    world = read(paths[0]); roads = read(paths[2]); bus = read(paths[3])
    context = source_context(features, world, roads)
    route = LineString(bus["route"]["xz"])
    whites = unary_union([Polygon(p["xz"]) for p in roads["paint"] if p["kind"] in ["lane", "edge"]])
    stops = []
    for stop in bus["stops"]:
        p, d = frame(route, stop["station_m"]); right = (-d[1], d[0])
        approaches = []
        for door_index, z in enumerate([-2.95, .55]):
            door = (p[0] + right[0] * 1.58 - d[0] * z, p[1] + right[1] * 1.58 - d[1] * z)
            marker = (p[0] + right[0] * 2.65 - d[0] * z, p[1] + right[1] * 2.65 - d[1] * z)
            direct = LineString([stop["wait_xz"], door])
            path = LineString([stop["wait_xz"], marker]); corridor = path.buffer(.42)
            paint_ids = [r["id"] for r in roads["paint"] if r["kind"] in ["lane", "edge", "centre", "paired_centre"] and path.intersects(Polygon(r["xz"]))]
            road_area = corridor.intersection(context["drive"]).area
            private_area = corridor.intersection(context["private"]).area
            solid_area = corridor.intersection(context["solid"]).area
            crossing_clearance = corridor.distance(context["crossings"])
            approaches.append({"door_index": door_index, "door_local_z_m": z,
                               "door_xz": door, "boarding_xz": marker,
                               "original_wait_to_actual_door_m": direct.length,
                               "original_wait_to_actual_door_drive_length_m": direct.intersection(context["drive"]).length,
                               "boarding_connector_length_m": path.length,
                               "whole_0_42m_radius_corridor_drive_overlap_m2": road_area,
                               "whole_corridor_private_overlap_m2": private_area,
                               "whole_corridor_solid_overlap_m2": solid_area,
                               "whole_corridor_crossing_clearance_m": crossing_clearance,
                               "vehicle_paint_crossings": paint_ids,
                               "accepted": road_area < 1e-7 and private_area < 1e-7 and solid_area < 1e-7 and crossing_clearance >= 3 and not paint_ids})
        chosen = next((a for a in approaches if a["accepted"]), None)
        stops.append({"id": stop["id"], "name": stop["name"], "bus_centre_xz": p,
                      "retained_source_wait_xz": stop["wait_xz"], "retained_shelter_xz": stop["shelter_xz"],
                      "source_walk_feature_id": stop["source_walk_feature_id"],
                      "original_stop_certificate": certify_stop(stop, route, context),
                      "door_approaches": approaches, "chosen_pedestrian_connector": chosen})
    cars = read(paths[4])["routes"] + read(paths[5])["vehicle_routes"]
    car_rows = []
    for car in cars:
        line = LineString(car["xz"]); outside = 0; maximum = 0.; samples = 0; directions = []
        source = features[car["source_binding"]["feature_id"]]
        source_line = LineString(source["geometry"]["coordinates"])
        for n in range(math.ceil(line.length / .5) + 1):
            station = min(line.length - .001, n * .5); p, d = frame(line, station)
            body = rectangle(p, d, (-.95, .95, -2.15, 2.15))
            area = body.difference(context["drive"]).area
            maximum = max(maximum, area); outside += area > 1e-7; samples += 1
            s = source_line.project(Point(p)); a = source_line.interpolate(max(0, s - .03)); b = source_line.interpolate(min(source_line.length, s + .03))
            norm = math.hypot(b.x - a.x, b.y - a.y)
            if norm: directions.append((d[0] * (b.x - a.x) + d[1] * (b.y - a.y)) / norm)
        car_rows.append({"route_id": car["id"], "source_feature_id": car["source_binding"]["feature_id"],
                         "sample_count": samples, "whole_sedan_box_outside_source_drive_samples": outside,
                         "maximum_box_outside_source_drive_m2": maximum,
                         "minimum_source_forward_dot": min(directions),
                         "white_paint_over_car_corridor_m2": whites.intersection(line.buffer(.91, cap_style=2)).area,
                         "scope": "Route geometry only. Physical movement/yield/recycle behavior requires a fresh engine journey."})
    checks = [{"name": "all_four_retained_shelter_source_and_crossing_certificates", "passed": all(s["original_stop_certificate"]["accepted"] for s in stops)},
              {"name": "all_four_selected_full_pedestrian_connectors_clear_every_drive_private_solid_crossing_and_lane", "passed": all(s["chosen_pedestrian_connector"] is not None for s in stops)},
              {"name": "stop4_front_door_detected_unsafe_middle_door_selected", "passed": not stops[3]["door_approaches"][0]["accepted"] and stops[3]["chosen_pedestrian_connector"]["door_index"] == 1},
              {"name": "all_six_original_14car_route_classes_inside_source_drive_and_source_forward", "passed": len(car_rows) == 6 and all(r["whole_sedan_box_outside_source_drive_samples"] == 0 and r["minimum_source_forward_dot"] > .99 for r in car_rows)},
              {"name": "all_original_car_route_corridors_clear_white_lane_boundaries", "passed": all(r["white_paint_over_car_corridor_m2"] < .001 for r in car_rows)}]
    curbs = read(paths[6])
    report = {"task": "EXP27_ROAD_BUS_STOP_PLACEMENT_REVIEW", "result": "PASS" if all(c["passed"] for c in checks) else "FAIL",
              "checks": checks, "source_sha256": inputs, "stops": stops, "normal_car_routes": car_rows,
              "road_counts": roads["counts"], "curbs": {"segments": len(curbs["segments"]), "scope": curbs["scope"]},
              "limitations": ["All four T01 stops are authored on the eastern side of one closed southern loop, not a complete Seoul bus network or official stop locations.",
                              "The rejected multi-lane hypothesis is retained: original direct wait-to-front-door drive travel is 0 to 0.70m, with no painted lane crossings; setback across the verge, not crossing multiple lanes, caused the long approach.",
                              "Current lane width is a 3.2m authored cadence fitted to source-display road widths; actual markings, curb surveys and present-day signal schedules are not established.",
                              "Original normal cars follow finite source-forward corridors with guarded off-camera endpoint recycling, rather than routing through an entire street graph.",
                              "Existing raised kerbs cover bounded central stretches; source sidewalk heights across the whole city have not been surveyed or rebuilt.",
                              "This independent planar audit cannot prove native support, live crowd traffic, FPS, visual quality or physical-key/OS acceptance."]}
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"result": report["result"], "checks": len(checks), "failed": [c["name"] for c in checks if not c["passed"]], "stop_distances_m": [round(s["chosen_pedestrian_connector"]["boarding_connector_length_m"], 2) if s["chosen_pedestrian_connector"] else None for s in stops]}, ensure_ascii=False))
    raise SystemExit(0 if report["result"] == "PASS" else 1)


if __name__ == "__main__":
    main()

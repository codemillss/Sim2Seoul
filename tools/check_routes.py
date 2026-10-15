#!/usr/bin/env python3
"""Independently audit N01 route snapshots against retained source geometry.

This checker does not import the route generator, run Godot, fetch data, or
rebuild prior stages.  Passing concerns this local planning snapshot only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from shapely import union_all
from shapely.errors import GEOSException
from shapely.geometry import LineString, Point, Polygon, box, shape

ROOT = Path(__file__).resolve().parents[1]
EPS = 1e-7
INPUTS = (
    "data/manual/urban_routes.json",
    "config/region.json",
    "config/movement_rules.json",
    "config/data_usage.json",
    "data/processed/features.json",
    "data/processed/walkable_areas.json",
    "data/processed/driveable_areas.json",
    "data/processed/boundary_candidate.json",
    "game/data/generated/public_walk.json",
    "game/resources/world_geometry/world.json",
    "game/data/generated/daehanmun.json",
    "game/resources/collision/rules.json",
    "data/raw/deoksugung_cityhall-v2.osm.pbf",
    "tools/prepare_routes.py",
)


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def finite_tree(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite_tree(v) for v in value.values())
    if isinstance(value, (list, tuple)):
        return all(finite_tree(v) for v in value)
    return True


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def points(value):
    return (isinstance(value, list) and len(value) >= 2
            and all(isinstance(p, list) and len(p) == 2 and all(number(v) for v in p) for p in value))


def length(xz):
    return sum(math.dist(a, b) for a, b in zip(xz, xz[1:]))


def slice_source(xz, start, end):
    """Cut a source line by cumulative metre stations, retaining inner vertices."""
    total = length(xz)
    if not number(start) or not number(end) or not 0 <= start < end <= total + EPS:
        raise ValueError("invalid source stations")
    stations = [0.0]
    for a, b in zip(xz, xz[1:]):
        stations.append(stations[-1] + math.dist(a, b))

    def at(s):
        for i, (low, high) in enumerate(zip(stations, stations[1:])):
            if s <= high + EPS and high > low:
                t = max(0.0, min(1.0, (s - low) / (high - low)))
                return [xz[i][k] + t * (xz[i + 1][k] - xz[i][k]) for k in (0, 1)]
        return list(xz[-1])

    return [at(start), *[list(p) for p, s in zip(xz, stations) if start + EPS < s < end - EPS], at(end)]


def right_offset(xz, distance):
    """Intersect adjacent offset segments: X east / Z south, right=(-dz,dx)."""
    directions = []
    for a, b in zip(xz, xz[1:]):
        size = math.dist(a, b)
        if size <= EPS:
            raise ValueError("zero source segment")
        directions.append(((b[0] - a[0]) / size, (b[1] - a[1]) / size))

    def shifted(p, d):
        return [p[0] - distance * d[1], p[1] + distance * d[0]]

    result = [shifted(xz[0], directions[0])]
    for i in range(1, len(xz) - 1):
        a, b = directions[i - 1], directions[i]
        p, q = shifted(xz[i], a), shifted(xz[i], b)
        cross = a[0] * b[1] - a[1] * b[0]
        if abs(cross) < 1e-12:
            result.append([(p[k] + q[k]) / 2 for k in (0, 1)])
        else:
            delta = [q[k] - p[k] for k in (0, 1)]
            t = (delta[0] * b[1] - delta[1] * b[0]) / cross
            result.append([p[k] + t * a[k] for k in (0, 1)])
    result.append(shifted(xz[-1], directions[-1]))
    return result


def rings_geometry(rings):
    return union_all([Polygon(p[0], p[1:]) for p in rings])


def same_points(a, b, tolerance=EPS):
    return points(a) and len(a) == len(b) and all(math.dist(p, q) <= tolerance for p, q in zip(a, b))


def same_directed_line(a, b):
    if not points(a) or math.dist(a[0], b[0]) > EPS or math.dist(a[-1], b[-1]) > EPS:
        return False
    actual, expected = LineString(a), LineString(b)
    # GEOS suppresses tiny almost-collinear mitre segments.  Compare their
    # continuous directed traces rather than requiring identical join vertices.
    return (actual.is_simple and actual.hausdorff_distance(expected) <= EPS
            and abs(actual.length - expected.length) <= EPS
            and all(actual.interpolate(i / 64, normalized=True).distance(
                    expected.interpolate(i / 64, normalized=True)) <= EPS for i in range(65)))


def same_geometry(actual, expected, tolerance=EPS):
    geom = shape(actual)
    return (geom.is_valid and not geom.is_empty
            and geom.hausdorff_distance(expected) <= tolerance
            and geom.symmetric_difference(expected).area <= tolerance * 100)


def crossing_stations(line, crossing, radius):
    """Stations whose conservative actor circle can touch the crossing."""
    contact = line.intersection(crossing.buffer(radius, quad_segs=16))
    if contact.is_empty:
        return None
    coordinates = []

    def collect(g):
        if g.geom_type in ("Point", "LineString", "LinearRing"):
            coordinates.extend(g.coords)
        elif hasattr(g, "geoms"):
            for part in g.geoms:
                collect(part)

    collect(contact)
    stations = [line.project(Point(p)) for p in coordinates]
    return [min(stations), max(stations)] if stations else None


def audit(root, npc, vehicles):
    """Return a JSON verdict; accepts in-memory documents for mutation tests."""
    root = Path(root).resolve()
    checks = []

    def ck(name, passed, **details):
        checks.append({"name": name, "passed": bool(passed), **details})

    def guarded(name, fn):
        try:
            fn()
        except (KeyError, TypeError, ValueError, IndexError, OSError, AttributeError, GEOSException) as exc:
            ck(name + ".readable_contract", False, error=type(exc).__name__ + ": " + str(exc)[:240])

    structured = all(isinstance(doc, dict) and isinstance(doc.get("routes"), list)
                     and all(isinstance(route, dict) for route in doc["routes"]) for doc in (npc, vehicles))
    ck("documents.route_document_types", structured)
    if not structured:
        return {"schema_version": 1, "task": "N01", "passed": False, "checks": checks}
    finite = all(finite_tree(doc) for doc in (npc, vehicles))
    ck("documents.finite_numbers", finite)
    if not finite:
        return {"schema_version": 1, "task": "N01", "passed": False, "checks": checks}

    try:
        source = read(root / "data/processed/features.json")
        drive = read(root / "data/processed/driveable_areas.json")
        public = read(root / "game/data/generated/public_walk.json")
        palace = read(root / "game/data/generated/palace_walk.json")
        plan = read(root / "data/manual/urban_routes.json")
        world = read(root / "game/resources/world_geometry/world.json")
        gate = read(root / "game/data/generated/daehanmun.json")
        boundary = read(root / "data/processed/boundary_candidate.json")
    except (OSError, ValueError) as exc:
        ck("inputs.readable", False, error=str(exc)[:240])
        return {"schema_version": 1, "task": "N01", "passed": False, "checks": checks}

    features = {f["feature_id"]: f for f in source["features"]}
    roads = {r["feature_id"]: r for r in drive["records"]}
    public_routes = {r["id"]: r for r in public["routes"]}
    movement = rings_geometry(public["movement_rings"])
    support = shape(public["support"]["geometry"])
    private = rings_geometry(public["private_rings"])
    palace_domain = shape(palace["support"]["geometry"])
    crossings = {c["id"]: c for c in public["crossings"]}
    # G04's candidate_geometry is a walking proposal, not a vehicle domain.
    # The reviewed vehicle domain is its own source road within background.
    envelope = box(*boundary["background_extent_xz_m"])
    stale = [p for p, digest in public["provenance"].items()
             if not (root / p).is_file() or sha(root / p) != digest]
    ck("inputs.W03_predecessor_freshness_without_regeneration", not stale, stale=stale)
    ck("inputs.G04_source_freshness_without_regeneration",
       drive["provenance"]["features_sha256"] == sha(root / "data/processed/features.json")
       and drive["provenance"]["rules_sha256"] == sha(root / "config/movement_rules.json")
       and drive["provenance"]["source_sha256"] == source["provenance"]["source_sha256"]
       == sha(root / source["provenance"]["source_file"]))

    def active_obstacles(height):
        result = []
        for mesh in world["meshes"]:
            if (mesh["role"] in ("Buildings", "Barriers") and mesh["id"] not in gate["disabled_source_ids"]
                    and mesh["bottom_y_m"] < height and mesh["top_y_m"] > 0):
                g = shape(features[mesh["metadata"]["feature_id"]]["geometry"])
                if g.geom_type in ("LineString", "MultiLineString"):
                    g = g.buffer(world["display"]["barrier_thickness_m"] / 2, cap_style="flat", join_style="mitre")
                result.append(g)
        result.extend(shape(g["geometry"]) for g in gate["fragments"] if g["bottom_y_m"] < height and g["top_y_m"] > 0)
        return union_all(result)

    npc_obstacles, vehicle_obstacles = active_obstacles(1.7), active_obstacles(1.5)
    expected_scope = {"game_plan_only": True, "runtime_controller_implemented": False,
                      "physical_lane_terrain_access_verified": False, "original_permissions_unchanged": True,
                      "new_physical_support": False, "runtime_support_verified": False,
                      "source": "OSM/G04 plus existing W03 game paths"}
    ck("plan.actor_dimensions", plan["pedestrian"] == {"height_m": 1.7, "radius_m": .3, "clearance_m": .05, "speed_mps": 1.2}
       and plan["vehicle"] == {"length_m": 4.2, "width_m": 1.8, "height_m": 1.5, "swept_radius_m": 2.6, "speed_mps": 5.0})
    ck("plan.vehicle_sweep_covers_body", 2.6 >= math.hypot(4.2 / 2, 1.8 / 2) + .1)
    policy = plan["policy"]
    ck("plan.crossing_guards", policy["priority"] == ["player_and_pedestrian", "vehicle_already_inside", "fifo_waiting_vehicle"]
       and policy["brake_mps2"] == 3.0 and policy["reaction_s"] == .5 and policy["stop_margin_m"] == 1.0
       and policy["crossing_clearance_m"] == .35 and policy["clear_hold_s"] == 1.0
       and policy["max_observation_age_s"] == .1 and policy["unknown_occupancy"] == "stop"
       and policy["zone_vehicle_capacity"] == 1 and policy["timeout_forced_entry"] is False)
    ck("plan.recycling_guards", policy["vehicle_end"] == "brake_to_stop_and_wait; no U-turn or reverse drive"
       and policy["vehicle_recycle"] == {"both_portals_outside_actual_camera_frustum": True,
           "minimum_human_distance_m": 30.0, "dynamic_entry_envelope_empty": True, "hold_until_eligible": True,
           "spatial_connection_between_portals": False})

    for name, doc in (("npc", npc), ("vehicle", vehicles)):
        def common(name=name, doc=doc):
            ck(name + ".schema", doc["schema_version"] == 1 and doc["task"] == "N01")
            ck(name + ".contract_and_mode", doc["contract_id"] == plan["contract_id"] == "N01-routes-v1"
               and doc["mode"] == ("pedestrian" if name == "npc" else "vehicle"))
            ck(name + ".coordinates", doc["coordinate_system"] == source["coordinate_system"])
            provenance = doc["provenance"]
            ck(name + ".required_source_hashes", isinstance(provenance, dict) and set(INPUTS) == set(provenance))
            invalid = []
            for path, digest in provenance.items():
                candidate = (root / path).resolve()
                if (not candidate.is_relative_to(root) or not isinstance(digest, str)
                        or len(digest) != 64 or not candidate.is_file() or sha(candidate) != digest):
                    invalid.append(path)
            ck(name + ".current_source_hashes", not invalid, invalid=invalid)
            routes = doc["routes"]
            ck(name + ".unique_route_ids", len(routes) == 2 and len({r["id"] for r in routes}) == len(routes))
            ck(name + ".planning_only_scope", doc["scope"] == expected_scope)
            ck(name + ".actor_and_policy", doc["actor"] == plan["pedestrian" if name == "npc" else "vehicle"]
               and doc["policy"] == policy)
            ck(name + ".proposal_and_assumptions", doc["initial_profile"] == plan["initial_profile"]
               and doc["assumptions"] == plan["assumptions"]
               and doc["initial_profile"]["status"] == "proposal_not_spawned_or_performance_result")
        guarded(name, common)

    expected_npc = {("court_approach", 0, 11), ("city_plaza", 97, 98)}
    npc_specs = {r["id"]: r for r in plan["npc_routes"]}
    vehicle_specs = {r["id"]: r for r in plan["vehicle_routes"]}
    npc_bodies, vehicle_bodies = [], []
    actual_npc = set()
    for i, route in enumerate(npc.get("routes", [])):
        label = "npc." + str(route.get("id", i))

        def check_npc(route=route, label=label):
            binding = route["source_binding"]
            key = (binding["parent_route"], binding["first_vertex"], binding["last_vertex"])
            actual_npc.add(key)
            parent, first, last = key
            ck(label + ".source_vertex_types", type(first) is int and type(last) is int)
            expected = public_routes[parent]["xz"][first:last + 1]
            ck(label + ".retained_W03_vertices", key in expected_npc and same_points(route["xz"], expected))
            ck(label + ".source_length", number(route["length_m"]) and abs(route["length_m"] - length(expected)) <= EPS)
            line = LineString(route["xz"])
            body = line.buffer(.35, quad_segs=16)
            npc_bodies.append(body)
            ck(label + ".snapshot_envelope", same_geometry(route["swept_geometry"], body))
            spec = npc_specs[route["id"]]
            ck(label + ".manual_binding", binding == {k: spec[k] for k in ("parent_route", "first_vertex", "last_vertex")})
            ck(label + ".name_and_repeat", route["name"] == spec["name"] and route["repeat"] == spec["repeat"] == "ping_pong"
               and route["cycle_length_m"] == 2 * line.length
               and route["turn_policy"] == "stop then rotate in free capsule; never jump endpoints")
            ck(label + ".height_and_speed", route["ground_y_m"] == 0.0 and route["speed_mps"] == 1.2)
            ck(label + ".center_in_movement", movement.buffer(EPS).covers(line))
            ck(label + ".full_body_in_support", support.buffer(EPS).covers(body))
            ck(label + ".outside_private", body.intersection(private).area <= EPS)
            ck(label + ".source_obstacle_clearance", body.disjoint(npc_obstacles))
        guarded(label, check_npc)
    ck("npc.complete_source_selections", actual_npc == expected_npc)
    ck("npc.manual_route_ids", {r.get("id") for r in npc.get("routes", [])} == set(npc_specs))

    def check_crossings():
        rows = vehicles["crossings"]
        ck("crossings.all_three_source_records", len(rows) == len(crossings) == 3
           and {c["id"] for c in rows} == set(crossings))
        for c in rows:
            original = crossings[c["id"]]
            ck("crossings." + c["id"] + ".unchanged_W03", {k: c[k] for k in original} == original)
            ck("crossings." + c["id"] + ".human_occupancy_geometry",
               same_geometry(c["human_occupancy_geometry"], shape(original["geometry"]).buffer(.35, quad_segs=16)))
        ck("crossings.priority_rule", vehicles["crossing_rule"] == "human_priority_single_vehicle_FIFO")
    guarded("crossings", check_crossings)

    expected_vehicle = {
        "osm:way:1084408283:highway_line": (5.0, 195.0),
        "osm:way:378453707:highway_line": (5.0, 260.0),
    }
    actual_vehicle = set()
    for i, route in enumerate(vehicles.get("routes", [])):
        label = "vehicle." + str(route.get("id", i))

        def check_vehicle(route=route, label=label):
            binding = route["source_binding"]
            fid = binding["feature_id"]
            actual_vehicle.add(fid)
            source_feature, road = features[fid], roads[fid]
            tags = source_feature["source_tags"]
            ck(label + ".source_consistency", road["source_tags"] == tags and road["source_geometry"] == source_feature["geometry"])
            ck(label + ".source_topology_and_refs", binding["source_node_ids"] == road["source_topology"]["node_ids"]
               and binding["source_refs"] == road["source_refs"] == source_feature["source_refs"])
            ck(label + ".road_candidate_holds", road["structural_candidate"] is True
               and not road["placement_review_reasons"] and not road["node_constraints"]
               and road["runtime_permission"] is None and road["runtime_surface_ready"] is False
               and road["physical_width_ground_and_access_verified"] is False)
            ck(label + ".source_forward_oneway_lanes", tags.get("oneway") == "yes" and tags.get("lanes") == "8"
               and road["direction"] == binding["source_direction"] == "source_forward"
               and binding["oneway"] == tags["oneway"] and str(binding["lanes"]) == tags["lanes"])
            stations = (binding["from_s_m"], binding["to_s_m"])
            ck(label + ".frozen_source_stations", fid in expected_vehicle and stations == expected_vehicle[fid])
            ck(label + ".explicit_assumed_lane", binding["lane_index_zero_based_from_left"] == 4
               and binding["assumed_lane_width_m"] == 3.2 and binding["right_offset_m"] == 1.6)
            raw = source_feature["geometry"]["coordinates"]
            cut = slice_source(raw, *stations)
            expected = right_offset(cut, 1.6)
            ck(label + ".independent_source_cut_and_right_offset", same_directed_line(route["xz"], expected))
            ck(label + ".length", number(route["length_m"]) and abs(route["length_m"] - length(expected)) <= EPS)
            line = LineString(expected)
            swept = line.buffer(2.6, quad_segs=16)
            vehicle_bodies.append(swept)
            full_road = LineString(raw).buffer(8 * 3.2 / 2, quad_segs=4, cap_style="flat", join_style="mitre")
            road_domain = full_road.intersection(envelope)
            ck(label + ".independent_estimated_road_domain", same_geometry(route["road_domain"], road_domain)
               and same_geometry(road["candidate_surface_geometry"], full_road))
            ck(label + ".swept_geometry", same_geometry(route["swept_geometry"], swept))
            ck(label + ".inside_estimated_road_and_review_envelope", road_domain.buffer(EPS).covers(swept)
               and envelope.buffer(EPS).covers(swept))
            ck(label + ".outside_palace", swept.intersection(palace_domain).area <= EPS)
            ck(label + ".outside_private", swept.intersection(private).area <= EPS)
            ck(label + ".source_obstacle_clearance", swept.disjoint(vehicle_obstacles))
            crossing_shapes = [shape(c["geometry"]) for c in crossings.values() if fid in c["road_ids"]]
            allowed = union_all(crossing_shapes)
            overlap = swept.intersection(movement)
            ck(label + ".movement_contact_only_at_source_crossing", overlap.difference(allowed.buffer(EPS)).area <= EPS)
            expected_conflicts = {}
            for cid, crossing in crossings.items():
                interval = crossing_stations(line, shape(crossing["geometry"]).buffer(.35, quad_segs=16), 2.6)
                if interval is not None:
                    expected_conflicts[cid] = interval
                    ck(label + "." + cid + ".source_road_binding", fid in crossing["road_ids"])
            reported = route["conflicts"]
            ck(label + ".complete_crossing_conflicts", len(reported) == len(expected_conflicts)
               and {c["crossing_id"] for c in reported} == set(expected_conflicts))
            for conflict in reported:
                cid = conflict["crossing_id"]
                if cid not in expected_conflicts:
                    continue
                enter, exit_ = expected_conflicts[cid]
                ck(label + "." + cid + ".full_body_entry_exit", abs(conflict["enter_s_m"] - enter) <= 1e-6
                   and abs(conflict["exit_s_m"] - exit_) <= 1e-6)
                ck(label + "." + cid + ".stop_before_body_contact", number(conflict["stop_s_m"])
                   and abs(conflict["stop_s_m"] - (enter - (5.0 * .5 + 5.0 ** 2 / (2 * 3.0) + 1.0))) <= 1e-6
                   and 0 <= conflict["stop_s_m"] < enter - EPS)
                stop = line.interpolate(conflict["stop_s_m"])
                ck(label + "." + cid + ".stop_position_and_room", math.dist(conflict["stop_xz"], list(stop.coords)[0]) <= EPS
                   and abs(conflict["stopping_distance_m"] - 23 / 3) <= EPS and exit_ < line.length - 2.6)
            spec = vehicle_specs[route["id"]]
            ck(label + ".manual_binding", all(binding[k] == spec[k] for k in ("feature_id", "from_s_m", "to_s_m",
               "assumed_lane_width_m", "lane_index_zero_based_from_left", "right_offset_m")))
            ck(label + ".oneway_repeat_and_end_stop", route["name"] == spec["name"]
               and route["repeat"] == spec["repeat"] == "guarded_oneway_stream" and route["repeat_spatial_edge"] is None
               and abs(route["stopping_distance_m"] - 23 / 3) <= EPS
               and abs(route["end_stop_s_m"] - (line.length - 23 / 3)) <= EPS)
            ck(label + ".height_and_speed", route["ground_y_m"] == 0.0 and route["speed_mps"] == 5.0)
        guarded(label, check_vehicle)
    ck("vehicle.complete_source_selections", actual_vehicle == set(expected_vehicle))
    ck("vehicle.manual_route_ids", {r.get("id") for r in vehicles.get("routes", [])} == set(vehicle_specs))
    ck("envelopes.npc_vehicle_separation", all(a.disjoint(b) for a in npc_bodies for b in vehicle_bodies))
    ck("envelopes.opposing_vehicle_separation", all(a.disjoint(b) for i, a in enumerate(vehicle_bodies) for b in vehicle_bodies[i + 1:]))

    return {
        "schema_version": 1, "task": "N01", "passed": all(c["passed"] for c in checks), "checks": checks,
        "checker_sha256": sha(Path(__file__)),
        "scope": "Local source-bound route planning snapshot; no engine/controller, real-road lane survey, terrain, traffic legality, fresh-environment installation, or prior-stage regeneration acceptance",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=Path("data/reports/n01/routes_check.json"))
    args = parser.parse_args()
    root = args.root.resolve()
    report = audit(root, read(root / "data/processed/npc_routes.json"), read(root / "data/processed/vehicle_routes.json"))
    output = args.output if args.output.is_absolute() else root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"task": "N01", "passed": report["passed"], "checks": len(report["checks"]),
                      "failed": [c["name"] for c in report["checks"] if not c["passed"]]}, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

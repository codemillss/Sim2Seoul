#!/usr/bin/env python3
"""G04 source-based walking/driving and boundary review candidates, not navmesh."""
from __future__ import annotations

import argparse
from collections import Counter
import math
from pathlib import Path

from shapely import STRtree, union_all
from shapely.geometry import Point, mapping, shape

from coordinate_system import CoordinateSystem, ROOT
from prepare_features import SourceIndex, canonical, load, save, sha
from prepare_heights import metres, levels


class TransportIndex(SourceIndex):
    def node(self, obj):
        super().node(obj)
        self.objects[f"n/{obj.id}"]["lon_lat"] = [obj.location.lon, obj.location.lat]


def inputs():
    paths = {"features": "data/processed/features.json", "heights": "data/processed/heights.json", "terrain": "data/processed/terrain.json",
        "geometry_report": "data/reports/geometry_check.json", "height_report": "data/reports/height_check.json",
        "rules": "config/movement_rules.json", "manual": "data/manual/movement_review.json", "official": "data/reports/g04_official_route_evidence.json"}
    docs = {k: load(ROOT / v) for k,v in paths.items()}
    f, h, t, gr, hr = [docs[k] for k in ["features", "heights", "terrain", "geometry_report", "height_report"]]
    hp, fp = h["provenance"], f["provenance"]
    bindings = {"features_sha256": paths["features"], "geometry_report_sha256": paths["geometry_report"],
        "height_rules_sha256": "config/height_rules.json", "decisions_sha256": "data/manual/height_review_decisions.json",
        "official_evidence_sha256": "data/reports/g03_official_evidence.json", "generator_sha256": "tools/prepare_heights.py", "source_sha256": hp["source_file"]}
    geometry_bindings = {"source_sha256":fp["source_file"], "coordinate_report_sha256":"data/reports/coordinate_check.json",
        "config_sha256":"config/region.json", "rules_sha256":"config/geometry_rules.json",
        "generator_sha256":"tools/prepare_features.py", "coordinate_module_sha256":"tools/coordinate_system.py",
        "policy_sha256":"config/data_usage.json", "manual_queue_sha256":"data/manual/review_queue.json",
        "overture_sha256":fp["overture_file"]}
    valid = (gr["passed"] and hr["passed"] and gr["input_sha256"] == sha(ROOT / paths["features"])
        and hr["heights_sha256"] == sha(ROOT / paths["heights"]) and hr["terrain_sha256"] == sha(ROOT / paths["terrain"])
        and hr["checker_sha256"] == sha(ROOT / "tools/check_heights.py") and gr["checker_sha256"] == sha(ROOT / "tools/check_geometry.py")
        and all(sha(ROOT / name) == hp[key] for key,name in bindings.items()) and hp == t["provenance"] == hr["provenance"]
        and f["coordinate_system"] == h["coordinate_system"] == t["coordinate_system"]
        and gr["provenance"] == fp and all(sha(ROOT/name)==fp[key] for key,name in geometry_bindings.items())
        and sha(ROOT/fp["preview_artifact"]["file"])==fp["preview_artifact"]["sha256"]
        and docs["manual"]["source_sha256"] == hp["source_sha256"])
    if not valid:
        raise ValueError("G04 input/G02/G03/policy/manual provenance mismatch; review and regenerate predecessors")
    rules = docs["rules"]
    numbers = [*rules["walk_width_m"].values(), *rules["drive_width_m"].values(), rules["estimated_lane_width_m"], rules["boundary_review_padding_m"]]
    if rules["schema_version"] != 1 or not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) and v>0 for v in numbers):
        raise ValueError("G04 width/envelope assumptions must be finite positive metres")
    if rules["buffer_cap_style"] != "flat" or rules["buffer_join_style"] != "mitre" or rules["buffer_quad_segs"] != 4:
        raise ValueError("Unsupported candidate buffer contract")
    p = {k+"_sha256": sha(ROOT / v) for k,v in paths.items()}
    p.update(generator_sha256=sha(Path(__file__)), source_file=hp["source_file"], source_sha256=hp["source_sha256"])
    return docs, p


def mode_access(tags, mode, rules):
    keys = ["foot", "access"] if mode == "walk" else ["motorcar", "motor_vehicle", "vehicle", "access"]
    key = next((k for k in keys if k in tags), None)
    value = tags.get(key)
    highway = tags.get("highway")
    semantic = (highway in rules["walk_highways"] or highway == "cycleway" and value in rules["accepted_access_values"]) if mode == "walk" else highway in rules["drive_highways"]
    # Explicit foot on a carriageway does not create a sidewalk. Retain for review.
    if any(k.endswith(":conditional") for k in tags) or tags.get("opening_hours"):
        return False, "held_conditional_or_time_access", key, value
    if highway == "construction":
        return False, "held_construction", key, value
    if value is not None and value not in rules["accepted_access_values"]:
        return False, "held_restricted_or_unparsed_access", key, value
    if not semantic:
        return False, "not_this_mode_geometry", key, value
    return True, "explicit_mode_access" if key else "highway_semantic_candidate_not_verified_access", key, value


def width(feature, mode, rules):
    tags = feature["source_tags"]
    if feature["source_kind"] == "highway_area":
        return None, "source_area_no_centreline_width", None
    if "width" in tags:
        value, status = metres(tags["width"])
        return value, "source_width_not_independently_measured" if value is not None else "held_invalid_source_width", None
    count = levels(tags.get("lanes"))
    if mode == "drive" and count is not None:
        return count * rules["estimated_lane_width_m"], "estimated_from_total_lanes_no_sidewalk_inferred", rules["assumption_id"]
    table = rules[mode+"_width_m"]
    return table.get(tags["highway"]), "estimated_highway_default" if tags["highway"] in table else "no_width_for_this_mode", rules["assumption_id"] if tags["highway"] in table else None


def source_node_ids(feature, raw):
    nodes = []
    visited = set()
    def visit(identity):
        if identity in visited:
            return
        visited.add(identity)
        obj = raw.objects[identity]
        nodes.extend(obj.get("node_ids", []))
        for member in obj.get("members", []):
            if member["object_id"].startswith("n/"):
                nodes.append(int(member["object_id"][2:]))
            else:
                visit(member["object_id"])
    visit(feature["source_refs"][0]["object_id"])
    return list(dict.fromkeys(nodes))


def node_constraints(feature, raw, system):
    result = []
    for nid in source_node_ids(feature, raw):
        obj = raw.objects[f"n/{nid}"]; tags = obj["tags"]
        if any(k in tags for k in ["barrier", "access", "foot", "motor_vehicle", "motorcar", "vehicle", "indoor"]) or any(k.endswith(":conditional") for k in tags):
            x,_,z = system.to_world(*obj["lon_lat"], local_height_m=0)
            result.append({"node_id": nid, "source_tags": tags, "local_xz": [x,z],
                "status": "node_access_or_barrier_review; no automatic opening or height"})
    return result


def classify(feature, ground, mode, rules, raw, system):
    tags = feature["source_tags"]
    eligible, state, key, value = mode_access(tags, mode, rules)
    w, ws, assumption = width(feature, mode, rules)
    constraints = node_constraints(feature, raw, system)
    reasons = list(ground["reasons"])
    if tags.get("indoor") not in (None, "no"):
        reasons.append("indoor_context_not_public_ground")
    if tags.get("step_count") or tags.get("incline"):
        reasons.append("step_or_incline_requires_height_review")
    if constraints:
        reasons.append("transport_node_constraint_review")
    if ws == "held_invalid_source_width":
        reasons.append(ws)
    surface = None
    if eligible and not reasons:
        geom = shape(feature["geometry"])
        if feature["source_kind"] == "highway_area":
            surface = feature["geometry"]
        elif w is not None:
            surface = mapping(geom.buffer(w/2, quad_segs=rules["buffer_quad_segs"], cap_style="flat", join_style="mitre"))
    if mode == "walk":
        direction = "bidirectional_walk_candidate; vehicle_oneway_not_applied"
    else:
        value_oneway = tags.get("oneway")
        direction = "source_forward" if value_oneway in ("yes","1","true") else "source_reverse" if value_oneway == "-1" else "source_bidirectional" if value_oneway in ("no","0","false") else "implicit_bidirectional_candidate" if value_oneway is None and tags.get("junction") != "roundabout" else "source_roundabout_forward" if value_oneway is None else "held_unparsed_direction"
        if direction == "held_unparsed_direction":
            surface = None; reasons.append(direction)
    return {"feature_id": feature["feature_id"], "source_refs": feature["source_refs"], "source_tags": tags,
        "source_kind": feature["source_kind"], "source_geometry": feature["geometry"], "source_topology": feature["source_topology"],
        "mode": mode, "mode_class": state, "access_basis": {"key":key,"value":value}, "structural_candidate": eligible,
        "runtime_permission": None, "direction": direction, "width_m": w, "width_class": ws, "assumption_id": assumption,
        "ground_y_m": ground["ground_y_m"], "placement_review_reasons": reasons, "node_constraints": constraints,
        "candidate_surface_geometry": surface, "runtime_surface_ready": False,
        "physical_width_ground_and_access_verified": False}


def contacts(a, b):
    ga, gb = shape(a["source_geometry"]), shape(b["source_geometry"])
    shared = sorted(set(a["source_topology"].get("node_ids",[])) & set(b["source_topology"].get("node_ids",[])))
    if a["source_kind"] == b["source_kind"] == "highway_line":
        return ("shared_source_nodes", shared) if shared else None
    if not ga.intersects(gb):
        return None
    return "source_line_area_contact" if "highway_line" in (a["source_kind"], b["source_kind"]) else "source_area_area_contact", shared


def graph(records):
    candidates = [r for r in records if r["structural_candidate"]]
    tree = STRtree([shape(r["source_geometry"]) for r in candidates])
    edges = []
    for n,a in enumerate(candidates):
        for k in sorted(tree.query(shape(a["source_geometry"]), predicate="intersects")):
            if k <= n: continue
            b = candidates[k]; contact = contacts(a,b)
            if contact:
                basis, nodes = contact
                edges.append({"feature_ids": [a["feature_id"],b["feature_id"]], "basis":basis,"shared_node_ids":nodes,
                    "vertical_or_node_review": bool(a["placement_review_reasons"] or b["placement_review_reasons"]),
                    "physical_connection_verified":False})
    return edges


def conflicts(records, features, threshold):
    obstacles = [f for f in features if f["source_kind"] in ("building","barrier") and (f["source_kind"]=="barrier" or f["source_tags"].get("building")!="roof")]
    tree = STRtree([shape(f["geometry"]) for f in obstacles]); result=[]
    for r in records:
        geometry = r["candidate_surface_geometry"]
        if geometry is None: continue
        geom = shape(geometry)
        for k in sorted(tree.query(geom,predicate="intersects")):
            obstacle = obstacles[k]; hit = geom.intersection(shape(obstacle["geometry"]))
            if hit.area > threshold or obstacle["source_kind"]=="barrier" and hit.length > 0:
                result.append({"feature_id":r["feature_id"],"obstacle_id":obstacle["feature_id"],"area_m2":hit.area,"length_m":hit.length,
                    "status":"review_candidate_not_auto_cut_or_accepted_collision"})
    return result


def prepare():
    docs,p = inputs(); fdoc = docs["features"]; features=fdoc["features"]; rules=docs["rules"]; manual=docs["manual"]
    byid = {f["feature_id"]:f for f in features}; ground={g["feature_id"]:g for g in docs["terrain"]["records"]}
    roads=[f for f in features if f["source_kind"].startswith("highway")]
    raw=TransportIndex(); raw.apply_file(ROOT/p["source_file"]); system=CoordinateSystem()
    walk=[classify(f,ground[f["feature_id"]],"walk",rules,raw,system) for f in roads]
    drive=[classify(f,ground[f["feature_id"]],"drive",rules,raw,system) for f in roads]
    edges=graph(walk); edge_map={frozenset(e["feature_ids"]):e for e in edges}; by_source={r["source_refs"][0]["object_id"]:r for r in walk}
    routes=[]
    for route in manual["routes"]:
        chain=[by_source[i]["feature_id"] for i in route["chain"]]
        links=[edge_map.get(frozenset(pair)) for pair in zip(chain,chain[1:])]
        targets=[by_source[i]["feature_id"] for i in route["target_surface_ids"]]
        target_links=[e for e in edges if any(i in targets for i in e["feature_ids"]) and any(i in chain for i in e["feature_ids"] if i not in targets)]
        checkpoints=[]
        for c in route["checkpoints"]:
            r=by_source[c["way_id"]]; nid=c["node_id"]
            if nid not in r["source_topology"]["node_ids"]: raise ValueError("Checkpoint is not on declared source way")
            lonlat=raw.objects[f"n/{nid}"]["lon_lat"]; x,_,z=system.to_world(*lonlat,local_height_m=0)
            checkpoints.append({**c,"source_lon_lat":lonlat,"local_xz":[x,z],"ground_y_m":None,"runtime_spawn":False})
        routes.append({**route,"feature_chain":chain,"source_contact_links":links,"target_contact_links":target_links,
            "source_chain_connected_2d":all(links) and all(by_source[i]["structural_candidate"] for i in route["chain"]),
            "checkpoints":checkpoints,"placement_review_feature_ids":[fid for fid in chain if next(r for r in walk if r["feature_id"]==fid)["placement_review_reasons"]],
            "runtime_path_geometry":None,"game_or_real_world_completion_verified":False})
    passages=[]
    for passage in manual["gate_passages"]:
        road=by_source[passage["way_id"]]; building=byid[canonical(passage["building_id"])+":building"]
        passages.append({**passage,"source_tags":road["source_tags"],"source_intersection_length_m":shape(road["source_geometry"]).intersection(shape(building["geometry"])).length,
            "geometry_changed":False,"collision_opening_created":False})
    all_route_ids=sorted({fid for route in routes for fid in route["feature_chain"]+ [by_source[i]["feature_id"] for i in route["target_surface_ids"]]})
    envelope_inputs=all_route_ids+manual["boundary_reference_ids"]
    envelope=union_all([shape(byid[fid]["geometry"]) for fid in envelope_inputs]).buffer(rules["boundary_review_padding_m"],quad_segs=4,join_style="mitre")
    private=union_all([shape(byid[fid]["geometry"]) for fid in manual["excluded_private_enclosure_ids"]])
    envelope=envelope.difference(private)
    if envelope.is_empty or not envelope.is_valid: raise ValueError("Invalid review envelope; no automatic repair")
    base={"schema_version":1,"task_id":"G04","provenance":p,"coordinate_system":fdoc["coordinate_system"],"rules":rules,"scope":"Source-based movement candidates; no runtime permission, mesh or verified terrain"}
    walkdoc={**base,"mode":"walk","records":walk,"classification_counts":dict(sorted(Counter(r["mode_class"] for r in walk).items())),
        "source_contact_graph":edges,"route_reviews":routes,"gate_passage_reviews":passages,
        "obstacle_conflicts":conflicts(walk,features,rules["conflict_min_area_m2"]),
        "land_references_not_auto_walkable":[f["feature_id"] for f in features if f["source_kind"]=="land_area"]}
    drivedoc={**base,"mode":"drive","records":drive,"classification_counts":dict(sorted(Counter(r["mode_class"] for r in drive).items())),
        "obstacle_conflicts":conflicts(drive,features,rules["conflict_min_area_m2"]),"vehicle_routes":[],"turn_restrictions_or_traffic_control_verified":False}
    cross=[]; driverecs=[r for r in drive if r["structural_candidate"]]
    for r in walk:
        if r["structural_candidate"] and r["source_tags"].get("footway")=="crossing":
            hits=[d["feature_id"] for d in driverecs if shape(r["source_geometry"]).intersects(shape(d["source_geometry"]))]
            cross.append({"feature_id":r["feature_id"],"drive_contact_ids":hits,"traffic_control_created":False})
    drivedoc["crossing_conflicts"]=cross
    boundary={**base,"candidate_geometry":mapping(envelope),"candidate_bounds_xz_m":list(envelope.bounds),"padding_m":rules["boundary_review_padding_m"],
        "envelope_input_feature_ids":envelope_inputs,"private_enclosure_exclusions":manual["excluded_private_enclosure_ids"],
        "investigation_bbox_is_play_boundary":False,"finalized_playable_boundary":None,"background_extent_xz_m":docs["terrain"]["temporary_support_plane"]["local_xz_extent"],
        "access_granted_by_envelope":False,"spawn_point":None,"fall_recovery_or_boundary_collision_created":False,
        "remaining":["mixed road/building/garden zones are not granted access", "wall duplicates/gate opening widths", "terrain transitions and fall recovery", "dated construction footprint", "W01-W04 collision and route acceptance"]}
    return walkdoc,drivedoc,boundary


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--walk",default="data/processed/walkable_areas.json");parser.add_argument("--drive",default="data/processed/driveable_areas.json");parser.add_argument("--boundary",default="data/processed/boundary_candidate.json")
    args=parser.parse_args();w,d,b=prepare()
    for path,doc in [(args.walk,w),(args.drive,d),(args.boundary,b)]:save(ROOT/path,doc)
    print({"walk_counts":w["classification_counts"],"drive_counts":d["classification_counts"],"source_graph_edges":len(w["source_contact_graph"]),"route_connections":{r["route_id"]:r["source_chain_connected_2d"] for r in w["route_reviews"]}})


if __name__ == "__main__":main()

#!/usr/bin/env python3
"""Validate G04 source semantics, candidate surfaces, contacts and review limits."""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from shapely import union_all
from shapely.geometry import shape, Point

from coordinate_system import CoordinateSystem, ROOT
from prepare_features import canonical, load, save, sha
from prepare_movement import inputs, TransportIndex, mode_access, width, contacts, graph, conflicts, node_constraints


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--walk",default="data/processed/walkable_areas.json");parser.add_argument("--drive",default="data/processed/driveable_areas.json");parser.add_argument("--boundary",default="data/processed/boundary_candidate.json");parser.add_argument("--report",default="data/reports/movement_check.json")
    args=parser.parse_args();docs,p=inputs()
    walk,drive,boundary=[load(ROOT/path) for path in [args.walk,args.drive,args.boundary]]
    rules=docs["rules"]; manual=docs["manual"];fdoc=docs["features"]; features={f["feature_id"]:f for f in fdoc["features"]}
    ground={g["feature_id"]:g for g in docs["terrain"]["records"]}
    checks={"current_predecessors_rules_manual_evidence_and_generator_bound":all(d["provenance"]==p for d in [walk,drive,boundary]),
        "schema_coordinates_embedded_rules_match":walk["mode"]=="walk" and drive["mode"]=="drive" and all(d["schema_version"]==1 and d["task_id"]=="G04" and d["coordinate_system"]==fdoc["coordinate_system"] and d["rules"]==rules for d in [walk,drive,boundary])}
    if not checks["current_predecessors_rules_manual_evidence_and_generator_bound"]:raise SystemExit("G04 provenance mismatch; regenerate three candidates together")
    roadids={fid for fid,f in features.items() if f["source_kind"].startswith("highway")}
    checks["complete_unique_highway_records_in_both_modes"] = all(len(d["records"])==len(roadids) and {r["feature_id"] for r in d["records"]}==roadids for d in [walk,drive])
    raw=TransportIndex();raw.apply_file(ROOT/p["source_file"]);system=CoordinateSystem()
    attribute_errors=[];access_errors=[];width_errors=[];geometry_errors=[];placement_errors=[];permission_errors=[];direction_errors=[]
    for mode,doc in [("walk",walk),("drive",drive)]:
        for r in doc["records"]:
            fid=r["feature_id"]; f=features[fid]; tags=f["source_tags"]
            if any(r[key]!=f[key] for key in ["source_tags","source_refs","source_topology","source_kind"]) or r["source_geometry"]!=f["geometry"] or r["mode"]!=mode:
                attribute_errors.append([mode,fid])
            eligible,state,key,value=mode_access(tags,mode,rules)
            if r["structural_candidate"]!=eligible or r["mode_class"]!=state or r["access_basis"]!={"key":key,"value":value}:
                access_errors.append([mode,fid])
            expected_width,expected_class,assumption=width(f,mode,rules)
            if (r["width_m"],r["width_class"],r["assumption_id"])!=(expected_width,expected_class,assumption):width_errors.append([mode,fid])
            expected_nodes=node_constraints(f,raw,system)
            if r["node_constraints"]!=expected_nodes:attribute_errors.append([mode,fid])
            reasons=list(ground[fid]["reasons"])
            if tags.get("indoor") not in (None,"no"):reasons.append("indoor_context_not_public_ground")
            if tags.get("step_count") or tags.get("incline"):reasons.append("step_or_incline_requires_height_review")
            if expected_nodes:reasons.append("transport_node_constraint_review")
            if expected_class=="held_invalid_source_width":reasons.append(expected_class)
            if mode=="walk":
                expected_direction="bidirectional_walk_candidate; vehicle_oneway_not_applied"
            else:
                ow=tags.get("oneway")
                expected_direction="source_forward" if ow in ("yes","1","true") else "source_reverse" if ow=="-1" else "source_bidirectional" if ow in ("no","0","false") else "implicit_bidirectional_candidate" if ow is None and tags.get("junction")!="roundabout" else "source_roundabout_forward" if ow is None else "held_unparsed_direction"
                if expected_direction=="held_unparsed_direction":reasons.append(expected_direction)
            if r["direction"]!=expected_direction:direction_errors.append([mode,fid])
            if r["placement_review_reasons"]!=reasons or r["ground_y_m"]!=ground[fid]["ground_y_m"]:placement_errors.append([mode,fid])
            if r["runtime_permission"] is not None or r["runtime_surface_ready"] or r["physical_width_ground_and_access_verified"]:permission_errors.append([mode,fid])
            surface=r["candidate_surface_geometry"]
            if not eligible or reasons:
                if surface is not None:geometry_errors.append([mode,fid])
            elif f["source_kind"]=="highway_area":
                if surface!=f["geometry"]:geometry_errors.append([mode,fid])
            elif expected_width is not None:
                expected=shape(f["geometry"]).buffer(expected_width/2,quad_segs=4,cap_style="flat",join_style="mitre")
                if surface is None or not shape(surface).equals_exact(expected,1e-8):geometry_errors.append([mode,fid])
            elif surface is not None:geometry_errors.append([mode,fid])
            if surface is not None and (not shape(surface).is_valid or shape(surface).is_empty):geometry_errors.append([mode,fid])
    checks.update(source_tags_topology_node_constraints_and_geometry_preserved=not attribute_errors,
        mode_specific_access_overrides_and_restrictions_preserved=not access_errors,
        widths_and_assumptions_not_measured_sidewalks=not width_errors,
        source_area_holes_and_exact_estimated_buffers_preserved=not geometry_errors,
        ground_steps_indoor_and_node_holds_not_flattened=not placement_errors,
        candidate_surfaces_do_not_grant_runtime_permission=not permission_errors,
        vehicle_oneway_preserved_and_not_applied_to_walking=not direction_errors)
    checks["classification_counts_match_records"]=all(d["classification_counts"]==dict(Counter(r["mode_class"] for r in d["records"])) for d in [walk,drive])
    expected_graph=graph(walk["records"])
    checks["graph_contacts_complete_no_distance_snapping_or_verified_connections"]=walk["source_contact_graph"]==expected_graph and all(not e["physical_connection_verified"] for e in walk["source_contact_graph"])
    edge_map={frozenset(e["feature_ids"]):e for e in expected_graph};wby={r["source_refs"][0]["object_id"]:r for r in walk["records"]}
    route_errors=[]; checkpoint_errors=[]
    if len(walk["route_reviews"])!=len(manual["routes"]):route_errors.append("missing_route")
    for m,r in zip(manual["routes"],walk["route_reviews"]):
        chain=[wby[i]["feature_id"] for i in m["chain"]]
        links=[edge_map.get(frozenset(pair)) for pair in zip(chain,chain[1:])]
        targets=[wby[i]["feature_id"] for i in m["target_surface_ids"]]
        target_links=[e for e in expected_graph if any(i in targets for i in e["feature_ids"]) and any(i in chain for i in e["feature_ids"] if i not in targets)]
        expected_held=[fid for fid in chain if next(t for t in walk["records"] if t["feature_id"]==fid)["placement_review_reasons"]]
        if any(r[k]!=m[k] for k in m if k!="checkpoints") or r["feature_chain"]!=chain or r["source_contact_links"]!=links or not all(links) or not r["source_chain_connected_2d"] or r["target_contact_links"]!=target_links or not target_links or r["placement_review_feature_ids"]!=expected_held or r["runtime_path_geometry"] is not None or r["game_or_real_world_completion_verified"]:
            route_errors.append(m["route_id"])
        if len(r["checkpoints"])!=len(m["checkpoints"]):checkpoint_errors.append(m["route_id"])
        for mc,c in zip(m["checkpoints"],r["checkpoints"]):
            obj=raw.objects[f"n/{mc['node_id']}"]; x,_,z=system.to_world(*obj["lon_lat"],local_height_m=0)
            if any(c[k]!=v for k,v in mc.items()) or mc["node_id"] not in raw.objects[mc["way_id"]]["node_ids"] or c["source_lon_lat"]!=obj["lon_lat"] or c["local_xz"]!=[x,z] or c["ground_y_m"] is not None or c["runtime_spawn"]:checkpoint_errors.append(m["route_id"])
    checks["required_R1_R2_R3_source_chains_connected_with_holds_retained"]=not route_errors
    checks["checkpoints_bound_to_raw_nodes_not_runtime_spawns"]=not checkpoint_errors
    passages=[]
    for m in manual["gate_passages"]:
        tags=raw.objects[m["way_id"]]["tags"]
        length=shape(wby[m["way_id"]]["source_geometry"]).intersection(shape(features[canonical(m["building_id"])+":building"]["geometry"])).length
        passages.append({**m,"source_tags":tags,"source_intersection_length_m":length,"geometry_changed":False,"collision_opening_created":False})
    checks["gate_passage_evidence_preserved_no_invented_width_or_opening"]=walk["gate_passage_reviews"]==passages and all(p["source_tags"].get("tunnel")=="building_passage" and p["source_intersection_length_m"]>0 and p["clear_width_m"] is None for p in passages)
    all_route_ids=sorted({fid for r in walk["route_reviews"] for fid in r["feature_chain"]+[wby[i]["feature_id"] for i in r["target_surface_ids"]]})
    expected_ids=all_route_ids+manual["boundary_reference_ids"]
    private=union_all([shape(features[fid]["geometry"]) for fid in manual["excluded_private_enclosure_ids"]])
    expected_boundary=union_all([shape(features[fid]["geometry"]) for fid in expected_ids]).buffer(rules["boundary_review_padding_m"],quad_segs=4,join_style="mitre").difference(private)
    candidate=shape(boundary["candidate_geometry"])
    checks["boundary_envelope_source_union_padding_and_private_exclusions_match"]=boundary["padding_m"]==rules["boundary_review_padding_m"] and boundary["envelope_input_feature_ids"]==expected_ids and boundary["private_enclosure_exclusions"]==manual["excluded_private_enclosure_ids"] and candidate.equals_exact(expected_boundary,1e-8) and list(candidate.bounds)==boundary["candidate_bounds_xz_m"] and candidate.is_valid
    checks["boundary_covers_required_source_chains_and_excludes_embassy"]=all(candidate.covers(shape(features[fid]["geometry"])) for fid in all_route_ids) and candidate.intersection(private).area<1e-8
    checks["review_envelope_not_bbox_or_final_boundary_spawn_or_permission"]=boundary["finalized_playable_boundary"] is None and boundary["spawn_point"] is None and not boundary["investigation_bbox_is_play_boundary"] and not boundary["access_granted_by_envelope"] and not boundary["fall_recovery_or_boundary_collision_created"] and boundary["background_extent_xz_m"]==docs["terrain"]["temporary_support_plane"]["local_xz_extent"]
    checks["land_gardens_parks_not_auto_walking_or_vehicle_geometry"]=walk["land_references_not_auto_walkable"]==[fid for fid,f in features.items() if f["source_kind"]=="land_area"] and all(r["source_kind"].startswith("highway") for d in [walk,drive] for r in d["records"])
    checks["source_obstacle_conflicts_not_silently_cut_or_deleted"]=all(d["obstacle_conflicts"]==conflicts(d["records"],fdoc["features"],rules["conflict_min_area_m2"]) for d in [walk,drive])
    expected_cross=[]
    for r in walk["records"]:
        if r["structural_candidate"] and r["source_tags"].get("footway")=="crossing":
            expected_cross.append({"feature_id":r["feature_id"],"drive_contact_ids":[d["feature_id"] for d in drive["records"] if d["structural_candidate"] and shape(r["source_geometry"]).intersects(shape(d["source_geometry"]))],"traffic_control_created":False})
    checks["crossing_conflicts_retained_without_vehicle_control_claim"]=drive["crossing_conflicts"]==expected_cross and drive["vehicle_routes"]==[] and drive["turn_restrictions_or_traffic_control_verified"] is False
    # Current source examples independently guard the critical interpretation choices.
    checks["foot_yes_overrides_blanket_no_and_vehicle_stays_denied"]=all(wby[i]["structural_candidate"] and wby[i]["access_basis"]["key"]=="foot" and not next(r for r in drive["records"] if r["feature_id"]==wby[i]["feature_id"])["structural_candidate"] for i in ["w/1209113130","w/1209132247","w/1217120571","w/1230789314"])
    checks["R2_uses_ground_north_crossing_not_underground_or_direct_cut"]=wby["w/1230789306"]["source_tags"].get("footway")=="crossing" and not ground[wby["w/1230789306"]["feature_id"]]["reasons"] and all(i not in next(r for r in walk["route_reviews"] if r["route_id"]=="R2")["chain"] for i in ["w/338906156","w/338906157","w/338906159","w/1230789310"])
    report={"task_id":"G04","provenance":p,"checker_sha256":sha(Path(__file__)),"walk_sha256":sha(ROOT/args.walk),"drive_sha256":sha(ROOT/args.drive),"boundary_sha256":sha(ROOT/args.boundary),
        "checks":checks,"passed":all(checks.values()),"highway_record_count":len(walk["records"]),"walk_classification_counts":walk["classification_counts"],"drive_classification_counts":drive["classification_counts"],
        "walk_structural_candidates":sum(r["structural_candidate"] for r in walk["records"]),"drive_structural_candidates":sum(r["structural_candidate"] for r in drive["records"]),
        "walk_surface_candidates":sum(r["candidate_surface_geometry"] is not None for r in walk["records"]),"drive_surface_candidates":sum(r["candidate_surface_geometry"] is not None for r in drive["records"]),
        "walk_obstacle_conflict_count":len(walk["obstacle_conflicts"]),"drive_obstacle_conflict_count":len(drive["obstacle_conflicts"]),"crossing_conflict_count":len(drive["crossing_conflicts"]),
        "routes":[{k:r[k] for k in ["route_id","chain","source_chain_connected_2d","placement_review_feature_ids","remaining"]} for r in walk["route_reviews"]],"gate_passages":passages,"boundary_bounds_xz_m":boundary["candidate_bounds_xz_m"],
        "errors":{"attributes":attribute_errors,"access":access_errors,"widths":width_errors,"geometry":geometry_errors,"placement":placement_errors,"permissions":permission_errors,"directions":direction_errors,"routes":route_errors,"checkpoints":checkpoint_errors},
        "not_run":["Actual walk/drive or collision","Measured width/ground/access","Navmesh/vehicle routes/turn restrictions","Final play boundary/fall recovery","M4 Pro"]}
    save(ROOT/args.report,report);print({"passed":report["passed"],"checks":len(checks),"highways":len(walk["records"]),"walk_surface_candidates":report["walk_surface_candidates"],"drive_surface_candidates":report["drive_surface_candidates"]})
    if not report["passed"]:raise SystemExit(1)


if __name__ == "__main__":main()

#!/usr/bin/env python3
"""G04 negative tests for corrupt candidate inputs; source/manual files stay intact."""
from __future__ import annotations
import argparse, copy, subprocess, sys, tempfile
from pathlib import Path
from shapely.geometry import mapping, shape
from coordinate_system import ROOT
from prepare_features import canonical, load, save, sha

def record(doc, identity):
    return next(r for r in doc["records"] if r["source_refs"][0]["object_id"]==identity)

def wrong_foot(w,d,b):
    record(w,"w/1209113130")["structural_candidate"]=False
def vehicle_on_plaza(w,d,b):
    record(d,"r/6012272")["structural_candidate"]=True
def measured_estimate(w,d,b):
    record(w,"w/1530764334")["width_class"]="source_width_not_independently_measured"
def changed_buffer(w,d,b):
    r=record(w,"w/1530764334"); r["candidate_surface_geometry"]=mapping(shape(r["candidate_surface_geometry"]).buffer(1))
def filled_courtyard(w,d,b):
    g=record(w,"r/5681909")["candidate_surface_geometry"]; assert len(g["coordinates"][0])>1;del g["coordinates"][0][1:]
def flattened_passage(w,d,b):
    r=record(w,"w/377289807");r["ground_y_m"]=0;r["placement_review_reasons"]=[];r["candidate_surface_geometry"]=mapping(shape(r["source_geometry"]).buffer(1.2))
def fake_graph_edge(w,d,b):
    w["source_contact_graph"].append({"feature_ids":[record(w,"w/1530764334")["feature_id"],record(w,"r/6012272")["feature_id"]],"basis":"nearby_distance_snap","shared_node_ids":[],"vertical_or_node_review":False,"physical_connection_verified":False})
def lost_route(w,d,b):
    w["route_reviews"][0]["source_contact_links"]=[]
def shifted_checkpoint(w,d,b):
    w["route_reviews"][0]["checkpoints"][0]["local_xz"][0]+=1
def invented_gate_width(w,d,b):
    w["gate_passage_reviews"][0]["clear_width_m"]=2.4
def boundary_grants_access(w,d,b):
    b["access_granted_by_envelope"]=True;b["finalized_playable_boundary"]=b["candidate_geometry"]
def removed_conflicts(w,d,b):
    w["obstacle_conflicts"]=[]
def wrong_oneway(w,d,b):
    record(d,"w/37400087")["direction"]="source_bidirectional"
def runtime_permission(w,d,b):
    record(w,"w/1530764334")["runtime_permission"]=True
def changed_document_mode(w,d,b):
    w["mode"]="drive"
def changed_padding(w,d,b):
    b["padding_m"]=1000
def removed_relation_kerb(w,d,b):
    r=record(w,"r/10755141");assert r["node_constraints"];r["node_constraints"]=[]

CASES=[
    ("foot_override_lost",wrong_foot,"mode_specific_access_overrides_and_restrictions_preserved"),
    ("vehicles_on_pedestrian_plaza",vehicle_on_plaza,"mode_specific_access_overrides_and_restrictions_preserved"),
    ("estimate_relabelled_source_width",measured_estimate,"widths_and_assumptions_not_measured_sidewalks"),
    ("enlarged_centreline_buffer",changed_buffer,"source_area_holes_and_exact_estimated_buffers_preserved"),
    ("filled_courtyard_hole",filled_courtyard,"source_area_holes_and_exact_estimated_buffers_preserved"),
    ("flattened_gate_passage",flattened_passage,"ground_steps_indoor_and_node_holds_not_flattened"),
    ("snapped_direct_crossing",fake_graph_edge,"graph_contacts_complete_no_distance_snapping_or_verified_connections"),
    ("removed_R1_connection_evidence",lost_route,"required_R1_R2_R3_source_chains_connected_with_holds_retained"),
    ("shifted_raw_checkpoint",shifted_checkpoint,"checkpoints_bound_to_raw_nodes_not_runtime_spawns"),
    ("invented_gate_clear_width",invented_gate_width,"gate_passage_evidence_preserved_no_invented_width_or_opening"),
    ("review_boundary_grants_access",boundary_grants_access,"review_envelope_not_bbox_or_final_boundary_spawn_or_permission"),
    ("deleted_obstacle_conflicts",removed_conflicts,"source_obstacle_conflicts_not_silently_cut_or_deleted"),
    ("vehicle_oneway_lost",wrong_oneway,"vehicle_oneway_preserved_and_not_applied_to_walking"),
    ("candidate_grants_runtime_permission",runtime_permission,"candidate_surfaces_do_not_grant_runtime_permission"),
    ("changed_document_mode",changed_document_mode,"schema_coordinates_embedded_rules_match"),
    ("changed_boundary_padding",changed_padding,"boundary_envelope_source_union_padding_and_private_exclusions_match"),
    ("removed_relation_kerb_constraint",removed_relation_kerb,"source_tags_topology_node_constraints_and_geometry_preserved")]

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--report",default="data/reports/g04_regression_check.json");args=parser.parse_args()
    originals=[load(ROOT/p) for p in ["data/processed/walkable_areas.json","data/processed/driveable_areas.json","data/processed/boundary_candidate.json"]]; results=[]
    with tempfile.TemporaryDirectory(prefix="sim2seoul-g04-regression-") as name:
        folder=Path(name); baseline=folder/"baseline.json"
        r=subprocess.run([sys.executable,str(ROOT/"tools/check_movement.py"),"--report",str(baseline)],cwd=ROOT,capture_output=True,text=True)
        if r.returncode or not load(baseline)["passed"]:raise SystemExit("Baseline movement checks required")
        for name,mutate,required in CASES:
            w,d,b=copy.deepcopy(originals);mutate(w,d,b)
            paths=[folder/(name+s) for s in ["-walk.json","-drive.json","-boundary.json","-report.json"]]
            for p,doc in zip(paths,[w,d,b]):save(p,doc)
            r=subprocess.run([sys.executable,str(ROOT/"tools/check_movement.py"),"--walk",str(paths[0]),"--drive",str(paths[1]),"--boundary",str(paths[2]),"--report",str(paths[3])],cwd=ROOT,capture_output=True,text=True)
            report=load(paths[3]) if paths[3].exists() else {}
            results.append({"case":name,"rejected":r.returncode!=0 and report.get("checks",{}).get(required) is False,"required_failed_check":required,"failed_checks":[k for k,v in report.get("checks",{}).items() if not v],"exit_code":r.returncode,"error":r.stderr.strip() or None})
    report={"task_id":"G04","baseline_passed":True,"passed":all(r["rejected"] for r in results),"checker_sha256":sha(ROOT/"tools/check_movement.py"),"regression_tool_sha256":sha(Path(__file__)),"cases":results,
        "input_sha256":dict(zip(["walk","drive","boundary"],[sha(ROOT/p) for p in ["data/processed/walkable_areas.json","data/processed/driveable_areas.json","data/processed/boundary_candidate.json"]])),"scope":"Seventeen corrupt derived inputs; no source/manual changes or game tests"}
    save(ROOT/args.report,report);print({"passed":report["passed"],"rejected":sum(r["rejected"] for r in results),"cases":len(results)})
    if not report["passed"]:raise SystemExit(1)

if __name__=="__main__":main()

#!/usr/bin/env python3
"""E03: deterministic display triangles from reviewed local-XZ G02/G03/G04 inputs."""
import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

import shapely
from shapely import constrained_delaunay_triangles, orient_polygons
from shapely.geometry import box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
WORLD = "game/resources/world_geometry/world.json"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()


def validate_inputs(root):
    paths = ["config/region.json", "config/world_display.json", "data/reports/coordinate_check.json",
             "data/processed/features.json", "data/processed/heights.json", "data/processed/terrain.json",
             "data/processed/walkable_areas.json", "data/processed/driveable_areas.json",
             "data/reports/geometry_check.json", "data/reports/height_check.json", "data/reports/movement_check.json"]
    docs = {p: json.loads((root / p).read_text()) for p in paths}
    hashes = {p: digest(root / p) for p in paths}
    features = docs["data/processed/features.json"]
    heights = docs["data/processed/heights.json"]
    terrain = docs["data/processed/terrain.json"]
    walk = docs["data/processed/walkable_areas.json"]
    drive = docs["data/processed/driveable_areas.json"]
    links = [(docs["data/reports/coordinate_check.json"]["provenance"], "config_sha256", "config/region.json"),
             (features["provenance"], "config_sha256", "config/region.json"),
             (docs["data/reports/geometry_check.json"], "input_sha256", "data/processed/features.json"),
             (docs["data/reports/height_check.json"], "heights_sha256", "data/processed/heights.json"),
             (docs["data/reports/height_check.json"], "terrain_sha256", "data/processed/terrain.json"),
             (docs["data/reports/movement_check.json"], "walk_sha256", "data/processed/walkable_areas.json"),
             (docs["data/reports/movement_check.json"], "drive_sha256", "data/processed/driveable_areas.json")]
    for document in [heights, terrain, walk, drive]:
        links.append((document["provenance"], "features_sha256", "data/processed/features.json"))
        links.append((document["provenance"], "geometry_report_sha256", "data/reports/geometry_check.json"))
        if document in [walk, drive]:
            links.extend([(document["provenance"], "heights_sha256", "data/processed/heights.json"),
                          (document["provenance"], "terrain_sha256", "data/processed/terrain.json"),
                          (document["provenance"], "height_report_sha256", "data/reports/height_check.json")])
    # Policies and review decisions must still be those used by each preparer.
    for provenance, pairs in [
        (features["provenance"], {"rules_sha256":"config/geometry_rules.json", "policy_sha256":"config/data_usage.json", "manual_queue_sha256":"data/manual/review_queue.json", "generator_sha256":"tools/prepare_features.py", "coordinate_module_sha256":"tools/coordinate_system.py", "source_sha256":features["provenance"]["source_file"], "overture_sha256":features["provenance"]["overture_file"]}),
        (heights["provenance"], {"height_rules_sha256":"config/height_rules.json", "decisions_sha256":"data/manual/height_review_decisions.json", "generator_sha256":"tools/prepare_heights.py", "official_evidence_sha256":"data/reports/g03_official_evidence.json"}),
        (walk["provenance"], {"rules_sha256":"config/movement_rules.json", "manual_sha256":"data/manual/movement_review.json", "generator_sha256":"tools/prepare_movement.py", "official_sha256":"data/reports/g04_official_route_evidence.json"})]:
        for key, path in pairs.items():
            if provenance.get(key) != digest(root / path):
                raise ValueError(f"Stale reviewed input: {path}; regenerate its G-stage first")
            hashes[path] = digest(root / path)
    preview = features["provenance"]["preview_artifact"]
    if preview["sha256"] != digest(root / preview["file"]):
        raise ValueError("G02 source preview changed")
    hashes[preview["file"]] = preview["sha256"]
    hashes["tools/prepare_world.py"] = digest(root / "tools/prepare_world.py")
    for owner, key, path in links:
        if owner.get(key) != hashes[path]:
            raise ValueError(f"Unverified/stale input: {path}")
    for path in paths:
        if path.startswith("data/reports/") and not docs[path].get("passed"):
            raise ValueError(f"Precondition did not pass: {path}")
    coords = features["coordinate_system"]
    for document in [heights, terrain, walk, drive]:
        if document["coordinate_system"] != coords:
            raise ValueError("G-stage coordinate contracts differ")
    region = docs["config/region.json"]
    if coords["origin_lon_lat"] != region["origin_lon_lat"] or coords["world_axes"] != region["world_axes"] or region["meters_per_world_unit"] != 1:
        raise ValueError("Coordinate contract differs")
    return docs, hashes


def polygons(geometry):
    if geometry.geom_type == "Polygon": return [geometry]
    if geometry.geom_type == "MultiPolygon": return list(geometry.geoms)
    raise ValueError(f"Expected polygonal geometry, got {geometry.geom_type}")


def mesh_polygon(geometry, bottom, top=None):
    """Godot clockwise faces: outward normal is NEGATIVE cross(edge1, edge2)."""
    if geometry.is_empty or not geometry.is_valid:
        raise ValueError("Empty/invalid geometry; no implicit repairs")
    if not math.isfinite(bottom) or (top is not None and (not math.isfinite(top) or top <= bottom)):
        raise ValueError("Invalid vertical span")
    geometry = orient_polygons(geometry)
    vertices, normals = [], []
    def triangle(points, normal):
        for point in points:
            vertices.extend(round(float(v), 6) for v in point)
            normals.extend(round(float(v), 9) for v in normal)
    cap_triangles = []
    for poly in polygons(geometry):
        for tri in constrained_delaunay_triangles(poly).geoms:
            points = list(tri.exterior.coords)[:3]
            signed = sum(points[i][0]*points[(i+1)%3][1]-points[(i+1)%3][0]*points[i][1] for i in range(3))
            if signed < 0: points.reverse()
            # XZ counterclockwise gives cross=-Y; Godot's front points +Y.
            cap_triangles.append(tri)
            triangle([(x, top if top is not None else bottom, z) for x,z in points], (0,1,0))
            if top is not None:
                triangle([(x,bottom,z) for x,z in reversed(points)], (0,-1,0))
        if top is not None:
            for ring in [poly.exterior, *poly.interiors]:
                coords = list(ring.coords)
                for (x1,z1),(x2,z2) in zip(coords,coords[1:]):
                    length = math.hypot(x2-x1,z2-z1)
                    if length <= 1e-9: raise ValueError("Zero-length wall edge")
                    normal = ((z2-z1)/length, 0, -(x2-x1)/length)
                    a,b,c,d = (x1,bottom,z1),(x1,top,z1),(x2,top,z2),(x2,bottom,z2)
                    triangle([a,c,b],normal)
                    triangle([a,d,c],normal)
    union = unary_union(cap_triangles)
    error = union.symmetric_difference(geometry).area
    total_area = sum(t.area for t in cap_triangles)
    if error > 1e-6 or abs(total_area - geometry.area) > 1e-6:
        raise ValueError(f"Triangulation changed holes/coverage: {error}")
    return {"vertices":vertices, "normals":normals,
            "topology":{"parts":len(polygons(geometry)), "holes":sum(len(p.interiors) for p in polygons(geometry)),
                        "footprint_area_m2":geometry.area, "cap_area_m2":total_area,
                        "coverage_error_m2":error, "cap_triangles":len(cap_triangles)},
            "bottom_y_m":bottom, "top_y_m":top}


def generate(root=ROOT, check_only=False):
    root = Path(root)
    docs, hashes = validate_inputs(root)
    display = docs["config/world_display.json"]
    features = docs["data/processed/features.json"]["features"]
    heights = {r["feature_id"]:r for r in docs["data/processed/heights.json"]["records"]}
    terrain = docs["data/processed/terrain.json"]
    ground = {r["feature_id"]:r for r in terrain["records"]}
    meshes, ledger, landmarks = [], [], []
    def emit(identifier, feature, role, material, geometry, y, top=None, extra=None):
        data = mesh_polygon(geometry, y, top)
        metadata = {"feature_id":feature["feature_id"] if feature else None,
                    "name":feature["source_tags"].get("name", "") if feature else "",
                    "source_refs":feature["source_refs"] if feature else [],
                    "runtime_permission":None,"collision_generated":False,
                    "ground_class":"temporary_support_plane_reference", **(extra or {})}
        meshes.append({"id":identifier,"role":role,"material":material,"metadata":metadata, **data})
        if metadata["name"] in display["label_names"]:
            centroid = geometry.centroid
            landmarks.append({"feature_id":feature["feature_id"],"name":metadata["name"],
                              "position":[centroid.x,(top if top is not None else y)+3,centroid.y]})
    plane = terrain["temporary_support_plane"]
    emit("temporary_support",None,"Ground","support",box(*plane["local_xz_extent"]),plane["ground_y_m"],
         extra={"assumption":"G03 engineering plane; not measured terrain or playable boundary"})
    for f in features:
        fid = f["feature_id"]; h = heights[fid]; t = ground[fid]; geom = shape(f["geometry"])
        reason = "source/reference role; no solid emission"
        if h["emit_coarse_body"]:
            if t["ground_y_m"] is None or f["source_kind"] != "building":
                raise ValueError(f"Invalid body selection {fid}")
            tags = f["source_tags"]
            material = "historic" if tags.get("historic") else "civic" if tags.get("building") == "civic" or tags.get("name") == "서울특별시청" else "building"
            emit(fid,f,"Buildings",material,geom,t["ground_y_m"]+h["min_height_m"],t["ground_y_m"]+h["height_m"],
                 {"height_class":h["height_class"],"height_assumption_id":h["assumption_id"],
                  "source_height_m":h["height_m"],"source_min_height_m":h["min_height_m"],
                  "component_evidence_ids":h["component_evidence_ids"]})
            reason = "G03 single coarse body"
        elif t["ground_y_m"] is None:
            reason = "held_ground_unresolved:" + ",".join(t["reasons"])
        elif f["source_kind"] == "land_area":
            tags = f["source_tags"]
            material = "sand" if tags.get("natural") == "sand" or tags.get("surface") == "sand" else "water" if tags.get("natural") == "water" else "grass" if tags.get("leisure") in ["park","garden"] or tags.get("landuse") in ["grass","forest","recreation_ground"] else "land"
            offset = display["surface_offsets_m"]["land"]+display["land_material_offsets_m"][material]
            emit(fid,f,"Ground",material,geom,t["ground_y_m"]+offset,
                 extra={"display_only_land_reference":True,"visual_offset_m":offset})
            reason = "land reference paint; no access granted"
        elif f["generation"]["role"] in ["boundary_line_candidate", "boundary_area_candidate"]:
            if h["height_m"] is None: raise ValueError(f"Barrier height missing {fid}")
            wall = geom.buffer(display["barrier_thickness_m"]/2,cap_style="flat",join_style="mitre") if geom.geom_type in ["LineString","MultiLineString"] else geom
            emit(fid,f,"Barriers","barrier",wall,t["ground_y_m"]+h["min_height_m"],t["ground_y_m"]+h["height_m"],
                 {"height_class":h["height_class"],"height_assumption_id":h["assumption_id"],
                  "thickness_assumption_id":display["barrier_thickness_assumption_id"]})
            reason = "separate display barrier; gates not opened"
        ledger.append({"feature_id":fid,"source_kind":f["source_kind"],"G02_role":f["generation"]["role"],"display_decision":reason})
    by_feature = {f["feature_id"]:f for f in features}
    candidates = {}
    for mode, name in [("walk","walkable_areas"),("drive","driveable_areas")]:
        for record in docs[f"data/processed/{name}.json"]["records"]:
            if record["runtime_permission"] is not None or record["runtime_surface_ready"]:
                raise ValueError("G04 candidate promoted into runtime permission")
            if record["candidate_surface_geometry"] is not None:
                if record["ground_y_m"] is None: raise ValueError("Candidate has unresolved ground")
                candidates.setdefault(record["feature_id"],{})[mode] = record
    for fid, modes in sorted(candidates.items()):
        mode = "drive" if "drive" in modes else "walk"
        r = modes[mode]
        emit(fid+":display_surface",by_feature[fid],"Routes",mode,shape(r["candidate_surface_geometry"]),
             r["ground_y_m"]+display["surface_offsets_m"][mode],extra={"candidate_modes":sorted(modes),
             "display_mode":mode,"width_class":r["width_class"],"width_assumption_id":r["assumption_id"],
             "runtime_surface_ready":False,"visual_offset_m":display["surface_offsets_m"][mode],
             "display_only_movement_candidate":True})
    world = {"schema_version":1,"task":"E03","coordinate_contract_sha256":hashes["config/region.json"],
             "coordinate_system":docs["data/processed/features.json"]["coordinate_system"],
             "provenance":{"inputs":[{"file":p,"sha256":s} for p,s in sorted(hashes.items())],
                           "generator_sha256":digest(root / "tools/prepare_world.py"),
                           "shapely_version":shapely.__version__,"geos_version":shapely.geos_version_string},
             "display":display,"meshes":meshes,"source_decisions":ledger,"landmarks":landmarks,
             "scope":{"collision":False,"walkability_verified":False,"physical_terrain_verified":False,
                      "playable_boundary":None,"spawn":None},
             "counts":{"meshes":len(meshes),"roles":dict(sorted(Counter(m["role"] for m in meshes).items())),
                       "triangles":sum(len(m["vertices"])//9 for m in meshes),
                       "building_height_classes":dict(sorted(Counter(m["metadata"]["height_class"] for m in meshes if m["role"]=="Buildings").items())),
                       "movement_feature_surfaces":len(candidates),"dual_mode_features":sum(len(v)==2 for v in candidates.values())},
             "known_overlaps":{"walk_obstacle_pairs":len(docs["data/processed/walkable_areas.json"]["obstacle_conflicts"]),
                               "drive_obstacle_pairs":len(docs["data/processed/driveable_areas.json"]["obstacle_conflicts"]),
                               "policy":"retained, no automatic clipping/access approval"}}
    content = encode(world); output = root / WORLD
    if check_only:
        if not output.is_file() or output.read_bytes()!=content:
            raise ValueError("World triangles stale/missing; run prepare_world.py")
    else:
        output.parent.mkdir(parents=True,exist_ok=True); output.write_bytes(content)
    return {"file":WORLD,"bytes":len(content),"sha256":hashlib.sha256(content).hexdigest(),"counts":world["counts"],"check_only":check_only}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    print(json.dumps(generate(check_only=args.check),ensure_ascii=False,indent=2))

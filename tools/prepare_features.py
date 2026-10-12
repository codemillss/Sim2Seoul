#!/usr/bin/env python3
"""G02: preserve source geometry, build local XZ shapes and conservative roles."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import html
import json
from pathlib import Path

import osmium
from shapely import STRtree, orient_polygons, transform, union_all
from shapely.geometry import mapping, shape

from coordinate_system import CoordinateSystem, ROOT


def load(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def canonical(identity):
    kind, number = identity.split("/")
    return f"osm:{ {'n': 'node', 'w': 'way', 'r': 'relation'}[kind]}:{number}"


class SourceIndex(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.objects = {}

    def node(self, obj):
        self.objects[f"n/{obj.id}"] = {"tags": dict(obj.tags)}

    def way(self, obj):
        self.objects[f"w/{obj.id}"] = {"tags": dict(obj.tags), "node_ids": [n.ref for n in obj.nodes]}

    def relation(self, obj):
        self.objects[f"r/{obj.id}"] = {"tags": dict(obj.tags),
            "members": [{"object_id": f"{m.type}/{m.ref}", "role": m.role} for m in obj.members]}


def local_geometry(geometry, system):
    projected = transform(geometry, system.forward.transform, interleaved=False)
    east, north = system.origin_east_north
    return orient_polygons(transform(projected, lambda x, y: (x - east, -(y - north)), interleaved=False))


def topology_stats(geom):
    polygons = list(geom.geoms) if geom.geom_type == "MultiPolygon" else [geom] if geom.geom_type == "Polygon" else []
    return {"polygon_count": len(polygons), "hole_count": sum(len(p.interiors) for p in polygons),
        "area_m2": geom.area, "length_m": geom.length}


def intersections(left_ids, right_ids, geometries, min_area, same_set=False):
    tree = STRtree([geometries[i] for i in right_ids])
    pairs = []
    for i in left_ids:
        for k in sorted(tree.query(geometries[i], predicate="intersects").tolist()):
            j = right_ids[k]
            if same_set and i >= j:
                continue
            area = geometries[i].intersection(geometries[j]).area
            if area > min_area:
                pairs.append({"a": i, "b": j, "overlap_area_m2": area,
                    "fraction_of_a": area / geometries[i].area,
                    "fraction_of_b": area / geometries[j].area})
    return sorted(pairs, key=lambda p: (p["a"], p["b"]))


def prepare():
    system = CoordinateSystem()
    rules_path = ROOT / "config/geometry_rules.json"
    policy_path = ROOT / "config/data_usage.json"
    queue_path = ROOT / "data/manual/review_queue.json"
    rules, policy = load(rules_path), load(policy_path)
    manifest = load(ROOT / "data/reports/extract_manifest.json")
    audit = load(ROOT / "data/reports/osm_audit.json")
    coordinate = load(ROOT / "data/reports/coordinate_check.json")
    source = ROOT / manifest["extract_file"]
    preview_record = audit["preview_artifact"]
    preview = ROOT / preview_record["file"]
    supplemental = policy["supplemental_buildings"]
    overture = ROOT / supplemental["file"]
    if not (sha(source) == manifest["extract_sha256"] == policy["base_geometry"]["sha256"] == audit["extract_sha256"]
            and source.stat().st_size == manifest["extract_bytes"]
            and sha(preview) == preview_record["sha256"] and preview.stat().st_size == preview_record["bytes"]
            and sha(system.config_path) == preview_record["config_sha256"] == coordinate["provenance"]["config_sha256"]
            and coordinate["passed"] and coordinate["provenance"]["source_sha256"] == manifest["extract_sha256"]
            and sha(overture) == supplemental["sha256"]):
        raise ValueError("G02 source/preview/config/G01/supplemental provenance mismatch")
    for name, digest in coordinate["provenance"]["generators"].items():
        if sha(ROOT / name) != digest:
            raise ValueError("G01 generator changed; rerun coordinate checks")
    if (rules["coordinate_contract_version"] != 1 or rules["clip_to_investigation_bbox"]
            or rules["repair_invalid_geometry"] or rules["schema_version"] != 1
            or rules["polygon_winding_in_local_xz"] != {"outer": "counterclockwise", "holes": "clockwise"}):
        raise ValueError("Unsupported geometry rules; review and implement changes explicitly")
    raw = SourceIndex()
    raw.apply_file(source)
    features, geoms, raw_to_features = {}, {}, {}
    invalid, tag_mismatches, restored_relation_types = [], [], []
    for original in sorted(load(preview)["features"], key=lambda f: f["id"]):
        props = original["properties"]
        identity, source_kind, tags = props["osm_id"], props["feature_kind"], props["tags"]
        if identity not in raw.objects:
            raise ValueError(f"Missing source object: {identity}")
        obj = raw.objects[identity]
        if tags != obj["tags"]:
            if identity.startswith("r/") and obj["tags"].get("type") == "multipolygon" and tags == {
                    k: v for k, v in obj["tags"].items() if k != "type"}:
                restored_relation_types.append(identity)
            else:
                tag_mismatches.append(identity)
        tags = obj["tags"]
        fid = canonical(identity) + ":" + source_kind
        if fid in features:
            raise ValueError(f"Duplicate feature ID: {fid}")
        geom = local_geometry(shape(original["geometry"]), system)
        role = {"building": "primary_footprint", "building_part": "component_reference",
            "highway_line": "centreline_candidate", "highway_area": "tagged_surface_candidate",
            "barrier": "boundary_line_candidate", "barrier_area": "boundary_area_candidate",
            "gate_node": "gate_location_candidate", "land_area": "land_reference"}[source_kind]
        if source_kind == "building" and tags.get("building") == "roof":
            role = "roof_reference"
        if geom.is_empty or not geom.is_valid:
            invalid.append(fid)
            role = "invalid_geometry_hold"
        roads = source_kind.startswith("highway")
        normalized_kind = ("footpath" if tags.get("highway") in {"footway", "pedestrian", "path", "steps"}
                           else "road") if roads else source_kind.replace("gate_node", "gate").replace("barrier_area", "barrier")
        record = {"feature_id": fid, "entity_id": canonical(identity), "source_kind": source_kind,
            "kind": normalized_kind, "source_refs": [{"provider": "OpenStreetMap via Geofabrik",
                "object_id": identity, "file": manifest["extract_file"], "snapshot_sha256": manifest["extract_sha256"]}],
            "source_tags": tags, "source_geometry": {"crs": "EPSG:4326", "axis_order": ["longitude", "latitude"],
                "geometry": original["geometry"]},
            "source_topology": {k: obj[k] for k in ("node_ids", "members") if k in obj},
            "geometry": {"coordinate_space": "local_xz", "axis_order": ["x", "z"], "unit": "metre", **mapping(geom)},
            "quality": {"horizontal": "derived_from_source_geometry", "independent_position_accuracy": "unverified",
                "height": "pending_G03", "ground": "pending_G03"},
            "access": {"source_tags": {k: tags[k] for k in ("access", "foot", "vehicle", "motor_vehicle", "bicycle", "opening_hours") if k in tags},
                "game_permission": None, "decision_task": "G04"},
            "override_ref": None, "generation": {"role": role, "reason": "source semantic role; no 3D emission in G02"},
            "building_group_refs": [], "spatial_parent_candidates": []}
        if source_kind in ("building", "building_part"):
            record["building"] = {"height_m": None, "min_height_m": None, "height_source": "pending_G03",
                "height_raw": tags.get("height"), "levels_raw": tags.get("building:levels"),
                "min_height_raw": tags.get("min_height"), "roof_tags": {k: v for k, v in tags.items() if k.startswith("roof:")},
                "height_assumption_id": None}
        if roads:
            record["road"] = {"representation": "source_area" if source_kind == "highway_area" else "source_centreline",
                "width_m": None, "width_source": "pending_G04", "width_raw": tags.get("width"),
                "lanes_raw": tags.get("lanes"), "oneway": tags.get("oneway"), "layer_raw": tags.get("layer"),
                "bridge": tags.get("bridge"), "tunnel": tags.get("tunnel"), "pedestrian_allowed": None}
        features[fid], geoms[fid] = record, geom
        raw_to_features.setdefault(identity, []).append(fid)
    if invalid or tag_mismatches:
        raise ValueError(f"Source geometry/tag review required: invalid={invalid}, tags={tag_mismatches}")

    threshold = rules["overlap_report_min_area_m2"]
    buildings = [i for i, f in features.items() if f["source_kind"] == "building"]
    parts = [i for i, f in features.items() if f["source_kind"] == "building_part"]
    groups = []
    for rid, obj in sorted(raw.objects.items()):
        if obj["tags"].get("type") != "building":
            continue
        members = obj["members"]
        outlines = [fid for m in members if m["role"] == "outline" for fid in raw_to_features.get(m["object_id"], []) if fid in buildings]
        member_parts = [fid for m in members if m["role"] == "part" for fid in raw_to_features.get(m["object_id"], []) if fid in parts]
        if not outlines and not member_parts:
            continue
        gid = canonical(rid)
        group = {"group_id": gid, "source_members": members, "outline_feature_ids": sorted(outlines),
            "part_feature_ids": sorted(member_parts), "missing_preview_members": [m for m in members
                if m["role"] in ("outline", "part") and m["object_id"] not in raw_to_features],
            "strategy": "coarse outline OR detailed parts; never both full volumes"}
        for fid in outlines + member_parts:
            features[fid]["building_group_refs"].append(gid)
        if outlines and member_parts:
            outline_union = union_all([geoms[i] for i in outlines])
            part_union = union_all([geoms[i] for i in member_parts])
            group["part_union_outside_outline_m2"] = part_union.difference(outline_union).area
            group["outline_not_covered_by_parts_m2"] = outline_union.difference(part_union).area
        groups.append(group)
    part_pairs = intersections(parts, buildings, geoms, threshold)
    for pair in part_pairs:
        features[pair["a"]]["spatial_parent_candidates"].append({"feature_id": pair["b"],
            "fraction_of_part": pair["fraction_of_a"], "overlap_area_m2": pair["overlap_area_m2"],
            "status": "spatial_candidate_not_source_parent_assertion"})

    exact_duplicates = []
    by_kind = {}
    for fid, f in features.items():
        by_kind.setdefault(f["source_kind"], []).append(fid)
    for kind, ids in sorted(by_kind.items()):
        tree = STRtree([geoms[i] for i in ids])
        for n, fid in enumerate(ids):
            for k in sorted(tree.query(geoms[fid], predicate="intersects").tolist()):
                other = ids[k]
                if k <= n or not geoms[fid].equals(geoms[other]) or features[fid]["source_tags"] != features[other]["source_tags"]:
                    continue
                exact_duplicates.append({"primary": fid, "alias": other, "source_kind": kind})
                features[other]["generation"] = {"role": "exact_geometry_alias", "primary_feature_id": fid,
                    "reason": "same-kind topological equality AND identical source tags; source record retained"}
    overlaps = intersections(buildings, buildings, geoms, threshold, same_set=True)
    body_conflicts = []
    for pair in overlaps:
        a, b = pair["a"], pair["b"]
        if features[a]["generation"]["role"] == "roof_reference" or features[b]["generation"]["role"] == "roof_reference":
            pair["classification"] = "roof_and_body_or_roof_overlap; references retained"
        elif features[a]["generation"]["role"] == "exact_geometry_alias" or features[b]["generation"]["role"] == "exact_geometry_alias":
            pair["classification"] = "exact_alias; one primary representation"
        else:
            pair["classification"] = "unexplained_body_overlap; both held from coarse emission"
            body_conflicts.append(pair)
    for pair in body_conflicts:
        for fid in (pair["a"], pair["b"]):
            features[fid]["generation"] = {"role": "body_overlap_hold", "reason": "unexplained non-roof overlap; G03/manual review before emission"}
    outer_duplicates = []
    for fid, f in features.items():
        if f["source_kind"] not in ("building", "building_part") or not f["source_refs"][0]["object_id"].startswith("r/"):
            continue
        for member in f["source_topology"].get("members", []):
            if member["role"] in ("outer", ""):
                for child in raw_to_features.get(member["object_id"], []):
                    if features[child]["source_kind"] == f["source_kind"]:
                        outer_duplicates.append({"relation_feature": fid, "member_feature": child})
                        features[child]["generation"] = {"role": "relation_member_reference", "reason": "represented in multipolygon parent; not a second independent body"}
    barrier_aliases = []
    for fid, f in features.items():
        if f["source_kind"] == "barrier_area":
            lines = [i for i in raw_to_features[f["source_refs"][0]["object_id"]] if features[i]["source_kind"] == "barrier"]
            if lines:
                f["generation"] = {"role": "boundary_area_reference", "reason": "same object has primary barrier line; no double wall"}
                barrier_aliases.append({"area": fid, "primary_lines": lines})

    ov_features = {f["id"]: f for f in load(overture)["features"]}
    candidates = []
    tree = STRtree([geoms[i] for i in buildings])
    for oid in sorted(supplemental["candidate_ids_not_automatically_approved"]):
        f = ov_features[oid]
        geom = local_geometry(shape(f["geometry"]), system)
        candidates.append({"overture_id": oid, "source_refs": f["properties"]["sources"],
            "geometry_valid": bool(geom.is_valid and not geom.is_empty), "area_m2": geom.area,
            "overlapping_osm_buildings": [{"feature_id": buildings[k],
                "intersection_area_m2": geom.intersection(geoms[buildings[k]]).area}
                for k in sorted(tree.query(geom, predicate="intersects").tolist())],
            "status": "held_not_in_base_feature_set", "reason": "current presence/shape/part identity lacks independent confirmation"})
    diagnostics = {"building_groups": groups, "part_building_overlap_pairs": part_pairs,
        "part_part_overlap_pairs": intersections(parts, parts, geoms, threshold, same_set=True),
        "parts_without_spatial_building_overlap": [i for i in parts if not features[i]["spatial_parent_candidates"]],
        "building_overlap_pairs": overlaps, "unexplained_body_overlap_pairs": body_conflicts,
        "exact_same_kind_duplicates": exact_duplicates, "relation_outer_member_duplicates": outer_duplicates,
        "barrier_same_entity_representations": barrier_aliases, "overture_candidates": candidates,
        "invalid_or_empty_geometry": invalid, "automatic_repairs": [], "bbox_clipped_features": [],
        "relation_type_restored_from_raw": restored_relation_types,
        "non_osm_or_official_comparison": "22 Overture candidates compared spatially; domestic authoritative building originals unreceived",
        "part_part_overlap_scope": "horizontal overlap can represent roof/wall/column stories; evaluate height/min_height in G03"}
    provenance = {"source_file": manifest["extract_file"], "source_sha256": sha(source),
        "preview_artifact": preview_record, "coordinate_report_sha256": sha(ROOT / "data/reports/coordinate_check.json"),
        "config_sha256": sha(system.config_path), "rules_sha256": sha(rules_path), "policy_sha256": sha(policy_path),
        "manual_queue_sha256": sha(queue_path), "overture_file": supplemental["file"], "overture_sha256": sha(overture),
        "generator_sha256": sha(Path(__file__)), "coordinate_module_sha256": sha(ROOT / "tools/coordinate_system.py")}
    return {"schema_version": 1, "format": "Sim2Seoul local-XZ feature document; NOT RFC7946 GeoJSON",
        "task_id": "G02", "provenance": provenance, "coordinate_system": {"projected_crs": system.config["metric_crs"],
            "origin_lon_lat": list(system.origin_lon_lat), "origin_projected_east_north_m": list(system.origin_east_north),
            "geometry_axis_order": ["x", "z"], "world_axes": system.config["world_axes"], "unit": "metre",
            "vertical_assignment": "absent; not synthetic ground or sea level"},
        "geometry_rules": rules, "features": list(features.values()), "diagnostics": diagnostics,
        "coarse_body_feature_ids": [i for i, f in features.items() if f["generation"]["role"] == "primary_footprint"],
        "kind_counts": dict(sorted(Counter(f["source_kind"] for f in features.values()).items())),
        "generation_role_counts": dict(sorted(Counter(f["generation"]["role"] for f in features.values()).items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="data/processed/features.json")
    parser.add_argument("--map", help="Optional SVG of three landmark topology checks")
    args = parser.parse_args()
    result = prepare()
    save(ROOT / args.output, result)
    if args.map:
        render_review(result, ROOT / args.map)
    print(json.dumps({"feature_count": len(result["features"]), "roles": result["generation_role_counts"]}, indent=2))


def render_review(document, output):
    records = {f["feature_id"]: f for f in document["features"]}
    geometries = {fid: shape(f["geometry"]) for fid, f in records.items()}
    panels = [("석조전 · 부모와 부분", "r/19357693", None),
              ("서울도서관 · 부모와 부분", "r/10757525", None),
              ("중화전 · 마당 내부 구멍", "w/181574577", "r/10754689")]
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1320" height="650" viewBox="0 0 1320 650">',
        '<rect width="1320" height="650" fill="#f7f7f3"/>',
        '<g font-family="sans-serif" fill="#23313b">',
        '<text x="30" y="35" font-size="22">G02 · 원본 도형 관계 검사 — 높이·통행·실제 외형 검증 전</text>']
    for index, (title, identity, courtyard_identity) in enumerate(panels):
        parent_id = canonical(identity) + ":building"
        parent = geometries[parent_id]
        context_id = canonical(courtyard_identity) + ":highway_area" if courtyard_identity else parent_id
        context = geometries[context_id]
        west, north, east, south = context.bounds
        scale = min(350 / (east - west), 380 / (south - north))
        left, top = 40 + 430 * index, 100
        def xy(x, z):
            return left + 20 + (x - west) * scale, top + 40 + (z - north) * scale
        def path(geometry):
            commands = []
            polygons = list(geometry.geoms) if geometry.geom_type == "MultiPolygon" else [geometry]
            for polygon in polygons:
                for ring in [polygon.exterior, *polygon.interiors]:
                    commands.append("M" + " L".join(f"{x:.3f},{z:.3f}" for x, z in [xy(*p) for p in ring.coords]) + " Z")
            return " ".join(commands)
        svg.append(f'<rect x="{left}" y="60" width="405" height="500" rx="8" fill="white" stroke="#d7dce0"/>')
        svg.append(f'<text x="{left+15}" y="89" font-size="17">{html.escape(title)}</text>')
        svg.append(f'<clipPath id="panel{index}"><rect x="{left+5}" y="105" width="395" height="415"/></clipPath><g clip-path="url(#panel{index})" fill-rule="evenodd">')
        if courtyard_identity:
            svg.append(f'<path d="{path(context)}" fill="#d7edce" stroke="#789d6b" stroke-width="1"/>')
        svg.append(f'<path d="{path(parent)}" fill="#d7e7f560" stroke="#3e78a2" stroke-width="2"/>')
        for fid, record in records.items():
            if record["source_kind"] == "building_part" and geometries[fid].intersects(parent):
                svg.append(f'<path d="{path(geometries[fid])}" fill="none" stroke="#467d54" stroke-width="0.8"/>')
            elif record["source_tags"].get("building") == "roof" and geometries[fid].intersects(parent):
                svg.append(f'<path d="{path(geometries[fid])}" fill="none" stroke="#d28928" stroke-width="1.3"/>')
        svg.append('</g>')
        bar_y = 530
        svg.append(f'<path d="M{left+20},{bar_y} h{10*scale:.3f}" stroke="#23313b" stroke-width="3"/><text x="{left+20}" y="550" font-size="13">10m · 격자 북 ↑</text>')
    svg.extend(['<text x="30" y="590" font-size="14">파랑: 부모 외곽 · 초록 선: 부분 후보 · 주황 선: building=roof · 연두 면: 원본 마당(구멍 유지)</text>',
        '<text x="30" y="615" font-size="13">부모 전체와 부분을 동시에 독립 건물로 생성하지 않음 · 도형만 표시, 지면/높이/문 개구부 미배정</text>',
        '<text x="30" y="638" font-size="12">© OpenStreetMap contributors · EPSG:32652 → 고정 원점 local XZ · 조사 도형, 플레이 경계 아님</text>',
        '</g></svg>'])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(svg) + "\n")


if __name__ == "__main__":
    main()

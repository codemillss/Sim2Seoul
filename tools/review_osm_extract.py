#!/usr/bin/env python3
"""D02: verify an existing regional extract against its pinned country source.

Read-only source audit. Checks full members and country multipolygon coverage;
does not infer real-world completeness or create game assets.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

import osmium
from shapely import wkb
from shapely.geometry import LineString, Point, Polygon, box

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "data/reports/extract_manifest.json").read_text())
SOURCE = ROOT / MANIFEST["source_file"]
EXTRACT = ROOT / MANIFEST["extract_file"]
WINDOW = box(*MANIFEST["bbox_west_south_east_north"])
KEYS = ("building", "building:part", "historic", "leisure", "landuse", "barrier", "natural", "highway")


def sha256(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def snapshot(obj):
    kind = obj.type_str()
    record = {"tags": dict(obj.tags), "version": obj.version}
    if kind == "n":
        record["coordinates"] = [obj.lon, obj.lat] if obj.location.valid() else None
    elif kind == "w":
        record["nodes"] = [n.ref for n in obj.nodes]
    elif kind == "r":
        record["members"] = [[m.type, m.ref, m.role] for m in obj.members]
    return kind, obj.id, record


def area_records(path, relation_ids=None):
    factory = osmium.geom.WKBFactory()
    processor = osmium.FileProcessor(path)
    if relation_ids is None:
        processor.with_areas()
    else:
        processor.with_areas(osmium.filter.IdFilter(relation_ids))
    processor.with_filter(osmium.filter.EntityFilter(osmium.osm.AREA))
    if relation_ids is not None:
        processor.with_filter(osmium.filter.IdFilter([2 * ident + 1 for ident in relation_ids]))
    records, errors = {}, []
    for area in processor:
        key = ("w" if area.from_way() else "r", area.orig_id())
        try:
            geom = wkb.loads(factory.create_multipolygon(area), hex=True)
            records[key] = {"geometry": geom, "tags": dict(area.tags)}
        except Exception as exc:
            errors.append({"osm_id": f"{key[0]}/{key[1]}", "error": str(exc)})
    return records, errors


def relevant_relation(record):
    tags = record["tags"]
    return tags.get("type") in {"multipolygon", "building", "site"} and (
        tags.get("type") == "building" or any(key in tags for key in KEYS))


def main():
    for path, purpose in ((EXTRACT, "regional map"), (SOURCE, "optional country source for full D02 comparison")):
        if not path.is_file():
            raise SystemExit(f"Missing {purpose}: {path.relative_to(ROOT)}. "
                "Use the regional audit to continue development; see docs/CROSS_MAC.md for the optional full review.")
    print("D02: parsing existing extract and checking references", flush=True)
    objects = {"n": {}, "w": {}, "r": {}}
    duplicates = []
    for obj in osmium.FileProcessor(EXTRACT):
        kind, ident, record = snapshot(obj)
        if ident in objects[kind]:
            duplicates.append(f"{kind}/{ident}")
        objects[kind][ident] = record
    missing = []
    invalid_locations = []
    inside_nodes = set()
    for ident, node in objects["n"].items():
        coords = node["coordinates"]
        if coords is None:
            invalid_locations.append(ident)
        elif WINDOW.covers(Point(*coords)):
            inside_nodes.add(ident)
    for ident, way in objects["w"].items():
        missing.extend({"owner": f"w/{ident}", "missing": f"n/{ref}"}
                       for ref in way["nodes"] if ref not in objects["n"])
    for ident, relation in objects["r"].items():
        missing.extend({"owner": f"r/{ident}", "missing": f"{kind}/{ref}"}
                       for kind, ref, role in relation["members"] if ref not in objects[kind])

    intersecting_ways, boundary_crossings = set(), []
    for ident, way in objects["w"].items():
        coords = [objects["n"].get(ref, {}).get("coordinates") for ref in way["nodes"]]
        if len(coords) < 2 or any(p is None for p in coords):
            continue
        closed = way["nodes"][0] == way["nodes"][-1] and len(coords) >= 4
        geom = Polygon(coords) if closed else LineString(coords)
        if geom.intersects(WINDOW):
            intersecting_ways.add(ident)
            if not WINDOW.covers(geom):
                boundary_crossings.append({"osm_id": f"w/{ident}", "node_count": len(coords),
                    "outside_bbox_nodes": sum(ref not in inside_nodes for ref in way["nodes"]),
                    "bounds": list(geom.bounds), "tags": way["tags"]})

    print("D02: comparing selected objects with full country source", flush=True)
    wanted = set().union(*(set(records) for records in objects.values()))
    seen = {"n": set(), "w": set(), "r": set()}
    differences = []
    for obj in osmium.FileProcessor(SOURCE).with_filter(osmium.filter.IdFilter(wanted)):
        kind, ident, record = snapshot(obj)
        if ident in objects[kind]:
            seen[kind].add(ident)
            if record != objects[kind][ident]:
                differences.append(f"{kind}/{ident}")
    source_absences = [f"{kind}/{ident}" for kind in objects for ident in set(objects[kind]) - seen[kind]]

    print("D02: collecting country relations and assembling regional areas", flush=True)
    country_relations = {}
    for obj in osmium.FileProcessor(SOURCE, entities=osmium.osm.RELATION):
        kind, ident, record = snapshot(obj)
        if relevant_relation(record):
            country_relations[ident] = record
    local_areas, local_area_errors = area_records(EXTRACT)
    expected_local_areas = set()
    for ident, record in objects["r"].items():
        if record["tags"].get("type") == "multipolygon":
            expected_local_areas.add(("r", ident))
    for ident, record in objects["w"].items():
        tags, nodes = record["tags"], record["nodes"]
        if len(nodes) >= 4 and nodes[0] == nodes[-1] and (
            "building" in tags or "building:part" in tags or tags.get("area") == "yes"
            or any(k in tags for k in ("leisure", "landuse", "historic"))):
            expected_local_areas.add(("w", ident))
    unassembled_local = [f"{k}/{i}" for k, i in sorted(expected_local_areas - local_areas.keys())]
    invalid_local_areas = [f"{k}/{i}" for (k, i), item in local_areas.items()
                           if not item["geometry"].is_valid]

    multipolygons = {ident for ident, record in country_relations.items()
                     if record["tags"].get("type") == "multipolygon"}
    print(f"D02: checking {len(multipolygons)} country multipolygons for intersection/enclosure", flush=True)
    country_areas, country_area_errors = area_records(SOURCE, multipolygons)
    intersecting_relations = {ident for (kind, ident), item in country_areas.items()
                             if item["geometry"].intersects(WINDOW)}
    expected_relations = set(intersecting_relations)
    changed = True
    while changed:
        changed = False
        for ident, record in country_relations.items():
            if ident not in expected_relations and any(
                (kind == "n" and ref in inside_nodes) or (kind == "w" and ref in intersecting_ways)
                or (kind == "r" and ref in expected_relations) for kind, ref, role in record["members"]):
                expected_relations.add(ident)
                changed = True
    missing_relevant_relations = sorted(expected_relations - objects["r"].keys())
    unassembled_country = sorted(multipolygons - {ident for kind, ident in country_areas})
    unassembled_with_local_members = [ident for ident in unassembled_country if ident in expected_relations]
    landmark_ids = {"대한문": ("w", 377289797), "중화전": ("w", 181574577),
                    "석조전": ("r", 19357693), "돈덕전": ("w", 517072312),
                    "서울특별시청": ("w", 198561926), "서울도서관": ("r", 10757525),
                    "서울광장": ("w", 370019676)}
    landmarks = []
    for name, key in landmark_ids.items():
        item = local_areas.get(key)
        record = objects[key[0]].get(key[1])
        geom = item["geometry"] if item else None
        landmarks.append({"name": name, "osm_id": f"{key[0]}/{key[1]}", "object_present": record is not None,
            "geometry_assembled": geom is not None, "geometry_valid": geom.is_valid if geom is not None else None,
            "inside_investigation_bbox": WINDOW.covers(geom) if geom is not None else None,
            "polygon_parts": len(geom.geoms) if geom is not None else None,
            "inner_rings": sum(len(p.interiors) for p in geom.geoms) if geom is not None else None,
            "member_count": len(record.get("members", record.get("nodes", []))) if record else 0})

    recovered = []
    for ident in MANIFEST.get("repair", {}).get("added_relation_ids", []):
        item = local_areas.get(("r", ident))
        geom = item["geometry"] if item else None
        recovered.append({"osm_id": f"r/{ident}", "geometry_assembled": geom is not None,
            "highway": item["tags"].get("highway") if item else None,
            "geometry_valid": bool(geom.is_valid) if geom is not None else False,
            "inner_rings": sum(len(p.interiors) for p in geom.geoms) if geom is not None else None})
    courtyard_hole = None
    if recovered:
        courtyard = local_areas.get(("r", 10754689))
        hall = local_areas.get(("w", 181574577))
        overlap = courtyard["geometry"].intersection(hall["geometry"]).area if courtyard and hall else None
        courtyard_hole = {"courtyard_id": "r/10754689", "building_id": "w/181574577",
            "overlap_square_degrees": overlap, "passed": overlap is not None and overlap < 1e-14,
            "interpretation": "Pedestrian area excludes Junghwajeon footprint; game ground/collision remains untested."}

    checks = {
        "extract_sha256_matches_manifest": sha256(EXTRACT) == MANIFEST["extract_sha256"],
        "source_sha256_matches_manifest": sha256(SOURCE) == MANIFEST["source_sha256"],
        "no_duplicate_object_ids": not duplicates,
        "no_unresolved_references": not missing,
        "node_locations_valid": not invalid_locations,
        "all_extract_objects_identical_to_country_source": not differences and not source_absences,
        "all_expected_local_areas_assembled": not unassembled_local and not local_area_errors,
        "local_area_geometries_valid": not invalid_local_areas,
        "no_missing_relevant_country_relations": not missing_relevant_relations,
        "no_unassembled_local_country_multipolygons": not unassembled_with_local_members,
        "all_required_landmarks_present_with_valid_geometry": all(x["object_present"] and x["geometry_assembled"] and x["geometry_valid"] for x in landmarks)
    }
    if recovered:
        checks["recovered_pedestrian_areas_present_and_valid"] = all(
            x["geometry_assembled"] and x["geometry_valid"] and x["highway"] == "pedestrian" for x in recovered)
        checks["junghwajeon_courtyard_hole_preserved"] = courtyard_hole["passed"]
    report = {
        "task_id": "D02", "verified_at_utc": datetime.now(timezone.utc).isoformat(), "passed": all(checks.values()),
        "scope": "structural_extract_integrity_and_country_multipolygon_coverage_not_real_world_accuracy",
        "checks": checks, "source_file": MANIFEST["source_file"], "extract_file": MANIFEST["extract_file"],
        "bbox_west_south_east_north": MANIFEST["bbox_west_south_east_north"], "bbox_role": "investigation_not_playable_boundary",
        "object_counts": {k: len(v) for k, v in objects.items()}, "unresolved_references": missing,
        "duplicates": duplicates, "source_object_differences": differences, "objects_absent_from_country_source": source_absences,
        "bbox_intersecting_way_count": len(intersecting_ways), "boundary_crossing_way_count": len(boundary_crossings),
        "boundary_crossing_ways": boundary_crossings, "expected_local_area_count": len(expected_local_areas),
        "assembled_local_area_count": len(local_areas), "unassembled_local_areas": unassembled_local,
        "invalid_local_areas": invalid_local_areas, "local_area_errors": local_area_errors,
        "country_relevant_relation_count": len(country_relations), "country_relevant_multipolygon_count": len(multipolygons),
        "country_assembled_multipolygon_count": len(country_areas), "country_multipolygons_intersecting_bbox": sorted(intersecting_relations),
        "expected_local_relation_count_after_parent_closure": len(expected_relations),
        "missing_relevant_relations": missing_relevant_relations,
        "unassembled_country_multipolygon_count": len(unassembled_country),
        "unassembled_country_multipolygons_with_local_members": unassembled_with_local_members,
        "country_area_errors": country_area_errors, "landmarks": landmarks,
        "recovered_pedestrian_areas": recovered, "recovered_pedestrian_area_count": len(recovered),
        "previous_failed_review": MANIFEST.get("repair", {}).get("source_review"),
        "courtyard_hole_check": courtyard_hole,
        "reextract_required": bool(missing_relevant_relations or source_absences or differences or missing),
        "limitations": ["Comparison uses the same pinned OSM source, not independent survey truth.",
            "Country multipolygons that cannot assemble and have no detected local members cannot be located reliably.",
            "Administrative/route relations outside the stated local spatial semantics are intentionally excluded.",
            "Height correctness, geometry deduplication, terrain and actual walkable access remain later work."]
    }
    target = ROOT / "data/reports/d02_extract_review.json"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("passed", "checks", "object_counts", "boundary_crossing_way_count", "missing_relevant_relations", "unassembled_local_areas", "reextract_required")}, ensure_ascii=False), flush=True)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

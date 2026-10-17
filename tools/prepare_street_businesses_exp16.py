#!/usr/bin/env python3
"""Add source-qualified ground convenience facades; never alter the four EXP14 rows.

Run with .venv-data/bin/python tools/prepare_street_businesses_exp16.py.
Uses only the retained regional PBF and prepared source geometry, offline.
The checks below certify authored 2D placement, not occupancy or physical runtime.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

import osmium
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

from coordinate_system import CoordinateSystem

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "game/assets/authored/street_businesses.json"
PBF = ROOT / "data/raw/deoksugung_cityhall-v2.osm.pbf"
GENERATION = "EXP16-regional-convenience-v1"


def load(relative):
    return json.loads((ROOT / relative).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ConvenienceNodes(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.rows = []

    def node(self, node):
        tags = dict(node.tags)
        if tags.get("shop") == "convenience" and node.location.valid():
            self.rows.append({"id": node.id, "lon": node.location.lon,
                              "lat": node.location.lat, "tags": tags})


def rejected_floor(tags):
    """OSM level 0 and Korean addr:floor 1 may be ground; unknown stays unknown."""
    if tags.get("tunnel", "no") not in ("no", "false", "0"):
        return "explicit_tunnel"
    if tags.get("location") in ("underground", "indoor") or tags.get("indoor") in ("yes", "room"):
        return "explicit_indoor_or_underground"
    if tags.get("railway") or tags.get("public_transport"):
        return "station_infrastructure"
    title = " ".join(tags.get(key, "") for key in ("name", "name:ko", "branch", "addr:unit"))
    if re.search(r"역\s*(?:\d+호선|내|지하)|지하|B\s*\d|basement|concourse", title, re.I):
        return "explicit_basement_or_station_unit"
    if "level" in tags and tags["level"] not in ("0", "0.0"):
        return "explicit_non_ground_osm_level"
    if "layer" in tags and tags["layer"] not in ("0", "0.0"):
        return "explicit_non_ground_layer"
    if "addr:floor" in tags and tags["addr:floor"].strip() not in ("1", "1F", "1층", "0", "ground"):
        return "explicit_non_ground_address_floor"
    unit = tags.get("addr:unit", "")
    if re.search(r"[2-9]\d*\s*층|\b[2-9]\d*F\b", unit, re.I):
        return "explicit_upper_floor_unit"
    return ""


def style_for(tags):
    label = " ".join(tags.get(k, "") for k in ("name", "name:en", "brand", "brand:en")).lower()
    if "gs25" in label:
        return "gs25"
    if "cu" in label:
        return "cu"
    if "이마트" in label or "emart" in label:
        return "emart24"
    if "세븐" in label or "7-eleven" in label:
        return "seven_eleven"
    return "convenience"


def fit_facade(poi, building_id, polygon, building_parts, forbidden, doors, streets, world_record):
    """Try exact source-edge spans; protect full authored display and approach strip."""
    candidates = []
    point = poi["point"]
    parts = list(polygon.geoms) if polygon.geom_type == "MultiPolygon" else [polygon]
    for part_index, part in enumerate(parts):
        ring = list(part.exterior.coords)
        for a, b in zip(ring, ring[1:]):
            dx, dz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dz)
            if length < 4.45:
                continue
            tx, tz = dx / length, dz / length
            nx, nz = tz, -tx
            midpoint = Point((a[0] + b[0]) * .5 + nx * .1, (a[1] + b[1]) * .5 + nz * .1)
            if polygon.covers(midpoint):
                nx, nz = -nx, -nz
            projection = LineString([a, b]).project(point)
            for width in (6.4, 5.2, 4.0):
                if width + .4 > length:
                    continue
                margin = width * .5 + .22
                stations = [min(length-margin, max(margin, projection))]
                stations += [margin, length-margin, length*.25, length*.75, length*.5]
                for station in sorted(set(stations)):
                    if station < margin or station > length-margin:
                        continue
                    cx, cz = a[0]+tx*station, a[1]+tz*station
                    # Window/display depth .41m; player's external approach
                    # keeps another 1.2m. No new physical shop portal is made.
                    corners = [(cx+tx*s+nx*d, cz+tz*s+nz*d)
                               for s, d in [(-width*.5-.12, .02), (width*.5+.12, .02),
                                            (width*.5+.12, 1.75), (-width*.5-.12, 1.75)]]
                    approach = Polygon(corners)
                    if not box(-449.5, -459.5, 449.5, 459.5).covers(approach):
                        continue
                    if forbidden.intersects(approach):
                        continue
                    if approach.intersection(polygon).area > .000001:
                        continue
                    # Every candidate is tested against source buildings and
                    # barriers; source host may touch only its own facade plane.
                    overlap = False
                    for object_id, obstacle in building_parts:
                        if object_id == building_id:
                            continue
                        if approach.intersects(obstacle):
                            overlap = True
                            break
                    if overlap:
                        continue
                    span = LineString([(cx-tx*width*.5, cz-tz*width*.5),
                                       (cx+tx*width*.5, cz+tz*width*.5)])
                    if any(span.distance(door) < 1.30 or approach.distance(door) < .50 for door in doors):
                        continue
                    road_distance = streets.distance(Point(cx+nx*1.1, cz+nz*1.1))
                    if road_distance > 22.0:
                        continue
                    score = point.distance(Point(cx, cz)) + road_distance*.25 + (6.4-width)*.25
                    candidates.append((score, {"source_edge_xz": [list(a), list(b)],
                                              "source_part_index": part_index,
                                              "facade_center_xz": [cx, cz], "outward_xz": [nx, nz],
                                              "facade_width_m": width,
                                              "approach_xz": [cx+nx*1.1, cz+nz*1.1],
                                              "source_road_distance_m": road_distance,
                                              "source_edge_clearance_checked": True,
                                              "source_height_m": world_record["top_y_m"]}))
    return min(candidates, key=lambda entry: entry[0]) if candidates else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=8, choices=range(6, 11))
    parser.add_argument("--check", action="store_true", help="verify deterministic contents without writing")
    args = parser.parse_args()
    result = json.loads(CATALOG.read_text())
    base_rows = [row for row in result["records"] if row.get("frontage_generation") != GENERATION]
    if len(base_rows) != 4:
        raise SystemExit("Expected exactly four preserved EXP14 rows")
    before = json.dumps(base_rows, ensure_ascii=False, sort_keys=True)
    if sha(PBF) != result["source_osm_sha256"]:
        raise SystemExit("Regional PBF checksum differs from retained storefront snapshot")
    world = load("game/resources/world_geometry/world.json")
    features = load("data/processed/features.json")["features"]
    source = {item["id"]: item for item in world["meshes"]
              if item["role"] == "Buildings" and item["bottom_y_m"] <= .01 and item["top_y_m"] >= 2.9}
    buildings = {f["feature_id"]: shape(f["geometry"]) for f in features
                 if f["feature_id"] in source and f["geometry"]["type"] in ("Polygon", "MultiPolygon")}
    obstacles = list(buildings.items())
    obstacles += [(f["feature_id"], shape(f["geometry"]).buffer(.18)) for f in features if f["kind"] == "barrier"]
    walk = load("game/data/generated/public_walk.json")
    forbidden = unary_union([Polygon(p[0], p[1:]) for p in walk["private_rings"]]
                            + [shape(r["geometry"]) for r in walk["road_exclusions"]])
    catalog = load("game/assets/authored/interiors/source_catalog.json")
    doors = [Point(entry["door"]) for row in catalog["records"] for entry in row["entry_candidates"]]
    visit_ids = {row["id"] for row in catalog["records"]}
    streets = unary_union([shape(f["geometry"]) for f in features if f["kind"] in ("footpath", "road")
                           and f["source_tags"].get("tunnel", "no") == "no"
                           and f["source_tags"].get("layer", "0") in ("0", "")])
    cs = CoordinateSystem()
    nodes = ConvenienceNodes()
    nodes.apply_file(str(PBF))
    existing_ids = {row["source_poi"] for row in base_rows}
    excluded, choices = [], []
    tree = STRtree(list(buildings.values()))
    building_keys = list(buildings)
    for row in sorted(nodes.rows, key=lambda item: item["id"]):
        if f'n/{row["id"]}' in existing_ids:
            continue
        reason = rejected_floor(row["tags"])
        if reason:
            excluded.append({"source_poi": f'n/{row["id"]}', "reason": reason})
            continue
        x, _, z = cs.to_world(row["lon"], row["lat"])
        row["point"] = Point(x, z)
        candidate_ids = [building_keys[int(index)] for index in tree.query(row["point"].buffer(8.0))]
        candidate_ids.sort(key=lambda feature_id: (not buildings[feature_id].covers(row["point"]),
                                                   buildings[feature_id].distance(row["point"]), feature_id))
        best = None
        for feature_id in candidate_ids[:4]:
            polygon = buildings[feature_id]
            if polygon.distance(row["point"]) > 8.0:
                continue
            fit = fit_facade(row, feature_id, polygon, obstacles, forbidden, doors, streets, source[feature_id])
            if fit is None:
                continue
            score, facade = fit
            if row["point"].distance(Point(facade["facade_center_xz"])) > 25:
                continue
            score += 15 if not polygon.covers(row["point"]) else 0
            if best is not None and best[0] <= score:
                continue
            tags = row["tags"]
            title = tags.get("name", tags.get("name:en", tags.get("brand", "편의점")))
            if tags.get("branch") and tags["branch"] not in title:
                title += " " + tags["branch"]
            record = {"id": f'shop_{row["id"]}', "title": title, "style": style_for(tags),
                      "source_poi": f'n/{row["id"]}', "source_lon_lat": [row["lon"], row["lat"]],
                      "source_tags": tags, "source_feature_id": feature_id,
                      "source_world_point_xz": [x, z], "source_footprint_area_m2": polygon.area,
                      **facade, "height_m": 2.85,
                      "source_reference_url": f'https://www.openstreetmap.org/node/{row["id"]}',
                      "existing_visit_source_match": feature_id in visit_ids,
                      "offers_new_entry": False, "frontage_generation": GENERATION,
                      "source_snapshot": "data/raw/deoksugung_cityhall-v2.osm.pbf",
                      "source_snapshot_sha256": sha(PBF),
                      "frontage_basis": "Authored facade on retained source building edge with a 2D-clear exterior approach and protected existing game entrance candidates. Snapshot POI is not confirmation of current occupancy, exact ground-floor unit, public access or surveyed facade.",
                      "ground_floor_basis": "No explicit basement/upper-level/station tag in the retained POI; unknown level remains unverified. Ground-facing game frontage is authored.",
                      "menu": ["도시락 · 삼각김밥", "음료 · 간식"]}
            best = (score, record)
        if best is None:
            excluded.append({"source_poi": f'n/{row["id"]}', "reason": "no_clear_source_frontage_preserving_entrance_private_road_bounds"})
        else:
            choices.append(best)
    # Favor reliable source membership, then spread across 90m city cells.
    choices.sort(key=lambda value: (value[0], value[1]["id"]))
    selected, cells = [], set()
    used_sources = {row["source_feature_id"] for row in base_rows}
    for spread in (True, False):
        for score, record in choices:
            if len(selected) >= args.count:
                break
            if record["source_feature_id"] in used_sources:
                continue
            cell = tuple(int(math.floor(value/90)) for value in record["facade_center_xz"])
            if spread and cell in cells:
                continue
            selected.append(record);used_sources.add(record["source_feature_id"]);cells.add(cell)
    if len(selected) < 6:
        raise SystemExit(f"Only {len(selected)} safe candidates; do not invent placements: {excluded}")
    result["records"] = base_rows + sorted(selected, key=lambda row: row["source_poi"])
    result["exp16_generation"] = {"method": GENERATION, "new_facades": len(selected),
                                 "regional_convenience_nodes": len(nodes.rows),
                                 "existing_records_preserved": 4,
                                 "generator_sha256": sha(Path(__file__)),
                                 "source_features_sha256": sha(ROOT/"data/processed/features.json"),
                                 "excluded": excluded,
                                 "limits": "Offline source-linked 2D frontage selection. Runtime floor/capsule/source-body and rendered verification are separate. No current tenancy, actual shop-unit or surveyed facade assertion."}
    assert json.dumps(result["records"][:4], ensure_ascii=False, sort_keys=True) == before
    encoded = json.dumps(result, ensure_ascii=False, indent=2)+"\n"
    if args.check:
        if CATALOG.read_text() != encoded:
            raise SystemExit("Generated storefront contents differ; regenerate before checking")
    else:
        CATALOG.write_text(encoded)
    print(json.dumps({"result": "PASS", "mode": "check" if args.check else "write", "preserved": 4,
                      "added": len(selected), "total": len(result["records"]),
                      "selected": [{"id": row["id"], "title": row["title"], "source": row["source_feature_id"]}
                                   for row in selected], "excluded_count": len(excluded)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

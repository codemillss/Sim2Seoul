#!/usr/bin/env python3
"""Add only the retained Lotte Hotel source to the immutable EXP04 base catalog.

The investigation bbox is projected with the existing coordinate contract and
used as a game-only exploration limit. It is not surveyed public access.
"""
import argparse
import json
import math
from pathlib import Path

from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.ops import unary_union

from coordinate_system import CoordinateSystem
from prepare_building_visits import digest, edges, largest_grid_rectangle

ROOT = Path(__file__).resolve().parents[1]
LOTTE_ID = "osm:way:117914845:building"
EXTENT_PATH = "game/assets/authored/exploration_extent.json"
AUX_PATH = "game/assets/authored/interiors/supplemental_catalog.json"
BASE_PATH = "game/assets/authored/interiors/source_catalog.json"
INPUTS = ["config/region.json", "data/processed/features.json", "data/processed/heights.json",
          "game/resources/world_geometry/world.json", "game/data/generated/public_walk.json", BASE_PATH]
MARGIN = 0.4


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"


def generate():
    docs = {path: json.loads((ROOT / path).read_text()) for path in INPUTS}
    world = docs[INPUTS[3]]
    config = docs[INPUTS[0]]
    coordinates = CoordinateSystem(ROOT / INPUTS[0])
    west, south, east, north = config["bbox_west_south_east_north"]
    corners = [[coordinates.to_world(lon, lat)[axis] for axis in (0, 2)]
               for lon, lat in [(west, south), (east, south), (east, north), (west, north)]]
    extent_polygon = Polygon(corners)
    assert extent_polygon.is_valid and extent_polygon.area > 800000
    assert extent_polygon.buffer(-MARGIN).covers(box(-449.6, -459.6, 449.6, 459.6))
    min_x, min_z, max_x, max_z = extent_polygon.bounds
    extent = {"schema_version": 1, "task": "source_bbox_game_exploration_extent",
              "world_sha256": digest(ROOT / INPUTS[3]),
              "coordinate_contract_sha256": digest(ROOT / INPUTS[0]),
              "config_path": INPUTS[0], "source_bbox_west_south_east_north": config["bbox_west_south_east_north"],
              "coordinate_space": "local_xz_metres", "polygon_xz": corners,
              "aabb_min_xz": [min_x, min_z], "aabb_size_xz": [max_x - min_x, max_z - min_z],
              "capsule_edge_margin_m": MARGIN,
              "scope": "Game-only floor and player limit inside the already acquired source bbox. The AABB support is clipped logically by the player polygon. Private exclusions remain enforced. No new geographic data, surveyed terrain or public-access authorization.",
              "previous_rectangle": {"min_xz": [-450, -460], "size_xz": [900, 920],
                                     "capsule_inset_region_retained": True},
              "generator_sha256": digest(Path(__file__))}
    assert world["coordinate_contract_sha256"] == extent["coordinate_contract_sha256"]
    features = {item["feature_id"]: item for item in docs[INPUTS[1]]["features"]}
    height = next(item for item in docs[INPUTS[2]]["records"] if item["feature_id"] == LOTTE_ID)
    entry = next(item for item in world["meshes"] if item["id"] == LOTTE_ID)
    base = docs[BASE_PATH]
    assert len(base["records"]) == 125 and all(item["id"] != LOTTE_ID for item in base["records"])
    feature = features[LOTTE_ID]
    tags = feature["source_tags"]
    geometry = shape(feature["geometry"])
    assert geometry.is_valid and tags.get("tourism") == "hotel"
    assert extent_polygon.buffer(-MARGIN).covers(geometry), "Hotel footprint leaves source-bbox capsule margin"
    private = unary_union([Polygon(part[0], part[1:]) for part in docs[INPUTS[4]]["private_rings"]])
    assert not geometry.intersects(private), "Retained private exclusion overlaps hotel"
    roads = unary_union([shape(item["geometry"]) for item in features.values() if item["kind"] in ("road", "footpath")])
    obstacles = [(item["id"], shape(features[item["id"]]["geometry"])) for item in world["meshes"]
                 if item["role"] in ("Buildings", "Barriers") and item["id"] in features]
    floors = []
    for polygon in geometry.geoms:
        source_edges = sorted(edges(polygon), key=lambda edge: edge["length"], reverse=True)
        orientations = []
        for edge in source_edges:
            if any(abs(sum(a * b for a, b in zip(edge["along"], other["along"]))) > 0.985 for other in orientations):
                continue
            orientations.append(edge)
            rectangle = largest_grid_rectangle(polygon, edge["along"], edge["outward"])
            if rectangle is not None:
                floors.append((rectangle, polygon, source_edges))
            if len(orientations) >= 3:
                break
    assert floors, "No source-inscribed 12x16m floor"
    floor, polygon, source_edges = max(floors, key=lambda row: row[0]["rectangle_area_m2"])
    ax, az = floor["along"]
    ox, oz = floor["outward"]
    cx, cz = floor["rectangle_center"]
    rectangle = affinity.affine_transform(box(-floor["width"] / 2, -floor["depth"] / 2,
                                             floor["width"] / 2, floor["depth"] / 2), [ax, ox, az, oz, cx, cz])
    assert polygon.covers(rectangle) and geometry.covers(rectangle)
    candidates = []
    for edge in source_edges:
        along, outward, first = edge["along"], edge["outward"], edge["first"]
        projection = sum((floor["rectangle_center"][i] - first[i]) * along[i] for i in range(2))
        distance = max(1.8, min(projection, edge["length"] - 1.8))
        door = [first[i] + along[i] * distance for i in range(2)]
        entrance = [door[i] + outward[i] * 2 for i in range(2)]
        apron = LineString([entrance, [entrance[i] + outward[i] * .6 for i in range(2)]]).buffer(MARGIN)
        if not extent_polygon.covers(apron) or private.intersects(apron) or geometry.intersects(apron):
            continue
        if any(other_id != LOTTE_ID and other.intersects(apron) for other_id, other in obstacles):
            continue
        assert polygon.exterior.distance(Point(door)) < 1e-7
        candidates.append({"door": door, "entrance": entrance, "along": list(along), "outward": list(outward),
                           "door_width": min(3.6, edge["length"] - 1), "source_edge_length": edge["length"],
                           "street_distance": Point(entrance).distance(roads)})
    candidates.sort(key=lambda item: item["street_distance"])
    assert candidates, "No clear source-perimeter hotel entrance"
    source_height = float(entry["top_y_m"] - entry["bottom_y_m"])
    levels = height["source_levels"]
    assert source_height == float(height["height_m"]) == 150 and levels == 37
    assert entry["bottom_y_m"] == 0 and 3 <= source_height / levels <= 6
    record = {"id": LOTTE_ID, "title": entry["metadata"]["name"], "kind": "hotel",
              "catalog_origin": "supplemental_lotte_source_bbox", "source_rings": feature["geometry"]["coordinates"],
              "source_part_index": next(i for i, part in enumerate(geometry.geoms) if part.equals(polygon)),
              "source_height": source_height, "source_levels": levels, "source_height_class": height["height_class"],
              "floor_count": levels, "floor_height": source_height / levels, "height_basis": height["height_class"],
              "floors_basis": "osm_building_levels", "floor": floor, "entry_candidates": candidates[:8],
              "source_footprint_area_m2": geometry.area, "source_building_tag": tags.get("building", ""),
              "source_reference_ids": [item["object_id"] for item in feature["source_refs"]]}
    aux = {"schema_version": 1, "task": "supplemental_lotte_visit", "coordinate_space": "source_local_xz_metres",
           "world_sha256": digest(ROOT / INPUTS[3]), "base_catalog_sha256": digest(ROOT / BASE_PATH),
           "coordinate_contract_sha256": extent["coordinate_contract_sha256"],
           "exploration_extent_sha256": __import__("hashlib").sha256(encode(extent).encode()).hexdigest(),
           "provenance": {path: digest(ROOT / path) for path in INPUTS}, "generator_sha256": digest(Path(__file__)),
           "counts": {"base_records_unchanged": 125, "supplemental_records": 1, "merged_records": 126,
                      "base_floor_count": 1205, "supplemental_floor_count": 37, "merged_floor_count": 1242},
           "validation": {"result": "PASS", "hotel_source_bbox_outside_m2": geometry.difference(extent_polygon).area,
                          "hotel_capsule_inset_bbox_outside_m2": geometry.difference(extent_polygon.buffer(-MARGIN)).area,
                          "source_private_overlap_m2": geometry.intersection(private).area,
                          "floor_outside_actual_source_m2": rectangle.difference(geometry).area,
                          "source_door_candidates": len(candidates), "door_apron_capsule_radius_m": MARGIN,
                          "retail_not_added": "osm:way:233592424:building", "source_data_or_world_modified": False},
           "assumptions": {"floor_layout": "Source-inscribed game floor, no surveyed indoor plan.",
                           "door": "Clear candidate on actual source perimeter, not a measured real hotel doorway.",
                           "hotel_roof_pool": "Authored game amenity; factual hotel pool location/access unverified."},
           "records": [record]}
    return {EXTENT_PATH: extent, AUX_PATH: aux}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify existing outputs without writing")
    args = parser.parse_args()
    outputs = generate()
    for path, value in outputs.items():
        content = encode(value)
        target = ROOT / path
        if args.check:
            assert target.read_text() == content, f"Generated output differs: {path}"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
    print(json.dumps({"result": "PASS", "mode": "check" if args.check else "write", "outputs": list(outputs),
                      "validation": outputs[AUX_PATH]["validation"], "floor": outputs[AUX_PATH]["records"][0]["floor"],
                      "counts": outputs[AUX_PATH]["counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()

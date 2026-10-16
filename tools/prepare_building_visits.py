#!/usr/bin/env python3
"""EXP04 game interiors constrained by the retained source building envelopes.

The floor plans, door locations and height-derived storeys are game assumptions.
Footprint coordinates, heights and available OSM levels are copied from reviewed
G02/G03 inputs; no source exterior or collision file is modified.
"""
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import Point, Polygon, box, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = "game/assets/authored/interiors/source_catalog.json"
INPUTS = ["data/processed/features.json", "data/processed/heights.json",
          "game/resources/world_geometry/world.json", "game/data/generated/public_walk.json"]
MIN_WIDTH, MIN_DEPTH = 12.0, 16.0
INSET = 0.30


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def largest_grid_rectangle(polygon, along, outward):
    """Whole occupied cells give a rectangle covered by the actual polygon.

    A <= 1m grid is used for typical buildings, bounded to 140 cells per axis
    for large footprints. Each complete cell must be covered, retaining concave
    notches and holes. The final rectangle is checked by exact intersection.
    """
    ax, az = along
    ox, oz = outward
    local = affinity.affine_transform(polygon.buffer(-INSET), [ax, az, ox, oz, 0, 0])
    if local.is_empty:
        return None
    x0, z0, x1, z1 = local.bounds
    if x1 - x0 < MIN_WIDTH or z1 - z0 < MIN_DEPTH:
        return None
    step = max(0.75, (x1 - x0) / 140, (z1 - z0) / 140)
    nx, nz = math.ceil((x1 - x0) / step), math.ceil((z1 - z0) / step)
    dx, dz = (x1 - x0) / nx, (z1 - z0) / nz
    xx, zz = np.meshgrid(np.arange(nx), np.arange(nz))
    cells = shapely.box(x0 + xx * dx, z0 + zz * dz,
                        x0 + (xx + 1) * dx, z0 + (zz + 1) * dz)
    occupied = shapely.covers(local, cells)
    heights = np.zeros(nx, dtype=int)
    best = None
    best_area = 0
    for row in range(nz):
        heights = (heights + 1) * occupied[row]
        stack = []
        for column in range(nx + 1):
            height = int(heights[column]) if column < nx else 0
            start = column
            while stack and stack[-1][1] > height:
                first, count = stack.pop()
                width, depth = (column - first) * dx, count * dz
                area = width * depth
                if width >= MIN_WIDTH and depth >= MIN_DEPTH and area > best_area:
                    best_area = area
                    best = (x0 + first * dx, z0 + (row - count + 1) * dz,
                            x0 + column * dx, z0 + (row + 1) * dz)
                start = first
            if height > 0 and (not stack or stack[-1][1] < height):
                stack.append((start, height))
    if best is None:
        return None
    lx0, lz0, lx1, lz1 = best
    rectangle = affinity.affine_transform(box(*best), [ax, ox, az, oz, 0, 0])
    if not polygon.covers(rectangle):
        raise ValueError("Interior rectangle escaped source footprint")
    cx, cz = (lx0 + lx1) * 0.5, (lz0 + lz1) * 0.5
    return {"width": lx1 - lx0, "depth": lz1 - lz0,
            "rectangle_center": [ax * cx + ox * cz, az * cx + oz * cz],
            "along": [ax, az], "outward": [ox, oz],
            "rectangle_area_m2": rectangle.area,
            "rectangle_outside_source_m2": polygon.intersection(rectangle).symmetric_difference(rectangle).area}


def edges(polygon):
    result = []
    ring = list(polygon.exterior.coords)
    for first, second in zip(ring, ring[1:]):
        vx, vz = second[0] - first[0], second[1] - first[1]
        length = math.hypot(vx, vz)
        if length < 4:
            continue
        along = (vx / length, vz / length)
        outward = (-along[1], along[0])
        centre = ((first[0] + second[0]) / 2, (first[1] + second[1]) / 2)
        if polygon.contains(Point(centre[0] + outward[0] * 0.1,
                                  centre[1] + outward[1] * 0.1)):
            outward = (-outward[0], -outward[1])
        result.append({"first": first, "second": second, "along": along,
                       "outward": outward, "length": length, "centre": centre})
    return result


def main():
    docs = {path: json.loads((ROOT / path).read_text()) for path in INPUTS}
    features = {entry["feature_id"]: entry for entry in docs[INPUTS[0]]["features"]}
    heights = {entry["feature_id"]: entry for entry in docs[INPUTS[1]]["records"]}
    buildings = [entry for entry in docs[INPUTS[2]]["meshes"] if entry["role"] == "Buildings"]
    private = unary_union([Polygon(part[0], part[1:])
                           for part in docs[INPUTS[3]]["private_rings"]])
    roads = unary_union([shape(entry["geometry"]) for entry in features.values()
                         if entry["kind"] in ("road", "footpath")])
    obstacle_shapes = [(entry["id"], shape(features[entry["id"]]["geometry"])) for entry in buildings]
    records = []
    excluded = Counter()
    for entry in buildings:
        feature = features[entry["id"]]
        height = heights[entry["id"]]
        tags = feature["source_tags"]
        geometry = shape(feature["geometry"])
        if tags.get("building") in ("gate", "gatehouse", "pavilion", "parking") or tags.get("building:architecture") == "joseon" or tags.get("historic"):
            excluded["historic_gate_pavilion_or_parking"] += 1
            continue
        if geometry.intersects(private):
            excluded["retained_private_exclusion"] += 1
            continue
        if entry["bottom_y_m"] > 0.05 or entry["top_y_m"] - entry["bottom_y_m"] < 3:
            excluded["unsupported_bottom_or_height"] += 1
            continue
        if not box(-449.6, -459.6, 449.6, 459.6).covers(geometry):
            excluded["outside_current_outdoor_map"] += 1
            continue
        polygons = sorted(geometry.geoms, key=lambda part: part.area, reverse=True)
        candidates = []
        for polygon in polygons:
            if polygon.area < MIN_WIDTH * MIN_DEPTH:
                continue
            source_edges = edges(polygon)
            source_edges.sort(key=lambda edge: edge["length"], reverse=True)
            orientations = []
            for edge in source_edges:
                # Opposite parallel edges produce the same occupied rectangle.
                if any(abs(sum(a*b for a, b in zip(edge["along"], prior["along"]))) > 0.985
                       for prior in orientations):
                    continue
                orientations.append(edge)
                if len(orientations) == 3:
                    break
            for edge in orientations:
                result = largest_grid_rectangle(polygon, edge["along"], edge["outward"])
                if result is not None:
                    candidates.append((result, polygon, source_edges))
        if not candidates:
            excluded["no_safe_12_by_16m_inscribed_floor"] += 1
            continue
        floor, polygon, source_edges = max(candidates, key=lambda candidate: candidate[0]["rectangle_area_m2"])
        door_candidates = []
        centre = floor["rectangle_center"]
        for edge in source_edges:
            # Place a game door on the real outside perimeter, away from corners.
            a, along, outward = edge["first"], edge["along"], edge["outward"]
            distance = sum((centre[index] - a[index]) * along[index] for index in range(2))
            distance = max(min(distance, edge["length"] - 1.8), 1.8)
            door = [a[index] + along[index] * distance for index in range(2)]
            entrance = [door[index] + outward[index] * 2 for index in range(2)]
            point = Point(entrance)
            if geometry.buffer(0.35).contains(point) or private.buffer(0.4).intersects(point):
                continue
            if any(other_id != entry["id"] and other.buffer(0.35).contains(point)
                   for other_id, other in obstacle_shapes):
                continue
            if not box(-449, -459, 449, 459).contains(point):
                continue
            door_candidates.append({"door": door, "entrance": entrance,
                                    "along": list(along), "outward": list(outward),
                                    "door_width": min(3.6, edge["length"] - 1.0),
                                    "source_edge_length": edge["length"],
                                    "street_distance": point.distance(roads)})
        if not door_candidates:
            excluded["no_clear_source_perimeter_door"] += 1
            continue
        door_candidates.sort(key=lambda candidate: candidate["street_distance"])
        source_levels = height.get("source_levels")
        source_height = float(entry["top_y_m"] - entry["bottom_y_m"])
        count = int(source_levels) if source_levels and float(source_levels).is_integer() else max(1, int(source_height / 3.6))
        basis = "osm_building_levels" if source_levels and float(source_levels).is_integer() else "assumed_from_source_envelope_3.6m"
        # Invalid/very dense source levels cannot create head-height ceilings.
        count = max(1, min(count, 60, int(source_height / 3.0)))
        if source_levels and count != source_levels:
            basis = "source_levels_adjusted_to_3m_clear_floor_or_60_storey_limit"
        title = entry["metadata"]["name"] or "이름 없는 건물"
        kind = "library" if tags.get("amenity") == "library" else "civic" if entry["material"] == "civic" or tags.get("amenity") in ("townhall", "community_centre", "arts_centre") else "office"
        records.append({"id": entry["id"], "title": title, "kind": kind,
                        "source_rings": feature["geometry"]["coordinates"],
                        "source_part_index": next(index for index, part in enumerate(geometry.geoms) if part.equals(polygon)),
                        "source_height": source_height, "source_levels": source_levels,
                        "source_height_class": height["height_class"],
                        "floor_count": count, "floor_height": source_height / count,
                        "height_basis": height["height_class"], "floors_basis": basis,
                        "floor": floor, "entry_candidates": door_candidates[:8],
                        "source_footprint_area_m2": geometry.area,
                        "source_building_tag": tags.get("building", ""),
                        "source_reference_ids": [item["object_id"] for item in feature["source_refs"]]})
    payload = {"schema_version": 1, "task": "EXP04", "coordinate_space": "source_local_xz_metres",
               "world_sha256": digest(ROOT / INPUTS[2]),
               "provenance": {path: digest(ROOT / path) for path in INPUTS},
               "generator_sha256": digest(Path(__file__)),
               "assumptions": {"floor_layout": "game reconstruction; no measured indoor floor plan",
                               "doors": "game doors selected on actual source perimeter, not surveyed entrances",
                               "estimated_levels": "floor(source height / 3.6m), limited to >=3m and <=60 floors",
                               "rectangle": "whole covered grid cells within source polygon inset 0.30m; holes retained",
                               "real_world_access": "unverified; game entry does not grant physical access"},
               "counts": {"source_buildings": len(buildings), "records": len(records), "exclusions": dict(excluded)},
               "records": records}
    target = ROOT / OUTPUT
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n")
    print(json.dumps({"output": OUTPUT, "bytes": target.stat().st_size, "counts": payload["counts"],
                      "dimensions": {record["title"]: {key: record["floor"][key] for key in ("width", "depth")} | {"floor_count": record["floor_count"], "floor_height": record["floor_height"]} for record in records if record["kind"] in ("library", "civic")}}, ensure_ascii=False))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""D03 local reference checks, source comparison and an SVG investigation map."""
from __future__ import annotations

from collections import Counter
import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
import math
from pathlib import Path
import re

import numpy as np
import osmium
from pyproj import Geod, Transformer
import rasterio
from shapely.geometry import box, shape
from shapely import transform as transform_geometry

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "config/region.json").read_text())
BBOX = CONFIG["bbox_west_south_east_north"]
WINDOW = box(*BBOX)
PROJECT = Transformer.from_crs(4326, CONFIG["metric_crs"], always_xy=True).transform


def project(geometry):
    return transform_geometry(geometry, PROJECT, interleaved=False)


def load(path):
    return json.loads((ROOT / path).read_text())


def save(path, value):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def verify_file(record):
    path = ROOT / record["file"]
    return path.stat().st_size == record["bytes"] and hashlib.sha256(path.read_bytes()).hexdigest() == record["sha256"]


def positive(value, integer=False):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value > 0
            and (not integer or value == int(value)))


def source_osm_ids(feature):
    ids = []
    for source in feature["properties"].get("sources", []):
        if source.get("dataset") != "OpenStreetMap":
            continue
        match = re.fullmatch(r"([nwr])(\d+)@(\d+)", source.get("record_id") or "")
        if match:
            ids.append(f"{match[1]}/{match[2]}")
    return ids


def crossing_candidates():
    class Nodes(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.crossings = []
        def node(self, node):
            tags = dict(node.tags)
            if tags.get("highway") == "crossing" and node.location.valid():
                if BBOX[0] <= node.lon <= BBOX[2] and BBOX[1] <= node.lat <= BBOX[3]:
                    self.crossings.append({"osm_id": f"n/{node.id}", "lon_lat": [node.lon, node.lat],
                        "tags": tags, "status": "OSM candidate; current access and continuous route unverified"})
    nodes = Nodes()
    nodes.apply_file(str(ROOT / load("data/reports/extract_manifest.json")["extract_file"]))
    return nodes.crossings


def render_map(osm, overture, crossings):
    extent = project(WINDOW).bounds
    west, south, east, north = extent
    scale = min(1140 / (east - west), 970 / (north - south))
    width, height = 1280, 1130
    def point(x, y):
        x, y = PROJECT(x, y)
        return 60 + (x - west) * scale, 65 + (north - y) * scale
    def path(geometry):
        geometry = shape(geometry)
        components = list(geometry.geoms) if hasattr(geometry, "geoms") else [geometry]
        commands = []
        for component in components:
            rings = [component.exterior, *component.interiors] if component.geom_type == "Polygon" else [component]
            for ring in rings:
                coordinates = list(ring.coords)
                converted = [point(*coordinate[:2]) for coordinate in coordinates]
                commands.append("M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in converted)
                                + (" Z" if component.geom_type == "Polygon" else ""))
        return " ".join(commands)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fafaf7"/>',
        '<text x="60" y="32" font-size="22" font-family="sans-serif">D03 · 덕수궁 / 시청 자료 대조 — 조사 범위, 플레이 경계 아님</text>',
        f'<defs><clipPath id="map"><rect x="60" y="65" width="{(east-west)*scale:.2f}" height="{(north-south)*scale:.2f}"/></clipPath></defs>',
        '<g clip-path="url(#map)" fill-rule="evenodd">']
    styles = {"land_area": ("#f0f2e7", "#e1e4d9", 0.4),
              "highway_area": ("#d5eacf", "#abc5a5", 0.5),
              "highway_line": ("none", "#c3b99d", 1.2),
              "building": ("#c6ccd1", "#969ea5", 0.45),
              "building_part": ("none", "#6c818e", 0.6),
              "barrier": ("none", "#4a555c", 1.2)}
    for kind, (fill, stroke, thickness) in styles.items():
        for feature in osm:
            if feature["properties"]["feature_kind"] != kind:
                continue
            parts.append(f'<path d="{path(feature["geometry"])}" fill="{fill}" stroke="{stroke}" stroke-width="{thickness}"/>')
    for feature in overture:
        if source_osm_ids(feature):
            continue
        parts.append(f'<path d="{path(feature["geometry"])}" fill="#c3359460" stroke="#a62577" stroke-width="1.2"/>')
    labels = {"w/377289797": "대한문", "w/181574577": "중화전", "r/19357693": "석조전",
              "w/517072312": "돈덕전", "w/198561926": "신 시청", "r/10757525": "서울도서관",
              "w/370019676": "서울광장"}
    for crossing in crossings:
        x, y = point(*crossing["lon_lat"])
        parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2.4" fill="#cf6639"/>')
    for feature in osm:
        tags = feature["properties"].get("tags", {})
        if feature["geometry"]["type"] == "Point" and tags.get("highway") == "crossing":
            x, y = point(*feature["geometry"]["coordinates"])
            parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="3" fill="#cf6639"/>')
        identity = feature["properties"]["osm_id"]
        if identity in labels:
            centroid = shape(feature["geometry"]).representative_point()
            x, y = point(centroid.x, centroid.y)
            parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="4" fill="#186598"/>'
                f'<text x="{x+7:.2f}" y="{y-6:.2f}" font-family="sans-serif" font-size="14" stroke="#fafaf7" stroke-width="3" paint-order="stroke">{html.escape(labels[identity])}</text>')
    parts.extend(['</g>', '<path d="M1210 110 V70 M1204 79 L1210 69 L1216 79" fill="none" stroke="#24303b" stroke-width="2"/>',
        '<text x="1204" y="57" font-family="sans-serif" font-size="16">N</text>',
        f'<path d="M60 1043 h{100*scale:.2f}" stroke="#24303b" stroke-width="4"/>',
        '<text x="60" y="1065" font-family="sans-serif" font-size="14">100m · EPSG:32652 투영 기준</text>',
        '<text x="300" y="1065" font-family="sans-serif" font-size="14">회색: OSM 건물 · 녹색: 보행 면 · 자주색: 비OSM 후보 · 주황: 횡단 노드 후보</text>',
        '<text x="60" y="1102" font-family="sans-serif" font-size="13">© OpenStreetMap contributors, Overture Maps Foundation; Qian Shi et al. (CC BY 4.0) · 통행·외부 측량 검증 전</text>', '</svg>'])
    output = ROOT / "docs/evidence/D03_SOURCE_OVERVIEW.svg"
    output.write_text("\n".join(parts) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", default="data/reports/d03_supplemental_review.json")
    parser.add_argument("--no-map", action="store_true", help="Do not rewrite map/crossing artifacts when only checking a checkout")
    args = parser.parse_args()
    if not (ROOT / "data/processed/osm_preview.geojson").exists():
        raise SystemExit("Run tools/setup_mac.sh (or the current OSM audit) to regenerate the local preview first")
    current = load("data/reports/extract_manifest.json")
    audit = load("data/reports/osm_audit.json")
    if audit["extract_sha256"] != current["extract_sha256"]:
        raise SystemExit("OSM preview/audit source is not the current extract")
    artifact = audit.get("preview_artifact")
    config_hash = hashlib.sha256((ROOT / "config/region.json").read_bytes()).hexdigest()
    if not artifact or not verify_file(artifact) or artifact.get("config_sha256") != config_hash:
        raise SystemExit("OSM preview checksum/provenance mismatch; regenerate with the current OSM audit")
    osm = load(artifact["file"])["features"]
    acquisition = load("data/reports/overture_acquisition-2026-09-23.1.json")
    dsm = load("data/reports/copernicus_acquisition-20261012.json")
    checks = []
    def check(name, passed):
        checks.append({"check": name, "passed": bool(passed)})
    check("osm_preview_hash_and_config_binding", True)
    check("current_osm_hash", hashlib.sha256((ROOT / current["extract_file"]).read_bytes()).hexdigest() == current["extract_sha256"])
    check("overture_snapshot_hash", verify_file(acquisition["artifact"]))
    check("dsm_regional_hash", verify_file(dsm["regional_artifact"]))
    collection = load(acquisition["artifact"]["file"])
    received = collection["features"]
    check("received_nonempty_feature_collection", collection["type"] == "FeatureCollection" and bool(received))
    check("overture_unique_ids", len({f["id"] for f in received}) == len(received))
    geometries = [shape(f["geometry"]) for f in received]
    invalid = [f["id"] for f, geom in zip(received, geometries) if geom.is_empty or not geom.is_valid]
    outside = [f["id"] for f, geom in zip(received, geometries) if not geom.intersects(WINDOW)]
    features = [f for f in received if f["id"] not in outside]
    check("valid_polygon_geometry", not invalid and all(g.geom_type in ("Polygon", "MultiPolygon") for g in geometries))
    check("bbox_false_positives_explicitly_excluded", len(features) + len(outside) == len(received)
          and all(shape(f["geometry"]).intersects(WINDOW) for f in features))
    check("source_references_preserved", all(f["properties"].get("sources") for f in features))
    heights = [f["properties"].get("height") for f in features if f["properties"].get("height") is not None]
    floors = [f["properties"].get("num_floors") for f in features if f["properties"].get("num_floors") is not None]
    check("height_values_finite_positive_numeric", all(positive(v) for v in heights))
    check("floor_values_positive_integers", all(positive(v, integer=True) for v in floors))
    datasets = Counter(s.get("dataset") for f in features for s in f["properties"]["sources"])
    osm_buildings = {f["properties"]["osm_id"]: f for f in osm if f["properties"]["feature_kind"] == "building"}
    projected_osm = {identity: project(shape(f["geometry"])) for identity, f in osm_buildings.items()}
    candidates = []
    id_matches = 0
    absent_ids = []
    height_additions = []
    height_differences = []
    for feature in features:
        identities = source_osm_ids(feature)
        matched = [identity for identity in identities if identity in osm_buildings]
        id_matches += bool(matched)
        absent_ids.extend(identity for identity in identities if identity not in osm_buildings)
        if not identities:
            geometry = project(shape(feature["geometry"]))
            overlaps = [identity for identity, old in projected_osm.items() if geometry.intersects(old)]
            candidates.append({"overture_id": feature["id"], "area_m2": geometry.area,
                "source_datasets": [s["dataset"] for s in feature["properties"]["sources"]],
                "overlapping_current_osm_building_ids": overlaps,
                "status": "review_candidate_not_added_to_game"})
        value = feature["properties"].get("height")
        for identity in matched:
            raw = osm_buildings[identity]["properties"]["tags"].get("height")
            if value is not None and raw is None:
                height_additions.append({"osm_id": identity, "overture_height": value})
            if value is not None and raw is not None:
                try:
                    parsed = float(re.sub(r"\s*m\s*$", "", raw.strip()))
                except ValueError:
                    parsed = None
                if parsed is None or abs(parsed - value) > 1e-6:
                    height_differences.append({"osm_id": identity, "current_osm_raw": raw,
                                              "older_overture_height": value})
    dsm_path = ROOT / dsm["regional_artifact"]["file"]
    with rasterio.open(dsm_path) as raster:
        array = raster.read(1, masked=True)
        check("dsm_single_band_wgs84", raster.count == 1 and raster.crs.to_epsg() == 4326)
        check("dsm_all_pixels_unmasked_and_finite", not np.any(np.ma.getmaskarray(array)) and np.isfinite(array.data).all())
        bounds = raster.bounds
        check("dsm_crop_covers_bbox", bounds.left <= BBOX[0] and bounds.bottom <= BBOX[1] and bounds.right >= BBOX[2] and bounds.top >= BBOX[3])
        check("dsm_reference_only_tag", raster.tags().get("reference_only") == "DSM_NOT_WALKABLE_GROUND")
        source_path = ROOT / dsm["source_artifact"]["file"]
        source_verified = None
        crop_equal = None
        if source_path.exists():
            from rasterio.windows import Window
            source_verified = verify_file(dsm["source_artifact"])
            with rasterio.open(source_path) as original:
                window = Window(*dsm["crop_window"])
                crop_equal = np.array_equal(array.data, original.read(1, window=window)) and raster.transform == original.window_transform(window)
            check("optional_local_dsm_source_hash", source_verified)
            check("optional_local_crop_native_pixel_equality", crop_equal)
        _, _, dx = Geod(ellps="WGS84").inv(BBOX[0], BBOX[1], BBOX[0]+raster.res[0], BBOX[1])
        _, _, dy = Geod(ellps="WGS84").inv(BBOX[0], BBOX[1], BBOX[0], BBOX[1]+raster.res[1])
        dsm_review = {"shape_rows_columns": list(raster.shape), "pixel_spacing_degrees": list(raster.res),
            "pixel_spacing_m_at_southwest": [dx, dy], "bounds": list(bounds),
            "surface_elevation_min_max_m": [float(array.min()), float(array.max())],
            "vertical_datum": dsm["vertical_datum"], "source_available_locally": source_path.exists(),
            "source_hash_verified": source_verified, "crop_native_pixels_equal": crop_equal,
            "use": "surface_reference_only_not_ground_or_building_height"}
    report = {"task_id": "D03", "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "passed": all(c["passed"] for c in checks), "checks": checks,
        "current_osm_extract": current["extract_file"], "current_osm_sha256": current["extract_sha256"],
        "osm_preview_artifact": artifact,
        "overture_release": acquisition["release"], "overture_received_feature_count": len(received),
        "overture_selected_intersecting_feature_count": len(features),
        "invalid_geometries": invalid, "excluded_bbox_false_positive_ids": outside, "source_record_counts": dict(datasets),
        "heights": {"present": len(heights), "denominator": len(features), "range_m": [min(heights), max(heights)],
                    "source_datasets": dict(Counter(s["dataset"] for f in features if f["properties"].get("height") is not None for s in f["properties"]["sources"]))},
        "floors": {"present": len(floors), "denominator": len(features), "range": [min(floors), max(floors)]},
        "matched_current_osm_building_ids": id_matches,
        "current_osm_height_missing_in_overture": [identity for identity, f in osm_buildings.items()
            if f["properties"]["tags"].get("height") is not None
            and any(identity in source_osm_ids(o) and o["properties"].get("height") is None for o in features)],
        "source_osm_ids_not_in_current_building_preview": absent_ids,
        "height_candidates_missing_current_osm_tag": height_additions, "height_value_differences": height_differences,
        "non_osm_candidates": candidates, "dsm": dsm_review,
        "before_review": "data/reports/d03_before_review.json",
        "limitations": ["Candidate count is not verified real-world building omission",
            "OSM-sourced Overture heights are not independent measured supplementation",
            "OSM snapshot dates differ; no automatic replacement or conflation performed",
            "DSM is coarse surface elevation and cannot establish walking ground",
            "Official access references and game route verification are separate"]}
    crossings = crossing_candidates()
    report["crossing_node_count_candidates_only"] = len(crossings)
    save(args.report, report)
    if not args.no_map:
        save("data/reports/d03_crossing_candidates.json", {"task_id": "D03",
            "input_manifest": "data/reports/extract_manifest.json", "coordinate_crs": "EPSG:4326",
            "crossing_candidates": crossings,
            "limitation": "OSM node candidates only; no current access, level or continuous route validation"})
        render_map(osm, features, crossings)
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "received": len(received), "selected_buildings": len(features),
        "non_osm_candidates": len(candidates), "height_values": len(heights),
        "report": args.report}, ensure_ascii=False))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

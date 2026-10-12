#!/usr/bin/env python3
"""Extract and audit a local OSM snapshot. No network, no game asset generation.

Run with the pinned .venv-data interpreter. Keep this preparation evidence
separate from a claim that the map is accurate or traversable in the game.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

import osmium
from pyproj import Geod, Transformer
from shapely import wkb
from shapely.geometry import LineString, Point, Polygon, box, mapping

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "config/region.json").read_text())
BBOX = CONFIG["bbox_west_south_east_north"]
WINDOW = box(*BBOX)


def save_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


class Extract(osmium.SimpleHandler):
    def __init__(self, writer):
        super().__init__()
        self.writer = writer
        self.nodes, self.ways, self.relations = set(), set(), set()
        self.counts = Counter()

    def node(self, n):
        self.counts["country_nodes_scanned"] += 1
        if (n.location.valid() and BBOX[0] <= n.lon <= BBOX[2]
                and BBOX[1] <= n.lat <= BBOX[3]):
            self.nodes.add(n.id)
            self.writer.add_node(n)

    def way(self, w):
        self.counts["country_ways_scanned"] += 1
        if len(w.nodes) < 2:
            return
        if not all(n.location.valid() for n in w.nodes):
            self.counts["country_ways_with_missing_locations_skipped"] += 1
            return
        coords = [(n.lon, n.lat) for n in w.nodes]
        west = min(p[0] for p in coords)
        east = max(p[0] for p in coords)
        south = min(p[1] for p in coords)
        north = max(p[1] for p in coords)
        if east < BBOX[0] or west > BBOX[2] or north < BBOX[1] or south > BBOX[3]:
            return
        geom = Polygon(coords) if w.is_closed() and len(coords) >= 4 else LineString(coords)
        # Invalid rings remain in raw data for a later repair decision.
        if geom.intersects(WINDOW):
            self.ways.add(w.id)
            self.writer.add_way(w)

    def relation(self, r):
        self.counts["country_relations_scanned"] += 1
        kind = r.tags.get("type", "")
        if kind not in {"multipolygon", "building", "site"}:
            return
        relevant = kind == "building" or any(k in r.tags for k in (
            "building", "building:part", "historic", "leisure", "landuse", "barrier", "natural", "highway"))
        if relevant and any(
            (m.type == "n" and m.ref in self.nodes)
            or (m.type == "w" and m.ref in self.ways)
            or (m.type == "r" and m.ref in self.relations) for m in r.members
        ):
            self.relations.add(r.id)
            self.writer.add_relation(r)


def extract(source: Path, target: Path):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise FileExistsError(f"Preserving existing snapshot: {target}")
    with osmium.BackReferenceWriter(target, source, remove_tags=False, relation_depth=3) as writer:
        handler = Extract(writer)
        handler.apply_file(source, locations=True)
    manifest = {
        "source_file": str(source.relative_to(ROOT)),
        "source_sha256": digest(source),
        "extract_file": str(target.relative_to(ROOT)),
        "extract_sha256": digest(target),
        "extract_bytes": target.stat().st_size,
        "bbox_west_south_east_north": BBOX,
        "selection_counts": dict(handler.counts),
        "directly_selected": {"nodes": len(handler.nodes), "ways": len(handler.ways),
                              "relations": len(handler.relations)},
        "policy": "BBox-intersecting ways (closed rings include enclosure), inside nodes, relevant local multipolygon/building/site relations; backward references completed to depth 3; tags retained.",
        "limitations": [
            "Not a universal recursive geographic extract: ancestor relations not discovered through selected members can be omitted.",
            "Multipolygons fully enclosing the bbox without any intersecting member can be omitted.",
            "Route and administrative relations intentionally excluded unless pulled as backward references.",
            "Country-edge ways with incomplete node locations skipped and counted; inspect local coverage independently.",
            "Reference completeness does not establish current real-world geometry or access."
        ]
    }
    save_json(ROOT / "data/reports/extract_manifest.json", manifest)
    print(json.dumps(manifest, ensure_ascii=False), flush=True)


class RawAudit(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ids = {"n": set(), "w": set(), "r": set()}
        self.refs = []
        self.categories = Counter()
        self.tag_presence = {}
        self.named = []
        self.header = None

    def collect(self, obj, kind):
        self.ids[kind].add(obj.id)
        tags = dict(obj.tags)
        for category in ("building", "building:part", "highway", "barrier", "historic"):
            if category in tags:
                label = f"{kind}:{category}"
                self.categories[label] += 1
                stats = self.tag_presence.setdefault(label, Counter())
                for key in ("height", "building:levels", "min_height", "width", "lanes", "access", "foot", "layer", "bridge", "tunnel", "incline"):
                    if key in tags:
                        stats[key] += 1
        if any(k in tags for k in ("name", "name:ko", "name:en")):
            self.named.append({"osm_id": f"{kind}/{obj.id}", "tags": tags})

    def node(self, n):
        self.collect(n, "n")

    def way(self, w):
        self.collect(w, "w")
        self.refs.extend((f"w/{w.id}", "n", n.ref) for n in w.nodes)

    def relation(self, r):
        self.collect(r, "r")
        self.refs.extend((f"r/{r.id}", m.type, m.ref) for m in r.members)


class GeometryAudit(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.factory = osmium.geom.WKBFactory()
        self.features = []
        self.errors = []

    def append(self, obj, geom, kind, osm_id):
        if not geom.intersects(WINDOW):
            return
        self.features.append({"type": "Feature", "id": f"{osm_id}:{kind}",
            "properties": {"osm_id": osm_id, "feature_kind": kind,
                           "geometry_valid": bool(geom.is_valid), "tags": dict(obj.tags)},
            "geometry": mapping(geom)})

    def way(self, w):
        # Closed pedestrian areas are surfaces, not road centre lines.
        kind = ("highway_line" if "highway" in w.tags and w.tags.get("area") != "yes"
                else "barrier" if "barrier" in w.tags else None)
        if kind:
            try:
                self.append(w, wkb.loads(self.factory.create_linestring(w), hex=True), kind, f"w/{w.id}")
            except Exception as exc:
                self.errors.append({"osm_id": f"w/{w.id}", "error": str(exc)})

    def node(self, n):
        if n.location.valid() and n.tags.get("barrier") in {"gate", "entrance", "lift_gate"}:
            self.append(n, Point(n.lon, n.lat), "gate_node", f"n/{n.id}")

    def area(self, a):
        kind = ("building_part" if "building:part" in a.tags else "building" if "building" in a.tags
                else "highway_area" if "highway" in a.tags and (a.tags.get("area") == "yes" or not a.from_way())
                else "barrier_area" if "barrier" in a.tags
                else "land_area" if any(k in a.tags for k in ("leisure", "landuse", "historic")) else None)
        if kind:
            source_kind = "w" if a.from_way() else "r"
            try:
                self.append(a, wkb.loads(self.factory.create_multipolygon(a), hex=True), kind, f"{source_kind}/{a.orig_id()}")
            except Exception as exc:
                self.errors.append({"osm_id": f"{source_kind}/{a.orig_id()}", "error": str(exc)})


def audit(source: Path):
    raw = RawAudit()
    raw.apply_file(source)
    missing = [{"owner": owner, "missing": f"{kind}/{ref}"}
               for owner, kind, ref in raw.refs if ref not in raw.ids[kind]]
    geometry = GeometryAudit()
    geometry.apply_file(source, locations=True)
    features = geometry.features
    heights = Counter()
    for f in features:
        if f["properties"]["feature_kind"] == "building":
            for k in ("height", "building:levels"):
                if k in f["properties"]["tags"]:
                    heights[k] += 1
            if any(k in f["properties"]["tags"] for k in ("height", "building:levels")):
                heights["either_height_or_levels"] += 1
            else:
                heights["neither_height_nor_levels"] += 1
    projection = Transformer.from_crs("EPSG:4326", CONFIG["metric_crs"], always_xy=True)
    inverse = Transformer.from_crs(CONFIG["metric_crs"], "EPSG:4326", always_xy=True)
    points = [BBOX[:2], BBOX[2:], CONFIG["origin_lon_lat"]]
    roundtrip = max(max(abs(a-b) for a, b in zip(p, inverse.transform(*projection.transform(*p)))) for p in points)
    a, b = points[:2]
    ax, ay = projection.transform(*a)
    bx, by = projection.transform(*b)
    planar = ((bx-ax)**2+(by-ay)**2)**0.5
    geodesic = Geod(ellps="WGS84").inv(*a, *b)[2]
    feature_counts = Counter(f["properties"]["feature_kind"] for f in features)
    report = {
        "extract_sha256": digest(source), "bbox_west_south_east_north": BBOX,
        "raw_object_counts_including_reference_objects": {k: len(v) for k, v in raw.ids.items()},
        "raw_category_counts_not_unique_real_buildings": dict(raw.categories),
        "raw_tag_presence_counts": raw.tag_presence,
        "unresolved_reference_count": len(missing), "unresolved_references_first_50": missing[:50],
        "preview_feature_counts_intersecting_bbox": dict(feature_counts),
        "preview_building_height_tag_presence_not_validated_values": dict(heights),
        "invalid_preview_geometry_count": sum(not f["properties"]["geometry_valid"] for f in features),
        "geometry_errors": geometry.errors,
        "projection_smoke_test": {"crs": CONFIG["metric_crs"], "axis_order": "longitude_latitude",
            "max_roundtrip_error_degrees": roundtrip, "diagonal_planar_m": planar,
            "diagonal_geodesic_m": geodesic, "relative_difference": abs(planar-geodesic)/geodesic,
            "origin_easting_northing": projection.transform(*CONFIG["origin_lon_lat"])},
        "not_yet_verified": ["Independent coverage/positional accuracy", "building vs building_part and relation duplication",
            "height units and semantic correctness", "actual access and gate openings", "road widths and road area handling",
            "terrain and vertical datum", "landmark alignment", "game geometry/collision/performance"]
    }
    save_json(ROOT / "data/reports/osm_audit.json", report)
    save_json(ROOT / "data/reports/named_features.json", raw.named)
    save_json(ROOT / "data/processed/osm_preview.geojson", {"type": "FeatureCollection", "features": features})
    print(json.dumps(report, ensure_ascii=False), flush=True)
    if missing or geometry.errors or roundtrip > 1e-8:
        raise SystemExit("Preparation audit found defects; see report. Do not promote to game-ready.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["extract", "audit"])
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "data/raw/deoksugung_cityhall.osm.pbf")
    args = parser.parse_args()
    if args.action == "extract":
        extract(args.source.resolve(), args.output.resolve())
    else:
        audit(args.source.resolve())

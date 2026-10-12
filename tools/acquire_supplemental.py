#!/usr/bin/env python3
"""Acquire versioned, small D03 reference datasets; never generate game assets."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import re
import subprocess
import sys

import requests

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "config/region.json").read_text())
BBOX = CONFIG["bbox_west_south_east_north"]
RELEASE = "2026-09-23.1"
DSM_TILE = "Copernicus_DSM_COG_10_N37_00_E126_00_DEM"
DSM_URL = f"https://copernicus-dem-30m.s3.amazonaws.com/{DSM_TILE}/{DSM_TILE}.tif"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def describe(path):
    return {"file": str(path.relative_to(ROOT)), "bytes": path.stat().st_size,
            "sha256": sha256(path)}


def download(url, output, limit=64_000_000):
    if output.exists():
        raise SystemExit(f"Existing snapshot is preserved: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    if temporary.exists():
        raise SystemExit(f"Inspect the previous incomplete download: {temporary}")
    with requests.get(url, stream=True, timeout=(30, 90)) as response:
        response.raise_for_status()
        expected = int(response.headers.get("Content-Length", "0"))
        if expected > limit:
            raise SystemExit("Response exceeds the planned download size")
        size = 0
        with temporary.open("wb") as stream:
            for chunk in response.iter_content(1024 * 1024):
                size += len(chunk)
                if size > limit:
                    raise SystemExit("Response exceeds the planned download size")
                stream.write(chunk)
        if not size or (expected and size != expected):
            raise SystemExit("Incomplete response; preserved .part for inspection")
        headers = {key: response.headers.get(key) for key in
                   ("Content-Length", "Content-Type", "ETag", "Last-Modified")}
    temporary.rename(output)
    return headers


def acquire_overture(release):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}\.\d+", release):
        raise SystemExit("Use a date-based Overture release, for example 2026-09-23.1")
    output = ROOT / f"data/raw/supplemental/overture/{release}/buildings.geojson"
    report = ROOT / f"data/reports/overture_acquisition-{release}.json"
    if output.exists() or report.exists():
        raise SystemExit("Existing Overture snapshot preserved; use the local review tool")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".geojson.part")
    if temporary.exists():
        raise SystemExit(f"Inspect previous partial output: {temporary}")
    started = datetime.now(timezone.utc).isoformat()
    command = [sys.executable, "-m", "overturemaps", "download",
               "--release", release, "--bbox=" + ",".join(map(str, BBOX)),
               "--type=building", "-f", "geojson", "--stac",
               "--connect_timeout", "30", "--request_timeout", "90",
               "-o", str(temporary.relative_to(ROOT))]
    print(f"Downloading Overture building reference {release}, bbox={BBOX}", flush=True)
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=600)
    log = ROOT / f"data/reports/overture_download-{release}.log"
    log.write_text(run.stdout + run.stderr)
    if run.returncode:
        raise SystemExit(f"Download failed with exit {run.returncode}; see {log.relative_to(ROOT)}")
    content = json.loads(temporary.read_text())
    if content.get("type") != "FeatureCollection" or not content.get("features"):
        raise SystemExit("No valid regional FeatureCollection received")
    temporary.rename(output)
    # The official CLI's absolute-path state is local-only and not a portable source manifest.
    state = Path(str(temporary) + ".state")
    if state.exists():
        state.unlink()
    write_json(report, {"provider": "Overture Maps Foundation", "release": release,
        "started_at_utc": started, "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
        "catalog_url": f"https://stac.overturemaps.org/{release}/catalog.json",
        "source_location": f"s3://overturemaps-us-west-2/release/{release}/theme=buildings/type=building/",
        "request_bbox_west_south_east_north": BBOX, "crs": "EPSG:4326",
        "geometry_policy": "Official CLI bounding-box query; full polygons retained. Exact intersections are checked locally; bbox false positives may exist",
        "command": command[1:], "tool_version": importlib.metadata.version("overturemaps"),
        "license": "ODbL-1.0", "license_url": "https://docs.overturemaps.org/attribution/",
        "record_count": len(content["features"]), "artifact": describe(output),
        "limitations": ["Sources may include OSM; not an independent ground truth",
                         "Release date is not the survey date of all features",
                         "No automatic merge into the current OSM map or game"]})
    print(json.dumps({"result": "received", **describe(output)}, ensure_ascii=False))


def acquire_dsm():
    import rasterio
    from rasterio.windows import Window, from_bounds

    directory = ROOT / "data/raw/supplemental/copernicus/20261012"
    source = directory / f"{DSM_TILE}.tif"
    crop = directory / "deoksugung_cityhall-dsm-reference.tif"
    report = ROOT / "data/reports/copernicus_acquisition-20261012.json"
    if crop.exists() or report.exists():
        raise SystemExit("Existing DSM snapshot preserved; use the local review tool")
    started = datetime.now(timezone.utc).isoformat()
    print("Downloading one public GLO-30 reference tile (about 30MB)", flush=True)
    headers = download(DSM_URL, source)
    with rasterio.open(source) as dataset:
        if dataset.crs.to_epsg() != 4326 or dataset.count != 1:
            raise SystemExit("Unexpected DSM horizontal CRS or band count")
        source_bounds = dataset.bounds
        if not (source_bounds.left <= BBOX[0] and source_bounds.bottom <= BBOX[1]
                and source_bounds.right >= BBOX[2] and source_bounds.top >= BBOX[3]):
            raise SystemExit("Source tile does not cover the investigation bbox")
        requested = from_bounds(*BBOX, transform=dataset.transform)
        x0, y0 = math.floor(requested.col_off), math.floor(requested.row_off)
        x1 = math.ceil(requested.col_off + requested.width)
        y1 = math.ceil(requested.row_off + requested.height)
        window = Window(x0, y0, x1 - x0, y1 - y0)
        values = dataset.read(1, window=window)
        profile = dataset.profile.copy()
        profile.update(width=window.width, height=window.height,
                       transform=dataset.window_transform(window), tiled=False,
                       compress="deflate")
        profile.pop("blockxsize", None)
        profile.pop("blockysize", None)
        with rasterio.open(crop, "w", **profile) as target:
            target.write(values, 1)
            target.update_tags(reference_only="DSM_NOT_WALKABLE_GROUND",
                source_url=DSM_URL, vertical_datum="EGM2008 (EPSG:3855)", elevation_unit="m")
        transform = list(dataset.transform)[:6]
    write_json(report, {"provider": "Copernicus / DLR / Airbus; AWS mirror by Sinergise",
        "started_at_utc": started, "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_url": DSM_URL, "response_headers": headers, "source_artifact": describe(source),
        "regional_artifact": describe(crop), "request_bbox_west_south_east_north": BBOX,
        "horizontal_crs": "EPSG:4326", "vertical_datum": "EGM2008 (EPSG:3855)",
        "vertical_datum_basis": "Copernicus DEM Product Handbook 5.0",
        "handbook_url": "https://dataspace.copernicus.eu/sites/default/files/media/files/2024-06/geo1988-copernicusdem-spe-002_producthandbook_i5.0.pdf",
        "mirror_release_basis": "AWS registry describes the 2021 release; per-pixel dates unknown",
        "license_url": "https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf",
        "registry_url": "https://registry.opendata.aws/copernicus-dem/",
        "source_transform": transform, "crop_window": [x0, y0, x1 - x0, y1 - y0],
        "crop_policy": "Native pixels enclosing bbox, no interpolation or height conversion",
        "tool_version": importlib.metadata.version("rasterio"),
        "limitations": ["DSM includes buildings and vegetation; not bare-earth terrain",
            "Nominal 30m resolution cannot establish thresholds, stairs or road level",
            "Do not use as the walkable game ground or subtract it from building heights",
            "Local SHA-256 and complete HTTP length; no provider checksum obtained"]})
    print(json.dumps({"result": "received_reference_only", **describe(crop)}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=["overture", "dsm"])
    parser.add_argument("--release", default=RELEASE)
    args = parser.parse_args()
    if args.source == "overture":
        acquire_overture(args.release)
    else:
        acquire_dsm()


if __name__ == "__main__":
    main()

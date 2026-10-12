"""Fixed G01 horizontal/local coordinate contract; no elevation conversion."""
from __future__ import annotations

import json
import math
from pathlib import Path

from pyproj import CRS, Transformer

ROOT = Path(__file__).resolve().parents[1]


def finite(*values):
    if not all(math.isfinite(value) for value in values):
        raise ValueError("Coordinates must be finite")


class CoordinateSystem:
    def __init__(self, config_path=None):
        self.config_path = Path(config_path) if config_path else ROOT / "config/region.json"
        self.config = json.loads(self.config_path.read_text())
        c = self.config
        if (c["source_crs"] != "EPSG:4326" or c["metric_crs"] != "EPSG:32652"
                or c["world_axes"] != {"x": "east", "y": "up", "z": "south"}
                or c["meters_per_world_unit"] != 1.0
                or c["coordinate_contract_version"] != 1):
            raise ValueError("Unsupported coordinate contract: migrate all assets before changing CRS/axes/units")
        self.source_crs = CRS.from_user_input(c["source_crs"])
        self.metric_crs = CRS.from_user_input(c["metric_crs"])
        self.forward = Transformer.from_crs(self.source_crs, self.metric_crs, always_xy=True,
                                           allow_ballpark=False)
        self.inverse = Transformer.from_crs(self.metric_crs, self.source_crs, always_xy=True,
                                           allow_ballpark=False)
        self.origin_lon_lat = tuple(c["origin_lon_lat"])
        self.origin_east_north = self.project(*self.origin_lon_lat)

    def project(self, lon, lat):
        finite(lon, lat)
        if not (-180 <= lon <= 180 and -90 <= lat <= 90):
            raise ValueError("Expected longitude, latitude in degrees")
        east, north = self.forward.transform(lon, lat, errcheck=True)
        finite(east, north)
        return east, north

    def projected_to_world(self, east, north, local_height_m=0.0):
        finite(east, north, local_height_m)
        return (east - self.origin_east_north[0], local_height_m,
                -(north - self.origin_east_north[1]))

    def to_world(self, lon, lat, local_height_m=0.0):
        return self.projected_to_world(*self.project(lon, lat), local_height_m)

    def world_to_projected(self, x, y, z):
        finite(x, y, z)
        return self.origin_east_north[0] + x, self.origin_east_north[1] - z

    def to_lon_lat(self, x, y, z):
        """Return horizontal coordinates only; y has no geodetic datum conversion."""
        lon, lat = self.inverse.transform(*self.world_to_projected(x, y, z), errcheck=True)
        finite(lon, lat)
        return lon, lat

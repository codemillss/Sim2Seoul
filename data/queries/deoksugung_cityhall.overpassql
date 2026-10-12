// Temporary investigation bbox, not the final playable boundary.
// South, west, north, east. Query returns complete geometries of matching objects.
// Objects crossing the bbox can extend outside it. Inspect before clipping.
// Data: OpenStreetMap contributors, ODbL https://www.openstreetmap.org/copyright
// This query has not yet produced a successfully downloaded and audited extract.
[out:json][timeout:30][maxsize:33554432];
(
  nwr["building"](37.5608,126.9710,37.5694,126.9815);
  way["building:part"](37.5608,126.9710,37.5694,126.9815);
  nwr["highway"](37.5608,126.9710,37.5694,126.9815);
  nwr["barrier"](37.5608,126.9710,37.5694,126.9815);
  nwr["historic"](37.5608,126.9710,37.5694,126.9815);
  nwr["leisure"](37.5608,126.9710,37.5694,126.9815);
  nwr["landuse"](37.5608,126.9710,37.5694,126.9815);
);
out body geom;

#!/usr/bin/env python3
"""Measure retained footprints and spacing; units alone are not visual acceptance."""
from pathlib import Path
import collections, hashlib, json, math
from shapely.geometry import shape, MultiPoint, box
from shapely import transform
from pyproj import Geod, Transformer

ROOT = Path(__file__).resolve().parents[1]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def audit():
    source_path = ROOT/'data/processed/features.json'
    world_path = ROOT/'game/resources/world_geometry/world.json'
    sources = json.loads(source_path.read_text())
    world = json.loads(world_path.read_text())
    by_id = {f['feature_id']: f for f in sources['features']}
    geod = Geod(ellps='WGS84')
    projection=Transformer.from_crs('EPSG:4326','EPSG:32652',always_xy=True)
    origin=world['coordinate_system']['origin_projected_east_north_m']
    def project(lon,lat):
        east,north=projection.transform(lon,lat)
        return east-origin[0], origin[1]-north
    rows, shapes, errors = [], [], []
    for entry in world['meshes']:
        if entry['role'] != 'Buildings': continue
        feature = by_id[entry['id']]
        footprint = shape(feature['geometry'])
        xyz = entry['vertices']
        emitted = MultiPoint([(xyz[i],xyz[i+2]) for i in range(0,len(xyz),3)]).convex_hull
        bounds = footprint.bounds
        rectangle=list(footprint.minimum_rotated_rectangle.exterior.coords)
        rectangle_edges=[math.dist(rectangle[i],rectangle[i+1]) for i in range(4)]
        bounds_error = max(abs(a-b) for a,b in zip(bounds,emitted.bounds))
        # Convex hull only compares emitted extents. Full concave/hole fidelity
        # remains the retained polygon, not the hull used for bounds here.
        original = shape(feature['source_geometry']['geometry'])
        original_polys = list(original.geoms) if hasattr(original,'geoms') else [original]
        projection_error=transform(original,project,interleaved=False).hausdorff_distance(footprint)
        ratios=[]
        for geo in original_polys:
            b=list(geo.exterior.coords)
            for i in range(len(b)-1):
                length=math.dist(project(*b[i]),project(*b[i+1])); _,_,metres=geod.inv(*b[i],*b[i+1])
                if metres>0.5: ratios.append(length/metres)
        row={'id':entry['id'],'name':entry['metadata'].get('name',''),
             'width_x_m':bounds[2]-bounds[0],'depth_z_m':bounds[3]-bounds[1],
             'xz_aspect':(bounds[2]-bounds[0])/max(.001,bounds[3]-bounds[1]),
             'oriented_envelope_long_m':max(rectangle_edges),
             'oriented_envelope_short_m':min(rectangle_edges),
             'area_m2':footprint.area,'emitted_extent_error_m':bounds_error,
             'source_reprojection_hausdorff_error_m':projection_error,
             'height_m':entry['top_y_m']-entry['bottom_y_m'],
             'height_basis':entry['metadata']['height_class'],
             'projected_vs_source_geodesic_ratio_range':[min(ratios),max(ratios)] if ratios else None}
        if bounds_error>0.00001 or projection_error>0.001 or any(abs(v-1)>.002 for v in ratios):
            errors.append({'id':entry['id'],'extent_error':bounds_error,'projection_error':projection_error,'geodesic_ratios':ratios})
        rows.append(row);shapes.append(footprint)
    for i,g in enumerate(shapes):
        distances=[(g.distance(h),j) for j,h in enumerate(shapes) if j!=i]
        distance,j=min(distances)
        rows[i]['nearest_source_building']={'id':rows[j]['id'],'gap_m':distance,
            'overlap_area_m2':g.intersection(shapes[j]).area}
    report={'schema_version':1,'task':'EXP28_REAL_SCALE_AUDIT','result':'PASS' if not errors else 'FAIL',
        'inputs':{'world_sha256':sha(world_path),'source_features_sha256':sha(source_path),
                  'auditor_sha256':sha(Path(__file__))},
        'source_buildings':len(rows),'height_basis_counts':dict(collections.Counter(r['height_basis'] for r in rows)),
        'extent_errors':errors,'buildings':rows,
        'scope':'Source geodesic edges, all emitted original XZ extents and pair spacing. This is not independent survey accuracy, replacement-landmark visible bounds, runtime collision placement, camera appearance, or proof of surveyed heights.'}
    target=ROOT/'data/reports/real_scale/20261022/source_audit.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['result','source_buildings','height_basis_counts','extent_errors']},ensure_ascii=False))
    reference={'schema_version':1,'world_sha256':sha(world_path),'unit':'metre',
        'accuracy':'Original source footprints and estimates, not an independent survey.',
        'buildings':[dict(row,rings=[list(poly.exterior.coords) for poly in (list(g.geoms) if hasattr(g,'geoms') else [g])]) for row,g in zip(rows,shapes)]}
    (ROOT/'game/assets/authored/city_metric_reference.json').write_text(json.dumps(reference,ensure_ascii=False,separators=(',',':'))+'\n')
    # User-authorised fictional hospital at a retained construction parcel.
    parcel=by_id['osm:way:1216911414:land_area']; footprint=box(241,358,289,392)
    if not shape(parcel['geometry']).covers(footprint): raise ValueError('Hospital footprint outside named source parcel')
    conflicts=[]
    for f in sources['features']:
        if f['source_kind'] in ['building','building_part','highway_line','highway_area','barrier','barrier_area'] or f['source_tags'].get('access') in ['private','no']:
            if shape(f['geometry']).intersects(footprint.buffer(1)): conflicts.append(f['feature_id'])
    if conflicts: raise ValueError(f'Hospital original geometry conflicts: {conflicts}')
    design={'schema_version':1,'task':'EXP28_GAME_HOSPITAL','source_world_sha256':sha(world_path),
        'title':'서울시티 종합병원','fictional':True,'center_xz_m':[265,375],
        'footprint_xz_m':[[241,358],[289,358],[289,392],[241,392]],
        'width_x_m':48,'depth_z_m':34,'height_m':44,'floor_count':12,
        'ground_floor_height_m':4.4,'upper_floor_height_m':3.6,
        'door_width_m':2.4,'door_height_m':2.4,'entry_outward_xz':[1,0],
        'source_parcel_id':parcel['feature_id'],'source_parcel_tags':parcel['source_tags'],
        'source_refs':parcel['source_refs'],'original_geometry_conflicts':conflicts,
        'approach_scope':'The main building footprint is inside the named construction parcel. Two bounded entrance ramps extend onto adjacent non-private native-supported game ground; original buildings/roads/footways/barriers remain intact.',
        'scope':'User-authorised fictional large hospital, realistic metre dimensions; no claim of an actual Seoul hospital, surveyed plan, clinical service, or inferred original building height.'}
    (ROOT/'game/assets/authored/city_hospital.json').write_text(json.dumps(design,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':audit()

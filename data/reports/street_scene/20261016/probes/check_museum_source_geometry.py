import json, hashlib, math, datetime
from pathlib import Path
from shapely.geometry import LineString, Point, Polygon, shape
from shapely.ops import substring
root=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul')
features=json.loads((root/'data/processed/features.json').read_text())['features']
design=json.loads((root/'game/assets/authored/museum_approach.json').read_text())
source=next(x for x in features if x['feature_id']==design['source']['feature_id'])
line=LineString(source['geometry']['coordinates']); used=substring(line,0,90)
footprint=used.buffer(3.6,cap_style=2,join_style=2)
a,b=used.interpolate(41.99),used.interpolate(42.01)
tx,tz=(b.x-a.x)/a.distance(b),(b.y-a.y)/a.distance(b)
sx,sz=tz,-tx
at=used.interpolate(42);cx,cz=at.x-sx*4.6,at.y-sz*4.6
terrace=Polygon([(cx+sx*x+tx*z,cz+sz*x+tz*z) for x,z in [(-3,-3),(3,-3),(3,3),(-3,3)]])
conflicts=[];roads=[]; minimum_building=(1e9,None)
for item in features:
 try:g=shape({k:v for k,v in item['geometry'].items() if k in ('type','coordinates','geometries')})
 except Exception:continue
 if item['source_kind'] in ('building','building_part','barrier','barrier_area'):
  if footprint.intersects(g) or terrace.intersects(g):conflicts.append(item['feature_id'])
  if item['kind']=='building':minimum_building=min(minimum_building,(footprint.union(terrace).distance(g),item['feature_id']))
 if item['kind']=='road':roads.append((item['feature_id'],terrace.distance(g),footprint.distance(g)))
door=Point(design['design']['museum_flat_door_xz'])
checks=[{'name':'all_nine_XZ_vertices_equal_current_source','passed':source['geometry']['coordinates']==design['source']['xz']}, {'name':'no_new_terrain_or_terrace_intersects_source_building_parts_or_barriers','passed':not conflicts}, {'name':'authored_90m_end_leaves_over_6m_source_footway_flat','passed':line.length-90>6}, {'name':'new_terrain_stays_over_6m_from_original_flat_door','passed':footprint.union(terrace).distance(door)>6}]
report={'task':'museum_source_geometry','timestamp':datetime.datetime.now().isoformat(),'scope':'Source snapshot geometry comparison only; no surveyed horizontal accuracy, access, vertical datum or real grades asserted. Road widths are not surveyed by this check.','source_hashes':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['data/processed/features.json','game/resources/world_geometry/world.json','game/assets/authored/museum_approach.json','game/scripts/museum_approach.gd']},'checks':checks,'source_route_length_m':line.length,'flat_source_footway_after_authored_hill_m':line.length-90,'terrain_buffer_width_m':7.2,'terrace_corners':list(terrace.exterior.coords),'terrace_centre':[cx,3,cz],'minimum_source_building_distance_m':minimum_building,'original_flat_door_clearance_m':footprint.union(terrace).distance(door),'source_building_barrier_intersections':conflicts,'nearest_road_to_terrace':sorted(roads,key=lambda x:x[1])[:3], 'result':'PASS' if all(c['passed'] for c in checks) else 'FAIL'}
Path('/private/tmp/museum_source_geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:report[k] for k in ['checks','minimum_source_building_distance_m','original_flat_door_clearance_m','nearest_road_to_terrace','result']},ensure_ascii=False,indent=2))

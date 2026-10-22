import json,hashlib
from pathlib import Path
from shapely.geometry import shape,box,Point
root=Path.cwd(); features=json.loads((root/'data/processed/features.json').read_text())['features']; trees=json.loads((root/'game/assets/authored/neighborhood_greenery.json').read_text())['trees']
parts={'building':box(-135,-431,-105,-409),'entry_ramp':box(-122,-409,-118,-402),'campus_reserve':box(-140,-435,-100,-405)}
checks={}
for name,geom in parts.items():
 checks[name]={'bounds_xz':list(geom.bounds),'source_obstacle_intersections':[],'tree_centres_within4m':[]}
 for row in features:
  if row['kind'] in ['building','barrier','highway_line','highway_area'] and shape(row['geometry']).intersects(geom):checks[name]['source_obstacle_intersections'].append(row['feature_id'])
 for row in trees:
  if geom.distance(Point(row['xz']))<4:checks[name]['tree_centres_within4m'].append(row['id'])
assert all(not row['source_obstacle_intersections'] and not row['tree_centres_within4m'] for row in checks.values())
paths=['game/resources/world_geometry/world.json','data/processed/features.json','game/assets/authored/neighborhood_greenery.json']
a={'schema_version':1,'task':'EXP28_GAME_SCALE_POLICE_HEADQUARTERS','name':'서울 생활안전 경찰청사','subtitle':'게임용 가상 기관 · 실제 경찰서 위치 아님','center_xz':[-120,-420],'width_m':30,'depth_m':22,'floor_height_m':3.9,'floors':4,'height_m':15.6,'door_width_m':3.2,'door_height_m':2.6,'lobby_m2':660,'ramp_xz':[[-120,-409],[-120,-402]],'ramp_width_m':4,'parked_car_xz':[-138,-421],'source_inputs':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths},'source_clearance_certificate':checks,'scope':'User-authorized fictional full-size civic campus inside existing world bounds on unchanged non-private native TIN. No real Seoul institution identity, actual plan, cadastral access, present-day building height or parking claim. Ground public lobby is directly walkable through a native automatic door; upper floors are visual staff offices, not invented public access.'}
(root/'game/assets/authored/police_headquarters.json').write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
print('HQ design source clear',checks)

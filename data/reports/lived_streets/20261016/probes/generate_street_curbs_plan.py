import json,math,hashlib,collections
from pathlib import Path
from shapely.geometry import Polygon,LineString,Point,box,shape
from shapely.ops import unary_union
from shapely import set_precision
R=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul')
w=json.loads((R/'game/resources/world_geometry/world.json').read_text()); f=json.loads((R/'data/processed/features.json').read_text())['features']; public=json.loads((R/'game/data/generated/public_walk.json').read_text()); doors=json.loads((R/'game/assets/authored/interiors/source_catalog.json').read_text())['records']; traffic=json.loads((R/'game/data/generated/traffic.json').read_text()); npcs=json.loads((R/'game/data/generated/pedestrians.json').read_text()); hill=json.loads((R/'game/assets/authored/museum_approach.json').read_text())
def tri_area(material):
 triangles=[]
 for m in w['meshes']:
  if m['role']!='Routes' or m['material']!=material:continue
  v=m['vertices']
  for i in range(0,len(v),9):
   p=Polygon([(v[i],v[i+2]),(v[i+3],v[i+5]),(v[i+6],v[i+8])])
   if p.is_valid and p.area>1e-9:triangles.append(set_precision(p,.001))
 return unary_union(triangles)
def geom(raw):return shape({k:v for k,v in raw.items() if k in ('type','coordinates','geometries')})
drive=tri_area('drive'); walk=tri_area('walk'); region=box(-449.6,-459.6,449.6,459.6)
road_edge=drive.buffer(.20,join_style=2).boundary.intersection(region)
source_footpaths=[geom(i['geometry']) for i in f if i['kind']=='footpath']
source_footpath_protection=unary_union(source_footpaths).buffer(1.5)
walk_route_protection=unary_union([LineString(r['xz']) for r in public['routes']]).buffer(1.5)
npc_protection=unary_union([LineString(r['xz']) for r in npcs['routes']]).buffer(.65)
traffic_protection=unary_union([shape(r['swept_geometry']) for r in traffic['routes']]).buffer(.25)
entry_lines=[];entries=0
for record in doors:
 for e in record['entry_candidates']:
  a=e['entrance'];v=e['outward'];entry_lines.append(LineString([e['door'],a,[a[0]+v[0]*5,a[1]+v[1]*5]]).buffer(max(1.2,float(e['door_width'])/2)+.3));entries+=1
entrance_protection=unary_union(entry_lines)
source_solids=unary_union([geom(i['geometry']) for i in f if i['source_kind'] in ('building','building_part','barrier','barrier_area')]).buffer(.35)
crossing_protection=unary_union([unary_union([shape(c['geometry']),LineString(c['source_xz']).buffer(1.5)]) for c in public['crossings']]).buffer(.5)
private_protection=shape({'type':'MultiPolygon','coordinates':public['private_rings']}).buffer(.4)
from shapely.ops import substring
hill_line=substring(LineString(hill['source']['xz']),0,90);hill_protection=hill_line.buffer(4.6)
p=hill_line.interpolate(42);a=hill_line.interpolate(41.99);b=hill_line.interpolate(42.01);t=((b.x-a.x)/a.distance(b),(b.y-a.y)/a.distance(b));s=(t[1],-t[0]);c=(p.x-s[0]*4.6,p.y-s[1]*4.6)
hill_protection=hill_protection.union(Polygon([(c[0]+s[0]*x+t[0]*z,c[1]+s[1]*x+t[1]*z) for x,z in [(-3,-3),(3,-3),(3,3),(-3,3)]]).buffer(1))
protected={'source_footpaths':source_footpath_protection,'public_walking_routes':walk_route_protection,'NPC_routes':npc_protection,'traffic_swept':traffic_protection,'all_704_entrance_candidates':entrance_protection,'source_buildings_parts_barriers':source_solids,'all_3_W03_crossings':crossing_protection,'private_exclusions':private_protection,'authored_SeMA_hill':hill_protection}
protection=unary_union(list(protected.values()))
footprint_radius=2.4
clear=road_edge.intersection(walk.buffer(1.5)).difference(protection.buffer(footprint_radius))
def lines(g):
 if g.geom_type=='LineString':return [g]
 if hasattr(g,'geoms'):return [x for z in g.geoms for x in lines(z)]
 return []
lines_clear=[l for l in lines(clear) if l.length>=4.]
result={"drive_meshes":sum(m['material']=='drive' for m in w['meshes']),"walk_meshes":sum(m['material']=='walk' for m in w['meshes']),"drive_union_area_m2":drive.area,"all_road_edge_length_m":road_edge.length,"source_footpaths":len(source_footpaths),"public_routes":len(public['routes']),"door_buildings":len(doors),"entry_candidates":entries,"candidate_band_radius_m":footprint_radius,"protection_lengths_scope":"Clear edge centreline buffered 2.4m after removing every protection geometry; static source plan only, live prop/capsule checks still required.","global_candidates":{"pieces":len(lines_clear),"length_m":sum(l.length for l in lines_clear)},"first_zones":{}}
for rid in ['stonewall','city_plaza']:
 route=next(r for r in public['routes'] if r['id']==rid);centre=LineString(route['xz']);zone=centre.buffer(25)
 ls=[l for part in lines_clear for l in lines(part.intersection(zone)) if l.length>=4.]
 footprint=unary_union([l.buffer(footprint_radius) for l in ls])
 result['first_zones'][rid]={"pieces":len(ls),"length_m":sum(l.length for l in ls),"route_bounds":list(centre.bounds),"coordinates":[list(l.coords) for l in ls],"footprint_clearance_proofs":{k:footprint.intersection(g).area for k,g in protected.items()},"minimum_static_protected_distance_m":min([l.distance(protection) for l in ls],default=None)}
result['source_hashes']={p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in ['game/resources/world_geometry/world.json','data/processed/features.json','game/data/generated/public_walk.json','game/data/generated/traffic.json','game/assets/authored/interiors/source_catalog.json','game/assets/authored/museum_approach.json']}
Path('/private/tmp/curb_feasibility.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='first_zones'},ensure_ascii=False,indent=2))
for k,v in result['first_zones'].items():print(k,{x:y for x,y in v.items() if x!='coordinates'})

from shapely.ops import linemerge
crossings_all=unary_union([g.intersection(drive.boundary) for g in source_footpaths]).buffer(1.8)
protected['source_footpaths']=crossings_all
protected['all_source_footpath_drive_crossings']=protected.pop('source_footpaths')
protection=unary_union(list(protected.values()))
edge=drive.buffer(.9,join_style=2).boundary.intersection(region)
clear=edge.intersection(walk.buffer(2.)).difference(protection.buffer(.85))
zone=unary_union([LineString(next(r for r in public['routes'] if r['id']==rid)['xz']).buffer(40) for rid in ['stonewall','city_plaza']])
parts=[l for l in lines(clear.intersection(zone)) if l.length>=4.]
print('BATCH',len(parts),sum(x.length for x in parts))
print([(round(l.length,1),tuple(round(x,1) for x in l.bounds)) for l in parts])
footprint=unary_union([l.buffer(.85) for l in parts])
print('clearproof', {k:round(footprint.intersection(g).area,8) for k,g in protected.items()})
drive_sources=[]
for m in w['meshes']:
 if m['material']!='drive':continue
 vs=m['vertices'];ts=[]
 for i in range(0,len(vs),9):
  q=Polygon([(vs[i],vs[i+2]),(vs[i+3],vs[i+5]),(vs[i+6],vs[i+8])])
  if q.is_valid:ts.append(q)
 drive_sources.append((m['metadata']['feature_id'],unary_union(ts)))
records=[]
for index,l in enumerate(sorted(parts,key=lambda x:(x.bounds[0],x.bounds[1]))):
 a=l.interpolate(max(0,l.length/2-.05));b=l.interpolate(min(l.length,l.length/2+.05));tx,tz=(b.x-a.x)/a.distance(b),(b.y-a.y)/a.distance(b);sx,sz=tz,-tx;p=l.interpolate(l.length/2)
 sign=1 if Point(p.x+sx*.2,p.y+sz*.2).distance(drive)<Point(p.x-sx*.2,p.y-sz*.2).distance(drive) else -1
 bindings=[fid for fid,g in drive_sources if l.distance(g)<1.3]
 records.append({'id':'curb_%02d'%(index+1),'xz':[[round(x,6),round(z,6)] for x,z in l.coords],'length_m':l.length,'roadside_sign':sign,'source_drive_features':bindings,'static_protection_clearance_m':l.distance(protection)})
paths=['game/resources/world_geometry/world.json','game/data/generated/public_walk.json','game/data/generated/traffic.json','game/data/generated/pedestrians.json','game/assets/authored/interiors/source_catalog.json','game/assets/authored/museum_approach.json']
output={'schema_version':1,'id':'central_authored_curbs_v1','title':'덕수궁·서울광장 게임용 입체 연석','scope':{'placement':'0.9m outside the union boundary of current game drive meshes, near existing walk surfaces and within40m of stonewall/city_plaza routes','widths':'current game display widths; many are G04 estimates, not surveyed road or curb edges','height':'authored game geometry, not surveyed kerb heights','physical_terrain_verified':False,'source_geometry_modified':False,'city_sidewalks_raised':False,'note':'Bounded beveled boundary bands; all existing Y0 ground, road support, NPC tracks and entrances remain unchanged.'},'source_hashes':{'res://'+p.removeprefix('game/'):hashlib.sha256((R/p).read_bytes()).hexdigest() for p in paths},'source_features_sha256':hashlib.sha256((R/'data/processed/features.json').read_bytes()).hexdigest(),'design':{'height_m':.12,'width_m':1.4,'flat_top_width_m':.3,'end_fade_length_m':1.2,'sample_spacing_m':.8,'bottom_y_m':-.15,'drive_edge_offset_m':.9,'proven_footprint_radius_m':.85,'minimum_segment_length_m':4.,'maximum_cross_grade':.12/.55,'maximum_end_grade':.12*1.5/1.2},'protection':{'source_drive_meshes':180,'source_walk_meshes':190,'existing_public_routes':5,'NPC_routes':2,'traffic_routes':2,'named_crossings':3,'source_footpath_crossing_inputs':275,'door_buildings':125,'entrance_candidates':704,'entrance_corridor':'Every source door to entrance plus5m outward, half-width max(1.2,door_width/2)+.3m; further .85m curb footprint guard.','walk_corridor_half_width_m':1.5,'crossing_radius_m':1.8,'source_solid_clearance_m':.35,'protected_static_intersection_area_m2':{k:footprint.intersection(g).area for k,g in protected.items()},'live_props':'At setup, reject a whole segment if an above-ground volume sweep meets existing static props/buildings or NPC/car bodies; source actor routes are additionally excluded by the static plan.'},'named_flat_cuts':[{'id':c['id'],'source_xz':c['source_xz'],'flat_y_m':0.0} for c in public['crossings']],'segments':records,'planned_segment_count':len(records),'planned_length_m':sum(x['length_m'] for x in records)}
(R/'game/assets/authored/street_curbs.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
Path('/private/tmp/street_curbs_source_proof.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
print('WROTE',len(records),output['planned_length_m'])

#!/usr/bin/env python3
"""Small OSM-derived street coverage layer; source/world geometry stays untouched."""
import argparse,hashlib,json,math
from pathlib import Path
import osmium
from pyproj import Transformer
from shapely.geometry import Point,LineString,Polygon,MultiPolygon,shape,box,mapping
from shapely.ops import unary_union,substring
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
def read(p):return json.loads((ROOT/p).read_text())
def sha(p):return hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
def lines(g):
 if g.geom_type=='LineString':return [g]
 if hasattr(g,'geoms'):return [q for v in g.geoms for q in lines(v)]
 return []
def flat_polys(rings):return MultiPolygon([Polygon(p[0],p[1:]) for p in rings])
features=read('data/processed/features.json')['features'];byid={f['feature_id']:f for f in features}
world=read('game/resources/world_geometry/world.json');public=read('game/data/generated/public_walk.json')
bounds=box(-430,-440,430,440)
build_ids={m['metadata']['feature_id'] for m in world['meshes'] if m['role']=='Buildings'}
build=unary_union([shape(byid[i]['geometry']) for i in build_ids if i in byid])
# Walls have authored native widths in the actual world mesh; a fixed .25m
# source-line buffer can falsely certify a narrow path inside a thick wall.
barrier_parts=[]
for mesh in world['meshes']:
 if mesh['role']!='Barriers':continue
 vertices=mesh['vertices']
 for k in range(0,len(vertices),9):
  triangle=Polygon([(vertices[k],vertices[k+2]),(vertices[k+3],vertices[k+5]),(vertices[k+6],vertices[k+8])])
  if triangle.area>1e-7:barrier_parts.append(triangle)
barriers=unary_union(barrier_parts)
private=flat_polys(public['private_rings'])
road_parts=[];road_byid={}
for m in world['meshes']:
 if m['metadata'].get('display_mode')!='drive':continue
 v=m['vertices'];ps=[]
 for k in range(0,len(v),9):
  t=Polygon([(v[k],v[k+2]),(v[k+3],v[k+5]),(v[k+6],v[k+8])])
  if t.area>1e-7:ps.append(t)
 if ps:road_byid[m['metadata']['feature_id']]=unary_union(ps);road_parts+=ps
roads=unary_union(road_parts)
old=read('game/assets/authored/street_pedestrians.json');old_lines=[]
for r in old['routes']:
 if 'source_segment' in r:
  route=next(q for q in public['routes'] if q['id']==r['source_route']);i,j=r['source_segment'];line=LineString([route['xz'][i],route['xz'][j]]);old_lines.append(substring(line,line.length*r['fractions'][0],line.length*r['fractions'][1]))
old_union=unary_union(old_lines)
# Produce ten independent source-walk corridors; cut out roads and solid source footprints.
walk_sources=[f for f in features if f['source_kind']=='highway_line' and f['source_tags'].get('highway') in ['footway','pedestrian','path'] and f['source_tags'].get('access') not in ['private','no']]
walk_mask=build.buffer(.85).union(barriers.buffer(.50)).union(roads.buffer(.75)).union(private.buffer(.5))
candidates=[]
for f in walk_sources:
 g=shape(f['geometry']).intersection(bounds).difference(walk_mask)
 for part in lines(g):
  if part.length<19:continue
  if old_union.distance(part)<6:continue
  for start in range(0,max(1,int(part.length)-18),55):
   segment=substring(part,start,min(part.length,start+65))
   if segment.length<19:continue
   c=segment.interpolate(.5,normalized=True);candidates.append((segment,f,c))
chosen=[]
while candidates and len(chosen)<10:
 def score(item):
  line,f,c=item;separation=min([c.distance(q[2]) for q in chosen]) if chosen else 130;return min(line.length,55)+separation*1.5
 best=max(candidates,key=score);chosen.append(best)
 candidates=[c for c in candidates if c[2].distance(best[2])>65]
walk_records=[]
for i,(line,f,c) in enumerate(chosen):
 for n in range(2):
  color=[[.28,.41,.55],[.66,.39,.22],[.37,.51,.39],[.68,.61,.48],[.48,.37,.53]][(i+n)%5]
  walk_records.append({'id':f'coverage_walk_{i:02}_{n}','source_feature_id':f['feature_id'],'source_refs':f['source_refs'],'xz':[list(p)for p in line.coords],'side_offset_m':0.,'initial_fraction':.24 if n==0 else .76,'direction':1 if n==0 else -1,'dog':False,'clothing':color,'coverage_sector':i,'authored_initial_phase':True})
class Nodes(osmium.SimpleHandler):
 def __init__(self):super().__init__();self.trees=[];self.crossings=[]
 def node(self,n):
  if n.tags.get('natural')=='tree':self.trees.append((n.id,n.location.lon,n.location.lat,dict(n.tags)))
  if n.tags.get('highway')=='crossing':self.crossings.append((n.id,n.location.lon,n.location.lat,dict(n.tags)))
nodes=Nodes();nodes.apply_file(str(ROOT/'data/raw/deoksugung_cityhall-v2.osm.pbf'))
region=read('config/region.json');tr=Transformer.from_crs(4326,32652,always_xy=True);ox,oy=tr.transform(*region['origin_lon_lat'])
def xz(lon,lat):x,y=tr.transform(lon,lat);return[x-ox,oy-y]
crossings=[{'id':str(i),'xz':xz(x,y),'tags':t}for i,x,y,t in nodes.crossings]
public_lines=unary_union([LineString(r['xz'])for r in public['routes']]);new_walks=unary_union([q[0]for q in chosen]);foot_lines=unary_union([shape(f['geometry'])for f in walk_sources])
entries=read('game/assets/authored/interiors/source_catalog.json')['records'];doors=[Point(e['entrance']) for b in entries for e in b['entry_candidates']]
entry_corridors=[]
for building in entries:
 for entry in building['entry_candidates']:
  x,z=entry['entrance'];dx,dz=entry['outward']
  half_width=max(1.2,float(entry['door_width'])*.5)+.3+.35+.17+.02
  entry_corridors.append(LineString([(x,z),(x+dx*5,z+dz*5)]).buffer(half_width))
protected_entries=unary_union(entry_corridors)
build_clear=build.buffer(.65);barrier_clear=barriers.buffer(.65);road_clear=roads.buffer(.45)
protected_walks=public_lines.buffer(.80).union(new_walks.buffer(.80)).union(foot_lines.buffer(.65))
tree_records=[];tree_rejections=[]
def tree_allowed(p,source_point=False):
 if not bounds.contains(p):return 'outside_game_bounds'
 if build_clear.intersects(p):return 'source_building_footprint_clearance'
 if barrier_clear.intersects(p):return 'source_barrier_clearance'
 if private.intersects(p):return 'source_private_ground'
 if road_clear.intersects(p):return 'source_driving_area_trunk_clearance'
 if protected_walks.intersects(p):return 'protected_existing_or_new_walk_centre'
 # A mapped tree in an outdoor park/plaza need not sit next to a mapped
 # footway. Actual public game floor is separately ray-tested at runtime.
 if not source_point and foot_lines.distance(p)>9:return 'not_source_footway_edge'
 if protected_entries.intersects(p):return 'source_door_approach_0_to_5m'
 if min([p.distance(Point(q['xz']))for q in crossings]+[100])<5:return 'crossing_sightline'
 return ''
for i,lon,lat,tags in nodes.trees:
 point=Point(xz(lon,lat));reason=tree_allowed(point,True)
 if reason:tree_rejections.append({'id':f'osm:node:{i}','reason':reason});continue
 tree_records.append({'id':f'osm:node:{i}:tree','xz':list(point.coords)[0],'basis':'source_natural_tree_node','source_node_id':i,'source_lon_lat':[lon,lat],'tags':tags,'height_m':5.7,'canopy_bottom_m':2.65})
# Fill sparse street stretches with labelled game trees on source footway edges.
fill=[]
for f in walk_sources:
 line=shape(f['geometry'])
 if line.geom_type!='LineString' or line.length<25:continue
 for station in range(10,int(line.length)-7,13):
  p=line.interpolate(station);a=line.interpolate(max(0,station-.1));b=line.interpolate(min(line.length,station+.1));dx,dy=b.x-a.x,b.y-a.y;l=math.hypot(dx,dy)
  if l<.01:continue
  for sign in [-1,1]:
   q=Point(p.x+sign*dy/l*2.3,p.y-sign*dx/l*2.3)
   if tree_allowed(q):continue
   if min([q.distance(Point(r['xz']))for r in tree_records]+[100])<7:continue
   fill.append((q,f,station,sign))
selected_fill=[]
while fill and len(selected_fill)<48:
 best=max(fill,key=lambda r:min([r[0].distance(q[0])for q in selected_fill]+[120]));selected_fill.append(best);fill=[r for r in fill if r[0].distance(best[0])>10]
for i,(q,f,station,sign)in enumerate(selected_fill):tree_records.append({'id':f'authored_street_tree_{i:02}','xz':list(q.coords)[0],'basis':'authored_source_footway_edge_fill','source_feature_id':f['feature_id'],'source_station_m':station,'side_offset_m':sign*2.3,'height_m':5.3+(i%3)*.35,'canopy_bottom_m':2.65})
provenance={p:sha(p)for p in ['data/raw/deoksugung_cityhall-v2.osm.pbf','data/processed/features.json','game/resources/world_geometry/world.json','game/data/generated/public_walk.json','config/region.json']}
# New source-forward road coverage, outside the original central two traffic streams.
vehicle_records=[]
for i,fid in enumerate(['osm:way:620634303:highway_line','osm:way:899373686:highway_line','osm:way:469260694:highway_line','osm:way:218923160:highway_line']):
 f=byid[fid];line=shape(f['geometry']).intersection(bounds)
 if line.geom_type!='LineString':line=max(lines(line),key=lambda q:q.length)
 line=substring(line,8,line.length-8);domain=road_byid[fid]
 # Keep source forward direction; 0m centre offset is a game lane assumption.
 # The 1.8x4.2m actual car footprint must fit the source-derived display road.
 conflicts=[];near=[]
 for cross in crossings:
  p=Point(cross['xz'])
  if line.distance(p)<4.5:
   station=line.project(p)
   if 10<station<line.length-10:near.append((station,cross['id'],cross['xz']))
 for s,cid,c in sorted(near):
  if conflicts and s-conflicts[-1]['enter_s_m']<9:continue
  conflicts.append({'crossing_id':'coverage_'+cid,'enter_s_m':max(0,s-3.4),'exit_s_m':min(line.length,s+3.4),'stop_s_m':max(0,s-11.1),'stop_xz':list(line.interpolate(max(0,s-11.1)).coords)[0],'stopping_distance_m':7.7,'center_xz':c})
 vehicle_records.append({'id':f'coverage_drive_{i}','name':f['source_tags'].get('name',fid),'xz':[list(q)for q in line.coords],'ground_y_m':0.,'length_m':line.length,'source_binding':{'feature_id':fid,'source_direction':'source_forward','oneway':f['source_tags'].get('oneway'),'lanes':f['source_tags'].get('lanes'),'source_refs':f['source_refs'],'offset_m':0.,'lane_basis':'authored centre corridor inside source-derived display road, not surveyed lane centre'},'repeat':'guarded_oneway_stream','speed_mps':5.,'road_domain':mapping(domain),'conflicts':conflicts,'stopping_distance_m':7.7,'end_stop_s_m':max(0,line.length-8.),'repeat_spatial_edge':None})
out=ROOT/'game/assets/authored';out.mkdir(exist_ok=True)
green={'schema_version':1,'task':'SOURCE_TREES_AND_STREET_GREENERY','world_sha256':provenance['game/resources/world_geometry/world.json'],'provenance':provenance,'source_tree_node_count':len(nodes.trees),'source_tree_candidates_retained':sum(r['basis']=='source_natural_tree_node'for r in tree_records),'source_rejections':tree_rejections,'trees':tree_records,'driving_polygons':mapping(roads),'private_polygons':mapping(private),'coverage_viewpoints':[{'id':f'sector_{i}','point_xz':[c.x,c.y],'toward_xz':list(line.interpolate(.75,normalized=True).coords)[0]}for i,(line,_,c)in enumerate(chosen)],'policy':{'collision_budget':128,'player_activation_m':75.,'actor_activation_m':12.,'native_batch_grid_m':100.,'visual_distance_m':230.,'tree_height_and_shape':'Authored species-neutral forms, source tree point positions preferred; no present-day tree survey or elevation claim.'}}
def publish(name,record):
 path=out/name;payload=json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n'
 if args.check:
  if not path.exists() or path.read_text()!=payload:raise SystemExit(f'coverage output is stale: {path}')
 else:path.write_text(payload)
publish('neighborhood_greenery.json',green)
pop={'schema_version':1,'task':'NEIGHBORHOOD_COVERAGE','world_sha256':provenance['game/resources/world_geometry/world.json'],'provenance':provenance,'scope':{'new_walkers':20,'new_walk_corridors':10,'new_cars':8,'new_drive_corridors':4,'authored_population':True,'source_geometry_changed':False,'real_density_verified':False},'policy':old['policy']|{'maximum_actors':20,'traffic_route_clearance_m':3.5},'routes':walk_records,'vehicle_routes':vehicle_records,'driving_polygons':mapping(roads),'coverage_viewpoints':green['coverage_viewpoints']}
publish('neighborhood_population.json',pop)
print(json.dumps({'source_tree_nodes':len(nodes.trees),'source_tree_kept':green['source_tree_candidates_retained'],'authored_fill':len(selected_fill),'walk_corridors':len(chosen),'walkers':len(walk_records),'drive_routes':[(r['name'],round(r['length_m'],1),len(r['conflicts']))for r in vehicle_records],'green_json_bytes':(out/'neighborhood_greenery.json').stat().st_size,'pop_json_bytes':(out/'neighborhood_population.json').stat().st_size},ensure_ascii=False))

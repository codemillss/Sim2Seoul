#!/usr/bin/env python3
"""W01 bounded source-footway connection and explicit engineering gate overrides."""
import argparse, hashlib, json, math
from pathlib import Path
from shapely.geometry import LineString, Point, mapping, shape
from prepare_world import mesh_polygon, polygons, encode
from check_collision_bundle import check as check_p04
ROOT=Path(__file__).resolve().parents[1]
OUT='game/data/generated/daehanmun.json'
MANIFEST='game/data/generated/daehanmun_manifest.json'
DECISION='game/data/generated/daehanmun_decision.json'
INPUT='data/manual/daehanmun_connection.json'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rings(g):return [[list(p.exterior.coords),*[list(r.coords) for r in p.interiors]] for p in polygons(g)]
def prepare(root=ROOT,check_only=False):
 root=Path(root);check_p04(root)
 d=json.loads((root/INPUT).read_text());fs=json.loads((root/'data/processed/features.json').read_text());world=json.loads((root/'game/resources/world_geometry/world.json').read_text());by={f['feature_id']:f for f in fs['features']};meshes={m['id']:m for m in world['meshes']}
 assert d['task']=='W01' and d['schema_version']==1 and d['opening_width_m']==3 and d['opening_height_m']==3
 assert not d['scope']['physical_terrain_verified'] and not d['scope']['measured_gate_dimensions'] and d['scope']['global_playable_boundary'] is None
 def node(fid,n):
  f=by[fid];i=f['source_topology']['node_ids'].index(n);return f['geometry']['coordinates'][i]
 outside=node(d['passage_id'],d['outside_node']);inside=node(d['passage_id'],d['gate_node']);start=node(d['external_path_id'],d['external_start_node']);end=node(d['internal_path_id'],d['internal_end_node'])
 f=by[d['passage_id']];assert f['source_tags']['tunnel']=='building_passage' and f['source_tags']['access']=='permissive'
 line=LineString([outside,inside]);length=line.length;u=[(inside[i]-outside[i])/length for i in range(2)];n=[-u[1],u[0]]
 extended=LineString([[outside[i]-u[i]*d['cut_extension_m'] for i in range(2)],[inside[i]+u[i]*d['cut_extension_m'] for i in range(2)]])
 cut=extended.buffer(d['opening_width_m']/2,cap_style='flat',join_style='mitre')
 gate=shape(by[d['gate_building_id']]['geometry']);wall=shape(by[d['wall_id']]['geometry']).buffer(world['display']['barrier_thickness_m']/2,cap_style='flat',join_style='mitre')
 assert abs(gate.intersection(line).length-length)<1e-7
 route=[start,outside,inside,end];route_line=LineString(route)
 # Extend along original first/last source segment, without inventing a new connection.
 first=math.dist(start,outside);last=math.dist(inside,end)
 extended_route=[ [start[i]-(outside[i]-start[i])*d['support_end_extension_m']/first for i in range(2)], *route, [end[i]+(end[i]-inside[i])*d['support_end_extension_m']/last for i in range(2)]]
 floor=LineString(extended_route).buffer(d['support_width_m']/2,cap_style='flat',join_style='mitre')
 area=floor.buffer(-d['movement_edge_margin_m'],join_style='mitre');assert area.geom_type=='Polygon' and not area.interiors
 lower=gate.difference(cut);barrier=wall.difference(cut)
 assert len(polygons(lower))==2 and abs(lower.union(gate.intersection(cut)).symmetric_difference(gate).area)<1e-7
 assert abs(barrier.union(wall.intersection(cut)).symmetric_difference(wall).area)<1e-7
 fragments=[];volumes=[]
 def emit(id,g,lo,hi,material,role,source):
  mesh=mesh_polygon(g,lo,hi)
  fragments.append({'id':id,'material':material,'role':role,'source_id':source,'geometry':mapping(g),**mesh})
  volumes.append({'id':id,'rings':rings(g),'bottom':lo,'top':hi})
 gm=meshes[d['gate_building_id']]
 for i,p in enumerate(polygons(lower)):emit('W01_gate_side_'+str(i),p,gm['bottom_y_m'],d['opening_height_m'],'historic','Buildings',d['gate_building_id'])
 emit('W01_gate_lintel',gate,d['opening_height_m'],gm['top_y_m'],'historic','Buildings',d['gate_building_id'])
 wm=meshes[d['wall_id']];emit('W01_palace_wall',barrier,wm['bottom_y_m'],wm['top_y_m'],'barrier','Barriers',d['wall_id'])
 emit('W01_support',floor,-d['support_depth_m'],d['ground_y_m'],'support','Ground',None)
 disabled=[d['gate_building_id'],d['wall_id'],'temporary_support']
 for m in world['meshes']:
  if m['id'] in disabled or m['role'] not in ['Buildings','Barriers']:continue
  f=by[m['metadata']['feature_id']];g=shape(f['geometry'])
  if m['role']=='Barriers' and g.geom_type in ['LineString','MultiLineString']:g=g.buffer(world['display']['barrier_thickness_m']/2,cap_style='flat',join_style='mitre')
  if g.intersects(floor.buffer(6)):volumes.append({'id':m['id'],'rings':rings(g),'bottom':m['bottom_y_m'],'top':m['top_y_m']})
 # The capsule-sized route is clear from non-overridden lower obstructions.
 for v in volumes:
  if v['id']=='W01_support' or v['bottom']>=1.7:continue
  g=shape(next(m['geometry'] for m in fragments if m['id']==v['id'])) if v['id'].startswith('W01_') else shape(by[meshes[v['id']]['metadata']['feature_id']]['geometry'])
  if not v['id'].startswith('W01_') and g.geom_type in ['LineString','MultiLineString']:g=g.buffer(world['display']['barrier_thickness_m']/2,cap_style='flat',join_style='mitre')
  if route_line.buffer(.32).intersects(g):raise ValueError('Source route blocked by '+v['id'])
 sources=[INPUT,'config/region.json','data/processed/features.json','data/processed/terrain.json','data/processed/walkable_areas.json','data/manual/movement_review.json','data/reports/g04_official_route_evidence.json','docs/evidence/D03_PALACE_ROUTE_SOURCES.md','game/resources/world_geometry/world.json','game/resources/collision/generated.json','tools/prepare_daehanmun.py','tools/prepare_world.py']
 inputs={p:sha(root/p) for p in sources}
 data={'schema_version':1,'task':'W01','provenance':inputs,'scope':d['scope'],'assumption_id':d['assumption_id'],'source_nodes':{'start':d['external_start_node'],'outside':d['outside_node'],'inside':d['gate_node'],'end':d['internal_end_node']},'route_xz':route,'route_length_m':route_line.length,'passage_length_m':length,'direction_xz':u,'normal_xz':n,'cut_geometry':mapping(cut),'disabled_source_ids':disabled,'fragments':fragments,'volume_obstacles':volumes,'movement_ring':list(area.exterior.coords),'spawn':[start[0],d['spawn_height_m'],start[1]],'opening':{'width':d['opening_width_m'],'height':d['opening_height_m']},'counts':{'preserved_active_bodies':682,'replacement_bodies':len(fragments),'active_bodies':682+len(fragments),'fragment_triangles':sum(len(f['vertices'])//9 for f in fragments)}}
 content=encode(data);decision=(root/INPUT).read_bytes()
 files={OUT:content,DECISION:decision}
 manifest={'schema_version':1,'task':'W01','files':{'connection':{'path':'res://data/generated/daehanmun.json','sha256':hashlib.sha256(content).hexdigest()},'decision':{'path':'res://data/generated/daehanmun_decision.json','sha256':hashlib.sha256(decision).hexdigest()}},'world_sha256':inputs['game/resources/world_geometry/world.json'],'collision_sha256':inputs['game/resources/collision/generated.json'],'region_sha256':inputs['config/region.json']}
 files[MANIFEST]=encode(manifest)
 for path,blob in files.items():
  p=root/path
  if check_only:
   if not p.exists() or p.read_bytes()!=blob:raise ValueError('Stale/missing W01 generated file:'+path)
  else:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(blob)
 return {'task':'W01','passed':True,'counts':data['counts'],'passage_length_m':length,'route_length_m':route_line.length,'connection_sha256':hashlib.sha256(content).hexdigest(),'inputs':inputs}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args();print(json.dumps(prepare(a.root,a.check),ensure_ascii=False,indent=2))

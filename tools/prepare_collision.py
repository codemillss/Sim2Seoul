#!/usr/bin/env python3
"""P04 separate collision plan; E03/G-stage geometry and permissions stay unchanged."""
import argparse,hashlib,json,math
from pathlib import Path
from collections import Counter
from shapely.geometry import shape,Point
from prepare_game_data import prepare
ROOT=Path(__file__).resolve().parents[1]
RULES='game/resources/collision/rules.json'
OUTPUT='game/resources/collision/generated.json'
WORLD='game/resources/world_geometry/world.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def mesh_digest(m):return hashlib.sha256(json.dumps(m['vertices'],separators=(',',':')).encode()).hexdigest()
def selected(m):return m['role'] in ('Buildings','Barriers') or m['id']=='temporary_support'
def generate(root=ROOT,check_only=False):
 root=Path(root);prepare(root,check_only=True)
 rules=json.loads((root/RULES).read_text());world=json.loads((root/WORLD).read_text())
 expected={'static_world':{'layer_number':1,'layer':1,'mask':14},'player':{'layer_number':2,'layer':2,'mask':13},'pedestrian':{'layer_number':3,'layer':4,'mask':15},'vehicle':{'layer_number':4,'layer':8,'mask':15}}
 if rules['body_roles']!=expected or rules['camera_query']!={'layer':None,'mask':1,'exclude_player_rid':True}:raise ValueError('Review collision matrix change before generation')
 if rules['static_selection']!={'roles':['Buildings','Barriers'],'ground_ids':['temporary_support'],'shape':'ConcavePolygonShape3D','backface_collision':True}:raise ValueError('Unsupported static selection')
 scope={'runtime_permission':None,'walkability_verified':False,'physical_terrain_verified':False,'playable_boundary':None,'spawn':None,'gate_openings':'W01_pending','support_plane':'G03 temporary engineering plane only'}
 if rules['scope']!=scope or rules['schema_version']!=1 or rules['task']!='P04':raise ValueError('P04 scope differs')
 entries=[{'mesh_id':m['id'],'role':m['role'],'face_sha256':mesh_digest(m),'triangles':len(m['vertices'])//9,'holes':m['topology']['holes'],'layer':1,'mask':14,'shape':'ConcavePolygonShape3D','backface_collision':True,'runtime_permission':None} for m in world['meshes'] if selected(m)]
 excluded=[{'mesh_id':m['id'],'role':m['role'],'reason':'E03 display/reference candidate; no collision/access promotion'} for m in world['meshes'] if not selected(m)]
 # Probe specification derives locations from source triangles/rings, never a new road/spawn contract.
 meshes={m['id']:m for m in world['meshes']};features=json.loads((root/'data/processed/features.json').read_text())['features'];by={f['feature_id']:f for f in features}
 probes=[];moves=[];holes=[]
 named=[m for m in world['meshes'] if selected(m) and m['metadata']['name'] in ['대한문','중화문','중화전','석조전','서울특별시청','서울도서관','정관헌','국립현대미술관 덕수궁관']]
 named+= [m for m in world['meshes'] if m['role']=='Barriers'][:3]
 obstacles=[(m['id'],shape(by[m['id']]['geometry'])) for m in world['meshes'] if m['role']=='Buildings']
 for m in named:
  verts=m['vertices'];normals=m['normals'];picked={}
  for i in range(0,len(verts),9):
   n=normals[i:i+3];kind='top' if n[1]>.9 else 'bottom' if n[1]<-.9 else 'side'
   if kind in picked:continue
   point=[sum(verts[i+j*3+k] for j in range(3))/3 for k in range(3)]
   picked[kind]=True
   for sign in ([1,-1] if kind=='side' else [1]):
    probes.append({'mesh_id':m['id'],'kind':kind,'triangle_index':i//9,'point':point,'normal':n,'from':[point[k]+n[k]*.5*sign for k in range(3)],'to':[point[k]-n[k]*.5*sign for k in range(3)],'expected_hit':True})
  if m['id'] in by and m['role']=='Buildings':
   g=shape(by[m['id']]['geometry']);polys=[g] if g.geom_type=='Polygon' else list(g.geoms)
   for p in polys:
    xy=list(p.exterior.coords)
    for a,z in sorted(zip(xy,xy[1:]),key=lambda pair:-math.dist(*pair)):
     dx,dz=z[0]-a[0],z[1]-a[1];length=math.hypot(dx,dz)
     if length<2:continue
     mid=((a[0]+z[0])/2,(a[1]+z[1])/2);out=(dz/length,-dx/length)
     if g.contains(Point(mid[0]+out[0]*.2,mid[1]+out[1]*.2)):out=(-out[0],-out[1])
     start=Point(mid[0]+out[0]*.8,mid[1]+out[1]*.8);end=Point(mid[0]-out[0]*.8,mid[1]-out[1]*.8)
     if not g.contains(end) or g.distance(start)<.35 or any(og.distance(start)<.35 for oid,og in obstacles if oid!=m['id']):continue
     moves.append({'mesh_id':m['id'],'kind':'external_wall_capsule_sweep','start':[start.x,m['bottom_y_m']+.08,start.y],'motion':[-out[0]*1.6,0,-out[1]*1.6],'edge_midpoint':[mid[0],m['bottom_y_m']+.85,mid[1]],'outward_normal':[out[0],0,out[1]]});break
    if moves and moves[-1]['mesh_id']==m['id']:break
 for m in world['meshes']:
  if m['role']!='Buildings' or not m['topology']['holes']:continue
  g=shape(by[m['id']]['geometry']);polys=[g] if g.geom_type=='Polygon' else list(g.geoms)
  for p in polys:
   for ring in p.interiors:
    from shapely.geometry import Polygon
    centre=Polygon(ring).representative_point()
    holes.append({'mesh_id':m['id'],'kind':'hole_cap_clear','from':[centre.x,m['top_y_m']+.5,centre.y],'to':[centre.x,m['bottom_y_m']+.05,centre.y],'expected_hit':False})
 # Known gate blocking is retained, not interpreted as an opening from gate nodes.
 gates=[{'mesh_id':m['id'],'name':m['metadata']['name'],'opening':'not_created_W01_pending'} for m in named if m['metadata']['name'] in ['대한문','중화문']]
 plan={'schema_version':1,'task':'P04','world_file':'res://resources/world_geometry/world.json','world_sha256':sha(root/WORLD),'rules_file':'res://resources/collision/rules.json','rules_sha256':sha(root/RULES),'region_sha256':sha(root/'config/region.json'),'generator_sha256':sha(root/'tools/prepare_collision.py'),'scope':scope,'entries':entries,'excluded':excluded,'counts':{'colliders':len(entries),'roles':dict(Counter(x['role'] for x in entries)),'triangles':sum(x['triangles'] for x in entries),'excluded':len(excluded)},'surface_probes':probes,'capsule_moves':moves,'hole_probes':holes,'gates_pending':gates}
 content=(json.dumps(plan,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n').encode();path=root/OUTPUT
 if check_only:
  if not path.exists() or path.read_bytes()!=content:raise ValueError('Collision plan stale/missing; regenerate')
 else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
 return {'file':OUTPUT,'sha256':hashlib.sha256(content).hexdigest(),'counts':plan['counts'],'surface_probes':len(probes),'capsule_moves':len(moves),'hole_probes':len(holes),'gates_pending':gates,'scope':scope}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args();print(json.dumps(generate(check_only=a.check),ensure_ascii=False,indent=2))

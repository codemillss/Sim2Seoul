"""Source-aware full stop footprints. No renderer or source geometry is modified."""
import hashlib,json,math
from shapely.geometry import Polygon,LineString,Point,shape
from shapely.ops import unary_union
from shapely.prepared import prep

CROSSING_MARGIN=3.0
PATH_MARGIN=.5
SOLID_MARGIN=.4
SHELTER_BOUNDS=(-.775,.775,-3.235,2.5) # Godot local +Z is route-backwards.

def rectangle(point,direction,bounds):
 x0,x1,z0,z1=bounds
 return Polygon([(point[0]-direction[1]*x+direction[0]*z,point[1]+direction[0]*x+direction[1]*z) for x,z in [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]])

def mesh_polygon(mesh):
 v=mesh['vertices']
 return unary_union([Polygon([(v[i],v[i+2]),(v[i+3],v[i+5]),(v[i+6],v[i+8])]) for i in range(0,len(v),9)])

def source_context(features,world,roads):
 walk=[];solid=[];drive=[]
 for mesh in world['meshes']:
  material=mesh['material']
  if material not in ['walk','building','historic','barrier','drive']:continue
  g=mesh_polygon(mesh);fid=mesh['metadata']['feature_id']
  if material=='walk':walk.append((fid,g))
  elif material=='drive':drive.append(g)
  else:solid.append(g)
 bands=[]
 for fid,row in features.items():
  tags=row.get('source_tags',{})
  if row['geometry']['type']=='LineString' and (tags.get('footway')=='crossing' or 'crossing' in tags):
   bands.append({'id':fid,'basis':'source_crossing','width_m':4.4,'xz':row['geometry']['coordinates']})
 for row in roads['crossings']:bands.append({'id':row['id'],'basis':'game_crossing','width_m':float(row.get('width_m',4.4)),'xz':row['xz']})
 for row in bands:row['shape']=LineString(row['xz']).buffer(row['width_m']*.5,cap_style=2)
 private=unary_union([shape(row['geometry']) for row in features.values() if row['geometry']['type'] in ['Polygon','MultiPolygon'] and row.get('source_tags',{}).get('access') in ['no','private']])
 valid=[]
 for fid,g in walk:
  tags=features.get(fid,{}).get('source_tags',{})
  if tags.get('footway')!='crossing' and 'crossing' not in tags and tags.get('access') not in ['private','no']:valid.append((fid,g))
 return {'walk':valid,'paths':unary_union([g for f,g in walk]),'solid':unary_union(solid),'private':private,'drive':unary_union(drive),'bands':bands,'crossings':unary_union([b['shape'] for b in bands])}

def frame(line,station):
 p=line.interpolate(station);q=line.interpolate(min(line.length,station+.05));length=math.hypot(q.x-p.x,q.y-p.y)
 return (p.x,p.y),((q.x-p.x)/length,(q.y-p.y)/length)

def certify_stop(stop,line,context):
 point,direction=frame(line,stop['station_m'])
 geometries={'bus':rectangle(point,direction,(-1.275,1.275,-4.55,4.55)),'wait':Point(stop['wait_xz']).buffer(.35),'shelter':rectangle(stop['shelter_xz'],direction,SHELTER_BOUNDS)}
 nearest={}
 for label,g in geometries.items():
  band=min(context['bands'],key=lambda b:g.distance(b['shape']))
  nearest[label]={'crossing_id':band['id'],'distance_m':g.distance(band['shape'])}
 shelter=geometries['shelter'];wait=Point(stop['wait_xz'])
 return {'id':stop['id'],'source_walk_feature_id':stop['source_walk_feature_id'],'nearest_crossing':nearest,'full_shelter_source_path_distance_m':shelter.distance(context['paths']),'full_shelter_source_solid_distance_m':shelter.distance(context['solid']),'wait_to_full_shelter_distance_m':wait.distance(shelter),'wait_to_source_solid_distance_m':wait.distance(context['solid']),'full_shelter_private_overlap_m2':shelter.intersection(context['private']).area,'shelter_visual_bounds_route_xz_m':list(SHELTER_BOUNDS),'footprints':{label:list(g.exterior.coords) for label,g in geometries.items()},'accepted':all(row['distance_m']>=CROSSING_MARGIN for row in nearest.values()) and shelter.distance(context['paths'])>=PATH_MARGIN and shelter.distance(context['solid'])>=SOLID_MARGIN and not shelter.intersects(context['private'])}

def place_stops(line,features,world,roads):
 context=source_context(features,world,roads)
 blocked_cross=prep(context['crossings'].buffer(CROSSING_MARGIN));blocked_path=prep(context['paths'].buffer(PATH_MARGIN));blocked_solid=prep(context['solid'].buffer(SOLID_MARGIN));private=prep(context['private']);drive=prep(context['drive'])
 stops=[]
 # A bounded +/-50m local search, not arbitrary remote stops; wait stays on a noncrossing source path.
 for target,name in [(375,'숭례문 북측'),(280,'북창동'),(210,'서소문'),(130,'시청 남측')]:
  candidates=[]
  for sample in range(math.ceil(line.length/.25)):
   station=sample*.25;point,direction=frame(line,station)
   if direction[1]>=0 or abs(point[1]-target)>50:continue
   if blocked_cross.intersects(rectangle(point,direction,(-1.275,1.275,-4.55,4.55))):continue
   right=(-direction[1],direction[0])
   for offset in [2.6+n*.25 for n in range(46)]:
    wait=Point(point[0]+right[0]*offset,point[1]+right[1]*offset);wait_disc=wait.buffer(.35)
    if blocked_cross.intersects(wait_disc) or wait.distance(context['solid'])<3.2:continue
    fid=next((fid for fid,g in context['walk'] if g.covers(wait_disc)),None)
    if not fid:continue
    for setback in [3.85+n*.25 for n in range(25)]:
     shelter=[wait.x+right[0]*setback,wait.y+right[1]*setback];envelope=rectangle(shelter,direction,SHELTER_BOUNDS)
     if blocked_cross.intersects(envelope) or blocked_path.intersects(envelope) or blocked_solid.intersects(envelope) or private.intersects(envelope) or drive.intersects(envelope):continue
     aisle=LineString([wait,Point(shelter)]).buffer(.35)
     if aisle.intersects(context['solid']) or aisle.intersects(context['private']):continue
     score=abs(point[1]-target)*.1+offset+setback*.2
     row={'id':'GAME-L%02d'%(len(stops)+1),'name':name+' 정류장','station_m':station,'route_id':'T01','door_side':'right','shelter_xz':shelter,'wait_xz':[wait.x,wait.y],'source_walk_feature_id':fid,'door_to_wait_m':offset,'shelter_setback_from_wait_m':setback,'authored_game_placement':True,'placement_basis':'Noncrossing source public walk wait; separate adjacent game shelter bay, no official stop survey.'}
     candidates.append((score,station,row));break
    break
  assert candidates,(name,'no bounded full-stop-clearance candidate')
  stops.append(min(candidates,key=lambda r:(r[0],r[1]))[2])
 certificates=[certify_stop(stop,line,context) for stop in stops]
 assert all(row['accepted'] for row in certificates),certificates
 basis=[{k:v for k,v in row.items() if k!='shape'} for row in context['bands']]
 return stops,{'crossing_source_count':sum(row['basis']=='source_crossing' for row in basis),'crossing_game_count':sum(row['basis']=='game_crossing' for row in basis),'crossing_basis_sha256':hashlib.sha256(json.dumps(basis,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'crossing_clearance_m':CROSSING_MARGIN,'full_visual_source_path_clearance_m':PATH_MARGIN,'full_visual_source_solid_clearance_m':SOLID_MARGIN,'stop_certificates':certificates,'source_geometry_changed':False,'route_geometry_changed':False,'scope':'Planar full visual/physical stop footprint exclusion; native TIN, capsule/LOS, actual crossing walk and camera checks are separate.'}

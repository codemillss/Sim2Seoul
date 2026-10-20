import argparse, json, math, hashlib
from pathlib import Path
from shapely.geometry import Polygon, LineString, Point, MultiPoint, shape
from shapely.ops import unary_union, substring, voronoi_diagram, linemerge
from shapely.strtree import STRtree
from coordinate_system import CoordinateSystem

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Reproduce the bounded game-authored street paint/furniture; never modifies source geometry.')
parser.add_argument('--check',action='store_true',help='Compare with the saved asset without writing it.')
args=parser.parse_args()
def read(p):return json.loads((ROOT/p).read_text())
def sha(p):return hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
world=read('game/resources/world_geometry/world.json')
features={r['feature_id']:r for r in read('data/processed/features.json')['features']}
traffic=read('game/data/generated/traffic.json')
coverage=read('game/assets/authored/neighborhood_population.json')
walk=read('game/data/generated/public_walk.json')
green=read('game/assets/authored/neighborhood_greenery.json')
extent=Polygon(read('game/assets/authored/exploration_extent.json')['polygon_xz']).buffer(-.1)

def footprint(m):
 v=m['vertices'];polys=[]
 for i in range(0,len(v),9):
  t=Polygon([(v[i],v[i+2]),(v[i+3],v[i+5]),(v[i+6],v[i+8])])
  if t.area>1e-7:polys.append(t)
 return unary_union(polys)

drives={m['metadata']['feature_id']:footprint(m) for m in world['meshes'] if m['material']=='drive'}
drive=unary_union(list(drives.values()))
walk_mesh=unary_union([footprint(m) for m in world['meshes'] if m['material']=='walk'])
solids=unary_union([footprint(m) for m in world['meshes'] if m['material'] in ['building','historic','civic','barrier']]).buffer(.25)
private=shape(green['private_polygons'])
forbidden=solids.union(private)
paint_forbidden=forbidden.buffer(.00001)
main_names=('세종대로','서소문로','소공로','을지로','남대문로','무교로','청계천로')
main_features={s:features[s] for s in drives if features[s]['source_tags'].get('name') in main_names and features[s]['source_tags'].get('highway') in ['primary','secondary','tertiary']}
road_by_name={name:unary_union([drives[s] for s,f in main_features.items() if f['source_tags']['name']==name]) for name in main_names}
ownership={};paired_medians=[]
# A display source may count the same broad carriageway twice. Partition only
# authored paint by the nearest sampled direction-centre, retaining all source
# geometry. One shared yellow median replaces competing inner white edges.
for name in sorted(main_names):
 group={s:f for s,f in main_features.items() if f['source_tags'].get('name')==name and f['source_tags'].get('oneway')=='yes' and LineString(f['geometry']['coordinates']).length>15}
 if len(group)<2:continue
 longest=max(group.values(),key=lambda f:LineString(f['geometry']['coordinates']).length)['geometry']['coordinates'];axis=(longest[-1][0]-longest[0][0],longest[-1][1]-longest[0][1]);alen=math.hypot(*axis);axis=(axis[0]/alen,axis[1]/alen)
 directions={};sites=[];labels=[];dupes=set()
 for source,f in group.items():
  coords=f['geometry']['coordinates'];heading=(coords[-1][0]-coords[0][0],coords[-1][1]-coords[0][1]);h=math.hypot(*heading)
  dot=(heading[0]*axis[0]+heading[1]*axis[1])/max(h,1e-9)
  if abs(dot)<.55:continue
  sign=1 if dot>0 else -1;directions[source]=sign;line=LineString(coords)
  for i in range(int(math.ceil(line.length/2))+1):
   p=line.interpolate(min(line.length,i*2));key=(round(p.x,5),round(p.y,5))
   if key in dupes:continue
   dupes.add(key);sites.append(p);labels.append(sign)
 pos=unary_union([drives[s] for s in directions if directions[s]==1]);neg=unary_union([drives[s] for s in directions if directions[s]==-1])
 if pos.is_empty or neg.is_empty or pos.intersection(neg).area<30:continue
 tree=STRtree(sites);regions={1:[],-1:[]};envelope=pos.union(neg).envelope.buffer(100).envelope
 for cell in voronoi_diagram(MultiPoint(sites),envelope=envelope).geoms:
  site_ids=tree.query(cell,predicate='intersects')
  if not len(site_ids):continue
  regions[labels[int(site_ids[0])]].append(cell)
 regions={sign:unary_union(parts) for sign,parts in regions.items()}
 for s,sign in directions.items():ownership[s]=regions[sign]
 median=regions[1].boundary.intersection(regions[-1].boundary).intersection(pos.intersection(neg).buffer(-.5))
 if median.geom_type=='MultiLineString':median=linemerge(median)
 median=median.simplify(.16)
 paired_medians.append({'name':name,'geometry':median,'positive_source_ids':[s for s in directions if directions[s]==1],'negative_source_ids':[s for s in directions if directions[s]==-1],'source_ids':list(directions),'basis':'game-authored nearest-direction partition of overlapping source display corridors,2m centreline samples,not real median survey'})
catalog=read('game/assets/authored/interiors/source_catalog.json')
entry=[]
for rec in catalog['records']:
 for e in rec['entry_candidates']:
  a=e['door'];b=e['entrance'];out=e['outward'];end=[b[0]+out[0]*5,b[1]+out[1]*5]
  entry.append(LineString([a,end]).buffer(max(1.2,e['door_width']/2)+.55))
entry_union=unary_union(entry)
routes=traffic['routes']+coverage['vehicle_routes']
crossings=[];stops=[]
for r in routes:
 line=LineString(r['xz']);source=r['source_binding']['feature_id']
 for c in r['conflicts']:
  s=float(c['stop_s_m']);a=line.interpolate(max(0,s-.1));b=line.interpolate(min(line.length,s+.1));d=(b.x-a.x,b.y-a.y);n=math.hypot(*d);d=(d[0]/n,d[1]/n)
  p=line.interpolate(s);center=[p.x+d[0]*2.6,p.y+d[1]*2.6]
  # Paint is2.6m beyond the established car-centre hold, leaving a.5m nose gap.
  stops.append({'id':r['id']+'_'+c['crossing_id'],'route_id':r['id'],'crossing_id':c['crossing_id'],'source_feature_id':source,'controller_stop_xz':[p.x,p.y],'paint_stop_xz':center,'direction_xz':list(d),'stop_s_m':s,'enter_s_m':c['enter_s_m'],'exit_s_m':c['exit_s_m'],'source_refs':r['source_binding']['source_refs']})
  if any(x['id']==c['crossing_id'] for x in crossings):continue
  if c['crossing_id']=='sejong_marked':
   src=traffic['crossings'][0];crossings.append({'id':c['crossing_id'],'xz':src['source_xz'],'source_feature_id':src['feature_id'],'road_ids':src['road_ids'],'basis':'existing_source_marked_zebra_path','width_m':4.4})
  else:
   p=line.interpolate((float(c['enter_s_m'])+float(c['exit_s_m']))/2);side=(-d[1],d[0]);domain=drives[source]
   half=max(2,min(15,domain.area/max(1,line.length)/2))
   xz=[[p.x-side[0]*half,p.y-side[1]*half],[p.x+side[0]*half,p.y+side[1]*half]]
   crossings.append({'id':c['crossing_id'],'xz':xz,'source_feature_id':source,'road_ids':[source],'basis':'authored_transverse_stripes_at_existing_source_crossing_conflict','width_m':4.4})

# The initial EXP23 recipe accidentally used only animated-car conflicts as its
# crossing inventory. Cover the source crossing geometry and explicit signal
# nodes too. A source node locates a crossing, not a surveyed pole: its local
# transverse bank segment and every fixture below remain game-authored.
signal_coverage=[]
system=CoordinateSystem(ROOT/'config/region.json')
node_candidates=read('data/reports/d03_crossing_candidates.json')['crossing_candidates']
signal_nodes=[]
for row in node_candidates:
 x,_,z=system.to_world(*row['lon_lat']);signal_nodes.append(dict(row,xz=[x,z]))
def road_direction(source,point):
 line=LineString(features[source]['geometry']['coordinates']);station=line.project(point)
 a=line.interpolate(max(0,station-.2));b=line.interpolate(min(line.length,station+.2));length=a.distance(b)
 return ((b.x-a.x)/length,(b.y-a.y)/length)
def roads_crossed(line):
 result=[]
 for source,domain in drives.items():
  portion=line.intersection(domain)
  if portion.length<.75:continue
  mid=line.interpolate(line.length*.5);d=road_direction(source,mid)
  a=line.interpolate(max(0,line.project(mid)-.2));b=line.interpolate(min(line.length,line.project(mid)+.2))
  delta=(b.x-a.x,b.y-a.y);length=math.hypot(*delta)
  # Ignore broad source display overlap parallel to a crossing path.
  if abs((delta[0]*d[0]+delta[1]*d[1])/max(length,1e-8))>.80:continue
  result.append(source)
 return result
for source,f in features.items():
 tags=f.get('source_tags',{})
 if tags.get('footway')!='crossing':continue
 line=LineString(f['geometry']['coordinates'])
 nearby=[n for n in signal_nodes if line.distance(Point(n['xz']))<1.2]
 explicit=[n for n in nearby if n['tags'].get('crossing')=='traffic_signals' or n['tags'].get('crossing:signals')=='yes']
 no_signal=tags.get('crossing')=='uncontrolled' or tags.get('crossing:signals')=='no' or (nearby and all(n['tags'].get('crossing:signals')=='no' for n in nearby))
 eligible=bool(explicit) or (tags.get('crossing')=='marked' and not no_signal)
 row={'kind':'source_crossing_way','source_id':source,'source_tags':tags,'explicit_signal_nodes':[n['osm_id'] for n in explicit]}
 if not eligible or no_signal:
  row.update(status='excluded',reason='source_explicit_uncontrolled_or_no_signals' if no_signal else 'no_marked_or_explicit_signal_evidence');signal_coverage.append(row);continue
 # These two northern bridge-bank sites passed XZ containment, but actual
 # production rays hit source static geometry even with a rooted5.25m head.
 # Preserve the measured rejection rather than drawing a one-sided orphan.
 if source in ['osm:way:506252749:highway_line','osm:way:506252752:highway_line']:
  row.update(status='excluded',reason='native_static_bridge_bank_blocks_far_end_head_or_rooted_pole',evidence='data/reports/street_detail/20261020/signals/development/headless02.json');signal_coverage.append(row);continue
 roads=roads_crossed(line)
 if not extent.intersects(line) or not roads:
  row.update(status='excluded',reason='outside_extent_or_no_transverse_source_drive');signal_coverage.append(row);continue
 nearest=min(crossings,key=lambda c:line.distance(LineString(c['xz']))) if crossings else None
 if nearest and line.distance(LineString(nearest['xz']))<3.0:
  crossing=nearest;crossing.update(xz=list(map(list,line.coords)),source_feature_id=source,road_ids=roads,basis='source_crossing_way_with_preserved_existing_conflict_id')
 else:
  crossing={'id':'source_crossing_'+source.split(':')[2],'xz':list(map(list,line.coords)),'source_feature_id':source,'road_ids':roads,'basis':'source_marked_or_explicit_signalled_crossing_way','width_m':4.4};crossings.append(crossing)
 crossing['source_signal_nodes']=[n['osm_id'] for n in explicit]
 row.update(status='accepted',crossing_id=crossing['id'],road_ids=roads);signal_coverage.append(row)
for row in signal_nodes:
 tags=row['tags'];explicit=tags.get('crossing')=='traffic_signals' or tags.get('crossing:signals')=='yes'
 record={'kind':'source_crossing_node','source_id':row['osm_id'],'source_tags':tags,'xz':row['xz']}
 if not explicit:
  record.update(status='excluded',reason='node_not_explicitly_signalled');signal_coverage.append(record);continue
 point=Point(row['xz']);near=[c for c in crossings if LineString(c['xz']).distance(point)<3]
 if near:
  record.update(status='accepted',crossing_id=near[0]['id'],reason='covered_by_source_crossing_way_or_existing_conflict');signal_coverage.append(record);continue
 road_candidates=[s for s,d in drives.items() if d.distance(point)<1.5]
 if not extent.contains(point) or not road_candidates:
  record.update(status='excluded',reason='outside_extent_or_no_adjacent_source_drive');signal_coverage.append(record);continue
 source=min(road_candidates,key=lambda s:LineString(features[s]['geometry']['coordinates']).distance(point));d=road_direction(source,point);side=(-d[1],d[0])
 probe=LineString([(point.x-side[0]*45,point.y-side[1]*45),(point.x+side[0]*45,point.y+side[1]*45)])
 segments=[g for g in getattr(probe.intersection(drive),'geoms',[probe.intersection(drive)]) if g.geom_type=='LineString' and g.length>2]
 if not segments:
  record.update(status='excluded',reason='no_continuous_transverse_drive_segment');signal_coverage.append(record);continue
 segment=min(segments,key=lambda g:g.distance(point));a=segment.coords[0];b=segment.coords[-1]
 line=LineString([(a[0]-side[0]*.4,a[1]-side[1]*.4),(b[0]+side[0]*.4,b[1]+side[1]*.4)])
 crossing={'id':'source_node_'+row['osm_id'].split('/')[1],'xz':list(map(list,line.coords)),'source_feature_id':'osm:node:'+row['osm_id'].split('/')[1],'road_ids':roads_crossed(line),'basis':'authored_transverse_source_drive_segment_at_explicit_source_signal_node','width_m':4.4,'source_signal_nodes':[row['osm_id']]};crossings.append(crossing)
 record.update(status='accepted',crossing_id=crossing['id'],reason='local_transverse_segment_authored_at_explicit_signal_node');signal_coverage.append(record)

# Keep the old five controller stop rows byte-for-value. Additional visible
# approaches use source-road direction and a line behind the marked crossing.
# Existing source route arrays and their human-priority/FIFO conflicts are not
# rewritten by this authoring tool.
for crossing in crossings:
 line=LineString(crossing['xz'])
 for source in crossing['road_ids']:
  road=LineString(features[source]['geometry']['coordinates']);mid=line.interpolate(line.length*.5);s=road.project(mid);d=road_direction(source,mid)
  signs=[1] if features[source]['source_tags'].get('oneway')=='yes' else [1,-1]
  for sign in signs:
   heading=[d[0]*sign,d[1]*sign]
   if any(r['crossing_id']==crossing['id'] and r['source_feature_id']==source and sum(a*b for a,b in zip(r['direction_xz'],heading))>.9 for r in stops):continue
   p=road.interpolate(max(0,min(road.length,s-sign*6.0)));paint=[p.x,p.y]
   stops.append({'id':crossing['id']+'_'+source.split(':')[2]+'_'+str(sign),'route_id':'','crossing_id':crossing['id'],'source_feature_id':source,'controller_stop_xz':[p.x-heading[0]*2.6,p.y-heading[1]*2.6],'paint_stop_xz':paint,'direction_xz':heading,'stop_s_m':max(0,s-sign*8.6),'enter_s_m':s-2.2,'exit_s_m':s+2.2,'source_refs':features[source]['source_refs'],'basis':'authored_visible_approach_at_source_crossing'})
for stop in stops:
 crossing=next(c for c in crossings if c['id']==stop['crossing_id']);p=stop['paint_stop_xz'];d=stop['direction_xz']
 stop['clearance_from_stop_m']=max((q[0]-p[0])*d[0]+(q[1]-p[1])*d[1] for q in crossing['xz'])+crossing['width_m']*.5

pedestrian_signals=[];unsupported_crossings=[]
for crossing in crossings:
 endpoints=[];raw=crossing['xz']
 for bank in [0,1]:
  a=raw[0] if bank==0 else raw[-1];b=raw[1] if bank==0 else raw[-2]
  out=(a[0]-b[0],a[1]-b[1]);length=math.hypot(*out);out=(out[0]/length,out[1]/length)
  found=None
  for distance in [.85,1.6,2.5,3.5,4.5,6,8,10,12,15]:
   for lateral in [0,.8,-.8,1.6,-1.6]:
    q=Point(a[0]+out[0]*distance-out[1]*lateral,a[1]+out[1]*distance+out[0]*lateral)
    if not extent.contains(q) or drive.distance(q)<.45 or forbidden.distance(q)<.50 or entry_union.intersects(q.buffer(.20)) or walk_mesh.distance(q)>4:continue
    # The approach is on this physical bank; the head itself faces across the
    # road so it is readable from the opposite bank, as a far-end signal.
    approach=[q.x-out[1]*.8+out[0]*.4,q.y+out[0]*.8+out[1]*.4]
    if drive.distance(Point(approach))<.25 or forbidden.distance(Point(approach))<.35:continue
    found={'id':crossing['id']+'_bank_'+str(bank),'crossing_id':crossing['id'],'bank':bank,'xz':[q.x,q.y],'approach_xz':approach,'outward_xz':list(out),'placement':'authored_outside_union_of_source_drive_surfaces_on_actual_crossing_bank'};break
   if found:break
  if not found:break
  endpoints.append(found)
 if len(endpoints)!=2:
  unsupported_crossings.append(crossing['id'])
  for rec in signal_coverage:
   if rec.get('crossing_id')==crossing['id']:rec.update(status='excluded',reason='no_source_safe_supported_road_bank_pair')
  continue
 for bank,row in enumerate(endpoints):
  other=endpoints[1-bank];delta=(other['xz'][0]-row['xz'][0],other['xz'][1]-row['xz'][1]);length=math.hypot(*delta)
  row['front_direction_xz']=[delta[0]/length,delta[1]/length];row['opposite_bank_approach_xz']=other['approach_xz'];pedestrian_signals.append(row)

crossings=[c for c in crossings if c['id'] not in unsupported_crossings]
stops=[s for s in stops if s['crossing_id'] not in unsupported_crossings]

paint=[]
def components(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 return [p for s in getattr(g,'geoms',[]) for p in components(s)]
def emit(id,kind,source,g,color='white',use_ownership=True):
 if source not in drives:return
 # Source road containment is exact; subtract old physical/visual solids and private land.
 safe=g.intersection(drives[source].buffer(-.08)).intersection(extent).difference(paint_forbidden)
 if use_ownership and source in ownership:safe=safe.intersection(ownership[source])
 if kind=='edge':safe=safe.intersection(drive.boundary.buffer(.60))
 for index,p in enumerate(components(safe)):
  if p.area<.006 or p.interiors:continue
  coords=[[round(x,6),round(z,6)] for x,z in list(p.exterior.coords)[:-1]]
  paint.append({'id':id+'_'+str(index),'kind':kind,'source_feature_id':source,'color':color,'xz':coords})

cross_masks=unary_union([LineString(c['xz']).buffer(c['width_m']/2+1.6,cap_style=2) for c in crossings])
corridors=[]
for source,domain in drives.items():
 f=features.get(source,{});tags=f.get('source_tags',{});g=f.get('geometry',{})
 if source not in main_features or g.get('type')!='LineString':continue
 line=LineString(g['coordinates']);length=line.length
 if length<25:continue
 width=domain.area/max(length,1);lanes=max(1,min(8,int(tags.get('lanes','1').split(';')[0])))
 if width<3:continue
 # Existing G04 source-road display widths are estimates; offsets are authored.
 half=width/2-.48;offsets=[(-half,'edge',False),(half,'edge',False)]
 if tags.get('oneway')!='yes' and width>=5.4:
  offsets.extend([(-.12,'centre',False),(.12,'centre',False)])
 elif lanes>=2 and width>=8.0:
  # Calmer4.5m game-lane cadence. Place separators around the unchanged
  # original1.6m-offset sedan corridor; the pilot bus is9m(two lanes) away.
  anchor=1.6 if source in ['osm:way:1084408283:highway_line','osm:way:378453707:highway_line'] else 0.0
  for k in range(-3,4):
   offset=anchor+2.25+k*4.5
   if abs(offset)<half-.65:offsets.append((offset,'lane',True))
 junction=domain.intersection(unary_union([road_by_name[n] for n in main_names if n!=tags['name']])).buffer(2.0)
 median_buffer=unary_union([m['geometry'].buffer(1.2) for m in paired_medians if source in m['source_ids']])
 for offset,kind,dashed in offsets:
  line2=line.offset_curve(offset,join_style=2)
  if line2.geom_type!='LineString':continue
  start=3.0
  while start<line2.length-3:
   end=min(start+(4.0 if dashed else 24),line2.length-3)
   stroke=substring(line2,start,end).buffer(.075 if kind=='lane' else .09,cap_style=2,join_style=2).difference(cross_masks).difference(junction)
   if kind=='lane':stroke=stroke.difference(median_buffer)
   emit(source+'_'+kind+'_'+str(round(offset,2))+'_'+str(round(start,2)),kind,source,stroke,'yellow' if kind=='centre' else 'white')
   start=end+(12.0 if dashed else 0.04)
 corridors.append({'source_feature_id':source,'name':tags['name'],'source_refs':f['source_refs'],'oneway':tags.get('oneway'),'source_lanes':tags.get('lanes'),'source_xz':g['coordinates'],'display_width_m':round(width,3),'offsets_basis':'authored_calm4.5m_lane_cadence_4m_dash12m_gap; outer edges only; opposing source overlap has shared ownership;not_surveyed_lanes'})

def lines(g):
 if g.is_empty:return []
 if g.geom_type=='LineString':return [g]
 return [p for child in getattr(g,'geoms',[]) for p in lines(child)]
for median in paired_medians:
 parts=[p for p in lines(median['geometry']) if p.length>.35]
 for index,line in enumerate(parts):
  for offset in [-.16,.16]:
   line2=line.offset_curve(offset,join_style=2)
   stroke=line2.buffer(.075,cap_style=2,join_style=2).difference(cross_masks)
   claimed=Polygon()
   for source in median['source_ids']:
    tags=features[source]['source_tags'];junction=drives[source].intersection(unary_union([road_by_name[n] for n in main_names if n!=tags['name']])).buffer(2)
    candidate=stroke.difference(junction).difference(claimed)
    emit(median['name']+'_shared_yellow_'+str(index)+'_'+str(offset),'paired_centre',source,candidate,'yellow',False)
    claimed=claimed.union(candidate.intersection(drives[source].buffer(-.08)))

for c in crossings:
 line=LineString(c['xz']);station=.2;stripe=0
 while station<line.length:
  seg=substring(line,station,min(station+.65,line.length));poly=seg.buffer(c['width_m']/2,cap_style=2,join_style=2)
  for source in c['road_ids']:emit(c['id']+'_stripe_'+str(stripe),'zebra',source,poly)
  station+=1.25;stripe+=1
for stop in stops:
 p=stop['paint_stop_xz'];d=stop['direction_xz'];side=(-d[1],d[0]);domain=drives[stop['source_feature_id']];width=domain.area/max(LineString(features[stop['source_feature_id']]['geometry']['coordinates']).length,1)
 a=(p[0]-side[0]*width,p[1]-side[1]*width);b=(p[0]+side[0]*width,p[1]+side[1]*width)
 emit(stop['id']+'_stop','stop',stop['source_feature_id'],LineString([a,b]).buffer(.22,cap_style=2))

# Poles only on the roadside, near an existing source walking display, with
# every original entrance candidate corridor and source solid preserved.
lamps=[];used=[]
priority=sorted(corridors,key=lambda c:(0 if c['name']=='세종대로' else 1 if c['name'] in ['덕수궁길','정동길','을지로','무교로','서소문로'] else 2,c['source_feature_id']))
for c in priority:
 line=LineString(c['source_xz']);width=c['display_width_m'];source=c['source_feature_id']
 for station in range(16,int(line.length)-12,34):
  p=line.interpolate(station);a=line.interpolate(max(0,station-.1));b=line.interpolate(min(line.length,station+.1));dx,dz=b.x-a.x,b.y-a.y;n=math.hypot(dx,dz);dx/=n;dz/=n
  for sign in [-1,1]:
   x=p.x-dz*sign*(width/2+1.15);z=p.y+dx*sign*(width/2+1.15);point=Point(x,z)
   if not extent.contains(point) or drive.distance(point)<.45 or forbidden.distance(point)<.75 or entry_union.intersects(point.buffer(.4)) or walk_mesh.distance(point)>3.0:continue
   if any(point.distance(q)<22 for q in used):continue
   if any(point.distance(LineString(cross['xz']))<3.5 for cross in crossings):continue
   # Head arm points toward road; dimensions are authored, not surveyed fixtures.
   lamps.append({'id':'road_lamp_'+str(len(lamps)).zfill(2),'source_feature_id':source,'source_name':c['name'],'xz':[round(x,6),round(z,6)],'toward_xz':[round(p.x,6),round(p.y,6)],'height_m':7.4 if width>=10 else 5.2,'arm_m':1.6 if width>=10 else .9,'basis':'authored_source_roadside_near_source_walk','source_refs':c['source_refs']});used.append(point)
   if len(lamps)>=64:break
  if len(lamps)>=64:break
 if len(lamps)>=64:break

signal_anchors=[]
for stop in stops:
 source=stop['source_feature_id'];domain=drives[source];p=stop['paint_stop_xz'];d=stop['direction_xz'];side=(-d[1],d[0]);feature_line=LineString(features[source]['geometry']['coordinates']);width=domain.area/max(feature_line.length,1)
 found=False
 for longitudinal in [3,6,0,-3,-6]:
  for extra in [1,2.5,4]:
   for sign in [-1,1]:
    q=Point(p[0]+side[0]*sign*(width/2+extra)+d[0]*longitudinal,p[1]+side[1]*sign*(width/2+extra)+d[1]*longitudinal)
    if not extent.contains(q) or drive.distance(q)<.30 or forbidden.distance(q)<.55 or entry_union.intersects(q.buffer(.25)):continue
    reach=abs((p[0]-q.x)*side[0]+(p[1]-q.y)*side[1])
    signal_anchors.append({'id':stop['id']+'_signal','crossing_id':stop['crossing_id'],'source_feature_id':source,'xz':[q.x,q.y],'direction_xz':d,'arm_sign':-sign,'arm_m':reach,'height_m':5.5,'controller_stop_xz':stop['controller_stop_xz'],'paint_stop_xz':p,'placement':'authored_roadside_mast_with_head_above_approach_centre','stop_line_id':stop['id']});found=True;break
   if found:break
  if found:break

# Nearby crossing paths must not advertise simultaneous perpendicular greens.
# This bounded layout contains only parallel approach groups at each site;
# fail authoring rather than silently extend this schedule to a new junction.
axis_conflicts=[]
for index,a in enumerate(stops):
 ca=next(c for c in crossings if c['id']==a['crossing_id'])
 for b in stops[index+1:]:
  cb=next(c for c in crossings if c['id']==b['crossing_id'])
  if LineString(ca['xz']).distance(LineString(cb['xz']))>45:continue
  dot=abs(sum(x*y for x,y in zip(a['direction_xz'],b['direction_xz'])))
  if dot<.65:axis_conflicts.append([a['id'],b['id'],dot])
if axis_conflicts:raise RuntimeError('Perpendicular nearby vehicle approaches require a separate coordinated phase: '+repr(axis_conflicts))

paths=['game/resources/world_geometry/world.json','game/data/generated/traffic.json','game/assets/authored/neighborhood_population.json','game/assets/authored/terrain_heightfield.json','game/assets/authored/interiors/source_catalog.json','data/processed/features.json','data/reports/d03_crossing_candidates.json','config/region.json','tools/coordinate_system.py']
out={'schema_version':1,'task':'EXP23_street_detail','coordinate_space':'source_local_xz_metres','source_hashes':{'res://'+p.removeprefix('game/'):sha(p) for p in paths if p.startswith('game/')},'source_features_sha256':sha('data/processed/features.json'),'provenance':{'source':'Existing OpenStreetMap-derived road/display triangles, existing traffic conflicts and all original entry candidates','paint':'Calm main-road-only4m dashes/12m gaps with authored4.5m lane cadence; shared ownership of overlapping opposite-direction source display surfaces, one shared double-yellow divider and outer-union white edges only. Source solids/private and intersections/crossings remain clear; not surveyed lane markings','terrain':'After EXP21 terrain.loaded; exact triangle-split runtime projection once, .052m relative paint offset above base TIN, road display .035m','schedules':'46 second coordinated game cycle, protected29-43s pedestrian phase with final5s flashing; never a live Seoul signal plan','lamp':'Authored dark slim tapered poles, short horizontal LED heads, base flange/service door; no imported photograph texture','external_references':[{'url':'https://news.seoul.go.kr/gov/archives/539324','checked':'2026-10-19','observation':'Official Seoul description separates signal, streetlight and combined S-Pole models and LED lighting. Used as functional integration reference, not placement/dimensions.'},{'url':'https://mediahub.seoul.go.kr/news/article/newsArticlePrintPopup.do?articleNo=2001844','checked':'2026-10-19','observation':'Official Seoul article describes red/green pedestrian information coordinated at crossings. Text reviewed; no claim to reconstruct the photographed location.'}]},'cycle':{'duration_s':46.0,'vehicle_green_end_s':24.0,'vehicle_amber_end_s':27.0,'pedestrian_green_start_s':29.0,'pedestrian_green_end_s':43.0,'pedestrian_flash_start_s':38.0,'flash_period_s':.5,'timing_basis':'game_authored_coordinated_not_real_signal_timing'},'policy':{'paint_y_above_TIN_m':.052,'new_collisions':False,'source_geometry_changed':False,'existing_route_arrays_changed':False,'real_schedule':False,'lamp_active_standard':12,'lamp_active_low':6,'lamp_range_m':16,'lamp_max_distance_m':70,'lane_dash_m':4.0,'lane_gap_m':12.0,'authored_lane_cadence_m':4.5,'lane_paint_width_m':.15,'pedestrian_heads':'One physical inward-facing far-end head on each road bank; both approaches share phase'},'corridors':corridors,'paired_direction_corridors':[{'name':m['name'],'positive_source_ids':m['positive_source_ids'],'negative_source_ids':m['negative_source_ids'],'basis':m['basis'],'median_xz':[list(line.coords) for line in lines(m['geometry'])]} for m in paired_medians],'paint':paint,'crossings':crossings,'source_signal_coverage':signal_coverage,'stop_lines':stops,'signals':signal_anchors,'pedestrian_signals':pedestrian_signals,'lamps':lamps,'counts':{'road_corridors':len(corridors),'paint_polygons':len(paint),'crossings':len(crossings),'signal_poles':len(signal_anchors),'pedestrian_heads':len(pedestrian_signals),'lamps_planned':len(lamps)},'preflight':{'source_solid_private_paint_overlap_m2':round(sum(Polygon(p['xz']).intersection(forbidden).area for p in paint),9),'source_road_outside_paint_m2':round(sum(Polygon(p['xz']).difference(drives[p['source_feature_id']]).area for p in paint),9),'all_entrance_corridors_lamp_overlap_m2':round(sum(Point(l['xz']).buffer(.25).intersection(entry_union).area for l in lamps),9),'white_lane_area_m2':round(sum(Polygon(p['xz']).area for p in paint if p['kind']=='lane'),3),'white_edge_area_m2':round(sum(Polygon(p['xz']).area for p in paint if p['kind']=='edge'),3),'nearby_perpendicular_green_approach_pairs':len(axis_conflicts),'paired_yellow_area_m2':round(sum(Polygon(p['xz']).area for p in paint if p['kind']=='paired_centre'),3)}}
out['authoring']={'generator':'tools/prepare_road_furniture.py','generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'library':'Shapely2.2.0','recipe':'Source-safe game geometry; no real lane count, traffic timing or surveyed-furniture claim.'}
serialized=json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n'
target=ROOT/'game/assets/authored/road_furniture.json'
if args.check:
 if not target.exists() or target.read_text()!=serialized:raise SystemExit('road_furniture.json differs; review authoring inputs before regeneration')
else:target.write_text(serialized)
print(json.dumps(out['counts']));print(json.dumps(out['preflight']))

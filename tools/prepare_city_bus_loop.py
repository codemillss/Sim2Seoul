#!/usr/bin/env python3
"""EXP25 authored closed route from existing source drive surfaces. Run with .venv-data/bin/python."""
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[1]
import os
os.chdir(ROOT)
CACHE=ROOT/'data/reports/urban_transit/20261021/bus/geometry_stages'
CACHE.mkdir(parents=True,exist_ok=True)
import json,math
from shapely.geometry import Polygon,LineString,Point
from shapely.ops import unary_union
F={r['feature_id']:r for r in json.load(open('data/processed/features.json'))['features']};WORLD=json.load(open('game/resources/world_geometry/world.json'))
ids=['619147732','517634898','899373686','619147733','619147735','908622900','908622899']
polys={}
for m in WORLD['meshes']:
 if m.get('material')!='drive':continue
 v=m['vertices'];polys[m['metadata']['feature_id']]=unary_union([Polygon([(v[i],v[i+2]),(v[i+3],v[i+5]),(v[i+6],v[i+8])]) for i in range(0,len(v),9)])
union=unary_union(list(polys.values()));raw=[]
for id in ids:
 p=F['osm:way:'+id+':highway_line']['geometry']['coordinates'];raw+=p if not raw else p[1:]
# Round each existing source-node corner using a quadratic Bezier inside its connected source surfaces.
def roundpath(radius):
 out=[]
 for i,b in enumerate(raw[:-1]):
  a=raw[i-1] if i else raw[-2];c=raw[(i+1)%(len(raw)-1)]
  la=math.dist(a,b);lc=math.dist(b,c);u=((b[0]-a[0])/la,(b[1]-a[1])/la);v=((c[0]-b[0])/lc,(c[1]-b[1])/lc);ang=math.acos(max(-1,min(1,sum(x*y for x,y in zip(u,v)))))
  t=min(la*.45,lc*.45,radius*math.tan(ang/2))
  s=(b[0]-u[0]*t,b[1]-u[1]*t);e=(b[0]+v[0]*t,b[1]+v[1]*t)
  for n in range(max(1,math.ceil((2*t)/.3))):
   q=n/max(1,math.ceil(2*t/.3));out.append(((1-q)**2*s[0]+2*(1-q)*q*b[0]+q*q*e[0],(1-q)**2*s[1]+2*(1-q)*q*b[1]+q*q*e[1]))
  out.append(e)
 out.append(out[0]);return out
base=LineString(roundpath(8));L=base.length
def smooth(t):
 t=max(0,min(1,t));return t*t*(3-2*t)
for inner in [1.6]:
 pts=[]
 for n in range(math.ceil(L/.4)):
  s=n*L/math.ceil(L/.4);a=base.interpolate(s);b=base.interpolate(min(L,s+.03));dx=b.x-a.x;dz=b.y-a.y;l=math.hypot(dx,dz);right=(-dz/l,dx/l)
  # Curb lane only along straights; source-node turning corridors have no claimed lane count.
  if a.y>90 and a.y<380:off=6.4 if dz>0 else 3.2
  elif a.y<=90:off=-inner+(6.4+inner)*smooth((a.y-38)/52) if dz>0 else -inner+(3.2+inner)*smooth((a.y-38)/52)
  else:off=-inner+((6.4 if dz>0 else 3.2)+inner)*smooth((417-a.y)/37)
  if dz>0:off+=3.2*smooth((a.y-150)/30)*smooth((380-a.y)/30)
  pts.append((a.x+right[0]*off,a.y+right[1]*off))
 pts.append(pts[0]);p=LineString(pts);bad=[]
 for i in range(math.ceil(p.length/.25)):
  s=i*.25;a=p.interpolate(s);b=p.interpolate(min(p.length,s+.04));dx=b.x-a.x;dz=b.y-a.y;l=math.hypot(dx,dz);dx/=l;dz/=l
  box=Polygon([(a.x-dz*x+dx*z,a.y+dx*x+dz*z) for x,z in [(-1.225,-4.5),(1.225,-4.5),(1.225,4.5),(-1.225,4.5)]])
  dif=box.difference(union).area
  if dif>1e-5:bad.append([s,a.x,a.y,dif])
 print(inner,'len',p.length,'bad',len(bad),'max',max([r[-1] for r in bad],default=0),'first',bad[:3])
 json.dump({'offset_m':inner,'length_m':p.length,'bad':bad,'xz':pts,'source_ids':ids},open(str(CACHE/'bus_loop_lane')+str(inner)+'.json','w'))
p=LineString(json.load(open(str(CACHE/'bus_loop_lane1.6.json')))['xz']);N=math.ceil(p.length/.25);pts=[p.interpolate(i*p.length/N).coords[0] for i in range(N)]
for sigma in [1.]:
 radius=math.ceil(sigma*3/.25);ws=[math.exp(-((i*.25)/sigma)**2/2) for i in range(-radius,radius+1)];W=sum(ws)
 sm=[tuple(sum(pts[(n+k-radius)%N][d]*w for k,w in enumerate(ws))/W for d in [0,1]) for n in range(N)];sm.append(sm[0]);path=LineString(sm);bad=[];rs=[]
 for i,b in enumerate(sm[:-1]):
  a=sm[i-1] if i else sm[-2];c=sm[(i+1)%(len(sm)-1)];dx=c[0]-b[0];dz=c[1]-b[1];l=math.hypot(dx,dz);dx/=l;dz/=l
  cross=abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]));r=math.dist(a,b)*math.dist(b,c)*math.dist(c,a)/(2*cross) if cross>1e-7 else 1e7;rs.append(r)
  box=Polygon([(b[0]-dz*x+dx*z,b[1]+dx*x+dz*z) for x,z in [(-1.275,-4.55),(1.275,-4.55),(1.275,4.55),(-1.275,4.55)]])
  dif=box.difference(union).area
  if dif>1e-5:bad.append([i,b,dif])
 print(sigma,'len',path.length,'bad',len(bad),'max',max([r[-1] for r in bad],default=0),'minR',min(rs))
 json.dump({'sigma_m':sigma,'length_m':path.length,'bad':bad,'min_radius_m':min(rs),'xz':sm,'source_ids':ids},open(str(CACHE/'bus_loop_sm')+str(sigma)+'.json','w'))
old=json.load(open(str(CACHE/'bus_loop_sm1.0.json')))['xz'];segments=[]
# Keep already-certified lane-following portions and replace two cramped nodal U joins with actual wide circles.
south=[p for p in old if p[1]>=65 and p[1]<=365 and p[0]<25+(405-p[1])*.34];north=[p for p in old if p[1]>=65 and p[1]<=365 and p[0]>=25+(405-p[1])*.34]
# classify by tangent rather than coordinates
south=[];north=[]
for i,p in enumerate(old[:-1]):
 q=old[(i+1)%(len(old)-1)]
 if 65<=p[1]<=365:(south if q[1]>p[1] else north).append(p)
south.sort(key=lambda p:p[1]);north.sort(key=lambda p:-p[1])
def bez(a,b,c,d,n=100):
 return [tuple((1-t)**3*a[k]+3*(1-t)**2*t*b[k]+3*(1-t)*t*t*c[k]+t**3*d[k] for k in [0,1]) for t in [i/n for i in range(n+1)]]
for config in [(-44.0,386.0,10.0)]:
 for topR in [10.]:
  ax,az,R=config;a=(ax,az);u=(-.318,.948);cx=a[0]+u[1]*R;cz=a[1]-u[0]*R;theta=math.atan2(a[1]-cz,a[0]-cx)
  cap=[(cx+R*math.cos(theta-t*math.pi),cz+R*math.sin(theta-t*math.pi)) for t in [i/100 for i in range(101)]]
  tx=77.;tz=32.;top=[(tx+topR*math.cos(-t*math.pi),tz+topR*math.sin(-t*math.pi)) for t in [i/100 for i in range(101)]]
  p=south[:];s=south[-1];p+=bez(s,(s[0]+u[0]*8,s[1]+u[1]*8),(a[0]-u[0]*8,a[1]-u[1]*8),a)[1:];p+=cap[1:]
  e=cap[-1];n=north[0];p+=bez(e,(e[0]-u[0]*8,e[1]-u[1]*8),(n[0]+u[0]*8,n[1]+u[1]*8),n)[1:];p+=north[1:]
  n=north[-1];b=top[0];p+=bez(n,(n[0],n[1]-12),(b[0],b[1]+12),b)[1:];p+=top[1:]
  b=top[-1];s=south[0];p+=bez(b,(b[0],b[1]+12),(s[0],s[1]-12),s)[1:]
  line=LineString(p);N=math.ceil(line.length/.25);p=[line.interpolate(i*line.length/N).coords[0] for i in range(N)];
  sigma=2.;radius=24;ws=[math.exp(-((i*.25)/sigma)**2/2) for i in range(-radius,radius+1)];W=sum(ws);p=[tuple(sum(p[(n+k-radius)%N][d]*w for k,w in enumerate(ws))/W for d in [0,1]) for n in range(N)];p.append(p[0]);bad=[];rs=[]
  for i,b in enumerate(p[:-1]):
   a=p[i-1] if i else p[-2];c=p[(i+1)%(len(p)-1)];dx=c[0]-b[0];dz=c[1]-b[1];l=math.hypot(dx,dz);dx/=l;dz/=l;cross=abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]));rs.append(math.dist(a,b)*math.dist(b,c)*math.dist(c,a)/(2*cross) if cross>1e-7 else 1e7)
   box=Polygon([(b[0]-dz*x+dx*z,b[1]+dx*x+dz*z) for x,z in [(-1.275,-4.55),(1.275,-4.55),(1.275,4.55),(-1.275,4.55)]]);dif=box.difference(union).area
   if dif>1e-5:bad.append([i,b,dif])
  print(ax,az,R,topR,'length',LineString(p).length,'bad',len(bad),'max',max([x[-1] for x in bad],default=0),'Rmin',min(rs))
  json.dump({'length_m':LineString(p).length,'bad':bad,'min_radius_m':min(rs),'xz':p,'source_ids':ids},open(str(CACHE/'bus_search_')+str(ax)+'_'+str(az)+'_'+str(R)+'.json','w'))

# Final route is downsampled only after the whole9m box+5cm certificate.
final=json.load(open(CACHE/'bus_search_-44.0_386.0_10.0.json'))
assert not final['bad'] and final['min_radius_m']>=6.0
points=[list(p) for p in LineString(final['xz']).simplify(.001,preserve_topology=True).coords];line=LineString(points)
line=LineString(points)
# Recheck the final simplified path, including the entire rectangle rather than corners only.
public_union=unary_union([g for fid,g in polys.items() if F.get(fid,{}).get('source_tags',{}).get('access') not in ['no','private'] and F.get(fid,{}).get('source_tags',{}).get('motor_vehicle')!='no'])
for i in range(math.ceil(line.length/.20)):
 a=line.interpolate(i*.20);b=line.interpolate(min(line.length,i*.20+.01));dx=b.x-a.x;dz=b.y-a.y;l=math.hypot(dx,dz);dx/=l;dz/=l
 box=Polygon([(a.x-dz*x+dx*z,a.y+dx*x+dz*z) for x,z in [(-1.275,-4.55),(1.275,-4.55),(1.275,4.55),(-1.275,4.55)]])
 assert box.difference(public_union).area<1e-7,(i*.20,'final whole footprint outside public drive')
arc=[0.]
for x,y in zip(points,points[1:]):arc.append(arc[-1]+math.dist(x,y))
bindings=[];radii=[]
for i,p in enumerate(points[:-1]):
 q=points[i+1];dx=q[0]-p[0];dz=q[1]-p[1];span=math.hypot(dx,dz);dx/=span;dz/=span
 choices=[]
 for fid in ['osm:way:'+v+':highway_line' for v in ids]:
  source=LineString(F[fid]['geometry']['coordinates']);s=source.project(Point(p));u=source.interpolate(max(0,s-.05));v=source.interpolate(min(source.length,s+.05));l=math.hypot(v.x-u.x,v.y-u.y)
  if l and (dx*(v.x-u.x)+dz*(v.y-u.y))/l>0.1:choices.append((source.distance(Point(p)),fid))
 bindings.append(min(choices)[1] if choices else bindings[-1])
 a=points[i-1] if i else points[-2];cross=abs((p[0]-a[0])*(q[1]-a[1])-(p[1]-a[1])*(q[0]-a[0]));radii.append(math.dist(a,p)*span*math.dist(q,a)/(2*cross) if cross>1e-8 else 100000.)
from city_bus_stop_placement import place_stops
roads=json.load(open('game/assets/authored/road_furniture.json'))
stops,stop_clearance=place_stops(line,F,WORLD,roads)
old=json.load(open('game/assets/authored/bus_service.json'))
old['schema_version']=2;old['task']='EXP25_T01_SOURCE_CLOSED_LOOP'
old['scope']={'bus_count':3,'stop_count':len(stops),'authored_game_route':True,'official_route_or_stop_ids':False,'live_arrivals':False,'source_geometry_changed':False,'original_vehicles_replaced':False,'repeat':'Actual closed source-road physical path; arc reset at same physical joint only, no recycle/teleport','boardable_stops':[s['id'] for s in stops]}
old['art']['route_display']='도심01  시청 · 북창 · 숭례문 순환'
old['policy'].update({'minimum_centre_turn_radius_m':6.,'lateral_acceleration_mps2':1.5,'maximum_speed_mps':8.,'acceleration_mps2':2.,'braking_mps2':4.,'headway_hold_s':12.,'ride_exit':'Fresh E at any dock or queued while moving; circular service does not auto-eject at an artificial final stop.','wait_request':'At every source-walk stop E toggles waiting; it never instant-spawns or auto-boards a bus.','boarding_hold':'All stops accept fresh E at both real doors and hold while a legal prospective passenger occupies them.'})
old['route']={'id':'T01_source_closed_loop','name':'시청·북창·숭례문 순환','xz':points,'ground_y_m':0.,'length_m':line.length,'source_binding':{'feature_id':'osm:way:619147732:highway_line','source_direction':'source_forward','connected_source_feature_ids':['osm:way:'+v+':highway_line' for v in ids],'graph_basis':'Existing source-forward one-way ring identifies the available public corridors. The southern game U-turn is intentionally before the exact shared-node connector to clear the unchanged original14 vehicle endpoints; it stays fully inside source public drive union. This is authored game traffic, not a real permitted turn or surveyed node-junction reproduction.'},'segment_source_ids':bindings,'segment_radius_m':radii,'repeat':'physical_closed_loop','conflicts':[],'end_stop_s_m':line.length}
old['stops']=stops
old['fleet']=[{'id':'T01-%02d'%(i+1),'initial_station_m':i*line.length/3} for i in range(3)]
old['route']['footprint_support_feature_ids']=[fid for fid,g in polys.items() if g.distance(line)<6. and F.get(fid,{}).get('source_tags',{}).get('access') not in ['no','private'] and F.get(fid,{}).get('source_tags',{}).get('motor_vehicle')!='no']
old['route']['authored_turn']={'southern_circle_entry_xz':[-44.,386.],'southern_radius_before_smoothing_m':10.,'not_real_turn_permission':True,'reason':'Avoid unchanged original two-vehicle endpoint queue and preserve their camera/human recycle guard.'}
old['preflight']={'whole_footprint_outside_source_m2':0.,'samples':len(final['xz'])-1,'box_with_margin_m':[2.55,9.1],'sample_m':.25,'minimum_centre_radius_m':min(radii),'loop_endpoint_gap_m':math.dist(points[0],points[-1]),'source_geometry_changed':False,'notes':'Source-display estimated widths and authored lanes, not surveyed bus swept-path approval. Southern U-turn is authored before the exact node connector to avoid original vehicle endpoint parking. Native terrain/full-box checks remain mandatory.'}
print('CLOSED_LOOP',line.length,'radius',min(radii),'stops',[(r['name'],round(r['station_m'],1),r['door_to_wait_m']) for r in stops])

legacy=next(r for r in json.load(open('game/assets/authored/neighborhood_population.json'))['vehicle_routes'] if r['id']=='coverage_drive_1')
old_line=LineString(legacy['xz']);parked=[]
for back in range(16):
 p=old_line.interpolate(old_line.length-back);a=old_line.interpolate(old_line.length-back-.02);dx=p.x-a.x;dz=p.y-a.y;l=math.hypot(dx,dz);dx/=l;dz/=l
 parked.append(Polygon([(p.x-dz*x+dx*z,p.y+dx*x+dz*z) for x,z in [(-.95,-2.15),(.95,-2.15),(.95,2.15),(-.95,2.15)]]))
queue=unary_union(parked);minimum=100.
for i in range(math.ceil(line.length/.20)):
 a=line.interpolate(i*.20);b=line.interpolate(min(line.length,i*.20+.01));dx=b.x-a.x;dz=b.y-a.y;l=math.hypot(dx,dz);dx/=l;dz/=l
 box=Polygon([(a.x-dz*x+dx*z,a.y+dx*x+dz*z) for x,z in [(-1.275,-4.55),(1.275,-4.55),(1.275,4.55),(-1.275,4.55)]])
 minimum=min(minimum,box.distance(queue))
assert minimum>.75,('legacy_endpoint_queue_clearance',minimum)
old['preflight']['original_two_vehicle_endpoint_queue_clearance_m']=minimum
old['preflight']['stop_clearance']=stop_clearance
old['preflight']['legacy_queue_zone']='Every sedan box at the original coverage_drive_1 endpoint and 0..15m behind it, with 5cm margin; original actors/route/guard unchanged.'
asset=Path('game/assets/authored/bus_service.json')
temporary=asset.with_suffix('.json.tmp')
temporary.write_text(json.dumps(old,ensure_ascii=False,indent=2)+'\n');temporary.replace(asset)
certificate_path=ROOT/'data/reports/urban_transit/20261021/bus/stop_clearance_certificate.json'
certificate_path.write_text(json.dumps(stop_clearance,ensure_ascii=False,indent=2)+'\n')
print('ENDPOINT_QUEUE_CLEARANCE',minimum)

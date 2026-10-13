#!/usr/bin/env python3
"""Independent standard-library W01 evidence audit; never executes Godot.

Retained samples are recomputed against source polygon volumes. Engine all-tick
extrema bound the unretained intervals but are not independent raw trajectories.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def number(v):
    return type(v) in (int, float) and math.isfinite(v)


def vector(v, size=3):
    return isinstance(v, list) and len(v) == size and all(number(x) for x in v)


def near(a, b, tolerance=.002):
    if isinstance(b, list):
        return isinstance(a, list) and len(a) == len(b) and all(near(x,y,tolerance) for x,y in zip(a,b))
    return number(a) and abs(a-b) <= tolerance


def sub(a,b):
    return [x-y for x,y in zip(a,b)]


def norm(a):
    return math.sqrt(sum(x*x for x in a))


def edge_distance(p,a,b):
    d=sub(b,a); l=sum(x*x for x in d)
    t=max(0.,min(1.,sum(x*y for x,y in zip(sub(p,a),d))/l)) if l else 0.
    return norm([p[i]-a[i]-t*d[i] for i in range(2)])


def edges(ring):
    return zip(ring,ring[1:]+ring[:1])


def ring_inside(p,ring):
    """Boundary-inclusive ray crossing, independent of mesh triangulation."""
    if any(edge_distance(p,a,b) <= 1e-9 for a,b in edges(ring)):
        return True
    inside=False
    for a,b in edges(ring):
        if (a[1]>p[1]) != (b[1]>p[1]) and p[0] < a[0]+(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1]):
            inside=not inside
    return inside


def polygon_inside(p,polygon):
    return ring_inside(p,polygon[0]) and not any(ring_inside(p,h) for h in polygon[1:])


def polygon_distance(p,polygon):
    return 0. if polygon_inside(p,polygon) else min(edge_distance(p,a,b) for ring in polygon for a,b in edges(ring))


def volume_distance(point,polygon,bottom,top,axis_half=0.):
    """Distance from vertical capsule axis (or sphere point) to a prism."""
    horizontal=polygon_distance([point[0],point[2]],polygon)
    vertical=max(bottom-(point[1]+axis_half),point[1]-axis_half-top,0.)
    return math.hypot(horizontal,vertical)


def capsule_penetration(player,volumes,height=1.7,radius=.3):
    centre=[player[0],player[1]+height/2,player[2]]
    return max([0.]+[radius-volume_distance(centre,p,b,t,height/2-radius) for p,b,t in volumes])


def sphere_penetration(point,volumes,radius=.2):
    return max([0.]+[radius-volume_distance(point,p,b,t) for p,b,t in volumes])


def volume_bounds(volumes):
    return [(min(v[0] for v in p[0]),max(v[0] for v in p[0]),min(v[1] for v in p[0]),max(v[1] for v in p[0])) for p,b,t in volumes]


def indexed_penetration(point,volumes,bounds,radius,axis_half=0.):
    worst=0.
    for (p,b,t),(xmin,xmax,zmin,zmax) in zip(volumes,bounds):
        dy=max(b-point[1]-axis_half,point[1]-axis_half-t,0.)
        dx=max(xmin-point[0],point[0]-xmax,0.)
        dz=max(zmin-point[2],point[2]-zmax,0.)
        if dx*dx+dy*dy+dz*dz>=radius*radius:continue
        worst=max(worst,radius-volume_distance(point,p,b,t,axis_half))
    return worst


def feature_polygons(feature):
    g=feature['geometry']
    if g['type']=='Polygon':
        return [g['coordinates']]
    if g['type']=='MultiPolygon':
        return g['coordinates']
    raise ValueError('Expected polygon geometry')


def float32_digest(vertices):
    return hashlib.sha256(struct.pack('<'+str(len(vertices))+'f',*vertices)).hexdigest()


def canonical_digest(value):
    return hashlib.sha256((json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n').encode()).hexdigest()


def ray_triangle(start,end,tri):
    def dot(a,b):return sum(x*y for x,y in zip(a,b))
    def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
    a,b,c=tri;direction=sub(end,start);e1=sub(b,a);e2=sub(c,a)
    p=cross(direction,e2);det=dot(e1,p)
    if abs(det)<1e-10:return None
    offset=sub(start,a);u=dot(offset,p)/det;q=cross(offset,e1);v=dot(direction,q)/det;t=dot(e2,q)/det
    if u < -1e-7 or v < -1e-7 or u+v>1+1e-7 or not 0<=t<=1:return None
    return [start[i]+t*direction[i] for i in range(3)]


def signed_area(ring):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in edges(ring))/2


def polygon_area(p):
    return abs(signed_area(p[0]))-sum(abs(signed_area(h)) for h in p[1:])


def convex_clip(subject,clip):
    """Sutherland-Hodgman clipping against the engineering rectangle."""
    output=list(subject);sign=1 if signed_area(clip)>0 else -1
    for a,b in edges(clip):
        previous=output;output=[]
        if not previous:break
        def side(p):return sign*((b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0]))
        last=previous[-1];lastside=side(last)
        for point in previous:
            current=side(point)
            if (current>=0)!=(lastside>=0):
                t=lastside/(lastside-current)
                output.append([last[i]+t*(point[i]-last[i]) for i in range(2)])
            if current>=0:output.append(point)
            last=point;lastside=current
    return output


def source_cut_area(mesh,cut):
    area=0.;removed=0.;v=mesh['vertices']
    for i in range(0,len(v),9):
        tri=v[i:i+9]
        if not all(near(tri[j],mesh['top_y_m'],1e-7) for j in (1,4,7)):continue
        points=[[tri[j],tri[j+2]] for j in (0,3,6)]
        area+=abs(signed_area(points))
        clipped=convex_clip(points,cut)
        if len(clipped)>=3:removed+=abs(signed_area(clipped))
    return area,removed


def audit(record,plan,world,features):
    checks=[]
    def check(name,condition,details=None):
        c={'name':name,'passed':bool(condition)}
        if details is not None:c['details']=details
        checks.append(c)
    def finite(x):
        if isinstance(x,float):return math.isfinite(x)
        if isinstance(x,dict):return all(finite(v) for v in x.values())
        if isinstance(x,list):return all(finite(v) for v in x)
        return True
    try:
        check('schema',record['task']=='W01' and record['schema_version']==1 and record['suite'] in ('full','gpu') and plan['task']=='W01' and world['task']=='E03' and features['task_id']=='G02')
        check('finite_values',all(finite(v) for v in (record,plan,world,features)))
        by={f['feature_id']:f for f in features['features']}
        meshes={m['id']:m for m in world['meshes']}
        gate_id='osm:way:377289797:building'; wall_id='osm:way:26658458:barrier'
        passage=by['osm:way:377289807:highway_line']
        route=plan['route_xz']; outside,inside=passage['geometry']['coordinates']
        check('source_passage',passage['source_tags']['tunnel']=='building_passage' and passage['source_tags']['access']=='permissive' and passage['access']['game_permission'] is None and near(route[1],outside,1e-6) and near(route[2],inside,1e-6) and near(plan['passage_length_m'],norm(sub(inside,outside)),1e-6))
        check('route_source_points',len(route)==4 and near(route[0],[49.052535,13.578888],1e-5) and near(route[-1],[-15.734372,3.912829],1e-5) and near(plan['route_length_m'],sum(norm(sub(b,a)) for a,b in zip(route,route[1:])),1e-6))
        check('engineering_opening',plan['opening']=={'width':3,'height':3} and plan['disabled_source_ids']==[gate_id,wall_id,'temporary_support'] and plan['counts']['preserved_active_bodies']==682 and plan['counts']['replacement_bodies']==5 and plan['counts']['active_bodies']==687)
        scope=plan['scope']
        check('scope_limits',scope['real_world_access_verified'] is False and scope['physical_terrain_verified'] is False and scope['measured_gate_dimensions'] is False and scope['global_playable_boundary'] is None)
        fragments=plan['fragments']; fby={f['id']:f for f in fragments}
        check('fragment_coverage',len(fragments)==len(fby)==5 and set(fby)=={'W01_gate_side_0','W01_gate_side_1','W01_gate_lintel','W01_palace_wall','W01_support'})
        allvol=plan['volume_obstacles']; vby={v['id']:v for v in allvol}
        check('volumes_unique',len(allvol)==len(vby) and set(fby)<=set(vby))
        volumes=[(p,v['bottom'],v['top']) for v in allvol for p in v['rings']]
        for id,f in fby.items():
            g=f['geometry']; polys=[g['coordinates']] if g['type']=='Polygon' else g['coordinates']
            v=vby[id]
            check('fragment.'+id+'.volume',near(v['rings'],polys,1e-7) and near(v['bottom'],f['bottom_y_m'],1e-7) and near(v['top'],f['top_y_m'],1e-7))
            verts=f['vertices']; lo=v['bottom'];hi=v['top']
            check('fragment.'+id+'.mesh',len(verts)%9==0 and all(number(x) for x in verts) and hi>lo and all(near(verts[i],lo,1e-6) or near(verts[i],hi,1e-6) for i in range(1,len(verts),3)) and all(any(edge_distance([verts[i],verts[i+2]],a,b)<=2e-6 for p in polys for r in p for a,b in edges(r)) for i in range(0,len(verts),3)))
        check('lintel_full_source',near(vby['W01_gate_lintel']['rings'],feature_polygons(by[gate_id]),1e-7) and vby['W01_gate_lintel']['bottom']==3 and vby['W01_gate_lintel']['top']==10)
        check('support_depth',vby['W01_support']['bottom']==-.2 and vby['W01_support']['top']==0)
        support=vby['W01_support']['rings']
        width_checks=[]
        for a,b in zip(route,route[1:]):
            length=norm(sub(b,a));normal=[-(b[1]-a[1])/length,(b[0]-a[0])/length];mid=[(a[i]+b[i])/2 for i in range(2)]
            for sign in (-1,1):
                inner=[mid[i]+sign*normal[i]*2.999 for i in range(2)]
                outer=[mid[i]+sign*normal[i]*3.001 for i in range(2)]
                width_checks.append(any(polygon_inside(inner,p) for p in support) and not any(polygon_inside(outer,p) for p in support))
        check('support_width_6m',all(width_checks))
        movement=plan['movement_ring']
        check('bounded_movement_area',all(ring_inside(point,movement) for point in route) and all(any(polygon_inside(point,p) for p in support) and min(edge_distance(point,a,b) for poly in support for ring in poly for a,b in edges(ring))>=.39999 for point in movement) and abs(signed_area(movement))<sum(polygon_area(p) for p in support))
        source_gate=feature_polygons(by[gate_id]);cut=plan['cut_geometry'];cutpoly=cut['coordinates']
        # Partition consistency at every vertex and a regular local lattice, independently
        # of producer triangulation. This bounds source-footprint replacement topology.
        probes=[[x,z] for x in [15+i*.25 for i in range(81)] for z in [-5+i*.25 for i in range(105)]]
        lower=vby['W01_gate_side_0']['rings']+vby['W01_gate_side_1']['rings']
        check('gate_lower_source_partition',all(any(polygon_inside(p,g) for g in lower)==(any(polygon_inside(p,g) for g in source_gate) and not polygon_inside(p,cutpoly)) for p in probes if all(edge_distance(p,a,b)>.00001 for poly in source_gate+[cutpoly]+lower for r in poly for a,b in edges(r))))
        for source_id,ids in ((gate_id,['W01_gate_side_0','W01_gate_side_1']),(wall_id,['W01_palace_wall'])):
            total,removed=source_cut_area(meshes[source_id],cutpoly[0])
            retained=sum(polygon_area(p) for id in ids for p in vby[id]['rings'])
            check('source_partition_area.'+source_id,abs(total-removed-retained)<=.003,{'source_area_m2':total,'cut_area_m2':removed,'remaining_area_m2':retained})
        inv=record['inventory']; source=inv['source_bodies']; replacement=inv['fragments']
        selected={k for k,m in meshes.items() if m['role'] in ('Buildings','Barriers')} - {gate_id,wall_id}
        all_source={b['id']:b for b in source}; sby={k:v for k,v in all_source.items() if k in selected}; rby={b['id']:b for b in replacement}
        check('inventory.source_coverage',len(source)==len(all_source)==685 and len(sby)==682 and set(sby)==selected and set(all_source)==selected|set(plan['disabled_source_ids']) and set(inv['disabled_ids'])==set(plan['disabled_source_ids']))
        disabled={b['id']:b for b in inv['disabled_bodies']}
        check('inventory.actual_disabled_bodies',len(inv['disabled_bodies'])==len(disabled)==3 and set(disabled)==set(plan['disabled_source_ids']) and all(b['layer']==0 and b['mask']==0 and b['visible'] is False and all_source[id]['layer']==0 and all_source[id]['mask']==0 for id,b in disabled.items()))
        check('inventory.fragment_coverage',len(replacement)==len(rby)==5 and set(rby)==set(fby))
        for key,body in {**sby,**rby}.items():
            vertices=(meshes[key] if key in sby else fby[key])['vertices']
            check('inventory.'+key,body['disabled'] is False and body['layer']==1 and body['mask']==14 and body['identity'] is True and body['shape']=='ConcavePolygonShape3D' and body['backface'] is True and body['face_sha256']==float32_digest(vertices) and (key in sby or body['visual_face_sha256']==float32_digest(vertices)))
        check('plan_sha256',record['plan_sha256']==canonical_digest(plan))
        check('world_provenance',plan['provenance']['game/resources/world_geometry/world.json']==canonical_digest(world))
        eng=record['engine'];gpu=str(eng['display']).lower()!='headless'
        check('engine',record['suite']==('gpu' if gpu else 'full') and eng['physics_hz']==60 and eng['render_fps'] in (30,60) and (not gpu or str(eng.get('renderer','')).lower() not in ('','headless')))
        actor=record['actor']
        check('actual_player_contract',actor['identity'] is True and all(near(actor[k],v,1e-6) for k,v in {'height':1.7,'radius':.3,'layer':2,'mask':13,'walk_mps':1.4,'run_mps':3.5,'gravity':9.8,'safe_margin':.001}.items()))
        spawn=record['spawn']
        check('spawn_valid',near([spawn['point'][0],spawn['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.00002) and abs(spawn['point'][1])<=.002 and spawn['valid'] is True and spawn['volume_guard_clear'] is True and spawn['rejected_inside_gate'] is True and ring_inside([spawn['point'][0],spawn['point'][2]],plan['movement_ring']) and capsule_penetration(spawn['point'],volumes)<=.005)
        # Independently recover preserved collider prisms from E03 cap triangles,
        # rather than trusting the producer's selected nearby obstacle volumes.
        independent_volumes=[(p,vby[id]['bottom'],vby[id]['top']) for id in fby for p in vby[id]['rings']]
        xs=[p[0] for p in route];zs=[p[1] for p in route]
        near_source_meshes=[]
        for key in selected:
            m=meshes[key];verts=m['vertices']
            if max(verts[0::3]) < min(xs)-8 or min(verts[0::3]) > max(xs)+8 or max(verts[2::3])<min(zs)-8 or min(verts[2::3])>max(zs)+8:continue
            near_source_meshes.append(m)
            lo=m['bottom_y_m'];hi=m['top_y_m']
            if by[m['metadata']['feature_id']]['geometry']['type'] in ('Polygon','MultiPolygon'):
                independent_volumes.extend((p,lo,hi) for p in feature_polygons(by[m['metadata']['feature_id']]))
            else:
                for i in range(0,len(verts),9):
                    tri=verts[i:i+9]
                    if all(near(tri[j],hi,1e-6) for j in (1,4,7)):
                        independent_volumes.append(([[[tri[j],tri[j+2]] for j in (0,3,6)]],lo,hi))
        independent_bounds=volume_bounds(independent_volumes)
        raw=record['cases']; cases={c['name']:c for c in raw}
        wanted={'idle'}|{'route_'+d+'_'+str(i) for d in ('in','out') for i in range(3)}|{'gate_'+d+'_'+str(i) for d in ('forward','reverse') for i in range(10)}|{'block_'+d+'_'+s for d in ('front','back') for s in ('left','right')}
        check('cases.coverage',len(raw)==len(cases)==31 and set(cases)==wanted)
        for title in sorted(wanted):
            c=cases[title]; samples=c['samples']; stats=c['all_tick_stats']; ws=c['W01_stats']
            duration=c['duration_s']; ticks=c['ticks']
            check(title+'.clock',number(duration) and duration>0 and ticks>0 and near(ticks/60,duration,.001) and c['recoveries']==0 and len(samples)>=math.ceil(ticks/6) and len(samples)<=ticks+1)
            if gpu:
                check(title+'.real_clock',abs(c['wall_s']-duration)<=duration*.02 and abs(c['frames']/c['wall_s']-eng['render_fps'])<=eng['render_fps']*.2)
            check(title+'.all_ticks',ws['ticks']==ticks and 0<=ws['max_player_penetration_m']<=.005 and 0<=ws['max_camera_penetration_m']<=.005 and ws['floor_support_ticks']==ticks and stats['ticks']==ticks and stats['floor_ticks']==ticks and stats['max_camera_overlap_count']==0 and stats['max_near_hit_count']==0 and stats['max_follow_error_m']<=.002 and stats['max_length_excess_m']<=.002 and stats['max_tick_mismatch']==0 and 0<=stats['min_distance']<=stats['max_distance']<=6.002 and -.005<=stats['min_player_y']<=stats['max_player_y']<=.005 and stats['camera_max_step_m']>=0)
            check(title+'.sample_clock',len(samples)>=2 and 0<=samples[0]['t']<=.02 and near(samples[-1]['t'],duration,.0001) and all(0<b['t']-a['t']<=.11 for a,b in zip(samples,samples[1:])) and near(c['start'],samples[0]['player'],.07) and near(c['end'],samples[-1]['player'],.002))
            worst_player=0.;worst_camera=0.;bad=[]
            for i,s in enumerate(samples):
                p=s['player'];rig=s['rig'];cp=rig['camera']
                if not(vector(p) and vector(cp)):raise ValueError('Invalid retained position')
                pp=indexed_penetration([p[0],p[1]+.85,p[2]],independent_volumes,independent_bounds,.3,.55);pc=indexed_penetration(cp,independent_volumes,independent_bounds,.2)
                worst_player=max(worst_player,pp);worst_camera=max(worst_camera,pc)
                corners=s['near_corners']; corner_hits=any(b<v[1]<t and xmin<v[0]<xmax and zmin<v[2]<zmax and polygon_inside([v[0],v[2]],poly) for v in corners for (poly,b,t),(xmin,xmax,zmin,zmax) in zip(independent_volumes,independent_bounds))
                pivot=[p[0],p[1]+1.3,p[2]]
                basis=rig['basis']
                geometry_ok=len(corners)==4 and all(vector(v) for v in corners) and len(basis)==3 and all(vector(v) for v in basis)
                if geometry_ok:
                    offsets=[sub(v,cp) for v in corners]
                    local=[[sum(a*b for a,b in zip(v,col)) for col in basis] for v in offsets]
                    hw=max(abs(v[0]) for v in local);hh=max(abs(v[1]) for v in local)
                    fhalf=rig['near']*math.tan(math.radians(rig['fov'])/2)
                    geometry_ok=(all(near(norm(col),1,.002) for col in basis) and all(abs(sum(a*b for a,b in zip(basis[j],basis[k])))<=.002 for j,k in ((0,1),(0,2),(1,2))) and near([pivot[j]+basis[2][j]*rig['distance'] for j in range(3)],cp,.002) and max(norm(v) for v in offsets)<=.200001 and len({(1 if v[0]>0 else -1,1 if v[1]>0 else -1) for v in local})==4 and all(near(v[2],-rig['near'],.0001) and near(abs(v[0]),hw,.0001) and near(abs(v[1]),hh,.0001) for v in local) and hh>0 and near(hw/hh,rig['aspect'],.002) and (near(hw,fhalf,.0001) or near(hh,fhalf,.0001)) and near(rig['near'],.05,1e-6) and near(rig['fov'],65,1e-6))
                okay=(geometry_ok and abs(p[1])<=.005 and any(polygon_inside([p[0],p[2]],v) for v in support) and stats['min_distance']-.002<=rig['distance']<=stats['max_distance']+.002 and stats['min_player_y']-.002<=p[1]<=stats['max_player_y']+.002 and pp<=.005 and pc<=.005 and near(s['player_penetration_m'],pp,.0001) and near(s['camera_penetration_m'],pc,.0001) and ws['max_player_penetration_m']+.0001>=pp and ws['max_camera_penetration_m']+.0001>=pc and s['floor'] is True and s['floor_id']=='W01_support' and near(s['floor_normal'],[0,1,0],.002) and s['camera_overlap']==[] and s['near_ray_hits']==[] and not corner_hits and near(rig['pivot'],pivot) and rig['mask']==1 and near(rig['probe_radius'],.2,1e-6) and rig['follow_ticks']==rig['observed_ticks'] and 0<=rig['distance']<=rig['hit_length']+.002<=rig['requested_distance']+.004 and 2<=rig['requested_distance']<=6 and near(norm(sub(cp,pivot)),rig['distance']) and rig['input_enabled'] is True and rig['mouse_mode']==(2 if gpu else 0) and math.radians(-55)-1e-6<=rig['pitch']<=math.radians(15)+1e-6)
                if not okay:bad.append(i)
            check(title+'.independent_samples',not bad,{'failed_sample_indices':bad,'max_player_penetration_m':worst_player,'max_camera_penetration_m':worst_camera})
            horizontal=lambda v:[v[0],v[2]]
            if title=='idle':
                check(title+'.stable',duration>=(2 if gpu and eng['render_fps']==30 else 60)-1e-6 and all(norm(sub(s['player'],samples[0]['player']))<=.001 for s in samples) and stats['max_player_y']-stats['min_player_y']<=.001)
            elif title.startswith('route_'):
                _,direction,index=title.split('_');index=int(index)
                points=route if direction=='in' else list(reversed(route))
                check(title+'.source_leg',near(horizontal(c['start']),points[index],.06) and near(horizontal(c['end']),points[index+1],.18) and all(edge_distance(horizontal(s['player']),points[index],points[index+1])<=.08 for s in samples) and abs(norm(sub(horizontal(c['end']),horizontal(c['start'])))-3.5*duration)<=.02*3.5*duration+.12)
            elif title.startswith('gate_'):
                direction=1 if title.startswith('gate_forward') else -1
                u=plan['direction_xz']; midpoint=[(a+b)/2 for a,b in zip(outside,inside)]
                projection=lambda v:sum((v[i]-midpoint[i])*u[i] for i in range(2))
                speed=1.4 if title.endswith('_0') else 3.5
                travelled=norm(sub(horizontal(c['end']),horizontal(c['start'])))
                yaw=[s['rig']['yaw'] for s in samples]
                rotation=max(abs(math.atan2(math.sin(y-yaw[0]),math.cos(y-yaw[0]))) for y in yaw)
                check(title+'.actual_passage_crossing',direction*projection(horizontal(c['start']))<=-plan['passage_length_m']/2-1.5 and direction*projection(horizontal(c['end']))>=plan['passage_length_m']/2+1.5 and abs(travelled-speed*duration)<=.02*speed*duration+.15 and rotation>.1 and ws['solid_contact_ticks']==0)
            else:
                check(title+'.solid_contact',ws['solid_contact_ticks']>0 and any(id.startswith('W01_gate_side') or id=='W01_palace_wall' for id in ws['contact_ids']) and norm(sub(horizontal(c['end']),horizontal(c['start'])))<1.7)
        check('full_routes',len(record['full_routes'])==2 and {r['direction'] for r in record['full_routes']}=={'in','out'} and all(r['legs']==['route_'+r['direction']+'_'+str(i) for i in range(3)] for r in record['full_routes']))
        events=record['events'];eby={e['name']:e for e in events}
        check('events.coverage',len(events)==len(eby)==4 and set(eby)=={'menu','fall','outside_test_area','manual_restart'})
        menu=eby['menu']
        check('menu.actual_pause_and_capture',menu['paused'] is True and menu['actor_ticks']==0 and menu['rig_ticks']==0 and menu['drift']<=.001 and menu['yaw_drift']<=1e-6 and menu['mouse_open']==0 and menu['capture_open'] is False and menu['mouse_closed']==(2 if gpu else 0) and menu['capture_closed'] is True and menu['first_motion_ignored'] is True and menu['held_drift']<=.002 and .65<=menu['release_move_m']<=.75)
        heading=math.atan2(-plan['direction_xz'][0],-plan['direction_xz'][1])
        for reason in ('fall','outside_test_area','manual_restart'):
            e=eby[reason]
            check('recovery.'+reason,e['reason']==reason and e['recoveries']==1 and e['latched'] is True and e['spawn_valid'] is True and near([e['point'][0],e['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.002) and -.002<=e['point'][1]<=plan['spawn'][1]+.002 and e['floor'] is True and e['held_drift']<=.002 and .65<=e['release_move_m']<=.75 and abs(math.atan2(math.sin(e['yaw']-heading),math.cos(e['yaw']-heading)))<=.002 and near(e['pitch'],math.radians(-15),.002) and near(e['requested_distance'],4.5,.002))
        rays=record['rays'];rb={r['name']:r for r in rays}
        check('rays.coverage',len(rays)==len(rb)==5 and set(rb)=={'gate_center','lintel','wall_left','wall_right','off_support'})
        for name in rb:
            ray=rb[name]
            expected_id={'gate_center':'','lintel':'W01_gate_lintel','wall_left':'W01_palace_wall','wall_right':'W01_palace_wall','off_support':''}[name]
            check('ray.'+name+'.observed',ray['hit'] is bool(expected_id) and ray['id']==expected_id and ray['isolated_wall'] is name.startswith('wall_') and vector(ray['from']) and vector(ray['to']) and (vector(ray['position']) if expected_id else ray['position']==[]))
            candidates=[fby['W01_palace_wall']] if name.startswith('wall_') else fragments+near_source_meshes
            hits=[]
            for m in candidates:
                verts=m['vertices']
                for i in range(0,len(verts),9):
                    point=ray_triangle(ray['from'],ray['to'],[verts[i+j:i+j+3] for j in (0,3,6)])
                    if point is not None:hits.append((norm(sub(point,ray['from'])),m['id'],point))
            first=min(hits,key=lambda h:h[0]) if hits else None
            check('ray.'+name+'.independent_source_hit',(first is None) if not expected_id else first is not None and first[1]==expected_id and near(first[2],ray['position'],.002))
            u=plan['direction_xz'];n=plan['normal_xz']
            if name in ('gate_center','lintel'):
                from_xz=[outside[i]-u[i]*2 for i in range(2)];to_xz=[inside[i]+u[i]*2 for i in range(2)]
            elif name.startswith('wall_'):
                sign=1 if name=='wall_left' else -1
                from_xz=[outside[i]-u[i]*2+sign*n[i]*6 for i in range(2)]
                to_xz=[outside[i]+u[i]*2+sign*n[i]*6 for i in range(2)]
            else:from_xz=to_xz=[route[0][i]+n[i]*6 for i in range(2)]
            check('ray.'+name+'.source_xz',near([ray['from'][0],ray['from'][2]],from_xz,.0001) and near([ray['to'][0],ray['to'][2]],to_xz,.0001))
            expected_y=3.5 if name=='lintel' else 1.
            check('ray.'+name+'.source_endpoints',near(ray['from'][1],expected_y,1e-6) and near(ray['to'][1],-1. if name=='off_support' else expected_y,1e-6))
        captures=record['captures']
        expected_captures={'outside_spawn','inside_entry','return_outside','gate_inside','gate_outside','under_gate','wall_contact','menu'}
        check('actual_gpu_captures',not captures if not gpu else len(captures)==8 and {c['name'] for c in captures}==expected_captures and all(c['width']>0 and c['height']>0 for c in captures))
        # Event/ray checks are appended by the observed producer schema below.
    except (KeyError,TypeError,ValueError,IndexError,AttributeError,ZeroDivisionError,OverflowError,struct.error) as error:
        check('read_or_schema',False,str(error))
    return {'task':'W01','passed':bool(checks) and all(c['passed'] for c in checks),'checks':checks}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--plan',type=Path,default=Path('game/data/generated/daehanmun.json'))
    p.add_argument('--world',type=Path,default=Path('game/resources/world_geometry/world.json'))
    p.add_argument('--features',type=Path,default=Path('data/processed/features.json'))
    a=p.parse_args()
    try:
        record,plan,world,features=[json.loads(path.read_text()) for path in (a.input,a.plan,a.world,a.features)]
        result=audit(record,plan,world,features)
        matched=(record['plan_sha256']==hashlib.sha256(a.plan.read_bytes()).hexdigest() and plan['provenance']['game/resources/world_geometry/world.json']==hashlib.sha256(a.world.read_bytes()).hexdigest() and plan['provenance']['data/processed/features.json']==hashlib.sha256(a.features.read_bytes()).hexdigest())
        result['checks'].append({'name':'source_plan_file_bytes','passed':matched});result['passed'] &= matched
    except (OSError,ValueError,KeyError,TypeError) as error:result={'task':'W01','passed':False,'checks':[{'name':'read_or_schema','passed':False,'details':str(error)}]}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Independent W02 source/retained-evidence audit, standard library only.

Never imports the GIS generator or executes Godot. Independent retained sample
geometry is distinct from engine-produced every-tick extrema.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from check_daehanmun_evidence import (number, vector, near, sub, norm, edges,
    ring_inside, polygon_inside, polygon_distance, edge_distance,
    feature_polygons, float32_digest, canonical_digest, polygon_area,
    signed_area, volume_distance, volume_bounds, indexed_penetration, ray_triangle)


def polygons(geometry):
    if geometry['type']=='Polygon':return [geometry['coordinates']]
    if geometry['type']=='MultiPolygon':return geometry['coordinates']
    raise ValueError('Expected polygon geometry')


def line_length(points):
    return sum(norm(sub(b,a)) for a,b in zip(points,points[1:]))


def line_distance(point,points):
    return min(edge_distance(point,a,b) for a,b in zip(points,points[1:]))


def line_buffer_parts(points,radius):
    """Flat segment strips plus offset-line mitre joins, without GIS code."""
    segments=[];parts=[]
    for a,b in zip(points,points[1:]):
        delta=sub(b,a);length=norm(delta)
        if length<=1e-12:continue
        u=[v/length for v in delta];n=[-u[1],u[0]]
        segments.append((a,b,u,n))
        parts.append([[[a[i]+n[i]*radius for i in range(2)],
                       [b[i]+n[i]*radius for i in range(2)],
                       [b[i]-n[i]*radius for i in range(2)],
                       [a[i]-n[i]*radius for i in range(2)]]])
    pairs=list(zip(segments,segments[1:]))
    if near(points[0],points[-1],1e-9):pairs.append((segments[-1],segments[0]))
    cross=lambda a,b:a[0]*b[1]-a[1]*b[0]
    for previous,current in pairs:
        a,b,u,n=previous;c,d,v,k=current
        det=cross(u,v)
        if abs(det)<1e-12:continue
        for sign in (-1,1):
            p=[b[i]+sign*n[i]*radius for i in range(2)]
            q=[c[i]+sign*k[i]*radius for i in range(2)]
            t=cross(sub(q,p),v)/det;join=[p[i]+t*u[i] for i in range(2)]
            # Shapely's default mitre limit 5; no source route needs bevel fallback.
            if norm(sub(join,b))<=5*radius+1e-8:parts.append([[p,join,q]])
    return parts


def strictly_inside(point,poly,tolerance=.00002):
    return polygon_inside(point,poly) and min(edge_distance(point,a,b) for ring in poly for a,b in edges(ring))>tolerance


def volume_from_mesh(mesh):
    verts=mesh['vertices'];lo=mesh['bottom_y_m'];hi=mesh['top_y_m'];result=[]
    for i in range(0,len(verts),9):
        t=verts[i:i+9]
        if all(near(t[j],hi,1e-7) for j in (1,4,7)):
            result.append(([[[t[j],t[j+2]] for j in (0,3,6)]],lo,hi))
    return result


def segment_inside_union(a,b,polys):
    """Partition a segment at every polygon boundary, then test each interval."""
    d=sub(b,a);cross=lambda x,y:x[0]*y[1]-x[1]*y[0];cuts=[0.,1.]
    for poly in polys:
        for ring in poly:
            for c,e in edges(ring):
                side=sub(e,c);det=cross(d,side)
                if abs(det)<1e-12:continue
                offset=sub(c,a);t=cross(offset,side)/det;u=cross(offset,d)/det
                if 0<=t<=1 and 0<=u<=1:cuts.append(t)
    cuts=sorted(set(cuts))
    return all(any(polygon_inside([a[k]+d[k]*(x+y)/2 for k in range(2)],p) for p in polys) for x,y in zip(cuts,cuts[1:]) if y-x>1e-9)


def audit(record,plan,world,features):
    checks=[]
    def ck(name,passed,details=None):
        item={'name':name,'passed':bool(passed)}
        if details is not None:item['details']=details
        checks.append(item)
    def finite(x):
        if isinstance(x,float):return math.isfinite(x)
        if isinstance(x,dict):return all(finite(v) for v in x.values())
        if isinstance(x,list):return all(finite(v) for v in x)
        return True
    try:
        ck('schema',record['schema_version']==1 and record['task']=='W02' and plan['task']=='W02' and world['task']=='E03' and features['task_id']=='G02')
        ck('finite_values',all(finite(v) for v in (record,plan,world,features)))
        by={f['feature_id']:f for f in features['features']};meshes={m['id']:m for m in world['meshes']}
        out=by['osm:way:377289813:highway_line'];ret=by['osm:way:377289810:highway_line'];court=by['osm:relation:5681909:highway_area']
        start=out['source_topology']['node_ids'].index(921242931);join=ret['source_topology']['node_ids'].index(921242850);finish=ret['source_topology']['node_ids'].index(921242931)
        source=out['geometry']['coordinates'][start:]+list(reversed(ret['geometry']['coordinates'][finish:join]))
        nodes=out['source_topology']['node_ids'][start:]+list(reversed(ret['source_topology']['node_ids'][finish:join]))
        routes={r['id']:r for r in plan['routes']};loop=routes['palace_loop'];runtime=loop['xz']
        ck('source_loop',len(source)==len(nodes)==24 and near(loop['source_xz'],source,1e-8) and loop['source_node_ids']==nodes and nodes[0]==nodes[-1]==921242931 and near(loop['source_length_m'],line_length(source),1e-7) and near(loop['source_length_m'],564.412107,.00001) and all(f['source_tags']['highway']=='footway' and f['source_tags']['access']=='permissive' and f['access']['game_permission'] is None for f in (out,ret)))
        corrections=plan['source_leg_corrections'];assembled=[corrections[0]['runtime_xz'][0]];deviations=[]
        ck('route_correction_coverage',len(corrections)==23)
        for i,c in enumerate(corrections):
            points=c['runtime_xz'];a,b=source[i:i+2];distance=norm(sub(b,a));steps=max(1,math.ceil(distance/.05))
            directed=max(edge_distance(p,a,b) for p in points)
            inverse=max(line_distance([a[k]+(b[k]-a[k])*j/steps for k in range(2)],points) for j in range(steps+1))
            measured=max(directed,inverse);deviations.append(measured);assembled.extend(points[1:])
            ck('source_leg.'+str(i),c['leg']==i and c['source_nodes']==nodes[i:i+2] and near(c['source_xz'],source[i:i+2],1e-8) and near(c['maximum_deviation_m'],measured,.03) and measured+.025<=.75 and (i==0 or near(corrections[i-1]['runtime_xz'][-1],points[0],1e-8)))
        ck('runtime_loop',near(runtime,assembled,1e-8) and near(runtime[0],runtime[-1],1e-8) and near(loop['length_m'],line_length(runtime),1e-7) and near(plan['diagnostics']['maximum_loop_adjustment_m'],max(deviations),.03))
        support=plan['support'];sp=polygons(support['geometry']);movement=plan['movement_rings'];verts=support['vertices']
        caparea=sum(polygon_area(p) for p,b,t in volume_from_mesh(support))
        ck('support_geometry',support['id']=='W02_support' and support['bottom_y_m']==-.2 and support['top_y_m']==0 and len(verts)//9==1068 and len(sp)==1 and len(sp[0])-1==2 and plan['counts']=={'source_bodies':685,'active_source_bodies':682,'retained_gate_wall_fragments':4,'active_bodies':687,'created_bodies':691,'support_triangles':1068} and abs(caparea-sum(polygon_area(p) for p in sp))<=.01)
        courtpolys=feature_polygons(court);eligible= courtpolys+line_buffer_parts(source,1.2)
        # The entrance strip comes from original W01 corridor coordinates. Its
        # support has 2m endpoint extensions, 3m half width, unchanged at W02.
        entrance=routes['entrance']['xz'];first=sub(entrance[1],entrance[0]);last=sub(entrance[-1],entrance[-2])
        extended=[[entrance[0][i]-2*first[i]/norm(first) for i in range(2)],*entrance,[entrance[-1][i]+2*last[i]/norm(last) for i in range(2)]]
        eligible+=line_buffer_parts(extended,3.)
        exclusions=plan['exclusions'];forbidden=[];expected_exclusion_ids=set()
        # Recompute all source semantic exclusions that intersect actual support.
        semantic=[]
        for f in by.values():
            tags=f['source_tags'];g=f['geometry'];pp=[]
            if g['type'] in ('Polygon','MultiPolygon') and (tags.get('landuse')=='grass' or tags.get('natural')=='water' or tags.get('amenity')=='fountain'):
                pp=feature_polygons(f)
            elif tags.get('highway')=='steps' and tags.get('access')=='no':pp=line_buffer_parts(g['coordinates'],1.2)
            if pp:semantic.append((f['feature_id'],pp))
        for id,pp in semantic:forbidden.extend(pp)
        forbidden.extend([[hole] for poly in courtpolys for hole in poly[1:]])
        solid_polygons=[]
        sx=[v[0] for v in sp[0][0]];sz=[v[1] for v in sp[0][0]]
        disabled_source={'osm:way:377289797:building','osm:way:26658458:barrier','temporary_support'}
        for id,mesh in meshes.items():
            if id in disabled_source or mesh['role'] not in ('Buildings','Barriers'):continue
            vv=mesh['vertices']
            if max(vv[0::3])<min(sx) or min(vv[0::3])>max(sx) or max(vv[2::3])<min(sz) or min(vv[2::3])>max(sz):continue
            f=by[mesh['metadata']['feature_id']];g=f['geometry']
            if g['type'] in ('Polygon','MultiPolygon'):solid_polygons.extend(feature_polygons(f))
            elif g['type']=='LineString':solid_polygons.extend(line_buffer_parts(g['coordinates'],world['display']['barrier_thickness_m']/2))
            elif g['type']=='MultiLineString':
                for line in g['coordinates']:solid_polygons.extend(line_buffer_parts(line,world['display']['barrier_thickness_m']/2))
        forbidden.extend(solid_polygons)
        for e in exclusions:
            id=e['id'];f=by[id];tags=f['source_tags']
            ck('exclusion.'+id,('source solid' in e['reason'] and id in meshes and meshes[id]['role'] in ('Buildings','Barriers')) or ('lawn/water/fountain' in e['reason'] and (tags.get('landuse')=='grass' or tags.get('natural')=='water' or tags.get('amenity')=='fountain')) or ('restricted stairs' in e['reason'] and tags.get('highway')=='steps' and tags.get('access')=='no'))
        points=[]
        for i in range(0,len(verts),9):
            tri=verts[i:i+9]
            if all(near(tri[j],0,1e-7) for j in (1,4,7)):
                ps=[[tri[j],tri[j+2]] for j in (0,3,6)]
                points.extend(ps+[[sum(p[k] for p in ps)/3 for k in range(2)]])
        bad=[p for p in points if not any(polygon_inside(p,poly) or polygon_distance(p,poly)<=.00002 for poly in eligible) or any(strictly_inside(p,poly) for poly in forbidden)]
        ck('support_source_semantic_eligibility',not bad,{'bad_count':len(bad),'first_bad_points':bad[:8]})
        ck('court_viewpoint',court['source_tags']['highway']=='pedestrian' and any(polygon_inside([-130,-40],p) for p in courtpolys) and any(polygon_inside([-130,-40],p) for p in movement) and routes['court_approach']['xz'][-1]==[-130.,-40.] and plan['checkpoints'][-1]['source_node'] is None)
        ck('bounded_movement_area',all(any(polygon_inside(v,p) for p in sp) for poly in movement for ring in poly for v in ring) and all(any(polygon_inside(p,poly) for poly in movement) for p in runtime) and all(segment_inside_union(a,b,movement) for a,b in zip(runtime,runtime[1:])))
        scope=plan['scope'];ck('scope_limits',scope['physical_terrain_verified'] is False and scope['real_world_access_verified'] is False and scope['global_playable_boundary'] is None and scope['source_display_permissions']=='unchanged/null' and scope['building_interiors']=='unresolved/excluded')
        ck('plan_sha256',record['plan_sha256']==canonical_digest(plan))
        ck('world_provenance',plan['provenance']['game/resources/world_geometry/world.json']==canonical_digest(world))
        w01_path=Path(__file__).resolve().parents[1]/'game/data/generated/daehanmun.json'
        w01=json.loads(w01_path.read_text())
        ck('w01_provenance',plan['provenance']['game/data/generated/daehanmun.json']==hashlib.sha256(w01_path.read_bytes()).hexdigest() and all(near(plan[k],w01[k],1e-8) for k in ('spawn','route_xz','direction_xz','normal_xz','passage_length_m')))
        inv=record['inventory'];sources=inv['source_bodies'];fragments=inv['fragments'];sby={b['id']:b for b in sources};fby={b['id']:b for b in fragments};old={f['id']:f for f in w01['fragments']}
        selected={k for k,m in meshes.items() if m['role'] in ('Buildings','Barriers')}|{'temporary_support'}
        ck('inventory.source_coverage',len(sources)==len(sby)==685 and set(sby)==selected)
        ck('inventory.fragment_coverage',len(fragments)==len(fby)==6 and set(fby)==set(old)|{'W02_support'})
        ck('inventory.census',inv['created_body_count']==691 and inv['active_body_count']==687)
        disabled={b['id']:b for b in inv['disabled_bodies']}
        ck('inventory.actual_disabled_bodies',len(inv['disabled_bodies'])==len(disabled)==3 and set(disabled)==disabled_source and set(inv['disabled_ids'])==disabled_source and all(b['layer']==0 and b['mask']==0 and b['visible'] is False for b in disabled.values()))
        for id,body in sby.items():
            active=id not in disabled_source
            ck('inventory.'+id,body['layer']==(1 if active else 0) and body['mask']==(14 if active else 0) and body['identity'] is True and body['disabled'] is False and body['shape']=='ConcavePolygonShape3D' and body['backface'] is True and body['face_sha256']==float32_digest(meshes[id]['vertices']))
        for id,body in fby.items():
            expected=support if id=='W02_support' else old[id];active=id!='W01_support';digest=float32_digest(expected['vertices'])
            ck('inventory.'+id,body['layer']==(1 if active else 0) and body['mask']==(14 if active else 0) and body['visible'] is active and body['identity'] is True and body['disabled'] is False and body['shape']=='ConcavePolygonShape3D' and body['backface'] is True and body['face_sha256']==digest and body['visual_face_sha256']==digest)
        actor=record['actor'];contract={'height':1.7,'radius':.3,'layer':2,'mask':13,'walk_mps':1.4,'run_mps':3.5,'gravity':9.8,'safe_margin':.001,'camera_mask':1,'camera_probe_radius':.2}
        ck('actual_player_contract',all(near(actor[k],v,1e-6) for k,v in contract.items()) and actor['player_camera_path_matches'] is True)
        engine=record['engine'];gpu=engine['display'].lower()!='headless';suite=record['suite'];full=suite=='full'
        ck('engine',suite in ('full','short') and engine['physics_hz']==60 and engine['render_fps'] in (30,60) and (not gpu or engine['renderer'].lower() not in ('','headless')))
        ck('suite_scope',not gpu or (engine['render_fps']==60 and full) or (engine['render_fps']==30 and not full))
        spawn=record['spawn'];ck('spawn_valid',near([spawn['point'][0],spawn['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.00003) and abs(spawn['point'][1])<=.002 and spawn['valid'] is True and spawn['volume_guard_clear'] is True and any(polygon_inside([spawn['point'][0],spawn['point'][2]],p) for p in movement))
        # Recover preserved source volumes without trusting volume_obstacles.
        volumes=[];near_meshes=[]
        for id in selected-disabled_source:
            mesh=meshes[id];v=mesh['vertices']
            if max(v[0::3])<min(sx)-8 or min(v[0::3])>max(sx)+8 or max(v[2::3])<min(sz)-8 or min(v[2::3])>max(sz)+8:continue
            near_meshes.append(mesh);f=by[mesh['metadata']['feature_id']]
            if f['geometry']['type'] in ('Polygon','MultiPolygon'):volumes.extend((p,mesh['bottom_y_m'],mesh['top_y_m']) for p in feature_polygons(f))
            else:volumes.extend(volume_from_mesh(mesh))
        for id,mesh in old.items():
            if id!='W01_support':volumes.extend((p,mesh['bottom_y_m'],mesh['top_y_m']) for p in polygons(mesh['geometry']))
        volumes.extend((p,-.2,0.) for p in sp);bounds=volume_bounds(volumes)
        wanted={'idle','speed_walk','speed_run','gate_forward','gate_reverse','boundary_footway','boundary_lawn','boundary_court_hole','boundary_seok_stairs'}
        if full:wanted|={r['id']+'_'+d+'_'+str(i) for r in routes.values() for d in ('forward','reverse') for i in range(len(r['xz'])-1)}
        raw=record['cases'];cases={c['name']:c for c in raw}
        ck('cases.coverage',len(raw)==len(cases)==len(wanted) and set(cases)==wanted)
        for name in sorted(wanted):
            c=cases[name];samples=c['samples'];stats=c['all_tick_stats'];ws=c['W02_stats'];duration=c['duration_s'];ticks=c['ticks']
            ck(name+'.clock',all(number(c[k]) for k in ('duration_s','wall_s','ticks','frames','recoveries','boundary_stops')) and number(duration) and duration>0 and ticks>0 and near(ticks/60,duration,.0001) and c['wall_s']>0 and c['recoveries']==0 and math.ceil(ticks/6)<=len(samples)<=ticks+1)
            if gpu and name in {'idle','speed_walk','speed_run','gate_forward','gate_reverse','boundary_footway','boundary_lawn','boundary_court_hole','boundary_seok_stairs'}:
                ck(name+'.real_clock',abs(c['wall_s']-duration)<=.02*duration and abs(c['frames']/c['wall_s']-engine['render_fps'])<=.2*engine['render_fps'])
            ck(name+'.all_ticks',all(number(stats[k]) for k in ('ticks','max_camera_overlap_count','max_near_hit_count','max_follow_error_m','max_length_excess_m','max_tick_mismatch','floor_ticks','min_distance','max_distance','min_player_y','max_player_y','camera_max_step_m')) and all(number(ws[k]) for k in ('ticks','max_player_penetration_m','max_camera_penetration_m','floor_support_ticks','outside_movement_ticks','solid_contact_ticks')) and ws['ticks']==stats['ticks']==ticks and 0<=ws['max_player_penetration_m']<=.005 and 0<=ws['max_camera_penetration_m']<=.005 and ws['floor_support_ticks']==stats['floor_ticks']==ticks and ws['outside_movement_ticks']==0 and stats['max_camera_overlap_count']==stats['max_near_hit_count']==stats['max_tick_mismatch']==0 and 0<=stats['max_follow_error_m']<=.002 and stats['max_length_excess_m']<=.002 and 0<=stats['min_distance']<=stats['max_distance']<=6.002 and -.005<=stats['min_player_y']<=stats['max_player_y']<=.005)
            ck(name+'.sample_clock',bool(samples) and 0<samples[0]['t']<=.02 and near(samples[-1]['t'],duration,.0001) and all(0<b['t']-a['t']<=.11 for a,b in zip(samples,samples[1:])) and near(c['start'],samples[0]['player'],.07) and near(c['end'],samples[-1]['player'],.002))
            pipeline=c['pipelines'];ck(name+'.pipeline_metadata',all(number(pipeline['before'][k]) and number(pipeline['after'][k]) and 0<=pipeline['before'][k]<=pipeline['after'][k] for k in ('mesh','surface','draw')))
            bad=[];worstp=0.;worstc=0.
            for i,s in enumerate(samples):
                p=s['player'];rig=s['rig'];camera=rig['camera'];pivot=[p[0],p[1]+1.3,p[2]]
                pp=indexed_penetration([p[0],p[1]+.85,p[2]],volumes,bounds,.3,.55);pc=indexed_penetration(camera,volumes,bounds,.2);worstp=max(worstp,pp);worstc=max(worstc,pc)
                corners=s['near_corners'];basis=rig['basis'];local=[[sum(a*b for a,b in zip(sub(corner,camera),col)) for col in basis] for corner in corners]
                hw=max(abs(v[0]) for v in local);hh=max(abs(v[1]) for v in local);fhalf=rig['near']*math.tan(math.radians(rig['fov'])/2)
                plane=(len(corners)==4 and len(basis)==3 and all(vector(v) for v in corners+basis) and all(near(norm(col),1,.002) for col in basis) and all(abs(sum(a*b for a,b in zip(basis[j],basis[k])))<=.002 for j,k in ((0,1),(0,2),(1,2))) and near([pivot[j]+basis[2][j]*rig['distance'] for j in range(3)],camera,.002) and max(norm(sub(corner,camera)) for corner in corners)<=.200001 and len({(1 if v[0]>0 else -1,1 if v[1]>0 else -1) for v in local})==4 and all(near(v[2],-rig['near'],.0001) and near(abs(v[0]),hw,.0001) and near(abs(v[1]),hh,.0001) for v in local) and hh>0 and near(hw/hh,rig['aspect'],.002) and (near(hw,fhalf,.0001) or near(hh,fhalf,.0001)) and near(rig['near'],.05,1e-6) and near(rig['fov'],65,1e-6))
                cornerhit=any(b<v[1]<t and xmin<v[0]<xmax and zmin<v[2]<zmax and polygon_inside([v[0],v[2]],poly) for v in corners for (poly,b,t),(xmin,xmax,zmin,zmax) in zip(volumes,bounds))
                okay=(plane and not cornerhit and abs(p[1])<=.005 and s['inside_movement'] is True and any(polygon_inside([p[0],p[2]],v) for v in movement) and pp<=.005 and pc<=.005 and near(s['player_penetration_m'],pp,.0001) and near(s['camera_penetration_m'],pc,.0001) and ws['max_player_penetration_m']+.0001>=pp and ws['max_camera_penetration_m']+.0001>=pc and s['floor'] is True and s['floor_id']=='W02_support' and near(s['floor_normal'],[0,1,0],.002) and s['camera_overlap']==[] and s['near_ray_hits']==[] and near(rig['pivot'],pivot) and rig['mask']==1 and near(rig['probe_radius'],.2,1e-6) and rig['follow_ticks']==rig['observed_ticks'] and 0<=rig['distance']<=rig['hit_length']+.002<=rig['requested_distance']+.004 and 2<=rig['requested_distance']<=6 and near(norm(sub(camera,pivot)),rig['distance']) and rig['input_enabled'] is True and rig['mouse_mode']==(2 if gpu else 0) and math.radians(-55)-1e-6<=rig['pitch']<=math.radians(15)+1e-6 and stats['min_distance']-.002<=rig['distance']<=stats['max_distance']+.002 and stats['min_player_y']-.002<=p[1]<=stats['max_player_y']+.002)
                if not okay:bad.append(i)
            ck(name+'.independent_samples',not bad,{'failed_sample_indices':bad,'max_player_penetration_m':worstp,'max_camera_penetration_m':worstc})
            horizontal=lambda v:[v[0],v[2]]
            if name=='idle':ck(name+'.stable',duration>=(60 if full else 2)-1e-6 and all(norm(sub(s['player'],samples[0]['player']))<=.001 for s in samples) and stats['max_player_y']-stats['min_player_y']<=.001)
            elif name in ('speed_walk','speed_run'):
                speed=1.4 if name=='speed_walk' else 3.5
                ck(name+'.speed',near(duration,10,.0001) and abs(norm(sub(horizontal(c['end']),horizontal(c['start'])))-speed*duration)<=.02*speed*duration)
            elif name.startswith('gate_'):
                sign=1 if name=='gate_forward' else -1;u=plan['direction_xz'];mid=[(a+b)/2 for a,b in zip(plan['route_xz'][1],plan['route_xz'][2])];projection=lambda point:sum((point[k]-mid[k])*u[k] for k in range(2));yaw=[s['rig']['yaw'] for s in samples]
                ck(name+'.actual_passage_crossing',sign*projection(horizontal(c['start']))<=-plan['passage_length_m']/2-1.5 and sign*projection(horizontal(c['end']))>=plan['passage_length_m']/2+1.5 and abs(norm(sub(horizontal(c['end']),horizontal(c['start'])))-1.4*duration)<=.02*1.4*duration+.15 and max(abs(math.atan2(math.sin(v-yaw[0]),math.cos(v-yaw[0]))) for v in yaw)>.1)
            elif name.startswith('boundary_'):
                ck(name+'.boundary_stop',near(duration,4,.0001) and c['boundary_stops']>0 and norm(sub(horizontal(c['end']),horizontal(c['start'])))<3.5*duration-.5 and all(s['inside_movement'] for s in samples))
        groups=record['route_groups'];gby={(g['route'],g['direction']):g for g in groups};expected_groups={(r,d) for r in routes for d in ('forward','reverse')} if full else set()
        ck('route_groups.coverage',len(groups)==len(gby)==len(expected_groups) and set(gby)==expected_groups)
        for key,g in gby.items():
            rid,direction=key;points=routes[rid]['xz'] if direction=='forward' else list(reversed(routes[rid]['xz']));names=[rid+'_'+direction+'_'+str(i) for i in range(len(points)-1)];rows=[cases[n] for n in names]
            errors=[norm(sub([r['end'][0],r['end'][2]],p)) for r,p in zip(rows,points[1:])]
            ck('group.'+rid+'.'+direction+'.source_route',g['legs']==names and near(g['targets_xz'],points[1:],1e-8) and g['teleports_within_group']==0 and max(errors)<=.18 and near(g['maximum_target_error_m'],max(errors),.00003) and near([rows[0]['start'][0],rows[0]['start'][2]],points[0],.00005) and all(near(a['end'],b['start'],.002) for a,b in zip(rows,rows[1:])) and all(edge_distance([s['player'][0],s['player'][2]],points[i],points[i+1])<=.18 for i,row in enumerate(rows) for s in row['samples']))
            ck('group.'+rid+'.'+direction+'.clock_sums',near(g['duration_s'],sum(r['duration_s'] for r in rows),1e-7) and near(g['wall_s'],sum(r['wall_s'] for r in rows),1e-7) and g['frames']==sum(r['frames'] for r in rows) and abs(3.5*g['duration_s']-routes[rid]['length_m'])<=len(rows)*3.5/60+.18)
            if gpu:ck('group.'+rid+'.'+direction+'.real_clock',abs(g['wall_s']-g['duration_s'])<=.02*g['duration_s'] and abs(g['frames']/g['wall_s']-engine['render_fps'])<=.2*engine['render_fps'])
        ck('boundary_cases.coverage',record['boundary_cases']==['boundary_footway','boundary_lawn','boundary_court_hole','boundary_seok_stairs'])
        events=record['events'];eby={e['name']:e for e in events};ck('events.coverage',len(events)==len(eby)==4 and set(eby)=={'menu','fall','outside_test_area','manual_restart'});menu=eby['menu']
        ck('menu.actual_pause_and_capture',menu['paused'] is True and menu['actor_ticks']==menu['rig_ticks']==0 and menu['drift']<=.001 and menu['yaw_drift']<=1e-6 and menu['mouse_open']==0 and menu['capture_open'] is False and menu['mouse_closed']==(2 if gpu else 0) and menu['capture_closed'] is True and menu['first_motion_ignored'] is True and menu['held_drift']<=.002 and .65<=menu['release_move_m']<=.75)
        heading=math.atan2(-plan['direction_xz'][0],-plan['direction_xz'][1])
        for reason in ('fall','outside_test_area','manual_restart'):
            e=eby[reason];ck('recovery.'+reason,e['reason']==reason and e['recoveries']==1 and e['latched'] is True and e['spawn_valid'] is True and near([e['point'][0],e['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.002) and -.002<=e['point'][1]<=plan['spawn'][1]+.002 and e['floor'] is True and e['held_drift']<=.002 and .65<=e['release_move_m']<=.75 and abs(math.atan2(math.sin(e['yaw']-heading),math.cos(e['yaw']-heading)))<=.002 and near(e['pitch'],math.radians(-15),.002) and near(e['requested_distance'],4.5,.002))
        rays=record['rays'];rb={r['name']:r for r in rays};targets={'gate_center':'','lintel':'W01_gate_lintel','wall_left':'W01_palace_wall','wall_right':'W01_palace_wall','off_support':'','court_hole':'','lawn':'','seokjojeon_stairs':'','court_floor':'W02_support','loop_floor':'W02_support','preserved_retaining_wall':'osm:way:381755262:barrier','preserved_jungwhamun':'osm:way:181574580:building'}
        ck('rays.coverage',len(rays)==len(rb)==12 and set(rb)==set(targets))
        raymeshes=near_meshes+[old[k] for k in old if k!='W01_support']+[support]
        for name,target in targets.items():
            ray=rb[name];ck('ray.'+name,ray['hit'] is bool(target) and ray['id']==target and vector(ray['from']) and vector(ray['to']) and (vector(ray['position']) if target else ray['position']==[]))
            if name in ('court_hole','lawn','seokjojeon_stairs','court_floor','loop_floor'):
                locations={'court_hole':[-125,-60],'lawn':[-11.31,-46.07],'seokjojeon_stairs':[-174.46,-126],'court_floor':[-130,-40],'loop_floor':[-201.81,-32.65]}
                xz=locations[name];expected_from=[xz[0],1,xz[1]];expected_to=[xz[0],-1,xz[1]]
            elif name=='preserved_retaining_wall':expected_from=[-110,1,-60];expected_to=[-115,1,-60]
            elif name=='preserved_jungwhamun':expected_from=[-140,1,-5];expected_to=[-140,1,-35]
            else:
                u=plan['direction_xz'];n=plan['normal_xz'];outside=plan['route_xz'][1];inside=plan['route_xz'][2]
                if name in ('gate_center','lintel'):
                    start=[outside[k]-u[k]*2 for k in range(2)];end=[inside[k]+u[k]*2 for k in range(2)]
                elif name.startswith('wall_'):
                    sign=1 if name=='wall_left' else -1;start=[outside[k]-u[k]*2+sign*n[k]*6 for k in range(2)];end=[outside[k]+u[k]*2+sign*n[k]*6 for k in range(2)]
                else:start=end=[plan['route_xz'][0][k]+n[k]*6 for k in range(2)]
                y=3.5 if name=='lintel' else 1.;expected_from=[start[0],y,start[1]];expected_to=[end[0],-1. if name=='off_support' else y,end[1]]
            ck('ray.'+name+'.source_endpoints',near(ray['from'],expected_from,.00003) and near(ray['to'],expected_to,.00003))
            floor_ray=name in ('court_hole','lawn','seokjojeon_stairs','court_floor','loop_floor');candidates=[support] if floor_ray else [old['W01_palace_wall']] if name.startswith('wall_') else raymeshes
            hits=[]
            for mesh in candidates:
                vv=mesh['vertices']
                for i in range(0,len(vv),9):
                    point=ray_triangle(ray['from'],ray['to'],[vv[i+j:i+j+3] for j in (0,3,6)])
                    if point is not None:hits.append((norm(sub(point,ray['from'])),mesh['id'],point))
            first=min(hits,key=lambda h:h[0]) if hits else None
            ck('ray.'+name+'.independent_source_hit',first is None if not target else first is not None and first[1]==target and near(first[2],ray['position'],.002))
        regression=record['containment_regression'];point=regression['xz']
        distance=min(edge_distance(point,a,b) for poly in movement for ring in poly for a,b in edges(ring))
        ck('containment_regression',near(point,[-131.03157043457,-1.73030984401703],.00002) and regression['current_contains'] is True and isinstance(regression['legacy_contains'],bool) and any(polygon_inside(point,p) for p in movement) and near(distance,.7996440806111793,.00003),{'independent_boundary_distance_m':distance,'legacy_contains':regression['legacy_contains']})
        warm=record['warmup'];ck('warmup_scope',warm['poses']==15 and warm['wall_s']>0 and record['external_movement_events_ignored']>=0)
        captures=record['captures'];expected_captures={'outside_spawn','gate_inside','gate_outside','boundary_footway','boundary_lawn','boundary_court_hole','boundary_seok_stairs','menu'}
        if full:expected_captures|={r+'_'+d for r in routes for d in ('forward','reverse')}|{'checkpoint_'+str(i) for i in range(5)}
        ck('actual_gpu_captures',not captures if not gpu else len(captures)==len(expected_captures) and {c['name'] for c in captures}==expected_captures and all(c['width']>0 and c['height']>0 for c in captures))
    except (OSError,KeyError,TypeError,ValueError,IndexError,AttributeError,ZeroDivisionError,OverflowError) as error:
        ck('read_or_schema',False,str(error))
    return {'task':'W02','passed':bool(checks) and all(c['passed'] for c in checks),'checks':checks}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--plan',type=Path,default=Path('game/data/generated/palace_walk.json'))
    parser.add_argument('--world',type=Path,default=Path('game/resources/world_geometry/world.json'))
    parser.add_argument('--features',type=Path,default=Path('data/processed/features.json'))
    args=parser.parse_args()
    try:
        record,plan,world,features=[json.loads(p.read_text()) for p in (args.input,args.plan,args.world,args.features)]
        result=audit(record,plan,world,features)
        matched=(record['plan_sha256']==hashlib.sha256(args.plan.read_bytes()).hexdigest() and plan['provenance']['game/resources/world_geometry/world.json']==hashlib.sha256(args.world.read_bytes()).hexdigest() and plan['provenance']['data/processed/features.json']==hashlib.sha256(args.features.read_bytes()).hexdigest())
        result['checks'].append({'name':'source_file_bytes','passed':matched});result['passed'] &= matched
    except (OSError,ValueError,KeyError,TypeError) as error:
        result={'task':'W02','passed':False,'checks':[{'name':'read_or_schema','passed':False,'details':str(error)}]}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Independent W03 source/retained-evidence audit, standard library only.

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


from check_palace_evidence import (polygons, line_length, line_distance, line_buffer_parts, strictly_inside, volume_from_mesh, segment_inside_union)


def ring_inside_fast(point,ring,tolerance=1e-9):
    """One-pass boundary-inclusive scalar ray crossing, without per-edge square roots."""
    x,z=point;inside=False
    for a,b in edges(ring):
        dx=b[0]-a[0];dz=b[1]-a[1]
        if min(a[0],b[0])-tolerance<=x<=max(a[0],b[0])+tolerance and min(a[1],b[1])-tolerance<=z<=max(a[1],b[1])+tolerance:
            cross=dx*(z-a[1])-dz*(x-a[0])
            if cross*cross<=tolerance*tolerance*(dx*dx+dz*dz):return True
        if (a[1]>z)!=(b[1]>z) and x<a[0]+dx*(z-a[1])/dz:inside=not inside
    return inside


def polygon_inside(point,polygon):
    return ring_inside_fast(point,polygon[0]) and not any(ring_inside_fast(point,h) for h in polygon[1:])


def volume_distance(point,poly,bottom,top,axis_half=0.):
    p=[point[0],point[2]]
    horizontal=0. if polygon_inside(p,poly) else min(edge_distance(p,a,b) for ring in poly for a,b in edges(ring))
    return math.hypot(horizontal,max(bottom-point[1]-axis_half,point[1]-axis_half-top,0.))


def indexed_penetration(point,volumes,bounds,radius,axis_half=0.):
    worst=0.
    for (poly,b,t),(xmin,xmax,zmin,zmax) in zip(volumes,bounds):
        dx=max(xmin-point[0],point[0]-xmax,0.);dz=max(zmin-point[2],point[2]-zmax,0.);dy=max(b-point[1]-axis_half,point[1]-axis_half-t,0.)
        if dx*dx+dy*dy+dz*dz>=radius*radius:continue
        worst=max(worst,radius-volume_distance(point,poly,b,t,axis_half))
    return worst


def polygon_index(polys):
    return [(p,min(v[0] for v in p[0]),max(v[0] for v in p[0]),min(v[1] for v in p[0]),max(v[1] for v in p[0])) for p in polys]


def indexed_inside(point,index,strict=False,tolerance=.00002):
    for poly,xmin,xmax,zmin,zmax in index:
        if xmin-tolerance<=point[0]<=xmax+tolerance and zmin-tolerance<=point[1]<=zmax+tolerance:
            if strictly_inside(point,poly,tolerance) if strict else polygon_inside(point,poly) or polygon_distance(point,poly)<=tolerance:return True
    return False


def segment_distance(a,b,c,d):
    cross=lambda p,q:p[0]*q[1]-p[1]*q[0];u=sub(b,a);v=sub(d,c);det=cross(u,v)
    if abs(det)>1e-12:
        offset=sub(c,a);t=cross(offset,v)/det;q=cross(offset,u)/det
        if 0<=t<=1 and 0<=q<=1:return 0.
    return min(edge_distance(a,c,d),edge_distance(b,c,d),edge_distance(c,a,b),edge_distance(d,a,b))


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
        ck('schema',record['schema_version']==1 and record['task']=='W03' and plan['task']=='W03' and world['task']=='E03' and features['task_id']=='G02')
        ck('finite_values',all(finite(v) for v in (record,plan,world,features)))
        by={f['feature_id']:f for f in features['features']};meshes={m['id']:m for m in world['meshes']}
        project_root=Path(__file__).resolve().parents[1]
        w02_path=project_root/'game/data/generated/palace_walk.json';w02=json.loads(w02_path.read_text())
        ck('w02_preserved',plan['provenance']['game/data/generated/palace_walk.json']==hashlib.sha256(w02_path.read_bytes()).hexdigest() and plan['routes'][:3]==w02['routes'])
        routes={r['id']:r for r in plan['routes']};public_ids=['city_plaza','stonewall']
        ck('route_ids',list(routes)==['entrance','palace_loop','court_approach',*public_ids] and plan['public_routes']==public_ids)
        specifications=[('osm:way:1530764334:highway_line',14113953845,13012013154),('osm:way:1415923127:highway_line',13721232762,13012013153),('osm:way:1415923126:highway_line',13012013153,11414286298),('osm:way:1230789306:highway_line',11414286298,13721232744),('osm:way:1498257483:highway_line',13721232744,13721232743),('osm:way:1415923123:highway_line',7245912943,13012013129)]
        sections=plan['source_sections'];ck('source_sections.coverage',len(sections)==6);corridors=[]
        for index,(id,start_node,end_node) in enumerate(specifications):
            f=by[id];ns=f['source_topology']['node_ids'];coords=f['geometry']['coordinates'];a=ns.index(start_node);b=ns.index(end_node)
            nodes=ns[min(a,b):max(a,b)+1];points=coords[min(a,b):max(a,b)+1]
            if a>b:nodes=list(reversed(nodes));points=list(reversed(points))
            section=sections[index];tags=f['source_tags'];legs=section['legs'];assembled=[legs[0]['runtime_xz'][0]]
            ck('source_section.'+str(index),section['feature_id']==id and section['node_ids']==nodes and near(section['source_xz'],points,1e-8) and near(section['source_length_m'],line_length(points),1e-7) and len(legs)==len(nodes)-1 and (tags['highway']=='footway' or tags.get('foot')=='designated') and tags.get('tunnel')!='yes' and tags.get('layer','0') in ('0',0))
            for i,leg in enumerate(legs):
                original=points[i:i+2];runtime=leg['runtime_xz'];length=norm(sub(original[1],original[0]));n=max(1,math.ceil(length/.05))
                deviation=max(max(edge_distance(p,*original) for p in runtime),max(line_distance([original[0][k]+(original[1][k]-original[0][k])*j/n for k in range(2)],runtime) for j in range(n+1)))
                ck('source_section.'+str(index)+'.leg.'+str(i),leg['source_nodes']==nodes[i:i+2] and near(leg['source_xz'],original,1e-8) and near(leg['maximum_deviation_m'],deviation,.03) and deviation+.025<=.75 and (i==0 or near(legs[i-1]['runtime_xz'][-1],runtime[0],1e-8)))
                assembled.extend(runtime[1:])
            ck('source_section.'+str(index)+'.runtime',near(section['runtime_xz'],assembled,1e-8))
            first=sub(points[1],points[0]);last=sub(points[-1],points[-2]);square=[[points[0][k]-1.2*first[k]/norm(first) for k in range(2)],*points,[points[-1][k]+1.2*last[k]/norm(last) for k in range(2)]]
            corridors.extend(line_buffer_parts(square,1.2))
        areas=['osm:way:776588359:highway_area','osm:way:768397718:highway_area','osm:relation:6012272:highway_area'];area_polys=[]
        for id in areas:
            ck('source_area.'+id,by[id]['source_tags']['highway']=='pedestrian');area_polys.extend(feature_polygons(by[id]))
        sp=polygons(plan['support']['geometry']);movement=plan['movement_rings'];support=plan['support'];verts=support['vertices'];sx=[p[0] for p in sp[0][0]];sz=[p[1] for p in sp[0][0]]
        caparea=sum(polygon_area(p) for p,b,t in volume_from_mesh(support))
        ck('support_geometry',support['id']=='W03_support' and support['bottom_y_m']==-.2 and support['top_y_m']==0 and len(verts)//9==3028 and len(sp)==1 and len(sp[0])-1==4 and plan['counts']=={'source_bodies':685,'active_source_bodies':682,'retained_gate_wall_fragments':4,'active_bodies':687,'created_bodies':692,'support_triangles':3028} and abs(caparea-sum(polygon_area(p) for p in sp))<=.02)
        repair=plan['local_support_repair'];repair_polys=polygons(repair['geometry']);original_repair=feature_polygons(by[repair['source']])
        ck('local_support_repair.contract',repair['source']==areas[0] and repair['bounds_xz']==[36.,20.,58.,33.] and repair['outward_m']==.3 and near(sum(polygon_area(p) for p in repair_polys),plan['diagnostics']['repair_area_m2'],.00001) and near(plan['diagnostics']['repair_area_m2'],13.757727402624798,.0001))
        repair_points=[p for poly in repair_polys for ring in poly for p in ring]
        ck('local_support_repair.bounded',all(36-.00002<=p[0]<=58+.00002 and 20-.00002<=p[1]<=33+.00002 and min(polygon_distance(p,poly) for poly in original_repair)<=.30002 for p in repair_points))
        eligible=polygons(w02['support']['geometry'])+area_polys+corridors+repair_polys;forbidden=[]
        for poly in area_polys:forbidden.extend([[hole] for hole in poly[1:]])
        for f in by.values():
            g=f['geometry'];tags=f['source_tags']
            if g['type'] in ('Polygon','MultiPolygon') and (tags.get('landuse')=='grass' or tags.get('natural')=='water' or tags.get('amenity')=='fountain'):forbidden.extend(feature_polygons(f))
            elif tags.get('highway')=='steps':forbidden.extend(line_buffer_parts(g['coordinates'],1.2))
        candidate_path=project_root/'data/processed/boundary_candidate.json';candidate=json.loads(candidate_path.read_text());private=[]
        for id in candidate['private_enclosure_exclusions']:private.extend(feature_polygons(by[id]))
        forbidden.extend(private);ck('boundary.candidate_hash',plan['boundary']['candidate_sha256']==hashlib.sha256(candidate_path.read_bytes()).hexdigest())
        crossings=plan['crossings'];cb={c['id']:c for c in crossings};wanted_crossings={'sejong_marked':(3,['osm:way:1084408283:highway_line','osm:way:378453707:highway_line'],[5194567167,11414286282]),'side_street':(1,['osm:way:431903253:highway_line'],[11414286332]),'west_junction':(5,['osm:way:37400088:highway_line'],[13012013128])}
        ck('source_crossing.marked_tags',by['osm:way:1230789306:highway_line']['source_tags'].get('crossing')=='marked' and by['osm:way:1230789306:highway_line']['source_tags'].get('crossing:markings')=='zebra')
        ck('source_crossings.coverage',len(crossings)==len(cb)==3 and set(cb)==set(wanted_crossings))
        crossing_polys=[]
        for id,(index,roads,nodes) in wanted_crossings.items():
            c=cb[id];ss=sections[index];cp=polygons(c['geometry']);crossing_polys.extend(cp)
            ck('source_crossing.'+id,c['feature_id']==ss['feature_id'] and c['road_ids']==roads and c['shared_nodes']==nodes and near(c['source_xz'],ss['source_xz'],1e-8) and c['vehicle_controller'] is False and all(node in ss['node_ids'] and node in by[road]['source_topology']['node_ids'] for road,node in zip(roads,nodes)))
            if id!='sejong_marked':
                centre=ss['source_xz'][ss['node_ids'].index(nodes[0])]
                ck('source_crossing.'+id+'.local_radius',all(norm(sub(p,centre))<=2.00002 for poly in cp for ring in poly for p in ring))
            ck('source_crossing.'+id+'.footway_width',all(indexed_inside(p,polygon_index(line_buffer_parts(ss['source_xz'],1.2))) for poly in cp for ring in poly for p in ring))
        road_lines=[]
        for road in plan['road_exclusions']:
            f=by[road['id']];g=f['geometry'];ck('source_road.'+road['id'],road['source_geometry']['type']==g['type'] and near(road['source_geometry']['coordinates'],g['coordinates'],1e-8))
            road_lines.extend([g['coordinates']] if g['type']=='LineString' else g['coordinates'])
        disabled_source={'osm:way:377289797:building','osm:way:26658458:barrier','temporary_support'}
        for id,mesh in meshes.items():
            if id in disabled_source or mesh['role'] not in ('Buildings','Barriers'):continue
            vv=mesh['vertices']
            if max(vv[0::3])<min(sx) or min(vv[0::3])>max(sx) or max(vv[2::3])<min(sz) or min(vv[2::3])>max(sz):continue
            f=by[mesh['metadata']['feature_id']];g=f['geometry']
            if g['type'] in ('Polygon','MultiPolygon'):forbidden.extend(feature_polygons(f))
            else:forbidden.extend(p for p,b,t in volume_from_mesh(mesh))
        sample_points=[]
        for i in range(0,len(verts),9):
            tri=verts[i:i+9]
            if all(near(tri[j],0,1e-7) for j in (1,4,7)):
                ps=[[tri[j],tri[j+2]] for j in (0,3,6)];sample_points.extend(ps+[[sum(p[k] for p in ps)/3 for k in range(2)]])
        eligible_index=polygon_index(eligible);forbidden_index=polygon_index(forbidden)
        bad=[p for p in sample_points if not indexed_inside(p,eligible_index) or indexed_inside(p,forbidden_index,strict=True) or (any(line_distance(p,line)<.49998 for line in road_lines) and not any(polygon_inside(p,poly) or polygon_distance(p,poly)<=.00002 for poly in crossing_polys))]
        ck('support_source_eligibility',not bad,{'bad_count':len(bad),'first_bad_points':bad[:8]})
        ck('source_area_links.coverage',len(plan['area_links'])==2)
        for i,link in enumerate(plan['area_links']):
            f=by[link['feature_id']];mapping={node:point for section in sections for node,point in zip(section['node_ids'],section['source_xz'])};poly=feature_polygons(f)
            ck('source_area_link.'+str(i),link['feature_id']==areas[0] and link['source_nodes']==([13012013154,13721232762] if i==0 else [13012013154,7245912943]) and near(link['source_xz'][0],mapping[link['source_nodes'][0]],1e-8) and near(link['source_xz'][-1],mapping[link['source_nodes'][1]],1e-8) and near(link['source_length_m'],line_length(link['source_xz']),1e-7) and near(link['source_length_m'],12.970095 if i==0 else 327.523544,.00001) and all(segment_inside_union(a,b,poly) for a,b in zip(link['source_xz'],link['source_xz'][1:])) and all(segment_inside_union(a,b,movement) for a,b in zip(link['runtime_xz'],link['runtime_xz'][1:])))
        ck('viewpoints',routes['city_plaza']['viewpoints']==[[130.,-140.],[190.,-100.]] and all(any(polygon_inside(v,p) for p in area_polys) and any(polygon_inside(v,p) for p in movement) for v in routes['city_plaza']['viewpoints']))
        ck('bounded_all_routes',all(any(polygon_inside(v,p) for p in movement) for r in routes.values() for v in r['xz']) and all(segment_inside_union(a,b,movement) for r in routes.values() for a,b in zip(r['xz'],r['xz'][1:])))
        floor_edges=[(a,b) for poly in sp for ring in poly for a,b in edges(ring)]
        clearance=min(segment_distance(a,b,c,d) for id in public_ids for a,b in zip(routes[id]['xz'],routes[id]['xz'][1:]) for c,d in floor_edges)
        ck('public_route.routing_clearance',clearance>=.47998,{'independent_minimum_support_clearance_m':clearance,'movement_margin_m':.4,'routing_extra_margin_m':.08})
        boundary=plan['boundary'];scope=plan['scope'];ck('boundary.scene_only',boundary['contract_id']=='W03-play-boundary-v1' and boundary['finalized_for_scene'] is True and boundary['movement_edge_margin_m']==.4 and boundary['road_center_exclusion_m']==.5 and near(boundary['support_rings'],sp,1e-8))
        ck('scope_limits',scope['physical_terrain_verified'] is False and scope['real_world_access_verified'] is False and scope['source_display_permissions']=='unchanged/null' and scope['building_interiors']=='unresolved/excluded' and 'only for this game scene/source snapshot' in scope['global_playable_boundary'])
        ck('plan_sha256',record['plan_sha256']==canonical_digest(plan));ck('world_provenance',plan['provenance']['game/resources/world_geometry/world.json']==canonical_digest(world))
        w01_path=Path(__file__).resolve().parents[1]/'game/data/generated/daehanmun.json'
        w01=json.loads(w01_path.read_text())
        ck('w01_provenance',plan['provenance']['game/data/generated/daehanmun.json']==hashlib.sha256(w01_path.read_bytes()).hexdigest() and all(near(plan[k],w01[k],1e-8) for k in ('spawn','route_xz','direction_xz','normal_xz','passage_length_m')))
        inv=record['inventory'];sources=inv['source_bodies'];fragments=inv['fragments'];sby={b['id']:b for b in sources};fby={b['id']:b for b in fragments};old={f['id']:f for f in w01['fragments']};old['W02_support']=w02['support']
        selected={k for k,m in meshes.items() if m['role'] in ('Buildings','Barriers')}|{'temporary_support'}
        ck('inventory.source_coverage',len(sources)==len(sby)==685 and set(sby)==selected)
        ck('inventory.fragment_coverage',len(fragments)==len(fby)==7 and set(fby)==set(old)|{'W03_support'})
        ck('inventory.census',inv['created_body_count']==692 and inv['active_body_count']==687)
        disabled={b['id']:b for b in inv['disabled_bodies']}
        ck('inventory.actual_disabled_bodies',len(inv['disabled_bodies'])==len(disabled)==3 and set(disabled)==disabled_source and set(inv['disabled_ids'])==disabled_source and all(b['layer']==0 and b['mask']==0 and b['visible'] is False for b in disabled.values()))
        for id,body in sby.items():
            active=id not in disabled_source
            ck('inventory.'+id,body['layer']==(1 if active else 0) and body['mask']==(14 if active else 0) and body['identity'] is True and body['disabled'] is False and body['shape']=='ConcavePolygonShape3D' and body['backface'] is True and body['face_sha256']==float32_digest(meshes[id]['vertices']))
        for id,body in fby.items():
            expected=support if id=='W03_support' else old[id];active=id not in ('W01_support','W02_support');digest=float32_digest(expected['vertices'])
            ck('inventory.'+id,body['layer']==(1 if active else 0) and body['mask']==(14 if active else 0) and body['visible'] is active and body['identity'] is True and body['disabled'] is False and body['shape']=='ConcavePolygonShape3D' and body['backface'] is True and body['face_sha256']==digest and body['visual_face_sha256']==digest)
        actor=record['actor'];contract={'height':1.7,'radius':.3,'layer':2,'mask':13,'walk_mps':1.4,'run_mps':3.5,'gravity':9.8,'safe_margin':.001,'camera_mask':1,'camera_probe_radius':.2}
        ck('actual_player_contract',all(near(actor[k],v,1e-6) for k,v in contract.items()) and actor['player_camera_path_matches'] is True)
        engine=record['engine'];gpu=engine['display'].lower()!='headless';suite=record['suite'];full=suite=='full'
        ck('engine',suite in ('full','short') and engine['physics_hz']==60 and engine['render_fps'] in (30,60) and (not gpu or engine['renderer'].lower() not in ('','headless')))
        ck('suite_scope',not gpu or (engine['render_fps']==60 and full) or (engine['render_fps']==30 and not full))
        actual_boundary=record['boundary']
        ck('boundary.actual_resource',actual_boundary['contract_id']=='W03-play-boundary-v1' and actual_boundary['runtime_path']=='res://data/generated/public_walk.json' and near(actual_boundary['movement_edge_margin_m'],.4,1e-6) and near(actual_boundary['road_center_exclusion_m'],.5,1e-6) and actual_boundary['guide_exists'] is True and actual_boundary['guide_child_count']==0)
        ck('boundary.actual_player_script',actor['boundary_script']=='res://scripts/player/public_player.gd')
        for path in ('game/resources/play_boundary.tres','game/scripts/public_boundary.gd'):
            ck('boundary.source_hash.'+path,plan['provenance'][path]==hashlib.sha256((project_root/path).read_bytes()).hexdigest())
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
            if id not in ('W01_support','W02_support'):volumes.extend((p,mesh['bottom_y_m'],mesh['top_y_m']) for p in polygons(mesh['geometry']))
        volumes.extend((p,-.2,0.) for p in sp);bounds=volume_bounds(volumes)
        wanted={'idle','speed_walk','speed_run','gate_forward','gate_reverse','boundary_road','boundary_crossing','boundary_unfinished','boundary_plaza_hole'}
        tested_routes={id:routes[id] for id in public_ids} if full else {'sejong_marked':{'id':'sejong_marked','xz':sections[3]['runtime_xz'],'length_m':line_length(sections[3]['runtime_xz'])}}
        neck=plan['area_links'][1]['runtime_xz'][:6];tested_routes['neck']={'id':'neck','xz':neck,'length_m':line_length(neck)}
        wanted|={r['id']+'_'+d+'_'+str(i) for r in tested_routes.values() for d in ('forward','reverse') for i in range(len(r['xz'])-1)}
        raw=record['cases'];cases={c['name']:c for c in raw}
        ck('cases.coverage',len(raw)==len(cases)==len(wanted) and set(cases)==wanted)
        for name in sorted(wanted):
            c=cases[name];samples=c['samples'];stats=c['all_tick_stats'];ws=c['W03_stats'];duration=c['duration_s'];ticks=c['ticks']
            ck(name+'.clock',all(number(c[k]) for k in ('duration_s','wall_s','ticks','frames','recoveries','boundary_stops')) and number(duration) and duration>0 and ticks>0 and near(ticks/60,duration,.0001) and c['wall_s']>0 and c['recoveries']==0 and math.ceil(ticks/6)<=len(samples)<=ticks+1)
            if gpu and name in {'idle','speed_walk','speed_run','gate_forward','gate_reverse','boundary_road','boundary_crossing','boundary_unfinished','boundary_plaza_hole'}:
                ck(name+'.real_clock',abs(c['wall_s']-duration)<=.02*duration and abs(c['frames']/c['wall_s']-engine['render_fps'])<=.2*engine['render_fps'])
            ck(name+'.all_ticks',all(number(stats[k]) for k in ('ticks','max_camera_overlap_count','max_near_hit_count','max_follow_error_m','max_length_excess_m','max_tick_mismatch','floor_ticks','min_distance','max_distance','min_player_y','max_player_y','camera_max_step_m')) and all(number(ws[k]) for k in ('ticks','max_player_penetration_m','max_camera_penetration_m','floor_support_ticks','outside_movement_ticks','solid_contact_ticks')) and ws['ticks']==stats['ticks']==ticks and 0<=ws['max_player_penetration_m']<=.005 and 0<=ws['max_camera_penetration_m']<=.005 and ws['floor_support_ticks']==stats['floor_ticks']==ticks and ws['outside_movement_ticks']==0 and stats['max_camera_overlap_count']==stats['max_near_hit_count']==stats['max_tick_mismatch']==0 and 0<=stats['max_follow_error_m']<=.002 and stats['max_length_excess_m']<=.002 and 0<=stats['min_distance']<=stats['max_distance']<=6.002 and -.005<=stats['min_player_y']<=stats['max_player_y']<=.005)
            ck(name+'.sample_clock',bool(samples) and 0<samples[0]['t']<=.02 and near(samples[-1]['t'],duration,.0001) and all(0<b['t']-a['t']<=.11 for a,b in zip(samples,samples[1:])) and near(c['start'],samples[0]['player'],.07) and near(c['end'],samples[-1]['player'],.002))
            pipeline=c['pipelines'];ck(name+'.pipeline_metadata',all(number(pipeline['before'][k]) and number(pipeline['after'][k]) and 0<=pipeline['before'][k]<=pipeline['after'][k] for k in ('mesh','surface','draw')))
            ct=ws['crossing_ticks'];br=ws['boundary_reasons'];allowed_reasons={'private','road_outside_source_junction','unfinished_or_unsupported'}
            ck(name+'.junction_metadata',isinstance(ct,dict) and set(ct)<=set(cb) and all(number(v) and 0<=v<=ticks and int(v)==v for v in ct.values()) and sum(ct.values())<=ticks and isinstance(br,dict) and set(br)<=allowed_reasons and all(number(v) and 0<=v<=ticks and int(v)==v for v in br.values()) and sum(br.values())<=ticks and ws['first_outside_point']==[])
            bad=[];worstp=0.;worstc=0.
            for i,s in enumerate(samples):
                p=s['player'];rig=s['rig'];camera=rig['camera'];pivot=[p[0],p[1]+1.3,p[2]]
                pp=indexed_penetration([p[0],p[1]+.85,p[2]],volumes,bounds,.3,.55);pc=indexed_penetration(camera,volumes,bounds,.2);worstp=max(worstp,pp);worstc=max(worstc,pc)
                corners=s['near_corners'];basis=rig['basis'];local=[[sum(a*b for a,b in zip(sub(corner,camera),col)) for col in basis] for corner in corners]
                hw=max(abs(v[0]) for v in local);hh=max(abs(v[1]) for v in local);fhalf=rig['near']*math.tan(math.radians(rig['fov'])/2)
                plane=(len(corners)==4 and len(basis)==3 and all(vector(v) for v in corners+basis) and all(near(norm(col),1,.002) for col in basis) and all(abs(sum(a*b for a,b in zip(basis[j],basis[k])))<=.002 for j,k in ((0,1),(0,2),(1,2))) and near([pivot[j]+basis[2][j]*rig['distance'] for j in range(3)],camera,.002) and max(norm(sub(corner,camera)) for corner in corners)<=.200001 and len({(1 if v[0]>0 else -1,1 if v[1]>0 else -1) for v in local})==4 and all(near(v[2],-rig['near'],.0001) and near(abs(v[0]),hw,.0001) and near(abs(v[1]),hh,.0001) for v in local) and hh>0 and near(hw/hh,rig['aspect'],.002) and (near(hw,fhalf,.0001) or near(hh,fhalf,.0001)) and near(rig['near'],.05,1e-6) and near(rig['fov'],65,1e-6))
                cornerhit=any(b<v[1]<t and xmin<v[0]<xmax and zmin<v[2]<zmax and polygon_inside([v[0],v[2]],poly) for v in corners for (poly,b,t),(xmin,xmax,zmin,zmax) in zip(volumes,bounds))
                xz=[p[0],p[2]];claimed=s['crossing_id'];actual_ids=[id for id,crossing in cb.items() if any(polygon_inside(xz,q) for q in polygons(crossing['geometry']))]
                crossing_ok=claimed==(actual_ids[0] if actual_ids else '') or any(polygon_distance(xz,q)<=.00002 for crossing in cb.values() for q in polygons(crossing['geometry']))
                crossing_ok=crossing_ok and claimed in set(cb)|{''} and (not claimed or ct.get(claimed,0)>0) and s['boundary_reason'] in allowed_reasons|{''} and (not s['boundary_reason'] or br.get(s['boundary_reason'],0)>0)
                okay=(crossing_ok and plane and not cornerhit and abs(p[1])<=.005 and s['inside_movement'] is True and any(polygon_inside([p[0],p[2]],v) for v in movement) and pp<=.005 and pc<=.005 and near(s['player_penetration_m'],pp,.0001) and near(s['camera_penetration_m'],pc,.0001) and ws['max_player_penetration_m']+.0001>=pp and ws['max_camera_penetration_m']+.0001>=pc and s['floor'] is True and s['floor_id']=='W03_support' and near(s['floor_normal'],[0,1,0],.002) and s['camera_overlap']==[] and s['near_ray_hits']==[] and near(rig['pivot'],pivot) and rig['mask']==1 and near(rig['probe_radius'],.2,1e-6) and rig['follow_ticks']==rig['observed_ticks'] and 0<=rig['distance']<=rig['hit_length']+.002<=rig['requested_distance']+.004 and 2<=rig['requested_distance']<=6 and near(norm(sub(camera,pivot)),rig['distance']) and rig['input_enabled'] is True and rig['mouse_mode']==(2 if gpu else 0) and math.radians(-55)-1e-6<=rig['pitch']<=math.radians(15)+1e-6 and stats['min_distance']-.002<=rig['distance']<=stats['max_distance']+.002 and stats['min_player_y']-.002<=p[1]<=stats['max_player_y']+.002)
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
        groups=record['route_groups'];gby={(g['route'],g['direction']):g for g in groups};expected_groups={(r,d) for r in tested_routes for d in ('forward','reverse')}
        ck('route_groups.coverage',len(groups)==len(gby)==len(expected_groups) and set(gby)==expected_groups)
        for key,g in gby.items():
            rid,direction=key;points=tested_routes[rid]['xz'] if direction=='forward' else list(reversed(tested_routes[rid]['xz']));names=[rid+'_'+direction+'_'+str(i) for i in range(len(points)-1)];rows=[cases[n] for n in names]
            errors=[norm(sub([r['end'][0],r['end'][2]],p)) for r,p in zip(rows,points[1:])]
            ck('group.'+rid+'.'+direction+'.source_route',g['legs']==names and near(g['targets_xz'],points[1:],1e-8) and g['teleports_within_group']==0 and max(errors)<=.18 and near(g['maximum_target_error_m'],max(errors),.00003) and near([rows[0]['start'][0],rows[0]['start'][2]],points[0],.00005) and all(near(a['end'],b['start'],.002) for a,b in zip(rows,rows[1:])) and all(edge_distance([s['player'][0],s['player'][2]],points[i],points[i+1])<=.18 for i,row in enumerate(rows) for s in row['samples']))
            required_junctions={'city_plaza':{'sejong_marked','side_street'},'stonewall':{'west_junction'},'sejong_marked':{'sejong_marked'},'neck':set()}[rid]
            occupancy={id:sum(row['W03_stats']['crossing_ticks'].get(id,0) for row in rows) for id in required_junctions}
            ck('group.'+rid+'.'+direction+'.source_junction_occupancy',all(n>0 for n in occupancy.values()),occupancy)
            ck('group.'+rid+'.'+direction+'.clock_sums',near(g['duration_s'],sum(r['duration_s'] for r in rows),1e-7) and near(g['wall_s'],sum(r['wall_s'] for r in rows),1e-7) and g['frames']==sum(r['frames'] for r in rows) and abs(3.5*g['duration_s']-tested_routes[rid]['length_m'])<=len(rows)*3.5/60+.18)
            if gpu:ck('group.'+rid+'.'+direction+'.real_clock',abs(g['wall_s']-g['duration_s'])<=.02*g['duration_s'] and abs(g['frames']/g['wall_s']-engine['render_fps'])<=.2*engine['render_fps'])
        ck('boundary_cases.coverage',record['boundary_cases']==['boundary_road','boundary_crossing','boundary_unfinished','boundary_plaza_hole'])
        events=record['events'];eby={e['name']:e for e in events};ck('events.coverage',len(events)==len(eby)==5 and set(eby)=={'menu','fall','outside_test_area','manual_restart','private_return'});menu=eby['menu']
        ck('menu.actual_pause_and_capture',menu['paused'] is True and menu['actor_ticks']==menu['rig_ticks']==0 and menu['drift']<=.001 and menu['yaw_drift']<=1e-6 and menu['mouse_open']==0 and menu['capture_open'] is False and menu['mouse_closed']==(2 if gpu else 0) and menu['capture_closed'] is True and menu['first_motion_ignored'] is True and menu['held_drift']<=.002 and .65<=menu['release_move_m']<=.75)
        heading=math.atan2(-plan['direction_xz'][0],-plan['direction_xz'][1])
        for reason in ('fall','outside_test_area','manual_restart'):
            e=eby[reason];ck('recovery.'+reason,e['reason']==reason and e['recoveries']==1 and e['latched'] is True and e['spawn_valid'] is True and near([e['point'][0],e['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.002) and -.002<=e['point'][1]<=plan['spawn'][1]+.002 and e['floor'] is True and e['held_drift']<=.002 and .65<=e['release_move_m']<=.75 and abs(math.atan2(math.sin(e['yaw']-heading),math.cos(e['yaw']-heading)))<=.002 and near(e['pitch'],math.radians(-15),.002) and near(e['requested_distance'],4.5,.002))
        private_event=eby['private_return']
        ck('recovery.private_return',private_event['classified']=='private' and private_event['inside_before'] is False and private_event['spawn_rejected'] is True and private_event['recoveries']==1 and private_event['reason']=='outside_test_area' and private_event['floor'] is True and near([private_event['point'][0],private_event['point'][2]],[plan['spawn'][0],plan['spawn'][2]],.002) and abs(private_event['point'][1])<=.005)
        rays=record['rays'];rb={r['name']:r for r in rays};targets={'gate_center':'','lintel':'W01_gate_lintel','wall_left':'W01_palace_wall','wall_right':'W01_palace_wall','off_support':'','city_floor':'W03_support','plaza_floor':'W03_support','plaza_hole':'','private_floor':'','road_off_crossing':'','preserved_retaining_wall':'osm:way:381755262:barrier','library_closed':'osm:relation:10757525:building'}
        ck('rays.coverage',len(rays)==len(rb)==12 and set(rb)==set(targets))
        raymeshes=near_meshes+[old[k] for k in old if k not in ('W01_support','W02_support')]+[support]
        for name,target in targets.items():
            ray=rb[name];ck('ray.'+name,ray['hit'] is bool(target) and ray['id']==target and vector(ray['from']) and vector(ray['to']) and (vector(ray['position']) if target else ray['position']==[]))
            if name in ('city_floor','plaza_floor','plaza_hole','private_floor','road_off_crossing'):
                locations={'city_floor':[130,-140],'plaza_floor':[190,-100],'plaza_hole':[155.4,-56.73],'private_floor':[-131.61,-249.65],'road_off_crossing':[80,-180]}
                xz=locations[name];expected_from=[xz[0],1,xz[1]];expected_to=[xz[0],-1,xz[1]]
            elif name=='preserved_retaining_wall':expected_from=[-110,1,-60];expected_to=[-115,1,-60]
            elif name=='library_closed':expected_from=[150,1,-110];expected_to=[150,1,-140]
            else:
                u=plan['direction_xz'];n=plan['normal_xz'];outside=plan['route_xz'][1];inside=plan['route_xz'][2]
                if name in ('gate_center','lintel'):
                    start=[outside[k]-u[k]*2 for k in range(2)];end=[inside[k]+u[k]*2 for k in range(2)]
                elif name.startswith('wall_'):
                    sign=1 if name=='wall_left' else -1;start=[outside[k]-u[k]*2+sign*n[k]*6 for k in range(2)];end=[outside[k]+u[k]*2+sign*n[k]*6 for k in range(2)]
                else:start=end=[plan['route_xz'][0][k]+n[k]*6 for k in range(2)]
                y=3.5 if name=='lintel' else 1.;expected_from=[start[0],y,start[1]];expected_to=[end[0],-1. if name=='off_support' else y,end[1]]
            ck('ray.'+name+'.source_endpoints',near(ray['from'],expected_from,.00003) and near(ray['to'],expected_to,.00003))
            floor_ray=name in ('city_floor','plaza_floor','plaza_hole','private_floor','road_off_crossing');candidates=[support] if floor_ray else [old['W01_palace_wall']] if name.startswith('wall_') else raymeshes
            hits=[]
            for mesh in candidates:
                vv=mesh['vertices']
                for i in range(0,len(vv),9):
                    point=ray_triangle(ray['from'],ray['to'],[vv[i+j:i+j+3] for j in (0,3,6)])
                    if point is not None:hits.append((norm(sub(point,ray['from'])),mesh['id'],point))
            first=min(hits,key=lambda h:h[0]) if hits else None
            ck('ray.'+name+'.independent_source_hit',first is None if not target else first is not None and first[1]==target and near(first[2],ray['position'],.002))
        warm=record['warmup'];ck('warmup_scope',warm['poses']==16 and warm['wall_s']>0 and record['external_movement_events_ignored']>=0)
        captures=record['captures'];expected_captures={'outside_spawn','gate_inside','gate_outside','boundary_road','boundary_crossing','boundary_unfinished','boundary_plaza_hole','menu'}
        expected_captures|={r+'_'+d for r in tested_routes for d in ('forward','reverse')}
        if full:expected_captures|={'checkpoint_'+str(i) for i in (1,5,6,7)}
        ck('actual_gpu_captures',not captures if not gpu else len(captures)==len(expected_captures) and {c['name'] for c in captures}==expected_captures and all(c['width']>0 and c['height']>0 for c in captures))
    except (OSError,KeyError,TypeError,ValueError,IndexError,AttributeError,ZeroDivisionError,OverflowError) as error:
        ck('read_or_schema',False,str(error))
    return {'task':'W03','passed':bool(checks) and all(c['passed'] for c in checks),'checks':checks}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--plan',type=Path,default=Path('game/data/generated/public_walk.json'))
    parser.add_argument('--world',type=Path,default=Path('game/resources/world_geometry/world.json'))
    parser.add_argument('--features',type=Path,default=Path('data/processed/features.json'))
    args=parser.parse_args()
    try:
        record,plan,world,features=[json.loads(p.read_text()) for p in (args.input,args.plan,args.world,args.features)]
        result=audit(record,plan,world,features)
        matched=(record['plan_sha256']==hashlib.sha256(args.plan.read_bytes()).hexdigest() and plan['provenance']['game/resources/world_geometry/world.json']==hashlib.sha256(args.world.read_bytes()).hexdigest() and plan['provenance']['data/processed/features.json']==hashlib.sha256(args.features.read_bytes()).hexdigest())
        result['checks'].append({'name':'source_file_bytes','passed':matched});result['passed'] &= matched
    except (OSError,ValueError,KeyError,TypeError) as error:
        result={'task':'W03','passed':False,'checks':[{'name':'read_or_schema','passed':False,'details':str(error)}]}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

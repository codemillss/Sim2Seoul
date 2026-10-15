#!/usr/bin/env python3
"""Independent W04 continuous-journey audit. Standard library; never imports a generator.

Current engine observations are checked against unchanged source bodies/route copies.
Retained ~10Hz geometry is independent; every-tick extrema remain engine summaries.
Short diagnostic acceptance explicitly does not establish the full milestone.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from check_daehanmun_evidence import (number,vector,near,sub,norm,edges,feature_polygons,
    float32_digest,canonical_digest,polygon_distance,edge_distance,volume_bounds,ray_triangle)
from check_palace_evidence import polygons,volume_from_mesh,line_length
from check_public_evidence import polygon_inside,indexed_penetration

ROOT=Path(__file__).resolve().parents[1]
RECIPE=[('entrance_forward','entrance','forward',0,3),
 ('palace_loop_prefix','palace_loop','forward',0,5),
 ('court_forward','court_approach','forward',0,11),
 ('court_reverse','court_approach','reverse',11,0),
 ('palace_loop_suffix','palace_loop','forward',5,24),
 ('palace_loop_reverse','palace_loop','reverse',24,0),
 ('city_forward','city_plaza','forward',0,98),
 ('city_reverse','city_plaza','reverse',98,0),
 ('stonewall_forward','stonewall','forward',0,31),
 ('stonewall_reverse','stonewall','reverse',31,0),
 ('entrance_reverse','entrance','reverse',3,0)]

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def finite(value):
    if isinstance(value,float):return math.isfinite(value)
    if isinstance(value,dict):return all(finite(v) for v in value.values())
    if isinstance(value,list):return all(finite(v) for v in value)
    return True

def audit(record,plan,world,features):
    checks=[]
    def ck(name,passed,details=None):
        row={'name':name,'passed':bool(passed)}
        if details is not None:row['details']=details
        checks.append(row)
    try:
        w03path=ROOT/'game/data/generated/public_walk.json';w03=json.loads(w03path.read_text())
        w02=json.loads((ROOT/'game/data/generated/palace_walk.json').read_text())
        w01=json.loads((ROOT/'game/data/generated/daehanmun.json').read_text())
        ck('schema',record['schema_version']==plan['schema_version']==1 and record['task']==plan['task']=='W04' and world['task']=='E03' and features['task_id']=='G02')
        ck('finite_values',all(finite(v) for v in (record,plan,world,features)))
        ck('plan_sha256',record['plan_sha256']==canonical_digest(plan))
        ck('w03_sha256',record['w03_sha256']==plan['w03_sha256']==sha(w03path))
        ck('provenance.current_files',all(sha(ROOT/k)==v for k,v in plan['provenance'].items()) and plan['recipe_sha256']==sha(ROOT/'data/manual/walkable_milestone.json'))
        ck('world_features_bytes',w03['provenance']['game/resources/world_geometry/world.json']==canonical_digest(world) and w03['provenance']['data/processed/features.json']==sha(ROOT/'data/processed/features.json') and features==json.loads((ROOT/'data/processed/features.json').read_text()))
        # Reuse completed W03 static evidence only with exact current frozen bytes.
        frozen=json.loads((ROOT/'data/reports/public/contract_check.json').read_text())
        saved_root=Path(json.loads((ROOT/'data/reports/public/portability_check.json').read_text())['interpreter']).parents[2]
        mismatches=[]
        for field,prefix in (('sources','game'),('runtime_assets','game'),('input_sha256',''),('proof_sha256','')):
            for key,digest in frozen[field].items():
                relative=Path(key).relative_to(saved_root) if Path(key).is_absolute() else Path(prefix)/key
                path=ROOT/relative
                if not path.exists() or sha(path)!=digest:mismatches.append(key)
        ck('w03.frozen_evidence_reuse',frozen['passed'] is True and all(c['passed'] for c in frozen['checks']) and not mismatches,{'mismatches':mismatches,'scope':'Unchanged W03 static/source/cap provenance; current runtime observations independently checked below'})
        scope=plan['scope'];ck('scope_limits',plan['milestone_id']=='W0-engineering-walk-v1' and plan['meters_per_world_unit']==1 and plan['boundary_contract_id']=='W03-play-boundary-v1' and all(scope[k] is False for k in ('physical_terrain_verified','real_world_access_verified','human_operation_verified','m4_verified')) and scope['source_display_permissions']=='unchanged/null' and scope['building_interiors']=='unresolved/excluded')
        routes={r['id']:r for r in w03['routes']};stages=plan['stages']
        ck('itinerary.fixed_recipe',[(s['id'],s['route_id'],s['direction'],s['source_start_index'],s['source_end_index']) for s in stages]==RECIPE)
        expected_points=[];specs=[];events=[];source_cover={};expected_stages=[]
        for sid,rid,direction,start,end in RECIPE:
            indices=list(range(start,end+(1 if end>start else -1),1 if end>start else -1));points=[routes[rid]['xz'][i] for i in indices];offset=max(0,len(expected_points)-1)
            ck('itinerary.seam.'+sid,not expected_points or points[0]==expected_points[-1])
            expected_points.extend(points[1:] if expected_points else points)
            expected_stages.append((sid,rid,indices,points))
            stage=stages[len(expected_stages)-1]
            ck('itinerary.source.'+sid,stage['source_indices']==indices and stage['xz']==points and stage['start_point_index']==offset and stage['end_point_index']==offset+len(points)-1 and near(stage['length_m'],line_length(points),1e-8))
            for i,(a,b) in enumerate(zip(points,points[1:])):
                leg=min(indices[i:i+2]);source_cover[rid,direction,leg]=source_cover.get((rid,direction,leg),0)+1
                specs.append(dict(name=sid+'_'+str(i),stage_id=sid,route_id=rid,direction=direction,source_leg_index=leg,local_leg_index=i,from_point_index=offset+i,to_point_index=offset+i+1,from_xz=a,to_xz=b,length_m=norm(sub(b,a))))
            for i,point in enumerate(points):
                if i==0 and len(expected_stages)>1:continue
                for ci,cp in enumerate(w03['checkpoints']):
                    if point==cp['xz']:events.append(dict(event_index=len(events),checkpoint_index=ci,name=cp['name'],point_index=offset+i,stage_id=sid,local_point_index=i,source_point_index=indices[i],segment_name=sid+'_'+str(i-1) if i else None,xz=point))
        ck('itinerary.source_leg_coverage',all(source_cover.get((rid,direction,i))==1 for rid,r in routes.items() for direction in ('forward','reverse') for i in range(len(r['xz'])-1)) and len(source_cover)==334)
        ck('itinerary.points_segments',plan['points_xz']==expected_points and len(plan['segment_specs'])==len(specs)==334 and all(all(near(row[k],v,1e-8) if k=='length_m' else row[k]==v for k,v in spec.items()) for row,spec in zip(plan['segment_specs'],specs)) and near(plan['total_length_m'],sum(s['length_m'] for s in specs),1e-7))
        ck('itinerary.checkpoint_manifest',plan['checkpoint_events']==events and len(events)==21 and len(plan['checkpoints'])==8 and all(all(cp[k]==v for k,v in old.items()) for cp,old in zip(plan['checkpoints'],w03['checkpoints'])) and all(cp['event_indices']==[i for i,e in enumerate(events) if e['checkpoint_index']==ci] for ci,cp in enumerate(plan['checkpoints'])))
        ck('itinerary.counts',plan['counts']==dict(stages=11,points=335,segments=334,source_routes=5,checkpoints=8,checkpoint_events=21,teleport_links=0,new_coordinate_points=0))
        ck('itinerary.court_source_anchor',plan['court_anchor']==dict(route_id='palace_loop',runtime_index=5,checkpoint_index=2,source_node=921242850) and routes['palace_loop']['xz'][5]==routes['court_approach']['xz'][0]==w03['checkpoints'][2]['xz'] and w03['checkpoints'][2]['source_node']==921242850 and 921242850 in routes['palace_loop']['source_node_ids'])
        ck('itinerary.outside_return',plan['spawn']==w03['spawn'] and expected_points[0]==expected_points[-1]==w03['spawn'][::2])
        by={f['feature_id']:f for f in features['features']};meshes={m['id']:m for m in world['meshes']};project_root=ROOT
        disabled_source={'osm:way:377289797:building','osm:way:26658458:barrier','temporary_support'}
        support=w03['support'];sp=polygons(support['geometry']);movement=w03['movement_rings'];sx=[v[0] for poly in sp for v in poly[0]];sz=[v[1] for poly in sp for v in poly[0]];cb={c['id']:c for c in w03['crossings']}
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
        ck('engine',suite in ('full','short') and engine['physics_hz']==60 and engine['render_fps']==60 and (not gpu or engine['renderer'].lower() not in ('','headless')))
        actual_boundary=record['boundary']
        ck('boundary.actual_resource',actual_boundary['contract_id']=='W03-play-boundary-v1' and actual_boundary['runtime_path']=='res://data/generated/public_walk.json' and near(actual_boundary['movement_edge_margin_m'],.4,1e-6) and near(actual_boundary['road_center_exclusion_m'],.5,1e-6) and actual_boundary['guide_exists'] is True and actual_boundary['guide_child_count']==0)
        # Reconstruct the 5 cm guide strips from audited movement-ring edges,
        # independently of the renderer builder. Godot's clockwise front face
        # has the negative mathematical cross-product normal.
        guide=actual_boundary.get('guide_surface',{});gv=guide.get('vertices',[]);expected_guide=[];guide_edges=0
        for poly in movement:
            for ring in poly:
                for a,b in edges(ring):
                    dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz)
                    if length<.00001:continue
                    nx=-dz/length*.025;nz=dx/length*.025
                    am=[a[0]-nx,.08,a[1]-nz];ap=[a[0]+nx,.08,a[1]+nz]
                    bm=[b[0]-nx,.08,b[1]-nz];bp=[b[0]+nx,.08,b[1]+nz]
                    expected_guide.extend(x for v in (am,bm,bp,am,bp,ap) for x in v);guide_edges+=1
        finite_guide=isinstance(gv,list) and len(gv)==guide_edges*18 and all(number(v) for v in gv)
        front_y=[]
        if finite_guide:
            for i in range(0,len(gv),9):
                a,b,c=[gv[i+j:i+j+3] for j in (0,3,6)]
                front_y.append((b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0]))
        ck('boundary.actual_guide_surface',finite_guide and bool(front_y) and min(front_y)>0 and all(abs(y-.08)<=1e-6 for y in gv[1::3]) and near(gv,expected_guide,.0004) and guide.get('identity') is True and guide.get('cull_mode')==0 and guide.get('shading_mode')==0 and guide.get('cast_shadow')==0,{'source_ring_edges':guide_edges,'actual_triangles':len(gv)//9 if isinstance(gv,list) else 0,'minimum_front_y_twice_area_m2':min(front_y) if front_y else None,'guide_width_m':.05,'vertex_comparison_tolerance_m':.0004})
        ck('boundary.actual_player_script',actor['boundary_script']=='res://scripts/player/public_player.gd')
        for path in ('game/resources/play_boundary.tres','game/scripts/public_boundary.gd'):
            ck('boundary.source_hash.'+path,w03['provenance'][path]==hashlib.sha256((project_root/path).read_bytes()).hexdigest())
        spawn=record['spawn'];ck('spawn_valid',spawn['valid'] is True and spawn['volume_guard_clear'] is True and near(spawn['point'][::2],w03['spawn'][::2],.00003) and abs(spawn['point'][1])<=.005)
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
        active_stages=expected_stages if full else expected_stages[:2];active_ids=[s[0] for s in active_stages];active_specs=[s for s in specs if s['stage_id'] in active_ids]
        wanted=[s['name'] for s in active_specs];raw=record['cases'];cases={c['name']:c for c in raw};groups=record['journey']['groups'];gby={g['id']:g for g in groups}
        ck('stage_coverage',len(groups)==len(gby)==len(active_stages) and list(gby)==active_ids and len(raw)==len(cases)==len(wanted) and [c['name'] for c in raw]==wanted)
        ck('milestone_scope',full or suite=='short',{'full_milestone_observed':full,'short_is_diagnostic_only':not full})
        journey=record['journey'];jstats=journey['stats'];jticks=journey['ticks'];jfirst=journey['first_physics_tick'];jlast=journey['last_physics_tick']
        ck('journey.clock',jticks>0 and jlast-jfirst+1==jticks and near(journey['duration_s'],jticks/60,1e-6) and journey['wall_s']>0 and journey['frames']>0)
        ck('journey.step_bound',0<=jstats['max_player_step_m']<=3.5/60+.005 and jstats['max_tick_gap']==1 and jstats['recoveries']==jstats['pose_calls']==0,jstats)
        ck('journey.movement_dwell_accounting',journey['movement_ticks']==sum(c['ticks'] for c in raw) and journey['checkpoint_dwell_ticks']==jticks-journey['movement_ticks']>=0)
        ck('journey.endpoints',near(journey['start'][::2],w03['spawn'][::2],.00003) and near(journey['end'],raw[-1]['end'],.002) and near(journey['end'][::2],active_stages[-1][3][-1],.18))
        if gpu:ck('journey.real_clock',abs(journey['wall_s']-journey['duration_s'])<=.02*journey['duration_s'] and abs(journey['frames']/journey['wall_s']-60)<=12)
        for spec in active_specs:
            name=spec['name'];c=cases[name];samples=c['samples'];stats=c['all_tick_stats'];ws=c['W03_stats'];duration=c['duration_s'];ticks=c['ticks']
            ck(name+'.source_leg',c['stage_id']==spec['stage_id'] and near(c['end'][::2],spec['to_xz'],.18) and all(edge_distance(s['player'][::2],spec['from_xz'],spec['to_xz'])<=.18 for s in samples))
            ck(name+'.clock',ticks>0 and c['last_physics_tick']-c['first_physics_tick']+1==ticks and jfirst<=c['first_physics_tick']<=c['last_physics_tick']<=jlast and near(ticks/60,duration,.0001) and c['wall_s']>0 and c['recoveries']==0 and math.ceil(ticks/6)<=len(samples)<=ticks+1)
            ck(name+'.sample_clock',bool(samples) and 0<samples[0]['t']<=.02 and near(samples[-1]['t'],duration,.0001) and all(0<b['t']-a['t']<=.11 for a,b in zip(samples,samples[1:])) and near(c['start'],samples[0]['player'],.07) and near(c['end'],samples[-1]['player'],.002))
            ct=ws['crossing_ticks'];br=ws['boundary_reasons'];allowed_reasons={'private','road_outside_source_junction','unfinished_or_unsupported'}
            ck(name+'.junction_metadata',set(ct)<=set(cb) and all(type(v) is int and 0<=v<=ticks for v in ct.values()) and sum(ct.values())<=ticks and set(br)<=allowed_reasons and all(type(v) is int and 0<=v<=ticks for v in br.values()) and sum(br.values())<=ticks and ws['first_outside_point']==[])
            ck(name+'.physics_clock',all(c['first_physics_tick']<=s['global_physics_tick']<=c['last_physics_tick'] and near(s['t'],(s['global_physics_tick']-c['first_physics_tick']+1)/60,.0001) for s in samples))
            ck(name+'.run_speed',abs(duration-norm(sub(c['start'][::2],spec['to_xz']))/3.5)<=1/60+.00001)
            ck(name+'.all_ticks',all(number(stats[k]) for k in ('ticks','max_camera_overlap_count','max_near_hit_count','max_follow_error_m','max_length_excess_m','max_tick_mismatch','floor_ticks','min_distance','max_distance','min_player_y','max_player_y','camera_max_step_m')) and all(number(ws[k]) for k in ('ticks','max_player_penetration_m','max_camera_penetration_m','floor_support_ticks','outside_movement_ticks','solid_contact_ticks')) and ws['ticks']==stats['ticks']==ticks and 0<=ws['max_player_penetration_m']<=.005 and 0<=ws['max_camera_penetration_m']<=.005 and ws['floor_support_ticks']==stats['floor_ticks']==ticks and ws['outside_movement_ticks']==0 and stats['max_camera_overlap_count']==stats['max_near_hit_count']==stats['max_tick_mismatch']==0 and 0<=stats['max_follow_error_m']<=.002 and stats['max_length_excess_m']<=.002 and 0<=stats['min_distance']<=stats['max_distance']<=6.002 and -.005<=stats['min_player_y']<=stats['max_player_y']<=.005)
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
        ck('journey.case_continuity',near(raw[0]['start'],journey['start'],.002) and all(near(a['end'],b['start'],.002) and a['last_physics_tick']<b['first_physics_tick'] for a,b in zip(raw,raw[1:])))
        for sid,rid,indices,points in active_stages:
            g=gby[sid];rows=[cases[s['name']] for s in active_specs if s['stage_id']==sid];errors=[norm(sub(r['end'][::2],target)) for r,target in zip(rows,points[1:])]
            ck('stage.'+sid+'.source',g['route_id']==rid and g['source_indices']==indices and g['legs']==[r['name'] for r in rows] and near(g['targets_xz'],points[1:],1e-8) and near(g['start'],rows[0]['start'],.002) and near(g['end'],rows[-1]['end'],.002) and max(errors)<=.18 and near(g['maximum_target_error_m'],max(errors),.00003))
            ck('stage.'+sid+'.clock',g['ticks']==g['last_physics_tick']-g['first_physics_tick']+1 and g['first_physics_tick']<=rows[0]['first_physics_tick']<=rows[-1]['last_physics_tick']<=g['last_physics_tick'] and g['ticks']>=sum(r['ticks'] for r in rows) and near(g['duration_s'],g['ticks']/60,1e-6) and g['wall_s']>0)
            if gpu and g['duration_s']>=1:ck('stage.'+sid+'.real_clock',abs(g['wall_s']-g['duration_s'])<=.02*g['duration_s'] and abs(g['frames']/g['wall_s']-60)<=12)
            required={'city_plaza':{'sejong_marked','side_street'},'stonewall':{'west_junction'}}.get(rid,set());occupancy={key:sum(r['W03_stats']['crossing_ticks'].get(key,0) for r in rows) for key in required};ck('stage.'+sid+'.source_junctions',all(n>0 for n in occupancy.values()),occupancy)
        ck('journey.stage_continuity',all(a['last_physics_tick']+1==b['first_physics_tick'] and near(a['end'],b['start'],.002) for a,b in zip(groups,groups[1:])) and groups[-1]['last_physics_tick']==jlast and sum(g['ticks'] for g in groups)<=jticks and sum(g['frames'] for g in groups)<=journey['frames'])
        if full:
            for sid in ('entrance_forward','entrance_reverse'):
                rows=[c for c in raw if c['stage_id']==sid];u=w03['direction_xz'];mid=[sum(v)/2 for v in zip(w03['route_xz'][1],w03['route_xz'][2])];sign=1 if sid.endswith('forward') else -1
                projection=lambda v:sum((v[k]-mid[k])*u[k] for k in range(2))
                ck(sid+'.actual_gate_passage',sign*projection(rows[0]['start'][::2])<-w03['passage_length_m']/2 and sign*projection(rows[-1]['end'][::2])>w03['passage_length_m']/2)
        observed=journey['checkpoint_events'];expected_events=[e for e in events if e['stage_id'] in active_ids]
        ck('checkpoint_coverage',len(observed)==len(expected_events) and all(all(near(o[k],v,1e-8) if k=='xz' else o[k]==v for k,v in e.items()) and jfirst-1<=o['global_physics_tick']<=jlast and near(o['journey_t'],(o['global_physics_tick']-jfirst+1)/60,.0001) and norm(sub(o['point'][::2],e['xz']))<=.18 and near(o['distance_m'],norm(sub(o['point'][::2],e['xz'])),.00003) for o,e in zip(observed,expected_events)) and all(a['global_physics_tick']<b['global_physics_tick'] for a,b in zip(observed,observed[1:])))
        # Whole observer includes PNG-wait/neutral ticks, closing gaps between legs.
        name='journey';samples=journey['samples'];stats=jstats;ws=jstats;ticks=jticks;duration=journey['duration_s'];ct=ws['crossing_ticks'];br={};allowed_reasons={'private','road_outside_source_junction','unfinished_or_unsupported'}
        ck(name+'.all_ticks',all(number(stats[k]) for k in ('ticks','max_camera_overlap_count','max_near_hit_count','max_follow_error_m','max_length_excess_m','max_tick_mismatch','min_distance','max_distance','min_player_y','max_player_y')) and all(number(ws[k]) for k in ('ticks','max_player_penetration_m','max_camera_penetration_m','floor_support_ticks','outside_movement_ticks')) and ws['ticks']==stats['ticks']==ticks and 0<=ws['max_player_penetration_m']<=.005 and 0<=ws['max_camera_penetration_m']<=.005 and ws['floor_support_ticks']==ticks and ws['outside_movement_ticks']==0 and stats['max_camera_overlap_count']==stats['max_near_hit_count']==stats['max_tick_mismatch']==0 and 0<=stats['max_follow_error_m']<=.002 and stats['max_length_excess_m']<=.002 and 0<=stats['min_distance']<=stats['max_distance']<=6.002 and -.005<=stats['min_player_y']<=stats['max_player_y']<=.005)
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
        ck('journey.retained_clock',bool(samples) and 0<=samples[0]['t']<=.02 and near(samples[-1]['t'],duration,.0001) and all(0<b['t']-a['t']<=.11 for a,b in zip(samples,samples[1:])) and all(jfirst<=s['global_physics_tick']<=jlast and near(s['t'],(s['global_physics_tick']-jfirst+1)/60,.0001) for s in samples) and near(samples[-1]['player'],journey['end'],.002))
        retained={s['global_physics_tick']:s for s in samples}
        ck('journey.endpoint_trace_alignment',all(c['last_physics_tick'] in retained and near(c['end'],retained[c['last_physics_tick']]['player'],.00003) for c in raw) and len(retained)==len(samples))
        ck('journey.independent_step_bound',all(norm(sub(b['player'],a['player']))<=3.5*(b['global_physics_tick']-a['global_physics_tick'])/60+.005 for a,b in zip(samples,samples[1:])))
        events=record['events'];eby={e['name']:e for e in events};ck('events.coverage',len(events)==len(eby)==5 and set(eby)=={'menu','fall','outside_test_area','manual_restart','private_return'});menu=eby['menu']
        ck('menu.actual_pause_and_capture',menu['paused'] is True and menu['actor_ticks']==menu['rig_ticks']==0 and menu['drift']<=.001 and menu['yaw_drift']<=1e-6 and menu['mouse_open']==0 and menu['capture_open'] is False and menu['mouse_closed']==(2 if gpu else 0) and menu['capture_closed'] is True and menu['first_motion_ignored'] is True and menu['held_drift']<=.002 and .65<=menu['release_move_m']<=.75)
        heading=math.atan2(-w03['direction_xz'][0],-w03['direction_xz'][1])
        for reason in ('fall','outside_test_area','manual_restart'):
            e=eby[reason];ck('recovery.'+reason,e['reason']==reason and e['recoveries']==1 and e['latched'] is True and e['spawn_valid'] is True and near([e['point'][0],e['point'][2]],[w03['spawn'][0],w03['spawn'][2]],.002) and -.002<=e['point'][1]<=w03['spawn'][1]+.002 and e['floor'] is True and e['held_drift']<=.002 and .65<=e['release_move_m']<=.75 and abs(math.atan2(math.sin(e['yaw']-heading),math.cos(e['yaw']-heading)))<=.002 and near(e['pitch'],math.radians(-15),.002) and near(e['requested_distance'],4.5,.002))
        private_event=eby['private_return']
        ck('recovery.private_return',private_event['classified']=='private' and private_event['inside_before'] is False and private_event['spawn_rejected'] is True and private_event['recoveries']==1 and private_event['reason']=='outside_test_area' and private_event['floor'] is True and near([private_event['point'][0],private_event['point'][2]],[w03['spawn'][0],w03['spawn'][2]],.002) and abs(private_event['point'][1])<=.005)
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
                u=w03['direction_xz'];n=w03['normal_xz'];outside=w03['route_xz'][1];inside=w03['route_xz'][2]
                if name in ('gate_center','lintel'):
                    start=[outside[k]-u[k]*2 for k in range(2)];end=[inside[k]+u[k]*2 for k in range(2)]
                elif name.startswith('wall_'):
                    sign=1 if name=='wall_left' else -1;start=[outside[k]-u[k]*2+sign*n[k]*6 for k in range(2)];end=[outside[k]+u[k]*2+sign*n[k]*6 for k in range(2)]
                else:start=end=[w03['route_xz'][0][k]+n[k]*6 for k in range(2)]
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
        ck('events.after_journey',record['events_end_physics_tick']>record['events_start_physics_tick']>=jlast)
        warm=record['warmup'];ck('warmup_scope',warm['poses']==16 and warm['wall_s']>0 and record['external_movement_events_ignored']>=0)
        captures=record['captures'];expected_captures={'checkpoint_'+str(e['checkpoint_index']) for e in expected_events}|{'journey_end','menu'}
        ck('actual_gpu_captures',not captures if not gpu else len(captures)==len(expected_captures) and {c['name'] for c in captures}==expected_captures and all(c['width']>0 and c['height']>0 for c in captures))
    except (OSError,KeyError,TypeError,ValueError,IndexError,AttributeError,ZeroDivisionError,OverflowError) as error:ck('read_or_schema',False,str(error))
    return {'task':'W04','passed':bool(checks) and all(c['passed'] for c in checks),'full_milestone_observed':record.get('suite')=='full','checks':checks}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--plan',type=Path,default=Path('game/data/generated/walkable_itinerary.json'))
    parser.add_argument('--world',type=Path,default=Path('game/resources/world_geometry/world.json'))
    parser.add_argument('--features',type=Path,default=Path('data/processed/features.json'))
    args=parser.parse_args()
    try:
        record,plan,world,features=[json.loads(p.read_text()) for p in (args.input,args.plan,args.world,args.features)];result=audit(record,plan,world,features)
        result['checks'].append({'name':'source_file_bytes','passed':record['plan_sha256']==sha(args.plan) and record['w03_sha256']==sha(ROOT/'game/data/generated/public_walk.json')});result['passed']=all(c['passed'] for c in result['checks'])
    except (OSError,ValueError,KeyError,TypeError) as error:result={'task':'W04','passed':False,'checks':[{'name':'read_or_schema','passed':False,'details':str(error)}]}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');return 0 if result['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

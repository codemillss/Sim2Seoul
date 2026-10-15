#!/usr/bin/env python3
"""N01 source-bound route plans; no game actors, traffic signals or new floors."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from shapely.geometry import LineString, Point, box, mapping, shape
from shapely.ops import substring, unary_union

ROOT=Path(__file__).resolve().parents[1]
MANUAL='data/manual/urban_routes.json'
OUTPUTS=['data/processed/npc_routes.json','data/processed/vehicle_routes.json']
INPUTS=[MANUAL,'config/region.json','config/movement_rules.json','config/data_usage.json',
        'data/processed/features.json','data/processed/walkable_areas.json','data/processed/driveable_areas.json',
        'data/processed/boundary_candidate.json','game/data/generated/public_walk.json',
        'game/resources/world_geometry/world.json','game/data/generated/daehanmun.json',
        'game/resources/collision/rules.json','data/raw/deoksugung_cityhall-v2.osm.pbf',
        'tools/prepare_routes.py']

def read(path):return json.loads(Path(path).read_text())
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def encoded(value):return (json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode()
def finite(value):
    if isinstance(value,float):return math.isfinite(value)
    if isinstance(value,dict):return all(finite(v) for v in value.values())
    if isinstance(value,list):return all(finite(v) for v in value)
    return True

def parts(g):
    if g.is_empty:return []
    if g.geom_type in ('LineString','Point'):return [g]
    return [p for child in g.geoms for p in parts(child)]

def solid_geometry(features,world,w01,height):
    """Ground-intersecting active source bodies, not render-only landmarks."""
    by={f['feature_id']:f for f in features['features']};solids=[]
    for mesh in world['meshes']:
        if mesh['role'] not in ('Buildings','Barriers') or mesh['id'] in w01['disabled_source_ids']:continue
        if mesh['bottom_y_m']>=height or mesh['top_y_m']<=0:continue
        g=shape(by[mesh['metadata']['feature_id']]['geometry'])
        if g.geom_type in ('LineString','MultiLineString'):
            g=g.buffer(world['display']['barrier_thickness_m']/2,cap_style='flat',join_style='mitre')
        solids.append(g)
    for f in w01['fragments']:
        if f['bottom_y_m']<height and f['top_y_m']>0:solids.append(shape(f['geometry']))
    return unary_union(solids)

def build(root):
    root=Path(root);d=read(root/MANUAL);public=read(root/'game/data/generated/public_walk.json')
    features=read(root/'data/processed/features.json');drive=read(root/'data/processed/driveable_areas.json')
    walk=read(root/'data/processed/walkable_areas.json');boundary=read(root/'data/processed/boundary_candidate.json')
    world=read(root/'game/resources/world_geometry/world.json');w01=read(root/'game/data/generated/daehanmun.json')
    if d['schema_version']!=1 or d['task']!='N01' or not finite(d):raise ValueError('Wrong or nonfinite N01 schema')
    for actor in ('pedestrian','vehicle'):
        if not all(isinstance(v,(int,float)) and not isinstance(v,bool) and v>0 for v in d[actor].values()):raise ValueError('Actor dimensions/speeds must be positive finite metres')
    for mode in ('npc_routes','vehicle_routes'):
        ids=[r['id'] for r in d[mode]]
        if not ids or len(ids)!=len(set(ids)):raise ValueError('Empty/duplicate route IDs')
    if d['initial_profile']['per_route']!=1 or d['initial_profile']['pedestrians']!=len(d['npc_routes']) or d['initial_profile']['vehicles']!=len(d['vehicle_routes']):raise ValueError('Initial profile must assign one actor per route')
    if any(d['policy'][k]<=0 for k in ('brake_mps2','reaction_s','stop_margin_m','crossing_clearance_m','clear_hold_s','max_observation_age_s')):raise ValueError('Policy margins must be positive')
    if any(sha(root/p)!=h for p,h in public['provenance'].items()):raise ValueError('Stale W03 source/proof binding')
    if drive['provenance']!=walk['provenance'] or drive['provenance']['features_sha256']!=sha(root/'data/processed/features.json'):
        raise ValueError('Stale G04/features binding')
    if drive['provenance']['rules_sha256']!=sha(root/'config/movement_rules.json') or features['provenance']['source_sha256']!=sha(root/features['provenance']['source_file']):
        raise ValueError('Stale G04 rules/source')
    if features['coordinate_system']!=drive['coordinate_system']:raise ValueError('Coordinate contract mismatch')
    provenance={p:sha(root/p) for p in INPUTS}
    scope={'game_plan_only':True,'runtime_controller_implemented':False,'physical_lane_terrain_access_verified':False,
           'original_permissions_unchanged':True,'new_physical_support':False,'runtime_support_verified':False,'source':'OSM/G04 plus existing W03 game paths'}
    common={'schema_version':1,'task':'N01','contract_id':d['contract_id'],'coordinate_system':features['coordinate_system'],
            'provenance':provenance,'scope':scope,'policy':d['policy'],'initial_profile':d['initial_profile'],'assumptions':d['assumptions']}
    floor=shape(public['support']['geometry']);movement=unary_union([shape({'type':'Polygon','coordinates':p}) for p in public['movement_rings']])
    private=unary_union([shape({'type':'Polygon','coordinates':p}) for p in public['private_rings']])
    envelope=box(*boundary['background_extent_xz_m']);parents={r['id']:r for r in public['routes']}
    ped=d['pedestrian'];vehicle=d['vehicle'];policy=d['policy']
    if vehicle['swept_radius_m']<math.hypot(vehicle['length_m']/2,vehicle['width_m']/2)+.1:
        raise ValueError('Vehicle swept circle does not cover full body and clearance')
    if policy['unknown_occupancy']!='stop' or policy['timeout_forced_entry'] or policy['zone_vehicle_capacity']!=1:
        raise ValueError('Unsupported crossing guard')
    if policy['priority']!=['player_and_pedestrian','vehicle_already_inside','fifo_waiting_vehicle'] or not 0<policy['max_observation_age_s']<=.1 or policy['clear_hold_s']<1:
        raise ValueError('Unsafe human priority or observation guard')
    if policy['vehicle_recycle']!={'both_portals_outside_actual_camera_frustum':True,'minimum_human_distance_m':30.0,'dynamic_entry_envelope_empty':True,'hold_until_eligible':True,'spatial_connection_between_portals':False}:
        raise ValueError('Unsupported vehicle recycle guard')
    npc=[];cars=[]
    for spec in d['npc_routes']:
        if spec['repeat']!='ping_pong':raise ValueError('Unsupported pedestrian repeat')
        parent=parents[spec['parent_route']];a,b=spec['first_vertex'],spec['last_vertex']
        if not 0<=a<b<len(parent['xz']):raise ValueError('Invalid source vertex range')
        coords=parent['xz'][a:b+1];line=LineString(coords);swept=line.buffer(ped['radius_m']+ped['clearance_m'])
        if not movement.buffer(1e-8).covers(line) or not floor.buffer(1e-8).covers(swept):raise ValueError('NPC outside existing walking domain')
        if swept.intersects(solid_geometry(features,world,w01,ped['height_m'])) or swept.intersects(private):raise ValueError('NPC intersects a solid/private enclosure')
        npc.append({'id':spec['id'],'name':spec['name'],'xz':coords,'ground_y_m':0.,'length_m':line.length,
                    'source_binding':{k:spec[k] for k in ('parent_route','first_vertex','last_vertex')},
                    'repeat':spec['repeat'],'cycle_length_m':2*line.length,'turn_policy':'stop then rotate in free capsule; never jump endpoints',
                    'swept_geometry':mapping(swept),'speed_mps':ped['speed_mps']})
    rows={r['feature_id']:r for r in drive['records']};by={f['feature_id']:f for f in features['features']}
    crossings=[{**c,'human_occupancy_geometry':mapping(shape(c['geometry']).buffer(policy['crossing_clearance_m']))} for c in public['crossings']]
    allowed=unary_union([shape(c['geometry']) for c in crossings])
    stop_distance=vehicle['speed_mps']*policy['reaction_s']+vehicle['speed_mps']**2/(2*policy['brake_mps2'])+policy['stop_margin_m']
    for spec in d['vehicle_routes']:
        if spec['repeat']!='guarded_oneway_stream':raise ValueError('Unsupported vehicle repeat')
        row=rows[spec['feature_id']];tags=row['source_tags'];source=LineString(row['source_geometry']['coordinates'])
        if not row['structural_candidate'] or row['direction']!='source_forward' or tags.get('oneway')!='yes' or not tags.get('lanes','').isdigit():
            raise ValueError('Vehicle direction/lanes not supported by source')
        if row['source_geometry']!=by[row['feature_id']]['geometry'] or tags!=by[row['feature_id']]['source_tags']:raise ValueError('G04/source geometry mismatch')
        if row['placement_review_reasons'] or row['node_constraints']:raise ValueError('Unresolved road placement/node constraint')
        lanes=int(tags['lanes']);index=spec['lane_index_zero_based_from_left']
        if type(index) is not int:raise ValueError('Lane index must be an integer')
        expected=(index+.5-lanes/2)*spec['assumed_lane_width_m']
        if not 0<=index<lanes or abs(expected-spec['right_offset_m'])>1e-8:raise ValueError('Inconsistent lane assumption')
        if not 0<spec['from_s_m']<spec['to_s_m']<source.length:raise ValueError('Invalid source distance range')
        # XZ has east/south axes. Physical right=(-dz,+dx), hence positive Shapely offset.
        section=substring(source,spec['from_s_m'],spec['to_s_m'])
        line=section.offset_curve(spec['right_offset_m'],join_style='mitre')
        if line.geom_type!='LineString' or not line.is_simple:raise ValueError('Ambiguous offset geometry')
        swept=line.buffer(vehicle['swept_radius_m']);road=shape(row['candidate_surface_geometry']).intersection(envelope)
        if not road.buffer(1e-8).covers(swept) or not envelope.buffer(1e-8).covers(swept):raise ValueError('Vehicle outside reviewed road domain')
        if swept.intersects(solid_geometry(features,world,w01,vehicle['height_m'])) or swept.intersects(private):raise ValueError('Vehicle intersects active solid/private enclosure')
        if swept.intersection(movement).difference(allowed).area>1e-8:raise ValueError('Vehicle enters walking domain outside crossing')
        conflicts=[]
        for c in crossings:
            contact=line.intersection(shape(c['human_occupancy_geometry']).buffer(vehicle['swept_radius_m']))
            if contact.is_empty:continue
            spans=[]
            for part in parts(contact):
                coords=list(part.coords);spans.extend(line.project(Point(p)) for p in (coords[0],coords[-1]))
            enter,exit=min(spans),max(spans);stop=enter-stop_distance
            if stop<0 or exit>=line.length-vehicle['swept_radius_m']:raise ValueError('Crossing lacks approach/exit room')
            conflicts.append({'crossing_id':c['id'],'enter_s_m':enter,'exit_s_m':exit,'stop_s_m':stop,
                              'stop_xz':list(line.interpolate(stop).coords)[0],'stopping_distance_m':stop_distance})
        binding={k:spec[k] for k in ('feature_id','from_s_m','to_s_m','assumed_lane_width_m','lane_index_zero_based_from_left','right_offset_m')}
        binding.update(source_direction=row['direction'],oneway=tags['oneway'],lanes=lanes,source_node_ids=row['source_topology']['node_ids'],source_refs=row['source_refs'])
        cars.append({'id':spec['id'],'name':spec['name'],'xz':list(line.coords),'ground_y_m':0.,'length_m':line.length,
                     'source_binding':binding,'repeat':spec['repeat'],'speed_mps':vehicle['speed_mps'],
                     'road_domain':mapping(road),'swept_geometry':mapping(swept),'conflicts':conflicts,
                     'stopping_distance_m':stop_distance,'end_stop_s_m':line.length-stop_distance,
                     'repeat_spatial_edge':None})
    for a in cars:
        if any(shape(a['swept_geometry']).intersects(shape(b['swept_geometry'])) for b in npc):raise ValueError('NPC/vehicle route envelopes overlap')
    if len(cars)>1 and shape(cars[0]['swept_geometry']).intersects(shape(cars[1]['swept_geometry'])):raise ValueError('Opposing vehicle envelopes overlap')
    return [{**common,'mode':'pedestrian','actor':ped,'routes':npc},
            {**common,'mode':'vehicle','actor':vehicle,'routes':cars,'crossings':crossings,'crossing_rule':'human_priority_single_vehicle_FIFO'}]

def prepare(root=ROOT,check_only=False):
    root=Path(root);results=build(root)
    for name,result in zip(OUTPUTS,results):
        path=root/name;payload=encoded(result)
        if check_only:
            if not path.exists() or path.read_bytes()!=payload:raise ValueError('Stale N01 output: '+name)
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload)
    return results

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args()
    docs=prepare(a.root,a.check);print('N01', 'checked' if a.check else 'prepared',[(r['mode'],len(r['routes'])) for r in docs])

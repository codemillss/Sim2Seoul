#!/usr/bin/env python3
"""W03 connected palace/public support, source junctions and explicit local repair."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from shapely.geometry import LineString, Point, box, mapping, shape
from shapely.ops import nearest_points, unary_union
from prepare_world import encode, mesh_polygon, polygons
from prepare_daehanmun import rings
from prepare_palace_walk import shortest_inside, nearest_inside
from check_palace_bundle import check as check_w02
ROOT = Path(__file__).resolve().parents[1]
INPUT = 'data/manual/public_walk.json'
OUT = 'game/data/generated/public_walk.json'
DECISION = 'game/data/generated/public_decision.json'
MANIFEST = 'game/data/generated/public_manifest.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def section(feature, a, b):
    nodes = feature['source_topology']['node_ids']; aa, bb = nodes.index(a), nodes.index(b)
    ns = nodes[min(aa,bb):max(aa,bb)+1]; ps = feature['geometry']['coordinates'][min(aa,bb):max(aa,bb)+1]
    if aa > bb:ns, ps = list(reversed(ns)), list(reversed(ps))
    return {'feature_id':feature['feature_id'], 'node_ids':ns, 'source_xz':ps, 'source_length_m':LineString(ps).length}


def prepare(root=ROOT, check_only=False):
    root=Path(root);check_w02(root)
    d=json.loads((root/INPUT).read_text());assert d['task']=='W03' and d['schema_version']==1
    assert d['scope']['physical_terrain_verified'] is False and d['scope']['real_world_access_verified'] is False
    features=json.loads((root/'data/processed/features.json').read_text());by={f['feature_id']:f for f in features['features']}
    world=json.loads((root/'game/resources/world_geometry/world.json').read_text())
    w1=json.loads((root/'game/data/generated/daehanmun.json').read_text());w2=json.loads((root/'game/data/generated/palace_walk.json').read_text())
    candidate=json.loads((root/'data/processed/boundary_candidate.json').read_text());envelope=shape(candidate['candidate_geometry'])
    areas={id:shape(by[id]['geometry']) for id in d['public_areas']}
    assert all(by[id]['source_tags']['highway']=='pedestrian' for id in areas)
    sections=[section(by[id],a,b) for id,a,b in d['line_sections']]
    for s in sections:
        tags=by[s['feature_id']]['source_tags'];assert tags['highway']=='footway' or tags.get('foot')=='designated'
        assert not tags.get('tunnel')=='yes' and tags.get('layer','0') in ['0',0]
    corridors=[LineString(s['source_xz']).buffer(d['path_width_m']/2,cap_style='square',join_style='mitre') for s in sections]
    original_public=unary_union([*areas.values(),*corridors])
    repair=d['local_support_repair'];source_area=areas[repair['source']]
    extra=source_area.buffer(repair['outward_m'],join_style='round').difference(source_area).intersection(box(*repair['bounds_xz']))
    raw_floor=unary_union([shape(w2['support']['geometry']),original_public,extra]).intersection(envelope)
    solids=[];exclusions=[]
    for m in world['meshes']:
        if m['id'] in w1['disabled_source_ids'] or m['role'] not in ['Buildings','Barriers']:continue
        f=by[m['metadata']['feature_id']];g=shape(f['geometry'])
        if g.geom_type in ['LineString','MultiLineString']:g=g.buffer(world['display']['barrier_thickness_m']/2,cap_style='flat',join_style='mitre')
        if g.distance(raw_floor)<8:solids.append({'id':m['id'],'geometry':mapping(g),'bottom':m['bottom_y_m'],'top':m['top_y_m']})
    solids.extend({'id':f['id'],'geometry':f['geometry'],'bottom':f['bottom_y_m'],'top':f['top_y_m']} for f in w1['fragments'][:-1])
    for s in solids:
        g=shape(s['geometry'])
        if s['bottom']<1.7 and g.intersects(raw_floor):exclusions.append({'id':s['id'],'reason':'ground-level preserved solid footprint','geometry':mapping(g.buffer(d['solid_exclusion_margin_m']))})
    for f in features['features']:
        tags=f['source_tags'];g=shape(f['geometry'])
        if g.geom_type in ['Polygon','MultiPolygon'] and (tags.get('landuse')=='grass' or tags.get('natural')=='water' or tags.get('amenity')=='fountain'):
            if g.intersects(raw_floor):exclusions.append({'id':f['feature_id'],'reason':'source lawn/water/fountain','geometry':mapping(g)})
        elif tags.get('highway')=='steps':
            g=g.buffer(d['path_width_m']/2,cap_style='flat',join_style='mitre')
            if g.intersects(raw_floor):exclusions.append({'id':f['feature_id'],'reason':'stairs/grade not implemented','geometry':mapping(g)})
    private=unary_union([shape(by[id]['geometry']) for id in candidate['private_enclosure_exclusions']])
    exclusions.append({'id':'private_enclosures','reason':'original G04 private-enclosure exclusion','geometry':mapping(private)})
    crossings=[]
    # Broad marked crossing plus only the two genuine shared-node minor junctions.
    specs=[('sejong_marked',3,['osm:way:1084408283:highway_line','osm:way:378453707:highway_line'],[5194567167,11414286282],'marked zebra source'),
           ('side_street',1,['osm:way:431903253:highway_line'],[11414286332],'foot=designated/shared road node; paint/signals unspecified'),
           ('west_junction',5,['osm:way:37400088:highway_line'],[13012013128],'source footway/shared road node; paint/signals unspecified')]
    for id,index,road_ids,nodes,basis in specs:
        s=sections[index];path=LineString(s['source_xz'])
        zone=path.buffer(d['path_width_m']/2,cap_style='flat',join_style='mitre')
        if id!='sejong_marked':
            ns=s['node_ids'];p=s['source_xz'][ns.index(nodes[0])];zone=zone.intersection(Point(p).buffer(2.0))
        for rid,node in zip(road_ids,nodes):
            assert node in s['node_ids'] and node in by[rid]['source_topology']['node_ids']
        crossings.append({'id':id,'feature_id':s['feature_id'],'road_ids':road_ids,'shared_nodes':nodes,'source_xz':s['source_xz'],'geometry':mapping(zone),'basis':basis,'vehicle_controller':False})
    allowed_crossing=unary_union([shape(c['geometry']) for c in crossings])
    roads=json.loads((root/'data/processed/driveable_areas.json').read_text())['records'];road_exclusions=[]
    for r in roads:
        if not r['structural_candidate']:continue
        g=shape(r['source_geometry'])
        if g.geom_type not in ['LineString','MultiLineString'] or not g.intersects(raw_floor.buffer(.5)):continue
        road_exclusions.append({'id':r['feature_id'],'source_geometry':mapping(g),'geometry':mapping(g.buffer(d['road_center_exclusion_m'],cap_style='flat').difference(allowed_crossing)),'basis':'0.5m centreline exclusion outside source junctions; not surveyed road edges'})
    exclusions.extend({'id':r['id'],'reason':'road centre outside source junctions','geometry':r['geometry']} for r in road_exclusions)
    cut=unary_union([shape(e['geometry']) for e in exclusions]);floor=raw_floor.difference(cut)
    spawn=Point(w1['spawn'][0],w1['spawn'][2]);connected=[p for p in polygons(floor) if p.covers(spawn)]
    if len(connected)!=1:raise ValueError('No unique supported spawn component')
    floor=connected[0]
    before_cleanup=floor;floor=floor.simplify(1e-6,preserve_topology=True)
    cleanup_deviation=before_cleanup.hausdorff_distance(floor)
    if cleanup_deviation>1.0001e-6:raise ValueError("Numeric cleanup exceeded one micrometre")
    movement=floor.buffer(-d['movement_edge_margin_m'],join_style='mitre');routing=movement.buffer(-d['routing_extra_margin_m'],join_style='mitre')
    if len(polygons(movement))!=1 or len(polygons(routing))!=1:raise ValueError('Disconnected movement/routing domain; no invented link permitted')
    adjusted=[]
    for s in sections:
        anchors=[nearest_inside(routing,p) for p in s['source_xz']];runtime=[anchors[0]];legs=[]
        for i in range(len(anchors)-1):
            domain=routing.intersection(LineString(s['source_xz'][i:i+2]).buffer(d['max_line_adjustment_m'],cap_style='square',join_style='mitre'))
            points=shortest_inside(domain,anchors[i],anchors[i+1]);deviation=LineString(points).hausdorff_distance(LineString(s['source_xz'][i:i+2]))
            if deviation>d['max_line_adjustment_m']+1e-7:raise ValueError('Source line correction exceeded bound')
            legs.append({'source_nodes':s['node_ids'][i:i+2],'source_xz':s['source_xz'][i:i+2],'runtime_xz':points,'maximum_deviation_m':deviation});runtime.extend(points[1:])
        adjusted.append({**s,'runtime_xz':runtime,'legs':legs})
    links=[]
    public_domain=routing.intersection(original_public.union(extra))
    for id,a,b in d['area_links']:
        f=by[id];ns=f['source_topology']['node_ids'];coords=f['geometry']['coordinates'][0][0];source_nodes=dict(zip(ns,coords))
        p,q=source_nodes[a],source_nodes[b];source_path=shortest_inside(areas[id],p,q)
        pa,pb=nearest_inside(public_domain,p),nearest_inside(public_domain,q)
        path=shortest_inside(public_domain.intersection(areas[id].union(extra).union(unary_union(corridors)).buffer(1e-8)),pa,pb)
        links.append({'feature_id':id,'source_nodes':[a,b],'source_xz':source_path,'runtime_xz':path,'source_length_m':LineString(source_path).length,'length_m':LineString(path).length})
    def join(parts):
        result=[]
        for pts in parts:
            if result and math.dist(result[-1],pts[0])>.00001:result.extend(shortest_inside(routing,result[-1],pts[0])[1:])
            result.extend(pts if not result else pts[1:])
        return result
    first=list(reversed(w1['route_xz']))
    city_parts=[first,adjusted[0]['runtime_xz'],links[0]['runtime_xz'],*[s['runtime_xz'] for s in adjusted[1:5]]]
    city=join(city_parts);city_target=d['city_viewpoint_xz'];plaza_target=d['plaza_viewpoint_xz']
    city_domain=routing.intersection(unary_union([areas[d['public_areas'][1]],areas[d['public_areas'][2]],corridors[4]]))
    city.extend(shortest_inside(city_domain,city[-1],city_target)[1:]);city_checkpoint_index=len(city)-1
    city.extend(shortest_inside(city_domain,city_target,plaza_target)[1:])
    wall=join([first,adjusted[0]['runtime_xz'],links[1]['runtime_xz'],adjusted[5]['runtime_xz']])
    new_routes=[{'id':'city_plaza','name':'경내 입구→북측 횡단→시청 전면→서울광장 외곽','xz':city,'length_m':LineString(city).length,'city_checkpoint_index':city_checkpoint_index,'source_sections':[s['feature_id'] for s in adjusted[:5]],'area_links':[0],'viewpoints':[city_target,plaza_target]},
                {'id':'stonewall','name':'경내 입구→대한문 밖→남측 돌담길→서측 끝','xz':wall,'length_m':LineString(wall).length,'source_sections':[adjusted[0]['feature_id'],adjusted[5]['feature_id']],'area_links':[1]}]
    for route in [*w2['routes'],*new_routes]:
        if not movement.covers(LineString(route['xz'])):raise ValueError('Planned route exits final movement domain: '+route['id'])
    support={'id':'W03_support','material':'support','role':'Ground','source_id':None,'geometry':mapping(floor),**mesh_polygon(floor,-d['support_depth_m'],0)}
    volumes=[{'id':s['id'],'rings':rings(shape(s['geometry'])),'bottom':s['bottom'],'top':s['top']} for s in solids]
    volumes.append({'id':'W03_support','rings':rings(floor),'bottom':-.2,'top':0})
    checkpoints=w2['checkpoints']+[{'name':'시청 전면','xz':city_target,'source_node':None,'basis':d['viewpoint_basis']},{'name':'서울광장 외곽','xz':plaza_target,'source_node':None,'basis':d['viewpoint_basis']},{'name':'돌담길 서측 끝','xz':wall[-1],'source_node':13012013129}]
    inputs=[INPUT,'config/region.json','data/processed/features.json','data/processed/walkable_areas.json','data/processed/driveable_areas.json','data/processed/boundary_candidate.json','game/resources/world_geometry/world.json','game/data/generated/palace_walk.json','game/data/generated/palace_manifest.json','game/data/generated/daehanmun.json','game/resources/play_boundary.tres','game/scripts/public_boundary.gd','tools/prepare_public_walk.py','tools/prepare_palace_walk.py','tools/prepare_world.py']
    provenance={p:sha(root/p) for p in inputs}
    without_repair=unary_union([shape(w2['support']['geometry']),original_public]).intersection(envelope).difference(cut).buffer(-.4,join_style='mitre')
    data={'schema_version':1,'task':'W03','scope':d['scope'],'assumption_id':d['assumption_id'],'provenance':provenance,'support':support,'movement_rings':rings(movement),'routes':[*w2['routes'],*new_routes], 'public_routes':['city_plaza','stonewall'],'source_sections':adjusted,'area_links':links,'exclusions':exclusions,'road_exclusions':road_exclusions,'crossings':crossings,'private_rings':rings(private),'checkpoints':checkpoints,'volume_obstacles':volumes,
          'boundary':{'contract_id':d['boundary_contract_id'],'finalized_for_scene':True,'movement_edge_margin_m':.4,'road_center_exclusion_m':.5,'candidate_sha256':provenance['data/processed/boundary_candidate.json'],'support_rings':rings(floor)},
          'spawn':w1['spawn'],'route_xz':w1['route_xz'],'direction_xz':w1['direction_xz'],'normal_xz':w1['normal_xz'],'passage_length_m':w1['passage_length_m'],
          'counts':{'source_bodies':685,'active_source_bodies':682,'retained_gate_wall_fragments':4,'active_bodies':687,'created_bodies':692,'support_triangles':len(support['vertices'])//9},
          'local_support_repair':{'source':repair['source'],'bounds_xz':repair['bounds_xz'],'outward_m':repair['outward_m'],'geometry':mapping(extra.difference(cut).intersection(floor)),'basis':repair['basis']},
          'diagnostics':{'support_area_m2':floor.area,'support_holes':len(floor.interiors),'movement_components':len(polygons(movement)),'routing_components':len(polygons(routing)),'unrepaired_movement_components':len(polygons(without_repair)),'repair_area_m2':extra.difference(cut).intersection(floor).area,'numeric_cleanup_tolerance_m':1e-6,'numeric_cleanup_deviation_m':cleanup_deviation}}
    blob=encode(data);decision=(root/INPUT).read_bytes();manifest={'schema_version':1,'task':'W03','world_sha256':provenance['game/resources/world_geometry/world.json'],'w02_sha256':provenance['game/data/generated/palace_walk.json'],'region_sha256':provenance['config/region.json'],'boundary_resource_sha256':provenance['game/resources/play_boundary.tres'],'files':{'connection':{'path':'res://data/generated/public_walk.json','sha256':hashlib.sha256(blob).hexdigest()},'decision':{'path':'res://data/generated/public_decision.json','sha256':hashlib.sha256(decision).hexdigest()}}}
    for name,content in {OUT:blob,DECISION:decision,MANIFEST:encode(manifest)}.items():
        path=root/name
        if check_only:
            if not path.exists() or path.read_bytes()!=content:raise ValueError('Missing/stale W03 bundle: '+name)
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
    return {'task':'W03','passed':True,'connection_sha256':hashlib.sha256(blob).hexdigest(),'counts':data['counts'],'diagnostics':data['diagnostics'],'routes':[{k:v for k,v in r.items() if k!='xz'} for r in new_routes]}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--check',action='store_true');a=p.parse_args();print(json.dumps(prepare(a.root,a.check),ensure_ascii=False,indent=2))

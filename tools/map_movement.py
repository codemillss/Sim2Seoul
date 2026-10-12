#!/usr/bin/env python3
"""Render a G04 review map of source features; does not create runtime routes."""
import argparse
import html
from pathlib import Path
from shapely.geometry import shape
from prepare_features import load, sha
from coordinate_system import ROOT

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',default='data/reports/g04_movement_overview.svg');args=parser.parse_args()
    w=load(ROOT/'data/processed/walkable_areas.json');d=load(ROOT/'data/processed/driveable_areas.json');b=load(ROOT/'data/processed/boundary_candidate.json');f=load(ROOT/'data/processed/features.json')
    xmin,zmin,xmax,zmax=b['candidate_bounds_xz_m'];scale=min(740/(xmax-xmin),600/(zmax-zmin)); ox,oy=40,75
    def xy(p):return ox+(p[0]-xmin)*scale,oy+(p[1]-zmin)*scale
    def path(g):
        if g.geom_type.startswith('Multi') or g.geom_type=='GeometryCollection':return ' '.join(path(part) for part in g.geoms)
        rings=[g.exterior,*g.interiors] if g.geom_type=='Polygon' else [g] if g.geom_type in ('LineString','LinearRing') else []
        chunks=[]
        for ring in rings:
            points=[xy(c) for c in ring.coords];chunks.append('M '+' L '.join(f'{x:.3f},{y:.3f}' for x,y in points)+(' Z' if g.geom_type in ('Polygon','LinearRing') else ''))
        return ' '.join(chunks)
    lines=['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="740" viewBox="0 0 1200 740">',
        '<metadata>G04 source feature review; walk_sha256='+sha(ROOT/'data/processed/walkable_areas.json')+'</metadata>',
        '<rect width="1200" height="740" fill="#f8fafc"/>',
        '<style>text{font-family:Arial,"Apple SD Gothic Neo",sans-serif;fill:#172033} .small{font-size:13px}</style>',
        '<text x="35" y="30" font-size="23" font-weight="bold">G04 · 보행 / 차량 / 경계 후보</text>',
        '<text x="35" y="52" class="small">원본 선·면 연결 검토 — 확정 통행 영역, 최종 경로, 실제 지형이 아닙니다</text>',
        '<defs><clipPath id="map"><rect x="25" y="65" width="780" height="625"/></clipPath></defs><g clip-path="url(#map)">']
    def draw(g,fill,stroke,width,extra=''):
        lines.append(f'<path d="{path(g)}" fill="{fill}" fill-rule="evenodd" stroke="{stroke}" stroke-width="{width}" {extra}/>')
    for r in d['records']:
        if r['candidate_surface_geometry']:draw(shape(r['candidate_surface_geometry']),'#efd3b5','none',0)
    for r in w['records']:
        if r['candidate_surface_geometry']:draw(shape(r['candidate_surface_geometry']),'#cce8d7','none',0)
    byid={r['feature_id']:r for r in f['features']}
    for r in f['features']:
        if r['source_kind']=='building' and r['source_tags'].get('building')!='roof':draw(shape(r['geometry']),'#c7ced8','#7b8797',.5)
        elif r['source_kind']=='barrier':draw(shape(r['geometry']),'none','#263b50',1)
    draw(shape(b['candidate_geometry']),'none','#526da8',2,'stroke-dasharray="7 5"')
    colors={'R1':'#8c37b0','R2':'#176ddb','R3':'#de6913'}
    for route in w['route_reviews']:
        for fid in route['feature_chain']:
            g=shape(byid[fid]['geometry']);draw(g,'none',colors[route['route_id']],3 if g.geom_type=='LineString' else 1.8,'stroke-dasharray="5 3"' if fid in route['placement_review_feature_ids'] else '')
        for c in route['checkpoints']:
            x,y=xy(c['local_xz']);lines.append(f'<circle cx="{x:.3f}" cy="{y:.3f}" r="3.5" fill="{colors[route["route_id"]]}"/>')
    names={'osm:way:377289797:building':('대한문',12,17),'osm:way:181574577:building':('중화전',15,-12),'osm:relation:19357693:building':('석조전',-5,-20),'osm:way:198561926:building':('서울시청',0,-12),'osm:way:370019676:land_area':('서울광장',-5,0)}
    for fid,(name,dx,dy) in names.items():
        point=shape(byid[fid]['geometry']).representative_point();x,y=xy(point.coords[0]);lines.append(f'<text x="{x+dx:.3f}" y="{y+dy:.3f}" font-size="14" font-weight="bold">{html.escape(name)}</text>')
    lines.append('</g>')
    legend=[('R1 경내 연결','#8c37b0'),('R2 북측 지상 횡단 우회','#176ddb'),('R3 남측 보행면·서측 연결','#de6913'),('보행 검토용 면','#78b890'),('차량 검토용 면','#d4a56f'),('작업 경계 후보 (12m 여유)','#526da8')]
    for n,(label,color) in enumerate(legend):
        y=106+n*37;lines.append(f'<path d="M 840,{y} L 870,{y}" stroke="{color}" stroke-width="5"/><text x="880" y="{y+5}" font-size="16">{label}</text>')
    notes=['선: 원본 way 전체 표시','면: 원본 pedestrian 면의 외곽 표시','원본 면 내부의 상세 경로는 미생성','점: 원본 노드 체크포인트 후보','R1 점선: 대한문·gate 배치 보류','경계 안에서도 차도·건물·정원은','자동 통행 허용되지 않습니다.','영국대사관 경내는 경계에서 제외','남측 담장 공사 위치·폭 미확정','W0 실제 보행·충돌 검증 미실행']
    for n,note in enumerate(notes):lines.append(f'<text x="840" y="{360+n*26}" class="small">{html.escape(note)}</text>')
    lines.extend([f'<path d="M 50,706 L {50+50*scale:.3f},706" stroke="#172033" stroke-width="3"/><text x="50" y="726" class="small">50m · 미터 좌표 · 북쪽 ↑</text>',
        '<a href="https://www.openstreetmap.org/copyright"><text x="840" y="715" font-size="11">© OpenStreetMap contributors · ODbL 1.0</text></a>','</svg>'])
    out=ROOT/args.output;out.parent.mkdir(parents=True,exist_ok=True);out.write_text('\n'.join(lines)+'\n');print({'output':args.output,'width':1200,'height':740})

if __name__=='__main__':main()

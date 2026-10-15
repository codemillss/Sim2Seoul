#!/usr/bin/env python3
"""N01 static SVG diagram of retained geometry, route envelopes and stop points."""
import json
import html
from pathlib import Path
from shapely.geometry import shape,box,LineString

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text())

def main():
    npc=read('data/processed/npc_routes.json');cars=read('data/processed/vehicle_routes.json')
    features=read('data/processed/features.json');public=read('game/data/generated/public_walk.json')
    # Local X east, Z south: keep Z increasing downward, with equal metre scales.
    bounds=(-160,-260,220,30);scale=2.;left=55.;top=85.
    def xy(p):return left+(p[0]-bounds[0])*scale,top+(p[1]-bounds[1])*scale
    def line(points):return ' '.join(f'{x:.3f},{y:.3f}' for x,y in map(xy,points))
    def polygon(g,fill,stroke='none',opacity=1):
        if g.is_empty:return []
        pieces=[g] if g.geom_type=='Polygon' else list(g.geoms) if g.geom_type=='MultiPolygon' else []
        result=[]
        for p in pieces:
            segments=['M '+' L '.join(f'{x:.3f},{y:.3f}' for x,y in map(xy,r.coords))+' Z' for r in [p.exterior,*p.interiors]]
            result.append(f'<path d="{" ".join(segments)}" fill="{fill}" stroke="{stroke}" fill-rule="evenodd" opacity="{opacity}"/>')
        return result
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="900" height="900" viewBox="0 0 900 900">',
         '<rect width="900" height="900" fill="#fcfcf8"/>',
         '<g font-family="system-ui, sans-serif" fill="#18252b"><text x="40" y="35" font-size="23">N01 보행자·차량 경로 계획</text>',
         '<text x="40" y="60" font-size="13">미터 축척 유지 · 원천/가정 기반 평면도 · 실제 차선·지형·신호 및 실행 중 이동은 미검증</text>']
    clip=box(*bounds)
    for r in cars['routes']:svg+=polygon(shape(r['road_domain']).intersection(clip),'#e6e7e8')
    svg+=polygon(shape(public['support']['geometry']).intersection(clip),'#e0eee0')
    for f in features['features']:
        if f['feature_id'] not in features['coarse_body_feature_ids']:continue
        g=shape(f['geometry']).intersection(clip)
        svg+=polygon(g,'#c4c9ce','#a4acb5')
    for c in cars['crossings']:svg+=polygon(shape(c['geometry']).intersection(clip),'#fac978','#d78c15')
    colors={'palace_court':'#187c47','plaza_front':'#1c7e9c','sejong_south':'#c2364b','sejong_north':'#713caa'}
    for r in npc['routes']+cars['routes']:
        color=colors[r['id']];svg+=polygon(shape(r['swept_geometry']).intersection(clip),color,opacity=.18)
        svg.append(f'<polyline points="{line(r["xz"])}" fill="none" stroke="{color}" stroke-width="3"/>')
        for p in (r['xz'][0],r['xz'][-1]):
            x,y=xy(p);svg.append(f'<circle cx="{x}" cy="{y}" r="4" fill="white" stroke="{color}" stroke-width="2"/>')
        if 'conflicts' in r:
            route_line=LineString(r['xz']);a=route_line.interpolate(route_line.length*.5);b=route_line.interpolate(route_line.length*.5+1)
            dx,dz=b.x-a.x,b.y-a.y;size=(dx*dx+dz*dz)**.5;dx,dz=dx/size,dz/size;x,y=xy([a.x,a.y])
            arrow=[(x+10*dx,y+10*dz),(x-6*dx-5*dz,y-6*dz+5*dx),(x-6*dx+5*dz,y-6*dz-5*dx)]
            svg.append(f'<polygon points="{" ".join(f"{a:.3f},{b:.3f}" for a,b in arrow)}" fill="{color}"/>')
        for c in r.get('conflicts',[]):
            x,y=xy(c['stop_xz']);svg.append(f'<rect x="{x-6}" y="{y-3}" width="12" height="6" fill="#222"/>')
    legend=['초기 제안: 보행자2 · 차량2 (미생성)','실선: 이동 중심 / 옅은 띠: 전체 몸체 여유','녹색: 중화전 앞마당 왕복','청록색: 광장 전면 왕복','붉은색: 세종대로 남행 ↓','보라색: 세종대로 북행 ↑','주황: 기존 북측 횡단부','검은 표시: 점유 시 정지 여유 시작','흰 점: 경로 끝점','차량 끝: 정지 후 화면 밖·빈 공간일 때만 반복','N02/N03에서 실제 정지·재개·접촉 검증']
    for i,text in enumerate(legend):svg.append(f'<text x="{40 if i<6 else 460}" y="{715+(i if i<6 else i-6)*23}" font-size="12">{html.escape(text)}</text>')
    for z in range(-250,26,50):
        x,y=xy([bounds[0],z]);svg.append(f'<text x="10" y="{y}" font-size="11">{z}m</text>')
    for xvalue in range(-150,201,50):
        x,y=xy([xvalue,bounds[3]]);svg.append(f'<text x="{x-12}" y="{y+23}" font-size="11">{xvalue}m</text>')
    svg+=['<text x="460" y="851" font-size="14">북 ↑ / 동 →</text>',
          '<path d="M 660 845 H 760 M 660 840 V 850 M 760 840 V 850" fill="none" stroke="#222" stroke-width="2"/>',
          '<text x="685" y="867" font-size="12">50m</text>',
          '<text x="40" y="890" font-size="10">지도 © OpenStreetMap contributors · ODbL | 차로 위치·차폭·속도는 구현 가정이며 실제 교통 안내가 아님</text></g></svg>']
    output=ROOT/'data/reports/n01/routes.svg';output.parent.mkdir(parents=True,exist_ok=True);output.write_text('\n'.join(svg)+'\n')
    print('N01 diagram',output.relative_to(ROOT))

if __name__=='__main__':main()

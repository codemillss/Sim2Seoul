#!/usr/bin/env python3
"""Inventory intersections of the actual E03 cap triangles; do not clip sources."""
import argparse
import hashlib
import json
from pathlib import Path
from shapely import STRtree
from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[1]


def main(report):
    path=ROOT/"game/resources/world_geometry/world.json"
    world=json.loads(path.read_text());entries=world['meshes'];caps=[]
    for mesh in entries:
        vertices=mesh['vertices'];top=mesh['top_y_m'] if mesh['top_y_m'] is not None else mesh['bottom_y_m']
        triangles=[]
        for offset in range(0,len(vertices),9):
            if all(abs(vertices[offset+i+1]-top)<.000002 for i in [0,3,6]):
                triangles.append(Polygon([(vertices[offset+i],vertices[offset+i+2]) for i in [0,3,6]]))
        caps.append(unary_union(triangles))
    tree=STRtree(caps)
    categories={key:[] for key in ['body_body','route_obstacle','route_route','land_different_material']}
    coplanar_land=[]
    for i,(mesh,geometry) in enumerate(zip(entries,caps)):
        for j in tree.query(geometry,predicate='intersects'):
            j=int(j)
            if j<=i:continue
            other=entries[j];area=geometry.intersection(caps[j]).area
            if area<=.01:continue
            roles={mesh['role'],other['role']};category=None
            if roles=={'Buildings'}:category='body_body'
            elif 'Routes' in roles and roles&{'Buildings','Barriers'}:category='route_obstacle'
            elif roles=={'Routes'}:category='route_route'
            elif roles=={'Ground'} and mesh['material']!=other['material'] and 'temporary_support' not in [mesh['id'],other['id']]:category='land_different_material'
            if category:
                pair={'a':mesh['id'],'b':other['id'],'area_m2':area,'materials':[mesh['material'],other['material']]}
                if category=='land_different_material':
                    pair['display_y_separation_m']=abs(mesh['bottom_y_m']-other['bottom_y_m'])
                    if pair['display_y_separation_m']<.001:coplanar_land.append(pair)
                categories[category].append(pair)
    result={'task':'E03','passed':not categories['body_body'] and not coplanar_land,
            'world_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'basis':'actual generated top-cap polygons','threshold_m2':.01,
            'counts':{key:len(value) for key,value in categories.items()},'coplanar_different_material_land_pairs':coplanar_land,
            'pairs':categories,'policy':'intersections retained; material layers separate coplanar colours, no source geometry or permissions changed',
            'scope':'display intersections, not physical collision/access/walking approval'}
    report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'passed':result['passed'],'counts':result['counts'],'coplanar_land_pairs':len(coplanar_land)}))
    raise SystemExit(0 if result['passed'] else 1)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path,default=ROOT/'data/cache/world_overlap_check.json')
    main(parser.parse_args().report)

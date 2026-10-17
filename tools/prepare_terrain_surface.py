#!/usr/bin/env python3
"""Build a disposable, cell-indexed physical TIN from shared EXP21 inputs.

Foundation edges become actual triangle edges; no hidden flat plane bridges
between a building and its terrain. The shared source/world stays unmodified.
"""
from pathlib import Path
import argparse, hashlib, json, math
import numpy as np
import shapely
from shapely.geometry import Polygon, Point, shape
from shapely.strtree import STRtree
from terrain_mesh_conditioning import condition_triangles
ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT/'game/assets/authored/terrain_heightfield.json'
OUTPUT = ROOT/'game/data/generated/terrain_surface.json'
REPORT = ROOT/'data/reports/terrain_integration/20261018/mesh_preparation.json'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def parts(geom):
    if geom.is_empty: return []
    if geom.geom_type == 'Polygon': return [geom]
    return [p for g in getattr(geom,'geoms',[]) for p in parts(g)]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
    src=json.loads(INPUT.read_text()); signature={'heightfield_sha256':sha(INPUT),'builder_sha256':sha(Path(__file__)),'conditioning_sha256':sha(ROOT/'tools/terrain_mesh_conditioning.py')}
    if OUTPUT.exists():
        old=json.loads(OUTPUT.read_text())
        recorded=json.loads(REPORT.read_text()) if REPORT.exists() else {}
        if old.get('inputs')==signature and recorded.get('output_sha256')==sha(OUTPUT):
            print(json.dumps({'result':'PASS','mode':'reused','triangles':len(old['faces_xyz'])//9,'path':str(OUTPUT.relative_to(ROOT))}));return
    if args.check: raise SystemExit('Terrain surface missing/stale; run tools/prepare_terrain_surface.py')
    grid=src['grid']; origin=grid['origin_xz_m']; step=grid['cell_size_m']; width=grid['width']; depth=grid['depth']; values=np.asarray(grid['values_y_m']).reshape(depth,width)
    foundations=src['foundations']; pads=[]; pad_rows=[]
    for row in foundations:
        geom=shape(row.get('plateau_geometry',row['geometry']))
        if not row.get('plateau_geometry'): geom=geom.buffer(float(row.get('plateau_margin_m',0)))
        geom=shapely.union_all(parts(shapely.set_precision(shapely.make_valid(geom),1e-5)))
        if not geom.is_empty:pads.append(geom);pad_rows.append(row)
    tree=STRtree(pads)
    def grid_y(x,z):
        gx=min(max((x-origin[0])/step,0),width-1-1e-9);gz=min(max((z-origin[1])/step,0),depth-1-1e-9)
        i=int(gx);j=int(gz);u=gx-i;v=gz-j
        a,b,c,d=values[j,i],values[j,i+1],values[j+1,i],values[j+1,i+1]
        return float(a+(b-a)*u+(c-a)*v if u+v<=1 else d+(c-d)*(1-u)+(b-d)*(1-v))
    faces=[]; offsets=[0]; area=0.; max_grade=0.; min_y=math.inf;max_y=-math.inf; vertex_cache={}
    def exterior_y(x,z):
        key=(round(x,7),round(z,7))
        if key in vertex_cache:return vertex_cache[key]
        pt=Point(x,z); candidates=tree.query(pt.buffer(8).envelope); weights=[]; bases=[]
        for index in candidates:
            distance=pads[int(index)].distance(pt)
            if distance<.00002:
                y=float(pad_rows[int(index)]["base_y_m"]);vertex_cache[key]=y;return y
            if distance<8.:
                weights.append(4.*(1.-distance/8.)**2/distance**2);bases.append(float(pad_rows[int(index)]["base_y_m"]))
        y=(grid_y(x,z)+sum(w*b for w,b in zip(weights,bases)))/(1.+sum(weights))
        vertex_cache[key]=y;return y
    def emit(poly,base=None,candidates=()):
        nonlocal area,max_grade,min_y,max_y
        for p in parts(poly):
            if p.area<1e-10:continue
            triangles=shapely.constrained_delaunay_triangles(p)
            for tri in triangles.geoms:
                if tri.area<1e-10:continue
                coords=list(tri.exterior.coords)[:3]; vertices=[]
                for x,z in coords:
                    y=base
                    if y is None:
                        pt=Point(x,z);bound=[int(i) for i in candidates if pads[int(i)].distance(pt)<1e-7]
                        y=float(pad_rows[bound[0]]['base_y_m']) if bound else exterior_y(x,z)
                    vertices.append([round(x,7),round(float(y),7),round(z,7)])
                a,b,c=np.asarray(vertices);normal=np.cross(c-a,b-a)
                if normal[1]<0:vertices[1],vertices[2]=vertices[2],vertices[1];normal=-normal
                if normal[1]>1e-10:max_grade=max(max_grade,float(np.linalg.norm(normal[[0,2]])/normal[1]))
                faces.extend(v for point in vertices for v in point);area+=tri.area;min_y=min(min_y,*(p[1] for p in vertices));max_y=max(max_y,*(p[1] for p in vertices))
    for z_index in range(depth-1):
        z=origin[1]+step*z_index
        for x_index in range(width-1):
            x=origin[0]+step*x_index
            for coords in [[(x,z),(x+step,z),(x,z+step)],[(x+step,z),(x+step,z+step),(x,z+step)]]:
                triangle=shapely.set_precision(Polygon(coords),1e-5); candidates=tree.query(triangle,predicate='intersects')
                remaining=triangle
                for idx in candidates:
                    if remaining.is_empty:break
                    idx=int(idx)
                    piece=shapely.intersection(remaining,pads[idx],grid_size=1e-5)
                    emit(piece,float(pad_rows[idx]['base_y_m']))
                    remaining=shapely.union_all(parts(shapely.difference(remaining,pads[idx],grid_size=1e-5)))
                emit(remaining,None,candidates)
            offsets.append(len(faces)//9)
    faces,offsets,conditioning=condition_triangles(faces,offsets,exterior_y)
    max_grade=conditioning["maximum_triangle_grade_after"]
    min_y=min(faces[1::3]);max_y=max(faces[1::3])
    expected=(width-1)*(depth-1)*step*step
    assert abs(area-expected)<.05,(area,expected)
    payload={'schema_version':1,'task':'EXP21','inputs':signature,'domain_xz_m':src['domain_xz_m'],'grid':{'origin_xz_m':origin,'cell_size_m':step,'width':width,'depth':depth},'faces_xyz':faces,'cell_face_offsets':offsets,'foundation_count':len(foundations),'physical_surface':'Piecewise linear, source-interpolated terrain with explicit inferred flat foundation edges; unknown absolute vertical datum.'}
    OUTPUT.parent.mkdir(parents=True,exist_ok=True);OUTPUT.write_text(json.dumps(payload,separators=(',',':'))+'\n')
    report={'task':'EXP21','result':'PASS','inputs':signature,'output_sha256':sha(OUTPUT),'triangles':len(faces)//9,'cells':len(offsets)-1,'surface_area_xz_m2':area,'expected_area_xz_m2':expected,'area_error_m2':area-expected,'game_height_range_m':[min_y,max_y],'maximum_triangle_grade':max_grade,'foundation_count':len(foundations),'conditioning':conditioning,'foundation_transition':{'method':'Continuous inverse-distance transition to rigid pad boundary within8m, applied to disposable TIN vertices','precision_m':1e-5,'not_surveyed':True},'scope':'Disposable exact triangle surface and spatial index. Terrain source/CV quality is separate. Maximum grade includes inaccessible narrow inter-building gaps, not pedestrian acceptance.'}
    REPORT.parent.mkdir(parents=True,exist_ok=True);REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()

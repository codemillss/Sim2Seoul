#!/usr/bin/env python3
"""L03 native CC0 import, documented adaptation and source-bound city exteriors."""
import argparse
import hashlib
import json
import math
import os
import subprocess
import struct
from pathlib import Path

from shapely import constrained_delaunay_triangles
from shapely.geometry import MultiPoint, shape
from prepare_palace_landmarks import Model, digest, encoded, mesh_polygon, polygonal
from prepare_city_authored import build_authored

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'game/assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb'
TEXTURE = 'game/assets/vendor/kenney_city_kit_commercial/Textures/colormap.png'
LICENSE = 'game/assets/vendor/kenney_city_kit_commercial/License.txt'
RECIPES = 'game/assets/authored/landmarks/city/recipes.json'
SPEC = 'data/processed/landmark_spec.json'
WORLD = 'game/resources/world_geometry/world.json'
OUTPUT = 'game/data/generated/city_landmarks.json'
MANIFEST = 'game/data/generated/city_landmarks_manifest.json'
NATIVE = 'data/processed/l03_native_model.json'
ENGINE = os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot')


def native_import():
    # Always import the original; no .godot cache or generated .import resources needed.
    if subprocess.check_output([ENGINE,'--version'],text=True).strip()!='4.7.2.stable.official.ed1daf0bf':
        raise ValueError('Use the pinned Godot version from docs/environment.md')
    cache = ROOT / 'data/cache/l03'; cache.mkdir(parents=True, exist_ok=True)
    command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), ENGINE,
               '--headless', '--path', str(ROOT / 'game'), '--script', str(ROOT / 'tests/game/inspect_city_reuse.gd'),
               '--log-file', str(cache / 'native_import.log'), '--', '--source=' + str(ROOT / SOURCE),
               '--output=' + str(ROOT / NATIVE)]
    ran = subprocess.run(command, capture_output=True, text=True, check=True, timeout=60)
    if 'ERROR:' in ran.stdout + ran.stderr: raise ValueError(ran.stdout + ran.stderr)
    data = json.loads((ROOT / NATIVE).read_text())
    if data['source_sha256'] != digest(ROOT / SOURCE) or not data['actual_native_import']:
        raise ValueError('Native source identity differs')
    return data


def clip_plane(poly, a, b):
    """Clip 3D points and their source barycentric weights by an XZ half plane."""
    def signed(row):
        p = row[0]
        return (b[0]-a[0])*(p[2]-a[1])-(b[1]-a[1])*(p[0]-a[0])
    result = []
    for first, second in zip(poly, poly[1:]+poly[:1]):
        da, db = signed(first), signed(second)
        inside_a, inside_b = da >= -1e-10, db >= -1e-10
        if inside_a: result.append(first)
        if inside_a != inside_b:
            # Near-plane epsilon must never extrapolate outside the source face.
            t = max(0.0,min(1.0,da/(da-db)))
            result.append(([first[0][k]+t*(second[0][k]-first[0][k]) for k in range(3)],
                           [first[1][k]+t*(second[1][k]-first[1][k]) for k in range(3)]))
    return result


def adapt_sfc(item, native, recipe, gate):
    model = Model(item, {'eave_ratio': .8, 'podium_ratio': .05}, gate)
    surface = native['surfaces'][0]
    source = surface['vertices']
    bounds = [[min(source[k::3]), max(source[k::3])] for k in range(3)]
    scales = [(2*model.hu)/(bounds[0][1]-bounds[0][0]), model.height/(bounds[1][1]-bounds[1][0]),
              (2*model.hv)/(bounds[2][1]-bounds[2][0])]
    def transform(p):
        u = model.uc+(p[0]-(bounds[0][0]+bounds[0][1])/2)*scales[0]
        v = model.vc+(p[2]-(bounds[2][0]+bounds[2][1])/2)*scales[2]
        x,z = model.world(u,v)
        return [x, model.bottom+(p[1]-bounds[1][0])*scales[1], z]
    prisms = []
    for part in polygonal(model.footprint):
        for triangle in constrained_delaunay_triangles(part).geoms:
            ring = list(triangle.exterior.coords)[:3]
            if sum(ring[i][0]*ring[(i+1)%3][1]-ring[(i+1)%3][0]*ring[i][1] for i in range(3)) < 0: ring.reverse()
            prisms.append(ring)
    groups = {key: {'id': 'sfc_reused_'+key, 'material': key, 'feature_role': 'reused_model',
                    'vertices': [], 'normals': [], 'reuse_lineage': []} for key in ('glass','frame','stone')}
    kept = set()
    for offset in range(0,len(source),9):
        points = [transform(source[offset+k:offset+k+3]) for k in (0,3,6)]
        origin = [(p,[1.0 if a==b else 0.0 for b in range(3)]) for a,p in enumerate(points)]
        projection = MultiPoint([(p[0],p[2]) for p in points]).convex_hull
        if model.footprint.buffer(1e-9).covers(projection): pieces = [origin]
        else:
            pieces = []
            for ring in prisms:
                clipped = origin
                for a,b in zip(ring,ring[1:]+ring[:1]):
                    clipped = clip_plane(clipped,a,b)
                    if len(clipped)<3: break
                if len(clipped)>=3: pieces.append(clipped)
        brightness = sum(surface['sampled_rgb'][offset:offset+9])/9
        material = 'frame' if brightness>.68 else 'stone' if brightness<.28 else 'glass'
        group = groups[material]
        for piece in pieces:
            for j in range(1,len(piece)-1):
                triangle = [piece[0],piece[j],piece[j+1]]
                rounded = [[round(v,6) for v in row[0]] for row in triangle]
                # Reject clipping slivers at the precision actually stored by Godot.
                # Normals use those same positions, avoiding inverted micro-faces.
                a,b,c = [[struct.unpack('f',struct.pack('f',v))[0] for v in p] for p in rounded]
                ab,ac = [[b[k]-a[k] for k in range(3)],[c[k]-a[k] for k in range(3)]]
                n = [-(ab[1]*ac[2]-ab[2]*ac[1]),-(ab[2]*ac[0]-ab[0]*ac[2]),-(ab[0]*ac[1]-ab[1]*ac[0])]
                length = math.sqrt(sum(v*v for v in n))
                key = tuple(sorted(tuple(round(v,7) for v in p) for p in (a,b,c)))
                if length<1e-5 or min(math.dist(a,b),math.dist(b,c),math.dist(c,a))<.0001 or key in kept: continue
                kept.add(key)
                group['vertices'].extend(v for p in rounded for v in p)
                group['normals'].extend([round(v/length,9) for v in n]*3)
                group['reuse_lineage'].append({'source_triangle': offset//9, 'barycentric': [row[1] for row in triangle]})
    parts = [p for p in groups.values() if p['vertices']]
    # The imported toy-scale facade has very large panes after fitting. Add
    # restrained floor marks on its actual vertical faces, not a floating box.
    bands = {'id':'sfc_authored_floor_bands','material':'frame','feature_role':'frame','vertices':[],'normals':[],
             'metadata':{'authored_floor_divisions':28,'basis':'existing OSM levels tag, not verified real facade storeys'}}
    for group in parts:
        vs = group['vertices']; ns = group['normals']
        for offset in range(0,len(vs),9):
            tri = [vs[offset+k:offset+k+3] for k in (0,3,6)]; normal = ns[offset:offset+3]
            if abs(normal[1])>.01: continue
            for floor in range(1,28):
                y = model.bottom+model.height*floor/28
                cuts = []
                for a,b in zip(tri,tri[1:]+tri[:1]):
                    if (a[1]<=y<b[1]) or (b[1]<=y<a[1]):
                        t=(y-a[1])/(b[1]-a[1]); cuts.append([a[k]+t*(b[k]-a[k]) for k in range(3)])
                if len(cuts)!=2 or math.dist(*cuts)<.02: continue
                a,b=cuts
                points=[[p[0]+normal[0]*.04,y+dy,p[2]+normal[2]*.04] for p,dy in ((a,-.045),(b,-.045),(b,.045),(a,.045))]
                if not model.footprint.buffer(1e-8).covers(MultiPoint([(p[0],p[2]) for p in points]).convex_hull):continue
                for inds in ((0,1,2),(0,2,3)):
                    face=[points[k] for k in inds];a,b,c=face
                    ab=[b[k]-a[k] for k in range(3)];ac=[c[k]-a[k] for k in range(3)]
                    clockwise=[-(ab[1]*ac[2]-ab[2]*ac[1]),-(ab[2]*ac[0]-ab[0]*ac[2]),-(ab[0]*ac[1]-ab[1]*ac[0])]
                    if sum(clockwise[k]*normal[k] for k in range(3))<0:face.reverse()
                    bands['vertices'].extend(round(q,6) for p in face for q in p)
                    bands['normals'].extend(normal*3)
    parts.append(bands)
    # Closed visual plinth follows the complete original outline including its concavities.
    parts.append({'id': 'sfc_stone_plinth', 'material': 'stone', 'feature_role': 'stone',
                  **mesh_polygon(model.footprint,model.bottom,model.bottom+recipe['plinth_height_m'])})
    reuse = {'source_path': SOURCE, 'source_sha256': digest(ROOT / SOURCE), 'source_bounds': bounds,
             'method': 'nonuniform_fit_then_footprint_prism_clip',
             'transform': {'origin_xz_m':list(model.origin),'u_axis_xz':list(model.u),'v_axis_xz':list(model.v),
                           'local_center_uv':[model.uc,model.vc],'scale_xyz':scales,'bottom_y_m':model.bottom},
             'native_source_triangles': len(source)//9, 'native_materials': len(native['surfaces']),
             'modified_triangles':sum(len(p['vertices'])//9 for p in parts if p['feature_role']=='reused_model'),
             'modifications': ['nonuniform envelope fitting','prism clipping to original footprint','flat normals recomputed',
                               'texture palette quantized to three muted flat materials','source-bound authored stone plinth',
                               '28 authored thin floor marks on actual imported vertical faces'],
             'actual_SFC_replica':False, 'source_units_are_surveyed_metres':False}
    return parts,reuse


def build(native):
    spec = json.loads((ROOT / SPEC).read_text()); recipes = json.loads((ROOT / RECIPES).read_text())
    gate = json.loads((ROOT / 'game/data/generated/daehanmun.json').read_text())
    landmarks,reuse = [],{}
    for item in spec['landmarks']:
        if item['phase']!='L03': continue
        if item['id']=='sfc': parts,reuse = adapt_sfc(item,native,recipes['sfc'],gate)
        else: parts = build_authored(item,recipes[item['id']])
        landmarks.append({'id':item['id'],'feature_id':item['feature_id'],'source_name':item['source_name'],
                          'source_binding':item['spatial_binding'],'components':parts,
                          'collision_generated':False,'runtime_permission':None,
                          'representation':'modified generic CC0 geometry, not exact replica' if item['id']=='sfc' else 'independently authored simplification'})
    inputs = [SPEC,WORLD,RECIPES,SOURCE,TEXTURE,LICENSE,'tools/prepare_city_landmarks.py',
              'tools/prepare_city_authored.py','tools/prepare_palace_landmarks.py','tools/prepare_world.py',
              'tests/game/inspect_city_reuse.gd']
    return {'schema_version':1,'task':'L03','world_sha256':digest(ROOT / WORLD),'landmark_spec_sha256':digest(ROOT / SPEC),
            'source_sha256':{p:digest(ROOT / p) for p in inputs},'palette':recipes['palette'],'landmarks':landmarks,
            'hidden_mesh_ids':[item['source_binding']['current_visual_mesh_id'] for item in landmarks],
            'hidden_fragment_ids':[],'reuse':reuse,
            'counts':{'landmarks':len(landmarks),'components':sum(len(i['components']) for i in landmarks),
                      'triangles':sum(len(c['vertices'])//9 for i in landmarks for c in i['components']),
                      'new_collision_bodies':0,'new_routes':0,'imported_media_files':2}}


def main(check=False):
    native = native_import(); bundle = build(native); payload = encoded(bundle)
    manifest = {'schema_version':1,'task':'L03','file':{'path':'res://data/generated/city_landmarks.json',
                'sha256':hashlib.sha256(payload).hexdigest()},'world_sha256':bundle['world_sha256'],
                'landmark_spec_sha256':bundle['landmark_spec_sha256'],'source_sha256':bundle['source_sha256']}
    values = {OUTPUT:payload,MANIFEST:encoded(manifest)}
    if check:
        different = [p for p,data in values.items() if not (ROOT/p).exists() or (ROOT/p).read_bytes()!=data]
        if different: raise ValueError('Regeneration differs: '+','.join(different))
    else:
        for p,data in values.items(): (ROOT/p).parent.mkdir(parents=True,exist_ok=True); (ROOT/p).write_bytes(data)
    print('L03', 'CHECK' if check else 'PREPARED', bundle['counts'],flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true')
    parser.add_argument('--root',type=Path,default=ROOT)
    args=parser.parse_args(); ROOT=args.root.resolve(); main(args.check)

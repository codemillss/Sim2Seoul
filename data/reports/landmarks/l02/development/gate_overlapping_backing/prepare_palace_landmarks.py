#!/usr/bin/env python3
"""L02 independently authored, footprint-clipped palace exterior display meshes."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from shapely import constrained_delaunay_triangles
from shapely.geometry import Polygon, LineString, shape
from shapely.ops import unary_union

from prepare_world import mesh_polygon

ROOT = Path(__file__).resolve().parents[1]
SPEC = 'data/processed/landmark_spec.json'
WORLD = 'game/resources/world_geometry/world.json'
GATE = 'game/data/generated/daehanmun.json'
RECIPES = 'game/assets/authored/landmarks/palace/recipes.json'
OUTPUT = 'game/data/generated/palace_landmarks.json'
MANIFEST = 'game/data/generated/palace_landmarks_manifest.json'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()


def polygonal(g):
    if g.is_empty:
        return []
    if g.geom_type == 'Polygon':
        return [g] if g.area > 1e-9 else []
    if hasattr(g, 'geoms'):
        return [p for x in g.geoms for p in polygonal(x)]
    return []


def surface_mesh(g, height):
    vertices, normals = [], []
    for p in polygonal(g):
        for t in constrained_delaunay_triangles(p).geoms:
            pts = list(t.exterior.coords)[:3]
            signed = sum(pts[i][0]*pts[(i+1)%3][1]-pts[(i+1)%3][0]*pts[i][1] for i in range(3))
            if signed < 0:
                pts.reverse()
            pts3 = [(x, height(x, z), z) for x, z in pts]
            a, b, c = pts3
            ab, ac = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
            n = [-(ab[1]*ac[2]-ab[2]*ac[1]), -(ab[2]*ac[0]-ab[0]*ac[2]), -(ab[0]*ac[1]-ab[1]*ac[0])]
            length = math.sqrt(sum(q*q for q in n))
            if length < 1e-10:
                continue
            for pt in pts3:
                vertices.extend(round(v, 6) for v in pt)
                normals.extend(round(v/length, 9) for v in n)
    return {'vertices': vertices, 'normals': normals}


class Model:
    def __init__(self, item, recipe, gate):
        self.item, self.recipe = item, recipe
        self.binding = item['spatial_binding']
        self.footprint = shape(self.binding['geometry'])
        self.bottom, self.top = self.binding['current_bottom_y_m'], self.binding['current_top_y_m']
        self.height = self.top-self.bottom
        centre = self.footprint.centroid
        self.origin = (centre.x, centre.y)
        if item['id'] == 'daehanmun':
            self.u = tuple(gate['normal_xz'])
            self.v = tuple(gate['direction_xz'])
        else:
            c = list(self.footprint.minimum_rotated_rectangle.exterior.coords)
            a, b = max(zip(c, c[1:]), key=lambda e: math.dist(*e))
            v = (b[0]-a[0], b[1]-a[1]); d = math.hypot(*v)
            self.u = tuple(k/d for k in v)
            if self.u[0] < 0:
                self.u = tuple(-k for k in self.u)
            self.v = (-self.u[1], self.u[0])
        points = [self.local(x, z) for p in polygonal(self.footprint) for x, z in p.exterior.coords]
        self.umin, self.umax = min(x[0] for x in points), max(x[0] for x in points)
        self.vmin, self.vmax = min(x[1] for x in points), max(x[1] for x in points)
        self.uc, self.vc = (self.umin+self.umax)/2, (self.vmin+self.vmax)/2
        self.hu, self.hv = (self.umax-self.umin)/2, (self.vmax-self.vmin)/2
        self.gate_cut = shape(gate['cut_geometry']) if item['id'] == 'daehanmun' else None
        self.components = []
        self.eave = self.bottom+self.height*recipe['eave_ratio']
        self.podium = self.bottom+self.height*recipe['podium_ratio']

    def local(self, x, z):
        d = (x-self.origin[0], z-self.origin[1])
        return sum(d[i]*self.u[i] for i in range(2)), sum(d[i]*self.v[i] for i in range(2))

    def world(self, u, v):
        return tuple(self.origin[i]+u*self.u[i]+v*self.v[i] for i in range(2))

    def rectangle(self, u1, v1, u2, v2):
        return Polygon([self.world(u, v) for u, v in [(u1,v1),(u2,v1),(u2,v2),(u1,v2)]])

    def edge_point(self, along, side, axis='u', inset=0):
        """Place detail on the actual outline, not an empty minimum-rectangle corner."""
        if axis=='u':
            line=LineString([self.world(along,self.vmin-1),self.world(along,self.vmax+1)])
            boundary_axis=1
        else:
            line=LineString([self.world(self.umin-1,along),self.world(self.umax+1,along)])
            boundary_axis=0
        cut=line.intersection(self.footprint)
        lines=[cut] if cut.geom_type=='LineString' else list(getattr(cut,'geoms',[]))
        values=[self.local(x,z)[boundary_axis] for seg in lines if seg.geom_type=='LineString' for x,z in seg.coords]
        if not values:raise ValueError('No source facade intersection')
        edge=min(values)+inset if side==0 else max(values)-inset
        return (along,edge) if axis=='u' else (edge,along)

    def add(self, name, material, geometry, low, high, role, cut=True):
        geometry = geometry.intersection(self.footprint)
        if self.gate_cut is not None and low < 3 and cut:
            # The complete original 3 m wide engineering corridor stays empty.
            geometry = geometry.difference(self.gate_cut)
        parts = polygonal(geometry)
        if not parts or high-low < 1e-5:
            return
        geometry = unary_union(parts)
        mesh = mesh_polygon(geometry, low, high)
        self.components.append({'id': self.item['id']+'_'+name, 'material': material,
                                'feature_role': role, **mesh})

    def column(self, name, u, v, low, high, radius, material):
        x,z = self.world(u,v)
        ring = Polygon([(x+radius*math.cos(i*math.tau/8),z+radius*math.sin(i*math.tau/8)) for i in range(8)])
        self.add(name, material, ring, low, high, 'column')

    def roof(self, name='roof', low=None, top=None, material='tile'):
        low = self.eave if low is None else low
        top = self.top if top is None else top
        ridge = self.hu*self.recipe.get('roof_ridge_halfwidth_ratio', .58)
        gabled=self.recipe['family'] in ('traditional_hall','traditional_closed_gate')
        # A single roof tier with a broad hip, short ridge and a restrained eave curve.
        # Grid breaks are explicit so the long shallow lower slope is visible at human scale.
        def roof_y(x,z,outer=False):
            u,v=self.local(x,z); a,b=abs(u-self.uc),abs(v-self.vc)
            t=max(0,min(1,1-b/self.hv,(self.hu-a)/max(.001,self.hu-ridge)))
            if gabled:
                cross=max(0,1-b/self.hv)**1.3
                curve=min(cross,.52*max(0,(self.hu-a)/(self.hu-ridge))) if outer else cross
            else:curve=t**1.3
            upturn=.065*(min(a/self.hu,1)**5)*(min(b/self.hv,1)**4)
            return min(top, low+(top-low)*(curve+upturn))
        verts,norms=[],[]
        us=sorted(set([self.umin,self.uc-ridge,self.uc,self.uc+ridge,self.umax]+[self.umin+(self.umax-self.umin)*i/8 for i in range(1,8)]))
        vs=[self.vmin+(self.vmax-self.vmin)*i/12 for i in range(13)]
        for u1,u2 in zip(us,us[1:]):
            for v1,v2 in zip(vs,vs[1:]):
                outer=gabled and (u2<=self.uc-ridge+1e-9 or u1>=self.uc+ridge-1e-9)
                mesh=surface_mesh(self.rectangle(u1,v1,u2,v2).intersection(self.footprint),lambda x,z:roof_y(x,z,outer))
                verts.extend(mesh['vertices']);norms.extend(mesh['normals'])
        self.components.append({'id':self.item['id']+'_'+name,'material':material,'feature_role':'roof',
                                'vertices':verts,'normals':norms,'bottom_y_m':low,'top_y_m':top,
                                'roof_tiers':1,'authored_curve_exponent':1.3})
        if gabled:
            # The upper gable ends meet a lower hipped skirt: a single simplified paljak tier.
            # Vertical end faces are wholly inside the source footprint and retained height.
            half_v=self.hv*(1-.52**(1/1.3))
            for side,uu in enumerate((self.uc-ridge,self.uc+ridge)):
                xyz=[(*self.world(uu,self.vc-half_v),),(*self.world(uu,self.vc),),(*self.world(uu,self.vc+half_v),)]
                points=[(xyz[0][0],low+(top-low)*.52,xyz[0][1]),(xyz[1][0],top,xyz[1][1]),(xyz[2][0],low+(top-low)*.52,xyz[2][1])]
                # Gate/hall selected source surrounds both gable ends; reject instead of extrapolate.
                if not self.footprint.buffer(1e-8).covers(LineString([(p[0],p[2]) for p in points])):
                    raise ValueError('Gable end leaves selected footprint')
                desired=[self.u[0]*(-1 if side==0 else 1),0,self.u[1]*(-1 if side==0 else 1)]
                a,b,c=points;ab=[b[i]-a[i] for i in range(3)];ac=[c[i]-a[i] for i in range(3)]
                normal=[-(ab[1]*ac[2]-ab[2]*ac[1]),-(ab[2]*ac[0]-ab[0]*ac[2]),-(ab[0]*ac[1]-ab[1]*ac[0])]
                if sum(normal[i]*desired[i] for i in range(3))<0:points.reverse()
                self.components.append({'id':self.item['id']+f'_upper_gable_{side}','material':'tile_edge','feature_role':'roof',
                                        'vertices':[round(q,6) for p in points for q in p],'normals':desired*3,
                                        'bottom_y_m':low+(top-low)*.52,'top_y_m':top,'roof_tiers':1})
        # Thin bright ridge, clipped to source; its cap reaches the retained envelope top.
        self.add(name+'_ridge','tile_edge',self.rectangle(self.uc-ridge,self.vc-.11,self.uc+ridge,self.vc+.11),top-.12,top,'roof')

    def facade_rows(self, material, role='window', storeys=1, pitch=3.0):
        # Shallow strips following real boundary edges, never a new rectangle outside the footprint.
        inset=self.recipe['backing_inset_m']
        for pidx,p in enumerate(polygonal(self.footprint)):
            coords=list(p.exterior.coords)
            for eidx,(a,b) in enumerate(zip(coords,coords[1:])):
                length=math.dist(a,b)
                if length < 2:
                    continue
                count=max(1,int(length/pitch));dx,dz=(b[0]-a[0])/length,(b[1]-a[1])/length
                # Clipping makes either winding safe: the 2-sided strip is narrowed inside.
                for k in range(count):
                    centre=(k+.5)*length/count;half=min(.65,length/count*.26)
                    q1=(a[0]+dx*(centre-half),a[1]+dz*(centre-half));q2=(a[0]+dx*(centre+half),a[1]+dz*(centre+half))
                    strip=Polygon([(q1[0]-dz*inset,q1[1]+dx*inset),(q2[0]-dz*inset,q2[1]+dx*inset),(q2[0]+dz*inset,q2[1]-dx*inset),(q1[0]+dz*inset,q1[1]-dx*inset)])
                    for row in range(storeys):
                        span=self.eave-self.podium;lo=self.podium+span*(row+.23)/storeys;hi=self.podium+span*(row+.77)/storeys
                        self.add(f'{role}_{pidx}_{eidx}_{row}_{k}',material,strip,lo,hi,role)

    def traditional(self):
        recipe=self.recipe;family=recipe['family'];gate=family=='traditional_gate'
        if self.podium>self.bottom:
            self.add('stone_podium','stone',self.footprint,self.bottom,self.podium,'podium')
        inset=recipe['backing_inset_m']
        backing=self.footprint.buffer(-inset,join_style='mitre')
        wall='wood_panel' if family in ('traditional_closed_gate','shallow_porch') else 'cream_wall'
        self.add('closed_backing',wall,backing,max(self.bottom,self.podium),self.eave-.15,'backing')
        if gate:
            # Upper beam is uncut; underside exactly at the existing 3 m opening ceiling.
            self.add('passage_upper_backing','red_column',backing,3.0,self.eave-.15,'backing',cut=False)
        self.add('eave_fascia','green_beam',self.footprint,self.eave-.25,self.eave,'beam',cut=False)
        self.add('eave_ochre','ochre_trim',self.footprint,self.eave-.33,self.eave-.25,'beam',cut=False)
        self.facade_rows('wood_panel' if family!='shallow_porch' else 'dark_window',storeys=1,pitch=4.1)
        radius=recipe['column_radius_m'];col='cream_wall' if family=='shallow_porch' else 'red_column'
        # Repeated perimeter members supply a readable bay rhythm without an accessible porch.
        for side in (0,1):
            for k in range(recipe['front_bays']+1):
                u=self.umin+(self.umax-self.umin)*(k+.3)/(recipe['front_bays']+.6)
                u,v=self.edge_point(u,side,inset=radius*.45)
                self.column(f'front_column_{side}_{k}',u,v,max(self.bottom,self.podium),self.eave,radius,col)
        for side in (0,1):
            for k in range(1,recipe['side_bays']):
                v=self.vmin+(self.vmax-self.vmin)*k/recipe['side_bays']
                u,v=self.edge_point(v,side,axis='v',inset=radius*.45)
                self.column(f'side_column_{side}_{k}',u,v,max(self.bottom,self.podium),self.eave,radius,col)
        if family=='shallow_porch':
            ring=self.footprint.difference(self.footprint.buffer(-.18,join_style='mitre'))
            for k,yy in enumerate((self.podium+.48,self.podium+.88)):
                self.add(f'shallow_railing_{k}','railing',ring,yy,yy+.11,'railing')
            for side in (0,1):
                for k in range(13):
                    u=self.umin+(self.umax-self.umin)*(k+.5)/13
                    u,v=self.edge_point(u,side,inset=.025)
                    self.column(f'railing_post_{side}_{k}',u,v,self.podium+.15,self.podium+.98,.035,'railing')
        self.roof()

    def classical(self):
        self.add('base','stone_shadow',self.footprint,self.bottom,self.podium,'podium')
        self.add('closed_backing','light_stone',self.footprint.buffer(-self.recipe['backing_inset_m'],join_style='mitre'),self.podium,self.eave,'backing')
        for idx,(lo,hi) in enumerate(((self.podium-.15,self.podium+.16),(self.eave-.55,self.eave))):
            self.add(f'cornice_{idx}','light_stone',self.footprint,lo,hi,'beam')
        self.facade_rows('dark_window',storeys=2,pitch=4.0)
        # East/positive-V facade faces existing south/front stair approach. Columns remain relief.
        for side in (0,1):
            for k in range(self.recipe['front_columns']):
                u=self.umin+(self.umax-self.umin)*(k+1)/(self.recipe['front_columns']+1)
                u,v=self.edge_point(u,side,inset=.15)
                self.column(f'classical_column_{side}_{k}',u,v,self.podium+.1,self.eave-.55,.42,'light_stone')
                for capidx,lo in enumerate((self.podium,self.eave-.65)):
                    self.add(f'column_cap_{side}_{k}_{capidx}','light_stone',self.rectangle(u-.6,v-.43,u+.6,v+.43),lo,lo+.28,'column')
        # Flat parent roof plus a central triangular pediment silhouette; no duplicate part bodies.
        self.add('flat_roof','stone_shadow',self.footprint,self.eave,self.eave+.20,'roof')
        width=self.hu*self.recipe['pediment_width_ratio']
        for side in (0,1):
            _,v=self.edge_point(self.uc,side,inset=.2)
            g=self.rectangle(self.uc-width,v-.25,self.uc+width,v+.25).intersection(self.footprint)
            def height(x,z):
                u,_=self.local(x,z)
                return self.eave+.2+(self.top-self.eave-.2)*max(0,1-abs(u-self.uc)/width)
            # A closed prism with triangular upper surface rather than an unbacked open portico.
            faces,ns=[],[]
            for half in (self.rectangle(self.uc-width,v-.26,self.uc,v+.26),self.rectangle(self.uc,v-.26,self.uc+width,v+.26)):
                mesh=surface_mesh(g.intersection(half),height)
                faces.extend(mesh['vertices']);ns.extend(mesh['normals'])
            for p in polygonal(g):
                cs=list(p.exterior.coords)
                for a,b in zip(cs,cs[1:]):
                    aa=(a[0],self.eave+.19,a[1]);bb=(b[0],self.eave+.19,b[1]);at=(a[0],height(*a),a[1]);bt=(b[0],height(*b),b[1])
                    length=math.dist(a,b);normal=((b[1]-a[1])/length,0,-(b[0]-a[0])/length)
                    for pts in ((aa,bt,at),(aa,bb,bt)):
                        for pt in pts:faces.extend(round(c,6) for c in pt);ns.extend(normal)
            self.components.append({'id':self.item['id']+f'_pediment_{side}','material':'light_stone','feature_role':'pediment','vertices':faces,'normals':ns,'bottom_y_m':self.eave+.19,'top_y_m':self.top})
        # Three shallow bands are a stair silhouette inside the closed source footprint, not steps.
        _,front=self.edge_point(self.uc,1,inset=.03)
        for k in range(3):
            strip=self.rectangle(self.uc-width*.8,front-.60+k*.20,self.uc+width*.8,front-.40+k*.20)
            self.add(f'stair_relief_{k}','light_stone',strip,self.bottom,self.podium*(k+1)/3,'podium')

    def brick(self):
        self.add('podium','stone_shadow',self.footprint,self.bottom,self.podium,'podium')
        self.add('closed_backing','brick',self.footprint.buffer(-self.recipe['backing_inset_m'],join_style='mitre'),self.podium,self.eave,'backing')
        for idx,y in enumerate((self.podium,self.podium+(self.eave-self.podium)/2,self.eave-.3)):
            self.add(f'brick_band_{idx}','brick_trim',self.footprint,y,y+.22,'beam')
        self.facade_rows('teal_window',storeys=2,pitch=self.recipe['window_pitch_m'])
        self.roof()
        # Four clipped corner accents, kept below the same retained 14 m top.
        for a,u in enumerate((self.umin+self.hu*.13,self.umax-self.hu*.13)):
            for b,v in enumerate((self.vmin+self.hv*.13,self.vmax-self.hv*.13)):
                patch=self.rectangle(u-1.7,v-1.7,u+1.7,v+1.7).intersection(self.footprint)
                def accent_height(x,z):
                    uu,vv=self.local(x,z)
                    return self.eave+.12+(self.top-self.eave-.12)*max(0,1-max(abs(uu-u),abs(vv-v))/1.7)
                m=surface_mesh(patch,accent_height)
                if m['vertices']:
                    self.components.append({'id':self.item['id']+f'_corner_roof_{a}_{b}','material':'tile_edge','feature_role':'roof','bottom_y_m':self.eave,'top_y_m':self.top,**m})

    def build(self):
        family=self.recipe['family']
        if family=='classical_stone':self.classical()
        elif family=='brick_rebuilt':self.brick()
        else:self.traditional()
        return {'id':self.item['id'],'source_name':self.item['source_name'],'feature_id':self.item['feature_id'],
                'source_binding':self.binding,'minimum_features':self.item['minimum_features'],
                'recipe':self.recipe,'orientation':{'origin_xz_m':list(self.origin),'u_axis_xz':list(self.u),'v_axis_xz':list(self.v),
                                                   'front_side':'negative_v' if self.gate_cut is not None else 'positive_v',
                                                   'basis':'existing W01 passage and normal' if self.gate_cut is not None else 'long axis of original minimum rotated rectangle; authored positive-V front, not surveyed',
                                                   'local_bounds_m':[self.umin,self.vmin,self.umax,self.vmax]},
                'collision_generated':False,'runtime_permission':None,'components':self.components}


def build(root):
    read=lambda p:json.loads((root/p).read_text())
    spec,world,gate,recipes=map(read,(SPEC,WORLD,GATE,RECIPES))
    if spec['task']!='L01' or recipes['task']!='L02':raise ValueError('L01 specification and L02 recipes required')
    items=[x for x in spec['landmarks'] if x['phase']=='L02']
    if len(items)!=6 or set(recipes['landmarks'])!={x['id'] for x in items}:raise ValueError('All six palace targets required')
    landmarks=[Model(x,recipes['landmarks'][x['id']],gate).build() for x in items]
    hidden=[x['spatial_binding']['current_visual_mesh_id'] for x in items]
    componentids={fid for x in items if x['id']=='seokjojeon' for fid in x['spatial_binding']['height_component_ids']}
    hidden.extend(m['id'] for m in world['meshes'] if m.get('metadata',{}).get('feature_id') in componentids)
    inputs=(SPEC,WORLD,GATE,RECIPES,'tools/prepare_palace_landmarks.py','tools/prepare_world.py')
    return {'schema_version':1,'task':'L02','status':'authored_exterior_display_only','landmark_spec_sha256':digest(root/SPEC),
            'world_sha256':digest(root/WORLD),'source_sha256':{p:digest(root/p) for p in inputs},
            'hidden_mesh_ids':sorted(set(hidden)),'hidden_fragment_ids':['W01_gate_side_0','W01_gate_side_1','W01_gate_lintel'],
            'palette':recipes['palette'],'landmarks':landmarks,'protected_gate':spec['protected_gate'],
            'assumptions':{'geometry':'All projected triangles clipped to selected source footprints, including holes; retained current vertical envelopes',
                           'details':'Colours, ratios, curvature, relief and member spacing are authored simplifications, not surveyed measurements',
                           'closed_backing':'Inset 0.2 to 0.32 m to expose shallow column/window relief; no new porch or interior access',
                           'roof':'Single tier curved roof; Junghwajeon/Junghwamun have upper gable ends over a lower hipped skirt. All proportions are authored, not a construction survey',
                           'collision':'No collision, support, route, permission, entrance or ground changes',
                           'media':'No external media files, textures, copied calligraphy, logos or 3D models'},
            'counts':{'landmarks':len(landmarks),'components':sum(len(x['components']) for x in landmarks),
                      'triangles':sum(len(c['vertices'])//9 for x in landmarks for c in x['components']),
                      'new_collision_bodies':0,'new_routes':0,'imported_media_files':0}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=ROOT);parser.add_argument('--check',action='store_true');parser.add_argument('--output',type=Path)
    args=parser.parse_args();root=args.root.resolve();value=build(root);data=encoded(value)
    target=args.output or root/OUTPUT
    manifest_path=target.with_name(target.stem+'_manifest.json') if args.output else root/MANIFEST
    relative=target.relative_to(root).as_posix() if target.is_relative_to(root) else str(target)
    manifest=encoded({'schema_version':1,'task':'L02','file':{'path':'res://data/generated/palace_landmarks.json' if relative==OUTPUT else relative,'sha256':hashlib.sha256(data).hexdigest()},
                      'world_sha256':value['world_sha256'],'landmark_spec_sha256':value['landmark_spec_sha256'],'source_sha256':value['source_sha256']})
    for path,payload in ((target,data),(manifest_path,manifest)):
        if args.check:
            if not path.exists() or path.read_bytes()!=payload:raise ValueError('Missing/stale L02 runtime file: '+str(path))
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload)
    print(json.dumps({'task':'L02','passed':True,'output':str(target),'sha256':hashlib.sha256(data).hexdigest(),'counts':value['counts']},ensure_ascii=False))


if __name__=='__main__':main()

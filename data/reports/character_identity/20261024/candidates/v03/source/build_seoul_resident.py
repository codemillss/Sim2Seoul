#!/usr/bin/env python3
"""Author Sim2Seoul residents from explicit anatomical/clothing profiles.

No input mesh, scan, image, animation or body library is read. All positions,
topology, skeletons, weights, UVs and small material textures originate below.
Python stdlib writes glTF2 GLB directly; Pillow is only used for our own noise
and thread textures. Model coordinates are metres, +Y up, face +Z.
"""
from __future__ import annotations
import argparse, base64, hashlib, io, json, math, random, struct
from pathlib import Path
from PIL import Image
import numpy as np
from anatomical_surface_fields import deform_points
from resident_identity_mesh import build_identity_face, build_identity_hair, identity_contract
import portrait_materials

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/original/seoul_resident"
TAU = math.tau
BODY_PROFILES = ('standard','soft','athletic')

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a): return mul(a,1/max(1e-12,math.sqrt(dot(a,a))))
def mix(a,b,t): return add(mul(a,1-t),mul(b,t))
def clamp(x,a=0.,b=1.): return max(a,min(b,x))
def smooth(a,b,x):
    t=clamp((x-a)/(b-a));return t*t*(3-2*t)
def gauss(x,c,s): return math.exp(-.5*((x-c)/s)**2)
def linear_color(c): return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in c)

class Mesh:
    def __init__(self): self.v=[];self.uv=[];self.c=[];self.j=[];self.w=[];self.i=[]
    def vertex(self,p,uv,c,weights):
        index=len(self.v);self.v.append(p);self.uv.append(uv);self.c.append((*linear_color(c[:3]),1.))
        weights=sorted(weights.items(),key=lambda v:-v[1])[:4];total=sum(x[1] for x in weights)
        self.j.append(tuple([x[0] for x in weights]+[0]*(4-len(weights))))
        self.w.append(tuple([x[1]/total for x in weights]+[0.]*(4-len(weights))))
        return index
    def tri(self,a,b,c):
        # Parametric lip/eyelid endpoints can coincide exactly. Retain their
        # authoring samples but never reference a zero-area triangle, which
        # would otherwise leave an undefined corner normal in the GLB.
        normal=cross(sub(self.v[b],self.v[a]),sub(self.v[c],self.v[a]))
        if dot(normal,normal)>1e-20:self.i.extend([a,b,c])
    def quad(self,a,b,c,d): self.tri(a,b,c);self.tri(a,c,d)
    def normals(self):
        values=[[0.,0.,0.] for _ in self.v]
        for k in range(0,len(self.i),3):
            a,b,c=self.i[k:k+3];n=cross(sub(self.v[b],self.v[a]),sub(self.v[c],self.v[a]))
            for index in (a,b,c):
                for axis in range(3):values[index][axis]+=n[axis]
        return [unit(tuple(n)) for n in values]
    def raw(self,index):
        return {'p':self.v[index],'uv':self.uv[index],'c':self.c[index],'weights':{bone:amount for bone,amount in zip(self.j[index],self.w[index]) if amount>0}}
    def append_raw(self,v):
        index=len(self.v);self.v.append(v['p']);self.uv.append(v['uv']);self.c.append(v['c'])
        ordered=sorted(v['weights'].items(),key=lambda item:-item[1])[:4];total=sum(amount for _,amount in ordered)
        self.j.append(tuple([bone for bone,_ in ordered]+[0]*(4-len(ordered))))
        self.w.append(tuple([amount/total for _,amount in ordered]+[0.]*(4-len(ordered))))
        return index
    def clip_joint_plane(self,height,selector):
        """Open the existing anatomical surface at a real joint seam.

        Return its exact boundary samples, including interpolated native
        weights. The adjoining hand/foot uses these same samples rather
        than hiding two independently capped lofts inside each other.
        """
        result=Mesh();cache={};boundary={}
        def emit(v):
            key=tuple(round(x,9) for x in (*v['p'],*v['uv']))
            if key not in cache:cache[key]=result.append_raw(v)
            return cache[key]
        def interpolate(a,b,t):
            return {'p':(a['p'][0]+(b['p'][0]-a['p'][0])*t,height,a['p'][2]+(b['p'][2]-a['p'][2])*t),'uv':mix(a['uv'],b['uv'],t),'c':mix(a['c'],b['c'],t),'weights':Resident.weight_mix(a['weights'],b['weights'],t)}
        for k in range(0,len(self.i),3):
            poly=[self.raw(i) for i in self.i[k:k+3]]
            center=tuple(sum(v['p'][axis] for v in poly)/3 for axis in range(3))
            if selector(center) and any(v['p'][1]<height for v in poly):
                clipped=[]
                for a,b in zip(poly,poly[1:]+poly[:1]):
                    inside_a=a['p'][1]>=height;inside_b=b['p'][1]>=height
                    if inside_a:clipped.append(a)
                    if inside_a!=inside_b:
                        v=interpolate(a,b,(height-a['p'][1])/(b['p'][1]-a['p'][1]));clipped.append(v)
                        boundary[tuple(round(x,9) for x in v['p'])]=v
                poly=clipped
            if len(poly)>=3:
                indices=[emit(v) for v in poly]
                for j in range(1,len(indices)-1):result.tri(indices[0],indices[j],indices[j+1])
        return result,list(boundary.values())

class Resident:
    def __init__(self,female=False,swim=False,profile='standard'):
        assert profile in BODY_PROFILES
        self.female=female;self.swim=swim;self.profile=profile;self.meshes=[Mesh() for _ in range(8)]
        self.bones=[];self.ids={};self.global_rest=[];self.fingers={}
        self.body_seams={}
        self.swim_region_margin=None
        self.skin=(.69,.48,.36) if not female else (.77,.56,.44)
        self.skeleton()
    def bone(self,name,parent,p):
        index=len(self.bones);self.ids[name]=index
        self.bones.append((name,self.ids[parent] if parent else -1,p));self.global_rest.append(p);return index
    def skeleton(self):
        self.bone('Bip01 Pelvis',None,(0,.938,0))
        self.bone('Bip01 Spine','Bip01 Pelvis',(0,.980,0))
        self.bone('Bip01 Spine1','Bip01 Spine',(0,1.155,-.003))
        self.bone('Bip01 Spine2','Bip01 Spine1',(0,1.340,-.005))
        self.bone('Bip01 Neck','Bip01 Spine2',(0,1.438,-.004))
        self.bone('Bip01 Head','Bip01 Neck',(0,1.515,-.004))
        for side,sgn in [('L',1),('R',-1)]:
            pre='Bip01 '+side+' '
            self.bone(pre+'Clavicle','Bip01 Spine2',(sgn*.052,1.385,0))
            self.bone(pre+'UpperArm',pre+'Clavicle',(sgn*.178,1.385,0))
            self.bone(pre+'Forearm',pre+'UpperArm',(sgn*.232,1.098,.002))
            self.bone(pre+'Hand',pre+'Forearm',(sgn*.259,.849,.006))
            wrist=self.global_rest[self.ids[pre+'Hand']]
            # Palm extends -Y; +Z is the palm side. Four fingers are slightly
            # spread, individually jointed, with three skinned phalanges.
            lengths=[(.025,.019,.014),(.028,.021,.016),(.026,.020,.015),(.020,.016,.013)]
            for f,(x,lens) in enumerate(zip([-.022,-.007,.008,.023],lengths),1):
                x*=sgn;start=add(wrist,(x,-.067,0));parent=pre+'Hand';points=[]
                for ph,length in enumerate(lens):
                    name=pre+'Finger'+str(f)+('' if ph==0 else str(ph))
                    self.bone(name,parent,start);points.append((name,start,length));parent=name
                    start=add(start,(sgn*(f-2.5)*.0006,-length,.0035*ph))
                self.fingers[(side,f)]=points
            start=add(wrist,(-sgn*.033,-.025,.006));parent=pre+'Hand';points=[]
            for ph,length in enumerate([.025,.020,.017]):
                name=pre+'Finger0'+('' if ph==0 else str(ph))
                self.bone(name,parent,start);points.append((name,start,length));parent=name
                start=add(start,(-sgn*length*.63,-length*.76,.0015))
            self.fingers[(side,0)]=points
            self.bone(pre+'Thigh','Bip01 Pelvis',(sgn*.093,.925,0))
            self.bone(pre+'Calf',pre+'Thigh',(sgn*.096,.515,.012))
            self.bone(pre+'Foot',pre+'Calf',(sgn*.098,.111,.005))
            self.bone(pre+'Toe0',pre+'Foot',(sgn*.098,.041,.150))
    def weight(self,name):return {self.ids[name]:1.}
    def pair(self,a,b,t):return {self.ids[a]:1-clamp(t),self.ids[b]:clamp(t)}
    @staticmethod
    def weight_mix(a,b,t):
        out={key:value*(1-t) for key,value in a.items()}
        for key,value in b.items():out[key]=out.get(key,0)+value*t
        return {key:value for key,value in out.items() if value>.000001}
    def trunk_weights(self,p):
        y=p[1];levels=[(.96,'Bip01 Pelvis'),(1.04,'Bip01 Spine'),(1.20,'Bip01 Spine1'),(1.36,'Bip01 Spine2'),(1.45,'Bip01 Neck'),(1.49,'Bip01 Head')]
        if y<=levels[0][0]:return self.weight(levels[0][1])
        for (a,an),(b,bn) in zip(levels,levels[1:]):
            if y<=b:return self.pair(an,bn,smooth(a,b,y))
        return self.weight('Bip01 Head')
    def limb_weights(self,side,limb,p):
        pre='Bip01 '+side+' ';y=p[1]
        if limb=='leg':
            if y>.89:return self.pair('Bip01 Pelvis',pre+'Thigh',1-smooth(.89,.99,y))
            return self.pair(pre+'Thigh',pre+'Calf',1-smooth(.46,.57,y))
        if y>1.32:return self.pair('Bip01 Spine2',pre+'UpperArm',1-smooth(1.32,1.43,y))
        return self.pair(pre+'UpperArm',pre+'Forearm',1-smooth(1.045,1.15,y))
    def rings(self,surface,rows,segments,weights,color,deform=None,cap=True,angles=None):
        """Smoothly resample deliberately authored elliptical sections.
        row=(Y,centerX,centerZ,width,frontDepth,backDepth)."""
        dense=[];sample=self.section_sampler(rows) if surface in (1,3) else None
        for a,b in zip(rows,rows[1:]):
            steps=max(2,int(abs(b[0]-a[0])/.008))
            for k in range(steps):
                t=k/steps;y=a[0]+(b[0]-a[0])*t
                dense.append((y,*sample(y)) if sample else tuple(x+(y-x)*t for x,y in zip(a,b)))
        dense.append(rows[-1]);mesh=self.meshes[surface];ring=[]
        samples=angles if angles is not None else [TAU*j/segments for j in range(segments+1)]
        segments=len(samples)-1
        for row_index,row in enumerate(dense):
            y,cx,cz,width,front,back=row;indices=[]
            for j in range(segments+1):
                theta=samples[j];sn=math.sin(theta);cs=math.cos(theta)
                p=(cx+width*cs,y,cz+(front if sn>=0 else back)*sn)
                if deform:p=deform(p,theta)
                c=color(p,theta) if callable(color) else color
                indices.append(mesh.vertex(p,(j/segments,(y-dense[0][0])*3.),c,weights(p)))
            ring.append(indices)
        for a,b in zip(ring,ring[1:]):
            for j in range(segments):mesh.quad(a[j],b[j],b[j+1],a[j+1])
        if cap:
            for row,indices,up in [(dense[0],ring[0],False),(dense[-1],ring[-1],True)]:
                if isinstance(cap,tuple) and not cap[1 if up else 0]:continue
                p=(row[1],row[0],row[2]);c=color(p,0) if callable(color) else color
                middle=mesh.vertex(p,(.5,.5),c,weights(p))
                for j in range(segments):
                    if up:mesh.tri(middle,indices[j+1],indices[j])
                    else:mesh.tri(middle,indices[j],indices[j+1])
        return ring
    def seam_samples(self,kind,side,center):
        loop=self.body_seams.get((kind,side),[])
        if not loop:return None
        def angle(v):return math.atan2(v['p'][2]-center[2],v['p'][0]-center[0])%TAU
        loop=sorted(loop,key=angle);angles=[angle(v) for v in loop];mapping={round(t,8):v for t,v in zip(angles,loop)}
        return angles+[angles[0]+TAU],mapping
    def copy_seam_attributes(self,mesh,ring,angles,mapping):
        for index,theta in zip(ring,angles):
            source=mapping[round(theta%TAU,8)];mesh.v[index]=source['p'];mesh.c[index]=source['c']
            ordered=sorted(source['weights'].items(),key=lambda item:-item[1])[:4];total=sum(amount for _,amount in ordered)
            mesh.j[index]=tuple([bone for bone,_ in ordered]+[0]*(4-len(ordered)))
            mesh.w[index]=tuple([amount/total for _,amount in ordered]+[0.]*(4-len(ordered)))
    def tube(self,surface,path,radii,color,weights,sides=10):
        mesh=self.meshes[surface];last=None
        for i,p in enumerate(path):
            tangent=unit(sub(path[min(i+1,len(path)-1)],path[max(0,i-1)]))
            axis=unit(cross(tangent,(0,0,1)))
            if dot(axis,axis)<.5:axis=unit(cross(tangent,(0,1,0)))
            second=unit(cross(axis,tangent));ring=[]
            radius=radii[i] if isinstance(radii,list) else radii
            for j in range(sides+1):
                theta=TAU*j/sides;q=add(p,add(mul(axis,radius*math.cos(theta)),mul(second,radius*math.sin(theta))))
                w=weights(q,i) if callable(weights) else weights
                ring.append(mesh.vertex(q,(j/sides,i/max(1,len(path)-1)),color,w))
            if last:
                for j in range(sides):mesh.quad(last[j],ring[j],ring[j+1],last[j+1])
            last=ring
    def patch(self,surface,rows,color,weights):
        mesh=self.meshes[surface];indices=[]
        for i,row in enumerate(rows):
            indices.append([mesh.vertex(p,(j/max(1,len(row)-1),i/max(1,len(rows)-1)),color,weights(p)) for j,p in enumerate(row)])
        for a,b in zip(indices,indices[1:]):
            for j in range(len(a)-1):mesh.quad(a[j],b[j],b[j+1],a[j+1])
    def implicit(self,surface,bounds,fields,color,weights,blend=.018,step=.006,notch=None):
        """Weld one connected, smoothly joined authored anatomical shell.

        Own marching tetrahedra uses only our section-distance fields. Unlike
        overlapping cylinders, this really shares vertices at shoulder/crotch
        junctions, while preserving a deliberately sculpted silhouette.
        """
        axes=[np.arange(a,b+step*.5,step,dtype=np.float64) for a,b in bounds]
        xx,yy,zz=np.meshgrid(*axes,indexing='ij');points=np.stack([xx,yy,zz],axis=-1)
        distances=[(f[0](points),f[1](points) if callable(f[1]) else f[1]) if isinstance(f,tuple) else (f(points),blend) for f in fields];field=distances[0][0]
        for other,radius in distances[1:]:
            h=np.maximum(radius-np.abs(field-other),0.)/radius
            field=np.minimum(field,other)-h*h*radius*.25
        if notch is not None:field=np.maximum(field,notch(points))
        shape=field.shape;coords=np.stack(np.meshgrid(np.arange(shape[0]-1),np.arange(shape[1]-1),np.arange(shape[2]-1),indexing='ij'),-1).reshape(-1,3)
        corners=np.array([[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]])
        vi=coords[:,None,:]+corners[None,:,:]
        vals=field[vi[:,:,0],vi[:,:,1],vi[:,:,2]]
        active=(np.min(vals,axis=1)<0)&(np.max(vals,axis=1)>=0);vi=vi[active];vals=vals[active]
        pos=points[vi[:,:,0],vi[:,:,1],vi[:,:,2]]
        tetra=[[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]
        edges=[(0,1),(1,2),(2,0),(0,3),(1,3),(2,3)];mesh=self.meshes[surface];weld={}
        def vertex(q):
            p=tuple(float(v) for v in q);key=tuple(round(v,7) for v in p)
            if key in weld:return weld[key]
            c=color(p,0) if callable(color) else color
            idx=mesh.vertex(p,(p[0]*4,p[1]*4),c,weights(p));weld[key]=idx;return idx
        for tet in tetra:
            tv=vals[:,tet];tp=pos[:,tet,:];codes=np.sum((tv<0)*np.array([1,2,4,8]),axis=1)
            for case in range(1,15):
                mask=codes==case
                if not np.any(mask):continue
                v=tv[mask];p=tp[mask];crossings=[]
                for a,b in edges:
                    if bool(case&(1<<a))==bool(case&(1<<b)):continue
                    t=v[:,a]/(v[:,a]-v[:,b]);crossings.append(p[:,a,:]+t[:,None]*(p[:,b,:]-p[:,a,:]))
                for row in range(len(v)):
                    poly=[e[row] for e in crossings];center=np.mean(poly,axis=0)
                    inside=p[row][[bool(case&(1<<a)) for a in range(4)]].mean(axis=0)
                    normal=unit(tuple(center-inside));axis=unit(tuple(poly[0]-center));second=cross(normal,axis)
                    poly.sort(key=lambda q:math.atan2(dot(tuple(q-center),second),dot(tuple(q-center),axis)))
                    ids=[vertex(q) for q in poly]
                    for j in range(1,len(ids)-1):mesh.tri(ids[0],ids[j],ids[j+1])
    @staticmethod
    def section_sampler(rows):
        """C1 shape-preserving cubic sections with the exact authored anchors.

        Weighted harmonic slopes are zero at a local extremum. Each segment
        stays inside its adjacent anchor values: no bulges from spline
        overshoot, and no hard derivative jump at anatomical section rings.
        """
        values=np.array(sorted(rows,key=lambda row:row[0]),dtype=float)
        ys=values[:,0];cols=values[:,1:];h=np.diff(ys);delta=np.diff(cols,axis=0)/h[:,None]
        slopes=np.zeros_like(cols)
        if len(ys)==2:slopes[0]=slopes[1]=delta[0]
        else:
            for i in range(1,len(ys)-1):
                a,b=delta[i-1],delta[i];same=(a*b)>0;w1=2*h[i]+h[i-1];w2=h[i]+2*h[i-1]
                slopes[i,same]=(w1+w2)/(w1/a[same]+w2/b[same])
            for endpoint,d0,d1,h0,h1 in [(0,delta[0],delta[1],h[0],h[1]),(-1,delta[-1],delta[-2],h[-1],h[-2])]:
                m=((2*h0+h1)*d0-h0*d1)/(h0+h1)
                m=np.where(m*d0<=0,0,m);m=np.where((d0*d1<0)&(np.abs(m)>3*np.abs(d0)),3*d0,m)
                slopes[endpoint]=m
        def sample(y):
            yy=np.clip(np.asarray(y,dtype=float),ys[0],ys[-1]);i=np.clip(np.searchsorted(ys,yy,side='right')-1,0,len(ys)-2)
            t=((yy-ys[i])/h[i])[...,None];hh=h[i][...,None]
            return (2*t**3-3*t*t+1)*cols[i]+(t**3-2*t*t+t)*hh*slopes[i]+(-2*t**3+3*t*t)*cols[i+1]+(t**3-t*t)*hh*slopes[i+1]
        return sample
    @staticmethod
    def section_field(rows):
        rows=sorted(rows,key=lambda row:row[0]);ys=np.array([r[0] for r in rows]);sample=Resident.section_sampler(rows)
        def field(p):
            y=p[...,1];sections=sample(y);cx,cz,width,front,back=[sections[...,i] for i in range(5)];depth=np.where(p[...,2]>=cz,front,back)
            radial=(np.sqrt(((p[...,0]-cx)/width)**2+((p[...,2]-cz)/depth)**2)-1)*np.minimum(width,depth)
            return np.maximum(radial,np.maximum(ys[0]-y,y-ys[-1]))
        return field
    @staticmethod
    def ellipsoid_field(center,radius):
        c=np.array(center);r=np.array(radius)
        return lambda p:(np.sqrt(np.sum(((p-c)/r)**2,axis=-1))-1)*min(radius)
    @staticmethod
    def shoulder_blend(points):
        t=np.clip((points[...,1]-1.290)/.065,0,1);return .000001+.024*t*t*(3-2*t)
    @staticmethod
    def armpit_notch(torso,arm):
        torso_sample=Resident.section_sampler(torso);arm_sample=Resident.section_sampler(arm)
        def cut(points):
            y=points[...,1];tr=torso_sample(y);ar=arm_sample(y);outer=tr[...,2];inner=np.abs(ar[...,0])-ar[...,2];middle=(outer+inner)*.5
            t=np.clip((y-1.285)/.030,0,1);width=.008*(1-t*t*(3-2*t))
            # A real positive air slit, not just zero smooth-union radius:
            # overlapping rest fields otherwise fuse a long low armpit web.
            arm_cut=np.where(y<1.315,width-np.abs(np.abs(points[...,0])-middle),-1e6)
            return np.maximum(arm_cut,Resident.crotch_notch(points))
        return cut
    @staticmethod
    def crotch_notch(points):
        y=points[...,1];t=np.clip((y-.825)/.040,0,1);width=.009*(1-t*t*(3-2*t))
        # At 14mm extraction pitch a 4–10mm natural leg gap can alias into
        # a false web well below the pelvis. Explicitly retain the air gap
        # and close it smoothly only at the true upper groin.
        return np.where(y<.865,width-np.abs(points[...,0]),-1e6)
    def build(self):
        self.body();self.face();self.hair();self.hands();self.feet()
        if not self.swim:self.clothing()
        else:self.bathing_suit()
        self.sculpt_body_profile()
        return self
    def sculpt_body_profile(self):
        """Apply one shared anatomical surface field to skin and clothing.

        Rest bones, metre scale and hand/foot contacts stay independent from
        the authored tissue surface. A broad pelvis support blend prevents
        enlarged upper-medial skin from switching abruptly between thighs.
        """
        bone_names=[b[0] for b in self.bones]
        for surface,mesh in enumerate(self.meshes):
            # Preserve material-independent anatomical coordinates for weighting.
            source_points=mesh.v
            mesh.v=deform_points(mesh.v,mesh.j,mesh.w,bone_names,profile=self.profile,female=self.female,garment=surface in [0,4,5,6])
            if self.profile!='standard':
                for index,(x,y,z) in enumerate(mesh.v):
                    neck_head=sum(amount for bone,amount in zip(mesh.j[index],mesh.w[index]) if bone_names[bone] in ['Bip01 Neck','Bip01 Head'])
                    neck=(.18 if self.profile=='soft' else .12)*gauss(y,1.452,.039)*(1-smooth(.050,.073,abs(x)))*(1-smooth(.045,.070,abs(z)))*neck_head
                    if neck>0:mesh.v[index]=(x*(1+neck),y,z*(1+neck*.8))
            if self.profile=='soft':
                for index,p in enumerate(mesh.v):
                    x,y,z=p
                    # Profile fat on cheeks is deliberately separate from
                    # protected head contacts in the anatomical body helper.
                    head=sum(amount for bone,amount in zip(mesh.j[index],mesh.w[index]) if bone_names[bone]=='Bip01 Head')
                    fullness=.10*gauss(y,1.505,.042)*head
                    if fullness>0:mesh.v[index]=(x*(1+fullness),y,z*(1+fullness*.55))
                    ox,oy,oz=source_points[index]
                    support=.88*smooth(.70,.89,oy)*(1-smooth(.025,.165,abs(ox)))*(1-smooth(.98,1.09,oy))
                    if support>1e-8:
                        original={bone:amount for bone,amount in zip(mesh.j[index],mesh.w[index]) if amount>0}
                        revised=self.weight_mix(original,self.weight('Bip01 Pelvis'),support)
                        ordered=sorted(revised.items(),key=lambda item:-item[1])[:4];total=sum(amount for _,amount in ordered)
                        mesh.j[index]=tuple([bone for bone,_ in ordered]+[0]*(4-len(ordered)))
                        mesh.w[index]=tuple([amount/total for _,amount in ordered]+[0.]*(4-len(ordered)))
    def body(self):
        # Clothed mesh omits hidden skin, rather than retaining duplicate
        # anatomy under fabric. Swimming uses the very same authored body.
        if self.swim:
            f=.94 if self.female else 1.
            rows=[(.855,0,0,.086,.078,.100),(.9,0,-.003,.144*f,.101,.119),(.955,0,-.006,.154*f,.105,.112),(1.03,0,0,.134*f,.085,.090),(1.13,0,-.002,.127*f,.083,.079),(1.235,0,-.004,.149*f,.098,.086),(1.32,0,-.007,.166*f,.091,.083),(1.375,0,-.005,.176*f,.074,.071),(1.415,0,0,.135,.051,.053),(1.445,0,0,.046,.039,.037),(1.495,0,0,.041,.037,.035)]
            def tone(p,t):
                front=max(0,math.sin(t));shade=1-.06*front*gauss(p[1],1.04,.07)-.05*gauss(p[0],0,.018)*front
                return mul(self.skin,shade)
            body_field=self.section_field(rows);fields=[body_field];arm_fields={};leg_fields={}
            for side,s in [('L',1),('R',-1)]:
                leg=[(.10,s*.098,.005,.030,.032,.033),(.19,s*.098,.002,.033,.032,.038),(.28,s*.097,-.003,.041,.035,.051),(.38,s*.094,-.004,.049,.038,.061),(.45,s*.095,.004,.044,.036,.048),(.495,s*.096,.009,.041,.043,.036),(.535,s*.096,.010,.044,.045,.040),(.61,s*.094,.006,.060,.066,.060),(.77,s*.09,0,.077,.080,.080),(.88,s*.083,0,.081,.086,.091),(.94,s*.076,0,.073,.083,.096)]
                leg_fields[side]=self.section_field(leg);fields.append(leg_fields[side])
                arm=[(.851,s*.259,.006,.025,.024,.023),(.94,s*.250,0,.032,.030,.029),(1.04,s*.239,.002,.039,.035,.034),(1.098,s*.232,.002,.035,.035,.033),(1.19,s*.215,0,.045,.046,.043),(1.29,s*.195,0,.050,.052,.048),(1.37,s*.178,0,.048,.053,.051),(1.405,s*.162,0,.035,.040,.039)]
                arm_section=self.section_field(arm);deltoid=self.ellipsoid_field((s*.159,1.366,0),(.057,.058,.054))
                arm_fields[side]=lambda p,a=arm_section,b=deltoid:np.minimum(a(p),b(p))
                fields.append((arm_fields[side],self.shoulder_blend))
            # Material ownership follows the authored rest anatomy, not a
            # rectangular XY range that can also contain the hanging arms.
            def swim_region_margin(points):
                garment=np.minimum(body_field(points),np.minimum(leg_fields['L'](points),leg_fields['R'](points)))
                arms=np.minimum(arm_fields['L'](points),arm_fields['R'](points))
                return arms-garment
            self.swim_region_margin=swim_region_margin
            def body_weights(p):
                x,y,z=p;side='L' if x>0 else 'R'
                point=np.array(p)
                db=float(body_field(point));dl=float(leg_fields[side](point));da=float(arm_fields[side](point))
                # The medial groin belongs to the pelvis. A sign(x) choice
                # between two moving thighs would tear a shared crotch edge.
                medial_pelvis=smooth(.75,.91,y)*(1-smooth(.022,.110,abs(x)))
                # Keep the exact shared centre seam wholly on the pelvis;
                # broaden the surrounding upper-thigh transition separately.
                center_seam=smooth(.74,.83,y)*(1-smooth(.015,.095,abs(x)))
                medial_pelvis=1-(1-medial_pelvis)*(1-center_seam)
                leg_amount=smooth(-.035,.035,db-dl)*(1-medial_pelvis)
                base=self.weight_mix(self.trunk_weights(p),self.limb_weights(side,'leg',p),leg_amount)
                # Arms extend to wrist-height beside the pelvis. Classifying
                # y<1m as a leg/torso gives a 1m discontinuity on the forearm.
                arm_amount=smooth(-.060,.060,min(db,dl)-da)
                return self.weight_mix(base,self.limb_weights(side,'arm',p),arm_amount)
            self.implicit(1,[(-.29,.29),(.101,1.49),(-.13,.13)],fields,tone,body_weights,.017,.010,notch=self.armpit_notch(rows,arm))
            for kind,height,selector in [
                ('wrist',.889,lambda p:abs(p[0])>.205 and p[1]<.95),
                ('ankle',.145,lambda p:abs(p[0])<.18 and p[1]<.20)]:
                self.meshes[1],boundary=self.meshes[1].clip_joint_plane(height,selector)
                for side,sign in [('L',1),('R',-1)]:self.body_seams[(kind,side)]=[v for v in boundary if v['p'][0]*sign>0]
        # Neck is visible in every garment variant.
        neck=self.rings(1,[(1.408,0,-.002,.052,.042,.041),(1.44,0,0,.043,.039,.037),(1.48,0,-.002,.039,.038,.034),(1.505,0,-.003,.044,.043,.036)],32,self.trunk_weights,self.skin)
        self.identity_neck_ring=next(row for row in neck if abs(self.meshes[1].v[row[0]][1]-1.440)<1e-8)
        # Preserve the exact lower-neck vertices/native influences. The new
        # portrait continues from this ring through submental tissue and nape.
        # Remove the old hidden upper-neck cap/surface, including the implicit
        # bare-neck overlap; no body vertex below the boundary is moved.
        skin=self.meshes[1]
        skin.i=[index for k in range(0,len(skin.i),3) if all(skin.v[index][1]<=1.440+1e-8 for index in skin.i[k:k+3]) for index in skin.i[k:k+3]]
    def face(self):
        build_identity_face(self)
    def weight_head(self,p):return self.weight('Bip01 Head')
    def hair(self):
        build_identity_hair(self)
    def thumb_web(self,palm_rings,palm_angles,wrist,side,path,radii,weights):
        """Branch the thumb from a real opening in the palm surface.

        The thenar/web is an indexed loft from the palm's own boundary to
        the existing proximal thumb. It replaces the cut-off open cylinder
        at the thumb root; the original joints and distal contacts stay put.
        """
        mesh=self.meshes[3];s=1 if side=='L' else -1;n=len(palm_angles)-1
        center=math.pi if s>0 else 0.
        selected=[math.cos((palm_angles[j]+palm_angles[j+1])*.5-center)>math.cos(.90) for j in range(n)]
        start=next(j for j in range(n) if selected[j] and not selected[(j-1)%n]);count=0
        while selected[(start+count)%n]:count+=1
        arc=list(range(start,start+count+1))
        ys=[mesh.v[ring[0]][1] for ring in palm_rings]
        low=min(range(len(ys)),key=lambda i:abs(ys[i]-(wrist[1]-.050)))
        high=min(range(len(ys)),key=lambda i:abs(ys[i]-(wrist[1]-.005)))
        removed=set()
        for row in range(low,high):
            a,b=palm_rings[row],palm_rings[row+1]
            for segment in arc[:-1]:
                j=segment%n
                removed.add(tuple(sorted((a[j],b[j],b[j+1]))));removed.add(tuple(sorted((a[j],b[j+1],a[j+1]))))
        mesh.i=[index for k in range(0,len(mesh.i),3) if tuple(sorted(mesh.i[k:k+3])) not in removed for index in mesh.i[k:k+3]]
        at=lambda row,j:palm_rings[row][j%n]
        boundary=[at(low,j) for j in arc]
        boundary += [at(row,arc[-1]) for row in range(low+1,high+1)]
        boundary += [at(high,j) for j in arc[-2::-1]]
        boundary += [at(row,arc[0]) for row in range(high-1,low,-1)]
        points=[mesh.v[index] for index in boundary];target=mix(path[2],path[3],.5)
        tangent=unit(sub(path[3],path[2]));axis=unit(cross(tangent,(0,0,1)));second=unit(cross(axis,tangent))
        angles=[math.atan2(dot(sub(p,target),second),dot(sub(p,target),axis)) for p in points]
        orientation=sum(math.sin(b-a) for a,b in zip(angles,angles[1:]+angles[:1]))
        lengths=[math.sqrt(dot(sub(b,a),sub(b,a))) for a,b in zip(points,points[1:]+points[:1])];total=sum(lengths);travel=0.;theta=[]
        for length in lengths:
            theta.append(angles[0]+(1 if orientation>0 else -1)*TAU*travel/total);travel+=length
        thumb_weight=weights(target,2);last=boundary;radius=(radii[2]+radii[3])*.5
        for row in range(1,6):
            t=row/5;ring=[]
            for k,(source,angle) in enumerate(zip(boundary,theta)):
                circle=add(target,add(mul(axis,radius*math.cos(angle)),mul(second,radius*math.sin(angle))))
                p=mix(mesh.v[source],circle,t)
                base={bone:amount for bone,amount in zip(mesh.j[source],mesh.w[source]) if amount>0}
                ring.append(mesh.vertex(p,(k/len(boundary),t*.15),self.skin,self.weight_mix(base,thumb_weight,smooth(0,1,t))))
            for k in range(len(ring)):mesh.quad(last[k],ring[k],ring[(k+1)%len(ring)],last[(k+1)%len(ring)])
            last=ring
        for original_index in range(3,len(path)):
            p=path[original_index];tangent=unit(sub(path[min(original_index+1,len(path)-1)],path[max(0,original_index-1)]));axis=unit(cross(tangent,(0,0,1)));second=unit(cross(axis,tangent));ring=[]
            for k,angle in enumerate(theta):
                q=add(p,add(mul(axis,radii[original_index]*math.cos(angle)),mul(second,radii[original_index]*math.sin(angle))))
                ring.append(mesh.vertex(q,(k/len(theta),original_index/(len(path)-1)),self.skin,weights(q,original_index)))
            for k in range(len(ring)):mesh.quad(last[k],ring[k],ring[(k+1)%len(ring)],last[(k+1)%len(ring)])
            last=ring
    def hands(self):
        for side,s in [('L',1),('R',-1)]:
            pre='Bip01 '+side+' ';wrist=self.global_rest[self.ids[pre+'Hand']]
            rows=[]
            for y,width,front,back in [(0,.024,.020,.018),(-.018,.031,.017,.014),(-.045,.034,.015,.012),(-.065,.032,.013,.011),(-.075,.027,.010,.009)]:
                rows.append((wrist[1]+y,wrist[0],wrist[2],width,front,back))
            rows.reverse()
            # The own palm continues into a real wrist beneath the sleeve;
            # omitting clothed forearm skin otherwise leaves a 19mm gap from
            # wrist y=.849 to cuff y=.868. The top overlaps the cuff/body by
            # 38mm and inherits the native forearm, while the lower end follows
            # Hand with a continuous transition when the wrist turns.
            for rise,width,front,back in [(.018,.024,.021,.019),(.038,.025,.023,.021),(.057,.026,.024,.022)]:
                y=wrist[1]+rise;t=rise/(1.098-.849)
                rows.append((y,wrist[0]+(s*.232-wrist[0])*t,wrist[2]+(.002-wrist[2])*t,width,front,back))
            def wrist_weights(p,pre=pre,wrist=wrist):
                return self.pair(pre+'Hand',pre+'Forearm',smooth(wrist[1]-.010,wrist[1]+.038,p[1]))
            def palm_shape(p,theta,wrist=wrist,s=s):
                lx=(p[0]-wrist[0])*s;ly=p[1]-wrist[1];front=max(0,math.sin(theta));back=max(0,-math.sin(theta))
                thenar=.0048*gauss(lx,-.020,.013)*gauss(ly,-.031,.023)
                hypothenar=.0028*gauss(lx,.021,.012)*gauss(ly,-.044,.024)
                flexion=-.00065*gauss(ly+.08*lx,-.045,.0022)-.0005*gauss(ly-.10*lx,-.062,.0018)
                metacarpal=.0012*sum(gauss(lx,tx,.004) for tx in [-.022,-.007,.008,.023])*gauss(ly,-.043,.026)
                return p[0],p[1],p[2]+(thenar+hypothenar+flexion)*front-metacarpal*back
            samples=self.seam_samples('wrist',side,(wrist[0],.889,wrist[2])) if self.swim else None
            if samples:
                angles,mapping=samples
                rows=[row for row in rows if row[0]<=wrist[1]+.0181]
                rows.append((.889,wrist[0],wrist[2],.027,.026,.024))
                def joined_palm(p,theta,palm_shape=palm_shape,mapping=mapping):
                    q=palm_shape(p,theta);boundary=mapping[round(theta%TAU,8)]['p'];amount=smooth(.867,.889,p[1])
                    return (q[0]+(boundary[0]-q[0])*amount,p[1],q[2]+(boundary[2]-q[2])*amount)
                rings=self.rings(3,rows,32,wrist_weights,self.skin,joined_palm,cap=(True,False),angles=angles)
                self.copy_seam_attributes(self.meshes[3],rings[-1],angles,mapping)
            else:
                angles=[TAU*k/32 for k in range(33)]
                rings=self.rings(3,rows,32,wrist_weights,self.skin,palm_shape)
            # Real hands have interdigital web skin between the MCP roots.
            # These softly curved surfaces share the palm envelope and keep
            # a broad Hand contribution while each adjacent finger flexes.
            for finger in range(1,4):
                a=self.fingers[(side,finger)][0];b=self.fingers[(side,finger+1)][0]
                for front in [True,False]:
                    web=[]
                    for row in range(5):
                        phase=row/4;line=[]
                        for k in range(9):
                            t=k/8;x=a[1][0]+(b[1][0]-a[1][0])*t
                            y=wrist[1]-.059-phase*(.008+.0035*math.sin(math.pi*t))
                            z=wrist[2]+(.012-.002*phase if front else -.007+.001*phase)
                            line.append((x,y,z))
                        web.append(line)
                    wa=self.weight(a[0]);wb=self.weight(b[0]);hand=self.weight(pre+'Hand')
                    def web_weights(p,wa=wa,wb=wb,hand=hand,a=a,b=b):
                        t=clamp((p[0]-a[1][0])/(b[1][0]-a[1][0]));finger_mix=self.weight_mix(wa,wb,t)
                        return self.weight_mix(hand,finger_mix,.20)
                    self.patch(3,web,self.skin,web_weights)
            for f in range(5):
                chain=self.fingers[(side,f)];path=[];radii=[]
                for ph,(name,start,length) in enumerate(chain):
                    end=chain[ph+1][1] if ph<2 else add(start,(-s*length*.63,-length*.76,.0015) if f==0 else (s*(f-2.5)*.0015,-length,.0015))
                    for k in range(5):
                        t=k/5;path.append(mix(start,end,t));radii.append((.0090 if f==0 else .0078-.0006*abs(f-2.4))*(1-.22*(ph+t)/3)*(1+.06*math.cos(TAU*t)))
                path.append(end);radii.append(.002)
                def fw(p,i,chain=chain):
                    phase=min(2,i//5);amount=(i%5)/5
                    if phase<2 and amount>.55:return self.pair(chain[phase][0],chain[phase+1][0],smooth(.55,1,amount))
                    return self.weight(chain[phase][0])
                if f==0:self.thumb_web(rings,angles,wrist,side,path,radii,fw)
                else:self.tube(3,path,radii,self.skin,fw,12)
                # Nail is a small inset skin plate, not a finger-sized box.
                endbone,start,length=chain[2];center=mix(start,end,.55)
                rows=[]
                for k in range(5):
                    t=k/4;half=.0032*math.sin(math.pi*(.1+.8*t))
                    rows.append([(center[0]-half,center[1]+(.004-.008*t),center[2]-.005),(center[0]+half,center[1]+(.004-.008*t),center[2]-.005)])
                self.patch(3,rows,mix(self.skin,(.89,.72,.64),.55),lambda p,n=endbone:self.weight(n))
    def feet(self):
        for side,s in [('L',1),('R',-1)]:
            pre='Bip01 '+side+' ';cx=s*.098
            if self.swim:
                rows=[(.006,cx,.035,.039,.112,.075),(.015,cx,.031,.043,.122,.080),(.033,cx,.022,.045,.117,.074),(.055,cx,.006,.034,.079,.057),(.095,cx,0,.029,.040,.038),(.13,cx,0,.030,.035,.035)]
                samples=self.seam_samples('ankle',side,(cx,.145,.003))
                if samples:
                    angles,mapping=samples;rows.append((.145,cx,.003,.034,.036,.037))
                    def ankle_shape(p,theta,mapping=mapping):
                        boundary=mapping[round(theta%TAU,8)]['p'];amount=smooth(.095,.145,p[1])
                        return (p[0]+(boundary[0]-p[0])*amount,p[1],p[2]+(boundary[2]-p[2])*amount)
                    rings=self.rings(1,rows,36,lambda p,pre=pre:self.pair(pre+'Foot',pre+'Calf',smooth(.095,.145,p[1])),self.skin,ankle_shape,cap=(True,False),angles=angles)
                    self.copy_seam_attributes(self.meshes[1],rings[-1],angles,mapping)
                else:self.rings(1,rows,36,lambda p,pre=pre:self.weight(pre+'Foot'),self.skin)
                for toe in range(5):
                    x=cx+(-.030+.015*toe);length=.034-.003*toe
                    path=[(x,.017,.115),(x,.015,.13+length*.4),(x,.015,.13+length)]
                    self.tube(1,path,[.0085-.0007*toe,.0075-.0006*toe,.002],self.skin,self.weight(pre+'Toe0'),10)
            else:
                # Continuous sneaker upper, raised heel counter and rounded
                # asymmetric toe box; two sole layers retain flat contact.
                rows=[(.006,cx,.047,.046,.129,.085),(.016,cx,.047,.048,.131,.087),(.031,cx,.045,.048,.130,.087),(.043,cx,.040,.047,.128,.085),(.065,cx,.018,.043,.111,.071),(.084,cx,-.005,.038,.073,.056),(.112,cx,-.008,.032,.045,.044),(.126,cx,-.008,.028,.035,.036)]
                def shoe_tone(p,t):
                    if p[1]<.032:return (.70,.71,.70)
                    if p[1]<.043:return (.92,.90,.84)
                    return (.80,.81,.77)
                self.rings(5,rows,40,lambda p,pre=pre:self.weight(pre+'Foot'),shoe_tone)
                for k in range(5):
                    z=.037+.013*k;y=.098-.0045*k
                    self.tube(6,[(cx-.019,y,z-.004),(cx,y+.002,z+.003),(cx+.019,y,z-.004)],.0016,(.89,.88,.82),self.weight(pre+'Foot'),6)
                for xsign in [-1,1]:
                    self.tube(5,[(cx+xsign*.043,.047,-.024),(cx+xsign*.045,.045,.035),(cx+xsign*.04,.043,.104)],.0012,(.30,.32,.31),self.weight(pre+'Foot'),6)
    def clothing(self):
        jacket=(.10,.14,.18) if not self.female else (.57,.53,.44)
        pants=(.24,.25,.25) if not self.female else (.075,.085,.095)
        torso=[(.965,0,0,.149,.098,.098),(.980,0,0,.152,.102,.101),(1.03,0,0,.147,.101,.098),(1.13,0,-.003,.151,.106,.101),(1.24,0,-.006,.173,.112,.105),(1.32,0,-.007,.186,.108,.100),(1.375,0,-.004,.192,.088,.087),(1.408,0,-.002,.166,.069,.072),(1.425,0,-.001,.052,.045,.043)]
        def fabric(p,t):
            fold=1+.022*math.sin(t*8+p[1]*83)*gauss(p[1],1.035,.055)
            return (p[0]*fold,p[1],p[2]*fold)
        torso_field=self.section_field(torso);jacket_fields=[torso_field];jacket_arm_fields={}
        pants_fields=[self.ellipsoid_field((0,.933,-.003),(.159,.090,.114))]
        for side,s in [('L',1),('R',-1)]:
            arm=[(.868,s*.258,.006,.029,.027,.027),(.884,s*.256,.006,.030,.029,.028),(.925,s*.251,0,.035,.034,.032),(1.02,s*.241,0,.043,.042,.039),(1.095,s*.232,.002,.041,.041,.038),(1.18,s*.217,0,.051,.051,.046),(1.29,s*.196,0,.058,.058,.055),(1.36,s*.174,0,.057,.058,.055),(1.395,s*.157,0,.035,.044,.041)]
            arm_field=self.section_field(arm);deltoid=self.ellipsoid_field((s*.164,1.353,-.001),(.059,.052,.058))
            jacket_arm_fields[side]=lambda p,a=arm_field,b=deltoid:np.minimum(a(p),b(p))
            jacket_fields.append((jacket_arm_fields[side],self.shoulder_blend))
            # Cuffs and shoulder stitching are actual slender curved strips.
            for y,radius,cx in [(.879,.030,s*.256),(.886,.030,s*.256)]:
                path=[(cx+radius*math.cos(TAU*k/40),y,.003+radius*.91*math.sin(TAU*k/40)) for k in range(41)]
                self.tube(0,path,.0010,(.54,.57,.59),lambda p,i,side=side:self.limb_weights(side,'arm',p),6)
            # A curved sleeve construction seam follows the acromion into
            # the arm. A horizontal ring across the shoulder reads as the
            # cut edge of a cylinder rather than tailored clothing.
            seam=[];anchors=[(s*.055,1.412,.039),(s*.128,1.394,.070),(s*.195,1.350,.051),(s*.226,1.290,.014)]
            for a,b in zip(anchors,anchors[1:]):
                for k in range(10):seam.append(mix(a,b,k/10))
            seam.append(anchors[-1]);self.tube(0,seam,.00065,(.50,.52,.52),lambda p,i,side=side:self.limb_weights(side,'arm',p),5)
            leg=[(.085,s*.098,.003,.040,.046,.044),(.108,s*.098,.003,.040,.047,.045),(.20,s*.098,0,.045,.050,.049),(.34,s*.098,-.003,.053,.056,.054),(.48,s*.096,.007,.051,.053,.051),(.55,s*.095,.010,.054,.058,.055),(.67,s*.092,.004,.071,.075,.073),(.80,s*.087,0,.080,.088,.091),(.89,s*.082,0,.082,.095,.104),(.967,s*.078,0,.080,.097,.110)]
            pants_fields.append(self.section_field(leg))
            # Outer seam travels through both joints and is weighted with
            # the actual trouser surface; no rigid stick on a moving leg.
            path=[]
            for row in leg:
                y,cx,cz,w,fd,bd=row;path.append((cx+s*w*1.004,y,cz))
            self.tube(4,path,.0008,(.58,.60,.61),lambda p,i,side=side:self.limb_weights(side,'leg',p),5)
        def jacket_weights(p):
            side='L' if p[0]>0 else 'R';point=np.array(p)
            # Bone ownership follows the actual torso/arm surfaces. A simple
            # X threshold wrongly binds wide waist points to the forearm.
            delta=float(torso_field(point)-jacket_arm_fields[side](point))
            amount=smooth(-.060,.060,delta)
            return self.weight_mix(self.trunk_weights(p),self.limb_weights(side,'arm',p),amount)
        def pants_weights(p):
            # Only the upper medial groin blends into the pelvis. Extending
            # a crotch X-mask down the whole leg incorrectly anchors the
            # inner shin to the hip when sitting/cycling.
            medial_pelvis=smooth(.75,.91,p[1])*(1-smooth(.015,.110,abs(p[0])))
            center_seam=smooth(.74,.83,p[1])*(1-smooth(.015,.095,abs(p[0])))
            medial_pelvis=1-(1-medial_pelvis)*(1-center_seam)
            return self.weight_mix(self.weight('Bip01 Pelvis'),self.limb_weights('L' if p[0]>0 else 'R','leg',p),1-medial_pelvis)
        self.implicit(0,[(-.302,.302),(.867,1.436),(-.127,.128)],jacket_fields,(1,1,1),jacket_weights,.024,.014,notch=self.armpit_notch(torso,arm))
        self.implicit(4,[(-.173,.173),(.084,.986),(-.128,.122)],pants_fields,(1,1,1),pants_weights,.020,.014,notch=self.crotch_notch)
        # Welt waistband and front fly define garment construction without a
        # disconnected pelvis block. Upper hem folds follow the torso skin.
        self.rings(4,[(.957,0,-.003,.156,.106,.112),(.964,0,-.003,.157,.107,.113),(.978,0,-.003,.153,.104,.109),(.985,0,-.003,.150,.102,.107)],52,self.trunk_weights,(.78,.80,.80),cap=False)
        self.tube(4,[(.009,.970,.106),(.011,.935,.111),(.006,.905,.104),(0,.889,.098)],.0012,(.58,.60,.60),lambda p,i:self.trunk_weights(p),6)
        # Center zip, two slanted welt pockets and low-key collar.
        path=[(0,y,z+.0018) for y,z in [(1.000,.105),(1.08,.106),(1.18,.112),(1.28,.111),(1.37,.098),(1.416,.061)]]
        self.tube(6,path,.0011,(.49,.51,.51),lambda p,i:self.trunk_weights(p),6)
        for s in [-1,1]:
            path=[(s*(.065+.045*k/15),1.045+.035*k/15,.095-.013*k/15) for k in range(16)]
            self.tube(0,path,.0014,(.47,.49,.50),lambda p,i:self.trunk_weights(p),6)
            collar=[[(s*.006,1.398,.082),(s*.048,1.426,.049)],[(s*.023,1.350,.105),(s*.075,1.385,.087)]]
            self.patch(0,collar,(.72,.74,.75),self.trunk_weights)
        # A small white crew-neck insert is visible between the own collar.
        self.patch(6,[[(x,1.405,.054) for x in [-.019,0,.019]],[(x,1.379,.077) for x in [-.014,0,.014]]],(.78,.78,.73),self.trunk_weights)
    def bathing_suit(self):
        # Exactly clip the own body topology at garment boundaries and move
        # covered polygons to opaque textile. There are no hidden body faces
        # beneath the suit that can poke through a smaller independent loft.
        # Both sides share the exact anatomy and native weights, including
        # the connected pelvis/crotch, during swimming and a deep hip hinge.
        source=self.meshes[1];skin=Mesh();cloth=self.meshes[0];cache=[{},{}]
        lower=.795 if self.female else .755;upper=1.285 if self.female else .982
        margins=self.swim_region_margin(np.array(source.v))
        planes=[(1,1.,-lower),(1,-1.,upper),(0,1.,.177),(0,-1.,.177),lambda vertex:vertex['body_margin']]
        def raw(index):return {'p':source.v[index],'uv':source.uv[index],'c':source.c[index],'weights':{b:w for b,w in zip(source.j[index],source.w[index]) if w>0},'body_margin':float(margins[index])}
        def interpolate(a,b,t):
            return {'p':mix(a['p'],b['p'],t),'uv':mix(a['uv'],b['uv'],t),'c':mix(a['c'],b['c'],t),'weights':self.weight_mix(a['weights'],b['weights'],t),'body_margin':a['body_margin']+(b['body_margin']-a['body_margin'])*t}
        def split(poly,plane):
            inside=[];outside=[]
            for a,b in zip(poly,poly[1:]+poly[:1]):
                if callable(plane):av=plane(a);bv=plane(b)
                else:
                    axis,sign,offset=plane;av=a['p'][axis]*sign+offset;bv=b['p'][axis]*sign+offset
                (inside if av>=0 else outside).append(a)
                if (av>=0)!=(bv>=0):
                    v=interpolate(a,b,av/(av-bv));inside.append(v);outside.append(v)
            return inside,outside
        def emit(poly,target,slot):
            if len(poly)<3:return
            indices=[]
            for v in poly:
                key=tuple(round(x,7) for x in (*v['p'],*v['uv']))
                if key not in cache[slot]:
                    index=len(target.v);cache[slot][key]=index;target.v.append(v['p']);target.uv.append(v['uv'])
                    target.c.append((1.,1.,1.,1.) if slot==1 else v['c'])
                    ordered=sorted(v['weights'].items(),key=lambda item:-item[1])[:4];total=sum(w for _,w in ordered)
                    target.j.append(tuple([b for b,_ in ordered]+[0]*(4-len(ordered))))
                    target.w.append(tuple([w/total for _,w in ordered]+[0.]*(4-len(ordered))))
                indices.append(cache[slot][key])
            for k in range(1,len(indices)-1):
                a,b,c=indices[0],indices[k],indices[k+1]
                if dot(cross(sub(target.v[b],target.v[a]),sub(target.v[c],target.v[a])),cross(sub(target.v[b],target.v[a]),sub(target.v[c],target.v[a])))>1e-20:target.tri(a,b,c)
        for k in range(0,len(source.i),3):
            poly=[raw(index) for index in source.i[k:k+3]]
            for plane in planes:
                if not poly:break
                poly,outside=split(poly,plane);emit(outside,skin,0)
            emit(poly,cloth,1)
        self.meshes[1]=skin
        # The own female garment is deliberately strapless. Its upper edge
        # is clipped from the actual torso, so no fixed-space shoulder strap
        # floats above different anatomical profiles or moving shoulders.

def png_texture(kind):
    rng=random.Random(170033+len(kind));n=256;im=Image.new('RGB',(n,n));pixels=[]
    for y in range(n):
        for x in range(n):
            if kind=='fabric':
                v=int(clamp(.80+.055*math.sin(x*math.pi)+.036*math.sin(y*math.pi)+rng.uniform(-.025,.025))*255);pixels.append((v,v,v))
            elif kind=='skin':
                # Neutral fine pores and low-frequency mottling are original
                # numerical texture, not a photograph or downloaded skin map.
                pore=max(0,math.sin(x*2.13+y*.47)*math.sin(y*1.91-x*.31))**12
                v=int(clamp(.955+rng.uniform(-.013,.013)+.010*math.sin(x*.071+y*.043)-.036*pore)*255);pixels.append((v,v,v))
            else:
                # Subtle directional variation: broad high-contrast bands
                # read as a metal helmet at the actual third-person scale.
                v=int(clamp(.87+.025*math.sin(x*1.7+.5*math.sin(y*.09))+rng.uniform(-.014,.014))*255);pixels.append((v,v,v))
    im.putdata(pixels);buf=io.BytesIO();im.save(buf,format='PNG');return buf.getvalue()

class Glb:
    def __init__(self):self.data=bytearray();self.views=[];self.acc=[]
    def view(self,data,target=None):
        while len(self.data)%4:self.data.append(0)
        off=len(self.data);self.data.extend(data);v={'buffer':0,'byteOffset':off,'byteLength':len(data)}
        if target:v['target']=target
        self.views.append(v);return len(self.views)-1
    def accessor(self,values,fmt,ctype,kind,target=None,bounds=False):
        flat=[]
        for x in values:flat.extend(x if isinstance(x,(tuple,list)) else [x])
        view=self.view(struct.pack('<'+fmt*len(flat),*flat),target)
        item={'bufferView':view,'componentType':ctype,'count':len(values),'type':kind}
        if bounds:
            item['min']=[min(x[i] for x in values) for i in range(len(values[0]))];item['max']=[max(x[i] for x in values) for i in range(len(values[0]))]
        self.acc.append(item);return len(self.acc)-1
    def write(self,resident,path):
        native_normals=[mesh.normals() for mesh in resident.meshes]
        # Material boundaries may duplicate a vertex, but a real anatomical
        # join keeps both its native influences and its smooth shading normal.
        shared={};keys={}
        for surface in [0,1,3]:
            mesh=resident.meshes[surface]
            for vertex in set(mesh.i):
                influences=tuple(sorted((int(bone),round(float(weight),7)) for bone,weight in zip(mesh.j[vertex],mesh.w[vertex]) if weight>1e-8))
                key=(tuple(round(v,8) for v in mesh.v[vertex]),influences)
                keys[(surface,vertex)]=key
                shared[key]=add(shared.get(key,(0.,0.,0.)),native_normals[surface][vertex])
        for (surface,vertex),key in keys.items():native_normals[surface][vertex]=unit(shared[key])
        primitives=[]
        for material,mesh in enumerate(resident.meshes):
            if not mesh.i:continue
            attributes={
                'POSITION':self.accessor(mesh.v,'f',5126,'VEC3',34962,True),
                'NORMAL':self.accessor(native_normals[material],'f',5126,'VEC3',34962),
                'TEXCOORD_0':self.accessor(mesh.uv,'f',5126,'VEC2',34962),
                'COLOR_0':self.accessor(mesh.c,'f',5126,'VEC4',34962),
                'JOINTS_0':self.accessor(mesh.j,'H',5123,'VEC4',34962),
                'WEIGHTS_0':self.accessor(mesh.w,'f',5126,'VEC4',34962)}
            primitives.append({'attributes':attributes,'indices':self.accessor(mesh.i,'I',5125,'SCALAR',34963),'material':material,'mode':4})
        nodes=[{'name':'Sim2SeoulAuthoredResident','children':[1,2]}, {'name':'AuthoredWeightedSurface','mesh':0,'skin':0}, {'name':'AuthoredSkeleton','children':[3]}]
        for index,(name,parent,p) in enumerate(resident.bones):
            local=sub(p,resident.global_rest[parent]) if parent>=0 else p
            node={'name':name,'translation':list(local)};children=[3+i for i,(_,pr,_) in enumerate(resident.bones) if pr==index]
            if children:node['children']=children
            nodes.append(node)
        binds=[]
        for p in resident.global_rest:binds.append((1,0,0,0,0,1,0,0,0,0,1,0,-p[0],-p[1],-p[2],1))
        inverse=self.accessor(binds,'f',5126,'MAT4')
        textures=[];images=[]
        for kind in ['fabric','skin','hair','eye']:
            payload=png_texture(kind) if kind=='fabric' else portrait_materials.texture_png(kind,female=resident.female)
            images.append({'bufferView':self.view(payload),'mimeType':'image/png','name':'Authored_'+kind});textures.append({'sampler':0,'source':len(images)-1})
        jacket=(.11,.16,.21,1) if not resident.female else (.67,.62,.51,1)
        if resident.swim:jacket=(.12,.28,.36,1) if not resident.female else (.17,.25,.30,1)
        pants=(.29,.30,.29,1) if not resident.female else (.105,.12,.14,1)
        materials=[]
        for i,(name,color,tex,roughness) in enumerate([
            ('Resident_Jacket_or_Swimwear',jacket,0,.85),('Resident_Authored_Skin',(1,1,1,1),1,.62),('Resident_Hair_and_Eye_Detail',(1,1,1,1),2,.78),('Resident_Articulated_Hands',(1,1,1,1),1,.68),('Resident_Trousers',pants,0,.86),('Resident_Sneakers',(1,1,1,1),0,.75),('Resident_Garment_and_Eye_Accents',(1,1,1,1),1,.65),('Resident_Original_Eye',(1,1,1,1),3,.20)]):
            materials.append({'name':name,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':(*linear_color(color[:3]),color[3]),'baseColorTexture':{'index':tex},'metallicFactor':0,'roughnessFactor':roughness}})
        document={'asset':{'version':'2.0','generator':'Sim2Seoul original anatomical profile author v1; no input assets','copyright':'Copyright 2026 Sim2Seoul contributors; original project authored geometry, rig and textures'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':nodes,'meshes':[{'name':'SeoulResident_F01' if resident.female else 'SeoulResident_M01','primitives':primitives}],'skins':[{'name':'Original_52_Bone_Anatomy','inverseBindMatrices':inverse,'joints':[3+i for i in range(len(resident.bones))],'skeleton':3}],'materials':materials,'textures':textures,'images':images,'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'buffers':[{'byteLength':len(self.data)}],'bufferViews':self.views,'accessors':self.acc}
        raw=json.dumps(document,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);self.data+=b'\0'*((-len(self.data))%4)
        payload=struct.pack('<III',0x46546c67,2,12+8+len(raw)+8+len(self.data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(self.data),0x004e4942)+self.data
        path.write_bytes(payload)
        verts=[v for m in resident.meshes for v in m.v]
        torso=[]
        for mesh in resident.meshes:
            for p,j,w in zip(mesh.v,mesh.j,mesh.w):
                influence=sum(amount for bone,amount in zip(j,w) if resident.bones[bone][0] in ['Bip01 Pelvis','Bip01 Spine','Bip01 Spine1','Bip01 Spine2'])
                if influence>.5:torso.append(p)
        slices={}
        for name,lo,hi in [('waist',1.03,1.12),('hips',.90,.98),('chest',1.25,1.35)]:
            points=[p for p in torso if lo<=p[1]<=hi]
            slices[name]={'height_band_m':[lo,hi],'width_m':max(p[0] for p in points)-min(p[0] for p in points),'depth_m':max(p[2] for p in points)-min(p[2] for p in points),'vertex_count':len(points),'torso_bone_weight_threshold':.5}
        return {'path':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(payload).hexdigest(),'vertices':len(verts),'triangles':sum(len(m.i)//3 for m in resident.meshes),'bone_count':len(resident.bones),'bone_names':[b[0] for b in resident.bones],'neutral_rest_skinned_height_m':max(v[1] for v in verts)-min(v[1] for v in verts),'runtime_normalized_street_height_m':1.70,'bounds_m':{'min':[min(v[a] for v in verts) for a in range(3)],'max':[max(v[a] for v in verts) for a in range(3)]},'body_profile':resident.profile,'authored_torso_measurements':slices,'capsule_comparison':{'reference_radius_m':.30,'maximum_neutral_full_surface_radius_m':max(math.hypot(p[0],p[2]) for p in verts),'maximum_neutral_torso_surface_radius_m':max(math.hypot(p[0],p[2]) for p in torso),'scope':'Presentation-only rest surface comparison. Existing physical capsule and motion are unchanged.'},'surface_semantics':[materials[i]['name'] for i,m in enumerate(resident.meshes) if m.i],'model_id':'SeoulResident_F01' if resident.female else 'SeoulResident_M01','variant':'swimwear' if resident.swim else 'street','source_assets_read':[]}

def main(residents=None):
    OUT.mkdir(parents=True,exist_ok=True);results=[]
    for profile in BODY_PROFILES:
        for female in [False,True]:
            for swim in [False,True]:
                person=(residents or {}).get((profile,female,swim)) or Resident(female,swim,profile).build();name=('seoul_resident_f01' if female else 'seoul_resident_m01')+('' if profile=='standard' else '_'+profile)+('_swim' if swim else '_street')+'.glb'
                result=Glb().write(person,OUT/name);results.append(result);print(json.dumps(result),flush=True)
    manifest={'generator':'tools/authored_character/build_seoul_resident.py','generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'design':'Project-authored resident with continuous anatomical surface fields, shared wrist/ankle boundary attributes, shape-preserving cubic sections, articulated five-finger hands, street clothes and same-anatomy swimwear','provenance':'No external body, geometry, textures, scan or animation is loaded or adapted. All source values and topology are authored in the project generator.','coordinates':'+Y up; face +Z; metres; local bone bases identity','hand_contract':{'rest_finger_longitudinal':[0,-1,0],'palm_front_normal':[0,0,1],'flexion_axis':[-1,0,0],'knuckle_contact_wrist_local_m':[0,-.078,.022],'wrist_to_middle_fingertip_m':.132,'palm_breadth_m':.068,'upper_arm_length_m':math.sqrt(.054**2+.287**2),'forearm_length_m':math.sqrt(.027**2+.249**2+.004**2),'names':'Bip01 L/R Finger0, Finger01, Finger02 thumb; Finger1/11/12 index; Finger2/21/22 middle; Finger3/31/32 ring; Finger4/41/42 little'},'files':results}
    manifest['portrait_identity']=identity_contract()
    manifest['portrait_materials']=portrait_materials.material_contract()
    manifest['portrait_modules']=[{'path':str(Path(__file__).with_name(name).relative_to(ROOT)),'sha256':hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()} for name in ['resident_identity_mesh.py','portrait_materials.py']]
    manifest['body_profiles']={'standard':'기본','soft':'통통','athletic':'근육'}
    manifest['body_profile_scope']='Project-authored game body volumes, not BMI classes, scanned persons or a measured Korean population distribution. All variants keep the same 52 rest bones and the 1.70m normalized game stature.'
    manifest['anatomical_surface_helper']={'path':'tools/authored_character/anatomical_surface_fields.py','sha256':hashlib.sha256(Path(__file__).with_name('anatomical_surface_fields.py').read_bytes()).hexdigest(),'method':'Pure numerical continuous anatomical field applied to original skin and garment vertices; skeletal attachment weights are retained with broad soft medial-pelvis support.'}
    manifest['surface_sampling']={'bare_body_distance_field_pitch_m':.010,'street_garment_distance_field_pitch_m':.014,'scope':'Surface extraction density is not a quality rating. Native unclothed torso and joint contours must be visually reviewed.'}
    manifest['measurement_method']='Actual emitted vertex bands with >0.5 summed Pelvis/Spine/Spine1/Spine2 native weight; includes the displayed garment/skin. Width and depth are original metre-space distances, not circumference or medical measurements.'
    (OUT/'AUTHORED_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output-dir',type=Path);parser.add_argument('--candidate-standard',action='store_true');args=parser.parse_args()
    if args.output_dir:OUT=args.output_dir.resolve()
    if args.candidate_standard:BODY_PROFILES=('standard',)
    main()

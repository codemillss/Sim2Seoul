"""Authored editable clay head/hands/feet for EXP35, Blender Z-up/front -Y.

This is an explicit control mesh: landmark rings, orbital edge loops and
branching finger loops are editable in the saved .blend. No former body,
SDF, scan, portrait paint, downloaded character or automatic retopology is
read. The construction is scripted cage modelling, not hand-brush sculpting.
"""
from __future__ import annotations
import math
import bpy
from mathutils import Vector


class Cage:
    def __init__(self, obj):
        self.obj=obj
        self.v=[tuple(v.co) for v in obj.data.vertices]
        self.f=[tuple(p.vertices) for p in obj.data.polygons]
        self.regions={}
    def vertex(self,p,region):
        n=len(self.v);self.v.append(tuple(p));self.regions.setdefault(region,[]).append(n);return n
    def ring(self,points,region):return [self.vertex(p,region) for p in points]
    def bridge(self,a,b):
        """Zipper preserves boundary IDs, including unequal loop transitions."""
        i=j=0;na=len(a);nb=len(b)
        while i<na or j<nb:
            ta=(i+1)/na if i<na else math.inf;tb=(j+1)/nb if j<nb else math.inf
            if abs(ta-tb)<1e-8:
                self.f.append((a[i%na],a[(i+1)%na],b[(j+1)%nb],b[j%nb]));i+=1;j+=1
            elif ta<tb:
                self.f.append((a[i%na],a[(i+1)%na],b[j%nb]));i+=1
            else:
                self.f.append((a[i%na],b[(j+1)%nb],b[j%nb]));j+=1
    def cap(self,ring,center,region):
        pole=self.vertex(center,region)
        for a,b in zip(ring,ring[1:]+ring[:1]):self.f.append((a,b,pole))
    def finish(self):
        mesh=bpy.data.meshes.new('ResidentStudy_AuthoredControlCage')
        mesh.from_pydata(self.v,[],self.f);mesh.update();old=self.obj.data;self.obj.data=mesh
        for p in mesh.polygons:p.use_smooth=True
        if old.users==0:bpy.data.meshes.remove(old)
        return self.regions


def _boundary(info,key):return info['boundaries'][key]
def _sort_theta(cage,indices,center):
    # Front=-Y, theta0 +X. Keep body boundaries in their actual positions.
    return sorted(indices,key=lambda i:math.atan2(cage.v[i][1]-center[1],cage.v[i][0]-center[0]))


def _align(cage,a,b):
    """Choose correspondence from real boundary positions, not guessed order."""
    best=None
    for reverse in (False,True):
        base=list(reversed(a)) if reverse else list(a)
        for shift in range(len(base)):
            ring=base[shift:]+base[:shift]
            distance=sum((Vector(cage.v[v])-Vector(cage.v[b[round(i*len(b)/len(a))%len(b)]])).length_squared for i,v in enumerate(ring))
            if best is None or distance<best[0]:best=(distance,ring)
    return best[1]


def build_head(cage,info):
    """Cranial silhouette, jaw planes and actual open orbits, no face paint."""
    region='head'
    # z / halfwidth / front depth / back depth / chin-nose sculpt at centre.
    # Deliberately low-resolution editable planes; Subdivision refines these.
    rows=[(1.558,.027,.062,.041,.006),(1.569,.040,.068,.049,.009),
          (1.582,.051,.070,.059,.004),(1.591,.056,.073,.064,.004),
          (1.598,.059,.074,.067,.005),(1.605,.062,.073,.069,.002),
          (1.615,.066,.074,.073,.018),(1.625,.071,.077,.078,.042),
          (1.637,.073,.077,.081,.030),(1.650,.074,.076,.083,.014),
          (1.660,.074,.075,.084,.010),(1.671,.073,.076,.085,.008),
          (1.682,.072,.080,.085,.006),(1.696,.071,.081,.084,.003),
          (1.718,.069,.080,.080,0.),(1.742,.061,.070,.071,0.),
          (1.764,.045,.052,.052,0.),(1.777,.022,.025,.026,0.)]
    count=48;grid=[]
    # Head centre +Y is posterior; its front plane is landmark shaped.
    for k,(z,w,fd,bd,nose) in enumerate(rows):
        points=[]
        for j in range(count):
            a=-math.pi+math.tau*j/count;s=math.sin(a);co=math.cos(a)
            x=w*s;y=.006-(fd if co>=0 else bd)*co
            aa=abs(a)
            if co>0:
                # These are named cage-column offsets, not a noise/depth field.
                nose_profile=max(0.,1-aa/.37)
                y-=nose*nose_profile
                if k in (8,9,10,11):
                    # Supraorbital/zygomatic wall and inset medial eye plane.
                    if .26<aa<.79:y+=.004 if k in (9,10) else .001
                    if .65<aa<1.10:y-=.004 if k in (8,9) else .001
                if k in (3,4):
                    y-=.0035*max(0.,1-aa/.40)
                # Distinct gonial jaw angle, cheek and temporal silhouette.
                if k<4 and .8<aa<1.9:x*=1.045
            zz=z
            if k==0:
                zz+=.036*(1-co)*.5
            if k in (7,8,9,10,11,12) and 1.30<aa<1.95:
                # Connected auricle folds, authored into temporal control rows.
                ear=[.001,.006,.010,.009,.006,.002][k-7]
                x+=math.copysign(ear,a)
                if k in (9,10) and 1.48<aa<1.75:x-=math.copysign(.005,a)
            points.append((x,y,zz))
        grid.append(cage.ring(points,region))
    # Orbit bounds are exact cage indices: theta15..45 degrees, z1.650..1.682.
    def is_hole(k,j):
        a=-math.pi+math.tau*(j+.5)/count
        return 9<=k<12 and math.radians(15)<abs(a)<math.radians(45)
    for k,(a,b) in enumerate(zip(grid,grid[1:])):
        for j in range(count):
            if not is_hole(k,j):cage.f.append((a[j],a[(j+1)%count],b[(j+1)%count],b[j]))
    # Front centre is index24. Right/left orbital rectangles are sewn to lids.
    for side in (-1,1):
        ja=26 if side>0 else 18;jb=30 if side>0 else 22
        ka,kb=9,12
        boundary=(grid[ka][ja:jb]+[grid[k][jb] for k in range(ka,kb)]
                  +list(reversed(grid[kb][ja+1:jb+1]))+[grid[k][ja] for k in range(kb,ka,-1)])
        cx=side*.032;cy=-.0595;cz=1.665
        # Map rectangular perimeter to its eye-shaped angular loop by actual
        # radial position. Two concentric fleshy rims preserve lid thickness.
        angles=[math.atan2((cage.v[i][2]-cz)/.012,(cage.v[i][0]-cx)/.018) for i in boundary]
        previous=boundary
        for stage in range(3):
            u=(stage+1)/3;points=[]
            for vid,a in zip(boundary,angles):
                px=cx+.0150*math.cos(a);pz=cz+(.0045 if math.sin(a)>=0 else .0034)*math.sin(a)+side*(px-cx)*.075
                dx=(px-cx)/.0162;dz=(pz-cz)/.0125
                py=cy-.0128*math.sqrt(max(.035,1-dx*dx-dz*dz))-.00065
                outer=Vector(cage.v[vid]);target=Vector((px,py,pz))
                q=outer.lerp(target,u)
                if stage==1:q.y-=.00065
                points.append(q)
            rim=cage.ring(points,region);cage.bridge(previous,rim);previous=rim
        cavity=cage.ring([(cx+(cage.v[i][0]-cx)*.82,cy+.019,cz+(cage.v[i][2]-cz)*1.35) for i in previous],region)
        cage.bridge(previous,cavity);cage.cap(cavity,(cx,cy+.024,cz),region)
        _ellipsoid(cage,(cx,cy,cz),(.0162,.0128,.0125),region,32,16)
    # Neck and jaw are one cage, including the low anterior chin and high nape.
    n=_boundary(info,'neck');neck=_sort_theta(cage,n['indices'],n['center'])
    # grid theta uses x=sin, y=-cos; shift order to body's +X polar convention.
    jaw=sorted(grid[0],key=lambda i:math.atan2(cage.v[i][1]-.006,cage.v[i][0]))
    cage.bridge(_align(cage,neck,jaw),jaw)
    cage.cap(grid[-1],(0,.006,1.780),region)
    info['head_landmarks']={'top':[0,.006,1.780],'chin':[0,-.062,1.558],
                            'left_eye':[.032,-.0595,1.665],'right_eye':[-.032,-.0595,1.665]}


def _ellipsoid(cage,center,radii,region,segments=16,rings=8):
    previous=None
    for k in range(1,rings):
        p=math.pi*k/rings
        ring=cage.ring([(center[0]+radii[0]*math.sin(p)*math.cos(math.tau*j/segments),
                         center[1]+radii[1]*math.sin(p)*math.sin(math.tau*j/segments),
                         center[2]+radii[2]*math.cos(p)) for j in range(segments)],region)
        if previous is None:cage.cap(ring,(center[0],center[1],center[2]+radii[2]),region)
        else:cage.bridge(previous,ring)
        previous=ring
    cage.cap(previous,(center[0],center[1],center[2]-radii[2]),region)


def build_hand(cage,info,side):
    label='L' if side>0 else 'R';region='hand.'+label
    boundary=_boundary(info,'wrist.'+label);origin=Vector(boundary['center'])
    axis=Vector((side*.411,-.047,-.910)).normalized()
    across=Vector((side*.910,0,.411)).normalized();normal=axis.cross(across).normalized()
    if normal.y>0:normal=-normal
    def xyz(t,x,d):return origin+axis*t+across*x+normal*d
    # Front/back rows produce a broad metacarpal surface, not a tube mitten.
    xs=[-.032+i*.008 for i in range(9)]
    rings=[]
    for t,width,depth in [(0.012,.73,.013),(.040,.99,.013),(.072,1.00,.010),(.089,.96,.008)]:
        points=[xyz(t,x*width,depth*(1-.15*(x/.032)**2)) for x in xs]
        points+=[xyz(t,x*width,-depth*.80) for x in reversed(xs)]
        rings.append(cage.ring(points,region))
    # Match polar boundary rotation to the palm's actual first point.
    wrist=_align(cage,list(boundary['indices']),rings[0]);cage.bridge(wrist,rings[0])
    for k,(a,b) in enumerate(zip(rings,rings[1:])):
        for j in range(18):
            if j==17 and k in (0,1):continue  # Connected thenar thumb opening.
            cage.f.append((a[j],a[(j+1)%18],b[(j+1)%18],b[j]))
    distal=rings[-1]
    # Four finger roots share web edges, so the surface branches at the palm.
    lengths=[.069,.081,.075,.058]
    for f,length in enumerate(lengths):
        a=2*f;b=a+2;root=distal[a:b+1]+[distal[17-j] for j in range(b,a-1,-1)]
        center_x=(xs[a]+xs[b])*.5*.96;previous=root
        for t,fraction,width in [(.014,.20,.0074),(.038,.50,.0068),(length-.012,.80,.0057),(length,.98,.0034)]:
            if t>length:t=length*.86
            points=[]
            for j in range(6):
                angle=math.tau*j/6;xx=center_x+width*math.cos(angle)
                # Mild relaxed PIP/DIP flexion and separate fingertip pads.
                dd=.0062*math.sin(angle)-.010*fraction*fraction
                points.append(xyz(.089+t,xx,dd))
            ring=cage.ring(points,region);cage.bridge(_align(cage,previous,ring) if t==.014 else previous,ring);previous=ring
        cage.cap(previous,xyz(.089+length+.003,center_x,-.011),region)
    # Thumb root is a real hole on the medial palm side.
    root=[rings[0][17],rings[0][0],rings[1][0],rings[2][0],rings[2][17],rings[1][17]]
    previous=root
    for t,x,rad,deep in [(.039,-.041,.012,.000),(.059,-.057,.010,.003),(.082,-.066,.008,.005),(.096,-.067,.005,.007)]:
        points=[xyz(t+rad*.55*math.sin(math.tau*j/6),x+rad*math.cos(math.tau*j/6),deep+.010*math.sin(math.tau*j/6)) for j in range(6)]
        ring=cage.ring(points,region);cage.bridge(_align(cage,previous,ring) if t==.039 else previous,ring);previous=ring
    cage.cap(previous,xyz(.101,-.067,.007),region)


def build_foot(cage,info,side):
    label='L' if side>0 else 'R';region='foot.'+label
    boundary=_boundary(info,'ankle.'+label);center=Vector(boundary['center'])
    ankle=_sort_theta(cage,boundary['indices'],boundary['center']);previous=ankle
    for z,cy,width,front,back in [(.084,-.008,.035,.070,.052),(.060,-.030,.045,.126,.065),
                                 (.034,-.052,.050,.153,.065),(.012,-.052,.049,.152,.064),(.006,-.052,.047,.149,.061)]:
        points=[]
        for j in range(12):
            a=-math.pi+math.tau*j/12;sy=math.sin(a);cx=math.cos(a)
            y=cy+(back if sy>=0 else front)*sy
            # Forefoot is broader than heel; medial arch narrows at mid-foot.
            ww=width*(.80 if y>.005 else (1. if y<-.10 else .83))
            zz=z
            if z in (.012,.006) and side*cx<-.2 and -.10<y<-.01:zz+=.010
            points.append((center.x+ww*cx,y,zz))
        ring=cage.ring(points,region);cage.bridge(previous,ring);previous=ring
    cage.cap(previous,(center.x,-.052,.006),region)


def extend_anatomy(obj,info):
    """Append connected editable parts. Body IDs stay valid for rig weights."""
    cage=Cage(obj)
    build_head(cage,info)
    for side in (-1,1):build_hand(cage,info,side);build_foot(cage,info,side)
    info.setdefault('vertex_regions',{}).update(cage.finish())
    info['additional_authorship']='New explicit head/orbit, palm/finger branching and foot control cages. No imported body or image input.'
    return obj,info

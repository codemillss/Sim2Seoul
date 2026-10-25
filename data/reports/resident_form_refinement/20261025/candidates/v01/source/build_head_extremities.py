"""Authored editable clay head/hands/feet, EXP36, Blender Z-up/front -Y.

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
    rows=[(1.558,.030,.065,.041,.004),(1.569,.044,.073,.049,.005),
          (1.582,.054,.073,.059,.001),(1.591,.058,.071,.064,.001),
          (1.598,.061,.073,.067,.002),(1.605,.064,.073,.069,.001),
          (1.615,.068,.074,.073,.013),(1.625,.073,.075,.078,.028),
          (1.637,.075,.075,.081,.022),(1.650,.075,.074,.083,.014),
          (1.660,.074,.073,.084,.012),(1.671,.073,.076,.085,.010),
          (1.682,.072,.082,.085,.007),(1.696,.071,.082,.084,.002),
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
                nose_profile=max(0.,1-(aa/.39)**2)**2
                y-=nose*nose_profile
                # Broad cheek/zygomatic plane, separate from the central
                # muzzle: keep the eye-to-jaw transition out of a sphere.
                cheek=max(0.,1-abs(z-1.635)/.040)
                y-=.0055*cheek*max(0.,1-abs(aa-.64)/.42)
                if 1.587<=z<=1.607:
                    # Upper/lower lip volume around an actual recessed seam.
                    lip=max(0.,1-aa/.34)**2
                    y-=({3:.002,4:.0045,5:.001}.get(k,0))*lip
                    if k==3:y+=.0025*max(0.,1-aa/.32)
                if k in (8,9,10,11):
                    # Supraorbital/zygomatic wall and inset medial eye plane.
                    if .26<aa<.79:y+=.006 if k in (9,10) else .001
                    if .65<aa<1.10:y-=.006 if k in (8,9) else .002
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
        cx=side*.032;cy=-.0625;cz=1.665
        # Map rectangular perimeter to its eye-shaped angular loop by actual
        # radial position. Two concentric fleshy rims preserve lid thickness.
        angles=[math.atan2((cage.v[i][2]-cz)/.012,(cage.v[i][0]-cx)/.018) for i in boundary]
        previous=boundary
        for stage in range(3):
            u=(stage+1)/3;points=[]
            for vid,a in zip(boundary,angles):
                px=cx+.0144*math.cos(a);pz=cz+(.0053 if math.sin(a)>=0 else .0037)*math.sin(a)+side*(px-cx)*.045
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
                            'left_eye':[.032,-.0625,1.665],'right_eye':[-.032,-.0625,1.665]}


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
    xs=[-.038+i*.0095 for i in range(9)]
    def knuckle_t(x):return .089+.006*max(0.,1-abs(x+.006)/.035)-.007*max(0.,x/.038)
    rings=[]
    for t,width,depth in [(0.012,.65,.014),(.040,.93,.017),(.072,1.00,.014),(.089,.97,.011)]:
        def surface(x,palm):
            tx=knuckle_t(x) if t==.089 else t
            thenar=max(0.,1-abs(x+.025)/.025)*max(0.,1-abs(t-.044)/.040)
            transverse=max(0.,1-(x/.045)**2)
            d=depth*(.82+.18*transverse)+.004*thenar
            if not palm:d=-depth*(.65+.15*transverse)-.002*max(0.,1-abs(t-.072)/.030)
            return xyz(tx,x*width,d)
        points=[surface(x,True) for x in xs]
        points+=[surface(x,False) for x in reversed(xs)]
        rings.append(cage.ring(points,region))
    # Match polar boundary rotation to the palm's actual first point.
    wrist=_align(cage,list(boundary['indices']),rings[0]);cage.bridge(wrist,rings[0])
    for k,(a,b) in enumerate(zip(rings,rings[1:])):
        for j in range(18):
            if j==17 and k in (0,1):continue  # Connected thenar thumb opening.
            cage.f.append((a[j],a[(j+1)%18],b[(j+1)%18],b[j]))
    distal=rings[-1]
    # Four finger roots share web edges, so the surface branches at the palm.
    lengths=[.071,.082,.076,.058]
    for f,length in enumerate(lengths):
        a=2*f;b=a+2;root=distal[a:b+1]+[distal[17-j] for j in range(b,a-1,-1)]
        center_x=(xs[a]+xs[b])*.5*.97;previous=root;base=knuckle_t(center_x/.97)
        for t,fraction,width in [(.012,.16,.0082),(.030,.40,.0074),(.038,.50,.0078),(length-.014,.80,.0060),(length,.98,.0038)]:
            if t>length:t=length*.86
            points=[]
            for j in range(6):
                angle=math.tau*j/6;xx=center_x+width*math.cos(angle)
                # Mild relaxed PIP/DIP flexion and separate fingertip pads.
                dd=.0075*math.sin(angle)+.002-.013*fraction*fraction
                xx+=(f-1.5)*.0018*fraction
                points.append(xyz(base+t,xx,dd))
            ring=cage.ring(points,region);cage.bridge(_align(cage,previous,ring) if t==.012 else previous,ring);previous=ring
        cage.cap(previous,xyz(base+length+.003,center_x+(f-1.5)*.0018,-.011),region)
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
    # A dorsal/plantar patch replaces the old closed shoe-shaped radial cap.
    # The ankle enters a real dorsal opening; five toe roots branch from the
    # distal grid, sharing web edges. All pads remain one closed control cage.
    xs=[-.047,-.035,-.023,-.013,-.003,.006,.015,.023,.031,.038,.045]
    rows=[(.054,.55,.028),(.033,.68,.048),(.011,.74,.062),
          (-.013,.78,.071),(-.039,.83,.066),(-.076,.92,.050),
          (-.111,1.,.039),(-.145,1.,.027)]
    top=[];bottom=[]
    for y,width,height in rows:
        upper=[];lower=[]
        for x in xs:
            transverse=max(0.,1-(x/.055)**2)
            # A high medial instep and a low lateral support border are
            # deliberately asymmetric; mirror the local foot for R.
            arch=max(0.,1-abs(y+.046)/.075)*max(0.,1-abs(x+.025)/.028)
            z=.012+(height-.012)*(.65+.35*transverse)+.008*arch
            upper.append(cage.vertex((center.x+side*x*width,y,z),region))
            lower.append(cage.vertex((center.x+side*x*width,y,.006+.014*arch),region))
        top.append(upper);bottom.append(lower)
    for k in range(len(rows)-1):
        for j in range(10):
            if not (1<=k<4 and 2<=j<8):
                cage.f.append((top[k][j],top[k][j+1],top[k+1][j+1],top[k+1][j]))
            cage.f.append((bottom[k][j+1],bottom[k][j],bottom[k+1][j],bottom[k+1][j+1]))
        for j in (0,10):
            cage.f.append((top[k][j],top[k+1][j],bottom[k+1][j],bottom[k][j]))
    for j in range(10):
        cage.f.append((top[0][j+1],top[0][j],bottom[0][j],bottom[0][j+1]))
    ka,kb,ja,jb=1,4,2,8
    opening=(top[ka][ja:jb]+[top[k][jb] for k in range(ka,kb)]
             +list(reversed(top[kb][ja+1:jb+1]))+[top[k][ja] for k in range(kb,ka,-1)])
    ankle=_sort_theta(cage,boundary['indices'],boundary['center'])
    cage.bridge(_align(cage,ankle,opening),opening)
    lengths=[.050,.053,.045,.037,.029]
    for toe,length in enumerate(lengths):
        a=2*toe;b=a+2
        root=top[-1][a:b+1]+[bottom[-1][j] for j in range(b,a-1,-1)]
        xc=(xs[a]+xs[b])*.5;radius=(xs[b]-xs[a])*.5*.93;previous=root
        for fraction,wide,high in [(.18,1.,.010),(.50,.94,.0105),(.78,.85,.009),(.96,.55,.006)]:
            points=[]
            for j in range(8):
                angle=math.tau*j/8
                x=xc+radius*wide*math.cos(angle)
                y=-.145-length*fraction
                z=.0165+high*math.sin(angle)+.002*math.sin(math.pi*fraction)
                points.append((center.x+side*x,y,z))
            ring=cage.ring(points,region)
            cage.bridge(_align(cage,previous,ring) if fraction==.18 else previous,ring);previous=ring
        cage.cap(previous,(center.x+side*xc,-.145-length,.0165),region)
    info.setdefault('foot_construction',{})[label]={'method':'Dorsal/plantar grid, connected ankle aperture, medial arch, five connected individual toe loops.','toe_lengths_m':lengths,'input_assets':[]}


def extend_anatomy(obj,info):
    """Append connected editable parts. Body IDs stay valid for rig weights."""
    cage=Cage(obj)
    build_head(cage,info)
    for side in (-1,1):build_hand(cage,info,side);build_foot(cage,info,side)
    info.setdefault('vertex_regions',{}).update(cage.finish())
    info['additional_authorship']='EXP36 revised facial planes, cupped metacarpal/palm surface, knuckle/finger transitions and five-toe dorsal/plantar foot cage. No imported body or image input.'
    info['extremity_reference_urls']=['https://openstax.org/books/anatomy-and-physiology-2e/pages/8-2-bones-of-the-upper-limb','https://openstax.org/books/anatomy-and-physiology-2e/pages/8-4-bones-of-the-lower-limb']
    return obj,info

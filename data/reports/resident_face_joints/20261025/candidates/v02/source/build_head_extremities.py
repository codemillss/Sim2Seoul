"""Authored editable clay head/hands/feet, EXP37, Blender Z-up/front -Y.

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


def _rect_boundary(grid,ka,kb,ja,jb):
    return (grid[ka][ja:jb]+[grid[k][jb] for k in range(ka,kb)]
            +list(reversed(grid[kb][ja+1:jb+1]))+[grid[k][ja] for k in range(kb,ka,-1)])


def _eye_globe(cage,center,region):
    """Closed ocular surface with an inset pupil/iris relief, no image paint."""
    cx,cy,cz=center;rx,ry,rz=.0160,.0126,.0122
    previous=None
    angles=[.08,.15,.20,.32,.37,.46,.63,.82,1.04,1.29,1.57,1.85,2.14,2.43,2.70,2.94,3.06]
    for p in angles:
        inset=.0015 if p<=.15 else (.0003 if p==.20 else (-.00025 if p in (.32,.37) else 0.))
        ring=cage.ring([(cx+rx*math.sin(p)*math.cos(math.tau*j/40),
                          cy-ry*math.cos(p)+inset,
                          cz+rz*math.sin(p)*math.sin(math.tau*j/40)) for j in range(40)],region)
        if previous is None:cage.cap(ring,(cx,cy-ry+.0018,cz),region)
        else:cage.bridge(previous,ring)
        previous=ring
    cage.cap(previous,(cx,cy+ry,cz),region)


def build_head(cage,info):
    """EXP37 connected facial apertures and auricular folds, original cage."""
    region='head'
    # Named height / halfwidth / front depth / back depth / nasal projection.
    # These are authored art landmarks, not a scan or population measurements.
    rows=[('chin',1.558,.029,.066,.043,0.),
          ('chin_plane',1.567,.041,.074,.050,0.),
          ('jaw',1.578,.052,.075,.058,0.),
          ('lower_lip_wall',1.587,.058,.071,.063,0.),
          ('oral_low',1.591,.060,.071,.066,0.),
          ('oral_middle',1.598,.062,.073,.068,0.),
          ('oral_high',1.607,.064,.072,.071,0.),
          ('philtrum',1.613,.067,.073,.074,.004),
          ('nasal_base',1.618,.069,.074,.077,.012),
          ('alar_middle',1.623,.071,.074,.079,.024),
          ('alar_high',1.629,.073,.075,.081,.029),
          ('nasal_tip',1.635,.075,.075,.082,.026),
          ('malar',1.643,.076,.075,.084,.020),
          ('orbit_low',1.651,.076,.074,.085,.014),
          ('orbit_lower_mid',1.658,.075,.074,.086,.010),
          ('eye_mid',1.665,.074,.075,.086,.007),
          ('orbit_upper_mid',1.674,.073,.079,.086,.003),
          ('orbit_high',1.683,.073,.084,.086,0.),
          ('brow',1.690,.073,.085,.085,0.),
          ('forehead',1.707,.072,.084,.084,0.),
          ('vault',1.726,.067,.078,.079,0.),
          ('crown_low',1.746,.059,.067,.069,0.),
          ('crown',1.765,.043,.050,.052,0.),
          ('pole',1.777,.021,.024,.026,0.)]
    count=96;grid=[];index={row[0]:k for k,row in enumerate(rows)}
    for name,z,width,front,back,nose in rows:
        points=[]
        for j in range(count):
            a=-math.pi+math.tau*j/count;si,co=math.sin(a),math.cos(a)
            x=width*si;y=.006-(front if co>=0 else back)*co;zz=z
            if co>0:
                bridge_width=.010 if z>=1.643 else .019
                nasal=max(0.,1-(x/bridge_width)**2)**2
                y-=nose*nasal
                # Zygomatic support below the orbit; a flatter central
                # maxillary plane and shallow submalar hollow beside it.
                malar=max(0.,1-abs(z-1.645)/.030)*max(0.,1-abs(abs(x)-.046)/.026)
                y-=.006*malar
                hollow=max(0.,1-abs(z-1.612)/.025)*max(0.,1-abs(abs(x)-.046)/.024)
                y+=.0025*hollow
                if 1.651<=z<=1.674:
                    y+=.004*max(0.,1-abs(abs(x)-.032)/.020)
                if 1.683<=z<=1.707:
                    y-=.0025*max(0.,1-abs(abs(x)-.033)/.025)
                if 1.613<=z<=1.629:
                    alar=max(0.,1-abs(abs(x)-.013)/.009)*max(0.,1-abs(z-1.623)/.011)
                    y-=.0045*alar
                if 1.591<=z<=1.613:
                    # Philtral columns are a subtle pair of planes; the
                    # vermilion itself is constructed at the aperture below.
                    y-=.0013*max(0.,1-abs(abs(x)-.0045)/.0035)
                if z<=1.587 and .70<abs(a)<1.90:x*=1.035
            if name=='chin':zz+=.036*(1-co)*.5
            points.append((x,y,zz))
        grid.append(cage.ring(points,region))
    cuts=[(index['orbit_low'],index['orbit_high'],52,60),
          (index['orbit_low'],index['orbit_high'],36,44),
          (index['oral_low'],index['oral_high'],42,54),
          (index['nasal_base'],index['alar_high'],49,52),
          (index['nasal_base'],index['alar_high'],44,47),
          (index['nasal_base'],index['orbit_high'],69,75),
          (index['nasal_base'],index['orbit_high'],21,27)]
    for k,(lo,hi) in enumerate(zip(grid,grid[1:])):
        for j in range(count):
            if not any(ka<=k<kb and ja<=j<jb for ka,kb,ja,jb in cuts):
                cage.f.append((lo[j],lo[(j+1)%count],hi[(j+1)%count],hi[j]))
    # Lids follow the ocular surface. Aperture corners are tapered and the
    # lower lid is shallower than the upper lid, rather than two round bumps.
    for side,cut in [(1,cuts[0]),(-1,cuts[1])]:
        boundary=_rect_boundary(grid,*cut);cx,cy,cz=side*.032,-.0505,1.666
        angles=[math.atan2((cage.v[v][2]-cz)/.012,(cage.v[v][0]-cx)/.018) for v in boundary]
        previous=boundary
        for stage in range(4):
            u=(stage+1)/4;points=[]
            for vid,a in zip(boundary,angles):
                px=cx+.0143*math.cos(a);si=math.sin(a)
                pz=cz+(.0049 if si>0 else .0032)*si+side*(px-cx)*.055
                dx=(px-cx)/.016;dz=(pz-cz)/.0122
                py=cy-.0126*math.sqrt(max(.035,1-dx*dx-dz*dz))-.00045
                q=Vector(cage.v[vid]).lerp(Vector((px,py,pz)),u)
                if stage==2:q.y-=.00055
                points.append(q)
            rim=cage.ring(points,region);cage.bridge(previous,rim);previous=rim
        cavity=cage.ring([(cx+(cage.v[v][0]-cx)*.85,cy+.017,cz+(cage.v[v][2]-cz)*1.25) for v in previous],region)
        cage.bridge(previous,cavity);cage.cap(cavity,(cx,cy+.021,cz),region)
        _eye_globe(cage,(cx,cy,cz),region)
    # Rolled upper/lower lip and narrow relaxed oral fissure. Curved mouth
    # corners turn into the face instead of projecting as a flat oval plate.
    boundary=_rect_boundary(grid,*cuts[2]);previous=boundary
    angles=[math.atan2((cage.v[v][2]-1.598)/.008,cage.v[v][0]/.027) for v in boundary]
    for stage in range(4):
        u=(stage+1)/4;points=[]
        for vid,a in zip(boundary,angles):
            x=.026*math.cos(a);si=math.sin(a);edge=abs(x)/.026
            cupid=.0006*max(0.,1-abs(abs(x)-.007)/.007) if si>0 else 0.
            z=1.598+(.00055 if si>0 else .00035)*si+cupid
            target=Vector((x,-.0725+.007*edge**2,z))
            q=Vector(cage.v[vid]).lerp(target,u)
            if stage in (1,2):q.y-=.0010*(1-edge**2)
            points.append(q)
        rim=cage.ring(points,region);cage.bridge(previous,rim);previous=rim
    inner=cage.ring([(cage.v[v][0]*.94,-.060,1.598+(cage.v[v][2]-1.598)*.65) for v in previous],region)
    cage.bridge(previous,inner);cage.cap(inner,(0,-.054,1.598),region)
    # Slanted nostril rims, each sewn to the alar base, with closed cavities.
    for side,cut in [(1,cuts[3]),(-1,cuts[4])]:
        boundary=_rect_boundary(grid,*cut);cx=side*.0115;previous=boundary
        angles=[math.atan2((cage.v[v][2]-1.622)/.005,(cage.v[v][0]-cx)/.006) for v in boundary]
        for stage in range(3):
            u=(stage+1)/3;points=[]
            for vid,a in zip(boundary,angles):
                target=Vector((cx+.0040*math.cos(a),-.083+.0026*math.sin(a),1.6225+.0024*math.sin(a)))
                q=Vector(cage.v[vid]).lerp(target,u)
                if stage==1:q.y-=.0004
                points.append(q)
            rim=cage.ring(points,region);cage.bridge(previous,rim);previous=rim
        inner=cage.ring([(cx+(cage.v[v][0]-cx)*.8,cage.v[v][1]+.006,cage.v[v][2]+.006) for v in previous],region)
        cage.bridge(previous,inner);cage.cap(inner,(cx,-.076,1.631),region)
    # A true auricular patch: attached root, helix, recessed scapha,
    # antihelix and concha. It replaces the old temporal-side lump.
    for side,cut in [(1,cuts[5]),(-1,cuts[6])]:
        boundary=_rect_boundary(grid,*cut);previous=boundary
        angles=[math.atan2((cage.v[v][2]-1.651)/.030,(cage.v[v][1]-.004)/.016) for v in boundary]
        # Round the sewn boundary itself. A rectangular temporal opening
        # otherwise leaves a slab visible around the curved auricle.
        for vid,a in zip(boundary,angles):
            z=1.651+.030*math.sin(a);y=.004+.016*math.cos(a)+.002*math.sin(a)
            k=min(range(len(rows)),key=lambda i:abs(rows[i][1]-z))
            width,depth=rows[k][2],rows[k][3] if y<.006 else rows[k][4]
            x=width*math.sqrt(max(.6,1-((y-.006)/depth)**2))
            cage.v[vid]=(side*x,y,z)
        for stage,(yr,zr,xdepth) in enumerate([(.015,.029,.074),(.014,.028,.082),(.012,.025,.079),(.0095,.021,.081),(.007,.016,.075)]):
            points=[]
            for a in angles:
                co,si=math.cos(a),math.sin(a)
                y=.004+yr*co+.003*si;z=1.651+zr*si
                # Lower lobule is full and smooth; the anterior concha has
                # a small tragal rise rather than a uniformly concentric ring.
                depth=xdepth+(.0012 if si<-.65 else 0.)-.0025*max(0.,si)
                if stage==3 and co<-.3:depth+=.0015
                target=Vector((side*depth,y,z))
                if stage==0:
                    target=Vector(cage.v[boundary[len(points)]]).lerp(target,.75)
                points.append(target)
            ring=cage.ring(points,region);cage.bridge(previous,ring);previous=ring
        inner=cage.ring([(side*.070,.004+(cage.v[v][1]-.004)*.65,1.651+(cage.v[v][2]-1.651)*.7) for v in previous],region)
        cage.bridge(previous,inner);cage.cap(inner,(side*.068,.004,1.651),region)
    neck_info=_boundary(info,'neck');neck=_sort_theta(cage,neck_info['indices'],neck_info['center'])
    jaw=sorted(grid[0],key=lambda v:math.atan2(cage.v[v][1]-.006,cage.v[v][0]))
    cage.bridge(_align(cage,neck,jaw),jaw);cage.cap(grid[-1],(0,.006,1.780),region)
    info['head_landmarks']={'top':[0,.006,1.780],'chin':[0,-.060,1.558],
                            'left_eye':[.032,-.0505,1.666],'right_eye':[-.032,-.0505,1.666]}
    info['face_construction']={'angular_columns':count,'named_height_rows':[r[0] for r in rows],
        'connected_apertures':['two lid rims','two slanted nostril cavities','relaxed oral fissure','two auricular root patches'],
        'eye_surface':'Closed neutral ocular surface with geometric iris/pupil relief; no paint or realistic optical claim.',
        'reference_urls':['https://openstax.org/books/anatomy-and-physiology-2e/pages/7-2-the-skull','https://elementsofmorphology.nih.gov/anatomy-ear.shtml'],
        'source_assets_read':[],'anatomical_or_art_acceptance':False}


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
    info['additional_authorship']='EXP37 connected eyelids, nasal apertures, rolled lips and auricular folds; EXP36 editable hands and feet retained. No imported body or image input.'
    info['extremity_reference_urls']=['https://openstax.org/books/anatomy-and-physiology-2e/pages/8-2-bones-of-the-upper-limb','https://openstax.org/books/anatomy-and-physiology-2e/pages/8-4-bones-of-the-lower-limb']
    return obj,info

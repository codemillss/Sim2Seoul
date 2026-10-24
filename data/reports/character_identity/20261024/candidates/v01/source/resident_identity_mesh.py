"""Original portrait topology and groom for Sim2Seoul EXP34.

The face is an indexed craniofacial cage with actual orbital apertures sewn
into eight-loop eyelids, curved eyeballs and a continuous nose/mouth/jaw.
All coordinates and groom paths below are project-authored. No image, scan,
mesh, morph or third-party character is read.
"""
from __future__ import annotations
import math
import portrait_materials as pigment

TAU=math.tau

def clamp(v,a=0.,b=1.):return max(a,min(b,v))
def smooth(a,b,v):
    t=clamp((v-a)/(b-a));return t*t*(3-2*t)
def g(v,c,s):return math.exp(-.5*((v-c)/s)**2)
def add(a,b):return tuple(x+y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def mul(a,b):return tuple(x*b for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a):return mul(a,1/max(1e-12,math.sqrt(dot(a,a))))
def lerp(a,b,t):return add(mul(a,1-t),mul(b,t))
def bezier(control,t):
    points=control
    while len(points)>1:points=[lerp(a,b,t) for a,b in zip(points,points[1:])]
    return points[0]

def unique(values):return sorted(set(round(x,9) for x in values))

class PortraitSculpt:
    """One identity in metre-space, independent from the body-volume preset."""
    def __init__(self,resident):
        self.r=resident;self.f=resident.female;self.mesh=resident.meshes[1]
        self.head=resident.weight('Bip01 Head');self.eye_y=1.573 if self.f else 1.572
        self.eye_x=.029 if self.f else .028
        self.rx=.016 if self.f else .015;self.ry=.011 if self.f else .0108;self.rz=.012 if self.f else .0115
        # Distinct mandibular arches, maxilla and cranial widths; section
        # curves form the cage only. Feature topology and tissue are below.
        rows=[(1.458,0,.014,.027,.043,.030),(1.470,0,.002,.039,.054,.038),
              (1.487,0,-.004,.057,.063,.047),(1.510,0,-.008,.064,.069,.061),
              (1.538,0,-.010,.069,.071,.073),(1.561,0,-.010,.068,.073,.077),
              (1.588,0,-.010,.067,.074,.078),(1.618,0,-.011,.065,.072,.077),
              (1.643,0,-.012,.060,.063,.070),(1.663,0,-.012,.049,.049,.055),
              (1.680,0,-.012,.029,.026,.030),(1.685,0,-.012,.005,.004,.005)]
        if self.f:
            rows=[(y,cx,cz,w*k,fd*df,bd) for (y,cx,cz,w,fd,bd),k,df in zip(rows,[.94,.91,.86,.93,.95,.95,.96,.97,.97,.98,1.,1.],[1.04,1.02,.98,.98,.99,1.,1.,1.,1.,1.,1.,1.])]
        self.sample=resident.section_sampler(rows)
        self.theta=unique([-math.pi+TAU*j/112 for j in range(113)]+[-.89,-.07,.07,.89]+[-1.+2*j/68 for j in range(69)]+[s*(1.22+.016*j) for s in (-1,1) for j in range(45)])
        self.theta[0]=-math.pi;self.theta[-1]=math.pi
        self.eye_lo=1.549;self.eye_hi=1.596
        self.eyes={}
        for side in (-1,1):
            cx=side*self.eye_x;z=self.front(cx,self.eye_y)+.003-self.rz
            self.eyes[side]=(cx,self.eye_y,z)
    def skin(self,p,feature='face',front=1.):
        return pigment.face_color(self.r.skin,p[0]/.069,(p[1]-1.458)/.184,female=self.f,feature=feature,front=front)
    def jaw_bottom(self,theta):
        # The chin is lower than the jaw angle and nape. A horizontal ring
        # at the chin would pull the neck into an artificial circular shelf.
        a=abs(theta)
        return 1.458+.029*smooth(.40,1.60,a)+.022*smooth(1.55,2.70,a)
    def feature_depth(self,x,y):
        female=self.f
        nose=(.008 if female else .0095)*g(x,0,.010)*g(y,1.556,.025)
        nose+=(.0175 if female else .0205)*g(x,0,.0108)*g(y,1.536,.0085)
        nose+=.0085*(g(x,-.0108,.0055)+g(x,.0108,.0055))*g(y,1.530,.0058)
        nose+=.005*g(x,0,.0040)*g(y,1.524,.0050)
        nose-=.0052*(g(x,-.0095,.0028)+g(x,.0095,.0028))*g(y,1.526,.0024)
        orbit=-.0042*(g(x,-self.eye_x,.016)+g(x,self.eye_x,.016))*g(y,self.eye_y,.012)
        brow=(.0023 if female else .0043)*(g(x,-self.eye_x,.018)+g(x,self.eye_x,.018))*g(y,self.eye_y+.017,.0065)
        cheek=(.0044 if female else .0036)*(g(x,-.043,.015)+g(x,.043,.015))*g(y,1.548 if female else 1.545,.015)
        muzzle=.0019*g(x,0,.025)*g(y,1.508,.016)
        # Sculpt both vermilion volumes into the same indexed skin sheet.
        lip_width=.0235 if female else .0255
        envelope=math.exp(-((x/lip_width)**4))
        cupid=.0013*(g(x,-.005,.003)+g(x,.005,.003))
        seam_y=1.504+.0010*(abs(x)/lip_width)**1.8
        upper=(.0038 if female else .0028)*g(y,seam_y+.0027+cupid,.0022)
        lower=(.0048 if female else .0037)*g(y,seam_y-.0033,.0028)
        seam=-.0013*g(y,seam_y,.00085)
        lips=(upper+lower+seam)*envelope
        philtrum=.0016*(g(x,-.0038,.0018)+g(x,.0038,.0018))*g(y,1.516,.0058)-.00065*g(x,0,.002)*g(y,1.516,.005)
        corner=-.0013*(g(x,-lip_width,.003)+g(x,lip_width,.003))*g(y,1.505,.004)
        chin=(.0028 if female else .0042)*g(x,0,.021)*g(y,1.477,.012)
        labiomental=-.0017*g(x,0,.022)*g(y,1.488,.0038)
        return nose+orbit+brow+cheek+muzzle+lips+philtrum+corner+chin+labiomental
    def point(self,theta,y):
        _,cz,w,fd,bd=self.sample(y);s=math.sin(theta);c=math.cos(theta)
        x=float(w)*s;z=float(cz)+(float(fd) if c>=0 else float(bd))*c
        if c>0:z+=self.feature_depth(x,y)*c**5
        # Connected auricle: an oval helix with concha and antihelix grows
        # out of the temporal cage. It is not a capped tube pasted to it.
        a=abs(theta);u=(a-1.615)/.235;v=(y-1.553)/.027
        radius=math.sqrt(u*u+v*v)
        gate=1-smooth(.90,1.17,radius)
        helix=.0115*math.exp(-((radius-.77)/.18)**2)
        concha=.0030*math.exp(-((radius/.69)**4))
        anti=.0050*g(a,1.70,.055)*g(y,1.559,.012)
        tragus=.0052*g(a,1.435,.042)*g(y,1.550,.006)
        lobe=.0062*g(a,1.60,.125)*g(y,1.531,.0065)
        lateral=(helix+concha+anti+tragus+lobe)*gate
        x+=math.copysign(lateral,theta)
        z+=.0017*g(a,1.56,.11)*g(y,1.534,.007)*gate
        return float(x),float(y),float(z)
    def front(self,x,y):
        width=float(self.sample(y)[2]);theta=math.asin(clamp(x/max(.001,width),-.999,.999))
        return self.point(theta,y)[2]
    def face_feature(self,p,theta):
        if abs(theta)>2.3:return 'head_back'
        if 1.35<abs(theta)<1.91 and 1.526<p[1]<1.581:return 'ear_inner' if 1.49<abs(theta)<1.78 else 'ear'
        if abs(theta)<.65 and abs(p[0])<(.025 if self.f else .027) and 1.498<p[1]<1.512:
            return 'lip_upper' if p[1]>1.504 else 'lip_lower'
        return 'face'
    def vertex(self,p,theta,feature=None):
        return self.mesh.vertex(p,((theta+math.pi)/TAU,(p[1]-1.44)/.245),self.skin(p,feature or self.face_feature(p,theta),max(0,math.cos(theta))),self.head)
    def make(self):
        # Below the orbit, rows follow the sloping mandibular border.
        lower=[None]+[t/17 for t in range(1,18)]
        upper=unique([1.515+.0025*j for j in range(43)]+[1.620+.003*j for j in range(23)]+[1.549,1.596,1.685]+[1.493+.001*j for j in range(23)])
        upper=[y for y in upper if y>1.515 and y<=1.685]
        grid=[];row_y=[]
        for row,t in enumerate(lower):
            indices=[]
            for theta in self.theta:
                y=self.jaw_bottom(theta) if t is None else self.jaw_bottom(theta)+(1.515-self.jaw_bottom(theta))*t
                indices.append(self.vertex(self.point(theta,y),theta))
            grid.append(indices);row_y.append(None)
        for y in upper:
            grid.append([self.vertex(self.point(theta,y),theta) for theta in self.theta]);row_y.append(y)
        # Exact row lookup includes the eye cut boundary, avoiding T joints.
        level={round(self.mesh.v[row[0]][1],7):i for i,row in enumerate(grid) if len({round(self.mesh.v[j][1],7) for j in row})==1}
        for k,(a,b) in enumerate(zip(grid,grid[1:])):
            for j,(ta,tb) in enumerate(zip(self.theta,self.theta[1:])):
                ym=(self.mesh.v[a[j]][1]+self.mesh.v[b[j]][1])*.5;tm=(ta+tb)*.5
                hole=self.eye_lo<ym<self.eye_hi and (.07<tm<.89 or -.89<tm<-.07)
                if not hole:self.mesh.quad(a[j],a[j+1],b[j+1],b[j])
        # Close only the top of the cranial cage. Hair covers this small pole.
        top=grid[-1];pole=self.vertex((0,1.685,-.012),math.pi)
        for a,b in zip(top,top[1:]):self.mesh.tri(a,b,pole)
        self.sew_neck(grid[0])
        for side in (-1,1):
            lo=.07 if side>0 else -.89;hi=.89 if side>0 else -.07
            ja=self.theta.index(round(lo,9));jb=self.theta.index(round(hi,9));ka=level[round(self.eye_lo,7)];kb=level[round(self.eye_hi,7)]
            boundary=grid[ka][ja:jb]+[grid[k][jb] for k in range(ka,kb)]+list(reversed(grid[kb][ja+1:jb+1]))+[grid[k][ja] for k in range(kb,ka,-1)]
            self.orbit(side,boundary,lo,hi)
            self.eyeball(side)
            self.brow(side)
        self.r.identity_author=self
    def sew_neck(self,jaw):
        mesh=self.mesh;boundary=self.r.identity_neck_ring[:-1]
        # Order both boundaries by the same continuous head angle. Existing
        # neck samples/weights remain untouched and are shared by the join.
        neck=[]
        for index in boundary:
            p=mesh.v[index];theta=math.atan2(p[0],p[2]);neck.append((theta,index))
        neck.sort();neck.append((neck[0][0]+TAU,neck[0][1]))
        def neck_sample(theta):
            while theta<neck[0][0]:theta+=TAU
            for (a,ia),(b,ib) in zip(neck,neck[1:]):
                if a-1e-8<=theta<=b+1e-8:
                    t=(theta-a)/(b-a);ra=mesh.raw(ia);rb=mesh.raw(ib)
                    return lerp(ra['p'],rb['p'],t),self.r.weight_mix(ra['weights'],rb['weights'],t)
            raise ValueError(theta)
        # First join row sits close to the existing boundary. A zipper uses
        # the existing 32 lower edges and the denser facial topology exactly.
        rings=[]
        for k in range(1,9):
            t=k/8;row=[]
            for theta,index in zip(self.theta,jaw):
                lower,w=neck_sample(theta);upper=mesh.v[index]
                p=lerp(lower,upper,t)
                # Submental tissue has an actual concavity, not a disk rim.
                front=max(0,math.cos(theta));p=(p[0],p[1],p[2]-.0035*math.sin(math.pi*t)*front**2)
                weights=self.r.weight_mix(w,self.head,smooth(0,1,t))
                if k==8:row.append(index)
                else:row.append(mesh.vertex(p,((theta+math.pi)/TAU,(p[1]-1.44)/.245),self.skin(p,'neck',front),weights))
            rings.append(row)
        first=rings[0]
        ns=[(a if a>=-math.pi else a+TAU,i) for a,i in neck[:-1]];ns.sort();ns=[(ns[-1][0]-TAU,ns[-1][1])]+ns+[(ns[0][0]+TAU,ns[0][1])]
        # Triangulate ordered loops without introducing unattached samples.
        ni=0;fi=0
        while ni+1<len(ns) and ns[ni+1][0]<=self.theta[0]+1e-8:ni+=1
        while fi<len(first)-1:
            nt=ns[ni+1][0];ft=self.theta[fi+1]
            if nt<ft-1e-8:
                mesh.tri(ns[ni][1],ns[ni+1][1],first[fi]);ni+=1
            elif ft<nt-1e-8:
                mesh.tri(ns[ni][1],first[fi+1],first[fi]);fi+=1
            else:
                mesh.quad(ns[ni][1],ns[ni+1][1],first[fi+1],first[fi]);ni+=1;fi+=1
        for a,b in zip(rings,rings[1:]):
            for j in range(len(a)-1):mesh.quad(a[j],a[j+1],b[j+1],b[j])
    def orbit(self,side,boundary,lo,hi):
        mesh=self.mesh;cx,cy,cz=self.eyes[side];inner=[];outer=[];polar=[]
        for index in boundary:
            p=mesh.v[index];width=float(self.sample(p[1])[2]);theta=math.asin(clamp(p[0]/width,-1,1))
            angle=math.atan2((p[1]-cy)/((self.eye_hi-self.eye_lo)/2),(theta-(lo+hi)*.5)/((hi-lo)/2))
            polar.append(angle);outer.append(p)
            xx=(.0154 if self.f else .0144)*math.cos(angle)
            yy=(.0050 if self.f else .0044)*max(0,math.sin(angle))+(.0040 if self.f else .0033)*min(0,math.sin(angle))
            yy+=(.0011 if self.f else .0006)*(side*xx/self.rx)
            ell=max(.025,1-(xx/self.rx)**2-(yy/self.ry)**2)
            zz=cz+self.rz*math.sqrt(ell)+.00035
            inner.append((cx+xx,cy+yy,zz))
        rings=[]
        for k in range(9):
            t=k/8;row=[]
            for n,(a,b) in enumerate(zip(inner,outer)):
                if k==8:row.append(boundary[n]);continue
                x,y,_=lerp(a,b,t);base=self.front(x,y);base_inner=self.front(a[0],a[1])
                z=base+(a[2]-base_inner)*(1-t)**2
                ang=polar[n];upper=max(0,math.sin(ang))
                # Soft marginal roll and upper-lid hood. Both are sewn to
                # the same skin, with a shallow crease rather than a line.
                z+=.00075*math.sin(math.pi*t)*math.exp(-t*5)
                z+=.0010*upper*math.exp(-((t-.38)/.17)**2)
                z-=.00045*upper*math.exp(-((t-.69)/.095)**2)
                p=(x,y,z);row.append(mesh.vertex(p,((math.asin(clamp(x/float(self.sample(y)[2]),-.999,.999))+math.pi)/TAU,(y-1.44)/.245),self.skin(p,'eyelid'),self.head))
            rings.append(row)
        for a,b in zip(rings,rings[1:]):
            for j in range(len(a)):mesh.quad(a[j],b[j],b[(j+1)%len(a)],a[(j+1)%len(a)])
    def eyeball(self,side):
        mesh=self.r.meshes[7];cx,cy,cz=self.eyes[side];grid=[]
        for k in range(33):
            latitude=-math.pi/2+math.pi*k/32;row=[]
            for j in range(65):
                theta=-math.pi+TAU*j/64
                x=self.rx*math.cos(latitude)*math.sin(theta);y=self.ry*math.sin(latitude);z=self.rz*math.cos(latitude)*math.cos(theta)
                row.append(mesh.vertex((cx+x,cy+y,cz+z),pigment.eye_uv(x,y,diameter=.032),(1,1,1),self.head))
            grid.append(row)
        for a,b in zip(grid,grid[1:]):
            for j in range(64):mesh.quad(a[j],a[j+1],b[j+1],b[j])
    def brow(self,side):
        mesh=self.r.meshes[6];color=pigment.hair_color(.5,.2,female=self.f,feature='brow')
        count=36
        for strand in range(5 if self.f else 7):
            row=[]
            for j in range(count+1):
                t=j/count;x=side*(.012+.033*t)
                y=self.eye_y+.016+.0035*math.sin(math.pi*t)-.0015*t+(strand-(2 if self.f else 3))*.00035*math.sin(math.pi*t)
                z=self.front(x,y)+.00055;row.append((x,y,z))
            # Fine original brow hairs are low, tapered strokes in the
            # detail material, independent of hair palette ownership.
            for j,(a,b) in enumerate(zip(row,row[1:])):
                width=.00019*math.sin(math.pi*(j+.5)/count)
                ia=mesh.vertex((a[0],a[1]-width,a[2]),(j/count,0),color,self.head);ib=mesh.vertex((b[0],b[1]-width,b[2]),((j+1)/count,0),color,self.head)
                ic=mesh.vertex((b[0],b[1]+width,b[2]),((j+1)/count,1),color,self.head);id=mesh.vertex((a[0],a[1]+width,a[2]),(j/count,1),color,self.head)
                mesh.quad(ia,ib,ic,id)

def build_identity_face(resident):PortraitSculpt(resident).make()

class LayeredGroom:
    def __init__(self,resident):self.r=resident;self.s=resident.identity_author;self.m=resident.meshes[2];self.head=resident.weight('Bip01 Head');self.f=resident.female
    def scalp(self,theta,y,offset=.0025):
        p=self.s.point(theta,y);normal=unit((p[0],(y-1.587)*.5,p[2]+.01))
        return add(p,mul(normal,offset))
    def lock(self,controls,width,thickness=.0022,twist=0.,segments=18):
        mesh=self.m;rows=[]
        for k in range(segments+1):
            t=k/segments;p=bezier(controls,t)
            a=bezier(controls,max(0,t-.01));b=bezier(controls,min(1,t+.01));tangent=unit(sub(b,a))
            radial=unit((p[0],max(.005,p[1]-1.58)*.9,p[2]+.010))
            across=unit(cross(tangent,radial));normal=unit(cross(across,tangent))
            if dot(normal,radial)<0:normal=mul(normal,-1);across=mul(across,-1)
            # Flattened, rounded lock: individual flow, layered overlap and
            # a tapered end; no wires, scalp spikes or flat opaque slabs.
            taper=(.54+.46*math.sin(math.pi*(.16+.77*t)))*(1-.93*smooth(.72,1,t))
            breadth=width*taper;depth=thickness*(.5+.5*math.sin(math.pi*t))*(1-.75*smooth(.76,1,t));row=[]
            for j in range(13):
                a=TAU*j/12;u=(math.cos(a)+1)/2
                q=add(p,add(mul(across,breadth*math.cos(a)),mul(normal,depth*math.sin(a))))
                # A small root-to-tip twist follows the groom direction.
                q=add(q,mul(normal,twist*math.sin(math.pi*t)*math.cos(a)))
                row.append(mesh.vertex(q,(u,t),pigment.hair_color(u,t,female=self.f),self.head))
            rows.append(row)
        for a,b in zip(rows,rows[1:]):
            for j in range(12):mesh.quad(a[j],b[j],b[j+1],a[j+1])
        for row,flip in [(rows[0],True),(rows[-1],False)]:
            c=tuple(sum(mesh.v[i][axis] for i in row[:-1])/12 for axis in range(3));ci=mesh.vertex(c,(.5,0 if flip else 1),pigment.hair_color(.5,0 if flip else 1,female=self.f),self.head)
            for a,b in zip(row,row[1:]):mesh.tri(ci,b,a) if flip else mesh.tri(ci,a,b)
    def foundation(self):
        rows=[]
        for k in range(18):
            t=k/17;row=[]
            for j in range(97):
                theta=-math.pi+TAU*j/96;a=abs(theta)
                low=1.620-.071*smooth(.56,2.45,a)
                y=low+(1.683-low)*t
                p=self.scalp(theta,y,.0021)
                row.append(self.m.vertex(p,(j/96,t),pigment.hair_color(j/96,t,female=self.f,feature='scalp'),self.head))
            rows.append(row)
        for a,b in zip(rows,rows[1:]):
            for j in range(96):self.m.quad(a[j],a[j+1],b[j+1],b[j])
    def make(self):
        self.foundation()
        if self.f:self.female()
        else:self.male()
        # Fit the broad crown groom to the established authored stature,
        # preserving the face, skull and every skeletal/contact coordinate.
        # This is a continuous upper-groom shape adjustment, not a peak.
        highest=max(p[1] for p in self.m.v)
        gain=(1.698-1.620)/(highest-1.620)
        self.m.v=[(x,1.620+(y-1.620)*gain if y>1.620 else y,z) for x,y,z in self.m.v]
    def male(self):
        # Crown-to-temple swept layers emerge on both sides of a real
        # off-centre part; all locks are connected root-to-tip above1.59.
        for side in (-1,1):
            for layer in range(3):
                for j in range(7):
                    theta=side*(.20+j*.185);end_y=1.612-.039*(j/6)+layer*.006
                    root=( -.017+side*.004*layer,1.681-layer*.002,-.020-.006*j)
                    mid1=(side*(.018+.002*j),1.689-layer*.002,.018-.007*j)
                    mid2=self.scalp(theta*.82,max(end_y+.024,1.625),.006+layer*.001)
                    end=self.scalp(theta,end_y,.004+layer*.001)
                    self.lock([root,mid1,mid2,end],.0095 if side>0 else .0085,.0023,twist=.0009*math.sin(j),segments=14)
        # Nape layers break the cap edge and taper behind each ear.
        for side in (-1,1):
            for j in range(8):
                theta=side*(1.52+.18*j)
                root=self.scalp(theta*.92,1.645,.0038)
                end=self.scalp(theta,1.546+.007*math.sin(j*1.6),.0025)
                self.lock([root,self.scalp(theta,1.620,.0045),self.scalp(theta,1.570,.004),end],.0085,.0019,segments=13)
        # Front fringe, separated and asymmetric, leaves a readable hairline.
        for j in range(8):
            x=-.046+j*.012
            self.lock([(x*.24-.012,1.680,-.006),(x*.55,1.687,.039),(x,1.649,.064),(x+.004,1.619+.006*math.sin(j),.061)],.0080,.0021,segments=15)
        # Broad apex strand maintains the established source headheight;
        # its rounded crest, rather than an isolated spike, is 1.698m.
        self.lock([(-.021,1.683,-.044),(-.014,1.696,-.015),(.010,1.696,.010),(.035,1.675,.030)],.009,.0020,segments=16)
    def female(self):
        # Layered side-part bob: crown, temple and back locks are separate
        # flattened volumes with staggered tips instead of one hair shell.
        for side in (-1,1):
            for layer in range(3):
                for j in range(9):
                    theta=side*(.55+j*.27);low=1.477+.013*math.sin(j*.95+layer)
                    start=(-.019+side*.004*layer,1.680-layer*.002,-.020-.003*j)
                    turn=self.scalp(theta*.90,1.626,.006+layer*.002)
                    p=self.scalp(theta,1.555,.007+layer*.002)
                    tip=(p[0]*1.04+side*.001*layer,low,p[2]+.004*math.sin(j))
                    self.lock([start,turn,(p[0]*1.06,1.531,p[2]-.001),tip],.0105,.0024,twist=.0008*math.cos(j),segments=19)
        for side in (-1,1):
            for j in range(6):
                theta=side*(.41+.11*j);p=self.scalp(theta,1.575,.007)
                tip=(p[0]*1.04,1.501+.010*j,p[2]+.007)
                self.lock([(-.018+side*.005,1.683,.003),self.scalp(theta*.7,1.651,.008),p,tip],.0090,.0022,segments=18)
        self.lock([(-.025,1.683,-.041),(-.018,1.696,-.018),(.007,1.696,.007),(.035,1.675,.031)],.009,.002,segments=16)

def build_identity_hair(resident):LayeredGroom(resident).make()

def identity_contract():
    return {'version':'EXP34 authored portrait candidate 1','method':'Dedicated indexed facial cage with real orbital apertures, sewn eight-loop eyelids, independent curved eyeballs and connected craniofacial/auricle/upper-neck surface; individually lofted layered groom locks',
            'protected_lower_neck_y_m':1.440,'eye_centres_m':{'male':[[-.028,1.572],[.028,1.572]],'female':[[-.029,1.573],[.029,1.573]]},
            'eye_atlas_square_m':.032,'source_assets_read':[],'quality_scope':'Original game identities. Appearance and motion require actual front/profile/rear native review; dimensions are not a realism or attractiveness score.'}

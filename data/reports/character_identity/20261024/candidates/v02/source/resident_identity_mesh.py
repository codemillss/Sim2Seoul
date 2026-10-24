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
        self.head=resident.weight('Bip01 Head');self.eye_y=1.575 if self.f else 1.572
        self.eye_x=.029 if self.f else .028
        self.rx=.016 if self.f else .015;self.ry=.011 if self.f else .0108;self.rz=.011 if self.f else .0105
        # Distinct mandibular arches, maxilla and cranial widths; section
        # curves form the cage only. Feature topology and tissue are below.
        rows=[(1.458,0,.010,.033,.040,.030),(1.470,0,.001,.043,.052,.038),
              (1.487,0,-.004,.060,.061,.047),(1.510,0,-.008,.064,.069,.061),
              (1.538,0,-.010,.069,.071,.073),(1.561,0,-.010,.068,.073,.077),
              (1.588,0,-.010,.067,.074,.078),(1.618,0,-.011,.065,.072,.077),
              (1.643,0,-.012,.060,.063,.070),(1.663,0,-.012,.049,.049,.055),
              (1.680,0,-.012,.029,.026,.030),(1.685,0,-.012,.005,.004,.005)]
        if self.f:
            rows=[(1.468 if y==1.458 else (1.477 if y==1.470 else y),cx,cz,w,fd,bd) for y,cx,cz,w,fd,bd in rows]
            rows=[(y,cx,cz,w*k,fd*df,bd) for (y,cx,cz,w,fd,bd),k,df in zip(rows,[.94,.91,.86,.93,.95,.95,.96,.97,.97,.98,1.,1.],[1.04,1.02,.98,.98,.99,1.,1.,1.,1.,1.,1.,1.])]
        self.sample=resident.section_sampler(rows)
        self.theta=unique([-math.pi+TAU*j/80 for j in range(81)]+[-.89,-.07,.07,.89]+[-1.+2*j/52 for j in range(53)]+[s*(1.22+.022*j) for s in (-1,1) for j in range(33)])
        self.theta[0]=-math.pi;self.theta[-1]=math.pi
        self.eye_lo=1.549;self.eye_hi=1.596
        self.eyes={}
        for side in (-1,1):
            cx=side*self.eye_x;z=self.front(cx,self.eye_y)-.0005-self.rz
            self.eyes[side]=(cx,self.eye_y,z)
    def skin(self,p,feature='face',front=1.):
        base=pigment.face_color(self.r.skin,p[0]/.069,(p[1]-1.458)/.184,female=self.f,feature=feature,front=front)
        if feature=='face' and front>.3:
            x,y,_=p;half_width=.0235 if self.f else .0255;u=abs(x)/half_width
            if u<1.12:
                seam=(1.511 if self.f else 1.504)+.0008*u*u
                h=(.0042 if y>=seam else .0058)*math.sqrt(max(0,1-min(1,u*u)))
                if y>=seam:h+=.0009*(g(x,-.005,.003)+g(x,.005,.003))
                amount=(1-smooth(.86,1.10,u))*(1-smooth(h-.0009,h+.0013,abs(y-seam)))
                lip=pigment.face_color(self.r.skin,x/.069,(y-1.458)/.184,female=self.f,feature='lip_upper' if y>=seam else 'lip_lower',front=front)
                base=lerp(base,lip,amount)
        return base
    def jaw_bottom(self,theta):
        # The chin is lower than the jaw angle and nape. A horizontal ring
        # at the chin would pull the neck into an artificial circular shelf.
        a=abs(theta)
        return (1.468 if self.f else 1.458)+(.022 if self.f else .029)*smooth(.65,1.65,a)+(.019 if self.f else .022)*smooth(1.60,2.70,a)
    def feature_depth(self,x,y):
        female=self.f
        nose_y=1.541 if female else 1.536
        nose=(.0055 if female else .0065)*g(x,0,.010)*g(y,nose_y+.020,.024)
        nose+=(.0115 if female else .0135)*g(x,0,.0100)*g(y,nose_y,.0095)
        nose+=.0055*(g(x,-.0105,.0055)+g(x,.0105,.0055))*g(y,nose_y-.006,.0058)
        nose+=.0030*g(x,0,.0038)*g(y,nose_y-.012,.0048)
        nose-=.0028*(g(x,-.0091,.0028)+g(x,.0091,.0028))*g(y,nose_y-.010,.0024)
        orbit=-.0042*(g(x,-self.eye_x,.016)+g(x,self.eye_x,.016))*g(y,self.eye_y,.012)
        brow=(.0023 if female else .0043)*(g(x,-self.eye_x,.018)+g(x,self.eye_x,.018))*g(y,self.eye_y+.017,.0065)
        cheek=(.0044 if female else .0036)*(g(x,-.043,.015)+g(x,.043,.015))*g(y,1.548 if female else 1.545,.015)
        muzzle=.0019*g(x,0,.025)*g(y,1.508,.016)
        # Sculpt both vermilion volumes into the same indexed skin sheet.
        lip_width=.0235 if female else .0255
        envelope=math.exp(-((x/lip_width)**4))
        cupid=.0013*(g(x,-.005,.003)+g(x,.005,.003))
        seam_y=(1.511 if female else 1.504)+.0008*(abs(x)/lip_width)**1.8
        upper=(.0038 if female else .0028)*g(y,seam_y+.0027+cupid,.0022)
        lower=(.0048 if female else .0037)*g(y,seam_y-.0033,.0028)
        seam=-.0013*g(y,seam_y,.00085)
        lips=(upper+lower+seam)*envelope
        philtrum=.0016*(g(x,-.0038,.0018)+g(x,.0038,.0018))*g(y,1.522 if female else 1.516,.0058)-.00065*g(x,0,.002)*g(y,1.522 if female else 1.516,.005)
        corner=-.0013*(g(x,-lip_width,.003)+g(x,lip_width,.003))*g(y,1.512 if female else 1.505,.004)
        chin=(.0028 if female else .0042)*g(x,0,.021)*g(y,1.482 if female else 1.477,.012)
        labiomental=-.0017*g(x,0,.022)*g(y,1.495 if female else 1.488,.0038)
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
        helix=.0078*math.exp(-((radius-.72)/.24)**2)
        concha=.0038*math.exp(-((radius/.69)**4))
        anti=.0035*g(a,1.70,.055)*g(y,1.559,.012)
        tragus=.0037*g(a,1.435,.042)*g(y,1.550,.006)
        lobe=.0053*g(a,1.60,.125)*g(y,1.531,.0065)
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
                z+=.0016*upper*math.exp(-((t-.32)/.19)**2)
                z-=.00065*upper*math.exp(-((t-.67)/.11)**2)
                p=(x,y,z);row.append(mesh.vertex(p,((math.asin(clamp(x/float(self.sample(y)[2]),-.999,.999))+math.pi)/TAU,(y-1.44)/.245),self.skin(p,'eyelid'),self.head))
            rings.append(row)
        for a,b in zip(rings,rings[1:]):
            for j in range(len(a)):mesh.quad(a[j],b[j],b[(j+1)%len(a)],a[(j+1)%len(a)])
    def eyeball(self,side):
        mesh=self.r.meshes[7];cx,cy,cz=self.eyes[side];grid=[]
        for k in range(25):
            latitude=-math.pi/2+math.pi*k/24;row=[]
            for j in range(49):
                theta=-math.pi+TAU*j/48
                x=self.rx*math.cos(latitude)*math.sin(theta);y=self.ry*math.sin(latitude);z=self.rz*math.cos(latitude)*math.cos(theta)
                row.append(mesh.vertex((cx+x,cy+y,cz+z),pigment.eye_uv(x,y,diameter=.032),(1,1,1),self.head))
            grid.append(row)
        for a,b in zip(grid,grid[1:]):
            for j in range(48):mesh.quad(a[j],a[j+1],b[j+1],b[j])
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
    """Surface-conforming swept hair clumps, with separate groom-flow UVs."""
    def __init__(self,resident):
        self.r=resident;self.s=resident.identity_author;self.m=resident.meshes[2]
        self.head=resident.weight('Bip01 Head');self.f=resident.female
    def hairline(self,theta):
        a=abs(theta)
        if self.f:
            # Open face, tucked-ear sides and layered bob behind the ears.
            low=1.632-.127*smooth(.70,1.25,a)-.029*smooth(1.95,2.60,a)
            low+=.082*g(a,1.62,.24)
        else:
            low=1.625-.079*smooth(.65,1.35,a)-.031*smooth(1.95,2.70,a)
            low+=.040*g(a,1.64,.22)
        return low
    def surface(self,theta,y):
        # Original cranial groom volume. The broad crown follows a rounded
        # cranium, while the longer female ends follow the bob silhouette.
        crown=math.sqrt(max(.000001,1-((y-1.589)/.107)**2))
        w=.073*crown;fd=.080*crown;bd=.087*crown;cz=-.013
        if y<1.589:
            if self.f:
                w=.078+.003*g(y,1.533,.039)-.004*(1-smooth(1.470,1.500,y))
                fd=.071;bd=.086;cz=-.010
            else:
                p=self.s.point(theta,max(y,self.s.jaw_bottom(theta)))
                radial=unit((p[0],0,p[2]+.01));return add(p,mul(radial,.0028))
        return (w*math.sin(theta),y,cz+(fd if math.cos(theta)>=0 else bd)*math.cos(theta))
    def normal(self,p):
        return unit((p[0]/.073**2,max(.002,p[1]-1.589)/.107**2,(p[2]+.013)/.084**2))
    def foundation(self):
        rows=[]
        for k in range(33):
            t=k/32;row=[]
            for j in range(113):
                theta=-math.pi+TAU*j/112;low=self.hairline(theta);y=low+(1.6958-low)*t
                p=self.surface(theta,y)
                row.append(self.m.vertex(p,(j/112,t),pigment.hair_color(j/112,t,female=self.f,feature='scalp'),self.head))
            rows.append(row)
        for a,b in zip(rows,rows[1:]):
            for j in range(112):self.m.quad(a[j],a[j+1],b[j+1],b[j])
        ci=self.m.vertex((0,1.696,-.013),(.5,1),pigment.hair_color(.5,1,female=self.f,feature='scalp'),self.head)
        for a,b in zip(rows[-1],rows[-1][1:]):self.m.tri(a,b,ci)
    def flow(self,start_theta,end_theta,end_y,width=.006,height=.0013,phase=0.,start_y=1.687):
        rows=[];segments=22 if self.f else 18
        for k in range(segments+1):
            t=k/segments;theta=start_theta+(end_theta-start_theta)*smooth(0,1,t)
            y=start_y+(end_y-start_y)*t**.88
            dt=.0005;tm=max(0,t-dt);tp=min(1,t+dt)
            dtheta=(end_theta-start_theta)*(smooth(0,1,tp)-smooth(0,1,tm))/(tp-tm)
            dy=(end_y-start_y)*(tp**.88-tm**.88)/(tp-tm)
            local_radius=max(.026,math.hypot(self.surface(theta,y)[0],self.surface(theta,y)[2]+.013))
            length=math.hypot(dtheta*local_radius,dy);ax=dy/max(1e-9,length);ay=-dtheta*local_radius/max(1e-9,length)
            taper=(.25+.75*math.sin(math.pi*(.12+.78*t)))*(1-.94*smooth(.76,1,t))
            row=[]
            # Cross-section is a shallow fitted strip with an embedded
            # underside, not a free-floating round cylinder or U-shaped tube.
            cross_samples=[(-1,0),(-.75,.64),(-.5,.87),(-.25,.97),(0,1),(.25,.97),(.5,.87),(.75,.64),(1,0),(.5,-.32),(0,-.35),(-.5,-.32),(-1,0)]
            for u,relief in cross_samples:
                offset=width*taper*u;tt=theta+ax*offset/local_radius;yy=min(1.6957,y+ay*offset)
                p=self.surface(tt,yy);normal=self.normal(p)
                p=add(p,mul(normal,height*relief*(.60+.40*math.sin(math.pi*t))))
                row.append(self.m.vertex(p,((u+1)/2,t),pigment.hair_color((u+1)/2,t,female=self.f),self.head))
            rows.append(row)
        for a,b in zip(rows,rows[1:]):
            for j in range(len(a)-1):self.m.quad(a[j],a[j+1],b[j+1],b[j])
        # The taper closes at the scalp. Its tiny end cross-section is
        # covered by the foundation, so no exposed dark flat end cap is added.
    def make(self):
        self.foundation()
        for j in range(44):
            theta=-math.pi+TAU*(j+.35)/44
            end=self.hairline(theta)-(.0025 if self.f else .0015)+.0022*math.sin(j*1.83)
            start=theta-(.38 if theta>-.4 else -.20)
            self.flow(start,theta,end,width=.0068 if self.f else .0062,height=.0013,phase=j,start_y=1.686+.0020*math.sin(j*2.1))
        # A second swept layer exposes a genuine off-centre part and breaks
        # the continuous hairline without covering the eyes or the cheeks.
        for j in range(15):
            theta=-.97+1.94*j/14
            self.flow(-.48+.025*j,theta,1.624+(.006 if self.f else -.003)*math.sin(j*.7),width=.0058,height=.0015,start_y=1.690-.002*math.cos(j))
        if self.f:
            for side in (-1,1):
                for j in range(9):
                    theta=side*(1.08+.22*j)
                    end=self.hairline(theta)-.004+.004*math.sin(j*1.4)
                    self.flow(theta-side*.19,theta+side*.025,end,width=.0065,height=.0016,start_y=1.671+.004*math.sin(j))
        # Whole upper groom fit retains the established source max1.698m.
        highest=max(p[1] for p in self.m.v);gain=(1.698-1.620)/(highest-1.620)
        self.m.v=[(x,1.620+(y-1.620)*gain if y>1.620 else y,z) for x,y,z in self.m.v]

def build_identity_hair(resident):LayeredGroom(resident).make()

def identity_contract():
    return {'version':'EXP34 authored portrait candidate 2','method':'Dedicated indexed facial cage with real orbital apertures, sewn eight-loop eyelids, independent curved eyeballs and connected craniofacial/auricle/upper-neck surface; individually lofted layered groom locks',
            'protected_lower_neck_y_m':1.440,'eye_centres_m':{'male':[[-.028,1.572],[.028,1.572]],'female':[[-.029,1.575],[.029,1.575]]},
            'eye_atlas_square_m':.032,'source_assets_read':[],'quality_scope':'Original game identities. Appearance and motion require actual front/profile/rear native review; dimensions are not a realism or attractiveness score.'}

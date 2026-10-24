from pathlib import Path
import hashlib,json,struct,numpy as np
REPO=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul')
BASE=REPO/'data/reports/character_identity/20261024/candidates/v04'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(path):
 raw=path.read_bytes();at=12;doc=None;blob=None
 while at<len(raw):
  n,tag=struct.unpack_from('<II',raw,at);at+=8;data=raw[at:at+n];at+=n
  if tag==0x4e4f534a:doc=json.loads(data)
  elif tag==0x004e4942:blob=data
 def accessor(index):
  a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']];dtype={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];dt=np.dtype(dtype);start=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',n*dt.itemsize)
  return np.ndarray((a['count'],n),dtype=dt,buffer=blob,offset=start,strides=(stride,dt.itemsize)).copy()
 out=[]
 for m in doc['meshes']:
  for p in m['primitives']:
   v=accessor(p['attributes']['POSITION']).astype(float);idx=accessor(p['indices']).reshape(-1,3);out.append((int(p['material']),v,idx))
 return doc,out

def nearest(origin,direction,triangles):
 a=triangles[:,0];e1=triangles[:,1]-a;e2=triangles[:,2]-a;h=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-12;inv=np.zeros_like(det);inv[valid]=1/det[valid];s=origin-a;u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*(q@direction);t=inv*np.einsum('ij,ij->i',e2,q);valid &= (u>=-1e-9)&(v>=-1e-9)&(u+v<=1+1e-9)&(t>0)
 return float(t[valid].min()) if valid.any() else None

results=[]
for sex in ('m01','f01'):
 path=BASE/f'seoul_resident_{sex}_street.glb';doc,parts=load(path);eye=np.concatenate([v for mat,v,idx in parts if 'Original_Eye' in doc['materials'][mat]['name']]);skin=np.concatenate([v[idx] for mat,v,idx in parts if 'Authored_Skin' in doc['materials'][mat]['name']]);hair=np.concatenate([v[idx] for mat,v,idx in parts if 'Hair_and_Eye' in doc['materials'][mat]['name']]);eyes=[]
 for side in (-1,1):
  verts=eye[eye[:,0]*side>0];low=verts.min(0);high=verts.max(0);centre=(low+high)/2;radii=(high-low)/2
  tri=skin[(skin[:,:,1].max(1)>centre[1]-.025)&(skin[:,:,1].min(1)<centre[1]+.025)&(skin[:,:,0].max(1)>centre[0]-radii[0]*1.4)&(skin[:,:,0].min(1)<centre[0]+radii[0]*1.4)]
  maximum=0.;minnorm=1e99;inside=0;covered=0;example=None
  for ai in range(13):
   for bi in range(13-ai):
    u=ai/12;v=bi/12;p=tri[:,0]*(1-u-v)+tri[:,1]*u+tri[:,2]*v;t=(p-centre)/radii;q=t[:,0]**2+t[:,1]**2;mask=(q<1)&(p[:,2]>centre[2]);n=(t*t).sum(1);covered+=int(mask.sum());inside+=int((mask&(n<1-1e-5)).sum())
    if mask.any():
     surface=centre[2]+radii[2]*np.sqrt(np.maximum(0,1-q));depth=surface-p[:,2];j=np.where(mask)[0][np.argmax(depth[mask])];minimum=float(n[mask].min());minnorm=min(minnorm,minimum)
     if depth[j]>maximum:maximum=float(depth[j]);example=p[j].tolist()
  eyes.append({'side':side,'fitted_globe_center_m':centre.tolist(),'fitted_globe_radii_m':radii.tolist(),'near_skin_triangles':len(tri),'barycentric_grid_denominator':12,'sample_instances_over_front_hemisphere':covered,'sample_instances_inside_ideal_ellipsoid':inside,'minimum_normalized_radius_squared':minnorm,'maximum_front_surface_penetration_m':maximum,'maximum_penetration_example_m':example,'scope':'Actual indexed skin faces,91 barycentric samples per near face, compared against the ellipsoid fitted from actual eye mesh extrema. A slight sample penetration may reflect triangulation; this is not an exhaustive analytic intersection proof.'})
 # Five actual image locations per side sample native profile eye aperture.
 rays=[]
 for side in (-1,1):
  camera=np.array([3.*side,1.57,.2]);target=np.array([0.,1.57,0.]);z=(camera-target);z/=np.linalg.norm(z);right=np.cross([0.,1.,0.],z);right/=np.linalg.norm(right);direction=-z
  for px,py in ([(396,294),(398,294),(400,294),(398,292),(398,296)] if side>0 else [(558,294),(560,294),(562,294),(560,292),(560,296)]):
   u=(px+.5-480)*.36/600;v=(300-py-.5)*.36/600;origin=camera+right*u+np.array([0.,v,0.]);hits=[]
   for mat,verts,idx in parts:
    title=doc['materials'][mat]['name']
    if not any(n in title for n in ['Authored_Skin','Original_Eye','Hair_and_Eye']):continue
    triangles=verts[idx];a=triangles[:,:,1];triangles=triangles[(a.max(1)>1.54)&(a.min(1)<1.61)];distance=nearest(origin,direction,triangles)
    if distance is not None:hits.append({'material':title,'distance_m':distance,'world_point_m':(origin+direction*distance).tolist()})
   hits.sort(key=lambda h:h['distance_m']);rays.append({'camera_side':side,'pixel_xy':[px,py],'first_hit':hits[0] if hits else None,'ordered_hits':hits,'scope':'Orthographic profile camera reconstructed from the native preview fixture camera coordinates and0.36m vertical size. Material first-hit is geometry evidence, not the PNG renderer depth buffer.'})
 results.append({'asset':str(path),'sha256':sha(path),'eyes':eyes,'profile_sample_rays':rays})
result={'task':'EXP34_V04_READONLY_EYE_SEATING_GEOMETRY','script':str(Path(__file__)),'script_sha256':sha(Path(__file__)),'assets':results,'scope':'Read-only actual candidate GLB. No geometry/source edit or engine execution. Visible white inside an intended aperture is not a failure criterion; zero visible white in profile is not the objective. Numerical surface tests supplement the12 actual opened raw native views; they do not establish full realistic orbital anatomy or absence of all unsampled intersections.'}
out=BASE/'ocular_geometry_readonly.json';out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'report':str(out),'eye_summaries':[{'sex':Path(x['asset']).name,'eyes':[{'side':e['side'],'covered':e['sample_instances_over_front_hemisphere'],'inside':e['sample_instances_inside_ideal_ellipsoid'],'max_m':e['maximum_front_surface_penetration_m']} for e in x['eyes']],'first_hit_materials':[r['first_hit']['material'] if r['first_hit'] else None for r in x['profile_sample_rays']]} for x in results]},indent=2))

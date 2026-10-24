import json,struct,math
from pathlib import Path
import numpy as np
base=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul/data/reports/character_identity/20261024/candidates/v04')
def arrays(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);blob=raw[28+n:];out={}
 for p in d['meshes'][0]['primitives']:
  a={}
  for key,idx in p['attributes'].items():
   ac=d['accessors'][idx];vw=d['bufferViews'][ac['bufferView']];co={'VEC3':3,'VEC4':4,'VEC2':2}[ac['type']];dt={5126:'<f4',5123:'<u2'}[ac['componentType']];a[key]=np.frombuffer(blob,dt,count=ac['count']*co,offset=vw.get('byteOffset',0)+ac.get('byteOffset',0)).reshape(-1,co)
  ac=d['accessors'][p['indices']];vw=d['bufferViews'][ac['bufferView']];a['index']=np.frombuffer(blob,'<u4',count=ac['count'],offset=vw.get('byteOffset',0)).reshape(-1,3)
  out[p['material']]=a
 return out
results=[]
for sex in ['m01','f01']:
 a=arrays(base/f'seoul_resident_{sex}_street.glb');eyes=a[7]['POSITION'];skin=a[1]['POSITION'];tris=skin[a[1]['index']];row={'sex':sex,'scope':'Raw candidate GLB triangle interiors covering front eye hemisphere; not an appearance/attractiveness rating','eyes':[]}
 for e in np.split(eyes,2):
  lower=e.min(0);upper=e.max(0);center=(lower+upper)/2;radius=(upper-lower)/2;samples=[];minmargin=1e9;bad=[]
  for bary in [(1/3,1/3,1/3),(.50,.25,.25),(.25,.50,.25),(.25,.25,.50),(.8,.1,.1),(.1,.8,.1),(.1,.1,.8)]:
   points=np.einsum('nij,i->nj',tris,bary);q=((points[:,0]-center[0])/radius[0])**2+((points[:,1]-center[1])/radius[1])**2
   mask=(q<1)&(points[:,2]>center[2])
   if not mask.any():continue
   front=center[2]+radius[2]*np.sqrt(1-q[mask]);margin=points[mask,2]-front
   minmargin=min(minmargin,float(margin.min()));samples.extend(margin.tolist())
   ids=np.where(mask)[0];bad.extend([{'skin_triangle':int(ids[k]),'margin_m':float(margin[k]),'point':points[ids[k]].tolist()} for k in np.where(margin<-.00001)[0][:4]])
  row['eyes'].append({'centre_m':center.tolist(),'radii_m':radius.tolist(),'front_skin_triangle_samples':len(samples),'minimum_globe_clearance_m':minmargin,'samples_inside_globe_gt_10um':sum(v<-.00001 for v in samples),'examples':bad[:6]})
 results.append(row)
p=base/'eye_globe_cover_readonly.json';p.write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))

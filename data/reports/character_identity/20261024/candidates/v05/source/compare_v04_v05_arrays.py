from pathlib import Path
import json,struct,hashlib,numpy as np
root=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul');base=root/'data/reports/character_identity/20261024/candidates'
def read(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);blob=raw[28+n:]
 def accessor(i):
  a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];typ={5126:'<f4',5123:'<u2',5125:'<u4'}[a['componentType']];co={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
  return np.frombuffer(blob,typ,count=a['count']*co,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],co)
 meshes={p['material']:{**{key:accessor(idx) for key,idx in p['attributes'].items()},'index':accessor(p['indices'])} for p in doc['meshes'][0]['primitives']}
 return doc,meshes
results=[]
for sex in ['m01','f01']:
 for wardrobe in ['street','swim']:
  name=f'seoul_resident_{sex}_{wardrobe}.glb';a,b=[base/v/name for v in ['v04','v05']]
  da,ma=read(a);db,mb=read(b);rows=[]
  for material in ma:
   for attribute in ['POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0','index']:
    x,y=ma[material][attribute],mb[material][attribute]
    rows.append({'material':material,'attribute':attribute,'equal':bool(np.array_equal(x,y)),'sha256':hashlib.sha256(x.tobytes()).hexdigest(),'values':len(x)})
  colors=[]
  for material in ma:
   changed=np.max(np.abs(ma[material]['COLOR_0']-mb[material]['COLOR_0']),axis=1)>1e-8
   lower=ma[material]['POSITION'][:,1]<=1.440
   colors.append({'material':material,'changed_vertices':int(changed.sum()),'vertices':len(changed),'changed_y_le_1_440':int((changed&lower).sum())})
  results.append({'name':name,'inputs':[{'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [a,b]],'native_skeleton_nodes_equal':da['nodes']==db['nodes'],'skins_equal':da['skins']==db['skins'],'protected_geometry_uv_skin_arrays_equal':all(r['equal'] for r in rows),'arrays':rows,'colours':colors})
source=base/'v05/source/compare_v04_v05_arrays.py';source.parent.mkdir(parents=True,exist_ok=True);source.write_bytes(Path(__file__).read_bytes())
out={'scope':'Controlled geometry4 numerical colour versus same geometry4 with original generated paint vertex colour. Exact float32/index array comparison; not an appearance or motion acceptance.','source':{'path':str(source.relative_to(root)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()},'passed':all(r['protected_geometry_uv_skin_arrays_equal'] and r['native_skeleton_nodes_equal'] and r['skins_equal'] and all(c['changed_y_le_1_440']==0 and (c['material']==1 or c['changed_vertices']==0) for c in r['colours']) for r in results),'results':results}
(base/'v05/geometry_control_comparison.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'passed':out['passed'],'cases':[(r['name'],r['protected_geometry_uv_skin_arrays_equal'],r['colours']) for r in results]},indent=2))

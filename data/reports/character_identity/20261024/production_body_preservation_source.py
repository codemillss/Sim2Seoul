from pathlib import Path
import json,struct,hashlib,numpy as np
ROOT=Path('/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul')
BASE=Path('/private/tmp/sim2seoul_exp34_baseline12');OUT=ROOT/'game/assets/original/seoul_resident';REPORT=ROOT/'data/reports/character_identity/20261024'
def load(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);blob=raw[28+n:]
 def arr(i):
  a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];dt={5126:'<f4',5123:'<u2',5125:'<u4'}[a['componentType']];c={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
  return np.frombuffer(blob,dt,count=a['count']*c,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],c)
 m={p['material']:{**{name:arr(i) for name,i in p['attributes'].items()},'index':arr(p['indices']).reshape(-1,3)} for p in d['meshes'][0]['primitives']}
 return d,m
ATTR=['POSITION','TEXCOORD_0','JOINTS_0','WEIGHTS_0','COLOR_0']
def canonical_lower(mesh):
 indices=mesh['index'];indices=indices[(mesh['POSITION'][indices,1].max(1)<=1.440001)]
 records=[b''.join(mesh[key][i].tobytes() for key in ATTR) for i in range(len(mesh['POSITION']))]
 triangles=[]
 for a,b,c in indices:
  a,b,c=records[a],records[b],records[c];triangles.append(min(a+b+c,b+c+a,c+a+b))
 return len(triangles),hashlib.sha256(b''.join(sorted(triangles))).hexdigest()
rows=[]
for new in sorted(OUT.glob('seoul_resident_*.glb')):
 old=BASE/new.name
 if not old.exists():continue
 d0,m0=load(old);d1,m1=load(new)
 row={'name':new.name,'baseline_sha256':hashlib.sha256(old.read_bytes()).hexdigest(),'current_sha256':hashlib.sha256(new.read_bytes()).hexdigest(),'all_52_rest_nodes_and_hierarchy_exact':d0['nodes'][2:]==d1['nodes'][2:],'full_unchanged_surfaces':[],'lower_body_semantic_triangles':[]}
 for material in [0,3,4,5]:
  if material not in m0:continue
  equal=all(np.array_equal(m0[material][key],m1[material][key]) for key in m0[material])
  row['full_unchanged_surfaces'].append({'material':material,'all_positions_normals_uv_colours_weights_indices_equal':bool(equal)})
 for material in [1,6]:
  a=canonical_lower(m0[material]) if material in m0 else (0,hashlib.sha256(b'').hexdigest());b=canonical_lower(m1[material]) if material in m1 else (0,hashlib.sha256(b'').hexdigest());row['lower_body_semantic_triangles'].append({'material':material,'height_max_m':1.440001,'baseline':{'triangles':a[0],'sha256':a[1]},'current':{'triangles':b[0],'sha256':b[1]},'exact_oriented_triangles_and_attributes_equal':a==b})
 settings=OUT/(new.name+'.import');prior=BASE/(new.name+'.import')
 row['import_settings']={'path':str(settings.relative_to(ROOT)),'sha256':hashlib.sha256(settings.read_bytes()).hexdigest(),'baseline_sha256':hashlib.sha256(prior.read_bytes()).hexdigest(),'exact_bytes_equal':settings.read_bytes()==prior.read_bytes(),'generate_lods_false':'meshes/generate_lods=false' in settings.read_text()}
 row['passed']=row['all_52_rest_nodes_and_hierarchy_exact'] and all(r['all_positions_normals_uv_colours_weights_indices_equal'] for r in row['full_unchanged_surfaces']) and all(r['exact_oriented_triangles_and_attributes_equal'] for r in row['lower_body_semantic_triangles'])
 rows.append(row)
standard=[]
for candidate in sorted((REPORT/'candidates/v06').glob('*.glb')):
 standard.append({'name':candidate.name,'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'production_sha256':hashlib.sha256((OUT/candidate.name).read_bytes()).hexdigest(),'byte_identical':candidate.read_bytes()==(OUT/candidate.name).read_bytes()})
source=REPORT/'production_body_preservation_source.py';source.write_bytes(Path(__file__).read_bytes())
result={'scope':'EXP34 body preservation against archived main08ba5bf. Skin/detail below1.440001m compare exact oriented triangle multisets with POSITION/UV/JOINTS/WEIGHTS/COLOR. They intentionally do not compare neck-boundary shading normals. Whole garment/hands/trousers/shoe surfaces compare every exported array. Embedded neutral skin texture was separately updated with portrait materials; this is not a material-byte identity claim. Appearance/animation are separate native gates.','baseline_archive':'/private/tmp/sim2seoul_exp34_head_baseline_20261024.tar.gz','source':{'path':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()},'passed':len(rows)==12 and all(r['passed'] for r in rows) and all(r['byte_identical'] for r in standard),'assets':rows,'standard_candidate_matches':standard}
(REPORT/'production_body_preservation.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'passed':result['passed'],'assets':len(rows),'failed':[r['name'] for r in rows if not r['passed']],'exact_imports':sum(r['import_settings']['exact_bytes_equal'] for r in rows),'zero_lod':sum(r['import_settings']['generate_lods_false'] for r in rows),'standard_byte_identical':all(r['byte_identical'] for r in standard)},indent=2))

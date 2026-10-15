#!/usr/bin/env python3
"""Reproduce original false acceptance and fixed rejection, without editing production files."""
import argparse,copy,gzip,hashlib,importlib.util,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();root=a.root.resolve()
sys.path.insert(0,str(root/'tools'))
def load_module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
old=load_module('old_checker',HERE/'original_checker.py')
new=load_module('new_checker',HERE/'fixed_checker.py')
def read(path):
 with (gzip.open(path,'rt') if path.suffix=='.gz' else path.open()) as f:return json.load(f)
def write(path,x):path.write_text(json.dumps(x,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
paths=['data/reports/landmarks/l03/gpu.json.gz','game/data/generated/public_walk.json','game/resources/world_geometry/world.json','game/data/generated/daehanmun.json']
args=[read(root/path) for path in paths]+[read(HERE/'plan.json')]
manifest={path:hashlib.sha256((root/path).read_bytes()).hexdigest() for path in paths}
write(HERE/'inputs_sha256.json',manifest)
normal=read(HERE/'normal_gpu.json.gz')
variants={'normal_gpu':normal}
x=copy.deepcopy(normal);source=next(c for c in x['cases'] if c['purpose']=='orbit')
for i,c in enumerate(x['cases']):
 if c['purpose']=='orbit':
  row=copy.deepcopy(source);row['name']=c['name'];x['cases'][i]=row
variants['fault_all_orbits_reuse']=x
x=copy.deepcopy(normal)
for c in x['cases']:
 if c['purpose']=='walk':
  sample=copy.deepcopy(c['samples'][-1]);sample['t']=1/60
  c.update(start=sample['player'],end=sample['player'],duration_s=1/60,wall_s=1/60,ticks=1,frames=1,samples=[sample])
  c['all_tick_stats']['ticks']=c['all_tick_stats']['floor_ticks']=1
  c['W03_stats']['ticks']=c['W03_stats']['floor_support_ticks']=1
variants['fault_walks_static_endpoint']=x
summary=[]
for name,raw in variants.items():
 with gzip.GzipFile(filename=str(HERE/(name+'.json.gz')),mode='wb',mtime=0) as f:f.write((json.dumps(raw,separators=(',',':'),allow_nan=False)+'\n').encode())
 before=old.audit(raw,*args);after=new.audit(raw,*args)
 write(HERE/(name+'_before.json'),before);write(HERE/(name+'_after.json'),after)
 summary.append({'name':name,'before_passed':before['passed'],'after_passed':after['passed'],
                 'after_failed_checks':[c['name'] for c in after['checks'] if not c['passed']]})
write(HERE/'summary.json',summary)
print(json.dumps(summary,ensure_ascii=False))
assert all(row['before_passed'] for row in summary)
assert summary[0]['after_passed'] and all(not row['after_passed'] for row in summary[1:])

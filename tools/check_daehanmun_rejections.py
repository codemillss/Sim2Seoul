#!/usr/bin/env python3
"""W01 actual runtime refusals before world/collider creation."""
import argparse,copy,hashlib,json,re,shutil,subprocess,tempfile
from pathlib import Path
from check_daehanmun_contract import FILES,ASSETS
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n')
def main(output,engine):
 output=output.resolve();output.mkdir(parents=True,exist_ok=True);source={p:sha(ROOT/'game'/p) for p in ASSETS};results=[]
 names=['connection_checksum','manifest_world_hash','manifest_collision_hash','manifest_file_type','wrong_task','opening_width','terrain_claim','missing_fragment','fragment_number','movement_number','volume_number','route_number']
 for name in names:
  with tempfile.TemporaryDirectory(prefix='sim2seoul-w01-reject-') as tmp:
   game=Path(tmp)/'game'
   for path in FILES+ASSETS:
    p=game/path;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/path,p)
   generated=game/'data/generated';plan_path=generated/'daehanmun.json';decision_path=generated/'daehanmun_decision.json';manifest_path=generated/'daehanmun_manifest.json'
   plan=json.loads(plan_path.read_text());decision=json.loads(decision_path.read_text());manifest=json.loads(manifest_path.read_text())
   if name=='connection_checksum':plan_path.write_bytes(plan_path.read_bytes()+b' ')
   elif name=='manifest_world_hash':manifest['world_sha256']='0'*64
   elif name=='manifest_collision_hash':manifest['collision_sha256']='0'*64
   elif name=='manifest_file_type':manifest['files']['connection']=[]
   elif name=='wrong_task':plan['task']='W02'
   elif name=='opening_width':plan['opening']['width']=2;decision['opening_width_m']=2
   elif name=='terrain_claim':plan['scope']['physical_terrain_verified']=True;decision['scope']['physical_terrain_verified']=True
   elif name=='missing_fragment':plan['fragments'].pop()
   elif name=='fragment_number':plan['fragments'][0]['vertices'][0]='bad'
   elif name=='movement_number':plan['movement_ring'][0][0]='bad'
   elif name=='volume_number':plan['volume_obstacles'][0]['bottom']='bad'
   elif name=='route_number':plan['route_xz'][0][0]='bad'
   if name!='connection_checksum':
    write(plan_path,plan);write(decision_path,decision)
    if name!='manifest_file_type':
     manifest['files']['connection']['sha256']=sha(plan_path);manifest['files']['decision']['sha256']=sha(decision_path)
   write(manifest_path,manifest)
   result=output/(name+'.json');log=output/(name+'.log')
   ran=subprocess.run(['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine),'--headless','--path',str(game),'--script',str(ROOT/'tests/game/check_daehanmun_rejection.gd'),'--log-file',str(log),'--','--result='+str(result)],capture_output=True,text=True,timeout=30)
   messages=re.sub(r'\x1b\[[0-9;]*m','',ran.stdout+ran.stderr)
   if ran.returncode or 'ERROR:' in messages or 'SCRIPT ERROR' in messages or not result.exists():raise ValueError(name+':'+messages[-1500:])
   d=json.loads(result.read_text());ok=d['accepted'] is False and d['source_bodies_created']==0 and d['fragment_bodies_created']==0 and bool(d['error']);results.append({'case':name,'passed':ok,'engine_evidence':result.name});print('W01 reject',name,ok,flush=True)
 d={'task':'W01','passed':all(r['passed'] for r in results) and source=={p:sha(ROOT/'game'/p) for p in ASSETS},'cases':results,'original_runtime_sha256':source,'probe_sha256':sha(ROOT/'tests/game/check_daehanmun_rejection.gd'),'driver_sha256':sha(Path(__file__)),'scope':'12 actual runtime rejection variants, independent of 6 actual geometry/config faults and evidence JSON mutations'}
 write(output/'rejection_check.json',d);return 0 if d['passed'] else 1
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'data/cache/daehanmun_rejections');p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'));a=p.parse_args();raise SystemExit(main(a.output,a.engine))

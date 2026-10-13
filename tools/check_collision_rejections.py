#!/usr/bin/env python3
"""P04 actual runtime rejection of incomplete/promoted/stale collision plans."""
import argparse,copy,hashlib,json,shutil,subprocess,tempfile
from pathlib import Path
from check_collision_contract import ROOT,FILES,ASSETS

def main(output,engine):
 output=output.resolve();output.mkdir(parents=True,exist_ok=True);original=ROOT/'game/resources/collision/generated.json';content=original.read_bytes();plan=json.loads(content)
 cases=[]
 def add(name,func):
  p=copy.deepcopy(plan);func(p);cases.append((name,p))
 add('world_hash',lambda p:p.update(world_sha256='0'*64))
 add('rules_hash',lambda p:p.update(rules_sha256='0'*64))
 add('missing_body',lambda p:p['entries'].pop())
 add('duplicate_body',lambda p:p['entries'].append(copy.deepcopy(p['entries'][0])))
 add('reference_promoted',lambda p:p['entries'][0].update(mesh_id=p['excluded'][0]['mesh_id']))
 add('permission_promoted',lambda p:p['scope'].update(runtime_permission=True))
 add('gate_opened_claim',lambda p:p['scope'].update(gate_openings='complete'))
 add('entry_mask',lambda p:p['entries'][0].update(mask=0))
 add('entry_backface',lambda p:p['entries'][0].update(backface_collision=False))
 add('counts',lambda p:p['counts'].update(colliders=684))
 results=[]
 with tempfile.TemporaryDirectory(prefix='sim2seoul-p04-reject-') as tmp:
  game=Path(tmp)/'game'
  for n in [*FILES,*ASSETS]:
   p=game/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/n,p)
  for name,broken in cases:
   (game/'resources/collision/generated.json').write_text(json.dumps(broken,ensure_ascii=False,separators=(',',':'))+'\n')
   result=output/(name+'.json');log=output/(name+'.log')
   cmd=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine),'--headless','--path',str(game),'--script',str(ROOT/'tests/game/check_collision_rejection.gd'),'--log-file',str(log),'--','--result='+str(result)]
   ran=subprocess.run(cmd,capture_output=True,text=True,timeout=15)
   if 'ERROR:' in ran.stdout+ran.stderr or 'SCRIPT ERROR' in ran.stdout+ran.stderr or not result.exists():raise ValueError(name+' did not produce clean rejection')
   r=json.loads(result.read_text());ok=ran.returncode==0 and r['accepted'] is False and r['colliders_created']==0 and bool(r['error']);results.append({'case':name,'passed':ok,'engine_evidence':str(result.relative_to(output))});print('P04 runtime reject',name,ok,flush=True)
 passed=all(r['passed'] for r in results) and original.read_bytes()==content
 report={'task':'P04','passed':passed,'cases':results,'original_unchanged':original.read_bytes()==content,'source_collision_sha256':hashlib.sha256(content).hexdigest(),'probe_sha256':hashlib.sha256((ROOT/'tests/game/check_collision_rejection.gd').read_bytes()).hexdigest(),'driver_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'10 actual runtime-plan rejection cases; separate from 10 actual geometry/configuration faults and checker evidence mutations'}
 (output/'rejection_check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');return 0 if passed else 1
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'data/cache/collision_rejections');p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'));a=p.parse_args();raise SystemExit(main(a.output,a.engine))

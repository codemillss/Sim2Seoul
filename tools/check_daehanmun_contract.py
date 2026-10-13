#!/usr/bin/env python3
"""W01 engine observations from an isolated offline runtime-only game copy."""
import argparse,hashlib,json,re,shutil,subprocess,tempfile
from pathlib import Path
from check_collision_contract import FILES as P04_FILES, ASSETS as P04_ASSETS
ROOT=Path(__file__).resolve().parents[1]
# P04 fixture source is preserved, but W01 does not instantiate it.
FILES=[*P04_FILES,'scripts/daehanmun_connection.gd','scripts/daehanmun_walk.gd','scripts/player/daehanmun_player.gd','scenes/world/daehanmun_connection.tscn','scenes/tests/daehanmun_walk.tscn']
ASSETS=[*P04_ASSETS,'data/generated/daehanmun.json','data/generated/daehanmun_decision.json','data/generated/daehanmun_manifest.json']
FAULTS=['gate_blocked','wall_removed','support_disabled','player_mask_zero','camera_mask_zero','wrong_gate_transform']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def put(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n')
def main(engine,output,mode):
 checker_path=ROOT/"tools/check_daehanmun_evidence.py"
 checker_bytes=checker_path.read_bytes(); checker_namespace={"__name__":"w01_checker_snapshot","__file__":str(checker_path)}
 exec(compile(checker_bytes,str(checker_path),"exec"),checker_namespace);audit=checker_namespace["audit"]
 proof_scripts={p:sha(ROOT/p) for p in ["tests/game/check_daehanmun_walk.gd","tests/game/daehanmun_probe_input.gd","tests/game/check_camera_test.gd","tools/check_daehanmun_evidence.py","tools/check_daehanmun_contract.py"]}
 from check_daehanmun_bundle import check as preflight
 preflight(ROOT);output=output.resolve();output.mkdir(parents=True,exist_ok=True)
 sources={p:sha(ROOT/'game'/p) for p in FILES};assets={p:sha(ROOT/'game'/p) for p in ASSETS}
 plan=json.loads((ROOT/'game/data/generated/daehanmun.json').read_text());world=json.loads((ROOT/'game/resources/world_geometry/world.json').read_text());features=json.loads((ROOT/'data/processed/features.json').read_text());checks=[]
 def ck(n,ok,**details):checks.append({'name':n,'passed':bool(ok),**details})
 ck('engine.version',subprocess.check_output([str(engine),'--version'],text=True).strip()=='4.7.2.stable.official.ed1daf0bf')
 with tempfile.TemporaryDirectory(prefix='sim2seoul-w01-') as tmp:
  game=Path(tmp)/'game'
  for p in FILES+ASSETS:
   target=game/p;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/p,target)
  helper=game/'test_support/check_camera_test.gd';helper.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'tests/game/check_camera_test.gd',helper)
  shutil.copy2(ROOT/'tests/game/daehanmun_probe_input.gd',game/'test_support/daehanmun_probe_input.gd')
  ck('copy.runtime_only',not (game/'.godot').exists() and not (game/'data/raw').exists(),authored_files=len(FILES),runtime_files=len(ASSETS),test_helper='original P03 producer byte copy plus W01 test-only external-event filter')
  def run(label,fault='normal',gpu=False,fps=60):
   result=output/(label+'.json');log=output/(label+'.log');result.parent.mkdir(parents=True,exist_ok=True)
   if result.exists():result.unlink()  # A missing fresh result must never reuse an older record.
   cmd=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine)]
   if not gpu:cmd+=['--headless','--fixed-fps','60']
   cmd+=['--path',str(game),'--script',str(ROOT/'tests/game/check_daehanmun_walk.gd'),'--log-file',str(log),'--','--automatic-probe','--result='+str(result),'--suite='+('gpu' if gpu else 'full'),'--case='+fault,'--render-fps='+str(fps)]
   if gpu:cmd+=['--capture-prefix='+str(output/('view' if fps==60 else 'view_30'))]
   ran=subprocess.run(cmd,capture_output=True,text=True,timeout=330 if gpu else 120)
   messages=re.sub(r'\x1b\[[0-9;]*m','',ran.stdout+ran.stderr)
   if ran.returncode or 'ERROR:' in messages or 'SCRIPT ERROR' in messages or not result.exists():raise ValueError('W01 engine failure:'+label+':'+messages[-2000:])
   raw=json.loads(result.read_text());scored=audit(raw,plan,world,features);ck(label+'.plan_hash',raw['plan_sha256']==sha(ROOT/'game/data/generated/daehanmun.json'))
   put(output/(label+'_check.json'),scored);print('W01',label,scored['passed'],'checks',len(scored['checks']),flush=True)
   if not scored['passed']:print('FAILED',[(c['name'],c.get('details')) for c in scored['checks'] if not c['passed']][:12],flush=True)
   return raw,scored
  faults=[]
  if mode=='contract':
   raw,sc=run('headless_engine');ck('normal.full',sc['passed'],count=len(sc['checks']))
   repeated,sc=run('repeat_engine');ck('repeat.full',sc['passed'],count=len(sc['checks']))
   ck('repeat.inventory',raw['inventory']==repeated['inventory']);ck('repeat.paths',all(a['samples']==b['samples'] for a,b in zip(raw['cases'],repeated['cases'])))
   for fault in FAULTS:
    _,sc=run('regression/'+fault,fault);failed=[c['name'] for c in sc['checks'] if not c['passed']];ck('actual_fault.'+fault,not sc['passed'] and bool(failed));faults.append({'fault':fault,'checker_passed':sc['passed'],'failed_checks':failed})
  else:
   for fps in ([30,60] if mode=='gpu' else [int(mode[-2:])]):
    _,sc=run('gpu_'+str(fps)+'_engine',gpu=True,fps=fps);ck('gpu.'+str(fps),sc['passed'],count=len(sc['checks']))
  ck('inputs_unchanged',sources=={p:sha(ROOT/'game'/p) for p in FILES} and assets=={p:sha(ROOT/'game'/p) for p in ASSETS} and proof_scripts=={p:sha(ROOT/p) for p in proof_scripts})
 d={'task':'W01','mode':mode,'passed':all(c['passed'] for c in checks),'checks':checks,'sources':sources,'runtime_assets':assets,'probe_sha256':proof_scripts['tests/game/check_daehanmun_walk.gd'],'parent_probe_sha256':proof_scripts['tests/game/check_camera_test.gd'],'checker_sha256':hashlib.sha256(checker_bytes).hexdigest(),'driver_sha256':proof_scripts['tools/check_daehanmun_contract.py'],'actual_faults':faults,'test_input_guard_sha256':proof_scripts['tests/game/daehanmun_probe_input.gd'],'network':'deny network*','scope':'Automatic W01 connection movement, isolated local runtime-only copy on existing M1; no source maps or starting cache','not_tested':['surveyed gate/terrain/real access','human handling/OS focus','M4','full R1/R2/R3 and W0/V0','NPC/vehicle controllers','city performance']}
 put(output/(mode+'_check.json'),d);print('W01 driver',d['passed'],len(checks),flush=True);return 0 if d['passed'] else 1
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'));p.add_argument('--output',type=Path,default=ROOT/'data/cache/daehanmun_contract');p.add_argument('--mode',choices=['contract','gpu','gpu30','gpu60'],default='contract');a=p.parse_args();raise SystemExit(main(a.engine,a.output,a.mode))

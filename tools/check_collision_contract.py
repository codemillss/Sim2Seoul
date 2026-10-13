#!/usr/bin/env python3
"""P04 actual offline engine tests in a copied game with city runtime assets."""
import argparse,hashlib,json,re,shutil,subprocess,tempfile
from pathlib import Path
from check_camera_contract import FILES as P03_FILES
ROOT=Path(__file__).resolve().parents[1]
FILES=[*P03_FILES,'scenes/world/base_world.tscn','scripts/base_world.gd','resources/world_config.tres','scripts/world_config.gd','scenes/world/collision_world.tscn','scripts/collision_world.gd','scenes/tests/collision_test.tscn','scripts/collision_test.gd','resources/collision/rules.json']
ASSETS=['data/generated/region.json','data/generated/manifest.json','resources/world_geometry/world.json','resources/collision/generated.json']
FAULTS=['player_mask_zero','fixture_wall_disabled','camera_all_layers','city_layer_wrong','city_shape_disabled','city_shape_missing','city_transform_shift','city_faces_shift','display_collision_added','hole_blocked']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def put(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n')
def main(engine,output,mode):
 from check_collision_evidence import audit
 output=output.resolve();output.mkdir(parents=True,exist_ok=True)
 sources={p:sha(ROOT/'game'/p) for p in FILES};assets={p:sha(ROOT/'game'/p) for p in ASSETS};world=json.loads((ROOT/'game/resources/world_geometry/world.json').read_text());plan=json.loads((ROOT/'game/resources/collision/generated.json').read_text());features=json.loads((ROOT/'data/processed/features.json').read_text());checks=[]
 def check(n,ok,**d):checks.append({'name':n,'passed':bool(ok),**d})
 check('engine.version',subprocess.check_output([str(engine),'--version'],text=True).strip()=='4.7.2.stable.official.ed1daf0bf')
 with tempfile.TemporaryDirectory(prefix='sim2seoul-p04-') as tmp:
  game=Path(tmp)/'game'
  for p in [*FILES,*ASSETS]:
   target=game/p;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/p,target)
  helper=game/'test_support/check_camera_test.gd';helper.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'tests/game/check_camera_test.gd',helper)
  check('copy.authored_runtime_only',not (game/'.godot').exists() and not (game/'.venv-data').exists(),authored_files=len(FILES),runtime_files=len(ASSETS),test_helper_copy='P03 producer bytes')
  def run(label,fault='normal',gpu=False,fps=60):
   result=output/(label+'.json');log=output/(label+'.log');result.parent.mkdir(parents=True,exist_ok=True)
   cmd=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine)]
   if not gpu:cmd+=['--headless','--fixed-fps','60']
   cmd+=['--path',str(game),'--script',str(ROOT/'tests/game/check_collision_test.gd'),'--log-file',str(log),'--','--automatic-probe','--result='+str(result),'--suite='+('gpu' if gpu else 'full'),'--render-fps='+str(fps),'--fault='+fault]
   if gpu and fps==60:cmd+=['--capture-prefix='+str(output/'view')]
   proc=subprocess.run(cmd,capture_output=True,text=True,timeout=210 if gpu else 45)
   messages=re.sub(r'\x1b\[[0-9;]*m','',proc.stdout+proc.stderr)
   if proc.returncode or 'ERROR:' in messages or 'SCRIPT ERROR' in messages or not result.exists():raise ValueError('P04 actual engine failed '+label+':'+messages[:1800])
   record=json.loads(result.read_text());scored=audit(record,world,plan,features);put(output/(label+'_check.json'),scored)
   print('P04',label,'passed=',scored['passed'],'checks=',len(scored['checks']),flush=True)
   return record,scored
  mutations=[]
  if mode=='contract':
   normal,scored=run('headless_engine');check('normal.full',scored['passed'],checks=len(scored['checks']))
   repeat,scored=run('repeat_engine');check('repeat.full',scored['passed'])
   check('repeat.city_inventory',normal['city']['inventory']==repeat['city']['inventory'])
   check('repeat.paths',all(normal['camera_fixture']['cases'][i]['samples']==repeat['camera_fixture']['cases'][i]['samples'] for i in range(30)))
   for fault in FAULTS:
    _,scored=run('regression/'+fault,fault=fault);failed=[c['name'] for c in scored['checks'] if not c['passed']]
    check('regression.'+fault,not scored['passed'] and bool(failed));mutations.append({'case':fault,'checker_passed':scored['passed'],'failed_checks':failed})
  else:
   for fps in (30,60):
    _,scored=run('gpu_'+str(fps)+'_engine',gpu=True,fps=fps);check('gpu.'+str(fps),scored['passed'],checks=len(scored['checks']))
  check('inputs_unchanged',sources=={p:sha(ROOT/'game'/p) for p in FILES} and assets=={p:sha(ROOT/'game'/p) for p in ASSETS})
 report={'task':'P04','mode':mode,'passed':all(c['passed'] for c in checks),'checks':checks,'sources':sources,'runtime_assets':assets,'probe_sha256':sha(ROOT/'tests/game/check_collision_test.gd'),'parent_probe_sha256':sha(ROOT/'tests/game/check_camera_test.gd'),'checker_sha256':sha(ROOT/'tools/check_collision_evidence.py'),'driver_sha256':sha(Path(__file__)),'actual_mutations':mutations,'network':'deny network*','scope':'Copied authored game plus E03/P04 local runtime assets; no source maps, country data, Python packages or starting engine cache','not_tested':['city free walking/routes/Daehanmun opening','permission/terrain/geographical accuracy','real NPC/vehicle route/controllers','human handling','OS-driven focus changes','M4','city performance','W0/V0']}
 put(output/(mode+'_check.json'),report);print('P04',mode,'passed=',report['passed'],'checks=',len(checks),flush=True);return 0 if report['passed'] else 1
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'));p.add_argument('--output',type=Path,default=ROOT/'data/cache/collision_contract');p.add_argument('--mode',choices=['contract','gpu'],default='contract');a=p.parse_args();raise SystemExit(main(a.engine,a.output,a.mode))

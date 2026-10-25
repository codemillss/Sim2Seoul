#!/usr/bin/env python3
"""Source-bound run of the same EXP36 refinement scene; no art score is inferred."""
import argparse,datetime,hashlib,json,os,shutil,subprocess,sys,time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('mode',choices=['headless','native']);p.add_argument('tag')
opts=p.parse_args()
if not opts.tag.replace('_','').replace('-','').isalnum():p.error('simple fresh tag required')
base=ROOT/'data/reports/resident_form_refinement/20261025'/('refinement_'+opts.mode+'_'+opts.tag)
if any(base.parent.glob(base.name+'*')):p.error('existing evidence is never overwritten')
base.parent.mkdir(parents=True,exist_ok=True)
def sha(q):return hashlib.sha256(q.read_bytes()).hexdigest()
def sources():
 paths=list((ROOT/'tools/sculpted_character').glob('*.py'))+[Path(__file__),ROOT/'tests/game/check_resident_form_study.gd',ROOT/'game/project.godot',ROOT/'game/scripts/explore_walk.gd']
 paths+=list((ROOT/'game/scripts/study').glob('*.gd'))+list((ROOT/'game/scenes/study').glob('*.tscn'))
 paths+=list((ROOT/'game/assets/original/resident_study').glob('*'))+[ROOT/'art/characters/resident_form_m01.blend']
 return {q.relative_to(ROOT).as_posix():sha(q) for q in sorted(set(paths)) if q.is_file()}
before=sources()
snapshots=base.parent/(base.name+'_source')
for name in before:
 q=ROOT/name
 if q.suffix in ['.py','.gd','.tscn','.import','.json','.godot']:
  target=snapshots/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(q,target)
start=time.monotonic();started=datetime.datetime.now(datetime.timezone.utc).isoformat()
argv=[os.environ.get('SIM2SEOUL_GODOT','/Applications/Godot.app/Contents/MacOS/Godot')]
if opts.mode=='headless':argv+=['--headless']
argv+=['--path',str(ROOT/'game'),'--log-file',str(base)+'.log','--script','res://../tests/game/check_resident_form_study.gd','--','--automatic-probe','--report='+str(base)+'.json']
try:
 result=subprocess.run(argv,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 actual=result.returncode;output=result.stdout.decode(errors='replace')
except subprocess.TimeoutExpired as e:
 actual=None;output=(e.output or b'').decode(errors='replace')
Path(str(base)+'.console.log').write_text(output)
errors=[s for s in output.splitlines() if 'ERROR:' in s or 'Parse Error:' in s or 'Failed to load script' in s]
after=sources();changed=[s for s in before.keys()|after.keys() if before.get(s)!=after.get(s)]
report=Path(str(base)+'.json');expected=73 if opts.mode=='headless' else 109
expected_captures=0 if opts.mode=='headless' else 32
data=json.loads(report.read_text()) if report.exists() else {};checks=data.get('checks',[])
captures=data.get('captures',[]);capture_errors=[]
for capture in captures:
 q=Path(capture.get('file',''))
 if not q.is_file() or not q.resolve().is_relative_to(base.parent.resolve()):
  capture_errors.append('missing or out-of-report capture: '+str(q));continue
 if not q.read_bytes().startswith(b'\x89PNG\r\n\x1a\n') or sha(q)!=capture.get('sha256'):
  capture_errors.append('capture format/hash mismatch: '+str(q))
code=0 if actual==0 and not errors and not changed and data.get('task')=='EXP36_RESIDENT_FORM_REFINEMENT' and len(checks)==expected and all(s.get('passed') is True for s in checks) and len(captures)==expected_captures and not capture_errors and data.get('source_sha256')==data.get('source_after') else 2
meta={'task':'EXP36_FORM_REFINEMENT','mode':opts.mode,'argv':argv,'started_at_utc':started,'wall_seconds':round(time.monotonic()-start,3),'actual_engine_returncode':actual,'returncode':code,'engine_errors':errors,'expected_checks':expected,'actual_checks':len(checks),'expected_captures':expected_captures,'actual_captures':len(captures),'capture_errors':capture_errors,'source_sha256':before,'text_source_snapshot':snapshots.relative_to(ROOT).as_posix(),'source_changes_during_run':changed,'scope':'Source/capture/functional integrity only. Human form quality needs actual pixel review; not a realistic-character acceptance.'}
Path(str(base)+'.run.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS' if code==0 else 'FAIL','report':report.relative_to(ROOT).as_posix(),'actual_exit':actual,'checks':len(checks),'failed':[s['name'] for s in checks if not s.get('passed')],'errors':errors,'source_changed':changed,'captures':len(captures),'capture_errors':capture_errors},ensure_ascii=False))
if code:print(output[-3500:])
sys.exit(code)

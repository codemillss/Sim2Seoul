#!/usr/bin/env python3
"""W01 regeneration from copied, already-prepared small G/E03/P04 inputs."""
import argparse,hashlib,json,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main(report):
 connection=ROOT/'game/data/generated/daehanmun.json';original=sha(connection)
 world=json.loads((ROOT/'game/resources/world_geometry/world.json').read_text());plan=json.loads(connection.read_text())
 inputs=set(plan['provenance'])|{e['file'] for e in world['provenance']['inputs']}|{'data/reports/coordinate_check.json'}
 # Copy importable preparers and small runtime inputs, not environments/starting caches.
 inputs|={str(p.relative_to(ROOT)) for p in (ROOT/'tools').glob('*.py')}
 inputs|={'game/data/generated/region.json','game/data/generated/manifest.json','game/resources/collision/rules.json','game/resources/collision/generated.json'}
 with tempfile.TemporaryDirectory(prefix='sim2seoul-w01-portable-') as tmp:
  copied=Path(tmp)
  for p in sorted(inputs):
   target=copied/p;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,target)
  results=[]
  for _ in range(2):
   ran=subprocess.run([str(ROOT/'.venv-data/bin/python'),str(copied/'tools/prepare_daehanmun.py')],capture_output=True,text=True,check=True)
   results.append(sha(copied/'game/data/generated/daehanmun.json'))
  passed=results==[original,original] and original==sha(connection) and not (copied/'.venv-data').exists() and not (copied/'game/.godot').exists() and not (copied/'data/raw/geofabrik').exists()
 d={'task':'W01','passed':passed,'connection_sha256':original,'two_generations_sha256':results,'copied_inputs':{p:sha(ROOT/p) for p in sorted(inputs)},'scope':'W01-only regeneration from already-prepared small G/E03/P04 inputs using current M1 existing venv interpreter. No country data, whole DSM, venv/cache copied; not full G rebuild/new installation/M4.'}
 report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n');print('W01 portability',passed,'copied_files',len(inputs));return 0 if passed else 1
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,default=ROOT/'data/cache/daehanmun_portability.json');a=p.parse_args();raise SystemExit(main(a.report))

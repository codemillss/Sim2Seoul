#!/usr/bin/env python3
"""Rebuild only N01 from prepared inputs in a relocated, cache-free copy."""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from prepare_routes import INPUTS, OUTPUTS
from check_routes import audit

ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())

def main():
    public=read(ROOT/'game/data/generated/public_walk.json')
    paths=sorted(set(INPUTS)|set(public['provenance'])|{'tools/check_routes.py'})
    before={p:sha(ROOT/p) for p in paths}
    checks=[]
    def ck(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
    reference={p:sha(ROOT/p) for p in OUTPUTS}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n01-') as temp:
        copy=Path(temp)/'prepared-copy'
        for p in paths:
            dest=copy/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
        ck('prepared_inputs_only',not (copy/'.venv-data').exists() and not (copy/'game/.godot').exists()
           and len(list((copy/'data/raw').rglob('*.pbf')))==1)
        runs=[]
        for iteration in range(2):
            if iteration==1:
                relocated=Path(temp)/'relocated-copy';copy.rename(relocated);copy=relocated
                for p in OUTPUTS:(copy/p).unlink()
            result=subprocess.run([sys.executable,'-I','-B',str(copy/'tools/prepare_routes.py'),'--root',str(copy)],
                                  cwd=copy,capture_output=True,text=True,timeout=60)
            ck('run_'+str(iteration)+'.exit',result.returncode==0,messages=(result.stdout+result.stderr)[-1000:])
            observed={p:sha(copy/p) for p in OUTPUTS}
            runs.append(observed)
            ck('run_'+str(iteration)+'.identical_outputs',observed==reference)
            ck('run_'+str(iteration)+'.independent_audit',audit(copy,*[read(copy/p) for p in OUTPUTS])['passed'])
        ck('relocated_repeat_equal',runs[0]==runs[1])
        manual=copy/'data/manual/urban_routes.json';original=manual.read_bytes();plan=read(manual)
        trials=[]
        bad=__import__('copy').deepcopy(plan);bad['policy']['max_observation_age_s']=10
        trials.append(('stale_observation_allowed',bad,'Unsafe human priority or observation guard'))
        bad=__import__('copy').deepcopy(plan);bad['policy']['priority'].reverse()
        trials.append(('vehicles_before_humans',bad,'Unsafe human priority or observation guard'))
        bad=__import__('copy').deepcopy(plan);bad['policy']['vehicle_recycle']['both_portals_outside_actual_camera_frustum']=False
        trials.append(('visible_recycling_allowed',bad,'Unsupported vehicle recycle guard'))
        bad=__import__('copy').deepcopy(plan);bad['vehicle_routes'][0]['lane_index_zero_based_from_left']=4.01
        bad['vehicle_routes'][0]['right_offset_m']=(4.01+.5-4)*3.2
        trials.append(('fractional_lane_index',bad,'Lane index must be an integer'))
        for name,bad,reason in trials:
            try:
                manual.write_text(json.dumps(bad,ensure_ascii=False,indent=2)+'\n')
                result=subprocess.run([sys.executable,'-I','-B',str(copy/'tools/prepare_routes.py'),'--root',str(copy)],cwd=copy,capture_output=True,text=True,timeout=60)
                ck('reject.'+name,result.returncode!=0 and reason in result.stderr,error=result.stderr.splitlines()[-1])
            finally:manual.write_bytes(original)
        for name,path,reason,args in [
            ('stale_source','data/processed/features.json','Stale W03 source/proof binding',[]),
            ('stale_output',OUTPUTS[0],'Stale N01 output',['--check'])]:
            file=copy/path;original=file.read_bytes()
            try:
                file.write_bytes(original+b'\n')
                result=subprocess.run([sys.executable,'-I','-B',str(copy/'tools/prepare_routes.py'),'--root',str(copy),*args],cwd=copy,capture_output=True,text=True,timeout=60)
                ck('reject.'+name,result.returncode!=0 and reason in result.stderr,error=result.stderr.splitlines()[-1])
            finally:file.write_bytes(original)

        ck('copied_inputs_unchanged',before=={p:sha(copy/p) for p in paths})
    ck('original_inputs_unchanged',before=={p:sha(ROOT/p) for p in paths})
    report={'task':'N01','passed':all(c['passed'] for c in checks),'checks':checks,'prepared_files':len(paths),
            'prepared_bytes':sum((ROOT/p).stat().st_size for p in paths),'input_sha256':before,'output_sha256':reference,
            'scope':'Current M1 existing Python/Shapely; N01-only rebuild from prepared inputs, no install/full GIS/Godot/network/M4 test'}
    output=ROOT/'data/reports/n01/portability.json';output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('N01 portability',report['passed'],len(checks),'checks',len(paths),'prepared files')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

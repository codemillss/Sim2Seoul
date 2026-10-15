#!/usr/bin/env python3
"""N03 offline actual traffic scene tests in a runtime-only copy."""
import argparse
import copy
import gzip
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_pedestrians_contract import ROOT, FILES as BASE_FILES, ASSETS as BASE_ASSETS, HELPERS as BASE_HELPERS, sha, read, write, archive
from check_city_landmarks_evidence import audit as audit_city
from check_palace_landmarks_evidence import audit as audit_palace

FILES=[*BASE_FILES,'scripts/traffic/vehicle.gd','scripts/traffic/traffic_manager.gd','scripts/traffic_walk.gd',
       'scenes/npc/vehicle.tscn','scenes/world/traffic_walk.tscn','resources/collision/traffic_rules.json']
ASSETS=[*BASE_ASSETS,'data/generated/traffic.json','data/generated/traffic_manifest.json']
HELPERS=[*BASE_HELPERS,'tests/game/check_pedestrians.gd']
PROOF=['tools/prepare_traffic.py','tools/check_vehicles_contract.py','tools/check_vehicles_evidence.py',
       'tests/game/check_vehicles.gd','tools/run_traffic.sh']


def main(output,mode,engine):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    subprocess.run([str(ROOT/'.venv-data/bin/python'),str(ROOT/'tools/prepare_traffic.py'),'--check'],check=True)
    bundle=read(ROOT/'game/data/generated/traffic.json')
    source={p:sha(ROOT/'game'/p) for p in FILES}
    assets={p:sha(ROOT/'game'/p) for p in ASSETS}
    inputs={p:sha(ROOT/p) for p in bundle['source_sha256']}
    proof={p:sha(ROOT/p) for p in PROOF if (ROOT/p).exists()}
    checks=[]
    def ck(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
    ck('engine.version',subprocess.check_output([str(engine),'--version'],text=True).strip()=='4.7.2.stable.official.ed1daf0bf')
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n03-') as temporary:
        game=Path(temporary)/'game'
        for p in FILES+ASSETS:
            dest=game/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/p,dest)
        for p in HELPERS:
            dest=game/'test_support'/Path(p).name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
        ck('runtime_only',not (game/'.godot').exists() and not (game/'data/raw').exists())
        def run(label,gpu=False,suite='full',fault='normal',rejection=False):
            result=Path(temporary)/(label+'.json');log=output/(label+'.log')
            command=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine)]
            if not gpu:command+=['--headless','--fixed-fps','60']
            command+=['--path',str(game),'--script',str(ROOT/'tests/game/check_vehicles.gd'),'--log-file',str(log),'--',
                      '--automatic-probe','--result='+str(result),'--suite='+suite,'--case='+fault,'--render-fps=60']
            if gpu:command+=['--capture-prefix='+str(output/(label+'_view'))]
            try:ran=subprocess.run(command,capture_output=True,text=True,timeout=1200 if gpu else 300)
            except subprocess.TimeoutExpired as exc:
                write(output/(label+'_failure.json'),{'timeout':exc.timeout,'fresh_result':result.exists()});raise
            messages=re.sub(r'\x1b\[[0-9;]*m','',ran.stdout+ran.stderr)
            if result.exists():archive(output/(label+'.json.gz'),read(result))
            if ran.returncode or (not rejection and 'ERROR:' in messages+log.read_text(errors='replace')) or not result.exists():
                write(output/(label+'_failure.json'),{'returncode':ran.returncode,'fresh_result':result.exists(),'messages':messages[-7000:]})
                raise RuntimeError('N03 engine failed '+label+'\n'+messages[-5000:])
            record=read(result)
            if rejection:
                rejected=record.get('rejected') is True and record.get('vehicle_count')==record.get('support_count')==0
                write(output/(label+'_check.json'),{'task':'N03','passed':rejected,'checks':[
                    {'name':'rejected_before_actors_or_supports','passed':rejected}], 'reason':record.get('reason')})
                ck(label+'.rejected',rejected,reason=record.get('reason'))
                return record,None
            if mode=='smoke':
                ck(label+'.ready',record.get('task')=='N03' and len(record['descriptors'])==2)
                print('N03 smoke cases',[(c['name'],c['stats']) for c in record['cases']],flush=True)
                return record,None
            from check_vehicles_evidence import audit
            scored=audit(record,bundle,read(ROOT/'game/data/generated/public_walk.json'),read(ROOT/'game/resources/world_geometry/world.json'),read(ROOT/'game/data/generated/daehanmun.json'))
            write(output/(label+'_vehicles_check.json'),scored)
            spec=read(ROOT/'data/processed/landmark_spec.json');w01=read(ROOT/'game/data/generated/daehanmun.json')
            city_bundle=read(ROOT/'game/data/generated/city_landmarks.json')
            city=audit_city(record['city_visuals'],city_bundle,spec,w01)
            palace_raw=copy.deepcopy(record['palace_visuals'])
            for identity in city_bundle['hidden_mesh_ids']:palace_raw['all_source_visibility'][identity]=True
            palace=audit_palace(palace_raw,read(ROOT/'game/data/generated/palace_landmarks.json'),spec,w01)
            write(output/(label+'_city_check.json'),city);write(output/(label+'_palace_check.json'),palace)
            ck(label+'.city_retained',city['passed']);ck(label+'.palace_retained',palace['passed'])
            print('N03',label,scored['passed'],len(scored['checks']),[c['name'] for c in scored['checks'] if not c['passed']][:35],flush=True)
            return record,scored
        short=mode in ('smoke','short','gpu_short')
        record,scored=run(mode,gpu=mode in ('gpu','gpu_short'),suite='short' if short else 'full')
        if scored is not None:
            ck(mode+'.vehicles',scored['passed'] if not short else all(c['passed'] for c in scored['checks'] if c['name']!='acceptance.full_suite'))
        if mode=='contract' and scored is not None and scored['passed']:
            from check_vehicles_evidence import audit
            public=read(ROOT/'game/data/generated/public_walk.json')
            world=read(ROOT/'game/resources/world_geometry/world.json')
            w01=read(ROOT/'game/data/generated/daehanmun.json')
            faulty_record,faulty=run('fault_vehicle_mask',suite='short',fault='vehicle_mask')
            failed=[c['name'] for c in faulty['checks'] if not c['passed']]
            # The fault is injected after descriptors are captured. Require the
            # actual retained actor mask and independent sample check to expose it;
            # a short suite's generic acceptance failure is insufficient.
            mask_observed=any(v['route_id']=='sejong_south' and v['mask']!=31
                for case in faulty_record['cases'] for sample in case['samples'] for v in sample['vehicles'])
            ck('fault.actual_engine_mask_rejected',not faulty['passed'] and mask_observed
               and 'free_cycles.independent_samples' in failed,failed_checks=failed)

            def paused_position(changed):
                case=next(c for c in changed['cases'] if c['name']=='manual_stop')
                case['samples'][1]['vehicles'][0]['position'][0]+=1.
                return 'manual_stop.no_motion'

            def recycle_guard(changed):
                for case in changed['cases']:
                    for vehicle in case['end']:
                        for event in vehicle['recycle_history']:
                            if event['guard']['allowed']:
                                event['guard']['start_outside']=False
                                return case['name']+'.'+vehicle['route_id']+'.guarded_reentry_tick_'+str(event['tick'])
                raise ValueError('Full positive record has no allowed recycle guard')

            for name,mutate in (
                ('missing_case',lambda r:(r['cases'].pop(),'cases.complete_unique')[1]),
                ('descriptor_clone',lambda r:(r['descriptors'].append(copy.deepcopy(r['descriptors'][0])),'actors.count_and_routes')[1]),
                ('missing_sample',lambda r:(r['cases'][0]['samples'].pop(1),'free_cycles.retained_sampling')[1]),
                ('paused_car_moved',paused_position),
                ('allowed_recycle_guard',recycle_guard),
            ):
                changed=copy.deepcopy(record)
                target=mutate(changed)
                archive(output/('fault_'+name+'.json.gz'),changed)
                rejected=audit(changed,bundle,public,world,w01)
                write(output/('fault_'+name+'_check.json'),rejected)
                failed=[c['name'] for c in rejected['checks'] if not c['passed']]
                ck('fault.retained_'+name,not rejected['passed'] and target in failed,
                   targeted_check=target,failed_checks=failed)

            bundle_path=game/'data/generated/traffic.json'
            manifest_path=game/'data/generated/traffic_manifest.json'
            original_bundle=bundle_path.read_bytes()
            original_manifest=manifest_path.read_bytes()
            try:
                for fault in ('checksum','route_clone','coordinates','stale_runtime_binding'):
                    bundle_path.write_bytes(original_bundle)
                    manifest_path.write_bytes(original_manifest)
                    changed=read(bundle_path);manifest=read(manifest_path)
                    if fault=='checksum':
                        bundle_path.write_bytes(original_bundle+b' ')
                    elif fault=='stale_runtime_binding':
                        manifest['runtime_sha256']['res://data/generated/public_walk.json']='0'*64
                        write(manifest_path,manifest)
                    else:
                        if fault=='route_clone':changed['routes'][1]=copy.deepcopy(changed['routes'][0])
                        else:changed['coordinate_system']['units']='centimetres'
                        write(bundle_path,changed)
                        manifest['file']['sha256']=sha(bundle_path)
                        manifest['file']['bytes']=bundle_path.stat().st_size
                        write(manifest_path,manifest)
                    label='loader_'+fault
                    # Preserve exact corrupted bytes, including the checksum-only
                    # whitespace mutation, alongside every raw rejection/check.
                    for suffix,path in (('bundle',bundle_path),('manifest',manifest_path)):
                        (output/(label+'_input_'+suffix+'.json.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
                    rejected,_=run(label,suite='short',rejection=True)
                    reason='차량 자료 체크섬이 다릅니다.' if fault=='checksum' else (
                        '차량 원천/충돌 자료가 다릅니다.' if fault=='stale_runtime_binding' else '지원하지 않는 차량 경로/설정입니다.')
                    ck(label+'.targeted_reason',rejected.get('reason')==reason,reason=rejected.get('reason'))
            finally:
                bundle_path.write_bytes(original_bundle)
                manifest_path.write_bytes(original_manifest)
        ck('source_unchanged',source=={p:sha(ROOT/'game'/p) for p in FILES})
        ck('runtime_unchanged',assets=={p:sha(ROOT/'game'/p) for p in ASSETS})
        ck('inputs_unchanged',inputs=={p:sha(ROOT/p) for p in inputs})
        ck('proof_unchanged',proof=={p:sha(ROOT/p) for p in proof})
    report={'task':'N03','mode':mode,'passed':all(c['passed'] for c in checks),'checks':checks,'source_sha256':source,'runtime_sha256':assets,'input_sha256':inputs,'proof_sha256':proof,
            'network':'deny network*','scope':'Actual N03 targeted traffic cases; independent scene resets and fixtures recorded; no N04 endurance/human/M4/performance acceptance.'}
    write(output/(mode+'_check.json'),report)
    return 0 if report['passed'] else 1


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'data/cache/n03_contract')
    p.add_argument('--mode',choices=['smoke','short','contract','gpu_short','gpu'],default='contract');p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    a=p.parse_args();raise SystemExit(main(a.output,a.mode,a.engine))

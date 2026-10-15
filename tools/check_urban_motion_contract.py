#!/usr/bin/env python3
"""Run N04 ordinary-input continuous journey in an offline runtime-only copy."""
import argparse
import copy
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_vehicles_contract import ROOT, FILES, ASSETS, HELPERS, PROOF as BASE_PROOF, sha, read, write, archive
from check_city_landmarks_evidence import audit as audit_city
from check_palace_landmarks_evidence import audit as audit_palace

PROOF=[*BASE_PROOF,'tests/game/check_urban_motion.gd','tests/game/urban_motion_guidance.gd',
       'tools/check_urban_motion_contract.py','tools/check_urban_motion_evidence.py']
EXTRA_HELPERS=['tests/game/check_vehicles.gd','tests/game/urban_motion_guidance.gd']


def main(output,mode,engine):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    if (output/(mode+'.json.gz')).exists():raise SystemExit('Use a fresh output folder to preserve earlier evidence.')
    subprocess.run([str(ROOT/'.venv-data/bin/python'),str(ROOT/'tools/prepare_traffic.py'),'--check'],check=True)
    subprocess.run([str(ROOT/'.venv-data/bin/python'),str(ROOT/'tools/prepare_walkable_itinerary.py'),'--check'],check=True)
    source={p:sha(ROOT/'game'/p) for p in FILES};assets={p:sha(ROOT/'game'/p) for p in ASSETS};proof={p:sha(ROOT/p) for p in PROOF}
    checks=[]
    def ck(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
    ck('fixed_engine',subprocess.check_output([str(engine),'--version'],text=True).strip()=='4.7.2.stable.official.ed1daf0bf')
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n04-') as temporary:
        game=Path(temporary)/'game'
        for p in FILES+ASSETS:
            dst=game/p;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/p,dst)
        for p in [*HELPERS,*EXTRA_HELPERS]:
            dst=game/'test_support'/Path(p).name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dst)
        ck('runtime_only',not (game/'.godot').exists() and not (game/'data/raw').exists())
        def run(label,gpu=False,suite='full',fault='normal'):
            result=Path(temporary)/(label+'.json');log=output/(label+'.log')
            command=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine)]
            if not gpu:command+=['--headless','--fixed-fps','60']
            command+=['--path',str(game),'--script',str(ROOT/'tests/game/check_urban_motion.gd'),'--log-file',str(log),'--',
                      '--automatic-probe','--result='+str(result),'--suite='+suite,'--case='+fault,'--render-fps=60']
            if gpu:command+=['--capture-prefix='+str(output/(label+'_view'))]
            try:ran=subprocess.run(command,capture_output=True,text=True,timeout=3600 if gpu else 900)
            except subprocess.TimeoutExpired as exc:
                write(output/(label+'_failure.json'),{'timeout':exc.timeout,'fresh_result':result.exists()});raise
            messages=re.sub(r'\x1b\[[0-9;]*m','',ran.stdout+ran.stderr)
            if result.exists():archive(output/(label+'.json.gz'),read(result))
            if ran.returncode or 'ERROR:' in messages+log.read_text(errors='replace') or not result.exists():
                write(output/(label+'_failure.json'),{'returncode':ran.returncode,'fresh_result':result.exists(),'messages':messages[-8000:]})
                raise RuntimeError('N04 engine failure '+label+'\n'+messages[-5000:])
            record=read(result)
            if mode=='smoke':
                ck(label+'.ready',record['task']=='N04' and len(record['timeline']['end']['vehicles'])==2)
                print('N04 smoke',record.get('error'),record['timeline']['stats'],flush=True);return record,None
            from check_urban_motion_evidence import audit
            scored=audit(record,read(ROOT/'game/data/generated/traffic.json'),read(ROOT/'game/data/generated/walkable_itinerary.json'),
                         read(ROOT/'game/data/generated/public_walk.json'),read(ROOT/'game/resources/world_geometry/world.json'),read(ROOT/'game/data/generated/daehanmun.json'))
            write(output/(label+'_motion_check.json'),scored)
            spec=read(ROOT/'data/processed/landmark_spec.json');w01=read(ROOT/'game/data/generated/daehanmun.json')
            city_bundle=read(ROOT/'game/data/generated/city_landmarks.json')
            city=audit_city(record['city_visuals'],city_bundle,spec,w01)
            palace_raw=copy.deepcopy(record['palace_visuals'])
            for identity in city_bundle['hidden_mesh_ids']:palace_raw['all_source_visibility'][identity]=True
            palace=audit_palace(palace_raw,read(ROOT/'game/data/generated/palace_landmarks.json'),spec,w01)
            write(output/(label+'_city_check.json'),city);write(output/(label+'_palace_check.json'),palace)
            ck(label+'.city_retained',city['passed']);ck(label+'.palace_retained',palace['passed'])
            print('N04',label,scored['passed'],len(scored['checks']),[c['name'] for c in scored['checks'] if not c['passed']][:30],flush=True)
            return record,scored
        short=mode in ('smoke','short','gpu_short')
        record,scored=run(mode,mode in ('gpu','gpu_short'),'short' if short else 'full')
        if scored is not None:ck(mode+'.motion',scored['passed'])
        if mode=='contract' and scored is not None and scored['passed']:
            from check_urban_motion_evidence import audit
            faulty_record,faulty=run('fault_seam_teleport',suite='short',fault='seam_teleport')
            failed=[c['name'] for c in faulty['checks'] if not c['passed']]
            targeted={'timeline.all_tick_summary','timeline.player_continuity'}
            observed=faulty_record.get('fault')=='seam_teleport' and faulty_record['timeline']['stats']['max_player_step_m']>1.
            ck('fault.actual_engine_seam_teleport_rejected',not faulty['passed'] and observed
               and bool(targeted.intersection(failed)),targeted_checks=sorted(targeted.intersection(failed)),failed_checks=failed)

            inputs=[read(ROOT/p) for p in ('game/data/generated/traffic.json',
                'game/data/generated/walkable_itinerary.json','game/data/generated/public_walk.json',
                'game/resources/world_geometry/world.json','game/data/generated/daehanmun.json')]
            normal_path=output/(mode+'.json.gz')
            normal_sha=sha(normal_path)

            def canonical_sha(value):
                payload=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False)
                return hashlib.sha256(payload.encode()).hexdigest()

            def apply_patch(changed,path,operation,new=None):
                parent=changed
                for key in path[:-1]:parent=parent[key]
                key=path[-1]
                old=copy.deepcopy(parent[key]) if operation!='add' else None
                if operation=='remove':del parent[key]
                elif operation=='add':parent.insert(key,copy.deepcopy(new))
                else:parent[key]=copy.deepcopy(new)
                return {'op':operation,'path':'/'+('/'.join(str(k).replace('~','~0').replace('/','~1') for k in path)),
                        'old':old,'new':copy.deepcopy(new)}

            middle=len(record['timeline']['samples'])//2
            crossing_index=next(i for i,e in enumerate(record['exercises']) if e['kind']=='crossing')
            south_index=next(i for i,v in enumerate(record['final_vehicles']) if v['route_id']=='sejong_south')
            recycle_index=next(i for i,e in enumerate(record['final_vehicles'][south_index]['recycle_history']) if e['guard']['allowed'])
            vehicle_rows=record['timeline']['samples'][middle]['vehicles']
            for name,path,operation,new,target in (
                ('missing_walk_leg',('walk','cases',len(record['walk']['cases'])//2),'remove',None,'walk.full334_coverage'),
                ('player_sample_moved',('timeline','samples',middle,'player','position',0),'replace',
                 record['timeline']['samples'][middle]['player']['position'][0]+1.,'timeline.player_continuity'),
                ('missing_crossing_exercise',('exercises',crossing_index),'remove',None,'exercises.three_crossing_and_three_npc_block'),
                ('duplicate_vehicle',('timeline','samples',middle,'vehicles',len(vehicle_rows)),'add',vehicle_rows[0],'evidence_structure'),
                ('invalid_south_recycle_guard',('final_vehicles',south_index,'recycle_history',recycle_index,'guard','start_outside'),
                 'replace',False,'cars.sejong_south.endpoint_and_reentry_geometry'),
            ):
                changed=copy.deepcopy(record)
                patch=apply_patch(changed,path,operation,new)
                # The original compressed record and this exact patch reconstruct
                # each mutation; avoid five complete copies of the large timeline.
                descriptor={'task':'N04','mutation':name,'normal_record':normal_path.name,
                    'normal_raw_gzip_sha256':normal_sha,'changed_canonical_json_sha256':canonical_sha(changed),
                    'canonical_json':{'ensure_ascii':False,'sort_keys':True,'separators':[',',':'],'trailing_newline':False},
                    'patches':[patch],'targeted_check':target}
                write(output/('fault_'+name+'_mutation.json'),descriptor)
                rejected=audit(changed,*inputs)
                write(output/('fault_'+name+'_check.json'),rejected)
                failed=[c['name'] for c in rejected['checks'] if not c['passed']]
                ck('fault.retained_'+name,not rejected['passed'] and target in failed,
                   targeted_check=target,failed_checks=failed)
        ck('source_unchanged',source=={p:sha(ROOT/'game'/p) for p in FILES})
        ck('runtime_unchanged',assets=={p:sha(ROOT/'game'/p) for p in ASSETS})
        ck('proof_unchanged',proof=={p:sha(ROOT/p) for p in proof})
    report={'task':'N04','mode':mode,'passed':all(c['passed'] for c in checks),'checks':checks,'source_sha256':source,'runtime_sha256':assets,'proof_sha256':proof,
            'network':'deny network*','scope':'One continuous N04 input-controlled journey and natural encounters. Warmup and later recovery injections separate; no performance, human or M4 acceptance.'}
    write(output/(mode+'_check.json'),report)
    return 0 if report['passed'] else 1


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'data/cache/n04_contract')
    p.add_argument('--mode',choices=['smoke','short','contract','gpu_short','gpu'],default='contract');p.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    a=p.parse_args();raise SystemExit(main(a.output,a.mode,a.engine))

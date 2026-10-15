#!/usr/bin/env python3
"""L04 checkpoint views and local camera/walking checks; reuse byte-identical L03."""
import argparse
import copy
import gzip
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

import numpy as np
from check_city_landmarks_contract import FILES, ASSETS, HELPERS, PROOF, archive, read, write, sha
from check_city_landmarks_evidence import audit as audit_city
from check_palace_landmarks_evidence import audit as audit_palace
from check_landmark_review_evidence import audit as audit_local

ROOT=Path(__file__).resolve().parents[1]
PLAN='data/manual/landmark_review_plan.json'
NEW_PROOF=[PLAN,'tests/game/check_landmark_review.gd','tools/check_landmark_review.py','tools/check_landmark_review_evidence.py']


def png_pixels(path):
    """Independent PNG decoder for Godot's 8-bit RGB/RGBA diagnostic images."""
    raw=path.read_bytes()
    if raw[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Invalid PNG signature')
    offset=8;packed=bytearray();header=None
    while offset<len(raw):
        size=struct.unpack_from('>I',raw,offset)[0];kind=raw[offset+4:offset+8];data=raw[offset+8:offset+8+size]
        crc=struct.unpack_from('>I',raw,offset+8+size)[0]
        if zlib.crc32(kind+data)&0xffffffff!=crc:raise ValueError('PNG CRC mismatch')
        if kind==b'IHDR':header=struct.unpack('>IIBBBBB',data)
        if kind==b'IDAT':packed.extend(data)
        offset+=size+12
        if kind==b'IEND':break
    width,height,depth,colour,compression,filtering,interlace=header
    if depth!=8 or colour not in (2,6) or compression or filtering or interlace:raise ValueError('Unsupported diagnostic PNG')
    channels=3 if colour==2 else 4;stride=width*channels;stream=zlib.decompress(packed)
    if len(stream)!=height*(stride+1):raise ValueError('PNG scanline length')
    rows=[];previous=bytearray(stride)
    for y in range(height):
        start=y*(stride+1);kind=stream[start];row=bytearray(stream[start+1:start+1+stride])
        for x in range(stride):
            a=row[x-channels] if x>=channels else 0;b=previous[x];c=previous[x-channels] if x>=channels else 0
            if kind==1:value=a
            elif kind==2:value=b
            elif kind==3:value=(a+b)//2
            elif kind==4:
                p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
                value=a if pa<=pb and pa<=pc else b if pb<=pc else c
            elif kind==0:value=0
            else:raise ValueError('Unknown PNG filter')
            row[x]=(row[x]+value)&255
        rows.append(bytes(row));previous=row
    return np.frombuffer(b''.join(rows),dtype=np.uint8).reshape(height,width,channels)


def projection(point,rig):
    delta=[point[k]-rig['camera'][k] for k in range(3)]
    x,y,z=[sum(delta[k]*axis[k] for k in range(3)) for axis in rig['basis']]
    depth=-z;tangent=math.tan(math.radians(rig['fov'])/2)
    return [576+360*x/(depth*tangent),360-360*y/(depth*tangent)]


def main(output,gpu,engine,fault):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    accepted=read(ROOT/'data/reports/landmarks/l03/gpu_check.json')
    checks=[]
    def ck(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
    ck('baseline.accepted_L03_full_GPU',accepted['passed'])
    baseline_manifest=read(ROOT/'data/reports/l03_verification.json')
    baseline_evidence=['gpu.json.gz','gpu_check.json','gpu_walk_check.json','gpu_summary.json']
    evidence_changed=[name for name in baseline_evidence if sha(ROOT/'data/reports/landmarks/l03'/name)!=baseline_manifest['evidence_sha256']['data/reports/landmarks/l03/'+name]]
    ck('baseline.raw_and_verdict_sha256',baseline_manifest['passed'] and not evidence_changed,changed=evidence_changed)
    for key,prefix in [('source_sha256','game/'),('runtime_sha256','game/'),('input_sha256',''),('proof_sha256','')]:
        changed=[p for p,h in accepted[key].items() if sha(ROOT/(prefix+p))!=h]
        ck('baseline.exact_'+key,not changed,files=len(accepted[key]),changed=changed)
    if not all(c['passed'] for c in checks):raise ValueError('L03 changed: full regression evidence cannot be reused')
    plan=read(ROOT/PLAN);spec=read(ROOT/'data/processed/landmark_spec.json')
    world=read(ROOT/'game/resources/world_geometry/world.json');public=read(ROOT/'game/data/generated/public_walk.json')
    w01=read(ROOT/'game/data/generated/daehanmun.json')
    baseline=json.load(gzip.open(ROOT/'data/reports/landmarks/l03/gpu.json.gz','rt'))
    frozen={p:sha(ROOT/p) for p in dict.fromkeys([*PROOF,*NEW_PROOF])}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l04-') as temp:
        game=Path(temp)/'game'
        for p in FILES+ASSETS:
            dest=game/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'game'/p,dest)
        for p in HELPERS:
            dest=game/'test_support'/Path(p).name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
        shutil.copy2(ROOT/PLAN,game/'test_support/landmark_review_plan.json')
        shutil.copy2(ROOT/'data/processed/landmark_spec.json',game/'test_support/landmark_spec.json')
        ck('copy.runtime_only',not (game/'.godot').exists() and not (game/'data/raw').exists())
        result=Path(temp)/'fresh.json';label='gpu' if gpu else 'headless';log=output/(label+'.log')
        command=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine)]
        if not gpu:command+=['--headless','--fixed-fps','60']
        command+=['--path',str(game),'--script',str(ROOT/'tests/game/check_landmark_review.gd'),'--log-file',str(log),'--',
                  '--automatic-probe','--result='+str(result),'--case='+fault,'--render-fps=60']
        if gpu:command+=['--capture-prefix='+str(output/'review')]
        ran=subprocess.run(command,capture_output=True,text=True,timeout=600)
        messages=re.sub(r'\x1b\[[0-9;]*m','',ran.stdout+ran.stderr)
        if ran.returncode or not result.exists() or 'ERROR:' in messages:
            write(output/(label+'_failure.json'),{'returncode':ran.returncode,'messages':messages[-7000:]})
            raise ValueError('L04 engine failed\n'+messages[-5000:])
        record=read(result);archive(output/(label+'.json.gz'),record)
        local=audit_local(record,baseline,public,world,w01,plan)
        write(output/(label+'_local_check.json'),local)
        ck('local.orbits_and_walks',local['passed'])
        if not local['passed']:print('LOCAL_FAILED',[c['name'] for c in local['checks'] if not c['passed']][:20],flush=True)
        city=audit_city(record['city_visuals'],read(ROOT/'game/data/generated/city_landmarks.json'),spec,w01)
        palace_obs=copy.deepcopy(record['palace_visuals'])
        for id in read(ROOT/'game/data/generated/city_landmarks.json')['hidden_mesh_ids']:palace_obs['all_source_visibility'][id]=True
        palace=audit_palace(palace_obs,read(ROOT/'game/data/generated/palace_landmarks.json'),spec,w01)
        write(output/(label+'_city_check.json'),city);write(output/(label+'_palace_check.json'),palace)
        ck('actual.city_display',city['passed']);ck('actual.palace_display',palace['passed'])
        ck('engine.fixed_version',record['engine']['version']=='4.7.2-stable (official)')
        ck('record.plan_and_fault',record['plan_sha256']==sha(ROOT/PLAN) and record['fault']==fault)
        views=record['views']
        ck('views.exact_plan',len(views)==len(plan['views']) and [v['id'] for v in views]==[v['id'] for v in plan['views']])
        for v,p in zip(views,plan['views']):
            location=v['location'];rig=v['third_camera'];player=location['player']
            ck(v['id']+'.existing_walkable_position',location['inside_movement'] and location['floor'] and location['floor_id']=='W03_support'
               and math.dist(player[::2],p['xz'])<.01 and location['player_penetration_m']<=.005)
            ck(v['id']+'.retained_camera_and_eye_height',rig['mask']==1 and rig['fov']==65 and abs(v['eye_position'][1]-v['eye_player'][1]-1.6)<.00001
               and v['eye_fov']==65 and v['labels_hidden'] and -55.00001<=math.degrees(rig['pitch'])<=15.00001)
            if v['player_visible_in_third']:
                predicted=[projection(player,rig),projection([player[0],player[1]+1.7,player[2]],rig)]
                actual=[location['player_feet_pixel'],location['player_head_pixel']]
                ck(v['id']+'.metre_human_projection',max(math.dist(a,b) for a,b in zip(actual,predicted))<.03)
        exposure=[]
        if gpu:
            for row in record['masks']:
                path=output/('review_'+row['capture']+'.png');pixels=png_pixels(path);rgb=pixels[:,:,:3]
                selected=np.all(rgb>=250,axis=2);ys,xs=np.where(selected)
                exposure.append({**row,'file':str(path.relative_to(ROOT)),'white_pixels':int(selected.sum()),
                                 'image_size':[pixels.shape[1],pixels.shape[0]],
                                 'bounds_xy':None if not len(xs) else [int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())],
                                 'meaning':'Visible target silhouette only; not human recognition'})
            expected_masks={v['id']+'_'+kind+'_mask':v['target'] for v in plan['views'] for kind in ('third','eye')}
            ck('masks.complete_diagnostic_images',len(exposure)==len(expected_masks)
               and len({r['capture'] for r in exposure})==len(expected_masks)
               and all(expected_masks.get(r['capture'])==r['target'] and r['white_target_only'] is True
                       and r['image_size']==[1152,720] for r in exposure))
            targets={r['target'] for r in exposure if r['white_pixels']>=50}
            ck('masks.core_targets_exposed_somewhere',{'daehanmun','junghwajeon','seokjojeon','city_hall','library','plaza'}<=targets,exposed=sorted(targets))
            write(output/'exposure.json',exposure)
        # Check that the independent local checker rejects retained-evidence corruption.
        if fault=='normal':
            altered=copy.deepcopy(record);altered['actor']['camera_mask']=0
            ck('negative.camera_mask',not audit_local(altered,baseline,public,world,w01,plan)['passed'])
            altered=copy.deepcopy(record);altered['cases'][0]['samples'][0]['player'][0]+=1000
            ck('negative.outside_sample',not audit_local(altered,baseline,public,world,w01,plan)['passed'])
        ck('proof_unchanged',frozen=={p:sha(ROOT/p) for p in frozen})
    report={'task':'L04','mode':'gpu' if gpu else 'headless','fault':fault,'passed':all(c['passed'] for c in checks),'checks':checks,
            'new_proof_sha256':frozen,'reused_baseline_file':'data/reports/landmarks/l03/gpu_check.json',
            'reused_baseline_sha256':sha(ROOT/'data/reports/landmarks/l03/gpu_check.json'),
            'network':'deny network*','scope':'Fresh local orbits/walks and actual views; prior full journey reused only for identical source bytes; no human/M4/real-world survey acceptance'}
    write(output/(('gpu' if gpu else 'headless')+'_check.json'),report)
    print('L04',report['mode'],report['passed'],len(checks),'groups',flush=True)
    return 0 if report['passed'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,default=ROOT/'data/cache/l04_review')
    parser.add_argument('--gpu',action='store_true');parser.add_argument('--case',default='normal',choices=['normal','camera_mask'])
    parser.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args=parser.parse_args();raise SystemExit(main(args.output,args.gpu,args.engine,args.case))

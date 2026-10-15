#!/usr/bin/env python3
"""Capture an actual N03 car closeup, paused for review, in an offline runtime copy."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from check_vehicles_contract import ROOT, FILES, ASSETS, HELPERS, sha, write


def main(output, engine):
    output=output.resolve();output.mkdir(parents=True,exist_ok=True)
    sources={p:sha(ROOT/'game'/p) for p in FILES}
    assets={p:sha(ROOT/'game'/p) for p in ASSETS}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n03-views-') as temporary:
        game=Path(temporary)/'game'
        for name in FILES+ASSETS:
            target=game/name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/'game'/name,target)
        for name in [*HELPERS,'tests/game/check_vehicles.gd']:
            target=game/'test_support'/Path(name).name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/name,target)
        assert not (game/'.godot').exists() and not (game/'data/raw').exists()
        result=Path(temporary)/'views.json'
        command=['/usr/bin/sandbox-exec','-f',str(ROOT/'tests/game/offline.sb'),str(engine),
            '--path',str(game),'--script',str(ROOT/'tests/game/inspect_traffic.gd'),
            '--log-file',str(output/'views.log'),'--','--automatic-probe',
            '--result='+str(result),'--capture-prefix='+str(output/'review'),'--render-fps=60']
        ran=subprocess.run(command,capture_output=True,text=True,timeout=150)
        logged=(output/'views.log').read_text(errors='replace') if (output/'views.log').exists() else ''
        if ran.returncode or 'ERROR:' in ran.stdout+ran.stderr+logged or not result.exists():
            write(output/'views_failure.json',{'returncode':ran.returncode,'fresh_result':result.exists(),
                  'messages':(ran.stdout+ran.stderr)[-6000:]})
            raise RuntimeError((ran.stdout+ran.stderr)[-4000:])
        record=json.loads(result.read_text())
        record['probe_sha256']=sha(ROOT/'tests/game/inspect_traffic.gd')
        record['driver_sha256']=sha(Path(__file__))
        record['source_sha256']=sources;record['runtime_sha256']=assets
        image=output/'review_closeup_car.png'
        record['images']={image.name:sha(image)}
        assert record['bundle_sha256']==assets['data/generated/traffic.json']
        assert record['engine']['display'].lower()!='headless'
        assert record['captures']==[{'name':'closeup_car','width':1152,'height':720}]
        assert len(record['vehicles'])==len(record['descriptors'])==2
        assert all(not v['running'] and v['state']=='paused' and v['speed_mps']==0 for v in record['vehicles'])
        assert record['review']['arrived_before_pose']['station_m']>=25.2
        assert not record['review']['car_behind_camera']
        assert sources=={p:sha(ROOT/'game'/p) for p in FILES}
        assert assets=={p:sha(ROOT/'game'/p) for p in ASSETS}
        write(output/'views.json',record)
        print('N03 paused close review',image.name,flush=True)
    return 0


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'data/reports/n03')
    parser.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args=parser.parse_args();raise SystemExit(main(args.output,args.engine))

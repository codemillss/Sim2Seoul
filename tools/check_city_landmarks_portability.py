#!/usr/bin/env python3
"""Regenerate L03 twice from a relocated prepared-input copy, using native Godot."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
INPUTS=['data/processed/landmark_spec.json','game/resources/world_geometry/world.json',
        'game/data/generated/daehanmun.json','game/assets/authored/landmarks/city/recipes.json',
        'game/assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb',
        'game/assets/vendor/kenney_city_kit_commercial/Textures/colormap.png',
        'game/assets/vendor/kenney_city_kit_commercial/License.txt',
        'tools/prepare_city_landmarks.py','tools/prepare_city_authored.py','tools/prepare_palace_landmarks.py',
        'tools/prepare_world.py','tests/game/inspect_city_reuse.gd','tests/game/offline.sb','game/project.godot']
OUTPUTS=['game/data/generated/city_landmarks.json','game/data/generated/city_landmarks_manifest.json']


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output):
    checks=[]
    def ck(name,ok,**details):checks.append({'name':name,'passed':bool(ok),**details})
    inputs={p:sha(ROOT/p) for p in INPUTS};expected={p:sha(ROOT/p) for p in OUTPUTS}
    with tempfile.TemporaryDirectory(prefix='sim2seoul-l03-prepared-') as temp:
        copy=Path(temp)
        for p in INPUTS:
            dest=copy/p;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,dest)
        ck('copy.prepared_inputs_only',len(list(copy.rglob('*.*')))==len(INPUTS),files=len(INPUTS))
        command=[sys.executable,'-E','-B',str(copy/'tools/prepare_city_landmarks.py'),'--root',str(copy)]
        for repeat in (1,2):
            ran=subprocess.run(command,capture_output=True,text=True,timeout=90)
            actual={p:sha(copy/p) for p in OUTPUTS if (copy/p).exists()}
            ck('native_import_regenerate.'+str(repeat),ran.returncode==0 and actual==expected,
               output_sha256=actual,messages=(ran.stdout+ran.stderr)[-1000:])
        ck('check.fresh',subprocess.run(command+['--check'],capture_output=True,timeout=90).returncode==0)
        (copy/OUTPUTS[0]).write_text('{}\n')
        stale=subprocess.run(command+['--check'],capture_output=True,text=True,timeout=90)
        ck('check.stale_bundle_rejected',stale.returncode!=0 and 'Regeneration differs' in stale.stderr)
        subprocess.run(command,capture_output=True,check=True,timeout=90)
        recipe=copy/'game/assets/authored/landmarks/city/recipes.json'
        data=json.loads(recipe.read_text());data['palette']['glass'][0]+=.01;recipe.write_text(json.dumps(data))
        changed=subprocess.run(command+['--check'],capture_output=True,text=True,timeout=90)
        ck('check.modified_recipe_rejected',changed.returncode!=0 and 'Regeneration differs' in changed.stderr)
        ck('copy.no_national_maps_venv_or_editor_cache',not any((copy/p).exists() for p in ['data/raw','.venv-data','game/.godot']))
    ck('original_inputs_and_runtime_unchanged',inputs=={p:sha(ROOT/p) for p in INPUTS} and expected=={p:sha(ROOT/p) for p in OUTPUTS})
    report={'task':'L03','passed':all(c['passed'] for c in checks),'checks':checks,'input_sha256':inputs,'output_sha256':expected,
            'scope':'Prepared-input relocation with original GLB/texture and native importer on existing M1; no fresh install/full GIS/M4 proof'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('L03 relocation',report['passed'],len(checks),'checks');return 0 if report['passed'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,default=ROOT/'data/cache/l03_portability.json')
    raise SystemExit(main(parser.parse_args().output))

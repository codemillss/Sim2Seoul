#!/usr/bin/env python3
"""Verify one exported private V0 ZIP and its relocated release executable.

Run after active performance measurements finish, using .venv-data Python for
the unchanged geometric audits. This invokes the packaged executable, never an
editor, generator, importer or external test script. All results are separate
from the immutable export manifest; a fresh --output directory is mandatory.
"""
import argparse
import copy
import datetime as dt
import json
import plistlib
import re
import shutil
import struct
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode=True
from export_macos import (ROOT, ENGINE_VERSION, BUNDLE_ID, MAIN_SCENE,
    app_inventory, copy_new, describe, read_json, relative_file, reject_engine_errors,
    run_logged, sha, verify_pck, write_json_new, write_new)

SCRIPT='res://test_support/check_packaged_walk.gd'
QUALITY_SCRIPT='res://test_support/check_quality.gd'
LEGAL=('ATTRIBUTION.md','GODOT_LICENSE.txt','GODOT_THIRD_PARTY.txt','KENNEY_CC0.txt','NOTICES.txt')
GEOMETRY_INPUTS=('game/data/generated/traffic.json','game/data/generated/walkable_itinerary.json',
    'game/data/generated/public_walk.json','game/resources/world_geometry/world.json',
    'game/data/generated/daehanmun.json','game/data/generated/city_landmarks.json',
    'game/data/generated/palace_landmarks.json','data/processed/landmark_spec.json')


def same_inventory(expected,actual):
    return all(actual.get(key)==expected.get(key) for key in ('files','bytes','tree_sha256'))


def bound_sources(export):
    baseline=export.get('source_preservation',{})
    if baseline.get('passed') is not True or not baseline.get('before'):
        raise ValueError('Export input preservation evidence is missing')
    paths={}
    for name in baseline['before']:
        if name.startswith('evidence_catalog:'):
            path=Path(name.removeprefix('evidence_catalog:'))
            if path.resolve()!=Path(export['catalog']['path']).resolve():raise ValueError('Unexpected evidence catalog binding')
        else:path=relative_file(ROOT,name)
        paths[name]=path
    return paths,baseline['before']


def native_log(process,path,label):
    if not path.is_file():raise RuntimeError(label+' did not create its native log')
    text=path.read_text(errors='replace')
    class Messages:
        stdout=process.stdout
        stderr=process.stderr+'\n'+text
    reject_engine_errors(Messages,label)
    return Messages.stdout+Messages.stderr


def screenshot_size(path):
    with path.open('rb') as stream:header=stream.read(24)
    if len(header)!=24 or header[:8]!=b'\x89PNG\r\n\x1a\n' or header[12:16]!=b'IHDR':
        raise ValueError('Not a PNG screenshot: '+str(path))
    return list(struct.unpack('>II',header[16:24]))


def check_sandbox(policy,workspace,output,report,require):
    readable=workspace/'sandbox_control.txt';write_new(readable,'R03 external read control\n')
    result=run_logged(['/usr/bin/sandbox-exec','-f',policy,'/bin/cat',readable],
        'sandbox_external_read',output,report,cwd=workspace)
    require('sandbox.external_read_allowed',result.stdout=='R03 external read control\n')
    try:
        run_logged(['/usr/bin/sandbox-exec','-f',policy,'/bin/cat',ROOT/'game/project.godot'],
            'sandbox_source_read',output,report,cwd=workspace)
    except RuntimeError:pass  # A real denied read is this control's expected result.
    command=report['commands'][-1]
    stderr=(output/'sandbox_source_read.stderr.log').read_text(errors='replace')
    require('sandbox.repository_read_denied',command['label']=='sandbox_source_read'
        and isinstance(command['returncode'],int) and command['returncode']!=0
        and command['stdout']['bytes']==0 and re.search(r'Operation not permitted|Permission denied',stderr) is not None)


def audit_passed(report):
    rows=report.get('checks',[])
    return report.get('passed') is True and bool(rows) and all(row.get('passed') is True for row in rows)


def captures(record,runtime,prefix,require,required_size=None):
    rows=record.get('captures',[])
    names=[prefix+'_'+row['name']+'.png' for row in rows]
    pictures=sorted(runtime.glob(prefix+'_*.png'))
    require(prefix+'.capture_files',bool(rows) and len(set(names))==len(names)
        and set(names)=={path.name for path in pictures})
    dimensions={path.name:screenshot_size(path) for path in pictures}
    require(prefix+'.capture_dimensions',all(dimensions[name]==[row['width'],row['height']]
        and (required_size is None or dimensions[name]==required_size) for name,row in zip(names,rows)))
    return dimensions


def check_package(manifest_path,output,timeout):
    manifest_path=manifest_path.resolve();output=output.resolve()
    if timeout<=0:raise ValueError('--timeout must be positive')
    export=read_json(manifest_path)
    if export.get('schema_version')!=1 or export.get('task')!='R03' or export.get('passed') is not True:
        raise ValueError('Require a passed R03 export manifest')
    output.mkdir(parents=True,exist_ok=False)
    report={'schema_version':1,'task':'R03','stage':'relocated_release_package_contract','passed':False,
        'started_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'export_manifest':{'path':str(manifest_path)},
        'checks':[],'commands':[],'network':'deny network*','runtime_source_access':'deny file-read* beneath repository',
        'resolution':[1152,720],'runtime_tested':False,'human_input_tested':False,'m4_tested':False,'gatekeeper_transfer_tested':False,
        'quality_menu_and_settings_persistence_tested':False,
        'scope':'ZIP round-trip, offline relocated release startup and full N04 continuous-input geometry/actor/camera regression. No performance, human controls, OS focus, other-Mac or transfer acceptance.'}
    paths={};before={};original_app=None;archive=None;relocated=None;runtime=None;artifacts_copied=False

    def ck(name,passed,**details):
        report['checks'].append({'name':name,'passed':bool(passed),**details})
        return bool(passed)

    def require(name,passed,**details):
        if not ck(name,passed,**details):raise ValueError(name+' failed')

    def retain_runtime():
        nonlocal artifacts_copied
        if runtime is None or artifacts_copied:return
        for source in sorted(runtime.rglob('*')):
            if source.is_symlink():raise ValueError('Unexpected symlink in runtime evidence')
            if source.is_file():copy_new(source,output/'runtime'/source.relative_to(runtime))
        artifacts_copied=True

    try:
        report['export_manifest'].update(describe(manifest_path))
        paths,baseline=bound_sources(export)
        before={name:describe(path) for name,path in paths.items()}
        require('export.source_binding',before==baseline)
        paths['tools/check_package_contract.py']=Path(__file__).resolve()
        for name in GEOMETRY_INPUTS:paths[name]=relative_file(ROOT,name)
        # Import only the existing independent observers, never a producer.
        from check_urban_motion_evidence import audit as audit_motion
        from check_city_landmarks_evidence import audit as audit_city
        from check_palace_landmarks_evidence import audit as audit_palace
        from check_quality_contract import audit as audit_quality
        for module in tuple(sys.modules.values()):
            filename=getattr(module,'__file__',None)
            if not filename:continue
            path=Path(filename).resolve()
            if path.suffix=='.py' and path.is_relative_to(ROOT/'tools'):
                paths[path.relative_to(ROOT).as_posix()]=path
        before={name:describe(path) for name,path in paths.items()}
        report['source_before']=before
        require('export.engine_version',export.get('engine',{}).get('version')==ENGINE_VERSION)
        require('export.static_validation',export.get('stage')=='local_export_static_validation'
            and export.get('codesign',{}).get('verified') is True and export.get('codesign',{}).get('ad_hoc') is True
            and export.get('icu',{}).get('actual_pck_inclusion_verified') is True)
        original_app=Path(export['outputs']['app']['path']).resolve()
        archive=Path(export['outputs']['zip']['path']).resolve()
        require('export.app_inventory',same_inventory(export['outputs']['app'],app_inventory(original_app)))
        require('export.zip_sha256',describe(archive)=={key:export['outputs']['zip'][key] for key in ('bytes','sha256')})
        require('export.template_inputs',export.get('preset',{}).get('exclude_filter')==''
            and export['preset']['export_filter']=='all_resources')
        require('export.quality_probe_included','tests/game/check_quality.gd' in export.get('helper_sha256',{}))
        require('export.dispatcher_included','tests/game/package_dispatch.gd' in export.get('helper_sha256',{})
            and export.get('qa_dispatch',{}).get('normal_launch_inert') is True
            and export['qa_dispatch']['sha256']==export['helper_sha256']['tests/game/package_dispatch.gd'])
        report['free_before_bytes']=shutil.disk_usage(output).free
        if report['free_before_bytes']<1024**3:raise RuntimeError('Less than 1 GiB free; preserved all existing artifacts')
        workspace=Path(tempfile.mkdtemp(prefix='sim2seoul-r03-roundtrip-')).resolve()
        require('relocation.outside_repository',not workspace.is_relative_to(ROOT.resolve()))
        report['retained_workspace']=str(workspace)
        extraction=workspace/'unpacked';extraction.mkdir()
        runtime=workspace/'evidence';runtime.mkdir()
        run_logged(['/usr/bin/ditto','-x','-k',archive,extraction],'ditto_extract',output,report)
        relocated=extraction/original_app.name
        require('roundtrip.app_inventory',same_inventory(export['outputs']['app'],app_inventory(relocated)))
        with (relocated/'Contents/Info.plist').open('rb') as stream:info=plistlib.load(stream)
        binary=relocated/'Contents/MacOS'/info['CFBundleExecutable']
        require('release.bundle_identifier',info.get('CFBundleIdentifier')==BUNDLE_ID)
        require('release.binary_inside_app',binary.is_file() and binary.resolve().is_relative_to(relocated))
        binary_hash=sha(binary)
        result=run_logged(['/usr/bin/lipo','-archs',binary],'lipo_archs',output,report)
        require('release.universal2',set(result.stdout.split())=={'arm64','x86_64'})
        run_logged(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',relocated],'codesign_verify',output,report)
        result=run_logged(['/usr/bin/codesign','--display','--verbose=4',relocated],'codesign_display',output,report)
        require('release.ad_hoc','Signature=adhoc' in result.stdout+result.stderr)
        report['roundtrip']={'passed':True,'app_path':str(relocated),'architectures':['arm64','x86_64'],
            'codesign_verified':True,'ad_hoc':True,'method':'ditto -x -k'}
        report['pck']=verify_pck(relocated,export['staged_fileaccess_inputs'],
            ['test_support/'+Path(name).name for name in export['helper_sha256']])
        require('release.pck_inputs',bool(report['pck']['verified_fileaccess_inputs']))
        for name,item in export['loose_legal_files'].items():
            require('legal.loose.'+name,describe(relocated/'Contents/Resources'/name)==item)
        # The executable can read its copied PCK and system libraries, but cannot
        # fall back to any asset, map, tool or cache under the development repo.
        policy=workspace/'offline_no_source.sb'
        repository=json.dumps(str(ROOT.resolve()),ensure_ascii=False)
        write_new(policy,'(version 1)\n(allow default)\n(deny network*)\n(deny file-read* (subpath '+repository+'))\n(deny file-write* (subpath '+repository+'))\n')
        copy_new(policy,output/'offline_no_source.sb')
        report['sandbox_policy']={'path':'offline_no_source.sb',**describe(policy)}
        check_sandbox(policy,workspace,output,report,require)
        common=['/usr/bin/sandbox-exec','-f',policy,binary,'--resolution','1152x720','--windowed']
        normal_log=runtime/'normal.log'
        result=run_logged([*common,'--max-fps','60','--quit-after','180','--log-file',normal_log],
            'normal_launch',output,report,timeout=90,cwd=workspace)
        messages=native_log(result,normal_log,'normal launch')
        ready=re.findall(r'V0_READY quality=(standard|low) pedestrians=2 vehicles=2',messages)
        require('normal_launch.ready',bool(ready) and 'R03_QA_DISPATCH' not in messages,
            observed_quality=ready[-1] if ready else None)
        api_version=export.get('license_api',{}).get('version',{}).get('string')
        quality_raw=runtime/'quality.json';quality_log=runtime/'quality.log'
        result=run_logged([*common,'--log-file',quality_log,'--','--automatic-probe','--sim2seoul-test=quality',
            '--result='+str(quality_raw),'--suite=smoke','--case=normal','--render-fps=60','--capture-prefix='+str(runtime/'quality_view')],
            'package_settings_ui_short',output,report,timeout=180,cwd=workspace)
        quality_messages=native_log(result,quality_log,'package settings/UI short phase')
        require('quality.actual_dispatch','R03_QA_DISPATCH mode=quality script='+QUALITY_SCRIPT in quality_messages)
        require('quality.raw_exists',quality_raw.is_file())
        quality_record=read_json(quality_raw)
        require('quality.package_phase_identity',quality_record.get('suite')=='smoke'
            and quality_record.get('engine',{}).get('version')==api_version
            and quality_record['engine'].get('display') not in (None,'headless'))
        quality_checks=audit_quality(quality_record,smoke=True)
        quality_result={'task':'R03','phase':'package_settings_ui_short','passed':bool(quality_checks)
            and all(row['passed'] for row in quality_checks),'checks':quality_checks,'executable_path':str(binary),
            'executable_sha256':binary_hash,'raw_file':'runtime/quality.json',
            'scope':'Existing R02 smoke UI/settings audit on this relocated release app. Not R02 full regression, performance or human interaction acceptance.'}
        write_json_new(output/'quality_check.json',quality_result)
        require('quality.settings_and_ui',audit_passed(quality_result),checks=len(quality_checks),
            failed=[row['name'] for row in quality_checks if not row['passed']])
        report['quality_menu_and_settings_persistence_tested']=quality_result['passed']
        require('quality.ui_capture_cases',[row['name'] for row in quality_record.get('captures',[])]
            ==['menu_960','popup_1152','hud_1152'])
        report['quality_screenshots']=captures(quality_record,runtime,'quality_view',require)
        raw=runtime/'full.json';context_path=Path(str(raw)+'.package_context.json');full_log=runtime/'full.log'
        result=run_logged([*common,'--log-file',full_log,'--','--automatic-probe','--sim2seoul-test=urban',
            '--result='+str(raw),'--suite=full','--case=normal','--render-fps=60','--capture-prefix='+str(runtime/'full_view')],
            'full_journey',output,report,timeout=timeout,cwd=workspace)
        full_messages=native_log(result,full_log,'full journey')
        require('full_journey.actual_dispatch','R03_QA_DISPATCH mode=urban script='+SCRIPT in full_messages)
        require('full_journey.raw_and_context',raw.is_file() and context_path.is_file())
        record=read_json(raw);context=read_json(context_path)
        require('release.context',bool(api_version) and context.get('task')=='R03' and context.get('editor_feature') is False
            and context.get('debug_build') is False and context.get('engine_version')==api_version
            and Path(context.get('executable_path','')).resolve()==binary.resolve()
            and context.get('executable_sha256')==binary_hash)
        require('release.v0_main_scene',context.get('resolved_main_scene')==MAIN_SCENE and context.get('scene_path')==MAIN_SCENE)
        expected=export['staged_fileaccess_inputs']
        required=['icudt_godot.dat','resources/quality_presets/standard.json','resources/quality_presets/low.json',
            *('resources/legal/'+name for name in LEGAL)]
        for name in required:
            actual=context.get('packed_files',{}).get('res://'+name,{})
            require('fileaccess.'+name,actual.get('exists') is True
                and {key:actual.get(key) for key in ('bytes','sha256')}==expected.get(name))
        quality=context.get('quality',{})
        require('release.standard_quality',quality.get('runtime_ok') is True and quality.get('preset_id')=='standard'
            and quality.get('scaling_3d_scale')==1. and quality.get('sun_shadow_enabled') is True
            and quality.get('camera_far_m')==200. and quality.get('pedestrian_count')==2 and quality.get('vehicle_count')==2
            and quality.get('quality_settings_path')==str(raw)+'.quality.json')
        require('full_journey.suite',record.get('task')=='N04' and record.get('suite')=='full'
            and record.get('fault')=='normal' and record.get('error')==''
            and record.get('engine',{}).get('version')==api_version and record['engine'].get('display') not in (None,'headless'))
        inputs=[read_json(ROOT/name) for name in GEOMETRY_INPUTS]
        motion=audit_motion(record,*inputs[:5]);write_json_new(output/'motion_check.json',motion)
        ck('full_journey.motion',audit_passed(motion),checks=len(motion.get('checks',[])),
            failed=[row['name'] for row in motion.get('checks',[]) if row.get('passed') is not True])
        ck('full_journey.acceptance',any(row.get('name')=='acceptance.full_suite' and row.get('passed') is True for row in motion.get('checks',[])))
        city=audit_city(record['city_visuals'],inputs[5],inputs[7],inputs[4])
        write_json_new(output/'city_check.json',city);ck('full_journey.city',audit_passed(city),checks=len(city.get('checks',[])))
        palace_raw=copy.deepcopy(record['palace_visuals'])
        normalized=inputs[5]['hidden_mesh_ids']
        for identity in normalized:palace_raw['all_source_visibility'][identity]=True
        palace=audit_palace(palace_raw,inputs[6],inputs[7],inputs[4])
        write_json_new(output/'palace_check.json',palace)
        ck('full_journey.palace',audit_passed(palace),checks=len(palace.get('checks',[])),
            preserved_n04_visibility_normalization=normalized)
        report['screenshots']=captures(record,runtime,'full_view',require,[1152,720])
        report['package_context']={'path':'runtime/'+context_path.name,**describe(context_path)}
        report['runtime_tested']=True
    except Exception as exc:
        report['error']=type(exc).__name__+': '+str(exc)
        ck('runner.completed',False,error=report['error'])
    finally:
        try:retain_runtime()
        except Exception as exc:ck('evidence.retained',False,error=type(exc).__name__+': '+str(exc))
        def preserved_sources():
            after={name:describe(path) for name,path in paths.items()}
            report['source_after']=after
            return before==after
        preservation=[('export_manifest',lambda:describe(manifest_path)=={key:report['export_manifest'][key] for key in ('bytes','sha256')})]
        if before:preservation.append(('source',preserved_sources))
        if original_app is not None:preservation.append(('original_app',lambda:same_inventory(export['outputs']['app'],app_inventory(original_app))))
        if archive is not None:preservation.append(('original_zip',lambda:describe(archive)=={key:export['outputs']['zip'][key] for key in ('bytes','sha256')}))
        if relocated is not None and relocated.is_dir():
            preservation.append(('relocated_app',lambda:same_inventory(export['outputs']['app'],app_inventory(relocated))))
        for name,operation in preservation:
            try:ck('preservation.'+name,operation())
            except Exception as exc:ck('preservation.'+name,False,error=type(exc).__name__+': '+str(exc))
        if relocated is not None and relocated.is_dir():
            try:
                run_logged(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',relocated],
                    'codesign_verify_after_run',output,report)
                ck('preservation.signature',True)
            except Exception as exc:ck('preservation.signature',False,error=type(exc).__name__+': '+str(exc))
        report['evidence']={path.relative_to(output).as_posix():describe(path)
            for path in sorted(output.rglob('*')) if path.is_file()}
        report['completed_utc']=dt.datetime.now(dt.timezone.utc).isoformat()
        report['passed']=bool(report['checks']) and all(row['passed'] for row in report['checks'])
        write_json_new(output/'package_check.json',report)
        print(json.dumps({'passed':report['passed'],'report':str(output/'package_check.json'),
            'relocated_app':str(relocated) if relocated is not None else None,
            'failed':[row['name'] for row in report['checks'] if not row['passed']]},ensure_ascii=False))
    return 0 if report['passed'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path,help='Passed export_macos.py manifest.json')
    parser.add_argument('--output',required=True,type=Path,help='Fresh external evidence directory; must not already exist')
    parser.add_argument('--timeout',type=int,default=3600,help='Full GPU journey timeout in seconds')
    args=parser.parse_args()
    raise SystemExit(check_package(args.manifest,args.output,args.timeout))

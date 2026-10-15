#!/usr/bin/env python3
"""Build a private V0 macOS app from a fresh, runtime-only project copy.

Default invocation prints the plan only. Run with --execute after measurements
finish. Requires the verified local 4.7.2 TPZ/macOS cache; never downloads or
installs templates. No repository project, security settings or credentials change.
"""
import argparse
import contextlib
import datetime as dt
import difflib
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath

ROOT=Path(__file__).resolve().parents[1]
ENGINE_VERSION='4.7.2.stable.official.ed1daf0bf'
CACHE=ROOT/'data/cache/godot_export/4.7.2'
TPZ_NAME='Godot_v4.7.2-stable_export_templates.tpz'
TPZ_SHA256='f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
MACOS_SHA256='88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792'
BUNDLE_ID='org.codemillss.sim2seoul'
MAIN_SCENE='res://scenes/world/v0_walk.tscn'
PRESET_NAME='macOS Local'
ADDITIONS=('scripts/v0_walk.gd','scenes/world/v0_walk.tscn',
           'resources/quality_presets/standard.json','resources/quality_presets/low.json')
LEGAL_SOURCES={
    'resources/legal/ATTRIBUTION.md':'docs/ATTRIBUTION.md',
    'resources/legal/KENNEY_CC0.txt':'game/assets/vendor/kenney_city_kit_commercial/License.txt',
    'resources/legal/KENNEY_PROVENANCE.json':'game/assets/vendor/kenney_city_kit_commercial/provenance.json',
    'resources/legal/data_usage.json':'config/data_usage.json',
}
HELPER_ROOT='tests/game/check_packaged_walk.gd'
HELPER_RE=re.compile(r'res://test_support/([A-Za-z0-9_.-]+\.gd)')
OFFICIAL_SOURCES={
    'templates':'https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable',
    'custom_template':'https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/export/export_plugin.cpp',
    'icu':'https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform.cpp',
    'pck':'https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/file_access_pack.cpp',
    'license':'https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt',
}


def sha(path):
    digest=hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk:=stream.read(4*1024**2):digest.update(chunk)
    return digest.hexdigest()


def describe(path):
    path=Path(path)
    return {'bytes':path.stat().st_size,'sha256':sha(path)}


def read_json(path):
    value=json.loads(Path(path).read_text())
    if not isinstance(value,dict):raise ValueError('Expected JSON object: '+str(path))
    return value


def write_new(path,text):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf-8') as stream:stream.write(text)


def write_bytes_new(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:stream.write(data)


def write_json_new(path,value):
    write_new(path,json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n')


def relative_file(base,name):
    relative=PurePosixPath(name)
    if relative.is_absolute() or not relative.parts or any(p in ('..','.git','.godot') for p in relative.parts):
        raise ValueError('Unsafe catalog path: '+name)
    path=base/str(relative)
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(base.resolve()):
        raise FileNotFoundError('Missing or non-regular input: '+str(path))
    return path


def copy_new(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    with source.open('rb') as before,target.open('xb') as after:shutil.copyfileobj(before,after)
    shutil.copymode(source,target)


def source_helpers(root_helper=HELPER_ROOT):
    """Only literal res://test_support/*.gd dependencies, including inheritance."""
    pending=[root_helper];result={}
    while pending:
        name=pending.pop()
        if name in result:continue
        path=relative_file(ROOT,name)
        result[name]=path
        pending.extend('tests/game/'+name for name in HELPER_RE.findall(path.read_text()))
    return result


def catalog(report_path):
    report=read_json(report_path)
    rows=report.get('checks',[])
    if report.get('task')!='N04' or report.get('mode')!='gpu' or report.get('passed') is not True or not rows or not all(r.get('passed') is True for r in rows):
        raise ValueError('A fully passed N04 GPU catalog is required.')
    for key in ('source_sha256','runtime_sha256'):
        if not isinstance(report.get(key),dict) or not report[key]:raise ValueError('Missing N04 '+key)
    if set(report['source_sha256'])&set(report['runtime_sha256']):raise ValueError('Overlapping N04 catalogs')
    return report


def set_project_value(text,section,key,value):
    """Preserve existing text except the explicitly recorded temporary setting."""
    encoded=json.dumps(value,ensure_ascii=False) if not isinstance(value,bool) else str(value).lower()
    section_match=re.search(r'^\['+re.escape(section)+r'\]\s*$',text,re.M)
    old=None
    if not section_match:return text.rstrip()+'\n\n['+section+']\n'+key+'='+encoded+'\n',old
    start=section_match.end();following=re.search(r'^\[',text[start:],re.M)
    end=start+following.start() if following else len(text)
    body=text[start:end]
    line=re.search(r'^'+re.escape(key)+r'=(.*)$',body,re.M)
    if line:
        old=line.group(1)
        body=body[:line.start()]+key+'='+encoded+body[line.end():]
    else:body=body.rstrip()+'\n'+key+'='+encoded+'\n\n'
    return text[:start]+body+text[end:],old


def prepare_project(game,output):
    original=(game/'project.godot').read_text();text=original;changes=[]
    settings=(
        ('application','run/main_scene',MAIN_SCENE,'Private V0 entry scene in this copy only.'),
        ('rendering','textures/vram_compression/import_s3tc_bptc',True,'Official Universal 2 exporter requires desktop texture formats.'),
        ('rendering','textures/vram_compression/import_etc2_astc',True,'Official Universal 2 exporter also requires Apple Silicon texture formats.'),
        ('internationalization','locale/include_text_server_data',True,'Include the matching official ICU data for Korean text.'),
    )
    for section,key,value,reason in settings:
        text,old=set_project_value(text,section,key,value)
        changes.append({'setting':section+'/'+key,'old_literal':old,'new':value,'reason':reason})
    (game/'project.godot').write_text(text)
    write_new(output/'temporary_project.diff',''.join(difflib.unified_diff(original.splitlines(True),text.splitlines(True),fromfile='repository/game/project.godot',tofile='temporary/game/project.godot')))
    return {'changes':changes,'original_sha256':hashlib.sha256(original.encode()).hexdigest(),
            'temporary_sha256':sha(game/'project.godot'),'diff_file':'temporary_project.diff'}


def run_logged(command,label,output,manifest,*,timeout=900,cwd=None,environment=None):
    started=time.monotonic();argv=[str(p) for p in command];failure=None;timed_out=False
    try:process=subprocess.run(argv,capture_output=True,timeout=timeout,cwd=cwd,env=environment)
    except subprocess.TimeoutExpired as exc:
        failure=exc;timed_out=True
        process=subprocess.CompletedProcess(argv,None,exc.stdout or b'',exc.stderr or b'')
    except OSError as exc:
        failure=exc;process=subprocess.CompletedProcess(argv,None,b'',str(exc).encode())
    stdout=output/(label+'.stdout.log');stderr=output/(label+'.stderr.log')
    write_bytes_new(stdout,process.stdout);write_bytes_new(stderr,process.stderr)
    manifest['commands'].append({'label':label,'argv':argv,'returncode':process.returncode,'timed_out':timed_out,
        'wall_s':time.monotonic()-started,'stdout':{'path':stdout.name,**describe(stdout)},'stderr':{'path':stderr.name,**describe(stderr)}})
    if failure:raise RuntimeError(label+' could not complete; retained available stdout/stderr logs in '+str(output)) from failure
    if process.returncode:raise RuntimeError(label+' failed; retained stdout/stderr logs in '+str(output))
    return subprocess.CompletedProcess(argv,process.returncode,process.stdout.decode('utf-8',errors='replace'),process.stderr.decode('utf-8',errors='replace'))


def engine_command(engine,*args):
    return ['/usr/bin/sandbox-exec','-f',ROOT/'tests/game/offline.sb',engine,*args]


def reject_engine_errors(process,label):
    text=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',process.stdout+process.stderr)
    if re.search(r'^\s*(?:SCRIPT )?ERROR:',text,re.M):raise RuntimeError('Godot '+label+' logged an error')


def validate_templates(args,game,manifest):
    for path in (args.template,args.template_archive):
        if not path.is_file():raise FileNotFoundError('Missing verified template: '+str(path)+'. Prepare it locally; acquisition record: '+str(CACHE/'acquisition.json'))
    template=describe(args.template);archive=describe(args.template_archive)
    if template['sha256']!=MACOS_SHA256 or archive['sha256']!=TPZ_SHA256:
        raise ValueError('Pinned official 4.7.2 template SHA-256 mismatch; nothing will be exported.')
    with zipfile.ZipFile(args.template_archive) as package:
        version=package.read('templates/version.txt').decode().strip()
        if version!='4.7.2.stable':raise ValueError('Template version mismatch')
        info=package.getinfo('templates/icudt_godot.dat')
        if info.file_size>32*1024**2:raise ValueError('Unexpected ICU payload size')
        data=package.read(info)
    with (game/'icudt_godot.dat').open('xb') as stream:stream.write(data)
    manifest['templates']={'version':version,'cached_macos':{'path':str(args.template),**template},
        'official_tpz':{'path':str(args.template_archive),**archive},
        'acquisition_record':str(CACHE/'acquisition.json'),'global_install_performed':False}
    if (CACHE/'acquisition.json').is_file():manifest['templates']['acquisition_record_sha256']=sha(CACHE/'acquisition.json')
    manifest['icu']={'archive_member':info.filename,'resource_path':'res://icudt_godot.dat','bytes':len(data),
        'sha256':hashlib.sha256(data).hexdigest(),'crc32':format(info.CRC,'08x'),'include_text_server_data':True,
        'actual_pck_inclusion_verified':False}


def generate_notices(engine,game,workspace,output,manifest,environment):
    probe=workspace/'engine_notices.gd';result=workspace/'engine_notices.json'
    write_new(probe,'''extends SceneTree
func _initialize() -> void:
    var arguments: PackedStringArray=OS.get_cmdline_user_args()
    if arguments.size()!=1:quit(1);return
    var record: Dictionary={"version":Engine.get_version_info(),"godot_license":Engine.get_license_text(),"licenses":Engine.get_license_info(),"components":Engine.get_copyright_info()}
    var stream: FileAccess=FileAccess.open(arguments[0],FileAccess.WRITE)
    if stream==null:quit(1);return
    stream.store_string(JSON.stringify(record)+"\\n")
    stream.close()
    quit(0)
''')
    process=run_logged(engine_command(engine,'--headless','--path',game,'--script',probe,'--',result),
                       'engine_notices',output,manifest,environment=environment)
    reject_engine_errors(process,'license extraction')
    info=read_json(result)
    if not info.get('licenses') or not info.get('components') or len(info.get('godot_license',''))<100:
        raise ValueError('Engine did not provide complete license notices')
    legal=game/'resources/legal'
    write_new(legal/'GODOT_LICENSE.txt',info['godot_license'].rstrip()+'\n')
    thirdparty='Godot 4.7.2 third-party copyright information\n\n'+json.dumps(info['components'],ensure_ascii=False,indent=2)+'\n\n'
    thirdparty+='\n\n'.join(name+'\n'+text for name,text in sorted(info['licenses'].items()))+'\n'
    write_new(legal/'GODOT_THIRD_PARTY.txt',thirdparty)
    write_new(legal/'NOTICES.txt',
        'Sim2Seoul private local V0 package\n\n'
        'Map data: © OpenStreetMap contributors, Overture Maps Foundation — ODbL 1.0.\n'
        'See ATTRIBUTION.md for source snapshots, upstream credits, assumptions and reproduction references.\n'
        'Godot Engine 4.7.2: MIT; see GODOT_LICENSE.txt and GODOT_THIRD_PARTY.txt.\n'
        'Kenney City Kit Commercial 2.1: CC0; see KENNEY_CC0.txt and KENNEY_PROVENANCE.json.\n'
        'Copernicus DSM remains reference material and is not included as runtime terrain.\n')
    copy_new(result,output/'engine_notices.json')
    manifest['license_api']={'probe_sha256':sha(probe),'result':{'path':'engine_notices.json',**describe(result)},'version':info['version']}
    return {p.name:p for p in sorted(legal.iterdir()) if p.is_file()}


def legal_template(template,workspace,notices,manifest):
    """Add loose notices before Godot signs the final app, preserving the cache."""
    derived=workspace/'macos_with_notices.zip';copy_new(template,derived)
    entries=[]
    with zipfile.ZipFile(derived,'a',compression=zipfile.ZIP_DEFLATED) as package:
        existing=set(package.namelist())
        for name,path in notices.items():
            target='macos_template.app/Contents/Resources/'+name
            if target in existing:raise ValueError('Notice would overwrite a template member: '+target)
            package.write(path,target);entries.append({'zip_path':target,**describe(path)})
    manifest['templates']['derived']={'path':str(derived),**describe(derived),'added_notices':entries,
        'reason':'Loose notices must be inside the bundle before built-in ad-hoc signing seals it.'}
    return derived


def write_preset(game,template,version):
    quote=lambda value:json.dumps(str(value),ensure_ascii=False)
    options={'export/distribution_type':0,'binary_format/architecture':'universal',
        'custom_template/debug':str(template),'custom_template/release':str(template),
        'application/bundle_identifier':BUNDLE_ID,'application/short_version':version,'application/version':version,
        'codesign/codesign':1,'codesign/identity':'','notarization/notarization':0,
        'debug/export_console_wrapper':0,'shader_baker/enabled':False}
    text='[preset.0]\nname='+quote(PRESET_NAME)+'\nplatform="macOS"\nrunnable=true\nadvanced_options=true\n'
    text+='dedicated_server=false\ncustom_features=""\nexport_filter="all_resources"\ninclude_filter="*.json,*.txt,*.md"\nexclude_filter=""\nexport_path=""\n\n[preset.0.options]\n'
    for key,value in options.items():text+=key+'='+(str(value).lower() if isinstance(value,bool) else str(value) if isinstance(value,int) else quote(value))+'\n'
    write_new(game/'export_presets.cfg',text)
    return {'name':PRESET_NAME,'export_filter':'all_resources','include_filter':'*.json,*.txt,*.md','exclude_filter':'',
        'options':options,'sha256':sha(game/'export_presets.cfg')}


def pck_index(path):
    """Read official, unencrypted standalone Godot PCK v2/v3/v4 directories."""
    size=path.stat().st_size
    with path.open('rb') as stream:
        def integer(code):
            raw=stream.read(struct.calcsize(code))
            if len(raw)!=struct.calcsize(code):raise ValueError('Truncated PCK')
            return struct.unpack('<'+code,raw)[0]
        if stream.read(4)!=b'GDPC':raise ValueError('Expected standalone PCK')
        version=integer('I');engine=[integer('I') for _ in range(3)];flags=integer('I');base=integer('Q')
        if version not in (2,3,4) or flags&5:raise ValueError('Unsupported encrypted/sparse PCK format')
        if version in (3,4):stream.seek(integer('Q'))
        else:stream.seek(16*4,1)
        count=integer('I');entries={}
        if count>100000:raise ValueError('Unexpected PCK directory size')
        for _ in range(count):
            length=integer('I')
            if length>65536:raise ValueError('Unexpected PCK path length')
            name=stream.read(length).decode().rstrip('\0').removeprefix('res://')
            offset=base+integer('Q');length=integer('Q');md5=stream.read(16).hex();file_flags=integer('I')
            if name in entries or file_flags or offset+length>size:raise ValueError('Invalid or duplicate PCK member: '+name)
            entries[name]={'offset':offset,'bytes':length,'md5':md5}
    return {'version':version,'engine':engine,'flags':flags,'entry_count':count,'entries':entries}


def verify_pck(app,expected,helper_names):
    packs=list((app/'Contents/Resources').glob('*.pck'))
    if len(packs)!=1:raise ValueError('Expected one self-contained project PCK')
    pack=packs[0];index=pck_index(pack);verified={}
    for name in index['entries']:
        if name.startswith(('tools/','data/raw/','data/cache/','.git/','.venv/')) or name.endswith('.py'):
            raise ValueError('Development-only input unexpectedly present in PCK: '+name)
    with pack.open('rb') as stream:
        for name,wanted in expected.items():
            if name not in index['entries']:raise ValueError('Required FileAccess input missing from PCK: '+name)
            entry=index['entries'][name];stream.seek(entry['offset']);remaining=entry['bytes']
            digest=hashlib.sha256();md5=hashlib.md5()
            while remaining:
                data=stream.read(min(4*1024**2,remaining))
                if not data:raise ValueError('Truncated PCK input: '+name)
                remaining-=len(data);digest.update(data);md5.update(data)
            actual={'bytes':entry['bytes'],'sha256':digest.hexdigest()}
            if actual!=wanted or md5.hexdigest()!=entry['md5']:raise ValueError('PCK bytes differ from staged input: '+name)
            verified[name]=actual
    for name in helper_names:
        if name not in index['entries'] and name+'.remap' not in index['entries']:
            raise ValueError('Packaged verification helper missing: '+name)
    if 'project.binary' not in index['entries']:raise ValueError('Missing packed project settings')
    return {'path':str(pack),'file':describe(pack),'format':{k:v for k,v in index.items() if k!='entries'},
            'verified_fileaccess_inputs':verified,'member_names':sorted(index['entries']),'helper_inputs_present':True}


def app_inventory(app):
    files={};total=0
    for directory,dirs,names in os.walk(app,followlinks=False):
        base=Path(directory)
        for name in [*dirs,*names]:
            path=base/name;relative=path.relative_to(app).as_posix();mode=path.lstat().st_mode
            if path.is_symlink():files[relative]={'symlink':os.readlink(path),'mode':stat.S_IMODE(mode)}
            elif path.is_file():files[relative]={**describe(path),'mode':stat.S_IMODE(mode)};total+=path.stat().st_size
    tree_sha=hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return {'path':str(app),'bytes':total,'files':files,'tree_sha256':tree_sha}


def zip_app(app,target,output,manifest):
    if target.exists():raise FileExistsError('Refusing to overwrite archive: '+str(target))
    run_logged(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',app,target],
               'archive_ditto',output,manifest,timeout=1800)
    if not target.is_file():raise RuntimeError('Archive command returned without producing a ZIP')


def build(args):
    if not args.execute:
        print(json.dumps({'action':'plan_only','execute_flag_required':True,'catalog':str(args.catalog),
            'template':str(args.template),'template_archive':str(args.template_archive),'acquisition_record':str(CACHE/'acquisition.json'),
            'main_scene':MAIN_SCENE,'new_v0_inputs':list(ADDITIONS),'packaged_probe':HELPER_ROOT,
            'output_root':str(args.output_root),'scope':'Run --execute after measurements finish; no download or global installation.'},ensure_ascii=False,indent=2))
        return 0
    if not re.fullmatch(r'\d+\.\d+\.\d+',args.app_version):raise ValueError('--app-version must be three numeric components')
    engine=args.engine.resolve();catalog_path=args.catalog.resolve();report=catalog(catalog_path)
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    stamp=dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output=args.output_root.resolve()/('v'+args.app_version+'-'+head[:12]+'-'+stamp)
    output.mkdir(parents=True,exist_ok=False)
    manifest={'schema_version':1,'task':'R03','stage':'local_export_static_validation','passed':False,
        'version':args.app_version,'started_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'git_head':head,
        'git_status':subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True),
        'catalog':{'path':str(catalog_path),**describe(catalog_path)},'official_sources':OFFICIAL_SOURCES,'commands':[],
        'runtime_tested':False,'m4_tested':False,'gatekeeper_transfer_tested':False,'public_distribution_authorized':False,
        'scope':'Private local export and static artifact verification only. Normal app startup, complete packaged journey, Korean UI, M4 and transfer checks remain separate.'}
    tracked={};before={}
    try:
        inputs={**report['source_sha256'],**report['runtime_sha256']}
        for name,expected in inputs.items():
            source=relative_file(ROOT/'game',name)
            if sha(source)!=expected:raise ValueError('Current bytes differ from passed N04 catalog: '+name)
            tracked['game/'+name]=source
        for name,expected in report.get('proof_sha256',{}).items():
            proof=relative_file(ROOT,name)
            if sha(proof)!=expected:raise ValueError('Current proof differs from passed N04 catalog: '+name)
            tracked[name]=proof
        for name in ADDITIONS:tracked['game/'+name]=relative_file(ROOT/'game',name)
        for name in LEGAL_SOURCES.values():tracked[name]=relative_file(ROOT,name)
        helpers=source_helpers();tracked.update(helpers)
        tracked['tools/export_macos.py']=Path(__file__)
        tracked['tests/game/offline.sb']=ROOT/'tests/game/offline.sb'
        tracked['evidence_catalog:'+str(catalog_path)]=catalog_path
        before={name:describe(path) for name,path in tracked.items()}
        manifest['source_sha256']={p:before['game/'+p]['sha256'] for p in report['source_sha256']}
        manifest['runtime_sha256']={p:before['game/'+p]['sha256'] for p in report['runtime_sha256']}
        manifest['proof_sha256']={p:before[p]['sha256'] for p in report.get('proof_sha256',{})}
        manifest['v0_addition_sha256']={p:before['game/'+p]['sha256'] for p in ADDITIONS}
        manifest['helper_sha256']={p:before[p]['sha256'] for p in helpers}
        manifest['free_before_bytes']=shutil.disk_usage(output).free
        if manifest['free_before_bytes']<2*1024**3:raise RuntimeError('Less than 2 GiB free; preserved existing files and outputs.')
        environment=os.environ.copy()
        for name in list(environment):
            if name.startswith(('GODOT_MACOS_CODESIGN_','GODOT_MACOS_NOTARIZATION_')) or name=='GODOT_SCRIPT_ENCRYPTION_KEY':environment.pop(name)
        version=run_logged(engine_command(engine,'--version'),'engine_version',output,manifest,environment=environment).stdout.strip()
        if version!=ENGINE_VERSION:raise ValueError('Only pinned '+ENGINE_VERSION+' is supported: '+version)
        manifest['engine']={'path':str(engine),'version':version,**describe(engine)}
        cache_dir=ROOT/'data/cache';cache_dir.mkdir(parents=True,exist_ok=True)
        workspace=Path(tempfile.mkdtemp(prefix='sim2seoul-r03-',dir=cache_dir))
        cleanup=contextlib.nullcontext() if args.keep_workspace else contextlib.ExitStack()
        with cleanup as stack:
            if not args.keep_workspace:stack.callback(shutil.rmtree,workspace)
            manifest['temporary_workspace']={'path':str(workspace),'retained':args.keep_workspace}
            game=workspace/'game';game.mkdir()
            for name in inputs:copy_new(ROOT/'game'/name,game/name)
            for name in ADDITIONS:copy_new(ROOT/'game'/name,game/name)
            for name,source in LEGAL_SOURCES.items():copy_new(ROOT/source,game/name)
            for name,source in helpers.items():copy_new(source,game/'test_support'/Path(name).name)
            validate_templates(args,game,manifest)
            notices=generate_notices(engine,game,workspace,output,manifest,environment)
            manifest['legal_files']={name:{'resource_path':'res://resources/legal/'+name,**describe(path)} for name,path in notices.items()}
            template=legal_template(args.template,workspace,notices,manifest)
            manifest['temporary_project']=prepare_project(game,output)
            manifest['preset']=write_preset(game,template,args.app_version)
            copy_new(game/'export_presets.cfg',output/'export_presets.used.cfg')
            expected={name:describe(game/name) for name in inputs if Path(name).suffix.lower() in ('.json','.txt','.md')}
            expected.update({name:describe(game/name) for name in ADDITIONS if name.endswith('.json')})
            expected.update({'resources/legal/'+name:describe(path) for name,path in notices.items()})
            expected['icudt_godot.dat']=describe(game/'icudt_godot.dat')
            manifest['staged_fileaccess_inputs']=expected
            app=output/'Sim2Seoul.app'
            if app.exists():raise FileExistsError('Refusing to overwrite output app')
            for label,arguments in (
                ('import',('--headless','--editor','--import','--path',game)),
                ('export_release',('--headless','--path',game,'--export-release',PRESET_NAME,app)),
            ):
                result=run_logged(engine_command(engine,*arguments),'godot_'+label,output,manifest,timeout=1800,environment=environment)
                reject_engine_errors(result,label)
                actual_project=sha(game/'project.godot')
                manifest['temporary_project'][label+'_sha256']=actual_project
                if actual_project!=manifest['temporary_project']['temporary_sha256']:
                    raise ValueError('Godot unexpectedly changed temporary project settings during '+label)
            if not app.is_dir():raise RuntimeError('Exporter returned without producing an app')
            with (app/'Contents/Info.plist').open('rb') as stream:plist=plistlib.load(stream)
            if plist.get('CFBundleIdentifier')!=BUNDLE_ID:raise ValueError('Unexpected bundle identifier')
            binary=app/'Contents/MacOS'/plist['CFBundleExecutable']
            archs=run_logged(['/usr/bin/lipo','-archs',binary],'lipo_archs',output,manifest).stdout.split()
            if set(archs)!={'arm64','x86_64'}:raise ValueError('Final executable is not Universal 2')
            run_logged(['/usr/bin/codesign','--verify','--deep','--strict','--verbose=2',app],'codesign_verify',output,manifest)
            display=run_logged(['/usr/bin/codesign','--display','--verbose=4',app],'codesign_display',output,manifest)
            if 'Signature=adhoc' not in display.stdout+display.stderr:raise ValueError('Expected final ad-hoc signature')
            manifest['codesign']={'verified':True,'ad_hoc':True,'notarized':False,'architectures':archs}
            manifest['loose_legal_files']={}
            for name,path in notices.items():
                target=app/'Contents/Resources'/name
                if not target.is_file() or describe(target)!=describe(path):raise ValueError('Loose notice missing or changed: '+name)
                manifest['loose_legal_files'][name]=describe(target)
            manifest['pck']=verify_pck(app,expected,['test_support/'+Path(name).name for name in helpers])
            manifest['icu']['actual_pck_inclusion_verified']=True
            manifest['outputs']={'app':app_inventory(app)}
            archive=output/'Sim2Seoul.zip';zip_app(app,archive,output,manifest)
            manifest['outputs']['zip']={'path':str(archive),**describe(archive),
                'method':'ditto -c -k --sequesterRsrc --keepParent','roundtrip_verified':False}
            if sha(args.template)!=MACOS_SHA256:raise ValueError('Original cached macOS template changed')
        after={name:describe(path) for name,path in tracked.items()}
        manifest['source_preservation']={'passed':before==after,'before':before,'after':after,
            'git_head_after':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
        if before!=after or manifest['source_preservation']['git_head_after']!=head:raise RuntimeError('Input source or Git HEAD changed during export')
        manifest['passed']=True
    except Exception as exc:
        manifest['error']=type(exc).__name__+': '+str(exc)
        if before:
            manifest['source_preservation']={'passed':all(path.is_file() and describe(path)==before[name] for name,path in tracked.items()),'before':before}
        raise
    finally:
        manifest['completed_utc']=dt.datetime.now(dt.timezone.utc).isoformat()
        manifest['free_after_bytes']=shutil.disk_usage(output).free
        write_json_new(output/'manifest.json',manifest)
        print(json.dumps({'passed':manifest['passed'],'manifest':str(output/'manifest.json'),'app':str(output/'Sim2Seoul.app')},ensure_ascii=False))
    return 0


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute',action='store_true',help='Actually import/export/hash/compress; use only after active measurements finish')
    parser.add_argument('--engine',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--catalog',type=Path,default=ROOT/'data/reports/n04/gpu_check.json')
    parser.add_argument('--template',type=Path,default=CACHE/'macos.zip')
    parser.add_argument('--template-archive',type=Path,default=CACHE/TPZ_NAME)
    parser.add_argument('--output-root',type=Path,default=ROOT/'builds/macos')
    parser.add_argument('--app-version',default='0.1.0')
    parser.add_argument('--keep-workspace',action='store_true')
    raise SystemExit(build(parser.parse_args()))

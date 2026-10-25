#!/usr/bin/env python3
"""Build the current complete exploration game for a static ChatGPT Site.
The native checkout is not rewritten. Outputs and editor caches stay ignored.
"""
from pathlib import Path
import argparse,subprocess,shutil,hashlib,json,gzip,re,datetime,os
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(argv,log):
 with log.open('wb') as f:
  result=subprocess.run([str(a) for a in argv],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 text=log.read_text(errors='replace')
 errors=[s for s in text.splitlines() if any(t in s for t in ('ERROR:','SCRIPT ERROR:','Parse Error:'))]
 if result.returncode or errors:raise RuntimeError(str(log)+': '+str(result.returncode)+' '+str(errors[:8]))
 return {'argv':[str(a) for a in argv],'exit':result.returncode,'errors':errors,'log_sha256':digest(log)}
WEB_CHUNK_BYTES = 1024 * 1024

def chunk_file(path, kind, chunks):
 chunks.mkdir(parents=True, exist_ok=True)
 row={'path':'game/index.'+kind,'bytes':path.stat().st_size,'sha256':digest(path),'chunks':[]}
 with path.open('rb') as source:
  index=0
  while data:=source.read(WEB_CHUNK_BYTES):
   sha=hashlib.sha256(data).hexdigest()
   name=f'{kind}-1m-{index:03d}-{sha[:16]}.gz'
   compressed=gzip.compress(data,compresslevel=6,mtime=0)
   (chunks/name).write_bytes(compressed)
   row['chunks'].append({'path':'chunks/'+name,'bytes':len(data),'transferBytes':len(compressed),'sha256':sha,'encoding':'gzip'})
   index+=1
 return row

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--site',type=Path,required=True);ap.add_argument('--tag',required=True);a=ap.parse_args()
 if not re.fullmatch(r'[a-zA-Z0-9_-]+',a.tag):ap.error('simple fresh tag required')
 reports=ROOT/'data/reports/web_sites/20261025'/a.tag;reports.mkdir(parents=True,exist_ok=False)
 stage=ROOT/'data/cache/web-export'/a.tag;stage.mkdir(parents=True,exist_ok=False);project=stage/'game'
 def ignored(folder,names):
  skip={'.godot','.DS_Store','__pycache__'}
  if Path(folder).name=='vendor':skip|={'microsoft_rocketbox','makehuman_swim'}
  return set(names)&skip
 shutil.copytree(ROOT/'game',project,ignore=ignored)
 # Keep source hashes meaningful, including the three exact police-site inputs.
 design=json.loads((project/'assets/authored/police_headquarters.json').read_text())
 for name,expected in design['source_inputs'].items():
  source=ROOT/name;assert digest(source)==expected
  target=project/'web_source'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
 settings=project/'project.godot';s=settings.read_text().replace('run/main_scene="res://scenes/main.tscn"','run/main_scene="res://scenes/world/explore_walk.tscn"').replace('"Forward Plus"','"GL Compatibility"').replace('renderer/rendering_method="forward_plus"','renderer/rendering_method="gl_compatibility"')
 s+='\n[editor]\nexport/convert_text_resources_to_binary=false\n';settings.write_text(s)
 template=ROOT/'data/cache/engine/4.7.2/web-templates/templates/web_nothreads_release.zip';assert template.exists()
 preset='[preset.0]\nname="Web"\nplatform="Web"\nrunnable=true\nadvanced_options=false\ndedicated_server=false\ncustom_features=""\nexport_filter="all_resources"\ninclude_filter="*.json,*.glb,*.wav,*.md,*.txt,*.tres"\nexclude_filter="*.DS_Store"\nexport_path=""\nscript_export_mode=0\n\n[preset.0.options]\ncustom_template/debug=""\ncustom_template/release="__TEMPLATE__"\nvariant/extensions_support=false\nvariant/thread_support=false\nvram_texture_compression/for_desktop=true\nvram_texture_compression/for_mobile=false\nhtml/export_icon=false\nhtml/custom_html_shell=""\nhtml/head_include=""\nhtml/canvas_resize_policy=2\nhtml/focus_canvas_on_start=true\nprogressive_web_app/enabled=false\n'.replace('__TEMPLATE__',str(template))
 (project/'export_presets.cfg').write_text(preset)
 out=stage/'export';out.mkdir();engine=Path(os.environ.get('SIM2SEOUL_GODOT','/Applications/Godot.app/Contents/MacOS/Godot'))
 imported=run([engine,'--headless','--editor','--path',project,'--rendering-method','gl_compatibility','--import','--quit'],reports/'import.log')
 settings.write_text(settings.read_text()+'\n[gui]\ntheme/custom_font="res://assets/fonts/NotoSansKR.ttf"\n')
 exported=run([engine,'--headless','--path',project,'--rendering-method','gl_compatibility','--export-release','Web',out/'index.html'],reports/'export.log')
 expected={}
 for p in project.rglob('*'):
  if p.is_file() and '.godot' not in p.parts and p.suffix in ['.gd','.json','.glb','.wav','.tres']:expected['res://'+str(p.relative_to(project))]=digest(p)
 expected_path=reports/'expected_raw.json';expected_path.write_text(json.dumps(expected,indent=2)+'\n')
 original=out/'index.imported.pck';(out/'index.pck').rename(original)
 repacked=run([engine,'--headless','--main-pack',original,'--script',ROOT/'tools/web/repack_raw.gd','--',project,out/'index.pck',expected_path,reports/'repack.json'],reports/'repack.log')
 checked=run([engine,'--headless','--main-pack',out/'index.pck','--script',ROOT/'tests/game/check_web_pack.gd','--',expected_path,reports/'pack_integrity.json'],reports/'pack_integrity.log')

 dist=a.site.resolve()/'dist';dist.mkdir(parents=True,exist_ok=True);game=dist/'game';game.mkdir(exist_ok=True);chunks=dist/'chunks';chunks.mkdir(exist_ok=True)
 for source in (ROOT/'tools/web/site').glob('*'):
  if source.is_file():shutil.copyfile(source,dist/source.name)
 html=(out/'index.html').read_text();m=re.search(r'(?:const|var) GODOT_CONFIG\s*=\s*',html);assert m,'export config not found';config,_=json.JSONDecoder().raw_decode(html[m.end():])
 (game/'engine-config.json').write_text(json.dumps(config,indent=2)+'\n')
 for p in out.glob('*.js'):shutil.copyfile(p,game/p.name)
 manifest={'engineVersion':'4.7.2','buildCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'files':{}}
 for kind,filename in [('wasm','index.wasm'),('pck','index.pck')]:
  manifest['files'][kind]=chunk_file(out/filename,kind,chunks)
 (game/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 images=dist/'images';images.mkdir(exist_ok=True);shutil.copyfile(ROOT/'data/reports/resident_face_joints/20261025/os/01_world.jpg',images/'seoul.jpg')
 legal=dist/'legal';shutil.copytree(project/'resources/legal',legal,dirs_exist_ok=True)
 (legal/'index.html').write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Sim2Seoul 출처와 라이선스</title><style>body{font:17px/1.8 system-ui;max-width:850px;margin:60px auto;padding:20px}a{color:#145c48}li{margin:10px}</style><h1>출처와 라이선스</h1><p>이 도시는 공개 공간정보와 직접 작성한 게임용 시설을 함께 사용합니다. 원본 위치·형태와 게임 해석을 구분합니다.</p><ul>'+''.join('<li><a href="'+p.name+'">'+p.name+'</a></li>' for p in sorted(legal.iterdir()) if p.is_file())+'</ul><p><a href="../">돌아가기</a></p></html>')
 source={str(p.relative_to(ROOT)):{'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted((ROOT/'game').rglob('*')) if p.is_file() and '.godot' not in p.parts and p.name!='.DS_Store' and not any(x in p.parts for x in ('microsoft_rocketbox','makehuman_swim'))}
 record={'task':'WEB_SITES_EXPORT','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':source,'staged_project':str(project.relative_to(ROOT)),'staged_project_config_sha256':digest(settings),'preset':preset,'import':imported,'export':exported,'repack':repacked,'pack_integrity':checked,'build_script_sha256':digest(Path(__file__)),'files':manifest['files'],'excluded_vendor_reason':'No active scripts/resources load obsolete Microsoft Rocketbox or MakeHuman original rigs. Their source checkout remains intact. Kenney actual active building retained.','native_project_config_unchanged':digest(ROOT/'game/project.godot'),'scope':'Complete exploration scene export, not overview or replacement demo. Browser behavior still requires actual QA.'}
 (reports/'build.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'build':str(reports.relative_to(ROOT)),'pck_bytes':manifest['files']['pck']['bytes'],'wasm_bytes':manifest['files']['wasm']['bytes'],'transfer_bytes':sum(c['transferBytes'] for f in manifest['files'].values() for c in f['chunks'])}))
if __name__=='__main__':main()

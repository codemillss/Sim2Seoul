#!/usr/bin/env python3
"""Run one explicitly selected transport suite; native opens a Godot window.

Usage: python3 tools/run_urban_transit_acceptance.py speed native my_run
Requires setup_mac.sh inputs and Godot; reports are never overwritten.
"""
from pathlib import Path
import subprocess,sys,json,datetime,time,os,argparse,hashlib
root=Path(__file__).resolve().parents[1]
names={'shop':'check_shop_visit','car':'check_drivable_car','helicopter':'check_city_helicopter','pool':'check_pool_preparation','integration':'check_city_life_integration','bike_entry':'check_bike_entry_reliability','bus':'check_city_bus_loop_native','bus_safety':'check_city_bus_loop_safety','library':'check_library_entry_contact','scooter':'check_city_scooter_service','bike':'check_city_bike_service','speed':'check_transport_speed','subway':'check_city_subway','roads':'check_road_surface_detail','rope':'check_city_helicopter_rope','underground':'check_game_underground_connections','escalators':'check_multifloor_escalator','camera':'check_transport_camera_stability','distribution':'check_mobility_distribution','bike_visibility':'check_bike_visibility','takeover':'check_traffic_car_takeover','police':'check_city_public_safety','weather_fire':'check_city_weather_emergency','sandbox_controls':'check_city_sandbox_controls','car_police':'check_stolen_car_arrest','stolen_euljiro':'check_stolen_car_arrest_euljiro','bus_access':'check_bus_stop_access','audio':'check_city_vehicle_audio','hospital':'check_city_hospital','police_facility':'check_police_facility','police_headquarters':'check_police_headquarters','human_motion':'check_human_scale_motion','human_city':'check_human_city_integration','human_appearance':'check_human_appearance','human_portrait':'check_human_appearance_native','human_gait':'check_human_gait_views','human_locomotion':'check_human_locomotion','human_camera':'check_human_presence_camera','human_presence_city':'check_human_presence_city','facilities':'check_facility_interactions'}
names.update({'human_continuity':'check_human_gait_continuity','human_support':'check_human_gait_support','library_pool_life':'check_library_pool_life'})
names.update({'action_freedom':'check_city_action_freedom','action_views':'check_city_action_views','entry_cancel':'check_traffic_entry_cancel','vehicle_pose':'check_vehicle_transition_pose'})
names.update({'authored_resident':'check_authored_resident','authored_combat':'check_authored_combat_pose','police_dispatch':'check_police_dispatch_response','upper_gait':'check_human_upper_gait','stable_motion':'check_stable_motion','human_actions':'check_human_authored_actions','jump':'check_jump'})
names.update({'character_preview':'preview_authored_resident','driver_reaction':'check_departed_driver_reaction'})
names.update({'customization':'check_character_customization'})
names.update({'human_materials':'check_human_skin_materials'})
names.update({'swim_arm_skin':'check_swim_arm_skin'})
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('suite', choices=names)
parser.add_argument('mode', choices=['headless','native'])
parser.add_argument('tag', help='Fresh simple run tag; existing evidence is preserved')
parser.add_argument('--fixed-fps', type=int, choices=[60,120], help='Headless simulation acceleration only; never a performance claim')
parser.add_argument('--physics-hz', type=int, choices=[30,60,120], help='Explicit production fixture physics rate, when supported by the selected suite')
parser.add_argument('--female-model', action='store_true', help='Explicit female human portrait/gait fixture; does not modify the normal game preference')
parser.add_argument('--body-profile', choices=['standard','soft','athletic'], help='Explicit authored body geometry profile for combat or gait observation')
parser.add_argument('--swim-body', action='store_true', help='Explicit authored swim-body pose observation; not an in-water combat gameplay claim')
parser.add_argument('--output-dir', type=Path, default=Path('data/reports/urban_transit/20261021/acceptance'), help='Project-relative evidence folder; historical runs retain the EXP25 default')
opts=parser.parse_args()
if opts.fixed_fps and opts.mode!='headless':parser.error('--fixed-fps is headless only')
if opts.female_model and opts.suite not in ['human_portrait','human_gait','human_continuity','upper_gait','stable_motion','human_actions','authored_combat']:parser.error('--female-model is for human portrait/gait/action fixtures only')
if opts.body_profile and opts.suite not in ['human_gait','authored_combat']:parser.error('--body-profile is for gait/combat fixtures only')
if opts.swim_body and opts.suite!='authored_combat':parser.error('--swim-body is for authored combat pose observation only')
if opts.physics_hz and opts.suite not in ['human_continuity','upper_gait']:parser.error('--physics-hz is for continuity/upper gait fixtures only')
suite,mode,tag=opts.suite,opts.mode,opts.tag
if not tag.replace('_','').replace('-','').isalnum():parser.error('tag must be alphanumeric with underscores or hyphens')
destination=(root/opts.output_dir).resolve()
if not destination.is_relative_to(root/'data/reports'):parser.error('--output-dir must be inside project data/reports')
base=destination/f'{suite}_{mode}_{tag}'
base.parent.mkdir(parents=True,exist_ok=True)
if any(base.parent.glob(base.name+'*')):parser.error('run tag already exists; choose a new tag')
args=[os.environ.get('SIM2SEOUL_GODOT','/Applications/Godot.app/Contents/MacOS/Godot')]
if mode=='headless':
 args+=['--headless']
 if opts.fixed_fps:args+=['--fixed-fps',str(opts.fixed_fps)]
args+=['--path',str(root/'game'),'--log-file',str(base)+'.log','--script',f'res://../tests/game/{names[suite]}.gd','--','--automatic-probe','--report='+str(base)+'.json']
if opts.female_model:args+=['--female-model']
if opts.body_profile:args+=['--body-profile='+opts.body_profile]
if opts.swim_body:args+=['--swim-body']
if opts.physics_hz:args+=['--physics-hz='+str(opts.physics_hz)]
def source_bindings():
 paths=list((root/'game/scripts').rglob('*.gd'))+[root/'game/project.godot',root/'tests/game'/f'{names[suite]}.gd',Path(__file__).resolve()]
 paths+=list((root/'game/assets/original').rglob('*'))
 paths+=list((root/'tools/authored_character').rglob('*.py'))
 return {str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(set(paths)) if path.is_file()}
bindings_before=source_bindings()
started=datetime.datetime.now(datetime.timezone.utc).isoformat();now=time.monotonic()
print('RUN',suite,mode,flush=True)
try:
 result=subprocess.run(args,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
 code=result.returncode;output=result.stdout.decode(errors='replace')
except subprocess.TimeoutExpired as e:
 code=124;output=(e.output or b'').decode(errors='replace')
Path(str(base)+'.console.log').write_text(output)
script_errors=any(marker in output for marker in ['SCRIPT ERROR:', 'Parse Error:', 'Failed to load script'])
if script_errors:code=code or 2
bindings_after=source_bindings()
changed_sources=[path for path in sorted(bindings_before.keys()|bindings_after.keys()) if bindings_before.get(path)!=bindings_after.get(path)]
metadata={'suite':suite,'mode':mode,'headless_fixed_fps':opts.fixed_fps,'physics_hz':opts.physics_hz,'body_profile':opts.body_profile,'female_model':opts.female_model,'swim_body':opts.swim_body,'started_at':started,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'wall_seconds':round(time.monotonic()-now,3),'returncode':code,'script_errors':script_errors,'argv':args,'source_sha256':bindings_before,'source_changes_during_run':changed_sources,'scope':'Engine CLI test. OS keyboard and visual review are separate evidence. Source changes invalidate a final frozen-source acceptance claim.'}
Path(str(base)+'.run.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n')
path=Path(str(base)+'.json')
if path.exists():
 data=json.loads(path.read_text());checks=data.get('checks',[]);fails=[r.get('name',r.get('check',str(r))) for r in checks if r.get('passed') is not True]
 print(json.dumps({'report':str(path.relative_to(root)),'returncode':code,'passed':len(checks)-len(fails),'total':len(checks),'failed':fails,'captures':len(data.get('captures',[]))},ensure_ascii=False))
else: print('NO_REPORT',output[-3500:])
if script_errors:
 code=code or 2
 print('SCRIPT_ERRORS_DETECTED',output[-2200:])
if code:print(output[-2200:])
sys.exit(code)

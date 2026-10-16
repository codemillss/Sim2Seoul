extends SceneTree
var scene
var module
var group:Dictionary
var checks:=[]
func _initialize()->void:run.call_deferred()
func ticks(n:int)->void:
 for i in range(n):await physics_frame
 await process_frame
func check(n:String,p:bool,e:Dictionary={})->void:
 checks.append({"name":n,"passed":p,"evidence":e})
 if not p:push_warning("MUSEUM_PATROL_FAIL "+n)
func clean(v:Variant)->Variant:
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Vector2:return [v.x,v.y]
 if v is Transform3D:return {"origin":clean(v.origin),"basis":[clean(v.basis.x),clean(v.basis.y),clean(v.basis.z)]}
 if v is AABB:return {"position":clean(v.position),"size":clean(v.size)}
 if v is Dictionary:
  var d:={}
  for k in v:d[str(k)]=clean(v[k])
  return d
 if v is Array:
  var d:=[]
  for x in v:d.append(clean(x))
  return d
 return v
func run()->void:
 Engine.physics_ticks_per_second=60;Engine.max_fps=0
 scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/museum_patrol.settings.json";scene.quality_settings_path="/private/tmp/museum_patrol.quality.json";root.add_child(scene);await ticks(18)
 module=scene.get("street_pedestrians")
 if not is_instance_valid(module):module=load("res://scripts/street_pedestrians.gd").new();scene.add_child(module);module.setup(scene.city,scene.player,scene.rig)
 check("integrated_actual_city_setup",scene.runtime_ok and module.loaded,{"skips":module.skipped})
 if not module.loaded:finish({});return
 for row:Dictionary in module.groups:
  if row.id=="museum_slope":group=row
 var actor:CharacterBody3D=group.members[0].body
 var start:=actor.global_position;await ticks(360)
 check("hill_continues_past_former_stall",actor.global_position.distance_to(start)>5.5,{"actual_metres":actor.global_position.distance_to(start),"station":group.station})
 scene.set_pedestrians_running(false);await ticks(60);var stopped:=actor.global_position;var stopped_station:float=group.station
 scene.set_pedestrians_running(true);await ticks(90)
 check("checkbox_resume_hill_moves_without_reset",actor.global_position.distance_to(stopped)>1.0 and group.station>stopped_station,{"actual_metres":actor.global_position.distance_to(stopped),"before_station":stopped_station,"after_station":group.station})
 var min_station:float=group.station;var max_station:float=group.station;var minimum_grounded:=8;var max_route_error:=0.;var minimum_y:=INF;var maximum_y:float=-INF;var endpoints:=[];var last_turns:int=group.turns;var first_turns:int=group.turns;var ticks_count:=0
 for i in range(5400):
  await ticks(1);ticks_count+=1
  min_station=minf(min_station,group.station);max_station=maxf(max_station,group.station)
  minimum_y=minf(minimum_y,actor.global_position.y);maximum_y=maxf(maximum_y,actor.global_position.y)
  var p:Vector3=module._at(group,group.station);max_route_error=maxf(max_route_error,Vector2(p.x-actor.global_position.x,p.z-actor.global_position.z).length())
  var grounded:=0
  for row:Dictionary in module.actors:
   if row.body.is_on_floor():grounded+=1
  minimum_grounded=mini(minimum_grounded,grounded)
  if group.turns!=last_turns:endpoints.append({"station":group.station,"position":actor.global_position,"direction":group.direction,"physics_tick":Engine.get_physics_frames()});last_turns=group.turns
  if group.turns>=first_turns+3 and min_station<.04 and max_station>group.length-.04:break
 var evidence:={"ticks":ticks_count,"source_station_min":min_station,"source_station_max":max_station,"route_length":group.length,"turns_delta":group.turns-first_turns,"endpoint_events":endpoints,"max_route_error_m":max_route_error,"grounded_min":minimum_grounded,"actual_y_range":[minimum_y,maximum_y],"source_arc_unit":"XZ metres; fraction projection onto continuous mitered offset path"}
 check("complete_hill_patrol_both_directions_and_three_endpoint_reversals",group.turns>=first_turns+3 and min_station<.04 and max_station>group.length-.04,evidence)
 check("hill_and_other_actors_keep_physical_ground_and_path",minimum_grounded==8 and max_route_error<.02,evidence)
 finish(evidence)
func finish(evidence:Dictionary)->void:
 var failed:=0
 for c in checks:
  if not c.passed:failed+=1
 var report:={"result":"PASS" if failed==0 else "FAIL","checks":checks,"summary":{"checks":checks.size(),"failed":failed},"patrol":evidence,"final":module.snapshot(),"source_sha256":{"gd":FileAccess.get_sha256("res://scripts/street_pedestrians.gd"),"json":FileAccess.get_sha256("res://assets/authored/street_pedestrians.json")},"scope":"Actual production-integrated world and controller, 60Hz unmodified physics, accelerated scheduling through --fixed-fps60, no actor teleport after setup. Headless only, no rendered appearance acceptance."}
 FileAccess.open("/private/tmp/sim2seoul_museum_patrol_probe.json",FileAccess.WRITE).store_string(JSON.stringify(clean(report),"\t"))
 print("MUSEUM_PATROL_PROBE ",report.result," ",report.summary," patrol=",evidence)
 quit(0 if failed==0 else 1)

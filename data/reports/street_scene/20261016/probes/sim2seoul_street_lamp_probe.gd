extends SceneTree
var scene
func _initialize()->void:run.call_deferred()
func ticks(n:int)->void:
 for index in range(n):await physics_frame
 await process_frame
func clean(v:Variant)->Variant:
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Transform3D:return {"origin":clean(v.origin),"basis":[clean(v.basis.x),clean(v.basis.y),clean(v.basis.z)]}
 if v is Dictionary:
  var result:={}
  for key in v:result[str(key)]=clean(v[key])
  return result
 if v is Array:
  var result:=[]
  for item in v:result.append(clean(item))
  return result
 return v
func run()->void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate()
 scene.exploration_settings_path="/private/tmp/street_lamp_probe.settings.json";scene.quality_settings_path="/private/tmp/street_lamp_probe.quality.json"
 root.add_child(scene);await ticks(12)
 var life:Node3D=scene.street_life
 scene._visit_street_detail("busking");await ticks(3)
 scene.set_time_profile("night");scene.apply_quality("low")
 var busker:Vector3=life.performers[0].actor.global_position
 var nearest:Dictionary={};var best:=INF
 for lamp:Dictionary in life.lamps:
  var distance:float=lamp.light.global_position.distance_to(busker+Vector3.UP*1.2)
  if distance<best:best=distance;nearest=lamp
 var state:Dictionary=life.snapshot();var bad:=[]
 for anchor:Dictionary in state.anchors:
  if not anchor.protection.clear:bad.append(anchor.id)
 var pass_counts:bool=state.counts.get("parked_cars",0)==3 and state.counts.get("motorcycles",0)==3 and state.bird_count==6 and state.performer_count==4 and state.lamp_count==10 and state.skipped.is_empty()
 var pass_lamp:bool=best<5. and nearest.light.visible and nearest.light.omni_range==12. and nearest.light.light_energy>2. and state.active_lights<=4
 var passed:bool=scene.runtime_ok and pass_counts and pass_lamp and bad.is_empty()
 var result:={"result":"PASS" if passed else "FAIL","counts_correct":pass_counts,"stage_lamp_actual_coverage":pass_lamp,"bad_protection":bad,"stage_lamp_world_position":nearest.actor.global_position,"stage_light_world_position":nearest.light.global_position,"stage_light_to_busker_torso_m":best,"stage_lamp_station_m":nearest.station_m,"busker":busker,"source_sha256":{"street_life.gd":FileAccess.get_sha256("res://scripts/street_life.gd"),"street_life.json":FileAccess.get_sha256("res://assets/authored/street_life.json")},"snapshot":state,"scope":"Headless actual city counts, guarded lamp placement and active actual OmniLight range/energy. GPU performer visibility requires final native image review."}
 var f:=FileAccess.open("/private/tmp/sim2seoul_street_lamp_probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(clean(result),"\t"));f.close()
 print("STREET_LAMP_PROBE ",result.result," counts=",state.counts," skipped=",state.skipped," stage_to_torso_m=",best," stage_station_m=",nearest.station_m," low_active=",state.active_lights)
 quit(0 if passed else 1)

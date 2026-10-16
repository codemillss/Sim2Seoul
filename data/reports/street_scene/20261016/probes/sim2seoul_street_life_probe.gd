extends SceneTree
var scene
var life
var checks:=[]
func check(n:String,p:bool,e:Dictionary={})->void:
 checks.append({"name":n,"passed":p,"evidence":e})
 if not p:push_warning("STREET_LIFE_PROBE_FAIL "+n)
func inv()->Dictionary:
 var d:={}
 for c in [scene.city.bodies,scene.city.fragments]:
  for id in c:
   var b:StaticBody3D=c[id];var s:CollisionShape3D=b.get_node("CollisionShape")
   d[id]=[b.get_instance_id(),b.collision_layer,b.collision_mask,str(b.global_transform),s.shape.get_instance_id(),s.disabled]
 return d
func ticks(n:int)->void:
 for i in range(n):await physics_frame
 await process_frame
func clean(v:Variant)->Variant:
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Transform3D:return {"origin":clean(v.origin),"basis":[clean(v.basis.x),clean(v.basis.y),clean(v.basis.z)]}
 if v is Dictionary:
  var d:={}
  for k in v:d[str(k)]=clean(v[k])
  return d
 if v is Array:
  var a:=[]
  for x in v:a.append(clean(x))
  return a
 return v
func _initialize()->void:run.call_deferred()
func run()->void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate()
 scene.exploration_settings_path="/private/tmp/street_life_probe.settings.json";scene.quality_settings_path="/private/tmp/street_life_probe.quality.json"
 root.add_child(scene);await ticks(24)
 var before:=inv()
 life=scene.get("street_life")
 if is_instance_valid(life):check("setup",life.loaded,{"method":"reuse production root-integrated StreetLife"})
 else:
  life=load("res://scripts/street_life.gd").new();scene.add_child(life);check("setup",life.setup(scene.city,scene.player,scene.rig))
 await ticks(3)
 var first:Dictionary=life.snapshot()
 check("source_collision_unchanged_after_setup",before==inv(),{"source_count":before.size()})
 check("cars_bikes_present",int(first.counts.get("parked_cars",0))>0 and int(first.counts.get("motorcycles",0))>0)
 check("birds_people_lamps_present",first.bird_count>=4 and first.performer_count>=2 and first.lamp_count>=6)
 var bad:=[]
 for a:Dictionary in first.anchors:
  if not a.protection.clear:bad.append(a.id)
 check("protected_paths_entrances_traffic_clear",bad.is_empty(),{"bad":bad})
 check("day_lights_off",first.active_lights==0)
 check("evening_valid",life.set_time_profile("evening"))
 var evening:Dictionary=life.snapshot();check("evening_actual_lights",evening.active_lights>0 and evening.active_lights<=8)
 check("night_valid",life.set_time_profile("night"))
 var night:Dictionary=life.snapshot();check("night_actual_lights",night.active_lights>0 and night.active_lights<=8)
 check("invalid_time_rejected",not life.set_time_profile("invalid") and life.time_profile=="night")
 var max_move:=0.;var states:={}
 for i in range(540):
  await ticks(1)
  for b:Dictionary in life.snapshot().birds:
   var delta:Vector3=b.position-b.anchor;max_move=maxf(max_move,Vector2(delta.x,delta.z).length());states[b.state]=true
 check("bounded_birds_actually_peck_walk_fly",max_move>.2 and max_move<=.801 and states.has_all(["peck","walk","flight"]),{"max_horizontal_excursion_m":max_move,"states":states.keys()})
 var a:Dictionary=life.snapshot();paused=true;await ticks(18);var b:Dictionary=life.snapshot()
 check("pause_freezes_real_actor_pose_and_clock",a.elapsed==b.elapsed and a.birds==b.birds and a.performers==b.performers)
 paused=false;await ticks(3)
 check("source_collision_unchanged_after_animation",before==inv())
 var failed:=0
 for c in checks:
  if not c.passed:failed+=1
 var report:={"result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"source_sha256":{"street_life.gd":FileAccess.get_sha256("res://scripts/street_life.gd"),"street_life.json":FileAccess.get_sha256("res://assets/authored/street_life.json")},"checks":checks,"initial":first,"evening":evening,"night":night,"final":life.snapshot(),"scope":"Headless real city setup and bounded native node animation only. No rendered GPU illumination, native human handling, real parking/bird/event/fixture locations or audio verified."}
 var f:=FileAccess.open("/private/tmp/sim2seoul_street_life_probe.json",FileAccess.WRITE);f.store_string(JSON.stringify(clean(report),"\t"));f.close()
 print("STREET_LIFE_PROBE ",report.result," ",report.summary," counts=",first.counts," birds=",first.bird_count," people=",first.performer_count," lamps=",first.lamp_count," skips=",first.skipped)
 quit(0 if failed==0 else 1)

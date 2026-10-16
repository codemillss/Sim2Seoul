extends SceneTree
var scene
var module
var checks:=[]
func _initialize()->void:run.call_deferred()
func ticks(n:int)->void:
 for index in range(n):await physics_frame
 await process_frame
func check(n:String,p:bool,e:Dictionary={})->void:
 checks.append({"name":n,"passed":p,"evidence":e})
 if not p:push_warning("STREET_PED_FAIL "+n)
func clean(v:Variant)->Variant:
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Vector2:return [v.x,v.y]
 if v is Transform3D:return {"origin":clean(v.origin),"basis":[clean(v.basis.x),clean(v.basis.y),clean(v.basis.z)]}
 if v is AABB:return {"position":clean(v.position),"size":clean(v.size)}
 if v is Dictionary:
  var r:={}
  for k in v:r[str(k)]=clean(v[k])
  return r
 if v is Array:
  var r:=[]
  for x in v:r.append(clean(x))
  return r
 return v
func run()->void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/street_ped.settings.json";scene.quality_settings_path="/private/tmp/street_ped.quality.json";root.add_child(scene);await ticks(18)
 module=load("res://scripts/street_pedestrians.gd").new();scene.add_child(module)
 check("setup",module.setup(scene.city,scene.player,scene.rig),{"skips":module.skipped})
 if not module.loaded:finish();return
 await ticks(2)
 var initial:Dictionary=module.snapshot();var minimum_floor:=8;var max_foot_error:=0.;var legs_moved:=false
 for i in range(600):
  await ticks(1)
  var floor_count:=0
  for row:Dictionary in module.actors:
   if row.body.is_on_floor():floor_count+=1
   if row.kind=="dog":
    for leg:Dictionary in row.legs:
     if absf(leg.joint.rotation.x)>.1:legs_moved=true
     var paw:Vector3=leg.paw.global_position
     var hit:Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(paw+Vector3.UP*.4,paw-Vector3.UP*.5,1|32))
     if not hit.is_empty():max_foot_error=maxf(max_foot_error,absf((paw.y-.0325)-hit.position.y))
  if i>20:minimum_floor=mini(minimum_floor,floor_count)
 var normal:Dictionary=module.snapshot()
 var all_move:=true;var humanoids_move:=true
 for row:Dictionary in normal.actors:
  if row.actual_distance_m<1.:all_move=false
  if row.kind=="walker" and row.avatar.clock<.5:humanoids_move=false
 check("all8_actual_physical_walking",all_move,{"routes":normal.routes,"actors":normal.actors})
 check("grounded_including_slope",minimum_floor==8,{"minimum_grounded":minimum_floor})
 check("human_and_fourleg_dog_gaits_move",humanoids_move and legs_moved and max_foot_error<.09,{"dog_stance_error_m":max_foot_error})
 check("bounded_steps_traffic_guards_and_registered",normal.maximum_step_m<.025 and normal.traffic_registration_count==8 and normal.minimum_neighbor_distance_m>.70,{"max_step":normal.maximum_step_m,"min_neighbor":normal.minimum_neighbor_distance_m})
 check("visible_bounded_leashes",normal.maximum_leash_length_m<=1.40 and normal.leash_blocked_ticks==0,{"max_leash_m":normal.maximum_leash_length_m,"blocked_ticks":normal.leash_blocked_ticks})
 var before:Dictionary=module.snapshot();paused=true;await ticks(20);var after:Dictionary=module.snapshot()
 check("pause_exact_clock_body_joint_and_leash",before==after)
 paused=false
 finish()
func finish()->void:
 var failed:=0
 for c in checks:
  if not c.passed:failed+=1
 var report:={"result":"PASS" if failed==0 else "FAIL","checks":checks,"summary":{"checks":checks.size(),"failed":failed},"final":module.snapshot(),"source_sha256":{"gd":FileAccess.get_sha256("res://scripts/street_pedestrians.gd"),"json":FileAccess.get_sha256("res://assets/authored/street_pedestrians.json")}}
 FileAccess.open("/private/tmp/sim2seoul_street_ped_probe.json",FileAccess.WRITE).store_string(JSON.stringify(clean(report),"\t"))
 print("STREET_PED_PROBE ",report.result," ",report.summary," skips=",module.skipped)
 quit(0 if failed==0 else 1)

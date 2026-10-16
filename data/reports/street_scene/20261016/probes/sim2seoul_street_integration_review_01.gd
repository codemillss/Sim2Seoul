extends SceneTree
var scene
var observations:=[]
var failures:=[]
func _initialize()->void:run.call_deferred()
func ticks(n:int)->void:
 for i in range(n):await physics_frame
 await process_frame
func vec(v:Vector3)->Array:return [v.x,v.y,v.z]
func record(name:String,passed:bool,data:Dictionary={})->void:
 observations.append({"name":name,"passed":passed,"data":data})
 if not passed:failures.append(name)
func run()->void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate()
 scene.exploration_settings_path="/private/tmp/street_integration_review.settings.json"
 scene.quality_settings_path="/private/tmp/street_integration_review.quality.json"
 root.add_child(scene);await ticks(18)
 record("runtime",scene.runtime_ok)
 for kind in ["restaurant","busking","hill"]:
  if not scene.menu.visible:scene.toggle_menu()
  var previous_recoveries:int=scene.player.recoveries
  scene._visit_street_detail(kind)
  var position:Vector3=scene.player.global_position
  var toward:=Vector3.ZERO
  if kind=="restaurant":toward=scene.street_businesses.stores[0].node.global_position
  elif kind=="busking":
   for row:Dictionary in scene.street_life.performers:
    if row.kind=="busker":toward=row.actor.global_position
  else:toward=scene.museum_approach.point_at_station(10.)
  var forward:Vector3=-scene.rig.camera.global_basis.z;forward.y=0;forward=forward.normalized()
  var intended:Vector3=toward-position;intended.y=0;intended=intended.normalized()
  var pivot_error:float=scene.rig.global_position.distance_to(position+Vector3.UP*scene.rig.pivot_height_m)
  var capsule:CollisionShape3D=scene.player.get_node("CollisionShape")
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,position)*capsule.transform;query.collision_mask=scene.player.collision_mask;query.exclude=[scene.player.get_rid()]
  var clear:bool=scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
  record("shortcut."+kind,clear and forward.dot(intended)>.9999 and pivot_error<.001 and not paused and not scene.menu.visible and scene.player.velocity==Vector3.ZERO,{"position":vec(position),"distance_m":scene.rig.current_distance,"facing_dot":forward.dot(intended),"immediate_pivot_error_m":pivot_error,"clear":clear,"neutral":scene.player.input_latched})
  await ticks(12)
  record("shortcut."+kind+".settled",scene.player.is_on_floor() and scene.player.recoveries==previous_recoveries,{"position":vec(scene.player.global_position),"distance_m":scene.rig.current_distance})
 scene._visit_street_detail("busking");await ticks(8)
 if not scene.menu.visible:scene.toggle_menu()
 var old_elapsed:float=scene.street_life.elapsed
 for id in ["night","evening","day"]:
  var index:int=scene.TIME_IDS.find(id)
  scene.time_option.item_selected.emit(index)
  scene.apply_quality("light")
  var state:Dictionary=scene.street_life.snapshot()
  record("time."+id,scene.time_id==id and scene.photo_atmosphere.time_profile==id and state.time_profile==id and paused and old_elapsed==state.elapsed and (state.active_lights==0 if id=="day" else state.active_lights>0 and state.active_lights<=4),{"lights":state.active_lights,"sun_energy":scene.photo_atmosphere.sun.light_energy,"sky_top":str(scene.photo_atmosphere.sky_material.sky_top_color),"paused":paused})
 var original_path:String=scene.exploration_settings_path
 var output:=FileAccess.open(original_path+".time.json",FileAccess.WRITE);output.store_string('{"schema_version":true,"time_id":"night"}');output.close()
 record("preferences.boolean_schema_rejected",scene._read_street_time()=="day")
 record("preferences.speed_schema_remains_three_keys",scene._read_exploration_settings().size()==3 and scene.speed_id=="brisk")
 paused=false
 var result:={"result":"PASS" if failures.is_empty() else "FAIL","observations":observations,"failures":failures,"scope":"Read-only production-source review with isolated temporary preferences. Actual headless nodes, collision queries, immediate camera snaps and paused UI callbacks; no GPU image acceptance."}
 var file:=FileAccess.open("/private/tmp/sim2seoul_street_integration_review.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
 print("STREET_INTEGRATION_REVIEW ",result.result," ",observations.size()," failures=",failures)
 quit(0 if failures.is_empty() else 1)

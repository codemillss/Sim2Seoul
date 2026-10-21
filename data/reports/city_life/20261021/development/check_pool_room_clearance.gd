extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
 var scene: Node3D=load("res://scenes/world/explore_walk.tscn").instantiate()
 scene.exploration_settings_path="/tmp/pool-room-clearance-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene)
 for tick: int in range(8):await scene.rig.camera_stepped
 var rows: Array=[];var ok: bool=scene.runtime_ok;var inspected:=0
 for roof: Node3D in scene.pool_preparation_service._roofs():
  var new_bodies: Array[StaticBody3D]=[];var excludes: Array[RID]=[scene.player.get_rid()]
  for body: StaticBody3D in roof.bodies:
   if String(body.get_meta("geometry_id","")).begins_with("EXP08_rooftop_PoolChanging") or String(body.get_meta("geometry_id","")).begins_with("EXP08_rooftop_PoolShower") or String(body.get_meta("geometry_id","")).begins_with("EXP08_rooftop_PoolLocker"):
    new_bodies.append(body);excludes.append(body.get_rid())
   elif String(body.get_meta("geometry_id","")).begins_with("EXP08_rooftop_DeckFloor"):excludes.append(body.get_rid())
  for body: StaticBody3D in new_bodies:
   for child: Node in body.get_children():
    if not child is CollisionShape3D:continue
    var query:=PhysicsShapeQueryParameters3D.new();query.shape=child.shape;query.transform=child.global_transform;query.collision_mask=47;query.exclude=excludes;query.margin=.0001
    var hits: Array=[]
    for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,32):hits.append(String(hit.collider.get_path()))
    rows.append({"roof":roof.spec.id,"body":String(body.name),"overlapping_existing_solids":hits});ok=ok and hits.is_empty();inspected+=1
 var output: Dictionary={"task":"pool_new_room_native_clearance","result":"PASS" if ok and inspected>0 else "FAIL","inspected_native_shapes":inspected,"rows":rows,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"recorded_at":Time.get_datetime_string_from_system(true),"source_hashes":{"res://scripts/rooftop_space.gd":FileAccess.get_sha256("res://scripts/rooftop_space.gd"),"res://scripts/pool_preparation_service.gd":FileAccess.get_sha256("res://scripts/pool_preparation_service.gd")},"scope":"Actual native full preparation-room shapes against retained world/roof fixtures/actors. Only their own assembly and supporting deck panels are excluded; original pillars, lift, lounge and all other physical actors remain queried. No visual appearance acceptance."}
 var file:=FileAccess.open("/tmp/pool-room-clearance.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close();print("POOL_ROOM_CLEARANCE ",output.result," shapes=",inspected);quit(0 if output.result=="PASS" else 1)

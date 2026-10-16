extends SceneTree
## Roof regions are authored at source-world XZ; scenario starts are test-only.
const IDS := ["osm:relation:10757525:building","osm:way:233593619:building","osm:way:223158445:building"]
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var report_path := ""
var scene
var visit
var checks: Array = []
var catalog_rows: Array = []
var captures: Array = []
var trials: Array = []
var source_hashes := {}
var original_inventory := {}
var finished := false
var capsule := CapsuleShape3D.new()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("check_rooftops needs absolute --report");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	capsule.radius=.30;capsule.height=1.70
	Engine.physics_ticks_per_second=60
	create_timer(360.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Vector2:return [v.x,v.y]
	if v is Rect2:return [v.position.x,v.position.y,v.size.x,v.size.y]
	if v is AABB:return {"position":_json(v.position),"size":_json(v.size)}
	if v is Transform3D:return {"origin":_json(v.origin),"basis":[_json(v.basis.x),_json(v.basis.y),_json(v.basis.z)]}
	if v is Dictionary:
		var out := {}
		for key in v:out[str(key)]=_json(v[key])
		return out
	if v is Array:
		var out := []
		for item in v:out.append(_json(item))
		return out
	return v

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("ROOFTOP_CHECK_FAIL "+title)

func _ticks(n: int) -> void:
	for i in range(n):await physics_frame
	await process_frame

func _keys() -> void:
	for action in ACTIONS:Input.action_release(action)

func _e(held: bool) -> void:
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.keycode=KEY_E;event.pressed=held;Input.parse_input_event(event)

func _inventory() -> Dictionary:
	var out := {}
	for group in [scene.city.bodies,scene.city.fragments]:
		for id in group:
			var body: StaticBody3D=group[id]
			var node: CollisionShape3D=body.get_node("CollisionShape")
			out[id]={"id":body.get_instance_id(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":str(body.transform),"shape":node.shape.get_instance_id(),"shape_transform":str(node.transform),"disabled":node.disabled,"faces":hash(node.shape.get_faces()) if node.shape is ConcavePolygonShape3D else 0}
	return out

func _clear(point: Vector3) -> Dictionary:
	var space:=root.get_world_3d().direct_space_state
	var ray:=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1,[scene.player.get_rid()]))
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.85);query.collision_mask=1;query.exclude=[scene.player.get_rid()]
	var hits:=space.intersect_shape(query,8)
	var names:=[]
	for hit in hits:names.append(String(hit.collider.name))
	return {"point":point,"floor_hit":not ray.is_empty(),"floor_gap":point.y-ray.position.y if not ray.is_empty() else INF,"capsule_hits":names,"supported_clear":not ray.is_empty() and ray.normal.y>.7 and absf(point.y-ray.position.y-.08)<.05 and hits.is_empty()}

func _in_source(point: Vector3, spec: Dictionary) -> bool:
	var p:=Vector2(point.x,point.z)
	var rings: Array=spec.source_rings[int(spec.source_part_index)]
	for index in range(rings.size()):
		var ring:=PackedVector2Array()
		for xy: Array in rings[index]:ring.append(Vector2(float(xy[0]),float(xy[1])))
		var inside:=Geometry2D.is_point_in_polygon(p,ring)
		if index==0 and not inside:return false
		if index>0 and inside:return false
	return true

func _catalog() -> void:
	var errors:=[];var profiles:={};var count:=0;var shape_queries:=0;var observed_features:={}
	for spec: Dictionary in visit.catalog:
		var roof: Node3D=load("res://scripts/rooftop_space.gd").new();scene.add_child(roof)
		if not roof.setup(scene,spec):errors.append({"id":spec.id,"kind":"setup"});roof.free();continue
		await _ticks(3);count+=1
		profiles[roof.profile_id]=int(profiles.get(roof.profile_id,0))+1
		var required: Array={"garden":["GardenBed","BenchSeat","PergolaPost","TreeCrown"],"outdoor_pool":["PoolSafetyFloor","PoolWaterSurface","SunLounger","ParasolCanopy"],"penthouse":["PenthouseGlassSide","PenthouseOpenDoor","PenthouseSofa","PenthouseCanopy"]}.get(roof.profile_id,[])
		var actual:=[]
		for title: String in required:
			var visual:=roof.get_node_or_null(NodePath(title))
			if visual is MeshInstance3D and visual.mesh!=null:actual.append(title)
			else:errors.append({"id":spec.id,"kind":"missing_actual_profile_mesh","name":title})
		observed_features[roof.profile_id]=actual
		var frame: Transform3D=roof.frame
		var rect: Rect2=roof.walkable_rect
		if not is_equal_approx(frame.basis.determinant(),1.):errors.append({"id":spec.id,"kind":"mirrored_frame","determinant":frame.basis.determinant()})
		for local in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
			var world: Vector3=frame*Vector3(local.x,0,local.y)
			if not _in_source(world,spec):errors.append({"id":spec.id,"kind":"outside_source_footprint","point":world})
		var center: Vector2=spec.rectangle_center
		if Vector2(frame.origin.x,frame.origin.z).distance_to(center)>.01 or frame.origin.y<float(spec.source_height):errors.append({"id":spec.id,"kind":"source_world_placement","origin":frame.origin,"source_height":spec.source_height})
		for point: Vector3 in [roof.spawn_point(),roof.lift_point()]:
			shape_queries+=1
			var observed:=_clear(point)
			if not observed.supported_clear or not roof.world_bounds.has_point(point):errors.append({"id":spec.id,"kind":"landing","observation":observed})
		if roof.profile_id=="outdoor_pool":
			for point: Vector3 in [roof.pool_entry_point(),roof.pool_rim_point()]:
				shape_queries+=1
				var observed:=_clear(point)
				if not observed.supported_clear or not roof.world_bounds.has_point(point):errors.append({"id":spec.id,"kind":"pool_entry_or_rim","observation":observed})
		if roof.profile_id=="penthouse":
			var back: float=-roof.depth*.5+1.1
			var front: float=back+minf(9.5,roof.depth-7.0)
			for index in range(12):
				shape_queries+=1
				var point: Vector3=frame*Vector3(0,.08,lerpf(front+1.0,back+1.0,float(index)/11.))
				var observed:=_clear(point)
				if not observed.supported_clear:errors.append({"id":spec.id,"kind":"penthouse_open_door_corridor","observation":observed})
		for body: StaticBody3D in roof.bodies:
			if body.collision_layer!=1 or body.collision_mask!=0:errors.append({"id":spec.id,"kind":"collision_layer","body":body.name})
		catalog_rows.append({"id":spec.id,"profile":roof.profile_id,"frame":frame,"walkable_rect":rect,"source_height":spec.source_height,"new_bodies":roof.bodies.size()})
		roof.free()
	_check("catalog.all_125_roofs_source_world_safe_landings",count==125 and errors.is_empty(),{"buildings":count,"landing_queries":shape_queries,"profiles":profiles,"errors":errors})
	_check("catalog.garden_pool_penthouse_all_present",profiles.size()>=3 and profiles.has("garden") and profiles.has("outdoor_pool") and profiles.has("penthouse"),profiles)
	_check("catalog.actual_profile_meshes_and_open_penthouse_paths",observed_features.size()==3 and errors.filter(func(row):return row.kind in ["missing_actual_profile_mesh","penthouse_open_door_corridor"]).is_empty(),{"observed_meshes":observed_features,"penthouse_path_samples":12*int(profiles.get("penthouse",0))})
	_check("catalog.original_692_shapes_unchanged",_inventory()==original_inventory and original_inventory.size()==692,{"count":original_inventory.size()})

func _pose(point: Vector3) -> void:
	_keys();_e(false)
	scene.player.global_transform=Transform3D(Basis.IDENTITY,point);scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.rig.snap_to_target_pose()
	await _ticks(16)

func _wait_ride() -> bool:
	for tick in range(1500):
		await _ticks(1)
		if not visit.in_elevator:return true
	return false

func _ride_to(index: int, title: String) -> bool:
	await _pose(visit.landing_point(visit.selected_floor))
	_e(true);_e(false);await _ticks(4)
	var opened: bool=visit.elevator_open
	var accepted: bool=visit.request_floor(index)
	_check(title+".E_selector_and_destination_accepted",opened and accepted,{"opened":opened,"accepted":accepted,"destination":index})
	if not accepted:return false
	var completed: bool=await _wait_ride()
	_keys();_e(false);await _ticks(15)
	_check(title+".safe_arrival",completed and scene.player.is_on_floor() and not scene.player.input_latched,{"on_roof":visit.on_roof,"selected_floor":visit.selected_floor,"player":scene.player.global_position})
	return completed

func _input_direction(direction: Vector3) -> void:
	_keys()
	var forward: Vector3=-scene.rig.camera.global_basis.z;forward.y=0.;forward=forward.normalized()
	var right:=forward.cross(Vector3.UP).normalized()
	var x:=direction.dot(right);var z:=direction.dot(forward)
	if x>0:Input.action_press("move_right",x)
	elif x<0:Input.action_press("move_left",-x)
	if z>0:Input.action_press("move_forward",z)
	elif z<0:Input.action_press("move_backward",-z)
	Input.action_press("move_fast")

func _edge_trial(roof: Node3D) -> void:
	var before: int=scene.player.recoveries
	var errors:=[];var samples:=0;var jumped:=false;var air_jump_observed:=false
	for local_direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		await _pose(roof.spawn_point())
		var direction: Vector3=(roof.frame.basis*local_direction).normalized()
		for tick in range(90):
			_input_direction(direction)
			if tick in [6,35]:Input.action_press("jump");jumped=true
			await _ticks(1);samples+=1
			if scene.player.air_jump_count()>0 and scene.player.has_unlimited_air_jumps():air_jump_observed=true
			var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
			if not roof.walkable_rect.grow(-.30).has_point(Vector2(local.x,local.z)):errors.append({"tick":tick,"point":local})
		_keys();await _ticks(70)
	_check("roof.turbo_fresh_air_jumps_four_edges_keep_footprint",errors.is_empty() and jumped and air_jump_observed and scene.player.recoveries==before,{"samples":samples,"errors":errors,"air_jump_observed":air_jump_observed,"recovery_delta":scene.player.recoveries-before,"speed":scene.player.run_speed_mps})
	var edge_cases := [
		{"name":"east","start":Vector3(roof.width*.5-1.4,.08,0),"direction":Vector3.RIGHT,"axis":0,"sign":1.},
		{"name":"west","start":Vector3(-roof.width*.5+1.4,.08,0),"direction":Vector3.LEFT,"axis":0,"sign":-1.},
		{"name":"north","start":Vector3(roof.width*.5-3.,.08,-roof.depth*.5+1.4),"direction":Vector3.FORWARD,"axis":2,"sign":-1.},
		{"name":"south","start":Vector3(roof.width*.5-3.,.08,roof.depth*.5-1.4),"direction":Vector3.BACK,"axis":2,"sign":1.}]
	for edge: Dictionary in edge_cases:
		await _pose(roof.frame*edge.start)
		var edge_errors:=[];var air_boost_observed:=false;var reached:=false;var high_over_rail:=false;var peak_speed:=0.
		var direction: Vector3=roof.frame.basis*edge.direction
		var half: float=(roof.width if edge.axis==0 else roof.depth)*.5
		for tick in range(90):
			var previous: Vector3=scene.player.global_position
			_input_direction(direction)
			if tick in [3,23]:Input.action_press("jump")
			await _ticks(1)
			var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
			var travelled: Vector3=scene.player.global_position-previous;travelled.y=0.
			peak_speed=maxf(peak_speed,travelled.length()*60.)
			if float(local[int(edge.axis)])*float(edge.sign)>=half-.65:reached=true
			if local.y>2. and float(local[int(edge.axis)])*float(edge.sign)>=half-.65:high_over_rail=true
			if scene.player.air_jump_count()>0 and scene.player.air_jumps_remaining()==-1:air_boost_observed=true
			if not roof.walkable_rect.grow(-.30).has_point(Vector2(local.x,local.z)):edge_errors.append({"tick":tick,"local":local})
		_keys();await _ticks(90)
		_check("roof.near_edge_turbo_air_jump_guard."+String(edge.name),reached and high_over_rail and air_boost_observed and peak_speed>20.8 and edge_errors.is_empty() and scene.player.recoveries==before,{"samples":90,"reached_within_m":.65,"reached":reached,"above_rail_at_edge":high_over_rail,"actual_air_boost_observed":air_boost_observed,"peak_actual_speed_mps":peak_speed,"errors":edge_errors,"recovery_delta":scene.player.recoveries-before})
	await _pose(roof.spawn_point())
	scene.player.global_position=roof.spawn_point()-Vector3.UP*6.
	await _ticks(10)
	_check("roof.fall_recovers_to_same_roof_not_street",scene.player.recoveries==before+1 and visit.on_roof and scene.player.global_position.distance_to(roof.spawn_point())<.3,{"player":scene.player.global_position,"spawn":roof.spawn_point()})

func _save_capture(title: String) -> void:
	var roof: Node3D=visit.rooftop
	await _ticks(12)
	var row:={"name":title,"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"profile":roof.profile_id,"source_id":visit.current_spec.id}
	if DisplayServer.get_name()=="headless":row.captured=false;captures.append(row);return
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var file:=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(file)==OK
	row.captured=saved;row.path=file;captures.append(row);_check("capture."+title,saved,row)

func _capture(title: String) -> void:
	var roof: Node3D=visit.rooftop
	await _pose(roof.spawn_point())
	visit._orient(atan2(roof.frame.basis.z.x,roof.frame.basis.z.z),deg_to_rad(-18.),2.8)
	await _save_capture(title+"_arrival")
	# A separate explicit camera/pose fixture makes the facilities inspectable;
	# this is not evidence of a continuous walk from the lift landing.
	await _pose(roof.frame*Vector3(0,.08,roof.depth*.5-8.0))
	visit._orient(atan2(roof.frame.basis.z.x,roof.frame.basis.z.z),deg_to_rad(-25.),6.)
	await _save_capture(title)
	visit._orient(atan2(-roof.frame.basis.z.x,-roof.frame.basis.z.z),deg_to_rad(-12.),4.)
	await _save_capture(title+"_lift_entrance")

func _amenity_walk() -> void:
	var roof: Node3D=visit.rooftop
	var before: int=scene.player.recoveries
	var forward: Vector3=-roof.frame.basis.z
	if roof.profile_id=="penthouse":
		var rear: float=-roof.depth*.5+1.1
		var front: float=rear+minf(9.5,roof.depth-7.)
		await _pose(roof.frame*Vector3(0,.08,front+1.8))
		for i in range(45):
			_input_direction(forward);Input.action_release("move_fast");await _ticks(1)
		_keys();await _ticks(20)
		var inside: Vector3=roof.frame.affine_inverse()*scene.player.global_position
		_check("penthouse.actual_walk_through_open_door",inside.z<front-.6 and inside.z>rear+.4 and absf(inside.x)<.3 and scene.player.is_on_floor() and scene.player.recoveries==before,{"local":inside,"front":front,"rear":rear})
		visit._orient(atan2(roof.frame.basis.z.x,roof.frame.basis.z.z),deg_to_rad(-12.),2.4)
		await _save_capture("penthouse_inside")
		for i in range(45):
			_input_direction(-forward);Input.action_release("move_fast");await _ticks(1)
		_keys();await _ticks(20)
		var outside: Vector3=roof.frame.affine_inverse()*scene.player.global_position
		_check("penthouse.actual_walk_returns_to_terrace",outside.z>front+.4 and scene.player.is_on_floor() and scene.player.recoveries==before,{"local":outside,"front":front})
	elif roof.profile_id=="outdoor_pool":
		var pool: MeshInstance3D=roof.get_node("PoolSafetyFloor")
		var size: Vector3=pool.mesh.size
		await _pose(roof.pool_rim_point())
		for i in range(30):
			_input_direction(forward);Input.action_release("move_fast")
			if i==3:Input.action_press("jump")
			await _ticks(1)
		_keys();await _ticks(120)
		var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
		var water: Dictionary=roof.pool_water_region()
		var floating: bool=absf(local.x-pool.position.x)<size.x*.5-.3 and absf(local.z-pool.position.z)<size.z*.5-.3 and absf(local.y-(float(water.surface_y)-1.0))<.10 and scene.player.is_swimming()
		_check("pool.jump_over_rim_enters_buoyant_raised_basin",floating and scene.player.recoveries==before,{"local":local,"pool_center":pool.position,"pool_size":size,"water":scene.player.water_snapshot(),"depth_m":float(water.surface_y)-float(water.floor_y)})
		await _pose(roof.frame*Vector3(0,.08,pool.position.z+size.z*.5+1.8))
		var target: Vector3=roof.frame*Vector3(pool.position.x,0,pool.position.z)
		var direction: Vector3=target-scene.player.global_position;direction.y=0.
		visit._orient(atan2(-direction.x,-direction.z),deg_to_rad(-28.),4.5)
		await _save_capture("outdoor_pool_detail")

func _visits() -> void:
	for id: String in IDS:
		var selected: bool=visit.select_building(id)
		_check("visit.select."+id,selected)
		if not selected:continue
		await _pose(visit.entrance_world_position)
		_e(true);_e(false);await _ticks(12)
		_check("visit.physical_E_entry."+id,visit.active)
		if not visit.active:continue
		var destination: int=visit.current_spec.floor_count
		_check("visit.roof_is_extra_destination_not_source_floor",visit.destination_count()==destination+1 and visit.room.floor_count==destination,{"interior_floors":visit.room.floor_count,"destinations":visit.destination_count()})
		if not await _ride_to(destination,"ride.roof."+id):continue
		_check("visit.rooftop_mode_and_actual_city_region",visit.on_roof and scene.player.interior_active and scene.player.global_position.distance_to(visit.rooftop.lift_point())<.3 and not visit.room.visible and visit.rooftop.visible,{"roof":visit.rooftop.snapshot(),"player":scene.player.global_position})
		await _capture(String(visit.rooftop.profile_id))
		await _amenity_walk()
		if id==IDS[2]:await _edge_trial(visit.rooftop)
		if not await _ride_to(0,"ride.return_lobby."+id):continue
		_check("visit.return_uses_original_indoor_region",not visit.on_roof and visit.room.visible and scene.player.interior_bounds==visit.room.interior_bounds,{"player":scene.player.global_position})
		await _pose(visit.room.exit_point());_e(true);_e(false);await _ticks(12)
		_check("visit.physical_E_returns_original_street."+id,not visit.active and not scene.player.interior_active,{"player":scene.player.global_position})

func _run() -> void:
	for path in ["res://scripts/rooftop_space.gd","res://scripts/water_effect.gd","res://scripts/elevator_cabin.gd","res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://../tests/game/check_rooftops.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit
	if not visit.has_method("destination_count"):_check("API.roof_visit_destinations",false);_finish();return
	await _ticks(20);scene.set_speed_profile("turbo");_keys();await _ticks(5)
	original_inventory=_inventory()
	await _catalog()
	await _visits()
	_check("final.original_outside_collision_inventory",_inventory()==original_inventory)
	_finish()

func _timeout() -> void:
	if finished:return
	_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys();_e(false);paused=false
	var failed:=0
	for row in checks:
		if not row.passed:failed+=1
	var report:={"schema_version":1,"task":"EXP09_ROOFTOPS","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"catalog":catalog_rows,"captures":captures,"source_sha256":source_hashes,"scope":"Source-world, source-inscribed authored roof decks, not surveyed roofs. All125 spawn/lift and geometry observations are separate from three representative physical E/lift visits. Explicit scenario-start teleports are not a continuous route. Pool buoyancy is a game controller in a raised basin above retained source slabs; detailed water entry/exit/effects are separate swimming-test evidence. Physical shaft travel, fluid simulation, real venue roof facilities, long-run performance, export and cross-Mac validation are not claimed."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	print("ROOFTOP_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

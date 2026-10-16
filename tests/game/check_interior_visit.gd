extends SceneTree
## Real controller/input checks. All scenario teleports and blockers are test fixtures.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","interact","toggle_menu"]
var report_path := ""
var scene
var visit
var checks: Array = []
var placements: Array = []
var trials: Array = []
var captures: Array = []
var original_inventory := {}
var finished := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path = arg.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_interior_visit requires --report=<absolute path>");quit(1);return
	# Register E without physical events before production setup, as for Space.
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	Engine.physics_ticks_per_second = 60
	create_timer(120.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("INTERIOR_VISIT_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _keys(actions: Array) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _ticks(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func _inventory() -> Dictionary:
	var result := {}
	for collection in [scene.city.bodies,scene.city.fragments]:
		for id in collection:
			var body: StaticBody3D = collection[id]
			var collision: CollisionShape3D = body.get_node("CollisionShape")
			var shape: Shape3D = collision.shape
			result[id] = {"node":body.get_instance_id(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":str(body.transform),"shape":shape.get_instance_id(),"shape_transform":str(collision.transform),"disabled":collision.disabled,"faces":hash(shape.get_faces()) if shape is ConcavePolygonShape3D else 0}
	return result

func _pose(title: String, requested: Vector3) -> bool:
	_keys([])
	var point := requested
	var safe := true
	if not visit.active:
		var validated: Dictionary = visit._safe_external_point(point)
		safe = not validated.is_empty()
		if safe:point = validated.point
	else:safe = scene.player._inside(point)
	placements.append({"name":title,"kind":"explicit_test_only_teleport","position":_v(point),"valid":safe})
	_check("placement."+title,safe,placements[-1])
	if not safe:return false
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.reset_orientation()
	await _ticks(16)
	_check("placement."+title+".grounded",scene.player.is_on_floor() and not scene.player.input_latched,{"position":_v(scene.player.global_position)})
	return true

func _enter(title: String) -> bool:
	scene.set_free_roam(true)
	if not await _pose(title,visit.entrance_world_position):return false
	var before: int = visit.entry_count
	_keys(["interact"]);await _ticks(5);_keys([]);await _ticks(5)
	_check(title+".entered",visit.active and visit.entry_count==before+1,visit.snapshot())
	return visit.active

func _door_pose(title: String) -> bool:
	return await _pose(title,visit.ROOM_ORIGIN+Vector3(0,.08,4.5))

func _camera_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new();query.shape = scene.rig.arm.shape
	query.transform = Transform3D(Basis.IDENTITY,scene.rig.camera.global_position)
	query.collision_mask = scene.rig.arm.collision_mask;query.exclude = [scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":
		captures.append({"name":title,"captured":false,"reason":"headless_has_no_rendered_viewport"})
		return
	await process_frame
	# Force an offscreen draw after native window resizing/menu focus changes.
	# Waiting on a conditional post_draw signal can stall an unattended GPU probe.
	RenderingServer.force_draw(false,0.0)
	var picture: Image = scene.get_viewport().get_texture().get_image()
	var path := report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool = not picture.is_empty() and picture.save_png(path)==OK
	captures.append({"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":_v(scene.player.global_position),"camera":scene.rig.snapshot(),"interior":visit.snapshot()})
	_check("capture."+title,saved,captures[-1])

func _blocker(title: String, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();body.name = title;body.position = at+Vector3.UP
	body.collision_layer = 1;body.collision_mask = 0
	var node := CollisionShape3D.new();node.name = "CollisionShape"
	var shape := BoxShape3D.new();shape.size = Vector3(4.,2.,4.);node.shape = shape
	body.add_child(node);scene.add_child(body)
	return body

func _run() -> void:
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json"
	scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:
		_check("startup",false,{"runtime_ok":scene.runtime_ok});_finish();return
	visit = scene.interior_visit
	await _ticks(25)
	_check("startup",visit.loaded and not visit.active and not scene.player.interior_active,visit.snapshot())
	_check("input.E_isolated",InputMap.action_get_events("interact").is_empty())
	original_inventory = _inventory()
	_check("exterior.original_library_body_closed",scene.city.bodies.has(visit.LIBRARY_ID) and scene.city.bodies[visit.LIBRARY_ID].collision_layer==1)
	_check("room.isolated_layer_and_opaque_shell",visit.room_bodies.size()>=6 and visit.room_bodies.all(func(body):return body.collision_layer==1 and body.collision_mask==0) and visit.ROOM_ORIGIN.x>scene.player.free_roam_bounds.end.x,{"static_bodies":visit.room_bodies.size(),"origin":_v(visit.ROOM_ORIGIN)})
	_keys(["interact"]);await _ticks(5);_keys([]);await _ticks(4)
	_check("entry.far_key_does_nothing",not visit.active and visit.entry_count==0)
	if not await _pose("occluded_entry",visit.entrance_world_position+visit.entrance_outward_direction*2.):_finish();return
	var wall := StaticBody3D.new();wall.name = "EntryOcclusionFixture"
	wall.position = visit.entrance_world_position+visit.entrance_outward_direction+Vector3.UP
	wall.collision_layer = 1;wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new();var wall_box := BoxShape3D.new();wall_box.size = Vector3(2.5,2.,.15)
	wall_shape.shape = wall_box;wall.add_child(wall_shape);scene.add_child(wall);await _ticks(3)
	_check("entry.wall_occlusion_rejects_near_E",not visit.enter_visit() and not visit.active and visit.entry_count==0)
	wall.queue_free();await _ticks(4)
	if not await _pose("first_entrance",visit.entrance_world_position):_finish();return
	await _capture("library_entry")
	var floor_body: StaticBody3D = visit.room.get_node("FloorBody")
	floor_body.collision_layer = 0;await _ticks(3)
	var before_failed_entry: Vector3 = scene.player.global_position
	_check("entry.missing_indoor_floor_rolls_back",not visit.enter_visit() and not visit.active and not scene.player.interior_active and scene.player.global_position==before_failed_entry and scene.player.fall_limit_y== -3.)
	floor_body.collision_layer = 1;await _ticks(3)
	_keys(["interact","jump","move_forward"]);await _ticks(20)
	_check("entry.held_movement_jump_neutral",visit.active and scene.player.global_position.distance_to(visit.ROOM_ORIGIN+Vector3(0,0,2.5))<.15 and scene.player.input_latched,{"position":_v(scene.player.global_position),"state":visit.snapshot()})
	_keys([]);await _ticks(5)
	_check("entry.outdoor_labels_hidden",not scene.hud_panel.visible and not scene.building_names.panel.visible and not scene.building_names.is_physics_processing())
	await _capture("library_lobby")
	var before_motion: Vector3 = scene.player.global_position
	_keys(["move_forward"]);await _ticks(30);_keys([]);await _ticks(2)
	var moved: float = Vector2(scene.player.global_position.x-before_motion.x,scene.player.global_position.z-before_motion.z).length()
	_check("room.actual_walk",moved>.9 and moved<1.3 and scene.player.is_on_floor() and visit.active,{"distance_m":moved,"position":_v(scene.player.global_position)})
	if not await _pose("indoor_edge_run",visit.ROOM_ORIGIN+Vector3(-7.4,.08,3.5)):_finish();return
	var edge_recoveries: int = scene.player.recoveries
	var before_boundary_stops: int = scene.player.boundary_stops
	_keys(["move_left","move_fast"]);await _ticks(35);_keys([]);await _ticks(3)
	_check("room.run_stops_at_indoor_edge_without_outdoor_recovery",scene.player._inside(scene.player.global_position) and scene.player.global_position.x>=visit.ROOM_ORIGIN.x-7.601 and scene.player.boundary_stops>before_boundary_stops and scene.player.recoveries==edge_recoveries and scene.player.is_on_floor(),{"position":_v(scene.player.global_position),"boundary_stops":scene.player.boundary_stops})
	var saved_window_size: Vector2i = root.size
	var saved_scale_size: Vector2i = root.content_scale_size
	var saved_scale_factor: float = root.content_scale_factor
	root.content_scale_size = Vector2i.ZERO;root.content_scale_factor = 1.
	root.size = Vector2i(640,480);await _ticks(5)
	var guide_rect: Rect2 = visit.indoor_panel.get_global_rect()
	var small_view: Vector2 = scene.get_viewport().get_visible_rect().size
	_check("UI.indoor_guide_fits_small_window",small_view==Vector2(640,480) and guide_rect.position.x>=0. and guide_rect.end.x<=small_view.x+.1 and guide_rect.end.y<=small_view.y+.1,{"rect":str(guide_rect),"viewport":[small_view.x,small_view.y]})
	root.size = saved_window_size;root.content_scale_size = saved_scale_size;root.content_scale_factor = saved_scale_factor;await _ticks(4)
	if not await _pose("ceiling_jump",visit.ROOM_ORIGIN+Vector3(0,.08,2.5)):_finish();return
	# Raise only this test's requested jump to force a real ceiling contact.
	var saved_height: float = scene.player.jump_height_m
	scene.player.jump_height_m = 4.
	var peak: float = scene.player.global_position.y
	var ascent_count := 0
	var was_up := false
	var ceiling_contact := false
	_keys(["jump"])
	for index in range(140):
		await physics_frame
		peak = maxf(peak,scene.player.global_position.y)
		var up: bool = scene.player.velocity.y>.01
		if up and not was_up:ascent_count += 1
		was_up = up
		for i in range(scene.player.get_slide_collision_count()):
			var hit: KinematicCollision3D = scene.player.get_slide_collision(i)
			if hit.get_normal().y<-.5:ceiling_contact = true
	_keys([]);scene.player.jump_height_m = saved_height;await _ticks(4)
	_check("room.ceiling_stops_high_jump_and_no_hold_repeat",ceiling_contact and peak<=visit.ROOM_ORIGIN.y+3.12 and ascent_count==1 and scene.player.is_on_floor(),{"peak_y":peak,"ceiling_contact":ceiling_contact,"ascending_episodes":ascent_count})
	var orbit_bad := 0
	for pitch in [-60.,-15.,15.]:
		for index in range(12):
			scene.rig.yaw = index*TAU/12.;scene.rig.pitch = deg_to_rad(pitch);scene.rig.requested_distance = 6.
			await _ticks(2)
			if not _camera_clear():orbit_bad += 1
	_check("camera.indoor_orbit_no_wall_ceiling_overlap",orbit_bad==0,{"poses":36,"overlap_failures":orbit_bad})
	scene.rig.reset_orientation();await _ticks(3)
	var recoveries: int = scene.player.recoveries
	placements.append({"name":"fall_below_room","kind":"explicit_test_only_fault_teleport","position":_v(visit.ROOM_ORIGIN+Vector3(0,-5,0))})
	scene.player.global_position = visit.ROOM_ORIGIN+Vector3(0,-5,0)
	await _ticks(15)
	_check("recovery.fall_returns_to_indoor_spawn",visit.active and scene.player.interior_active and scene.player.recoveries==recoveries+1 and scene.player.is_on_floor() and scene.player.last_recovery_reason=="fall",{"position":_v(scene.player.global_position),"recoveries":scene.player.recoveries})
	var paused_at: Vector3 = scene.player.global_position
	scene.toggle_menu();_keys(["interact","jump","move_forward"]);await _ticks(12)
	_check("menu.world_paused_and_E_blocked",paused and visit.active and scene.player.global_position.distance_to(paused_at)<.001)
	scene.toggle_menu();await _ticks(12)
	_check("menu.resume_held_E_jump_movement_neutral",not paused and visit.active and scene.player.global_position.distance_to(paused_at)<.02 and visit.e_requires_release and scene.player.input_latched)
	_keys([]);await _ticks(5)
	if not await _door_pose("first_exit"):_finish();return
	var outside_return: Array = visit.snapshot().outside_return
	_keys(["interact","jump","move_forward"]);await _ticks(25)
	var outside_target := Vector3(outside_return[0],outside_return[1],outside_return[2])
	_check("exit.actual_E_returns_to_entry_with_neutral_input",not visit.active and not scene.player.interior_active and scene.player.global_position.distance_to(outside_target)<.15 and scene.player.input_latched,visit.snapshot())
	_check("exit.held_E_cannot_reenter",visit.entry_count==1 and visit.exit_count==1)
	_keys([]);await _ticks(5)
	_check("exit.outdoor_HUD_restored",scene.hud_panel.visible and scene.building_names.is_physics_processing())
	await _capture("library_exit")
	if not await _enter("repeat_visit"):_finish();return
	var actor_positions := []
	for actor in scene.pedestrians+scene.vehicles:actor_positions.append(actor.global_position)
	await _ticks(90)
	var actor_moved := false
	var actors: Array = scene.pedestrians+scene.vehicles
	for index in range(actors.size()):
		if actors[index].global_position.distance_to(actor_positions[index])>.02:actor_moved = true
	_check("world.actors_continue_while_inside",actor_moved and scene.vehicles.size()==6 and scene.pedestrians.size()==2)
	var traffic_player_clear := false
	for row in scene.traffic.snapshot().humans:
		if row.id==str(scene.player.get_path()):traffic_player_clear = not row.inside_crossing
	_check("world.indoor_player_not_in_outdoor_crossing",traffic_player_clear,{"player":_v(scene.player.global_position)})
	scene.set_free_roam(false);scene.set_speed_profile("fast");await _ticks(5)
	_check("settings.indoor_mode_survives_outdoor_boundary_switch",visit.active and scene.player.interior_active and not scene.player.free_roam_enabled and scene.speed_id=="fast" and scene.player.is_on_floor())
	if not await _door_pose("walk_mode_exit"):_finish();return
	_keys(["interact"]);await _ticks(6);_keys([]);await _ticks(6)
	_check("settings.exit_uses_valid_walk_mode_return",not visit.active and scene.city.movement_contains(Vector2(scene.player.global_position.x,scene.player.global_position.z)) and scene.player.is_on_floor(),{"position":_v(scene.player.global_position)})
	if not await _enter("blocked_return_visit"):_finish();return
	if not await _door_pose("blocked_return_exit"):_finish();return
	var return_row: Array = visit.snapshot().outside_return
	var blockers := [_blocker("BlockedEntryFixture",Vector3(return_row[0],return_row[1],return_row[2])),_blocker("BlockedSpawnFixture",visit._world_spawn)]
	await _ticks(4)
	var blocked: bool = not visit.exit_visit()
	_check("exit.blocked_returns_stay_safely_inside",blocked and visit.active and scene.player.interior_active and scene.player.is_on_floor(),visit.snapshot())
	for body in blockers:body.queue_free()
	await _ticks(5)
	_check("exit.unblocked_return_succeeds",visit.exit_visit() and not visit.active)
	await _ticks(8)
	if not await _enter("manual_reset_visit"):_finish();return
	scene.toggle_menu();scene.reset_player()
	_check("camera.paused_manual_reset_immediately_snaps_outdoors",paused and scene.rig.camera.global_position.y>0.15 and scene.rig.camera.global_position.distance_to(scene.player.global_position)<7.0 and scene.rig._render_pose(0.5).origin.distance_to(scene.rig.camera.global_position)<0.001,{"camera":_v(scene.rig.camera.global_position),"player":_v(scene.player.global_position),"paused":paused})
	await _ticks(4)
	_check("recovery.menu_manual_reset_exits_to_original_spawn",not visit.active and not scene.player.interior_active and scene.player.global_position.distance_to(visit._world_spawn)<.15 and scene.player.spawn_transform.origin==visit._world_spawn)
	scene.toggle_menu();_keys([]);await _ticks(8)
	_check("exterior.original_bodies_shapes_transforms_preserved",_inventory()==original_inventory,{"body_count":original_inventory.size()})
	_check("exterior.player_camera_masks_preserved",scene.player.collision_layer==2 and scene.player.collision_mask==45 and scene.rig.arm.collision_mask==33)
	_finish()

func _timeout() -> void:
	if finished:return
	_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished = true;_keys([]);paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var source_hashes := {}
	for path in ["res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://scripts/explore_walk.gd","res://resources/world_geometry/world.json","res://../tests/game/check_interior_visit.gd"]:source_hashes[path] = FileAccess.get_sha256(path)
	var report := {"task":"EXP03_interior","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"placements":placements,"trials":trials,"captures":captures,"summary":{"checks":checks.size(),"failed":failed},"scope":"Scenario placements are test-only. Indoor dimensions and decoration are authored assumptions, not surveyed reconstruction. The jump-ceiling scenario temporarily raises the requested jump from 3m to 4m only in this probe. Missing-floor, occluding-wall and blocked-return cases are explicit fault fixtures.","state":visit.snapshot() if is_instance_valid(visit) else {}}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save interior report")
	print("INTERIOR_VISIT_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

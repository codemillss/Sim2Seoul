extends SceneTree
## Source-sized building visits. Scenario starts/fall faults are explicitly recorded.
const LIBRARY_ID := "osm:relation:10757525:building"
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var report_path := ""
var scene
var visit
var checks: Array = []
var placements: Array = []
var walks: Array = []
var rides: Array = []
var buildings: Array = []
var captures: Array = []
var source_hashes := {}
var original_inventory := {}
var finished := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path = arg.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_building_visits requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second = 60
	create_timer(240.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("BUILDING_VISIT_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _movement(actions: Array = []) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _e(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E;event.keycode = KEY_E;event.pressed = pressed
	Input.parse_input_event(event)

func _ticks(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func _world_keys(direction: Vector3) -> void:
	_movement()
	var forward: Vector3 = -scene.rig.camera.global_basis.z
	forward.y = 0.;forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var sideways: float = direction.dot(right)
	var ahead: float = direction.dot(forward)
	if sideways>0.00001:Input.action_press("move_right",sideways)
	elif sideways<-.00001:Input.action_press("move_left",-sideways)
	if ahead>0.00001:Input.action_press("move_forward",ahead)
	elif ahead<-.00001:Input.action_press("move_backward",-ahead)

func _inventory() -> Dictionary:
	var result := {}
	for collection in [scene.city.bodies,scene.city.fragments]:
		for id in collection:
			var body: StaticBody3D = collection[id]
			var node: CollisionShape3D = body.get_node("CollisionShape")
			var shape: Shape3D = node.shape
			result[id] = {"node":body.get_instance_id(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":str(body.transform),"shape":shape.get_instance_id(),"shape_transform":str(node.transform),"disabled":node.disabled,"faces":hash(shape.get_faces()) if shape is ConcavePolygonShape3D else 0}
	return result

func _source_contains(point: Vector2, spec: Dictionary) -> bool:
	var part: Array = spec.source_rings[int(spec.source_part_index)]
	for ring_index in range(part.size()):
		var ring := PackedVector2Array()
		for coordinate: Array in part[ring_index]:ring.append(Vector2(float(coordinate[0]),float(coordinate[1])))
		var inside := Geometry2D.is_point_in_polygon(point,ring)
		if ring_index==0 and not inside:return false
		if ring_index>0 and inside:return false
	return true

func _blocker(title: String, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();body.name = title;body.position = at+Vector3.UP
	body.collision_layer = 1;body.collision_mask = 0
	var node := CollisionShape3D.new();var box := BoxShape3D.new()
	box.size = Vector3(1.5,2.,1.5);node.shape = box
	body.add_child(node);scene.add_child(body)
	return body

func _pose(title: String, point: Vector3) -> bool:
	_movement();_e(false)
	placements.append({"name":title,"kind":"explicit_test_only_scenario_start","point":_v(point)})
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	scene.rig.reset_orientation();scene.rig.snap_to_target_pose()
	await _ticks(16)
	var grounded: bool = scene.player.is_on_floor() and not scene.player.input_latched
	_check("placement."+title+".grounded",grounded,{"position":_v(scene.player.global_position),"requested":_v(point)})
	return grounded

func _enter(id: String, title: String) -> bool:
	_movement();_e(false);await _ticks(3)
	var selected: bool = visit.select_building(id)
	_check(title+".selected",selected,{"id":id})
	if not selected:return false
	# Move to this source door before auto-nearest selection runs. The scenario
	# settling ticks also let its StaticBody3D floors reach the physics server.
	var entrance: Vector3 = visit.entrance_world_position
	if not await _pose(title+"_outside",entrance):return false
	var before: int = visit.entry_count
	_e(true);_e(false);await _ticks(8)
	var entered: bool = visit.active and visit.entry_count==before+1
	_check(title+".physical_E_enters",entered,visit.snapshot())
	return entered

func _leave(title: String) -> bool:
	if not visit.active:return true
	if not await _pose(title+"_exit",visit.room.exit_point()):return false
	var before: int = visit.exit_count
	var entries: int = visit.entry_count
	_e(true);await _ticks(25)
	var safe: bool = not visit.active and not scene.player.interior_active and not visit._safe_external_point(scene.player.global_position).is_empty()
	_check(title+".safe_physical_E_exit",safe and visit.exit_count==before+1,{"position":_v(scene.player.global_position),"state":visit.snapshot()})
	_check(title+".held_E_no_auto_reentry",visit.entry_count==entries and not visit.active)
	_e(false);await _ticks(5)
	return safe

func _walk_path(title: String, path: Array) -> bool:
	var before_recoveries: int = scene.player.recoveries
	var samples := 0
	var grounded := 0
	var max_step := 0.
	var max_height: float = scene.player.global_position.y
	var start: Vector3 = scene.player.global_position
	var completed := true
	var failed_target := -1
	for target_index in range(path.size()):
		var target: Vector3 = path[target_index]
		var initial: Vector3 = target-scene.player.global_position
		var budget := maxi(90,int(ceil(Vector2(initial.x,initial.z).length()/scene.player.walk_speed_mps*60.))*3+90)
		var reached := false
		for index in range(budget):
			var offset: Vector3 = target-scene.player.global_position
			var horizontal := Vector3(offset.x,0.,offset.z)
			if horizontal.length()<.18 and absf(offset.y)<.4:
				reached = true;break
			_world_keys(horizontal.normalized())
			var prior: Vector3 = scene.player.global_position
			await scene.player.physics_stepped
			max_step = maxf(max_step,scene.player.global_position.distance_to(prior))
			max_height = maxf(max_height,scene.player.global_position.y)
			samples += 1
			if scene.player.is_on_floor():grounded += 1
			if scene.player.recoveries!=before_recoveries:break
		if not reached:
			completed = false;failed_target = target_index;break
	_movement();await _ticks(5)
	var row := {"name":title,"waypoints":path.size(),"completed":completed,"failed_target":failed_target,"samples":samples,"grounded_samples":grounded,"max_step_m":max_step,"max_height_y":max_height,"start":_v(start),"end":_v(scene.player.global_position),"recoveries_before":before_recoveries,"recoveries_after":scene.player.recoveries,"kind":"real_controller_Input.action_press_movement_no_midflight_teleports"}
	walks.append(row)
	var physical: bool = samples>10 and max_step<.2 and scene.player.recoveries==before_recoveries and scene.player.is_on_floor()
	_check(title,completed and physical,row)
	return completed and physical

func _camera_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new();query.shape = scene.rig.arm.shape
	query.transform = Transform3D(Basis.IDENTITY,scene.rig.camera.global_position)
	query.collision_mask = scene.rig.arm.collision_mask;query.exclude = [scene.player.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":
		captures.append({"name":title,"captured":false,"reason":"headless_has_no_rendered_viewport"});return
	await process_frame
	RenderingServer.force_draw(false,0.0)
	var picture: Image = scene.get_viewport().get_texture().get_image()
	var path := report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool = not picture.is_empty() and picture.save_png(path)==OK
	var row := {"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":_v(scene.player.global_position),"state":visit.snapshot()}
	captures.append(row);_check("capture."+title,saved,row)

func _upper_camera() -> void:
	var bad := 0
	for pitch in [-60.,-15.,15.]:
		for index in range(12):
			scene.rig.yaw = index*TAU/12.;scene.rig.pitch = deg_to_rad(pitch);scene.rig.requested_distance = 6.
			await _ticks(2)
			if not _camera_clear():bad += 1
	_check("camera.upper_floor_36_orbits_clear",bad==0,{"poses":36,"overlaps":bad,"player":_v(scene.player.global_position)})
	scene.rig.reset_orientation();await _ticks(4)

func _people_check() -> void:
	var people: Array = visit.room.people
	_check("people.present",people.size()>=2,{"count":people.size()})
	if people.is_empty():return
	var before := []
	for person in people:before.append(person.global_position)
	await _ticks(90)
	var moved := 0
	for index in range(people.size()):
		if people[index].global_position.distance_to(before[index])>.1:moved += 1
	_check("people.actual_motion",moved>0,{"moving_people":moved,"count":people.size()})
	var paused_at := []
	for person in people:paused_at.append(person.global_position)
	scene.toggle_menu();await _ticks(18)
	var pause_motion := 0.
	for index in range(people.size()):pause_motion = maxf(pause_motion,people[index].global_position.distance_to(paused_at[index]))
	_check("people.menu_pauses_motion",paused and pause_motion<.001,{"max_motion_m":pause_motion})
	scene.toggle_menu();_movement();_e(false);await _ticks(6)

func _elevator_check() -> void:
	var room = visit.room
	if not await _pose("elevator_far",room.floor_spawn(0)):return
	var far_before: Vector3 = scene.player.global_position
	var distance: float = far_before.distance_to(room.elevator_point(0))
	_check("elevator.far_request_rejected",distance>2.5 and not visit.request_floor(1) and not visit.in_elevator and scene.player.global_position==far_before,{"distance_m":distance})
	if not await _pose("elevator_call",room.elevator_point(0)):return
	_check("elevator.invalid_floor_rejected",not visit.request_floor(-1) and not visit.request_floor(room.floor_count) and not visit.in_elevator)
	_e(true);_e(false);await _ticks(4)
	_check("elevator.physical_E_opens_selector",visit.elevator_panel.visible and visit.active)
	_check("elevator.selector_has_each_floor",visit.elevator_floors.get_child_count()==room.floor_count)
	await _capture("library_elevator_selector")
	var blocked_at: Vector3 = scene.player.global_position
	var obstruction := _blocker("BlockedUpperElevatorLanding",room.elevator_point(1))
	await _ticks(4)
	_check("elevator.blocked_destination_rejects_before_departure",not visit.request_floor(1) and not visit.in_elevator and scene.player.global_position.distance_to(blocked_at)<.01)
	obstruction.queue_free();await _ticks(5)
	var initial: Vector3 = scene.player.global_position
	var accepted: bool = visit.request_floor(1)
	_check("elevator.near_valid_request_starts",accepted and visit.in_elevator)
	if not accepted:return
	_movement(["move_forward","jump"]);_e(true)
	await _ticks(5)
	_check("elevator.during_ride_request_rejected",not visit.request_floor(0))
	var paused_at: Vector3 = scene.player.global_position
	scene.toggle_menu();await _ticks(18)
	_check("elevator.menu_freezes_ride",paused and scene.player.global_position.distance_to(paused_at)<.001 and visit.in_elevator,{"position":_v(scene.player.global_position)})
	var menu_above_ride: bool = scene.menu.get_parent()==visit.ride_panel.get_parent() and (scene.menu.z_index>visit.ride_panel.z_index or (scene.menu.z_index==visit.ride_panel.z_index and scene.menu.get_index()>visit.ride_panel.get_index()))
	_check("elevator.paused_menu_visible_above_car_and_focused",scene.menu.is_visible_in_tree() and visit.ride_panel.is_visible_in_tree() and menu_above_ride and scene.get_viewport().gui_get_focus_owner()==scene.resume_action,{"menu_index":scene.menu.get_index(),"ride_index":visit.ride_panel.get_index(),"menu_z_index":scene.menu.z_index,"ride_z_index":visit.ride_panel.z_index,"resume_has_focus":scene.resume_action.has_focus()})
	await _capture("library_elevator_paused_menu")
	scene.toggle_menu();await _ticks(2)
	var ys := [initial.y,paused_at.y,scene.player.global_position.y]
	var max_step := 0.
	var monotonic := true
	var prior: Vector3 = scene.player.global_position
	var motion_ticks := 0
	for index in range(900):
		if not visit.in_elevator:break
		await _ticks(1)
		var current: Vector3 = scene.player.global_position
		max_step = maxf(max_step,current.distance_to(prior))
		if current.y<prior.y-.01:monotonic = false
		prior = current;ys.append(current.y);motion_ticks += 1
	var arrived: bool = not visit.in_elevator and visit.selected_floor==1 and absf(scene.player.global_position.y-room.floor_spawn(1).y)<.2
	var row := {"start":_v(initial),"end":_v(scene.player.global_position),"motion_ticks":motion_ticks,"max_step_m":max_step,"monotonic_up":monotonic,"sampled_y":ys,"selected_floor":visit.selected_floor}
	rides.append(row)
	_check("elevator.continuous_vertical_ride_arrives",arrived and motion_ticks>3 and max_step<.3 and monotonic,row)
	_check("elevator.held_inputs_neutral_on_arrival",arrived and scene.player.input_latched and visit.active,visit.snapshot())
	_movement();_e(false);await _ticks(6)
	_check("elevator.arrival_spawn_is_valid_upper_floor",scene.player.spawn_transform.origin.y>room.floor_spawn(0).y+1. and scene.player._valid_spawn(),{"spawn":_v(scene.player.spawn_transform.origin)})
	# A deliberate fall fault must recover onto the arrived floor.
	var recoveries: int = scene.player.recoveries
	placements.append({"name":"upper_floor_fall_fault","kind":"explicit_test_only_fault_teleport","point":_v(room.floor_spawn(1)-Vector3.UP*30.)})
	scene.player.global_position = room.floor_spawn(1)-Vector3.UP*30.
	await _ticks(16)
	_check("recovery.elevator_floor_fall_stays_on_arrived_floor",visit.active and scene.player.recoveries==recoveries+1 and scene.player.is_on_floor() and absf(scene.player.global_position.y-room.floor_spawn(1).y)<.2,{"position":_v(scene.player.global_position),"recoveries":scene.player.recoveries})
	if not await _pose("elevator_return",room.elevator_point(1)):return
	_check("elevator.return_request",visit.request_floor(0))
	for index in range(900):
		if not visit.in_elevator:break
		await _ticks(1)
	_check("elevator.returns_to_ground_floor",not visit.in_elevator and visit.selected_floor==0 and absf(scene.player.global_position.y-room.floor_spawn(0).y)<.2)
	_movement();_e(false);await _ticks(6)
	await _elevator_faults(room)

func _elevator_faults(room) -> void:
	if not await _pose("midride_obstruction_start",room.elevator_point(0)):return
	var started: bool = visit.request_floor(1)
	_check("elevator.midride_obstruction_trial_started",started)
	if not started:return
	await _ticks(5)
	var destination := _blocker("LandingBlockedDuringRide",room.elevator_point(1))
	await _ticks(140)
	_check("elevator.midride_blocked_destination_rolls_back_safely",not visit.in_elevator and visit.selected_floor==0 and scene.player.is_on_floor() and scene.player.is_physics_processing() and scene.player._valid_spawn(),{"position":_v(scene.player.global_position),"state":visit.snapshot()})
	_check("elevator.rollback_restores_capture_and_gameplay",scene.rig.input_enabled and scene.input_router.gameplay_enabled)
	destination.queue_free();await _ticks(5)
	if not await _pose("all_landings_obstruction_start",room.elevator_point(0)):return
	started = visit.request_floor(1)
	_check("elevator.all_landings_trial_started",started)
	if not started:return
	await _ticks(5)
	var blockers: Array[StaticBody3D] = []
	blockers.append(_blocker("BlockedDeparturePad",room.elevator_point(0)))
	blockers.append(_blocker("BlockedDestinationPad",room.elevator_point(1)))
	var ground_spawn: StaticBody3D
	for index in range(room.floor_count):
		var body := _blocker("BlockedFloorSpawn%d"%index,room.floor_spawn(index))
		blockers.append(body)
		if index==0:ground_spawn = body
	await _ticks(140)
	_check("elevator.all_landings_blocked_keeps_passenger_guarded",visit.in_elevator and not scene.player.is_physics_processing() and not scene.input_router.gameplay_enabled and not scene.rig.input_enabled and visit.ride_panel.visible,visit.snapshot())
	# Disable the fixture now, then invoke rollback before any player/camera tick
	# can hide a stale rig pivot or a delayed interpolation reset.
	ground_spawn.collision_layer = 0
	var rollback_now: bool = visit._cancel_ride()
	var expected_pivot: Vector3 = scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
	_check("elevator.fallback_camera_snaps_before_next_tick",rollback_now and not visit.in_elevator and scene.player.global_position.distance_to(room.floor_spawn(0))<.15 and scene.rig.global_position.distance_to(expected_pivot)<.001 and scene.rig.camera.global_position.distance_to(scene.player.global_position)<7. and scene.rig._render_pose(.5).origin.distance_to(scene.rig.camera.global_position)<.001,{"player":_v(scene.player.global_position),"rig_pivot":_v(scene.rig.global_position),"expected_pivot":_v(expected_pivot),"camera":_v(scene.rig.camera.global_position)})
	ground_spawn.queue_free();await _ticks(10)
	_check("elevator.unblocking_valid_landing_recovers",not visit.in_elevator and visit.selected_floor==0 and scene.player.is_on_floor() and scene.player.is_physics_processing() and scene.player._valid_spawn() and scene.rig.input_enabled and scene.input_router.gameplay_enabled,{"position":_v(scene.player.global_position),"state":visit.snapshot()})
	for body in blockers:
		if is_instance_valid(body):body.queue_free()
	await _ticks(5)

func _quick_library_jump() -> void:
	var original_spawn: Transform3D = scene.player.spawn_transform
	_movement(["move_forward","jump"]);_e(true)
	var moved: bool = visit.go_to_library_entrance()
	_check("quick_access.closed_menu_safe_library_entrance",moved and not visit.active and scene.player.spawn_transform==original_spawn and scene.player.input_latched and not visit._safe_external_point(scene.player.global_position).is_empty() and scene.player.global_position.distance_to(visit.entrance_world_position)<.15)
	_check("quick_access.closed_menu_camera_snaps",scene.rig.camera.global_position.distance_to(scene.player.global_position)<7. and scene.rig._render_pose(.5).origin.distance_to(scene.rig.camera.global_position)<.001)
	_movement();_e(false);await _ticks(8)
	await _pose("quick_access_away_from_library",visit._world_spawn)
	scene.toggle_menu()
	moved = visit.go_to_library_entrance()
	_check("quick_access.open_menu_preserves_pause_spawn_and_camera",moved and paused and scene.menu.visible and not visit.active and scene.player.spawn_transform==original_spawn and scene.player.global_position.distance_to(visit.entrance_world_position)<.15 and scene.rig.camera.global_position.distance_to(scene.player.global_position)<7. and scene.rig._render_pose(.5).origin.distance_to(scene.rig.camera.global_position)<.001)
	scene.toggle_menu();_movement();_e(false);await _ticks(8)

func _library() -> void:
	if not await _enter(LIBRARY_ID,"library"):return
	var room = visit.room
	var api_ok: bool = room.has_method("floor_spawn") and room.has_method("exit_point") and room.has_method("elevator_point") and room.has_method("stair_path")
	_check("room.multifloor_API",api_ok and room.floor_count>=2,{"floor_count":room.floor_count})
	if not api_ok or room.floor_count<2:return
	await _capture("library_lobby")
	_check("room.library_source_dimensions_and_levels",is_equal_approx(room.width,float(visit.current_spec.width)) and is_equal_approx(room.depth,float(visit.current_spec.depth)) and room.floor_count==int(visit.current_spec.floor_count),{"width":room.width,"depth":room.depth,"floors":room.floor_count,"height_basis":visit.current_spec.height_basis,"floors_basis":visit.current_spec.floors_basis})
	_check("room.level_spacing_matches_source_height",absf(room.floor_spawn(1).y-room.floor_spawn(0).y-float(visit.current_spec.floor_height))<.001)
	_check("selection.cannot_replace_active_building",not visit.select_building("invalid-building") and visit.active)
	await _people_check()
	var up: Array = room.stair_path(0,true)
	var down: Array = room.stair_path(1,false)
	_check("stairs.valid_bidirectional_paths",up.size()>=6 and down.size()>=6)
	if up.size()>=6 and down.size()>=6:
		if await _pose("stairs_base",up[0]):
			var walked_up: bool = await _walk_path("stairs.real_walk_up",up)
			_check("stairs.arrives_on_second_floor",walked_up and absf(scene.player.global_position.y-room.floor_spawn(1).y)<.25,{"position":_v(scene.player.global_position)})
			if walked_up:
				await _capture("library_second_floor_stairs")
				await _upper_camera()
				var walked_down: bool = await _walk_path("stairs.real_walk_down",down)
				_check("stairs.returns_to_first_floor",walked_down and absf(scene.player.global_position.y-room.floor_spawn(0).y)<.25,{"position":_v(scene.player.global_position)})
	await _elevator_check()
	await _leave("library")

func _run() -> void:
	for path in ["res://scripts/interior_visit.gd","res://scripts/building_visit_catalog.gd","res://scripts/building_interior_space.gd","res://assets/authored/interiors/source_catalog.json","res://scripts/player/free_roam_player.gd","res://../tests/game/check_building_visits.gd"]:
		if FileAccess.file_exists(path):source_hashes[path] = FileAccess.get_sha256(path)
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json"
	scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit = scene.interior_visit
	await _ticks(25)
	original_inventory = _inventory()
	var catalog: Variant = visit.get("catalog")
	var api_ok: bool = catalog is Array and visit.has_method("select_building") and visit.has_method("request_floor")
	_check("startup.building_visit_API",api_ok and visit.loaded)
	if not api_ok:_finish();return
	_check("catalog.broad_building_access",catalog.size()>10,{"count":catalog.size()})
	var source_connected := true
	var library_present := false
	var dimensions_valid := true
	var envelope_matches := true
	var floors_basis_valid := true
	var declared_levels := 0
	var inferred_levels := 0
	var unsafe_doors: Array = []
	var escaped_rectangles: Array = []
	for spec: Dictionary in catalog:
		if not scene.city.source_nodes.has(spec.id):source_connected = false
		if spec.id==LIBRARY_ID:library_present = true
		if float(spec.width)<12. or float(spec.depth)<16. or int(spec.floor_count)<1:dimensions_valid = false
		if absf(float(spec.floor_count)*float(spec.floor_height)-float(spec.source_height))>.01:envelope_matches = false
		if spec.floors_basis=="osm_building_levels":
			declared_levels += 1
			if spec.source_levels==null or int(spec.source_levels)!=int(spec.floor_count):floors_basis_valid = false
		elif spec.floors_basis=="assumed_from_source_envelope_3.6m":inferred_levels += 1
		else:floors_basis_valid = false
		if String(spec.height_basis).is_empty() or spec.source_reference_ids.is_empty():floors_basis_valid = false
		if visit._safe_external_point(spec.entrance).is_empty():unsafe_doors.append(spec.id)
		var centre: Vector2 = spec.rectangle_center
		var along: Vector3 = spec.rectangle_along
		var outward: Vector3 = spec.rectangle_outward
		var rectangle_inside := true
		for u in [-.45,0.,.45]:
			for v in [-.45,0.,.45]:
				var point: Vector2 = centre+Vector2(along.x,along.z)*float(spec.width)*u+Vector2(outward.x,outward.z)*float(spec.depth)*v
				if not _source_contains(point,spec):rectangle_inside = false
		if not rectangle_inside:escaped_rectangles.append(spec.id)
	_check("catalog.every_entry_has_source_building",source_connected)
	_check("catalog.library_present",library_present)
	_check("catalog.source_dimensions_valid",dimensions_valid)
	_check("catalog.floor_stack_matches_source_height",envelope_matches)
	_check("catalog.declared_and_inferred_floor_basis_distinct",floors_basis_valid and declared_levels>0 and inferred_levels>0,{"declared_levels":declared_levels,"inferred_levels":inferred_levels})
	_check("catalog.every_selected_door_has_physical_clearance",unsafe_doors.is_empty(),{"checked":catalog.size(),"unsafe_ids":unsafe_doors})
	_check("catalog.floor_rectangles_stay_in_source_polygon_and_avoid_holes",escaped_rectangles.is_empty(),{"samples_per_building":9,"escaped_ids":escaped_rectangles})
	# Library exercises all movement modes; sample two other source-connected buildings.
	if library_present:await _library()
	var sampled := 0
	var sizes := {}
	for spec: Dictionary in catalog:
		if spec.id==LIBRARY_ID:continue
		if sampled>=2 or visit.active:break
		var title := "building_"+str(sampled+1)
		if await _enter(spec.id,title):
			var bounds: AABB = visit.room.interior_bounds
			var row := {"id":spec.id,"spec":spec,"bounds_size":_v(bounds.size),"floor_count":visit.room.floor_count,"body_count":visit.room.bodies.size()}
			buildings.append(row)
			if spec.id=="osm:way:198561926:building":await _capture("cityhall_lobby")
			sizes[str(snappedf(bounds.size.x,.1))+"x"+str(snappedf(bounds.size.z,.1))] = true
			_check(title+".source_sized_room_has_floors",is_equal_approx(visit.room.width,float(spec.width)) and is_equal_approx(visit.room.depth,float(spec.depth)) and visit.room.bodies.size()>=6 and visit.room.floor_count==int(spec.floor_count),row)
			await _leave(title)
			sampled += 1
	_check("catalog.multiple_buildings_entered",sampled==2,{"entered_other_buildings":sampled})
	_check("catalog.room_sizes_vary",sizes.size()>=2,{"distinct_room_sizes":sizes.size(),"buildings":buildings})
	if not visit.active:await _quick_library_jump()
	_check("exterior.original_collision_inventory_unchanged",_inventory()==original_inventory,{"source_body_count":original_inventory.size()})
	_finish()

func _timeout() -> void:
	if finished:return
	_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished = true;_movement();_e(false);paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var report := {"task":"building_visits","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"placements":placements,"walks":walks,"rides":rides,"buildings":buildings,"captures":captures,"summary":{"checks":checks.size(),"failed":failed},"scope":"Scenario starts and one fall fault are explicit test-only teleports. Stair ascent/descent use real controller movement with no per-step teleports; E uses production physical binding. Midride blockers are explicit fault fixtures. Floor dimensions/layouts/people are authored source-linked game representations, not surveyed or actual public access. Native GPU captures only when display is not headless; no native-human-input, performance or packaging acceptance."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save building visits report")
	print("BUILDING_VISITS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

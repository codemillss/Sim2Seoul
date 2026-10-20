extends SceneTree
## Contact regression: only starting poses are teleports; facade contact is real movement.
const MOVEMENT_ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var report_path := ""
var scene
var visit
var checks: Array = []
var contacts: Array = []
var source_hashes := {}
var finished := false
var blocked_return_checked := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path = arg.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_library_entry_contact requires --report=<absolute path>");quit(1);return
	for action in MOVEMENT_ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	# Production setup owns the physical E binding; do not install a test substitute.
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second = 60
	create_timer(90.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("LIBRARY_CONTACT_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _movement(actions: Array = []) -> void:
	for action in MOVEMENT_ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _e(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E;event.keycode = KEY_E;event.pressed = pressed
	Input.parse_input_event(event)

func _ticks(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func _pose(point: Vector3) -> void:
	_movement();_e(false)
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	var outward: Vector3 = visit.entrance_outward_direction.normalized()
	visit._orient(atan2(outward.x,outward.z),deg_to_rad(-15.),4.5)
	await _ticks(16)

func _blocker(title: String, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();body.name = title;body.position = at+Vector3.UP
	body.collision_layer = 1;body.collision_mask = 0
	var node := CollisionShape3D.new();var box := BoxShape3D.new()
	box.size = Vector3(4.,2.,4.);node.shape = box
	body.add_child(node);scene.add_child(body)
	return body

func _contact_evidence(lateral: float, start: Vector3, earlier: Vector3) -> Dictionary:
	var point: Vector3 = scene.player.global_position
	var shape: CapsuleShape3D = scene.player.get_node("CollisionShape").shape
	# Match the return validator's ground+0.08m point rather than count the
	# controller's sub-millimetre floor penetration as a facade obstruction.
	var return_point := point
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,scene.player.collision_mask,[scene.player.get_rid()])
	var ground: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
	if not ground.is_empty():return_point.y = ground.position.y+.08
	return {"lateral_m":lateral,"start":_v(start),"position":_v(point),"walked_m":point.distance_to(start),
		"last_10_ticks_motion_m":point.distance_to(earlier),"on_wall":scene.player.is_on_wall(),
		"entry_near":visit._entry_near(),"entry_visible":visit._entry_visible(),"on_floor":scene.player.is_on_floor(),
		"input_latched":scene.player.input_latched,"safe_current_return":not visit._safe_external_point(point).is_empty(),
		"physical_radius_m":shape.radius,"physical_safe_margin_m":scene.player.safe_margin,
		"return_validation_point":_v(return_point),"source_penetration_m":scene.city.volume_penetration(return_point,shape.height,shape.radius),
		"return_margin_penetration_m":scene.city.volume_penetration(return_point,shape.height,shape.radius+.005)}

func _exit_and_check(title: String) -> void:
	_movement();_e(false);await _ticks(5)
	await _pose(visit.room.exit_point())
	if not blocked_return_checked:
		blocked_return_checked = true
		var row: Array = visit.snapshot().outside_return
		var at := Vector3(row[0],row[1],row[2])
		var blockers := [_blocker("BlockedEntryContactReturn",at),_blocker("BlockedWorldSpawn",visit._world_spawn)]
		await _ticks(4)
		_e(true);await _ticks(5);_e(false);await _ticks(4)
		_check("exit.all_returns_blocked_stays_inside",visit.active and scene.player.interior_active and scene.player.is_on_floor(),visit.snapshot())
		for body in blockers:body.queue_free()
		await _ticks(5)
	var entries: int = visit.entry_count
	_movement(["move_forward"]);_e(true);await _ticks(25)
	_check(title+".exit_is_safe",not visit.active and not scene.player.interior_active and not visit._safe_external_point(scene.player.global_position).is_empty(),{"position":_v(scene.player.global_position),"state":visit.snapshot()})
	_check(title+".held_E_cannot_reenter",visit.entry_count==entries and not visit.active)
	_movement();_e(false);await _ticks(5)

func _run() -> void:
	for path in ["res://scripts/interior_visit.gd","res://scripts/player/free_roam_player.gd","res://../tests/game/check_library_entry_contact.gd"]:source_hashes[path] = FileAccess.get_sha256(path)
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json"
	scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit = scene.interior_visit
	await _ticks(25)
	_check("startup",visit.loaded and not visit.active)
	_check("physical_E_production_binding",InputMap.action_get_events("interact").any(func(event):return event is InputEventKey and event.physical_keycode==KEY_E))
	_check("library.selected",visit.select_building(visit.LIBRARY_ID))
	var outward: Vector3 = visit.entrance_outward_direction.normalized()
	# The player remains at a valid outdoor pose while a thin real collider
	# interrupts only the line between the player and the entrance marker.
	await _pose(visit.entrance_world_position+outward)
	var wall := StaticBody3D.new();wall.name = "EntryLineOfSightFault"
	wall.position = visit.entrance_world_position+outward*.5+Vector3.UP
	wall.collision_layer = 1;wall.collision_mask = 0
	var wall_node := CollisionShape3D.new();var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(2.5,2.,.15);wall_node.shape = wall_box
	wall.add_child(wall_node);scene.add_child(wall);await _ticks(4)
	var blocked_start: Vector3 = scene.player.global_position
	var before: int = visit.entry_count
	_e(true);_e(false);await _ticks(4)
	_check("entry.occluding_wall_blocks_physical_E",not visit.active and visit.entry_count==before and visit._entry_near() and not visit._entry_visible() and scene.player.is_on_floor() and scene.player.global_position.distance_to(blocked_start)<.02,visit.snapshot())
	wall.queue_free();await _ticks(5)
	# Use a real Space-action jump. Tap E early enough to remain in the portal's
	# vertical range, isolating the grounded requirement rather than distance.
	await _pose(visit.entrance_world_position)
	# Preserve the original 0.10-second early-jump observation at either the
	# exploration's 30 Hz default or the historical 60 Hz setting.
	_movement(["jump"]);await _ticks(ceili(.10*Engine.physics_ticks_per_second))
	var airborne: bool = not scene.player.is_on_floor() and visit._entry_near() and visit._entry_visible()
	before = visit.entry_count
	_e(true);_e(false);await _ticks(3)
	_check("entry.airborne_jump_blocks_physical_E",airborne and not visit.active and visit.entry_count==before,visit.snapshot())
	_movement();await _ticks(110)
	# A complete physical key tap between physics samples must survive to the next tick.
	await _pose(visit.entrance_world_position)
	_e(true);_e(false);await _ticks(6)
	_check("input.short_physical_E_tap_enters",visit.active,visit.snapshot())
	if visit.active:await _exit_and_check("short_tap")
	var along := Vector3(outward.z,0.,-outward.x)
	for lateral: float in [0.,-1.8,1.8,-2.2,2.2]:
		if visit.active:_check("previous_exit_completed",false);break
		var title := "contact_%+.1fm"%lateral
		await _pose(visit.entrance_world_position+along*lateral)
		var start: Vector3 = scene.player.global_position
		_movement(["move_forward"]);await _ticks(110)
		var earlier: Vector3 = scene.player.global_position
		await _ticks(10)
		var evidence := _contact_evidence(lateral,start,earlier)
		contacts.append(evidence)
		_check(title+".walk_reaches_solid_facade",evidence.walked_m>1.4 and evidence.last_10_ticks_motion_m<.01 and evidence.on_wall,evidence)
		var count: int = visit.entry_count
		_e(true);await _ticks(25)
		_check(title+".E_enters_while_W_held",visit.active and visit.entry_count==count+1,{"contact":evidence,"state":visit.snapshot()})
		_check(title+".held_E_only_once",visit.entry_count<=count+1)
		if visit.active:await _exit_and_check(title)
		else:_movement();_e(false);await _ticks(5)
	# Holding E while walking into reach must not become a fresh press.
	if not visit.active:
		await _pose(visit.entrance_world_position+outward*4.)
		_e(true);await _ticks(5)
		_movement(["move_forward"]);await _ticks(100)
		_check("input.far_held_E_does_not_autoenter",not visit.active,visit.snapshot())
		_movement();_e(false);await _ticks(5)
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
	var report := {"task":"library_entry_contact","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"checks":checks,"contacts":contacts,"summary":{"checks":checks.size(),"failed":failed},"scope":"Starting and indoor exit poses are explicit test-only teleports. Every facade contact is reached through the real controller with forward input. E uses the production physical key mapping; no native keyboard/GPU claims."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save library contact report")
	print("LIBRARY_CONTACT_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

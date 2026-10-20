extends SceneTree
## Test observer placements are explicit. E uses physical keyboard events,
## the ordinary dispatcher and the production capsule/ride controller.
var scene: Node3D
var service: Node3D
var checks: Array[Dictionary]=[]
var report_path:="/tmp/bike-entry-reliability.json"
var finished:=false
var physical_device:=0
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	create_timer(240.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _ticks(count: int) -> void:
	for tick: int in range(count):await scene.rig.camera_stepped
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	return value
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("BIKE_ENTRY_CHECK ",title," ",ok)
func _e(down: bool) -> void:
	var key:=InputEventKey.new();key.physical_keycode=KEY_E;key.keycode=KEY_E;key.pressed=down;key.device=physical_device;Input.parse_input_event(key)
func _tap_e() -> void:
	_e(true);await _ticks(3);_e(false);await _ticks(5)
func _finish() -> void:
	if finished:return
	finished=true
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var hashes: Dictionary={}
	for path: String in ["res://scripts/city_bike_service.gd","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://../tests/game/check_bike_entry_reliability.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"bike_E_entry_reliability","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"source_hashes":hashes,"scope":"Production physical E keyboard events with explicit observer placements around both bikes, contact and ground gates. No subjective/native visual acceptance."}),"  "));file.close();print("BIKE_ENTRY_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _clear_rental(at: Vector3) -> void:
	_e(false);scene.player.global_transform=Transform3D(Basis.IDENTITY,at)
	if service.riding:service.cancel_ride_for_teleport()
	scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(6)
func _pedestrian_sight_cases(spawn: Vector3) -> void:
	var view: Dictionary=service.viewpoint();await _clear_rental(view.point)
	var body: CharacterBody3D=service.bikes[0].body
	var direction: Vector3=scene.player.global_position-body.global_position;direction.y=0.;direction=direction.normalized()
	var pedestrian:=CharacterBody3D.new();pedestrian.name="TestRegisteredPassingPedestrian";pedestrian.collision_layer=4
	var capsule_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.76;capsule_shape.shape=capsule;capsule_shape.position.y=.90;pedestrian.add_child(capsule_shape);scene.add_child(pedestrian)
	pedestrian.global_position=body.global_position+direction*.95;scene.traffic.register_human(pedestrian);await _ticks(3)
	var raw_hits:=0
	for height: float in [.65,1.2]:
		var ray:=PhysicsRayQueryParameters3D.create(scene.player.global_position+Vector3.UP*height,body.global_position+Vector3.UP*height,1|4|8|32,[scene.player.get_rid(),body.get_rid()])
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==pedestrian:raw_hits+=1
	_check("passing_registered_NPC_blocks_raw_rays_but_keeps_E_target",raw_hits==2 and service.can_interact(),{"raw_NPC_ray_hits":raw_hits,"can_interact":service.can_interact()})
	await _tap_e();_check("physical_E_borrows_when_passer_is_outside_mount_volume",service.riding)
	await _clear_rental(view.point)
	# A solid wall behind the ignored NPC must still block the recast rays.
	var wall:=StaticBody3D.new();wall.collision_layer=1;var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(.15,2.,1.8);wall_shape.shape=wall_box;wall.add_child(wall_shape);scene.add_child(wall)
	wall.global_transform=Transform3D(Basis(direction,Vector3.UP,direction.cross(Vector3.UP)),body.global_position+direction*.55+Vector3.UP)
	await _ticks(3);await _tap_e();_check("wall_behind_ignored_NPC_still_blocks_physical_E",not service.can_interact() and not service.riding)
	wall.queue_free();await _ticks(3)
	# An NPC occupying the actual rider volume is ignored only for sight.
	# The native full-body safety query must explain and reject the mount.
	pedestrian.global_position=body.global_position;await _ticks(3)
	var could_attempt: bool=service.can_interact();var count: int=scene.interior_visit.entry_count;await _tap_e()
	_check("NPC_in_mount_volume_consumes_E_with_blocked_space_reason",could_attempt and not service.riding and service.blocked_reason=="mount_space_blocked" and service.prompt_text().contains("막혀") and scene.interior_visit.entry_count==count,{"could_attempt":could_attempt,"reason":service.blocked_reason,"prompt":service.prompt_text()})
	scene.traffic.humans.erase(pedestrian);pedestrian.queue_free();await _ticks(3);await _tap_e()
	_check("physical_E_retry_borrows_after_NPC_leaves_mount_volume",service.riding)
	await _clear_rental(spawn)
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/bike-entry-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(8);service=scene.get("city_bike_service")
	_check("production_setup",scene.runtime_ok and is_instance_valid(service) and service.loaded)
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_speed_profile("turbo")
	var spawn: Vector3=scene.player.global_position
	for device: int in [0,16,42]:
		physical_device=device
		for bike_index: int in range(service.bikes.size()):
			var body: CharacterBody3D=service.bikes[bike_index].body
			for offset: Vector3 in [Vector3(.72,0,0),Vector3(-.72,0,0),Vector3(0,0,-1.34),Vector3(0,0,1.34),Vector3(1.85,0,0),Vector3(-1.85,0,0),Vector3(0,0,-2.15),Vector3(0,0,2.15)]:
				var requested: Vector3=body.to_global(offset);var safe: Dictionary=scene.interior_visit._safe_external_point(requested)
				if safe.is_empty():_check("native_blocked_observer_not_placed_%d_%s_device%d"%[bike_index,offset,device],true,{"requested":requested,"scope":"No observer teleport into a wall or parked vehicle was fabricated; this contact direction is obstructed."});continue
				await _clear_rental(safe.point)
				var visible: bool=service._visible_bike(bike_index)
				var before: Dictionary={"offset":offset,"requested":requested,"actual":scene.player.global_position,"grounded":scene.player.is_on_floor(),"input_latched":scene.player.input_latched,"can_interact":service.can_interact(),"prompt":service.prompt_text(),"visible":visible,"distance_m":scene.player.global_position.distance_to(body.global_position),"e_requires_release":scene.interior_visit.e_requires_release,"physical_device":device}
				await _tap_e();_check(("physical_E_borrows" if visible else "physical_E_does_not_cross_blocking_geometry")+"_bike%d_%s_device%d"%[bike_index,offset,device],(service.riding and service.rental_index==bike_index) if visible else not service.riding,before)
				await _clear_rental(spawn)
	physical_device=0
	# A fresh press and release both arrive before the next physics tick after
	# the actual menu shortcut. They must not be lost behind a resume latch.
	scene.toggle_menu();scene._visit_street_detail("bike_station");_e(true);_e(false);await _ticks(8)
	_check("immediate_shortcut_physical_E_tap_without_waiting_a_tick",service.riding,{"e_requires_release":scene.interior_visit.e_requires_release,"events":service.events})
	await _clear_rental(spawn)
	scene.toggle_menu();_e(true)
	for frame: int in range(3):await process_frame
	scene._visit_street_detail("bike_station");await _ticks(8)
	_check("E_held_through_menu_does_not_borrow",not service.riding)
	_e(false);_e(true);_e(false);await _ticks(8);_check("fresh_E_after_menu_release_borrows",service.riding)
	await _clear_rental(spawn)
	var view: Dictionary=service.viewpoint();scene.player.global_position=view.point+Vector3.UP*.8;scene.player.velocity=Vector3.UP*2.;scene.player.reset_physics_interpolation();await _tap_e()
	_check("airborne_physical_E_does_not_borrow",not service.riding)
	await _clear_rental(view.point)
	var body: CharacterBody3D=service.bikes[0].body
	var blocker:=StaticBody3D.new();blocker.collision_layer=1;var blocker_shape:=CollisionShape3D.new();var blocker_box:=BoxShape3D.new();blocker_box.size=Vector3(.2,.2,.2);blocker_shape.shape=blocker_box;blocker.add_child(blocker_shape);scene.add_child(blocker);blocker.global_position=body.global_position+Vector3.UP*1.65;await _ticks(3)
	var entry_count: int=scene.interior_visit.entry_count;await _tap_e()
	_check("blocked_mount_consumes_E_and_explains_without_entering_building",not service.riding and service.blocked_reason=="mount_space_blocked" and service.prompt_text().contains("막혀") and scene.interior_visit.entry_count==entry_count,{"prompt":service.prompt_text(),"events":service.events})
	blocker.queue_free();await _ticks(3);await _tap_e();_check("fresh_E_retries_after_blocker_removed",service.riding)
	await _clear_rental(spawn)
	await _pedestrian_sight_cases(spawn)
	_finish()

extends "res://../tests/game/check_large_outdoor_pool.gd"
## Starts at the real street entrance, climbs with fresh Space presses and
## production movement, lands on the visible outdoor roof, swims and jumps off.

func _pose(title: String, point: Vector3) -> bool:
	if title=="pool_external_ramp_start":
		if scene.player.global_position.distance_to(point)<.25:return scene.player.is_on_floor()
		return await _walk_path("direct_roof.walk_arrival_deck_to_pool_steps",[point])
	return await super._pose(title,point)

func _jump_pulse() -> void:
	Input.action_press("jump");await _ticks(1)
	Input.action_release("jump");await _ticks(11)

func _climb_from_street() -> bool:
	var recoveries: int=scene.player.recoveries
	var start: Vector3=scene.player.global_position
	var pulses: int=0
	while scene.player.global_position.y<roof.deck_height_y+5.0 and pulses<100:
		await _jump_pulse();pulses+=1
	var summit: Vector3=scene.player.global_position
	_check("direct_roof.real_fresh_Space_ascent_from_original_street",summit.y>=roof.deck_height_y+5.0 and pulses>20 and scene.player.recoveries==recoveries and not visit.active and not scene.player.interior_active,{"start":start,"summit":summit,"fresh_jump_presses":pulses,"recoveries":scene.player.recoveries-recoveries})
	var destination: Vector3=roof.spawn_point()
	var reached: bool=false;var moved_ticks: int=0
	for tick in range(900):
		var offset: Vector3=Vector3(destination.x-scene.player.global_position.x,0,destination.z-scene.player.global_position.z)
		if offset.length()<.20:reached=true;break
		_world_keys(offset.normalized())
		if scene.player.global_position.y<roof.deck_height_y+4.0 and tick%12==0:Input.action_press("jump")
		else:Input.action_release("jump")
		await _ticks(1);moved_ticks+=1
	_movement()
	for tick in range(360):
		await _ticks(1)
		if scene.player.is_on_floor():break
	var landed: bool=reached and scene.player.is_on_floor() and absf(scene.player.global_position.y-roof.deck_height_y)<.15
	_check("direct_roof.outdoor_landing_without_E_lift_or_region_teleport",landed and not visit.active and not scene.player.interior_active and roof.is_visible_in_tree() and scene.player.recoveries==recoveries,{"destination":destination,"actual":scene.player.global_position,"movement_ticks":moved_ticks,"visit_active":visit.active,"player_interior_active":scene.player.interior_active,"roof_visible":roof.is_visible_in_tree(),"water":scene.player.water_snapshot()})
	return landed

func _jump_off_to_street() -> void:
	# Follow the nearest clear side deck to the north edge before one outward jump.
	# Scenario starts and ascent were explicit; this return uses no relocation.
	var local: Vector3=roof.frame.affine_inverse()*scene.player.global_position
	var side_x: float=roof.width*.5-1.2 if local.x>0.0 else -roof.width*.5+3.2
	var front_z: float=-roof.depth*.5+1.0
	var before_recoveries: int=scene.player.recoveries
	var path: Array=[roof.frame*Vector3(side_x,.08,local.z),roof.frame*Vector3(side_x,.08,front_z)]
	if not await _walk_path("direct_roof.walk_open_side_deck_to_edge",path):return
	scene.set_speed_profile("turbo");_movement();await _ticks(3)
	var start: Vector3=scene.player.global_position
	var outward: Vector3=-roof.frame.basis.z
	_world_keys(outward);Input.action_press("jump")
	var source_left: bool=false;var peak: float=start.y
	for tick in range(180):
		await _ticks(1);peak=maxf(peak,scene.player.global_position.y)
		if not _source_contains(Vector2(scene.player.global_position.x,scene.player.global_position.z),roof.spec):source_left=true;break
	if source_left:await _ticks(12)
	_movement()
	for tick in range(900):
		await _ticks(1)
		if scene.player.is_on_floor() and scene.player.global_position.y<2.0:break
	var landed: bool=scene.player.is_on_floor() and scene.player.global_position.y<2.0
	_check("direct_roof.single_jump_crosses_actual_source_edge_and_lands_outside_without_lift",source_left and landed and peak>roof.deck_height_y+1.3 and not visit.active and not scene.player.interior_active and scene.player.recoveries==before_recoveries,{"start":start,"peak_world_y":peak,"end":scene.player.global_position,"source_footprint_left":source_left,"grounded":scene.player.is_on_floor(),"recoveries":scene.player.recoveries-before_recoveries,"water":scene.player.water_snapshot()})
	_check("direct_roof.outdoor_departure_clears_only_pool_water",not scene.player.water_snapshot().registered and _inventory()==original_inventory,{"water":scene.player.water_snapshot(),"original_source_bodies":original_inventory.size()})

func _run() -> void:
	for path: String in ["res://scripts/rooftop_space.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/player/free_roam_player.gd","res://scripts/interior_visit.gd","res://scripts/explore_walk.gd","res://../tests/game/check_outdoor_roof_jumping.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	scene.set_speed_profile("brisk");scene.set_free_roam(true);_movement();await _ticks(4)
	var helper: Node3D=scene.get_node_or_null("ExplorationRooftopAccess")
	_check("direct_roof.shared_outdoor_roof_helper_ready",is_instance_valid(helper))
	if not is_instance_valid(helper):_finish();return
	roof=helper.ensure_rooftop(HOTEL_ID)
	if not is_instance_valid(roof):_check("direct_roof.pool_exists",false);_finish();return
	var hotel: Dictionary={}
	for building: Dictionary in visit.catalog:
		if building.id==HOTEL_ID:hotel=building;break
	if hotel.is_empty():_check("direct_roof.hotel_source_spec",false);_finish();return
	if not await _pose("only_fixture_original_hotel_street_start",hotel.entrance):_finish();return
	if not await _climb_from_street():_finish();return
	_observe_raised_basin()
	if await _jump_into_pool():
		await _float_and_swim();await _exit_water()
	await _jump_off_to_street()
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed: int=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var result: Dictionary={"task":"DIRECT_OUTDOOR_ROOF_JUMP_AND_LARGE_POOL","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"basin":basin_observation,"trials":swim_trials,"walks":walks,"placements":placements,"captures":captures,"deferred_checks":deferred_checks,"scope":"Only the real source hotel street start is a labelled fixture. Subsequent ascent, rooftop landing, ramp/jump entry, >20m swimming, Space water exit, crossing the real source footprint and street landing use production actions/move_and_slide. No elevator, portal, assigned flight velocity or per-step teleports. Authored pool is not a factual venue. Not human usability/performance/export acceptance."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save direct rooftop report")
	print("DIRECT_OUTDOOR_ROOF_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

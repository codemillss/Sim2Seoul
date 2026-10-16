extends "res://../tests/game/check_jump.gd"
## Historical filename; now verifies unlimited fresh-edge air jumps using the
## existing engine fixture/controller helpers. No settings or native UI.
var input_trials: Array = []

func _boost(title: String) -> void:
	_keys(["jump"]);await _ticks(1)
	await _ticks(20)
	_keys([]);await _ticks(2)
	var before := {"position":_v(player.global_position),"velocity_y":player.velocity.y,"remaining":player.air_jumps_remaining(),"air_count":player.air_jump_count()}
	_keys(["jump"]);await _ticks(1)
	var expected: float=sqrt(2.0*player.gravity_mps2*player.jump_height_m)-.5*player.gravity_mps2*player.step_delta
	var row := {"name":title,"before":before,"after_position":_v(player.global_position),"after_velocity_y":player.velocity.y,"remaining":player.air_jumps_remaining(),"expected_replaced_velocity_y":expected}
	input_trials.append(row)
	_check(title+".second_edge_replaces_vertical_speed_once",before.remaining==-1 and player.air_jumps_remaining()==-1 and player.air_jump_count()==int(before.air_count)+1 and absf(player.velocity.y-expected)<.025 and not player.is_on_floor(),row)

func _third(title: String) -> void:
	_keys([]);await _ticks(2)
	var before: float=player.velocity.y
	var count_before: int=player.air_jump_count()
	_keys(["jump"]);await _ticks(1)
	var row := {"name":title,"velocity_before":before,"velocity_after":player.velocity.y,"remaining":player.air_jumps_remaining(),"expected_gravity_step":player.gravity_mps2*player.step_delta}
	input_trials.append(row)
	var expected: float=sqrt(2.0*player.gravity_mps2*player.jump_height_m)-.5*player.gravity_mps2*player.step_delta
	_check(title+".third_fresh_air_edge_is_allowed_and_replaces_speed",player.air_jumps_remaining()==-1 and player.air_jump_count()==count_before+1 and absf(player.velocity.y-expected)<.025,row)

func _six_fresh_edges() -> void:
	await _pose()
	var rows:=[];var accepted:=0;var peak: float=player.global_position.y
	var start: Vector3=player.global_position;var recoveries: int=player.recoveries
	for index in range(6):
		_keys([]);await _ticks(2)
		_keys(["jump"]);await _ticks(1)
		if player.velocity.y>7.4:accepted+=1
		rows.append({"press":index+1,"position":_v(player.global_position),"velocity_y":player.velocity.y,"air_count":player.air_jump_count(),"remaining":player.air_jumps_remaining()})
		await _ticks(20);peak=maxf(peak,player.global_position.y)
	_check("chain.six_fresh_edges_boost_without_a_count_cap",accepted==6 and player.air_jump_count()==5 and player.air_jumps_remaining()==-1 and peak-start.y>12.0 and player.recoveries==recoveries,{"presses":rows,"peak_rise_m":peak-start.y,"recovery_delta":player.recoveries-recoveries})
	var row:=await _flight("sixth_edge_held_until_landing",["jump"],240)
	_check("chain.holding_sixth_press_never_auto_repeats_and_landing_resets_count",row.ascending_episodes==1 and row.ending_grounded and row.floor_ticks>30 and player.air_jump_count()==0 and player.air_jumps_remaining()==-1,row)

func _menu_budget(spend: bool) -> void:
	await _pose()
	if spend:await _boost("menu_spent_setup")
	else:_keys(["jump"]);await _ticks(14)
	var count: int=player.air_jump_count()
	router.gameplay_enabled=false;player.require_neutral_input();paused=true
	var at: Vector3=player.global_position
	var vertical: float=player.velocity.y
	_keys(["jump"])
	for index in range(4):await process_frame
	_check("menu."+("air_chain" if spend else "takeoff")+".pause_preserves_pose_and_air_count",player.global_position==at and player.velocity.y==vertical and player.air_jump_count()==count and player.air_jumps_remaining()==-1,{"air_count":count,"position":_v(at)})
	paused=false;router.gameplay_enabled=true
	await _ticks(2)
	_check("menu."+("air_chain" if spend else "takeoff")+".held_space_has_no_boost",player.input_latched and player.air_jump_count()==count and player.velocity.y<vertical,{"before":vertical,"after":player.velocity.y,"air_count":player.air_jump_count()})
	_keys([]);await _ticks(2)
	var before: float=player.velocity.y
	_keys(["jump"]);await _ticks(1)
	_check("menu."+("air_chain" if spend else "takeoff")+".new_fresh_edge_boosts_and_increments_preserved_count",player.air_jumps_remaining()==-1 and player.air_jump_count()==count+1 and player.velocity.y>7.4,{"before":before,"after":player.velocity.y,"count_before_pause":count,"count_after_fresh_press":player.air_jump_count()})
	_keys([]);await _ticks(180)

func _walkoff() -> void:
	var platform:=_solid("WalkoffPlatform",Vector3(4,.2,4),Vector3(0,2.9,0))
	await _pose(Vector3(0,3.08,0))
	_keys(["move_right"])
	var departed:=false
	for index in range(100):
		await _ticks(1)
		if not player.is_on_floor():departed=true;break
	_keys([]);await _ticks(3)
	var before: float=player.velocity.y
	_check("walkoff.unlimited_fresh_edges_available_without_ground_takeoff",departed and player.air_jumps_remaining()==-1 and player.air_jump_count()==0 and before<0.,{"position":_v(player.global_position),"velocity_y":before,"remaining":player.air_jumps_remaining()})
	_keys(["jump"]);await _ticks(1)
	_check("walkoff.fresh_air_edge_arrests_fall",player.velocity.y>7.4 and player.air_jumps_remaining()==-1 and player.air_jump_count()==1,{"before":before,"after":player.velocity.y})
	await _third("walkoff")
	_keys([]);await _ticks(180)
	platform.free()

func _ceiling_budget() -> void:
	await _pose()
	var ceiling:=_solid("BudgetCeiling",Vector3(3,.3,3),Vector3(0,2.45,0))
	await _ticks(2)
	_keys(["jump"])
	var hit:=false
	for index in range(20):
		await _ticks(1)
		if player.is_on_ceiling():hit=true;break
	_keys([]);await _ticks(1)
	_keys(["jump"]);await _ticks(1)
	_check("ceiling.air_attempt_is_counted_without_head_through_slab",hit and player.air_jumps_remaining()==-1 and player.air_jump_count()==1 and player.global_position.y<.65,{"ceiling_contact":hit,"position":_v(player.global_position),"air_count":player.air_jump_count()})
	_keys([]);await _ticks(1)
	var before: float=player.velocity.y
	var count: int=player.air_jump_count()
	_keys(["jump"]);await _ticks(1)
	_check("ceiling.further_fresh_edge_still_cannot_cross_physical_slab",player.air_jumps_remaining()==-1 and player.air_jump_count()==count+1 and player.global_position.y<.65 and player.velocity.y<=.05,{"before":before,"after":player.velocity.y,"air_count":player.air_jump_count()})
	ceiling.free();_keys([]);await _ticks(160)

func _transitions() -> void:
	await _pose();await _boost("recovery_setup")
	var recoveries: int=player.recoveries
	player.global_position=Vector3(0,player.fall_limit_y-1.,0)
	await _ticks(1)
	_check("recovery.success_resets_air_count_and_latches_held_space",player.recoveries==recoveries+1 and player.air_jumps_remaining()==-1 and player.air_jump_count()==0 and player.input_latched and player.velocity==Vector3.ZERO)
	var row:=await _flight("recovery_held_space",["jump"],20)
	_check("recovery.held_space_is_not_a_buffered_takeoff",row.ascending_episodes==0 and row.ending_grounded,row)
	await _pose();await _boost("portal_setup")
	var bounds:=AABB(Vector3(-10,-.5,-10),Vector3(20,20,20))
	var accepted: bool=player.begin_interior(Vector3(0,.08,0),bounds)
	_check("portal.valid_entry_resets_air_count_and_requires_neutral",accepted and player.air_jumps_remaining()==-1 and player.air_jump_count()==0 and player.input_latched)
	_keys([]);await _ticks(8);await _boost("indoor_relocate_setup")
	var before: Vector3=player.global_position
	var count: int=player.air_jump_count()
	var rejected: bool=not player.relocate_interior(Vector3(1000,0,0)) and not player.end_interior(Vector3.INF) and not player.begin_interior(Vector3(0,.08,0),bounds)
	_check("portal.rejected_transactions_preserve_air_count_and_pose",rejected and player.air_jumps_remaining()==-1 and player.air_jump_count()==count and count>0 and player.global_position==before)
	accepted=player.relocate_interior(Vector3(0,.08,0))
	_check("portal.valid_lift_landing_resets_air_count_and_latches_input",accepted and player.air_jumps_remaining()==-1 and player.air_jump_count()==0 and player.input_latched)
	_keys([]);await _ticks(8);await _boost("indoor_exit_setup")
	accepted=player.end_interior(Vector3(0,.08,0))
	_check("portal.valid_exit_resets_air_count_and_latches_input",accepted and not player.interior_active and player.air_jumps_remaining()==-1 and player.air_jump_count()==0 and player.input_latched)
	_keys([]);await _ticks(8)

func _run() -> void:
	_build();await _pose()
	_check("defaults.unlimited_fresh_air_edges_and_three_metre_impulse",player.MAX_AIR_JUMPS==-1 and player.has_unlimited_air_jumps() and player.air_jumps_remaining()==-1 and player.jump_height_m==3.0)
	var row:=await _flight("held_single_jump",["jump"])
	_check("ground.original_three_metre_apex_and_hold_safety",absf(float(row.apex_rise_m)-3.)<.12 and row.ascending_episodes==1 and row.ending_grounded,row)
	await _pose();await _boost("double")
	await _third("double")
	row=await _flight("third_held_to_landing",["jump"],180)
	_check("landing.resets_air_count_without_held_auto_jump",row.ending_grounded and row.floor_ticks>30 and row.ascending_episodes==1 and player.air_jumps_remaining()==-1 and player.air_jump_count()==0,row)
	_keys([]);await _ticks(2);await _boost("repeated_after_landing")
	_keys([]);await _ticks(180)
	await _six_fresh_edges();await _menu_budget(true);await _menu_budget(false)
	await _walkoff();await _ceiling_budget();await _transitions()
	await _pose();await _boost("turbo_air_control_setup")
	player.run_speed_mps=21.
	var start: Vector3=player.global_position
	_keys(["move_right","move_forward","move_fast"]);await _ticks(12)
	var offset: Vector3=player.global_position-start
	_check("air_control.turbo_diagonal_keeps_normalised_horizontal_speed",absf(Vector2(offset.x,offset.z).length()-4.2)<.04 and player.air_jumps_remaining()==-1 and player.air_jump_count()>0 and not player.is_on_floor(),{"horizontal_distance_m":Vector2(offset.x,offset.z).length(),"expected_m":4.2,"position":_v(player.global_position)})
	_keys([]);_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([]);paused=false
	var failures:=0
	for check in checks:
		if not check.passed:failures+=1
	var hashes:={}
	for path in ["res://scripts/player/free_roam_player.gd","res://../tests/game/check_jump.gd","res://../tests/game/check_double_jump.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var result:={"task":"EXPLORATION_AIR_JUMPS","result":"PASS" if failures==0 else "FAIL","summary":{"checks":checks.size(),"failed":failures},"source_sha256":hashes,"checks":checks,"trials":trials,"input_trials":input_trials,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second},"scope":"Historical check_double_jump filename now checks unlimited fresh-press air jumps, including six consecutive boosts, held-Space safety, physical ceilings, pause and transaction count semantics. Actual production controller and Input.action_press/release in an isolated synthetic metre fixture. Scenario starts and one fall fault are explicit test-only teleports. No player velocity is assigned to fake an airborne boost. UI/user settings/native game remain untouched. Camera, full city routes, performance and rooftop transactions are separately tested."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	else:failures+=1;push_error("Cannot save double jump report")
	print("DOUBLE_JUMP_TEST ","PASS" if failures==0 else "FAIL"," checks=",checks.size()," failed=",failures)
	quit(0 if failures==0 else 1)

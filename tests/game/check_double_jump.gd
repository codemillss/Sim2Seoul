extends "res://../tests/game/check_jump.gd"
## Uses the existing engine fixture/controller helpers. No settings or native UI.
var input_trials: Array = []

func _boost(title: String) -> void:
	_keys(["jump"]);await _ticks(1)
	await _ticks(20)
	_keys([]);await _ticks(2)
	var before := {"position":_v(player.global_position),"velocity_y":player.velocity.y,"remaining":player.air_jumps_remaining()}
	_keys(["jump"]);await _ticks(1)
	var expected: float=sqrt(2.0*player.gravity_mps2*player.jump_height_m)-.5*player.gravity_mps2*player.step_delta
	var row := {"name":title,"before":before,"after_position":_v(player.global_position),"after_velocity_y":player.velocity.y,"remaining":player.air_jumps_remaining(),"expected_replaced_velocity_y":expected}
	input_trials.append(row)
	_check(title+".second_edge_replaces_vertical_speed_once",before.remaining==1 and player.air_jumps_remaining()==0 and absf(player.velocity.y-expected)<.025 and not player.is_on_floor(),row)

func _third(title: String) -> void:
	_keys([]);await _ticks(2)
	var before: float=player.velocity.y
	_keys(["jump"]);await _ticks(1)
	var row := {"name":title,"velocity_before":before,"velocity_after":player.velocity.y,"remaining":player.air_jumps_remaining(),"expected_gravity_step":player.gravity_mps2*player.step_delta}
	input_trials.append(row)
	_check(title+".third_air_edge_cannot_add_impulse",player.air_jumps_remaining()==0 and absf(player.velocity.y-before+player.gravity_mps2*player.step_delta)<.025,row)

func _menu_budget(spend: bool) -> void:
	await _pose()
	if spend:await _boost("menu_spent_setup")
	else:_keys(["jump"]);await _ticks(14)
	var remaining: int=player.air_jumps_remaining()
	router.gameplay_enabled=false;player.require_neutral_input();paused=true
	var at: Vector3=player.global_position
	var vertical: float=player.velocity.y
	_keys(["jump"])
	for index in range(4):await process_frame
	_check("menu."+("spent" if spend else "available")+".pause_preserves_pose_and_budget",player.global_position==at and player.velocity.y==vertical and player.air_jumps_remaining()==remaining,{"remaining":remaining,"position":_v(at)})
	paused=false;router.gameplay_enabled=true
	await _ticks(2)
	_check("menu."+("spent" if spend else "available")+".held_space_has_no_boost",player.input_latched and player.air_jumps_remaining()==remaining and player.velocity.y<vertical,{"before":vertical,"after":player.velocity.y,"remaining":player.air_jumps_remaining()})
	_keys([]);await _ticks(2)
	var before: float=player.velocity.y
	_keys(["jump"]);await _ticks(1)
	if spend:_check("menu.used_budget_is_not_recharged_by_release_or_menu",player.air_jumps_remaining()==0 and player.velocity.y<before-.1,{"before":before,"after":player.velocity.y})
	else:_check("menu.available_air_jump_remains_usable_after_release",player.air_jumps_remaining()==0 and player.velocity.y>7.4,{"before":before,"after":player.velocity.y})
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
	_check("walkoff.one_air_jump_available_without_ground_takeoff",departed and player.air_jumps_remaining()==1 and before<0.,{"position":_v(player.global_position),"velocity_y":before,"remaining":player.air_jumps_remaining()})
	_keys(["jump"]);await _ticks(1)
	_check("walkoff.fresh_air_edge_arrests_fall_once",player.velocity.y>7.4 and player.air_jumps_remaining()==0,{"before":before,"after":player.velocity.y})
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
	_check("ceiling.air_attempt_consumes_budget_without_head_through_slab",hit and player.air_jumps_remaining()==0 and player.global_position.y<.65,{"ceiling_contact":hit,"position":_v(player.global_position),"remaining":player.air_jumps_remaining()})
	_keys([]);await _ticks(1)
	var before: float=player.velocity.y
	_keys(["jump"]);await _ticks(1)
	_check("ceiling.contact_does_not_recharge_air_budget",player.air_jumps_remaining()==0 and player.velocity.y<=before+.001,{"before":before,"after":player.velocity.y})
	ceiling.free();_keys([]);await _ticks(160)

func _transitions() -> void:
	await _pose();await _boost("recovery_setup")
	var recoveries: int=player.recoveries
	player.global_position=Vector3(0,player.fall_limit_y-1.,0)
	await _ticks(1)
	_check("recovery.success_restores_one_air_jump_and_latches_held_space",player.recoveries==recoveries+1 and player.air_jumps_remaining()==1 and player.input_latched and player.velocity==Vector3.ZERO)
	var row:=await _flight("recovery_held_space",["jump"],20)
	_check("recovery.held_space_is_not_a_buffered_takeoff",row.ascending_episodes==0 and row.ending_grounded,row)
	await _pose();await _boost("portal_setup")
	var bounds:=AABB(Vector3(-10,-.5,-10),Vector3(20,20,20))
	var accepted: bool=player.begin_interior(Vector3(0,.08,0),bounds)
	_check("portal.valid_entry_restores_budget_and_requires_neutral",accepted and player.air_jumps_remaining()==1 and player.input_latched)
	_keys([]);await _ticks(8);await _boost("indoor_relocate_setup")
	var before: Vector3=player.global_position
	var rejected: bool=not player.relocate_interior(Vector3(1000,0,0)) and not player.end_interior(Vector3.INF) and not player.begin_interior(Vector3(0,.08,0),bounds)
	_check("portal.rejected_transactions_preserve_spent_budget_and_pose",rejected and player.air_jumps_remaining()==0 and player.global_position==before)
	accepted=player.relocate_interior(Vector3(0,.08,0))
	_check("portal.valid_lift_landing_restores_budget_and_latches_input",accepted and player.air_jumps_remaining()==1 and player.input_latched)
	_keys([]);await _ticks(8);await _boost("indoor_exit_setup")
	accepted=player.end_interior(Vector3(0,.08,0))
	_check("portal.valid_exit_restores_budget_and_latches_input",accepted and not player.interior_active and player.air_jumps_remaining()==1 and player.input_latched)
	_keys([]);await _ticks(8)

func _run() -> void:
	_build();await _pose()
	_check("defaults.one_extra_air_jump_and_three_metre_impulse",player.MAX_AIR_JUMPS==1 and player.air_jumps_remaining()==1 and player.jump_height_m==3.0)
	var row:=await _flight("held_single_jump",["jump"])
	_check("ground.original_three_metre_apex_and_hold_safety",absf(float(row.apex_rise_m)-3.)<.12 and row.ascending_episodes==1 and row.ending_grounded,row)
	await _pose();await _boost("double")
	await _third("double")
	row=await _flight("third_held_to_landing",["jump"],180)
	_check("landing.restores_budget_without_held_auto_jump",row.ending_grounded and row.floor_ticks>30 and row.ascending_episodes==1 and player.air_jumps_remaining()==1,row)
	_keys([]);await _ticks(2);await _boost("repeated_after_landing")
	_keys([]);await _ticks(180)
	await _menu_budget(true);await _menu_budget(false)
	await _walkoff();await _ceiling_budget();await _transitions()
	await _pose();await _boost("turbo_air_control_setup")
	player.run_speed_mps=21.
	var start: Vector3=player.global_position
	_keys(["move_right","move_forward","move_fast"]);await _ticks(12)
	var offset: Vector3=player.global_position-start
	_check("air_control.turbo_diagonal_keeps_normalised_horizontal_speed",absf(Vector2(offset.x,offset.z).length()-4.2)<.04 and player.air_jumps_remaining()==0 and not player.is_on_floor(),{"horizontal_distance_m":Vector2(offset.x,offset.z).length(),"expected_m":4.2,"position":_v(player.global_position)})
	_keys([]);_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([]);paused=false
	var failures:=0
	for check in checks:
		if not check.passed:failures+=1
	var hashes:={}
	for path in ["res://scripts/player/free_roam_player.gd","res://../tests/game/check_jump.gd","res://../tests/game/check_double_jump.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var result:={"task":"DOUBLE_JUMP","result":"PASS" if failures==0 else "FAIL","summary":{"checks":checks.size(),"failed":failures},"source_sha256":hashes,"checks":checks,"trials":trials,"input_trials":input_trials,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second},"scope":"Actual production controller and Input.action_press/release in an isolated synthetic metre fixture. Scenario starts and one fall fault are explicit test-only teleports. No player velocity is assigned to fake an airborne boost. UI/user settings/native game remain untouched. Camera, full city routes, performance and rooftop transactions are separately tested."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	else:failures+=1;push_error("Cannot save double jump report")
	print("DOUBLE_JUMP_TEST ","PASS" if failures==0 else "FAIL"," checks=",checks.size()," failed=",failures)
	quit(0 if failures==0 else 1)

extends "res://../tests/game/check_facility_interactions.gd"
## Current exploration motion: actual city roofs, production Space and visible
## articulated joints. Earlier limited-double-jump reports remain historical.
const ROOF_IDS := [LIBRARY_ID,HOTEL_ID,"osm:way:223158445:building"]
var roof_trials: Array = []
var avatar_trials: Array = []
var avatar
var avatar_idle_joints := {}

func _motion_ride(index: int,title: String,hold_space := false) -> bool:
	var current: int=int(visit.snapshot().current_floor)
	if not await _pose(title+"_lift_call",visit.landing_point(current)):return false
	_e(true);_e(false);await _ticks(4)
	var opened: bool=visit.elevator_open
	var accepted: bool=opened and visit.request_floor(index)
	_check("roof_ride."+title+".real_E_picker_and_production_destination",accepted,{"opened":opened,"destination":index})
	if not accepted:return false
	_movement(["move_forward","jump"] if hold_space else [])
	await _wait_elevator_end();await _ticks(6)
	var arrived: bool=not visit.in_elevator and visit.on_roof and visit.selected_floor==index and scene.player.is_on_floor() and scene.rig.camera.current
	_check("roof_ride."+title+".actual_source_roof_arrival",arrived,{"visit":visit.snapshot(),"player":scene.player.global_position,"latched":scene.player.input_latched})
	return arrived

func _land(max_ticks := 600) -> bool:
	_movement()
	for index in range(max_ticks):
		if scene.player.is_on_floor() and absf(scene.player.velocity.y)<.01:return true
		await _ticks(1)
	return false

func _arrival_neutral(title: String) -> void:
	var roof: Node3D=visit.rooftop
	var arrival: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	_check("roof_input."+title+".Space_held_through_ride_never_auto_jumps",scene.player.is_on_floor() and scene.player.air_jump_count()==0 and absf(arrival.y-roof.lift_point().y)<.2,{"player":arrival,"lift_point":roof.lift_point(),"latched":scene.player.input_latched})
	_movement(["move_forward"]);await _ticks(3)
	var before: Vector3=scene.player.global_position
	_movement(["move_forward","jump"]);await _ticks(1)
	var after: Vector3=scene.player.global_position
	_check("roof_input."+title+".fresh_Space_works_even_when_W_remains_held",scene.player.velocity.y>7.0 and after.y>before.y+.08 and not scene.player.is_on_floor(),{"before":before,"after":after,"velocity":scene.player.velocity,"movement_latched":scene.player.input_latched})
	await _land();await _ticks(4)
	_check("roof_input."+title+".postarrival_jump_lands_without_recovery",scene.player.is_on_floor() and scene.player.recoveries==recoveries,{"position":scene.player.global_position,"recovery_delta":scene.player.recoveries-recoveries})

func _roof_chain(title: String) -> void:
	var roof: Node3D=visit.rooftop
	_movement();await _ticks(3)
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	var records:=[];var valid:=true;var max_y:=start.y;var max_xz_drift:=0.
	for edge in range(6):
		_movement(["jump"]);await _ticks(1)
		var expected: float=sqrt(2.*scene.player.gravity_mps2*scene.player.jump_height_m)-.5*scene.player.gravity_mps2*scene.player.step_delta
		var at: Vector3=scene.player.global_position
		var row:={"edge":edge+1,"position":at,"velocity_y":scene.player.velocity.y,"expected_impulse_after_gravity":expected,"air_jump_count":scene.player.air_jump_count(),"grounded":scene.player.is_on_floor()}
		records.append(row)
		if absf(scene.player.velocity.y-expected)>.03 or scene.player.is_on_floor():valid=false
		_movement()
		for tick in range(20):
			await _ticks(1)
			var point: Vector3=scene.player.global_position
			max_y=maxf(max_y,point.y)
			max_xz_drift=maxf(max_xz_drift,Vector2(point.x-start.x,point.z-start.z).length())
			var local: Vector3=roof.frame.affine_inverse()*point
			if not roof.walkable_rect.grow(-.30).has_point(Vector2(local.x,local.z)) or scene.player.recoveries!=recoveries:valid=false
	var count_after: int=scene.player.air_jump_count()
	var row:={"name":title,"profile":roof.profile_id,"source_id":visit.current_spec.id,"source_rectangle_center":visit.current_spec.rectangle_center,"roof_frame":roof.frame,"start":start,"six_press_records":records,"maximum_height_above_deck_m":max_y-roof.deck_height_y,"maximum_XZ_drift_m":max_xz_drift,"air_jump_count_after_six":count_after,"recoveries_before":recoveries,"recoveries_after":scene.player.recoveries,"method":"Six production Input.action_press/release edges, twenty real physics ticks between presses; no velocity or position assignment."}
	roof_trials.append(row)
	_check("roof_jump."+title+".six_fresh_presses_replace_impulse_beyond_old_ceiling",valid and count_after>=5 and max_y-roof.deck_height_y>10.0 and max_xz_drift<.01 and scene.player.has_unlimited_air_jumps() and scene.player.air_jumps_remaining()==-1,row)
	var landed: bool=await _land()
	_check("roof_jump."+title+".lands_on_same_source_roof_without_incorrect_recovery",landed and visit.on_roof and scene.player.recoveries==recoveries and absf(scene.player.global_position.y-start.y)<.15 and scene.player.air_jump_count()==0,{"position":scene.player.global_position,"start":start,"recovery_delta":scene.player.recoveries-recoveries})
	await _hold_single(title)

func _hold_single(title: String) -> void:
	_movement();await _ticks(3)
	var start: Vector3=scene.player.global_position
	var peak:=start.y;var episodes:=0;var prior_positive:=false;var grounded_samples:=0
	_movement(["jump"])
	for index in range(135):
		await _ticks(1)
		peak=maxf(peak,scene.player.global_position.y)
		var positive: bool=scene.player.velocity.y>.05
		if positive and not prior_positive:episodes+=1
		prior_positive=positive
		if scene.player.is_on_floor():grounded_samples+=1
	_check("roof_jump."+title+".holding_Space_produces_one_three_metre_jump",episodes==1 and absf(peak-start.y-3.)<.13 and grounded_samples>20 and scene.player.is_on_floor(),{"ascending_episodes":episodes,"rise_m":peak-start.y,"grounded_samples":grounded_samples,"ending_position":scene.player.global_position})
	_movement();await _ticks(4)

func _joints() -> Dictionary:
	var result:={}
	for title in ["LeftUpperArm","RightUpperArm","LeftForearm","RightForearm","LeftThigh","RightThigh","LeftShin","RightShin","LeftFoot","RightFoot"]:
		var node: Node3D=avatar.find_child(title,true,false)
		if is_instance_valid(node):result[title]={"rotation":node.rotation,"transform":node.transform,"world":node.global_transform}
	return result

func _avatar_geometry() -> void:
	var meshes:=0;var colliders:=0;var shoes:=0
	for node in _descendants(avatar):
		if node is MeshInstance3D and node.mesh!=null:meshes+=1
		if node is CollisionObject3D or node is CollisionShape3D:colliders+=1
		if node is MeshInstance3D and String(node.name) in ["LeftShoe","RightShoe"]:shoes+=1
	var joints:=_joints()
	_check("avatar.actual_articulated_human_has_limbs_and_shoes_without_new_colliders",meshes>=10 and joints.size()==10 and shoes==2 and colliders==0 and not scene.player.get_node("Visual/Body").visible,{"actual_meshes":meshes,"joint_names":joints.keys(),"shoes":shoes,"new_colliders":colliders,"snapshot":avatar.snapshot()})
	_check("avatar.original_physics_capsule_and_city_collision_retained",_player_shape()==player_shape_before and _inventory()==original_inventory)

func _gait_samples(kind: String,ticks: int,direction: Vector3) -> Dictionary:
	var samples:=[];var opposite:=0;var opposite_foreaft:=0;var moving:=0;var max_cadence:=0.;var min_sole:=INF;var max_sole:=-INF
	var previous: Vector3=scene.player.global_position
	# Bent knees have a nonzero IK rest angle. Observe swings relative to the
	# supported idle pose instead of incorrectly requiring opposite absolute X.
	var rest_angle: float=avatar_idle_joints.LeftThigh.rotation.x
	for index in range(ticks):
		_world_keys(direction)
		if kind=="run":Input.action_press("move_fast")
		await _ticks(1)
		var state: Dictionary=avatar.snapshot();var joints:=_joints()
		var delta: Vector3=scene.player.global_position-previous;previous=scene.player.global_position
		if Vector2(delta.x,delta.z).length()>.002:moving+=1
		var leg: float=joints.LeftThigh.rotation.x-rest_angle
		var opposite_leg: float=joints.RightThigh.rotation.x-rest_angle
		var arm: float=joints.LeftUpperArm.rotation.x+.04
		if absf(leg)>.02 and leg*opposite_leg<-.0001 and leg*arm<-.0001:opposite+=1
		var left_hand: Vector3=avatar.to_local((avatar.find_child("LeftHand",true,false) as MeshInstance3D).global_position)
		var right_hand: Vector3=avatar.to_local((avatar.find_child("RightHand",true,false) as MeshInstance3D).global_position)
		var left_foot: Vector3=avatar.to_local((avatar.find_child("LeftFoot",true,false) as Node3D).global_position)
		var right_foot: Vector3=avatar.to_local((avatar.find_child("RightFoot",true,false) as Node3D).global_position)
		# The actual hand and ankle fore/aft differences remove shared arm-bend
		# offsets and must oppose one another in the visible avatar's own frame.
		if absf(left_foot.z-right_foot.z)>.04 and (left_hand.z-right_hand.z)*(left_foot.z-right_foot.z)<-.002:opposite_foreaft+=1
		max_cadence=maxf(max_cadence,float(state.cadence_hz))
		for title in ["LeftShoe","RightShoe"]:
			var shoe: MeshInstance3D=avatar.find_child(title,true,false)
			var bounds: AABB=shoe.global_transform*shoe.get_aabb()
			var sole: float=bounds.position.y-scene.player.global_position.y
			min_sole=minf(min_sole,sole);max_sole=maxf(max_sole,sole)
		samples.append({"state":state,"joints":joints,"actual_hand_local":[left_hand,right_hand],"actual_foot_local":[left_foot,right_foot],"actual_displacement":delta})
	var result:={"name":kind,"samples":samples,"moving_samples":moving,"opposite_arm_leg_samples":opposite,"actual_opposed_hand_foot_foreaft_samples":opposite_foreaft,"maximum_cadence_hz":max_cadence,"minimum_shoe_sole_above_feet_m":min_sole,"maximum_shoe_sole_above_feet_m":max_sole}
	avatar_trials.append(result)
	_check("avatar."+kind+".actual_joint_swing_tracks_real_ground_motion",moving>ticks*.8 and opposite>ticks*.35 and max_cadence>0. and max_cadence<=2.21,result)
	_check("avatar."+kind+".actual_hands_oppose_same_side_feet_foreaft",opposite_foreaft>ticks*.55,{"actual_opposed_samples":opposite_foreaft,"samples":ticks,"method":"Visible hand MeshInstance3D and foot joint positions transformed into avatar-local coordinates, independent of the animation's phase counter."})
	_check("avatar."+kind+".actual_shoe_soles_stay_near_supported_ground",min_sole>-.12 and max_sole<.65,{"minimum_m":min_sole,"maximum_m":max_sole})
	return result

func _avatar_motion() -> void:
	var roof: Node3D=visit.rooftop
	_movement();await _ticks(45)
	var idle: Dictionary=avatar.snapshot();var idle_joints:=_joints();avatar_idle_joints=idle_joints.duplicate(true)
	await _ticks(18)
	_check("avatar.idle.no_walking_stride_while_stationary",avatar.snapshot().state=="idle" and avatar.snapshot().stride_phase==idle.stride_phase and _joints().LeftThigh.rotation.distance_to(idle_joints.LeftThigh.rotation)<.03,{"before":idle,"after":avatar.snapshot(),"joints":idle_joints})
	scene.set_speed_profile("brisk")
	_movement();await _ticks(6)
	await _gait_samples("walk",30,-roof.frame.basis.z)
	await _motion_capture("garden_human_walking")
	scene.set_speed_profile("turbo")
	_movement();await _ticks(6)
	await _gait_samples("run",12,-roof.frame.basis.z)
	await _motion_capture("garden_human_running")
	_movement();await _ticks(45)
	var position: Vector3=scene.player.global_position
	var barrier:=_blocker("EXP12ExplicitWallMotionFixture",position-roof.frame.basis.z*1.5)
	await _ticks(3)
	for index in range(35):_world_keys(-roof.frame.basis.z);Input.action_press("move_fast");await _ticks(1)
	var wall_before: Dictionary=avatar.snapshot();var wall_joints:=_joints();var at: Vector3=scene.player.global_position
	for index in range(18):_world_keys(-roof.frame.basis.z);Input.action_press("move_fast");await _ticks(1)
	var wall_after: Dictionary=avatar.snapshot()
	_check("avatar.wall.held_W_does_not_make_stationary_feet_walk",scene.player.global_position.distance_to(at)<.002 and wall_after.actual_speed_mps<.05 and wall_after.stride_phase==wall_before.stride_phase and _joints().LeftThigh.rotation.distance_to(idle_joints.LeftThigh.rotation)<.04,{"before":wall_before,"after":wall_after,"joints":wall_joints,"actual_position_delta":scene.player.global_position-at})
	_movement();barrier.queue_free();await _ticks(6)
	_movement(["jump"]);await _ticks(12)
	_check("avatar.air.actual_limb_pose_switches_from_ground_gait",avatar.snapshot().state=="air" and not scene.player.is_on_floor() and _joints().LeftThigh.transform!=idle_joints.LeftThigh.transform,{"snapshot":avatar.snapshot(),"joints":_joints()})
	await _motion_capture("garden_human_airborne")
	var before: Dictionary=avatar.snapshot();var joints_before:=_joints();var at_air: Vector3=scene.player.global_position;var velocity_before: float=scene.player.velocity.y
	scene.toggle_menu();await _ticks(18)
	_check("avatar.menu.pause_freezes_real_joints_clock_and_player",paused and avatar.snapshot().clock==before.clock and _joints()==joints_before and scene.player.global_position==at_air,{"before":before,"after":avatar.snapshot()})
	scene.toggle_menu();await _ticks(2)
	var vertical: float=scene.player.velocity.y
	_check("avatar.menu.Space_held_on_resume_cannot_relaunch",scene.player.input_latched and vertical<velocity_before-.10,{"snapshot":avatar.snapshot(),"velocity_before":velocity_before,"velocity_y":vertical})
	await _land();await _ticks(6)
	# Direct control-ownership fixture complements the separate production-E
	# facility suite; it never fabricates a real facility session here.
	scene.player.set_facility_control(true);_movement(["move_forward","jump"])
	var locked_at: Vector3=scene.player.global_position
	await _ticks(18);var facility: Dictionary=avatar.snapshot();var frozen_joints:=_joints()
	await _ticks(12)
	_check("avatar.facility.external_control_fixture_keeps_pose_and_clock_neutral",facility.state=="facility" and avatar.snapshot().clock==facility.clock and _joints()==frozen_joints and scene.player.global_position==locked_at and scene.player.air_jump_count()==0,{"state":avatar.snapshot(),"method":"Explicit player facility-control ownership fixture; production facility sessions are checked separately."})
	scene.player.set_facility_control(false);await _ticks(4)
	_check("avatar.facility.held_Space_cannot_auto_takeoff_on_release",scene.player.is_on_floor() and scene.player.input_latched)
	_movement();await _ticks(6)
	_check("avatar.facility.neutral_release_restores_normal_control",not scene.player.facility_control and not scene.player.input_latched)

func _motion_capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":deferred_checks.append({"name":"capture."+title,"reason":"headless_has_no_rendered_viewport"});return
	# Camera only: the current physics position and visible avatar are retained.
	var roof: Node3D=visit.rooftop
	scene.rig.yaw=atan2(roof.frame.basis.z.x,roof.frame.basis.z.z)+deg_to_rad(28.)
	scene.rig.pitch=deg_to_rad(-12.);scene.rig.requested_distance=3.6;scene.rig.snap_to_target_pose()
	await _ticks(4)
	await process_frame;RenderingServer.force_draw(false,0.)
	var image: Image=scene.get_viewport().get_texture().get_image();var path:=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not image.is_empty() and image.save_png(path)==OK
	var evidence:={"name":title,"captured":saved,"path":path,"width":image.get_width(),"height":image.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"actual_camera_distance_m":scene.rig.camera.global_position.distance_to(scene.rig.global_position),"avatar":avatar.snapshot(),"actual_joints":_joints()}
	captures.append(evidence)
	_check("capture."+title,saved and _camera_clear() and scene.player.get_node("Visual").is_visible_in_tree(),evidence)

func _run() -> void:
	for path in ["res://scripts/explore_walk.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/free_roam_player.gd","res://scripts/interior_visit.gd","res://scripts/rooftop_space.gd","res://scripts/facility_interaction.gd","res://scripts/facility_activity_visuals.gd","res://scripts/interior_facility_kit.gd","res://../tests/game/check_building_visits.gd","res://../tests/game/check_facility_interactions.gd","res://../tests/game/check_exploration_motion.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;activity=visit.facility_interaction;avatar=scene.exploration_avatar;await _ticks(25)
	var ready: bool=is_instance_valid(avatar) and avatar.has_method("snapshot") and scene.player.has_method("has_unlimited_air_jumps") and scene.player.has_method("air_jump_count")
	_check("startup.current_roof_unlimited_jump_and_human_avatar_API",ready)
	if not ready:_finish();return
	original_inventory=_inventory();player_shape_before=_player_shape();_avatar_geometry()
	for id in ROOF_IDS:
		if not await _enter(id,"motion_"+id):continue
		var roof_title:=String(visit.rooftop.profile_id)
		if await _motion_ride(visit.room.floor_count,roof_title,true):
			await _arrival_neutral(roof_title)
			await _roof_chain(roof_title)
			if id==LIBRARY_ID:await _avatar_motion()
			await _motion_capture(roof_title+"_human_roof")
		_movement();_e(false);visit.return_to_world_spawn();await _ticks(10)
	_check("regression.motion_preserves_original_city_shapes_and_player_capsule",_inventory()==original_inventory and _player_shape()==player_shape_before,{"source_body_count":original_inventory.size(),"shape":_player_shape()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var result:={"task":"exploration_motion","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"summary":{"checks":checks.size(),"failed":failed},"source_sha256":source_hashes,"checks":checks,"roof_trials":roof_trials,"avatar_trials":avatar_trials,"scenario_starts":placements,"captures":captures,"deferred_checks":deferred_checks,"scope":"Representative real production-E/lift arrivals on garden/pool/penthouse source-world roofs. Space edges drive the actual player, including held-input arrival, six fresh presses above the former nine-metre region ceiling, landing and hold/menu gates. Articulated limb/shoe meshes and joints are observed independently during actual physical displacement, wall blocking, air and paused/facility ownership. Scenario-start teleports and wall/control fixtures are explicit. Native normal-camera PNGs only outside headless. Original city collision and player capsule retained. No all-angle camera, measured human gait, full catalogue roof activity, performance, fluid simulation or human OS input acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save exploration motion report")
	print("EXPLORATION_MOTION_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

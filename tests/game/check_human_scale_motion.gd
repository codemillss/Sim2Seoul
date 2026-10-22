extends "res://../tests/game/check_stable_motion.gd"
## A metre fixture with production human/controller/camera and actual car art.
## Keys below are engine Input actions, not claims about physical OS keyboard use.
var measurements: Dictionary={}
var motion_trials: Array=[]
var captures: Array=[]
var review_camera: Camera3D
var car_art: Node3D
var car_builder: Node3D
var door: StaticBody3D

func _full_ticks(count: int) -> void:
	for index in range(count):await physics_frame;await process_frame

func _block_mesh(parent: Node3D,title: String,size: Vector3,at: Vector3,color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=at
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.85;node.material_override=mat;parent.add_child(node);return node

func _bounds(node: Node3D) -> AABB:
	var result:=AABB();var ready:=false
	var pending: Array[Node]=[node]
	while not pending.is_empty():
		var current: Node=pending.pop_back()
		if current is MeshInstance3D and current.visible and current.mesh!=null:
			var box: AABB=current.global_transform*current.get_aabb();result=box if not ready else result.merge(box);ready=true
		for child: Node in current.get_children():pending.append(child)
	return result

func _metric_scene() -> void:
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.70,.76,.79);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.65;environment.environment=env;fixture.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-28,0);sun.light_energy=1.2;sun.shadow_enabled=true;fixture.add_child(sun)
	_block_mesh(fixture,"VisibleMetreFloor",Vector3(100,.02,100),Vector3(0,-.015,0),Color(.38,.43,.44))
	for index in range(-8,9):
		_block_mesh(fixture,"OneMetreGrid",Vector3(.012,.003,16),Vector3(index,.002,0),Color(.65,.70,.69))
		_block_mesh(fixture,"OneMetreGrid",Vector3(16,.003,.012),Vector3(0,.002,index),Color(.65,.70,.69))
	var metre:=Node3D.new();metre.name="TwoMetreRuler";fixture.add_child(metre);metre.position=Vector3(-.85,0,0)
	_block_mesh(metre,"TwoMetrePost",Vector3(.025,2.,.025),Vector3(0,1.,0),Color(.95,.84,.22))
	for tick in range(21):_block_mesh(metre,"TenCentimetreTick",Vector3(.20 if tick%5==0 else .10,.012,.02),Vector3(.07,float(tick)/10.,0),Color(.96,.91,.69))
	var label:=Label3D.new();label.text="2.00 m\n0.10 m 눈금";label.font_size=32;label.pixel_size=.003;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=Vector3(0,2.20,0);label.modulate=Color(.98,.95,.78);metre.add_child(label)
	# This doorway has the original P01 dimensions, but is an explicit fixture.
	door=StaticBody3D.new();door.name="OnePointTwoByTwoPointTwoDoor";door.collision_layer=1;door.collision_mask=2;fixture.add_child(door);door.position=Vector3(0,0,-3.)
	for spec: Array in [[Vector3(.20,2.4,.25),Vector3(-.70,1.2,0)],[Vector3(.20,2.4,.25),Vector3(.70,1.2,0)],[Vector3(1.6,.20,.25),Vector3(0,2.30,0)]]:
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=spec[0];shape.shape=box;shape.position=spec[1];door.add_child(shape);_block_mesh(door,"DoorFrame",spec[0],spec[1],Color(.74,.71,.62))
	var door_label:=Label3D.new();door_label.text="빈 폭 1.20 m · 높이 2.20 m";door_label.font_size=27;door_label.pixel_size=.003;door_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;door_label.position=Vector3(0,2.65,0);door.add_child(door_label)
	car_art=Node3D.new();car_art.name="ActualProductionCarGeometry";fixture.add_child(car_art);car_art.position=Vector3(3.2,0,-.2);car_art.rotation.y=PI*.5
	car_builder=load("res://scripts/drivable_car_service.gd").new();fixture.add_child(car_builder)
	var row:={"wheels":[],"front":null,"crank":null,"kickstand":null};car_builder._build_bike(row,car_art)
	row.kickstand.visible=false
	review_camera=Camera3D.new();review_camera.name="IndependentMetreReviewCamera";review_camera.fov=48.;review_camera.near=.05;fixture.add_child(review_camera)

func _model_metrics() -> void:
	var geometry: AABB=_bounds(avatar);var capsule:=_capsule();var head: MeshInstance3D=avatar.find_child("Head",true,false)
	var head_box: AABB=head.global_transform*head.get_aabb();var car_box:=_bounds(car_art)
	measurements={"render_min_world_m":_json(geometry.position),"render_max_world_m":_json(geometry.end),"render_size_m":_json(geometry.size),"head_render_height_m":head_box.size.y,"render_head_units":geometry.size.y/head_box.size.y,"hip_joint_y_m":_joint("LeftThigh").position.y,"shoulder_joint_y_m":_joint("LeftUpperArm").position.y,"capsule":capsule,"car_render_size_m":_json(car_box.size),"car_safety_box_m":[2.20,1.65,4.50],"door_clear_opening_m":[1.20,2.20],"scope":"Actual production mesh bounds and retained controller in a 1m grid fixture; authored adult character, not an anthropometric scan or proof of all city geometry."}
	_check("render.actual_shoes_to_hair_height_is_1_70m_with_sole_contact",absf(geometry.end.y-player.global_position.y-1.70)<.005 and geometry.position.y-player.global_position.y>=-.004 and geometry.position.y-player.global_position.y<.015,measurements)
	_check("render.actual_head_and_total_mesh_have_adult_seven_to_eight_head_proportion",head_box.size.y>.225 and head_box.size.y<.235 and geometry.size.y/head_box.size.y>7.2 and geometry.size.y/head_box.size.y<7.6,measurements)
	_check("render.arms_legs_and_shoes_fit_retained_body_width",geometry.size.x<=.61 and geometry.size.z<.47 and _joint("LeftUpperArm").position.y>1.33 and _joint("LeftThigh").position.y>.85,measurements)
	_check("physics.original_1_70m_capsule_radius_0_30_and_identity_retained",capsule==initial_capsule and is_equal_approx(float(capsule.height),1.70) and is_equal_approx(float(capsule.radius),.30),measurements)
	_check("render.actual_car_model_remains_metres_in_relation_to_human",car_box.size.y>1.45 and car_box.size.y<1.7 and car_box.size.x>4.3 and car_box.size.x<4.6,measurements)

func _physics_foot(side: String) -> Vector3:
	return avatar.global_transform*_joint(side+"Thigh").transform*_joint(side+"Shin").transform*_joint(side+"Foot").transform.origin

func _ground_run(kind: String,speed: float,fast: bool,count:=180) -> void:
	await _place(Vector3(-30,.08,-30));player.walk_speed_mps=speed;player.run_speed_mps=speed
	var start: Vector3=player.global_position;var rows: Array=[];var maximum_stance_slip:=0.;var stance_samples:=0;var previous_feet:={};var previous_phases:={};var maximum_cadence:=0.;var minimum_sole:=INF;var maximum_sole:=-INF;var maximum_bob:=0.;var maximum_roll:=0.
	_keys(["move_forward","move_fast"] if fast else ["move_forward"])
	for tick in range(count):
		await _full_ticks(1);var sample: Dictionary=avatar.snapshot();maximum_cadence=maxf(maximum_cadence,sample.cadence_hz)
		maximum_bob=maxf(maximum_bob,absf(_joint("UpperBody").position.y-.85));maximum_roll=maxf(maximum_roll,absf(_joint("UpperBody").rotation.z))
		var feet:={}
		for side: String in ["Left","Right"]:
			var foot:=_physics_foot(side);feet[side]=foot
			var fraction:=fposmod(float(sample.stride_phase)/TAU+(.5 if side=="Right" else 0.),1.0)
			if tick>35 and fraction>.02 and fraction<float(sample.stance_fraction)-.02 and previous_phases.has(side) and fraction>float(previous_phases[side]) and float(previous_phases[side])>.02:
				var slip:=Vector2(foot.x-previous_feet[side].x,foot.z-previous_feet[side].z).length()*Engine.physics_ticks_per_second;maximum_stance_slip=maxf(maximum_stance_slip,slip);stance_samples+=1
			previous_phases[side]=fraction;previous_feet[side]=foot
			minimum_sole=minf(minimum_sole,foot.y-player.global_position.y-.1145);maximum_sole=maxf(maximum_sole,foot.y-player.global_position.y-.1145)
		rows.append({"tick":tick,"position":player.global_position,"velocity":player.velocity,"feet_physics":feet,"avatar_state":sample.state,"cadence_hz":sample.cadence_hz,"run_weight":sample.run_weight,"represented_gait_speed_mps":sample.represented_gait_speed_mps,"phase":sample.stride_phase})
	var record:={"kind":kind,"actual_travel_m":player.global_position.distance_to(start),"configured_speed_mps":speed,"actual_speed_mps":Vector2(player.velocity.x,player.velocity.z).length(),"stance_samples":stance_samples,"maximum_world_stance_foot_slip_mps":maximum_stance_slip,"maximum_cadence_hz":maximum_cadence,"sole_range_m":[minimum_sole,maximum_sole],"maximum_torso_bob_m":maximum_bob,"maximum_torso_roll_radians":maximum_roll,"final_avatar":avatar.snapshot(),"samples":rows}
	motion_trials.append(record)
	_check(kind+".real_controller_reaches_existing_speed_without_profile_reduction",absf(Vector2(player.velocity.x,player.velocity.z).length()-speed)<.015 and player.global_position.distance_to(start)>speed*float(count)/60.-speed*.25,record)
	_check(kind+".torso_and_camera_anchor_have_no_added_bob_or_roll",maximum_bob<.00001 and maximum_roll<.00001 and maximum_cadence<=2.21,record)
	if speed<4.:
		_check(kind+".actual_stance_ankles_remain_planted_in_world",stance_samples>40 and maximum_stance_slip<.025 and minimum_sole>-.012 and maximum_sole<.26,record)
	else:_check(kind+".arcade_speed_excess_is_explicit_and_cadence_stays_bounded",float(avatar.snapshot().arcade_speed_excess_mps)>15. and maximum_cadence<=2.21,record)
	await _photo(kind,Vector3(1.8,1.5,-3.5))
	_keys([]);await _full_ticks(18)

func _acceleration_and_turn() -> void:
	await _place(Vector3(0,.08,4));player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	var start: Vector3=player.global_position;var speeds: Array=[];_keys(["move_forward"])
	for tick in range(15):await _full_ticks(1);speeds.append(Vector2(player.velocity.x,player.velocity.z).length())
	_check("controller.grounded_start_accelerates_instead_of_one_frame_speed_snap",float(speeds[0])>0. and float(speeds[0])<1.0 and absf(float(speeds.back())-1.4)<.01,{"speeds_mps":speeds,"design":player.locomotion_snapshot()})
	var brake: Array=[];_keys([])
	for tick in range(12):await _full_ticks(1);brake.append(Vector2(player.velocity.x,player.velocity.z).length())
	_check("controller.grounded_release_brakes_to_complete_rest",float(brake[0])>0. and float(brake[0])<1.4 and float(brake.back())<.015,{"speeds_mps":brake,"remaining_drift_m":player.global_position.distance_to(start)})
	_keys(["move_backward"]);var turns: Array=[];var prior: float=player.visual.rotation.y;var maximum_step:=0.
	for tick in range(50):
		await _full_ticks(1);var amount:=absf(angle_difference(prior,player.visual.rotation.y));maximum_step=maxf(maximum_step,amount);turns.append({"yaw":player.visual.rotation.y,"step":amount,"turn_speed":player.locomotion_snapshot().visual_turn_speed_radians_s});prior=player.visual.rotation.y
	_check("controller.body_reversal_has_bounded_angular_acceleration",float(turns[0].step)<.035 and maximum_step<=TAU/60.+.001 and absf(angle_difference(player.visual.rotation.y,PI))<.01,{"samples":turns,"maximum_step_radians":maximum_step})
	_keys([]);await _full_ticks(18)

func _door_walk() -> void:
	await _place(Vector3(0,.08,-1.0));player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	var before: int=player.recoveries;_keys(["move_forward"]);await _full_ticks(180);_keys([]);await _full_ticks(12)
	_check("door.retained_full_capsule_actually_walks_through_1_20_by_2_20m_opening",player.global_position.z<-4.6 and player.is_on_floor() and player.recoveries==before and _capsule()==initial_capsule,{"actual_end":player.global_position,"door_frame":door.global_transform,"capsule":_capsule()})

func _actions_and_jump() -> void:
	await _place(Vector3(-10,.08,-10));var prior:=_joint("RightUpperArm").transform;avatar.play_sandbox_action("punch",.36);await _full_ticks(7)
	_check("actions.existing_non_graphic_punch_still_moves_articulated_arm",_joint("RightUpperArm").transform!=prior)
	await _full_ticks(30);avatar.play_sandbox_action("flinch",.5);await _full_ticks(9)
	_check("actions.existing_flinch_overlay_remains_visible",_joint("UpperBody").rotation.x>.1)
	await _full_ticks(30);var baseline: float=player.global_position.y;var peak:=baseline;var episodes:=0;var was_up:=false;_keys(["jump"])
	for tick in range(145):
		await _full_ticks(1);peak=maxf(peak,player.global_position.y);var up: bool=player.velocity.y>.05
		if up and not was_up:episodes+=1
		was_up=up
		if tick==15:await _photo("jump",Vector3(1.8,1.4,-3.5))
	_keys([]);await _full_ticks(6)
	_check("jump.retained_three_metre_jump_held_key_lands_once",absf(peak-baseline-3.)<.12 and episodes==1 and player.is_on_floor() and player.has_unlimited_air_jumps(),{"apex_m":peak-baseline,"ascending_episodes":episodes,"snapshot":avatar.snapshot()})
	player.set_facility_control(true);avatar.set_activity("weights",.8);await _full_ticks(3);var at: Vector3=player.global_position;var activity: Dictionary=avatar.snapshot();_keys(["move_forward","jump"]);await _full_ticks(8)
	_check("facility.activity_ownership_and_visible_hands_are_preserved",player.global_position==at and activity.state=="facility" and activity.activity_kind=="weights" and not activity.avatar_hands_visible,{"activity":activity})
	var maximum_grip_error:=0.;var grip_rows: Array=[]
	for elapsed: float in [0.,.25,.50,.75,1.0,1.5]:
		avatar.set_activity("weights",elapsed);await _full_ticks(1)
		var curl:=(1.-cos(elapsed*TAU/2.0))*.5
		for side: String in ["Left","Right"]:
			var hand: MeshInstance3D=avatar._hands[0 if side=="Left" else 1]
			var actual: Vector3=_joint(side+"UpperArm").transform*_joint(side+"Forearm").transform*hand.position
			var target:=Vector3((-.43 if side=="Left" else .43),.76+curl*.60,-.12-curl*.14)
			var error:=actual.distance_to(target);maximum_grip_error=maxf(maximum_grip_error,error);grip_rows.append({"actual_local":actual,"target_local":target,"error_m":error})
	_check("facility.adult_arm_lengths_still_reach_existing_dumbbell_contacts",maximum_grip_error<.025,{"maximum_hand_contact_error_m":maximum_grip_error,"samples":grip_rows,"scope":"Component-pose fixture using unchanged game dumbbell target coordinates; production E/facility session acceptance remains separate."})
	avatar.set_activity("",0.);player.set_facility_control(false);await _full_ticks(5)
	_check("facility.release_keeps_old_held_movement_and_jump_neutral",player.global_position.distance_to(at)<.002 and player.input_latched and player.is_on_floor())
	_keys([]);await _full_ticks(5);var frozen:=_joint("LeftThigh").transform;var clock: float=avatar.clock;paused=true;await _full_ticks(8)
	_check("menu.actual_pose_clock_and_controller_freeze",_joint("LeftThigh").transform==frozen and avatar.clock==clock and player.global_position.distance_to(at)<.002)
	paused=false;await _full_ticks(2)

func _boundary_guard() -> void:
	player.free_roam_bounds=Rect2(-10,-10,20,20);await _place(Vector3(9.2,.08,0));player.walk_speed_mps=1.4;player.run_speed_mps=21.
	var prior: int=player.boundary_stops;var outside:=0;var furthest:=player.global_position.x;_keys(["move_right","move_fast"])
	for tick in range(45):
		await _full_ticks(1);furthest=maxf(furthest,player.global_position.x)
		if not player._inside(player.global_position):outside+=1
	_check("boundary.smoothed_momentum_cannot_bypass_original_edge_refusal",outside==0 and furthest<=9.6001 and player.boundary_stops>prior and Vector2(player.velocity.x,player.velocity.z).length()<.015,{"outside_samples":outside,"furthest_x_m":furthest,"boundary_refusals":player.boundary_stops-prior,"motion_guard":player.locomotion_snapshot()})
	_keys([]);await _full_ticks(12);player.free_roam_bounds=Rect2(-250,-250,500,500)

func _photo(title: String,offset: Vector3) -> void:
	if DisplayServer.get_name()=="headless":return
	var saved_current: bool=rig.camera.current;rig.camera.current=false;review_camera.current=true
	review_camera.global_position=player.global_position+offset;review_camera.look_at(player.global_position+Vector3.UP*.95)
	await process_frame;await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+title+".png";var image:=root.get_texture().get_image();var code:=image.save_png(path)
	_check("native.actual_"+title+"_metre_fixture_image",code==OK and not image.is_empty(),{"file":path,"camera":review_camera.global_transform})
	if code==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":review_camera.global_transform,"player":player.global_position,"scope":"Actual native rendered production human in explicit metre fixture, camera-only view. Visual review remains separate from numeric checks."})
	review_camera.current=false;rig.camera.current=saved_current

func _run() -> void:
	for path: String in ["res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/exploration_camera.gd","res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/drivable_car_service.gd","res://scenes/player/player.tscn","res://../tests/game/check_human_scale_motion.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_jump.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();_metric_scene();await _full_ticks(15);await _place(Vector3(0,.08,0));_model_metrics();await _photo("front_car_door_ruler",Vector3(4.8,2.4,-8.2));await _photo("human_front",Vector3(.4,1.45,-3.5));await _photo("human_profile",Vector3(-3.2,1.45,.3))
	await _acceleration_and_turn();await _door_walk();await _ground_run("walk_1_4mps",1.4,false);await _ground_run("run_3_5mps",3.5,true);await _ground_run("turbo_21mps",21.,true,90);await _actions_and_jump();await _boundary_guard()
	_check("physics.retained_original_shape_identity_and_no_new_avatar_collision",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty(),{"capsule":_capsule()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_keys([]);var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write human motion report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP28_HUMAN_SCALE_MOTION","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"measurements":measurements,"motion_trials":motion_trials,"captures":captures,"source_sha256":source_hashes,"scope":"Production human/controller/camera/car art in explicit metre fixture. Authored adult proportions and physical engine movement; not motion capture, a GTA asset, OS keyboard, all-world surveyed scale, performance or subjective comfort acceptance. Turbo speed remains intentional sandbox motion."}),"  ")+"\n");file.close();print("HUMAN_SCALE_MOTION_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)

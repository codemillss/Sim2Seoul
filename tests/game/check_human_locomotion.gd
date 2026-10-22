extends "res://../tests/game/check_jump.gd"
## EXP29: actual production move_and_slide with digital Input actions. The
## independent planar/slope fixtures do not prove city routes or OS key input.
var motion_records: Array=[]
var initial_shape: Dictionary={}
var profile_results: Dictionary={}
var controller_path:="res://scripts/player/free_roam_player.gd"

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result:={}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("HUMAN_LOCOMOTION_FAIL "+title)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--player-script="):controller_path=argument.trim_prefix("--player-script=")
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("Absolute --report is required");quit(2);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	create_timer(110.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _build() -> void:
	# The same fixture can also load the preserved pre-change source as a
	# controlled baseline without ever replacing the live production file.
	fixture=Node3D.new();fixture.name="HumanLocomotionFixture"
	var world:=FixtureWorld.new();world.name="World";fixture.add_child(world)
	router=Node.new();router.name="InputRouter";router.set_script(ROUTER_SCRIPT);fixture.add_child(router)
	var camera:=Camera3D.new();camera.name="Camera";fixture.add_child(camera)
	player=CharacterBody3D.new();player.name="Player";player.set_script(load(controller_path))
	player.world_path=NodePath("../World");player.input_router_path=NodePath("../InputRouter");player.camera_path=NodePath("../Camera")
	player.free_roam_bounds=Rect2(-10,-10,20,20);player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	player.collision_layer=2;player.collision_mask=1;player.safe_margin=.001;player.floor_snap_length=.1
	var collision:=CollisionShape3D.new();collision.name="CollisionShape";var capsule:=CapsuleShape3D.new();capsule.height=1.7;capsule.radius=.3;collision.shape=capsule;collision.position.y=.85;player.add_child(collision)
	var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);fixture.add_child(player);root.add_child(fixture)
	_solid("Floor",Vector3(24,.2,24),Vector3(0,-.1,0))
	var regions: Array[Rect2]=[Rect2(-10,-10,20,20)];player.configure_recovery(Vector3(0,.08,0),regions);player.position=Vector3(0,.08,0);player.require_neutral_input()

func _shape_snapshot() -> Dictionary:
	var node: CollisionShape3D=player.get_node("CollisionShape")
	return {"node":node.get_instance_id(),"shape":node.shape.get_instance_id(),"height":node.shape.height,"radius":node.shape.radius,"disabled":node.disabled,"layer":player.collision_layer,"mask":player.collision_mask,"local_origin":node.position}

func _place(point:=Vector3(0,.08,0),yaw:=0.) -> void:
	_keys([]);player.global_transform=Transform3D(Basis.IDENTITY,point);player.velocity=Vector3.ZERO
	player.visual.rotation=Vector3(0.,yaw,0.);player.require_neutral_input();player.reset_physics_interpolation()
	await _ticks(8)
	_check("placement.supported_neutral_"+str(checks.size()),player.is_on_floor() and not player.input_latched,{"position":player.global_position})

func _observe(label: String,actions: Array,seconds: float) -> Dictionary:
	_keys(actions)
	var rows: Array=[];var prior: Vector3=player.global_position;var previous_yaw: float=player.visual.rotation.y
	for tick in range(int(round(seconds*Engine.physics_ticks_per_second))):
		await player.physics_stepped
		var displacement: Vector3=player.global_position-prior
		var velocity: Vector3=Vector3(player.velocity.x,0.,player.velocity.z)
		var forward:=Vector3(-sin(player.visual.rotation.y),0.,-cos(player.visual.rotation.y))
		var actual:=Vector3(displacement.x,0.,displacement.z)
		rows.append({"tick":tick,"time_s":float(tick+1)/Engine.physics_ticks_per_second,"position":player.global_position,"velocity":velocity,"speed_mps":velocity.length(),"achieved_mps":actual.length()*Engine.physics_ticks_per_second,"visual_yaw":player.visual.rotation.y,"yaw_step_radians":angle_difference(previous_yaw,player.visual.rotation.y),"direction_alignment":forward.dot(actual.normalized()) if actual.length()>.0001 else 1.,"state":player.locomotion_snapshot().get("state","baseline"),"grounded":player.is_on_floor(),"snapshot":player.locomotion_snapshot()})
		prior=player.global_position;previous_yaw=player.visual.rotation.y
	var row:={"name":label,"physics_hz":Engine.physics_ticks_per_second,"actions":actions,"seconds":seconds,"samples":rows}
	motion_records.append(row)
	return row

func _onset_brake(hz: int,speed: float,fast: bool) -> Dictionary:
	await _place();player.walk_speed_mps=1.4 if fast else speed;player.run_speed_mps=speed if fast else 3.5
	var tag:=str(hz)+"hz_"+str(speed)+"mps"
	var row:=await _observe(tag+"_start",["move_forward","move_fast"] if fast else ["move_forward"],1.)
	var onset: Array=row.samples;var monotonic:=true;var reached:=INF;var previous:=0.
	for sample: Dictionary in onset:
		var actual: float=sample.speed_mps
		if actual<previous-.00001 or actual>speed+.001:monotonic=false
		if actual>=speed*.99 and not is_finite(reached):reached=sample.time_s
		previous=actual
	_check(tag+".progressive_nonoscillating_acceleration",monotonic and float(onset[0].speed_mps)>0. and float(onset[0].speed_mps)<speed*.25 and absf(previous-speed)<.002,{"reach_99_percent_s":reached,"samples":onset})
	_check(tag+".profile_not_reduced_and_reasonable_start_time",reached>.18 and reached<.58,{"reach_99_percent_s":reached,"speed_limit_mps":speed})
	row=await _observe(tag+"_release",[],.65)
	var stopping: Array=row.samples;var stopped:=INF;monotonic=true;previous=speed;var maximum_tail_drift:=0.;var zero_position:=Vector3.INF
	for sample: Dictionary in stopping:
		var actual: float=sample.speed_mps
		if actual>previous+.00001:monotonic=false
		if actual<.001 and not is_finite(stopped):stopped=sample.time_s;zero_position=sample.position
		if zero_position.is_finite():maximum_tail_drift=maxf(maximum_tail_drift,Vector2(zero_position.x,zero_position.z).distance_to(Vector2(sample.position.x,sample.position.z)))
		previous=actual
	_check(tag+".release_brakes_monotonically_to_exact_rest",monotonic and float(stopping[0].speed_mps)>0. and previous==0. and stopped<.48,{"stop_time_s":stopped,"samples":stopping})
	_check(tag+".no_idle_drift_after_stop",maximum_tail_drift<.00001,{"tail_drift_m":maximum_tail_drift})
	return {"reach_99_percent_s":reached,"stop_time_s":stopped,"tail_drift_m":maximum_tail_drift}

func _turns(hz: int,fast: bool) -> void:
	var speed:=3.5 if fast else 1.4;player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	var tag:=str(hz)+"hz_"+("run" if fast else "walk")
	for degrees: int in [90,180]:
		await _place();await _observe(tag+"_before_turn_"+str(degrees),["move_forward","move_fast"] if fast else ["move_forward"],.8)
		var action:="move_right" if degrees==90 else "move_backward"
		var row:=await _observe(tag+"_turn_"+str(degrees),[action,"move_fast"] if fast else [action],1.8)
		var samples: Array=row.samples;var minimum_alignment:=1.;var maximum_yaw_step:=0.;var yaw_reversals:=0;var previous_sign:=0.;var reverse_brake:=0;var pivot:=0;var minimum_speed:=INF
		for sample: Dictionary in samples:
			if float(sample.achieved_mps)>.10:minimum_alignment=minf(minimum_alignment,sample.direction_alignment)
			var step: float=sample.yaw_step_radians;maximum_yaw_step=maxf(maximum_yaw_step,absf(step))
			if absf(step)>.001:
				if previous_sign!=0. and signf(step)!=previous_sign:yaw_reversals+=1
				previous_sign=signf(step)
			if sample.state=="reversal_brake":reverse_brake+=1
			if sample.state=="pivot":pivot+=1
			minimum_speed=minf(minimum_speed,sample.speed_mps)
		var target_yaw:=-PI*.5 if degrees==90 else PI
		var tail: Dictionary=samples.back()
		_check(tag+".turn_"+str(degrees)+"_physical_course_follows_visible_facing",minimum_alignment>.995,{"minimum_alignment":minimum_alignment,"samples":samples})
		_check(tag+".turn_"+str(degrees)+"_bounded_yaw_without_oscillation",maximum_yaw_step<=TAU/float(hz)+.0001 and yaw_reversals==0 and absf(angle_difference(float(tail.visual_yaw),target_yaw))<.005,{"maximum_yaw_step":maximum_yaw_step,"yaw_reversals":yaw_reversals,"ending_heading":tail.visual_yaw})
		_check(tag+".turn_"+str(degrees)+"_returns_to_configured_speed",absf(float(tail.speed_mps)-speed)<.005,{"ending_speed_mps":tail.speed_mps})
		if degrees==180:_check(tag+".reversal_brakes_before_pivot_instead_of_backwards_sliding",reverse_brake>0 and pivot>0 and minimum_speed<.001,{"brake_samples":reverse_brake,"pivot_samples":pivot,"minimum_speed":minimum_speed})

func _safety(hz: int) -> void:
	player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	await _place();await _observe(str(hz)+"hz_before_menu",["move_forward","move_fast"],.7)
	router.gameplay_enabled=false;player.require_neutral_input();var at: Vector3=player.global_position
	var row:=await _observe(str(hz)+"hz_router_blocked",["move_forward","move_fast"],.3)
	_check(str(hz)+"hz.menu_blocks_old_momentum_and_held_input",Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<.0001 and player.input_latched and Vector2(player.velocity.x,player.velocity.z).length()<.01,{"samples":row.samples,"floor_settlement_y_m":player.global_position.y-at.y})
	router.gameplay_enabled=true;await _ticks(3)
	_check(str(hz)+"hz.menu_resume_stays_neutral_until_release",player.input_latched and Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<.0001)
	_keys([]);await _ticks(3);player.set_facility_control(true);at=player.global_position
	await _observe(str(hz)+"hz_facility_owned",["move_forward","jump"],.2)
	_check(str(hz)+"hz.facility_keeps_capsule_and_pose_frozen",player.global_position==at and player.velocity==Vector3.ZERO and _shape_snapshot()==initial_shape)
	player.set_facility_control(false);await _ticks(3)
	_check(str(hz)+"hz.facility_release_neutralizes_held_keys",player.input_latched and Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<.0001)
	_keys([]);await _ticks(3)
	await _place();var wall:=_solid("NativeWall",Vector3(10.,3.,.30),Vector3(0.,1.5,-2.));await _ticks(2)
	await _observe(str(hz)+"hz_native_wall",["move_forward","move_fast"],1.4)
	_check(str(hz)+"hz.native_wall_still_blocks_complete_unchanged_capsule",player.global_position.z>=-1.551 and player.global_position.z<-1.4 and player.get_slide_collision_count()>0 and _shape_snapshot()==initial_shape,{"ending_position":player.global_position,"collisions":player.get_slide_collision_count()})
	_keys([]);wall.free();await _ticks(2)
	player.free_roam_bounds=Rect2(-10,-10,20,20);await _place(Vector3(9.1,.08,0),-PI*.5);player.run_speed_mps=21.
	var before: int=player.boundary_stops;row=await _observe(str(hz)+"hz_turbo_boundary",["move_right","move_fast"],.8)
	var outside:=0
	for sample: Dictionary in row.samples:
		if not player._inside(sample.position):outside+=1
	_check(str(hz)+"hz.turbo_curved_momentum_never_crosses_area_guard",outside==0 and player.global_position.x<=9.6001 and player.boundary_stops>before and Vector2(player.velocity.x,player.velocity.z).length()==0.,{"outside_samples":outside,"samples":row.samples})
	_keys([]);player.free_roam_bounds=Rect2(-250,-250,500,500);await _ticks(2)

func _slope(hz: int) -> void:
	await _place(Vector3(15.,.08,0));player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	var ramp:=_solid("WalkableNativeSlope",Vector3(4.,.25,6.),Vector3(15.,.59,-4.));ramp.rotation.x=deg_to_rad(12.)
	await _ticks(3);var recovery_before: int=player.recoveries
	var row:=await _observe(str(hz)+"hz_native_slope",["move_forward"],3.8)
	var maximum_y:=0.;var grounded:=0
	for sample: Dictionary in row.samples:
		maximum_y=maxf(maximum_y,sample.position.y)
		if sample.grounded:grounded+=1
	_check(str(hz)+"hz.walkable_slope_uses_actual_native_floor_without_recovery",maximum_y>.70 and grounded>row.samples.size()*.90 and player.recoveries==recovery_before,{"maximum_y":maximum_y,"grounded_samples":grounded,"samples":row.samples})
	_keys([]);ramp.free();await _ticks(2)

func _run() -> void:
	Engine.physics_ticks_per_second=60;_build();fixture.get_node("Floor").free();_solid("LargeFloor",Vector3(600.,.2,600.),Vector3(0.,-.1,0.));player.free_roam_bounds=Rect2(-250,-250,500,500)
	initial_shape=_shape_snapshot();await _ticks(10)
	for hz: int in [30,60]:
		Engine.physics_ticks_per_second=hz;await _ticks(4)
		var results:={}
		results.walk=await _onset_brake(hz,1.4,false)
		results.brisk_walk=await _onset_brake(hz,2.24,false)
		results.run=await _onset_brake(hz,3.5,true)
		results.brisk_run=await _onset_brake(hz,5.6,true)
		results.turbo=await _onset_brake(hz,21.,true)
		profile_results[str(hz)]=results
		await _turns(hz,false);await _turns(hz,true);await _safety(hz);await _slope(hz)
	for profile: String in ["walk","brisk_walk","run","brisk_run","turbo"]:
		var first: Dictionary=profile_results["30"][profile];var second: Dictionary=profile_results["60"][profile]
		_check(profile+".30_and_60hz_have_equivalent_onset_and_brake_times",absf(float(first.reach_99_percent_s)-float(second.reach_99_percent_s))<=1./30.+.001 and absf(float(first.stop_time_s)-float(second.stop_time_s))<=1./30.+.001,{"30hz":first,"60hz":second})
	_check("physics.capsule_identity_dimensions_and_masks_unchanged",_shape_snapshot()==initial_shape,{"initial":initial_shape,"current":_shape_snapshot()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_keys([])
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var hashes:={}
	for path: String in ["res://scripts/player/free_roam_player.gd","res://scripts/player/public_player.gd","res://scripts/player/palace_player.gd","res://scripts/player/movement_controller.gd","res://scripts/player/idle_support.gd","res://scripts/input_router.gd","res://../tests/game/check_jump.gd","res://../tests/game/check_human_locomotion.gd"]:hashes[path]=FileAccess.get_sha256(path)
	hashes[controller_path]=FileAccess.get_sha256(controller_path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write locomotion report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP29_HUMAN_LOCOMOTION","controller_script":controller_path,"result":"PASS" if failed==0 else "FAIL","passed":failed==0,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"motion_records":motion_records,"profile_results":profile_results,"source_sha256":hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"scope":"Real production player and native capsule, Input.action_press digital actions on independently authored flat, wall and 12-degree ramp fixtures at 30/60 physics Hz. Does not claim OS input, full-city routes, avatar planted-foot animation, camera comfort, performance or GTA motion-capture quality. Unlimited fresh-press air/swim motion remains separate jump/pool coverage."}),"  ")+"\n");file.close()
	print("HUMAN_LOCOMOTION_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)

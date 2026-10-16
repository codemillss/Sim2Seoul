extends "res://../tests/game/check_jump.gd"
## Focused metre fixture: production player, avatar and camera, 60Hz physics
## against independent 30/60/144Hz late-process observations. No city/UI writes.
class LateRecorder extends Node:
	var test
	func _physics_process(delta: float) -> void:test._observe_physics(delta)
	func _process(delta: float) -> void:test._observe_render(delta)

var rig: Node3D
var avatar: Node3D
var recorder: Node
var source_hashes := {}
var records: Array = []
var phase := ""
var physics_rows: Array = []
var render_rows: Array = []
var previous_avatar := Transform3D.IDENTITY
var current_avatar := Transform3D.IDENTITY
var pose_ready := false
var phase_physics_ticks := 0
var initial_capsule := {}
var started_at := ""

func _initialize() -> void:
	started_at=Time.get_datetime_string_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("check_stable_motion needs absolute --report");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if not InputMap.has_action("toggle_menu"):InputMap.add_action("toggle_menu")
	Engine.physics_ticks_per_second=60;Engine.max_fps=144
	create_timer(90.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var result:={}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result:=[]
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String,passed: bool,evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("STABLE_MOTION_FAIL "+title)

func _capsule() -> Dictionary:
	var shape: CollisionShape3D=player.get_node("CollisionShape")
	return {"node":shape.get_instance_id(),"shape":shape.shape.get_instance_id(),"radius":shape.shape.radius,"height":shape.shape.height,"disabled":shape.disabled,"transform":shape.transform,"layer":player.collision_layer,"mask":player.collision_mask}

func _joint(title: String) -> Node3D:return avatar.find_child(title,true,false) as Node3D

func _anchor() -> Node3D:
	var proxy:=avatar.get_node_or_null("RenderProxy") as Node3D
	return proxy if proxy!=null else avatar

func _observe_physics(_delta: float) -> void:
	if not is_instance_valid(avatar):return
	previous_avatar=current_avatar if pose_ready else avatar.global_transform
	current_avatar=avatar.global_transform;pose_ready=true
	if phase.is_empty():return
	phase_physics_ticks+=1
	if phase_physics_ticks<=4:return
	physics_rows.append({"player":player.global_position,"upper_body":_joint("UpperBody").transform,"left_thigh":_joint("LeftThigh").rotation.x,"left_arm":_joint("LeftUpperArm").rotation.x,"state":avatar.snapshot().state,"grounded":player.is_on_floor(),"velocity":player.velocity,"recoveries":player.recoveries})

func _observe_render(delta: float) -> void:
	if phase.is_empty() or phase_physics_ticks<=4 or not pose_ready:return
	var fraction:=Engine.get_physics_interpolation_fraction()
	var expected: Transform3D=previous_avatar.interpolate_with(current_avatar,clampf(fraction,0.,1.))
	var actual: Transform3D=_anchor().global_transform
	var offset: Vector3=Vector3.UP*rig.pivot_height_m+rig.global_basis.z*rig.current_distance
	var pair_error: Vector3=rig.camera.global_position-actual.origin-offset
	var raw: Node3D=player.get_node("Visual")
	render_rows.append({"delta":delta,"fraction":fraction,"actual_camera":rig.camera.global_transform,"actual_anchor":actual,"independent_expected_anchor":expected,"anchor_error_m":actual.origin.distance_to(expected.origin),"camera_avatar_relative_error_m":pair_error.length(),"raw_Visual_physics_error_m":raw.global_position.distance_to(player.global_position),"upper_body":_joint("UpperBody").transform,"proxy_exists":_anchor()!=avatar})

func _setup_stable() -> void:
	_build()
	fixture.name="StableMotionFixture"
	fixture.get_node("Floor").free()
	_solid("LargeFloor",Vector3(600,.2,600),Vector3(0,-.1,0))
	player.free_roam_bounds=Rect2(-250,-250,500,500)
	player.walk_speed_mps=8.4;player.run_speed_mps=21.
	var body:=MeshInstance3D.new();body.name="Body";body.position.y=.85
	var mesh:=CapsuleMesh.new();mesh.radius=.3;mesh.height=1.7;body.mesh=mesh;player.get_node("Visual").add_child(body)
	rig=load("res://scenes/player/camera_rig.tscn").instantiate();rig.set_script(load("res://scripts/player/exploration_camera.gd"));rig.target_path=NodePath("../Player");fixture.add_child(rig)
	player.movement_camera=rig.camera
	avatar=load("res://scripts/player/exploration_avatar.gd").new();player.get_node("Visual").add_child(avatar)
	_check("startup.actual_exploration_avatar_ready",avatar.setup(player))
	recorder=LateRecorder.new();recorder.test=self;recorder.process_priority=1000;recorder.process_physics_priority=1000;recorder.process_mode=Node.PROCESS_MODE_ALWAYS;fixture.add_child(recorder)
	initial_capsule=_capsule()

func _place(point: Vector3) -> void:
	_keys([]);player.global_transform=Transform3D(Basis.IDENTITY,point);player.velocity=Vector3.ZERO;player.require_neutral_input();player.reset_physics_interpolation()
	rig.reset_orientation();await _ticks(12);await process_frame
	_check("placement.supported_and_neutral",player.is_on_floor() and not player.input_latched,{"player":player.global_position})

func _case(title: String,actions: Array,ticks := 60) -> void:
	physics_rows=[];render_rows=[];phase_physics_ticks=0;phase=title
	var recovery_before: int=player.recoveries
	_keys(actions);await _ticks(ticks);phase="";_keys([])
	var min_y:=INF;var max_y:=-INF;var max_roll:=0.;var min_arm:=INF;var max_arm:=-INF;var min_leg:=INF;var max_leg:=-INF
	for row: Dictionary in physics_rows:
		min_y=minf(min_y,row.upper_body.origin.y);max_y=maxf(max_y,row.upper_body.origin.y)
		max_roll=maxf(max_roll,absf(row.upper_body.basis.get_euler().z))
		min_arm=minf(min_arm,row.left_arm);max_arm=maxf(max_arm,row.left_arm);min_leg=minf(min_leg,row.left_thigh);max_leg=maxf(max_leg,row.left_thigh)
	var relative_error:=0.;var anchor_error:=0.;var raw_error:=0.;var fmin:=INF;var fmax:=-INF;var proxies:=true
	for row: Dictionary in render_rows:
		relative_error=maxf(relative_error,row.camera_avatar_relative_error_m);anchor_error=maxf(anchor_error,row.anchor_error_m);raw_error=maxf(raw_error,row.raw_Visual_physics_error_m)
		fmin=minf(fmin,row.fraction);fmax=maxf(fmax,row.fraction);proxies=proxies and row.proxy_exists
	var evidence:={"name":title,"render_cap_fps":Engine.max_fps,"physics_samples":physics_rows.size(),"render_samples":render_rows.size(),"torso_y_range_m":[min_y,max_y],"maximum_torso_roll_radians":max_roll,"arm_range_radians":max_arm-min_arm,"leg_range_radians":max_leg-min_leg,"maximum_camera_avatar_relative_error_m":relative_error,"maximum_independent_render_anchor_error_m":anchor_error,"maximum_raw_Visual_physics_error_m":raw_error,"render_fraction_range":[fmin,fmax],"physical_rows":physics_rows,"render_rows":render_rows}
	records.append(evidence)
	_check(title+".torso_has_no_walk_run_or_jump_bob_and_roll",physics_rows.size()>30 and absf(min_y-.85)<.00001 and absf(max_y-.85)<.00001 and max_roll<.00001,evidence)
	_check(title+".camera_and_visible_body_share_render_fraction",render_rows.size()>=10 and proxies and relative_error<.002 and anchor_error<.002,evidence)
	_check(title+".physics_roots_remain_unmodified_and_no_recovery",raw_error<.0001 and player.recoveries==recovery_before and _capsule()==initial_capsule,{"maximum_Visual_error_m":raw_error,"recovery_delta":player.recoveries-recovery_before})
	if "jump" not in actions:
		_check(title+".limbs_still_animate_while_torso_stays_level",max_arm-min_arm>.1 and max_leg-min_leg>.1,{"arm_range":max_arm-min_arm,"leg_range":max_leg-min_leg})
	if Engine.max_fps==144:_check(title+".subphysics_render_fractions_are_exercised",fmax-fmin>.5,{"minimum_fraction":fmin,"maximum_fraction":fmax,"samples":render_rows.size()})

func _overlaps(point: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=rig.arm.shape;query.collision_mask=1;query.transform=Transform3D(Basis.IDENTITY,point);query.exclude=[player.get_rid()]
	return not fixture.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _safety() -> void:
	var wall:=_solid("ExplicitCameraWall",Vector3(10,4,.4),Vector3(0,2,3))
	await _place(Vector3(0,.08,0));await _ticks(8)
	var bad:=0
	for fraction in [0.,.25,.5,.75,1.]:
		if _overlaps(rig._render_pose(fraction).origin):bad+=1
	_check("safety.camera_obstruction_and_fractional_eye_positions_remain_clear",bad==0 and rig.current_distance<3. and rig.current_distance>1.,{"bad_fractional_eye_poses":bad,"actual_distance_m":rig.current_distance})
	_keys([]);var camera_before: Transform3D=rig.camera.global_transform;var anchor_before: Transform3D=_anchor().global_transform;var clock_before: float=avatar.snapshot().clock
	paused=true
	for index in range(12):await process_frame
	_check("safety.menu_pause_keeps_actual_camera_anchor_and_animation_frozen",rig.camera.global_transform==camera_before and _anchor().global_transform==anchor_before and avatar.snapshot().clock==clock_before)
	paused=false
	wall.free();await _ticks(3)
	# Explicit recovery fault: production recovery must publish a collapsed
	# history on the next physics frame, never a rendered cross-map sweep.
	var recovery_regions: Array[Rect2]=[Rect2(-250,-250,500,500)]
	player.configure_recovery(Vector3(80,.08,0),recovery_regions)
	var recovered: bool=player.recover("stable_motion_explicit_recovery_fixture")
	player.reset_physics_interpolation();await _ticks(2);await process_frame
	var distance: float=rig._previous_pose.origin.distance_to(rig._physics_pose.origin)
	var render_error: float=_anchor().global_position.distance_to(avatar.global_position)
	_check("safety.recovery_collapses_camera_and_visual_histories",recovered and distance<.001 and render_error<.001 and rig.camera.global_position.distance_to(player.global_position)<7.,{"production_recovery_accepted":recovered,"camera_history_separation_m":distance,"render_anchor_error_m":render_error,"camera":rig.camera.global_position,"player":player.global_position})

func _run() -> void:
	for path in ["res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/camera_rig.gd","res://scripts/input_router.gd","res://scenes/player/camera_rig.tscn","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_setup_stable();await _ticks(10)
	for fps in [30,60,144]:
		Engine.max_fps=fps
		await _place(Vector3(-80,.08,-80))
		await _case(str(fps)+"fps.walk_8_4mps",["move_forward"])
		await _case(str(fps)+"fps.run_21mps",["move_forward","move_fast"])
		await _case(str(fps)+"fps.jump_3m",["move_forward","jump"])
		_keys([]);await _ticks(90)
	Engine.max_fps=144;await _safety();_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([]);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var result:={"task":"stable_motion","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"physics_hz":Engine.physics_ticks_per_second,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":records,"scope":"Synthetic flat metre fixture with actual latest production player, articulated avatar and exploration camera. Real Input actions drive walk8.4/run21/jump3m. A late-priority recorder observes actual physics state and actual camera/render-proxy transforms at 30/60/144 render caps with 60Hz physics. Torso local Y/roll, independent interpolation expectation, fixed camera/avatar relative offset, retained capsule, obstruction, pause and recovery are checked quantitatively. Explicit scenario placements/recovery fault are test-only. Headless process-frame observations are not native GPU image quality, human perceived comfort, all city camera angles or performance acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Could not save stable motion report")
	print("STABLE_MOTION_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

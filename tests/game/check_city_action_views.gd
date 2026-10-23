extends "res://../tests/game/check_stable_motion.gd"
## Isolated native pose views, scheduled by elapsed real physics action time.
## World F/X/G contacts and car ownership are covered by action_freedom QA.
signal action_late_observed
var human: Node3D
var skeleton: Skeleton3D
var review_camera: Camera3D
var active_view := "front"
var captures: Array=[]
var started_usec := 0

func _observe_physics(_delta: float) -> void:pass

func _observe_render(_delta: float) -> void:
	if is_instance_valid(review_camera):
		var offset:=Vector3(0,1.10,-2.75)
		if active_view=="side":offset=Vector3(-2.75,1.10,0)
		elif active_view=="quarter":offset=Vector3(-1.90,1.10,-2.10)
		review_camera.global_position=_anchor().global_position+offset
		review_camera.look_at(_anchor().global_position+Vector3.UP*.94)
		review_camera.force_update_transform()
	action_late_observed.emit()

func _late(count: int) -> void:
	for index in range(count):await action_late_observed

func _stage() -> void:
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(.69,.75,.78);settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.65;environment.environment=settings;fixture.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-28,0);sun.light_energy=1.2;sun.shadow_enabled=true;fixture.add_child(sun)
	var floor_art:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(30,.02,30);floor_art.mesh=box;floor_art.position.y=-.011
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.38,.43,.44);material.roughness=.85;floor_art.material_override=material;fixture.add_child(floor_art)
	review_camera=Camera3D.new();review_camera.name="IsolatedActionReviewCamera";review_camera.fov=48.;review_camera.near=.05;fixture.add_child(review_camera);rig.camera.current=false;review_camera.current=true

func _sample() -> Dictionary:
	var bones: Array=[];var palms: Dictionary={};var finite:=true
	for index: int in range(skeleton.get_bone_count()):
		var pose:=skeleton.get_bone_global_pose(index);finite=finite and pose.is_finite()
		bones.append({"index":index,"name":skeleton.get_bone_name(index),"pose_skeleton_m":pose})
	for side: String in ["Left","Right"]:palms[side]=_anchor().global_transform.affine_inverse()*skeleton.global_transform*(skeleton.get_bone_global_pose(human._find(side+"Hand"))*Vector3(human._hand_contacts[side]))
	return {"native_finite":finite,"native_bones":bones,"native_palms_avatar_m":palms,"action":avatar._sandbox_action,"remaining_s":avatar._sandbox_remaining_s,"duration_s":avatar._sandbox_duration_s,"guard_held":avatar._sandbox_guarding,"guard_blend":avatar._sandbox_guard_weight,"model_id":avatar.textured_model_snapshot(false).get("model_id",""),"native_model":avatar._textured_surface.model_id,"camera":review_camera.global_transform,"player":player.global_transform,"avatar_anchor":_anchor().global_transform,"facility_control":player.facility_control,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"render_interpolation_fraction":Engine.get_physics_interpolation_fraction()}

func _capture(title: String,target_elapsed: float,actual_elapsed: float,timed:=true) -> void:
	# The late observer has already run after the imported rig. force_draw
	# publishes that same actual pose without advancing/injecting an action.
	RenderingServer.force_draw()
	var picture:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+"_"+active_view+".png";var code:=picture.save_png(path);var row:=_sample()
	row.merge({"file":path,"sha256":FileAccess.get_sha256(path) if code==OK else "","view":active_view,"title":title,"target_elapsed_s":target_elapsed,"actual_physics_elapsed_s":actual_elapsed,"schedule_overshoot_s":actual_elapsed-target_elapsed,"image_size":[picture.get_width(),picture.get_height()],"save_error":code,"timed_pose":timed,"capture_method":"Actual native late-process imported skeleton observation and force_draw; normal physics action advancement, no pose or phase injection."})
	captures.append(row)
	_check(title+".native_capture_is_finite_and_bound_to_actual_active_action",code==OK and row.native_finite and not picture.is_empty() and row.action!="",{"file":path,"action":row.action,"remaining_s":row.remaining_s,"view":active_view})
	if timed:_check(title+".physical_elapsed_is_within_one_30hz_tick",actual_elapsed>=target_elapsed-.000001 and actual_elapsed-target_elapsed<=1./30.+.000001,{"target_elapsed_s":target_elapsed,"actual_elapsed_s":actual_elapsed,"allowed_overshoot_s":1./30.})

func _timed_action(kind: String,duration: float,targets: Array,facility:=false) -> void:
	avatar.cancel_sandbox_action();avatar.set_sandbox_guarding(false);player.set_facility_control(facility);await _late(10)
	active_view=String(targets[0][1]);await _late(6);avatar.play_sandbox_action(kind,duration)
	for target: Array in targets:
		active_view=String(target[1]);var elapsed:=0.
		while elapsed+0.000001<float(target[0]):
			await action_late_observed;elapsed=duration-float(avatar._sandbox_remaining_s)
		_capture(kind+"_"+String(target[2]),float(target[0]),elapsed)
	while avatar._sandbox_remaining_s>0.:await action_late_observed
	player.set_facility_control(false);await _late(10)

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	for path: String in ["res://project.godot","res://scripts/city_public_safety.gd","res://scripts/traffic_car_takeover.gd","res://scripts/explore_walk.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_camera.gd","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_city_action_views.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_check("native_gpu_required",DisplayServer.get_name()!="headless")
	if DisplayServer.get_name()=="headless":_finish();return
	root.size=Vector2i(768,640);root.content_scale_size=Vector2i(768,640);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	_setup_stable();Engine.physics_ticks_per_second=30;Engine.max_fps=120;_stage();await _late(30)
	human=avatar._textured_surface.rig;skeleton=avatar._textured_surface.skeleton
	await _timed_action("jab_left",.42,[[.10,"side","contact"],[.30,"front","recovery"]])
	await _timed_action("cross_right",.48,[[.14,"side","contact"],[.35,"front","recovery"]])
	await _timed_action("hook_left",.56,[[.20,"front","contact"],[.42,"side","recovery"]])
	await _timed_action("shove",.64,[[.18,"side","extension"],[.46,"front","recovery"]])
	avatar.set_sandbox_guarding(true);active_view="front";var guard_started:=Engine.get_physics_frames();var held_elapsed:=0.
	while held_elapsed<.35:await action_late_observed;held_elapsed=float(Engine.get_physics_frames()-guard_started)/30.
	_capture("guard_steady",.35,held_elapsed,false)
	active_view="side"
	while held_elapsed<.50:await action_late_observed;held_elapsed=float(Engine.get_physics_frames()-guard_started)/30.
	_capture("guard_steady",.5,held_elapsed,false);avatar.set_sandbox_guarding(false);await _late(48)
	await _timed_action("vehicle_enter",.78,[[.35,"quarter","midgesture"]],true)
	await _timed_action("vehicle_exit",.65,[[.35,"quarter","midgesture"]],true)
	_check("twelve_requested_native_views_captured",captures.size()==12)
	var stable:=true
	for path: String in source_hashes:stable=stable and FileAccess.get_sha256(path)==source_hashes[path]
	_check("source_sha_bindings_unchanged",stable)
	_check("original_capsule_and_collision_preserved",_capsule()==initial_capsule)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_keys([])
	var failed: int=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"CITY_ACTION_ISOLATED_NATIVE_VIEWS","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed,"images":captures.size()},"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"elapsed_wall_s":float(Time.get_ticks_usec()-started_usec)/1000000.,"source_sha256":source_hashes,"checks":checks,"captures":captures,"world_sequence_evidence":"data/reports/city_action_freedom/20261023/action_freedom_native_native01.json","scope":"Native-only daylight isolated metre fixture of current imported skin and production timed action/guard API, normal physics advancement at30Hz. Contact captures are scheduled within one physical tick of declared .10/.14/.20/.18s contacts; source elapsed and actual rendered native bones/camera are recorded. This does not trigger world hits or vehicle sequence and is not ordinary OS input, animation phase injection, performance, mocap or subjective comfort acceptance. World sequence evidence remains separate; all native pixels require visual review."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write isolated action views report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close();print("CITY_ACTION_VIEWS_RESULT ",checks.size()-failed,"/",checks.size()," images=",captures.size());quit(0 if failed==0 else 1)

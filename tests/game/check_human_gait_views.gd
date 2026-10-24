extends "res://../tests/game/check_human_appearance_native.gd"
## Actual production W gait, not authored phase poses. Native pictures require
## separate human review; numeric finite/capture checks are not gait acceptance.
class GaitLateFrame extends Node:
	signal observed
	var test
	func _process(_delta: float) -> void:
		# Establish and continuously publish the current inspection camera
		# before phase observers capture. First-view pictures must not reuse
		# the previously rendered camera while its transform is still queued.
		if not test.gait_active_view.is_empty():test._gait_track(test.gait_active_view)
		observed.emit()

const VIEW_PHASES := 8
const HIP_PHASES := 4
const MAX_IMAGES := 72
var gait_late: GaitLateFrame
var gait_views: Array=[]
var gait_images: Array=[]
var gait_region_vertices: Array=[]
var gait_started_usec := 0
var gait_surface: Node3D
var gait_native: Node3D
var gait_skeleton: Skeleton3D
var gait_started_camera_current := false
var gait_active_view := ""
var gait_body_profile := "standard"

func _build() -> void:
	super._build()
	# StableMotion creates the production avatar after this inherited player
	# build returns. Select geometry before its first native rig calibration.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body-profile="):gait_body_profile=argument.trim_prefix("--body-profile=")
	player.set_meta("human_body_profile",gait_body_profile)

func _observe_physics(_delta: float) -> void:pass
func _observe_render(_delta: float) -> void:pass

func _gait_bind_sources() -> void:
	for path: String in ["res://project.godot","res://scripts/player/free_roam_player.gd","res://scripts/player/public_player.gd","res://scripts/player/movement_controller.gd","res://scripts/player/idle_support.gd","res://scripts/player/human_surface_meshes.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/camera_rig.gd","res://scripts/input_router.gd","res://scenes/player/camera_rig.tscn","res://scripts/drivable_car_service.gd","res://scripts/city_bike_service.gd","res://assets/original/seoul_resident/AUTHORED_MANIFEST.json","res://assets/original/seoul_resident/seoul_resident_m01_street.glb","res://assets/original/seoul_resident/seoul_resident_f01_street.glb","res://assets/original/seoul_resident/AUTHORED_MANIFEST.json","res://assets/original/seoul_resident/seoul_resident_m01_swim.glb","res://assets/original/seoul_resident/seoul_resident_f01_swim.glb","res://../tests/game/check_human_gait_views.gd","res://../tests/game/check_human_appearance_native.gd","res://../tests/game/check_human_scale_motion.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_jump.gd"]:
		source_hashes[path]=FileAccess.get_sha256(path)
	for folder: String in ["res://assets/original/seoul_resident/"]:
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".png") or file.ends_with(".glb"):source_hashes[folder+file]=FileAccess.get_sha256(folder+file)

func _gait_bone_observations() -> Dictionary:
	var rows: Array=[];var finite:=true
	for index: int in range(gait_skeleton.get_bone_count()):
		var pose: Transform3D=gait_skeleton.get_bone_global_pose(index)
		var rest: Transform3D=gait_skeleton.get_bone_global_rest(index)
		var world: Transform3D=gait_skeleton.global_transform*pose
		var parent:=gait_skeleton.get_bone_parent(index)
		var length:=0.;var rest_length:=0.
		if parent>=0:
			length=world.origin.distance_to((gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(parent)).origin)
			rest_length=(gait_skeleton.global_transform*rest).origin.distance_to((gait_skeleton.global_transform*gait_skeleton.get_bone_global_rest(parent)).origin)
		finite=finite and pose.is_finite() and world.is_finite() and is_finite(length)
		rows.append({"index":index,"name":gait_skeleton.get_bone_name(index),"parent":parent,"actual_world":world,"actual_parent_distance_m":length,"import_rest_parent_distance_m":rest_length})
	var pelvis: int=gait_native._find("Pelvis")
	var left: int=gait_native._find("LeftThigh");var right: int=gait_native._find("RightThigh")
	return {"finite":finite,"actual_pelvis_world":gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(pelvis),"actual_left_hip_joint_world":(gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(left)).origin,"actual_right_hip_joint_world":(gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(right)).origin,"actual_head_joint_world":(gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(gait_native._find("Head"))).origin,"native_bones":rows,"scope":"Actual rendered imported skeleton poses and parent distances, not hidden procedural proxy joint lengths. Native head/hip movement is recorded separately from the production camera eye."}

func _gait_skin_observations(build_regions:=false) -> Dictionary:
	var bounds:=AABB();var first:=true;var finite:=true;var zero_normals:=0;var normal_min:=INF;var normal_max:=0.;var normal_count:=0
	var centres:={"Left":Vector3.ZERO,"Right":Vector3.ZERO};var counts:={"Left":0,"Right":0};var regions:={"Left":AABB(),"Right":AABB()}
	var frame: Transform3D=avatar.global_transform.affine_inverse()*gait_skeleton.global_transform
	var pelvis_y: float=(frame*gait_skeleton.get_bone_global_rest(gait_native._find("Pelvis"))).origin.y
	if build_regions:gait_region_vertices.clear()
	for surface_index: int in range(gait_surface._surfaces.size()):
		var row: Dictionary=gait_surface._surfaces[surface_index]
		var mesh: MeshInstance3D=row.mesh;var matrices: Array[Transform3D]=gait_surface._skin_matrices(mesh,row.bind_bones,row.skeleton)
		var arrays: Array=mesh.mesh.surface_get_arrays(int(row.surface));var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var selected: Dictionary={}
		if not build_regions:
			for region: Dictionary in gait_region_vertices[surface_index]:selected[int(region.vertex)]=String(region.side)
		var reference: Array=[]
		for vertex: int in row.referenced:
			var point:=Vector3.ZERO;var normal:=Vector3.ZERO
			for influence: int in range(4):
				var amount: float=row.weights[vertex*4+influence]
				if amount>0.:
					var matrix: Transform3D=matrices[row.bones[vertex*4+influence]]
					point+=(matrix*row.vertices[vertex])*amount
					if normals.size()==row.vertices.size():normal+=(matrix.basis*normals[vertex])*amount
			finite=finite and point.is_finite() and normal.is_finite()
			var normal_length:=normal.length();normal_count+=1;normal_min=minf(normal_min,normal_length);normal_max=maxf(normal_max,normal_length)
			if normal_length<.00001:zero_normals+=1
			bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point);first=false
			if build_regions and absf(point.y-pelvis_y)<.12 and absf(point.x)>.015 and absf(point.x)<.25 and point.z>.015:
				var side:="Left" if point.x<0. else "Right"
				reference.append({"vertex":vertex,"side":side});selected[vertex]=side
			if selected.has(vertex):
				var side: String=selected[vertex]
				regions[side]=AABB(point,Vector3.ZERO) if int(counts[side])==0 else regions[side].expand(point)
				centres[side]+=point;counts[side]=int(counts[side])+1
		if build_regions:gait_region_vertices.append(reference)
	for side: String in ["Left","Right"]:
		if int(counts[side])>0:centres[side]/=float(counts[side])
	return {"finite":finite,"actual_skinned_bounds_avatar_local_m":bounds,"actual_skinned_bounds_world_m":avatar.global_transform*bounds,"buttock_surface_centres_avatar_local_m":centres,"buttock_surface_bounds_avatar_local_m":regions,"buttock_surface_sample_counts":counts,"normal_samples":normal_count,"finite_linear_blend_skin_normals":finite and zero_normals==0,"zero_normals":zero_normals,"linear_blend_normal_length_range":[normal_min,normal_max],"scope":"CPU skinning of referenced actual visible mesh vertices/bind poses. Buttock subset is fixed from neutral rendered surface within0.12m of actual pelvis rest height, lateral0.015..0.25m and actor-local rear z>0.015m. It can contain clothing. Normal finite test is linear-blend source normals, not GPU lighting/shading acceptance."}

func _gait_steady(speed: float) -> Dictionary:
	var consecutive:=0;var observed:=0;var previous_run: float=avatar.snapshot().run_weight
	var physical_samples:=0;var deadline:=Time.get_ticks_msec()+3000
	while physical_samples<120 and Time.get_ticks_msec()<deadline:
		await gait_late.observed
		# Count new physical states, rather than high-FPS duplicate renders.
		var physical:=Engine.get_physics_frames()
		if physical==observed:continue
		observed=physical;physical_samples+=1
		var current_run: float=avatar.snapshot().run_weight
		var actual:=Vector2(player.velocity.x,player.velocity.z).length()
		consecutive=consecutive+1 if absf(actual-speed)<speed*.02 and absf(current_run-previous_run)<.001 and player.is_on_floor() else 0
		previous_run=current_run
		if consecutive>=12:return {"settled":true,"consecutive_physical_samples":consecutive,"actual_speed_mps":actual,"physics_frame":physical,"run_weight":current_run}
	return {"settled":false,"consecutive_physical_samples":consecutive,"actual_speed_mps":Vector2(player.velocity.x,player.velocity.z).length(),"physics_frame":Engine.get_physics_frames()}

func _gait_track(view: String) -> void:
	var offset:=Vector3(0.,1.10,-3.1);var height:=.94
	match view:
		"back":offset.z=3.1
		"left":offset=Vector3(-3.1,1.10,0.)
		"right":offset=Vector3(3.1,1.10,0.)
		"rear_hip_close":offset=Vector3(0.,1.01,1.12);height=.92
	var facing: Basis=player.get_node("Visual").global_basis.orthonormalized()
	var rendered_origin: Vector3=_anchor().global_position
	review_camera.global_position=rendered_origin+facing*offset
	review_camera.look_at(rendered_origin+Vector3.UP*height)
	review_camera.force_update_transform()

func _gait_capture(title: String,view: String,index: int,target_phase: float,unwrapped_phase: float) -> Dictionary:
	_gait_track(view)
	# Called inside the late-priority observer, after the real avatar/rig renders.
	# Drawing this existing pose does not advance or assign a gait phase.
	RenderingServer.force_draw()
	var pixels:=root.get_texture().get_image()
	var path:=report_path.get_basename()+"_"+title+"_"+view+"_"+str(index).pad_zeros(2)+".png"
	var code:=pixels.save_png(path)
	var skin:=_gait_skin_observations();var bones:=_gait_bone_observations();var sample: Dictionary=avatar.snapshot()
	var row:={"file":path,"body_profile":gait_body_profile,"actual_glb_path":gait_surface._street_asset_path,"actual_glb_sha256":gait_surface._street_asset_sha256,"sha256":FileAccess.get_sha256(path) if code==OK else "","save_error":code,"image_size":[pixels.get_width(),pixels.get_height()],"view":view,"sample_index":index,"target_stride_phase_radians":fposmod(target_phase,TAU),"actual_stride_phase_radians":sample.stride_phase,"actual_unwrapped_phase_radians":unwrapped_phase,"phase_overshoot_radians":unwrapped_phase-target_phase,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"frames_drawn":Engine.get_frames_drawn(),"render_interpolation_fraction":Engine.get_physics_interpolation_fraction(),"elapsed_wall_seconds":float(Time.get_ticks_usec()-gait_started_usec)/1000000.,"player_position":player.global_position,"velocity":player.velocity,"camera":review_camera.global_transform,"avatar_world":avatar.global_transform,"skin":skin,"bones":bones,"capture_method":"Late-priority actual process observer then RenderingServer.force_draw; actual production W gait, no pose/phase assignment."}
	row["production_camera_eye_world"]=rig.camera.global_position
	row["production_camera_eye_over_physics_feet_m"]=rig.camera.global_position.y-player.global_position.y
	row["native_head_joint_over_physics_feet_m"]=bones.actual_head_joint_world.y-player.global_position.y
	row["inspection_camera_publication"]={"force_update_transform":true,"late_tracking_priority":3000,"view_established_before_12_physical_sample_settling":true,"first_image_requires_independent_view_direction_review":true}
	gait_images.append(row)
	return row

func _gait_view(title: String,view: String,speed: float,count: int) -> void:
	gait_active_view=view;_gait_track(view)
	var steady:=await _gait_steady(speed)
	_check(title+"."+view+".actual_physics_speed_and_gait_settled",steady.settled,steady)
	var previous: float=fposmod(float(avatar.snapshot().stride_phase),TAU)
	var unwrapped:=previous;var step:=TAU/float(count)
	# All core views observe the same canonical phase targets0..7/8. The
	# targets schedule pictures only; actual physics state is never written.
	var base: float=ceilf(unwrapped/TAU)*TAU
	var rows: Array=[];var deadline:=Time.get_ticks_msec()+5000
	for index: int in range(count):
		var target:=base+float(index)*step
		while unwrapped<target and Time.get_ticks_msec()<deadline:
			await gait_late.observed
			var current: float=fposmod(float(avatar.snapshot().stride_phase),TAU)
			unwrapped+=fposmod(current-previous,TAU);previous=current
		if unwrapped<target:break
		rows.append(_gait_capture(title,view,index,target,unwrapped))
	var captured:=rows.size()==count;var finite:=not rows.is_empty();var phase_rows: Array=[]
	for row: Dictionary in rows:
		captured=captured and int(row.save_error)==OK and row.image_size==[768,480]
		finite=finite and bool(row.skin.finite_linear_blend_skin_normals) and bool(row.bones.finite)
		phase_rows.append({"target":row.target_stride_phase_radians,"actual":row.actual_stride_phase_radians,"overshoot":row.phase_overshoot_radians,"physics_frame":row.physics_frame,"file":row.file})
	var record:={"gait":title,"view":view,"speed_mps":speed,"requested_phases":count,"actual_captures":rows.size(),"settled":steady,"phase_observations":phase_rows,"visual_acceptance":"PENDING independent actual-image review; image count and finite transforms do not establish natural hip/gait motion."}
	gait_views.append(record)
	_check(title+"."+view+".actual_native_images_saved",captured,record)
	_check(title+"."+view+".actual_skin_bones_and_normals_finite",finite,{"samples":rows.size(),"scope":"Finite geometry only; no visual/naturalness approval."})

func _run() -> void:
	gait_started_usec=Time.get_ticks_usec();_gait_bind_sources()
	_check("startup.native_gpu_required",DisplayServer.get_name()!="headless",{"display":DisplayServer.get_name()})
	if DisplayServer.get_name()=="headless":_finish();return
	root.size=Vector2i(768,480);root.content_scale_size=Vector2i(768,480);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	_setup_stable();_metric_scene();await _full_ticks(15)
	gait_surface=avatar._textured_surface;gait_native=gait_surface.rig;gait_skeleton=gait_surface.skeleton
	_check("startup.actual_textured_weighted_human_ready",gait_surface.loaded and gait_native.loaded and gait_skeleton.get_bone_count()>40)
	_check("startup.actual_requested_body_profile_loaded",gait_surface.body_profile==gait_body_profile and String(player.get_meta("human_body_profile",""))==gait_body_profile,gait_surface.snapshot(false))
	if not gait_surface.loaded or not gait_native.loaded:_finish();return
	_gait_skin_observations(true)
	gait_late=GaitLateFrame.new();gait_late.test=self;gait_late.process_priority=3000;fixture.add_child(gait_late)
	gait_started_camera_current=rig.camera.current;rig.camera.current=false;review_camera.current=true;review_camera.fov=48.
	for speed: float in [1.4,3.5]:
		await _place(Vector3(-70.,.08,30.));player.walk_speed_mps=speed;player.run_speed_mps=speed
		_keys(["move_forward","move_fast"] if speed>2. else ["move_forward"])
		var title:="walk_1_4mps" if speed<2. else "run_3_5mps"
		for view: String in ["front","back","left","right"]:await _gait_view(title,view,speed,VIEW_PHASES)
		await _gait_view(title,"rear_hip_close",speed,HIP_PHASES)
		_keys([])
	_check("physics.original_capsule_and_collision_ownership_preserved",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty())
	_check("captures.actual_72_native_images_with_bounded_storage",gait_images.size()==MAX_IMAGES,{"actual_images":gait_images.size(),"core_views":4,"core_phases_per_speed":VIEW_PHASES,"hip_close_phases_per_speed":HIP_PHASES,"speeds":[1.4,3.5],"viewport":[768,480]})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_keys([])
	if is_instance_valid(review_camera):review_camera.current=false
	if is_instance_valid(rig):rig.camera.current=gait_started_camera_current
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"EXP29_ACTUAL_HUMAN_GAIT_VIEWS","result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed,"actual_images":gait_images.size()},"started_at_local":started_at,"elapsed_wall_seconds":float(Time.get_ticks_usec()-gait_started_usec)/1000000.,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"female_model_requested":"--female-model" in OS.get_cmdline_user_args(),"body_profile_requested":gait_body_profile,"active_native_body":gait_surface.snapshot(false) if is_instance_valid(gait_surface) else {},"source_sha256":source_hashes,"checks":checks,"views":gait_views,"captures":gait_images,"scope":"Isolated daylight metre fixture, actual production controller/avatar/weighted rig and engine W action.768x480 native tracking cameras show front/back/left/right8canonical stride targets and rear hip close4targets for each of1.4/3.5mps. Observed actual physics phases and late-render geometry are recorded, not injected. Numeric PASS is capture/finite/settling integrity only; independent full-sequence pixel review is required for hips/gait naturalness. No OS keyboard, motion capture, city navigation, sustained FPS or user comfort claim."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write human gait view report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close()
	print("HUMAN_GAIT_VIEWS_RESULT ",checks.size()-failed,"/",checks.size()," images=",gait_images.size());quit(0 if failed==0 else 1)

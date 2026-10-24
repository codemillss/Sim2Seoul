extends "res://../tests/game/check_human_gait_views.gd"
## Two-light portraits plus real-controller moving head/neck views.
## PASS means capture/source/finite/physics integrity only. A person must
## separately assess facial design and the full ordered motion images.
const PORTRAIT_VIEWS: Array[String]=["front","left_profile","right_profile","front45_left","front45_right","rear","rear45_left","rear45_right"]
const STUDIOS: Array[String]=["soft_studio","side_rim"]
const IDENTITY_MAX_IMAGES:=64
var identity_images: Array=[]
var identity_models: Array=[]
var identity_region_cache: Array=[]
var identity_model_id:=""
var identity_light_name:=""
var identity_environment: Environment
var identity_key: DirectionalLight3D
var identity_fill: DirectionalLight3D
var identity_rim: DirectionalLight3D
var identity_started_usec:=0
var identity_camera_settings: Dictionary={}

func _identity_scene() -> void:
	var environment:=WorldEnvironment.new();identity_environment=Environment.new()
	identity_environment.background_mode=Environment.BG_COLOR
	identity_environment.background_color=Color(.14,.16,.18)
	identity_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	identity_environment.ambient_light_color=Color(.90,.93,1.)
	identity_environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=identity_environment;fixture.add_child(environment)
	review_camera=Camera3D.new();review_camera.name="IdentityInspectionCamera"
	review_camera.near=.025;review_camera.far=50.;fixture.add_child(review_camera)
	# Camera-relative inspection lights keep each requested side readable.
	# Their resources are private to this fixture, never gameplay materials.
	identity_key=DirectionalLight3D.new();identity_key.shadow_enabled=true;review_camera.add_child(identity_key)
	identity_fill=DirectionalLight3D.new();review_camera.add_child(identity_fill)
	identity_rim=DirectionalLight3D.new();review_camera.add_child(identity_rim)

func _identity_lighting(title: String) -> Dictionary:
	identity_light_name=title
	if title=="soft_studio":
		identity_environment.ambient_light_energy=.40
		identity_key.rotation_degrees=Vector3(-25,-35,0);identity_key.light_energy=1.15
		identity_fill.rotation_degrees=Vector3(-15,35,0);identity_fill.light_energy=.35
		identity_rim.rotation_degrees=Vector3(-20,150,0);identity_rim.light_energy=.20
	else:
		identity_environment.ambient_light_energy=.22
		identity_key.rotation_degrees=Vector3(-20,-75,0);identity_key.light_energy=1.25
		identity_fill.rotation_degrees=Vector3(-10,15,0);identity_fill.light_energy=.20
		identity_rim.rotation_degrees=Vector3(-15,145,0);identity_rim.light_energy=.50
	return {"name":title,"ambient_energy":identity_environment.ambient_light_energy,"key_energy":identity_key.light_energy,"key_degrees_camera_local":identity_key.rotation_degrees,"fill_energy":identity_fill.light_energy,"fill_degrees_camera_local":identity_fill.rotation_degrees,"rim_energy":identity_rim.light_energy,"rim_degrees_camera_local":identity_rim.rotation_degrees,"scope":"Fixture-only inspection lighting; same actual native material resources and geometry, no image retouch or gameplay lighting change."}

func _identity_bind_regions() -> Dictionary:
	identity_region_cache.clear();var total:={"head":0,"neck":0,"eye":0}
	for row: Dictionary in gait_surface._surfaces:
		var head_bind: Dictionary={};var neck_bind: Dictionary={}
		for binding: int in range(row.bind_bones.size()):
			var title:=String(row.skeleton.get_bone_name(row.bind_bones[binding]))
			if title=="Bip01 Head":head_bind[binding]=true
			if title=="Bip01 Neck":neck_bind[binding]=true
		var material_name: String=String(row.mesh.mesh.surface_get_material(int(row.surface)).resource_name)
		var entry:={"head":PackedInt32Array(),"neck":PackedInt32Array(),"eye":PackedInt32Array(),"material_name":material_name}
		for index: int in row.referenced:
			var head:=0.;var neck:=0.
			for slot: int in range(4):
				var binding: int=row.bones[index*4+slot];var weight: float=row.weights[index*4+slot]
				if head_bind.has(binding):head+=weight
				if neck_bind.has(binding):neck+=weight
			if head>.90:entry.head.append(index);total.head+=1
			if neck>.50:entry.neck.append(index);total.neck+=1
			if "original_eye" in material_name.to_lower():entry.eye.append(index);total.eye+=1
		identity_region_cache.append(entry)
	return total

func _identity_regions() -> Dictionary:
	var bounds:={"head":AABB(),"neck":AABB(),"eye":AABB()};var counts:={"head":0,"neck":0,"eye":0};var finite:=true
	for at: int in range(gait_surface._surfaces.size()):
		var row: Dictionary=gait_surface._surfaces[at];var regions: Dictionary=identity_region_cache[at]
		var matrices: Array[Transform3D]=gait_surface._skin_matrices(row.mesh,row.bind_bones,row.skeleton)
		var computed: Dictionary={}
		for region: String in ["head","neck","eye"]:
			for index: int in regions[region]:
				var point:=Vector3.ZERO
				if computed.has(index):point=computed[index]
				else:
					for slot: int in range(4):
						var weight: float=row.weights[index*4+slot]
						if weight>0.:point+=(matrices[row.bones[index*4+slot]]*row.vertices[index])*weight
					point=avatar.global_transform*point;computed[index]=point
				finite=finite and point.is_finite()
				bounds[region]=AABB(point,Vector3.ZERO) if int(counts[region])==0 else AABB(bounds[region]).expand(point)
				counts[region]=int(counts[region])+1
	return {"finite":finite,"world_bounds":bounds,"referenced_vertex_counts":counts,"scope":"Actual CPU skinned referenced displayed vertices, Head influence>.90/Neck>.50 and separate original-eye material. Bounds observe geometry/framing, not beauty or realism."}

func _identity_target() -> Vector3:
	var head: int=gait_native._find("Head")
	return (gait_skeleton.global_transform*gait_skeleton.get_bone_global_pose(head)).origin+Vector3.UP*.105

func _identity_track(view: String) -> void:
	var target:=_identity_target();var offset:=Vector3(0.,0.,-.86)
	match view:
		"left_profile","head_left":offset=Vector3(-.86,0.,0.)
		"right_profile","head_right":offset=Vector3(.86,0.,0.)
		"front45_left":offset=Vector3(-.61,0.,-.61)
		"front45_right":offset=Vector3(.61,0.,-.61)
		"rear":offset=Vector3(0.,0.,.86)
		"rear45_left":offset=Vector3(-.61,0.,.61)
		"rear45_right":offset=Vector3(.61,0.,.61)
	var facing: Basis=player.get_node("Visual").global_basis.orthonormalized()
	review_camera.global_position=target+facing*offset
	review_camera.look_at(target);review_camera.force_update_transform()

func _gait_track(view: String) -> void:
	if view.begins_with("head_"):_identity_track(view)
	else:super._gait_track(view)

func _identity_head_in_frame(region: Dictionary) -> bool:
	var box: AABB=region.world_bounds.head
	if int(region.referenced_vertex_counts.head)<100 or box.size.y<.15:return false
	for x: float in [box.position.x,box.end.x]:
		for y: float in [box.position.y,box.end.y]:
			for z: float in [box.position.z,box.end.z]:
				if not review_camera.is_position_in_frustum(Vector3(x,y,z)):return false
	return true

func _identity_static_capture(view: String,lighting: Dictionary) -> void:
	gait_active_view="";_identity_track(view)
	for frame: int in range(3):await gait_late.observed
	var publication:=_gait_publish_skeleton()
	_identity_track(view);RenderingServer.force_draw()
	var path:=report_path.get_basename()+"_"+identity_model_id+"_"+identity_light_name+"_"+view+".png"
	var pixels:=root.get_texture().get_image();var code:=pixels.save_png(path);var regions:=_identity_regions()
	var framed:=_identity_head_in_frame(regions)
	var row:={"file":path,"sha256":FileAccess.get_sha256(path) if code==OK else "","kind":"static_portrait","model_id":identity_model_id,"body_profile":"standard","actual_glb_path":gait_surface._street_asset_path,"actual_glb_sha256":gait_surface._street_asset_sha256,"view":view,"lighting":lighting,"camera":review_camera.global_transform,"camera_projection":"orthogonal","camera_vertical_size_m":review_camera.size,"image_size":[pixels.get_width(),pixels.get_height()],"save_error":code,"rendered_regions":regions,"head_bounds_inside_camera_frustum":framed,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"scope":"Native actual production avatar/skin/material portrait. Capture/finite/framing pass is not facial attractiveness or realism acceptance."}
	identity_images.append(row)
	row["skin_palette_publication"]=publication
	_check(identity_model_id+"."+identity_light_name+"."+view+".actual_native_portrait_finite_and_uncropped",code==OK and pixels.get_size()==Vector2i(960,600) and regions.finite and framed and publication.after.matches_cpu,row)

func _gait_capture(title: String,view: String,index: int,target_phase: float,unwrapped_phase: float) -> Dictionary:
	var row:=super._gait_capture(title,view,index,target_phase,unwrapped_phase)
	row["kind"]="actual_controller_head_motion";row["model_id"]=identity_model_id;row["gait_label"]=title
	row["rendered_head_neck_eye"]=_identity_regions()
	row["inspection_lighting"]=_identity_lighting("soft_studio")
	row["head_bounds_inside_camera_frustum"]=_identity_head_in_frame(row.rendered_head_neck_eye)
	identity_images.append(row)
	return row

func _run() -> void:
	identity_started_usec=Time.get_ticks_usec();gait_started_usec=identity_started_usec;_gait_bind_sources()
	for path: String in ["res://../tests/game/check_character_identity_preview.gd","res://scripts/player/human_skin_materials.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	# Bind every original numeric/geometry/material generator helper present in
	# this candidate, including new face modules added before the source freeze.
	var authored_folder:="res://../tools/authored_character/"
	for file: String in DirAccess.get_files_at(authored_folder):
		if file.ends_with(".py"):source_hashes[authored_folder+file]=FileAccess.get_sha256(authored_folder+file)
	var paint_folder:="res://assets/original/seoul_resident/portrait_sources/"
	for file: String in DirAccess.get_files_at(paint_folder):
		if file.ends_with(".png"):source_hashes[paint_folder+file]=FileAccess.get_sha256(paint_folder+file)
	var paint_prompt_record:="res://../data/reports/character_identity/20261024/imagegen_paint_sources.json"
	if FileAccess.file_exists(paint_prompt_record):source_hashes[paint_prompt_record]=FileAccess.get_sha256(paint_prompt_record)
	_check("startup.native_renderer_required",DisplayServer.get_name()!="headless",{"display":DisplayServer.get_name()})
	if DisplayServer.get_name()=="headless":_finish();return
	_setup_stable();_identity_scene();await _full_ticks(15)
	identity_camera_settings={"fov":rig.camera.fov,"near":rig.camera.near,"far":rig.camera.far,"pivot_height_m":rig.pivot_height_m}
	gait_late=GaitLateFrame.new();gait_late.test=self;gait_late.process_priority=3000;fixture.add_child(gait_late)
	gait_started_camera_current=rig.camera.current;rig.camera.current=false;review_camera.current=true
	for model: String in ["SeoulResident_M01","SeoulResident_F01"]:
		identity_model_id=model
		var changed: bool=avatar.set_authored_model(model,"standard")
		_check(model+".production_model_switch_accepted",changed)
		await _place(Vector3(-70.,.08,30.));await _full_ticks(12)
		gait_surface=avatar._textured_surface;gait_native=gait_surface.rig;gait_skeleton=gait_surface.skeleton
		var actual: Dictionary=gait_surface.snapshot();var regions:=_identity_bind_regions()
		_check(model+".actual_own_head_neck_eye_regions_loaded",gait_surface.loaded and gait_native.loaded and gait_skeleton.get_bone_count()==52 and actual.model_id==model and int(regions.head)>100 and int(regions.neck)>20 and int(regions.eye)>20,{"snapshot":actual,"region_counts":regions})
		_check(model+".capsule_and_source_collision_unchanged",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty())
		identity_models.append(actual);_gait_skin_observations(true)
		root.size=Vector2i(960,600);root.content_scale_size=Vector2i(960,600);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
		review_camera.projection=Camera3D.PROJECTION_ORTHOGONAL;review_camera.size=.40
		for studio: String in STUDIOS:
			var lighting:=_identity_lighting(studio)
			for view: String in PORTRAIT_VIEWS:await _identity_static_capture(view,lighting)
		_identity_lighting("soft_studio")
		root.size=Vector2i(768,480);root.content_scale_size=Vector2i(768,480)
		review_camera.projection=Camera3D.PROJECTION_PERSPECTIVE;review_camera.fov=34.
		for speed: float in [1.4,3.5]:
			await _place(Vector3(-70.,.08,30.));player.walk_speed_mps=speed;player.run_speed_mps=speed
			_keys(["move_forward","move_fast"] if speed>2. else ["move_forward"])
			var title:=model+("_walk_1_4mps" if speed<2. else "_run_3_5mps")
			for view: String in ["head_front","head_right"]:await _gait_view(title,view,speed,4)
			_keys([])
		gait_active_view=""
		var settings:={"fov":rig.camera.fov,"near":rig.camera.near,"far":rig.camera.far,"pivot_height_m":rig.pivot_height_m}
		var moving_frames: Array=identity_images.filter(func(row: Dictionary)->bool:return row.kind=="actual_controller_head_motion" and row.model_id==model)
		var heads_visible: bool=moving_frames.size()==16
		for row: Dictionary in moving_frames:heads_visible=heads_visible and row.head_bounds_inside_camera_frustum and row.rendered_head_neck_eye.finite
		_check(model+".moving_head_frames_and_production_camera_capsule_intact",heads_visible and settings==identity_camera_settings and _capsule()==initial_capsule,{"actual_motion_head_frames":moving_frames.size(),"all_head_bounds_uncropped_and_finite":heads_visible,"before_camera_settings":identity_camera_settings,"after_camera_settings":settings})
	_check("captures.exact_bounded32_static_plus32_actual_motion_images",identity_images.size()==IDENTITY_MAX_IMAGES and gait_images.size()==32,{"all_native_images":identity_images.size(),"actual_motion_images":gait_images.size(),"static_portraits":identity_images.size()-gait_images.size(),"lights":STUDIOS,"static_views":PORTRAIT_VIEWS,"motion_phases_per_view":4,"actual_controller_speeds_mps":[1.4,3.5]})
	var unchanged:=true
	for path: String in source_hashes:unchanged=unchanged and FileAccess.get_sha256(path)==source_hashes[path]
	_check("sources.actual_assets_and_fixture_unchanged_during_capture",unchanged)
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_keys([]);gait_active_view=""
	if is_instance_valid(review_camera):review_camera.current=false
	if is_instance_valid(rig):rig.camera.current=gait_started_camera_current
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var result:={"task":"EXP34_AUTHORED_CHARACTER_IDENTITY_PORTRAIT_AND_MOTION","result":"PASS" if failed==0 else "FAIL","visual_acceptance":"PENDING actual ordered pixel review; no naturalness/attractiveness rating inferred from checks.","summary":{"checks":checks.size(),"failed":failed,"actual_images":identity_images.size(),"static_images":identity_images.size()-gait_images.size(),"motion_images":gait_images.size()},"started_at_local":started_at,"elapsed_wall_seconds":float(Time.get_ticks_usec()-identity_started_usec)/1000000.,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"source_sha256":source_hashes,"models":identity_models,"checks":checks,"motion_views":gait_views,"captures":identity_images,"scope":"Actual production M/F standard street avatar/controller/weighted skin.32orthogonal portraits(front/bothprofiles/front45/rear/rear45 with2inspectionlights),32actual W-walk/run head/neck captures(front/right4observed phases eachspeed/model). Existing separate72image M/F gait fixtures supply fullbody front/back/left/right sequences. Numeric integrity only; actual image review required. No OS input, face animation/hair simulation, mocap, photo scan, performance or subjective comfort acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write character identity report");quit(2);return
	file.store_string(JSON.stringify(_json(result),"  ")+"\n");file.close();print("CHARACTER_IDENTITY_RESULT ",checks.size()-failed,"/",checks.size()," images=",identity_images.size());quit(0 if failed==0 else 1)

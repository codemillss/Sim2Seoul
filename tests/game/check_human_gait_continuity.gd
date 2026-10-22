extends "res://../tests/game/check_stable_motion.gd"
## Dense observations of production Input-driven gait and weighted human skin.
## Small body-motion design limits are not motion-capture/visual acceptance.
signal late_observed
const OBSERVATION_HZ := 120
const SAMPLE_TICKS := 480
var surface: Node3D
var human: Node3D
var skeleton: Skeleton3D
var sampled: Array=[]
var sampling:=false
var last_physical:=-1
var skin_patches: Array=[]
var gait_results: Array=[]
var native_dimensions: Dictionary={}
var selected_physics_hz:=OBSERVATION_HZ
var _previous_physics_phase:=0.
var _current_physics_phase:=0.
var _phase_history_ready:=false
var before_bob_replay:=false
const FROZEN_ROOT := "res://../data/reports/human_gait/20261022/source_snapshots/"
const REPLAY_ROOT := "res://../data/cache/human_gait_baseline/"

func _initialize() -> void:
	super._initialize()
	before_bob_replay="--replay-before-bob" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--physics-hz="):selected_physics_hz=int(argument.trim_prefix("--physics-hz="))
	if selected_physics_hz not in [30,60,120]:push_error("continuity requires physics-hz30|60|120");quit(2);return
	Engine.physics_ticks_per_second=selected_physics_hz
	Engine.max_fps=OBSERVATION_HZ

func _setup_stable() -> void:
	super._setup_stable()
	if not before_bob_replay:return
	# Exact old sources remain immutable evidence. Only preload paths in these
	# temporary copies are redirected, so the production files need no reset.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_ROOT))
	for title: String in ["textured_human_rig","textured_human_surface","exploration_avatar","exploration_camera"]:
		var source:=FileAccess.get_file_as_string(FROZEN_ROOT+title+".before_bob.gd.txt")
		if title=="textured_human_surface":source=source.replace("res://scripts/player/textured_human_rig.gd",REPLAY_ROOT+"textured_human_rig.gd")
		if title=="exploration_avatar":source=source.replace("res://scripts/player/textured_human_surface.gd",REPLAY_ROOT+"textured_human_surface.gd")
		var file:=FileAccess.open(REPLAY_ROOT+title+".gd",FileAccess.WRITE);file.store_string(source);file.close()
	# The old camera must accompany the old human API. New presentation code
	# calls sample_gait_foot/gait_support_wave, which the frozen avatar lacks.
	avatar.free();rig.free()
	rig=load("res://scenes/player/camera_rig.tscn").instantiate();rig.set_script(load(REPLAY_ROOT+"exploration_camera.gd"));rig.target_path=NodePath("../Player");fixture.add_child(rig);player.movement_camera=rig.camera
	avatar=load(REPLAY_ROOT+"exploration_avatar.gd").new();player.get_node("Visual").add_child(avatar)
	_check("replay.exact_frozen_human_replaces_current_surface_before_observation",avatar.setup(player))

func _observe_physics(_delta: float) -> void:
	if not is_instance_valid(avatar):return
	_previous_physics_phase=_current_physics_phase if _phase_history_ready else avatar.stride_phase
	_current_physics_phase=avatar.stride_phase;_phase_history_ready=true

func _world_bone(semantic: String) -> Vector3:
	return skeleton.global_transform*skeleton.get_bone_global_pose(human._find(semantic)).origin

func _point(row: Dictionary,index: int,matrices: Array[Transform3D]) -> Vector3:
	var value:=Vector3.ZERO
	for slot: int in range(4):
		var weight: float=row.weights[index*4+slot]
		if weight>0.:value+=(matrices[row.bones[index*4+slot]]*row.vertices[index])*weight
	return value

func _prepare_skin_patches() -> void:
	var pelvis_y: float=(avatar.global_transform.affine_inverse()*_world_bone("Pelvis")).y
	var rest_points: Array=[];var minimum_rest_y:=INF
	for row: Dictionary in surface._surfaces:
		var selected:={"LeftSole":[],"RightSole":[],"LeftButtock":[],"RightButtock":[],"LeftHeel":[],"LeftToe":[],"RightHeel":[],"RightToe":[]}
		var matrices: Array[Transform3D]=surface._skin_matrices(row.mesh,row.bind_bones,row.skeleton)
		var rest_matrices: Array[Transform3D]=[]
		var frame:=avatar.global_transform.affine_inverse()*skeleton.global_transform
		for bind: int in range(row.mesh.skin.get_bind_count()):rest_matrices.append(frame*human._rest_global[row.bind_bones[bind]]*row.mesh.skin.get_bind_pose(bind))
		for index: int in row.referenced:
			var point:=_point(row,index,matrices)
			var rest_point:=_point(row,index,rest_matrices);minimum_rest_y=minf(minimum_rest_y,rest_point.y)
			rest_points.append({"patch":skin_patches.size(),"vertex":index,"point":rest_point})
			if point.y>-.02 and point.y<.015:
				if point.x<-.02:selected.LeftSole.append(index)
				elif point.x>.02:selected.RightSole.append(index)
			if absf(point.y-pelvis_y)<.12 and absf(point.x)>.015 and absf(point.x)<.25 and point.z>.015:
				selected[("Left" if point.x<0. else "Right")+"Buttock"].append(index)
		skin_patches.append({"row":row,"selected":selected})
	# Independently evaluate indexed original-rest skin to select the same
	# geometrically defined heel/toe bands. Never call the production helper
	# calibration or reuse its stored pivot points as the measured skin.
	for side: String in ["Left","Right"]:
		var heel_z:=-INF;var toe_z:=INF;var selected: Array=[]
		for candidate: Dictionary in rest_points:
			var p: Vector3=candidate.point
			if p.y<=minimum_rest_y+.014 and (p.x<-.02 if side=="Left" else p.x>.02):selected.append(candidate);heel_z=maxf(heel_z,p.z);toe_z=minf(toe_z,p.z)
		for candidate: Dictionary in selected:
			if float(candidate.point.z)>=heel_z-.025:skin_patches[candidate.patch].selected[side+"Heel"].append(candidate.vertex)
			if float(candidate.point.z)<=toe_z+.035:skin_patches[candidate.patch].selected[side+"Toe"].append(candidate.vertex)

func _observe_render(delta: float) -> void:
	var physical:=Engine.get_physics_frames()
	if sampling:
		var bones:={};var skin:={};var count:={}
		for semantic: String in ["Pelvis","Head","Spine","LeftThigh","LeftShin","LeftFoot","RightThigh","RightShin","RightFoot"]:bones[semantic]=_world_bone(semantic)
		for key: String in ["LeftSole","RightSole","LeftButtock","RightButtock","LeftHeel","LeftToe","RightHeel","RightToe"]:skin[key]=Vector3.ZERO;count[key]=0
		for patch: Dictionary in skin_patches:
			var row: Dictionary=patch.row
			var matrices: Array[Transform3D]=surface._skin_matrices(row.mesh,row.bind_bones,row.skeleton)
			for key: String in patch.selected:
				for index: int in patch.selected[key]:skin[key]+=_point(row,index,matrices);count[key]+=1
		for key: String in skin:skin[key]=avatar.global_transform*(skin[key]/maxi(1,int(count[key])))
		var local_error:=0.;var length_error:=0.;var knee_forward_min:=INF;var finite:=true;var flexion:={}
		for semantic: String in ["Spine","LeftThigh","RightThigh"]:
			var index: int=human._find(semantic)
			local_error=maxf(local_error,skeleton.get_bone_pose(index).origin.distance_to(skeleton.get_bone_rest(index).origin)*skeleton.global_basis.get_scale().abs().x)
		for side: String in ["Left","Right"]:
			var hip: Vector3=bones[side+"Thigh"];var knee: Vector3=bones[side+"Shin"];var foot: Vector3=bones[side+"Foot"]
			var projection:=hip.lerp(foot,clampf((knee-hip).dot(foot-hip)/(foot-hip).length_squared(),0.,1.))
			knee_forward_min=minf(knee_forward_min,(knee-projection).dot(-avatar.global_basis.z.normalized()))
			flexion[side]=rad_to_deg(PI-(hip-knee).angle_to(foot-knee))
			for pair: Array in [["Thigh","Shin"],["Shin","Foot"]]:
				var a: int=human._find(side+pair[0]);var b: int=human._find(side+pair[1])
				var rest_length: float=(skeleton.global_basis*(human._rest_global[b].origin-human._rest_global[a].origin)).length()
				length_error=maxf(length_error,absf(Vector3(bones[side+pair[0]]).distance_to(bones[side+pair[1]])-rest_length))
		for value: Vector3 in bones.values():finite=finite and value.is_finite()
		var foot_pitch:={}
		for side: String in ["Left","Right"]:foot_pitch[side]=(avatar.global_basis.inverse()*avatar._joints[side+"Foot"].global_basis).get_euler().x
		var anchor: Vector3=_anchor().global_position
		var render_fraction:=Engine.get_physics_interpolation_fraction()
		var displayed_phase:=fposmod(_previous_physics_phase+fposmod(_current_physics_phase-_previous_physics_phase,TAU)*render_fraction,TAU)
		var rendered_gait: Dictionary=avatar.get_meta("render_gait_state",{})
		if rendered_gait.has("stride_phase"):displayed_phase=fposmod(float(rendered_gait.stride_phase),TAU)
		var rocker:={};var ground_feet: Variant=human.get("_ground_feet")
		if ground_feet is Dictionary:
			for side: String in ["Left","Right"]:
				if not ground_feet.has(side):continue
				var contact: Dictionary=ground_feet[side];var roll: float=contact.roll_radians
				foot_pitch[side]=roll
				if absf(roll)<.00001:continue
				var kind:="Heel" if roll>0. else "Toe";var actual: Vector3=skin[side+kind];var target: Vector3=skeleton.global_transform*Vector3(contact.pivot)
				rocker[side]={"kind":kind,"roll_radians":roll,"actual_cpu_skin_contact_world_m":actual,"target_pivot_world_m":target,"actual_skin_to_pivot_error_m":actual.distance_to(target),"actual_patch_vertices":count[side+kind]}
		sampled.append({"physics_frame":physical,"phase_radians":avatar.stride_phase,"render_fraction":Engine.get_physics_interpolation_fraction(),"run_weight":avatar._run_weight,"stance_fraction":avatar._stance_fraction,"cycle_distance_m":avatar._cycle_distance_m,"cadence_hz":avatar.cadence_hz,"actual_speed_mps":Vector2(player.velocity.x,player.velocity.z).length(),"player":player.global_position,"avatar":avatar.global_position,"render_anchor":anchor,"bones":bones,"skin":skin,"foot_pitch_radians":foot_pitch,"knee_flexion_degrees":flexion,"skin_patch_counts":count,"finite":finite,"local_connection_error_m":local_error,"leg_length_error_m":length_error,"minimum_knee_forward_m":knee_forward_min,"grounded":player.is_on_floor(),"contact_error_m":human.snapshot().maximum_contact_error_m,"camera_eye_height_m":rig.camera.global_position.y-anchor.y})
		sampled[-1]["rocker_contacts"]=rocker
		sampled[-1]["render_delta_s"]=delta
		sampled[-1]["rendered_phase_estimate_radians"]=displayed_phase
		sampled[-1]["phase_observation_source"]="production_render_gait_state" if rendered_gait.has("stride_phase") else "independent_physical_phase_history_interpolation"
		if rendered_gait.has("_stance_fraction"):sampled[-1]["stance_fraction"]=float(rendered_gait._stance_fraction)
		sampled[-1]["process_frame"]=Engine.get_process_frames()
	last_physical=physical
	late_observed.emit()

func _wait_steps(count: int) -> void:
	for index: int in range(count):await late_observed

func _range(values: Array[float]) -> Dictionary:
	if values.is_empty():return {"minimum":0.,"maximum":0.,"excursion":0.,"samples":0}
	var minimum:=INF;var maximum:=-INF
	for value: float in values:minimum=minf(minimum,value);maximum=maxf(maximum,value)
	return {"minimum":minimum,"maximum":maximum,"excursion":maximum-minimum,"samples":values.size()}

func _median(values: Array) -> float:
	if values.is_empty():return INF
	var sorted:=values.duplicate();sorted.sort()
	var middle: int=sorted.size()/2
	return float(sorted[middle]) if sorted.size()%2==1 else (float(sorted[middle-1])+float(sorted[middle]))*.5

func _analyse(mode: String,speed: float) -> void:
	var pelvis: Array[float]=[];var head: Array[float]=[];var rear: Array[float]=[];var vertical_velocity: Array[float]=[];var vertical_acceleration: Array[float]=[];var camera: Array[float]=[]
	var maximum_connections:=0.;var maximum_length:=0.;var minimum_knee:=INF;var maximum_contact:=0.;var finite:=true;var floor_all:=true;var maximum_speed_error:=0.;var maximum_step:=0.
	var maximum_bone_slip:={"Left":0.,"Right":0.};var maximum_sole_slip:={"Left":0.,"Right":0.};var stance_counts:={"Left":0,"Right":0};var count_min:=100000
	var maximum_bone_xz_slip:={"Left":0.,"Right":0.};var maximum_sole_xz_slip:={"Left":0.,"Right":0.};var flat_sole_y:={"Left":[],"Right":[]}
	var knees:={"Left":[],"Right":[]}
	var stance_knees:={"Left":[],"Right":[]}
	var rocker_error:=0.;var rocker_xz_speed:=0.;var rocker_count:=0;var rocker_types:={"Heel":0,"Toe":0}
	for index: int in range(sampled.size()):
		var row: Dictionary=sampled[index];var root_y: float=row.render_anchor.y
		pelvis.append(float(row.bones.Pelvis.y)-root_y);head.append(float(row.bones.Head.y)-root_y);rear.append((float(row.skin.LeftButtock.y)+float(row.skin.RightButtock.y))*.5-root_y);camera.append(row.camera_eye_height_m)
		maximum_connections=maxf(maximum_connections,row.local_connection_error_m);maximum_length=maxf(maximum_length,row.leg_length_error_m);minimum_knee=minf(minimum_knee,row.minimum_knee_forward_m);maximum_contact=maxf(maximum_contact,row.contact_error_m);finite=finite and row.finite;floor_all=floor_all and row.grounded;maximum_speed_error=maxf(maximum_speed_error,absf(float(row.actual_speed_mps)-speed))
		for key: String in row.skin_patch_counts:count_min=mini(count_min,row.skin_patch_counts[key])
		for side: String in ["Left","Right"]:knees[side].append(row.knee_flexion_degrees[side])
		if index==0:continue
		var prior: Dictionary=sampled[index-1];var dt: float=row.render_delta_s
		var delta_y: float=pelvis[index]-pelvis[index-1];maximum_step=maxf(maximum_step,absf(delta_y));vertical_velocity.append(delta_y/dt)
		if vertical_velocity.size()>1:vertical_acceleration.append((vertical_velocity[-1]-vertical_velocity[-2])/dt)
		for side: String in ["Left","Right"]:
			# This phase estimate shares the rendered root/joint time. Interior
			# contact limits exclude boundary classification uncertainty; actual
			# native/CPU skin, not this estimate, supplies every motion metric.
			var phase_: float=fposmod(float(row.rendered_phase_estimate_radians)/TAU+(.5 if side=="Right" else 0.),1.)
			var before_phase: float=fposmod(float(prior.rendered_phase_estimate_radians)/TAU+(.5 if side=="Right" else 0.),1.)
			if phase_>.04 and phase_<float(row.stance_fraction)-.04:stance_knees[side].append(row.knee_flexion_degrees[side])
			if phase_>.04 and phase_<float(row.stance_fraction)-.04 and row.rocker_contacts.has(side):
				var contact: Dictionary=row.rocker_contacts[side];rocker_error=maxf(rocker_error,contact.actual_skin_to_pivot_error_m)
				if before_phase>.04 and before_phase<float(prior.stance_fraction)-.04 and phase_>before_phase and prior.rocker_contacts.has(side) and prior.rocker_contacts[side].kind==contact.kind:
					var delta: Vector3=contact.actual_cpu_skin_contact_world_m-prior.rocker_contacts[side].actual_cpu_skin_contact_world_m
					rocker_xz_speed=maxf(rocker_xz_speed,Vector2(delta.x,delta.z).length()/dt);rocker_count+=1;rocker_types[contact.kind]+=1
			# Heel/toe rocker deliberately moves the ankle and sole centroid. Only
			# two consecutive genuinely flat stance frames enforce that criterion.
			var flat: bool=absf(float(row.foot_pitch_radians[side]))<.0001 and absf(float(prior.foot_pitch_radians[side]))<.0001
			if flat and phase_>.04 and phase_<float(row.stance_fraction)-.04 and before_phase>.04 and before_phase<float(prior.stance_fraction)-.04 and phase_>before_phase:
				maximum_bone_slip[side]=maxf(maximum_bone_slip[side],Vector3(row.bones[side+"Foot"]).distance_to(prior.bones[side+"Foot"])/dt)
				maximum_sole_slip[side]=maxf(maximum_sole_slip[side],Vector3(row.skin[side+"Sole"]).distance_to(prior.skin[side+"Sole"])/dt);stance_counts[side]+=1
				var bone_delta: Vector3=row.bones[side+"Foot"]-prior.bones[side+"Foot"];var sole_delta: Vector3=row.skin[side+"Sole"]-prior.skin[side+"Sole"]
				maximum_bone_xz_slip[side]=maxf(maximum_bone_xz_slip[side],Vector2(bone_delta.x,bone_delta.z).length()/dt)
				maximum_sole_xz_slip[side]=maxf(maximum_sole_xz_slip[side],Vector2(sole_delta.x,sole_delta.z).length()/dt);flat_sole_y[side].append(float(row.skin[side+"Sole"].y))
	var velocity_peak:=0.;var acceleration_peak:=0.
	var duration:=0.;var fraction_min:=INF;var fraction_max:=-INF;var physical_frames:={}
	for row: Dictionary in sampled:duration+=float(row.render_delta_s);fraction_min=minf(fraction_min,row.render_fraction);fraction_max=maxf(fraction_max,row.render_fraction);physical_frames[row.physics_frame]=true
	for value: float in vertical_velocity:velocity_peak=maxf(velocity_peak,absf(value))
	for value: float in vertical_acceleration:acceleration_peak=maxf(acceleration_peak,absf(value))
	var sole_y_ranges:={}
	var knee_ranges:={}
	for side: String in ["Left","Right"]:
		var values: Array[float]=[]
		for value: float in flat_sole_y[side]:values.append(value)
		sole_y_ranges[side]=_range(values)
		values=[]
		for value: float in knees[side]:values.append(value)
		knee_ranges[side]=_range(values)
	var result:={"mode":mode,"configured_speed_mps":speed,"samples":sampled.size(),"duration_s":float(sampled.size())/OBSERVATION_HZ,"pelvis_height_m":_range(pelvis),"head_height_m":_range(head),"rear_skin_centre_height_m":_range(rear),"maximum_pelvis_vertical_speed_mps":velocity_peak,"maximum_pelvis_vertical_acceleration_mps2":acceleration_peak,"maximum_one_tick_vertical_change_m":maximum_step,"maximum_local_connection_error_m":maximum_connections,"maximum_leg_length_error_m":maximum_length,"minimum_knee_forward_m":minimum_knee,"maximum_contact_error_m":maximum_contact,"minimum_cpu_skin_patch_vertices":count_min,"maximum_actual_speed_error_mps":maximum_speed_error,"camera_eye_height_m":_range(camera),"flat_stance_counts":stance_counts,"maximum_world_foot_bone_stance_speed_mps":maximum_bone_slip,"maximum_world_cpu_skin_sole_stance_speed_mps":maximum_sole_slip,"maximum_world_foot_bone_flat_stance_xz_speed_mps":maximum_bone_xz_slip,"maximum_world_cpu_skin_sole_flat_stance_xz_speed_mps":maximum_sole_xz_slip,"actual_world_flat_sole_height_m":sole_y_ranges,"trace":sampled.duplicate(true)}
	result["native_knee_flexion_degrees"]=knee_ranges
	result["observed_duration_s"]=duration
	result["duration_s"]=duration
	result["requested_nominal_duration_s"]=float(sampled.size())/OBSERVATION_HZ
	result["render_fraction_range"]=[fraction_min,fraction_max]
	result["distinct_observed_physical_states"]=physical_frames.size()
	result["native_stance_knee_flexion_median_degrees"]={"Left":_median(stance_knees.Left),"Right":_median(stance_knees.Right)}
	result["heel_toe_weighted_skin_contact"]={"maximum_skin_to_target_pivot_gap_m":rocker_error,"maximum_world_contact_patch_xz_speed_mps":rocker_xz_speed,"contact_intervals":rocker_count,"intervals_by_patch":rocker_types}
	gait_results.append(result)
	_check(mode+".production_input_actual_speed_and_ground_support",maximum_speed_error<.015 and floor_all and sampled.size()>=SAMPLE_TICKS-2,{"speed_error_mps":maximum_speed_error,"all_supported":floor_all,"samples":sampled.size()})
	if selected_physics_hz<OBSERVATION_HZ:_check(mode+".subphysics_render_fractions_are_actually_observed",fraction_max-fraction_min>.45 and physical_frames.size()<sampled.size()*.8,{"fractions":[fraction_min,fraction_max],"physics_states":physical_frames.size(),"render_samples":sampled.size()})
	_check(mode+".actual_pelvis_vertical_excursion_is_small",float(result.pelvis_height_m.excursion)<=(.035 if mode=="walk" else .055),{"range_m":result.pelvis_height_m,"predeclared_limit_m":.035 if mode=="walk" else .055})
	_check(mode+".actual_pelvis_vertical_velocity_is_bounded",velocity_peak<=(.35 if mode=="walk" else .75),{"peak_mps":velocity_peak,"predeclared_limit_mps":.35 if mode=="walk" else .75})
	_check(mode+".actual_pelvis_vertical_acceleration_has_no_contact_cusp",acceleration_peak<=(8. if mode=="walk" else 20.),{"peak_mps2":acceleration_peak,"predeclared_limit_mps2":8. if mode=="walk" else 20.})
	_check(mode+".actual_native_hip_connections_and_leg_lengths_preserved",maximum_connections<.00002 and maximum_length<.00002,{"maximum_connections_m":maximum_connections,"maximum_length_error_m":maximum_length})
	_check(mode+".knees_bend_forward_and_all_visible_samples_are_finite",minimum_knee>-.0005 and finite and count_min>2,{"minimum_knee_forward_m":minimum_knee,"finite":finite,"minimum_cpu_patch_vertices":count_min})
	_check(mode+".actual_skeleton_feet_still_reach_contact_goals",maximum_contact<.01,{"maximum_contact_error_m":maximum_contact})
	_check(mode+".camera_has_no_added_vertical_bob",float(result.camera_eye_height_m.excursion)<.0001,{"camera_eye_range_m":result.camera_eye_height_m})
	_check(mode+".supporting_knees_do_not_stay_in_deep_crouch",_median(stance_knees.Left)<=(35. if mode=="walk" else 40.) and _median(stance_knees.Right)<=(35. if mode=="walk" else 40.),{"stance_median_degrees":result.native_stance_knee_flexion_median_degrees,"predeclared_support_median_limit_degrees":35. if mode=="walk" else 40.,"scope":"Project pose-design guard against solving reduced bob by permanent deep crouch; not a measured human motion distribution."})
	if not before_bob_replay:_check(mode+".actual_weighted_heel_toe_patches_remain_at_planted_pivots",rocker_count>20 and int(rocker_types.Heel)>5 and int(rocker_types.Toe)>10 and rocker_error<.005 and rocker_xz_speed<.025,result.heel_toe_weighted_skin_contact)
	for side: String in ["Left","Right"]:
		_check(mode+"."+side+"_world_bone_and_weighted_sole_flat_stance_remain_planted",int(stance_counts[side])>40 and float(maximum_bone_xz_slip[side])<.025 and float(maximum_sole_xz_slip[side])<.025 and float(sole_y_ranges[side].excursion)<.002,{"flat_stance_intervals":stance_counts[side],"bone_xz_maximum_mps":maximum_bone_xz_slip[side],"weighted_sole_xz_maximum_mps":maximum_sole_xz_slip[side],"weighted_sole_world_height_m":sole_y_ranges[side],"criterion":"Native ankle and CPU shoe sole centroid horizontal speed<25mmps while both frames are flat. Vertical range<2mm permits actual flatfloor capsule safe-margin quantization without dividing that noise by120Hzdt. Whole3D speed remains recorded separately."})

func _trial(mode: String,speed: float) -> void:
	await _place(Vector3(0,.08,0));player.walk_speed_mps=speed;player.run_speed_mps=speed
	_keys(["move_forward","move_fast"] if mode=="run" else ["move_forward"])
	await _wait_steps(240);sampled=[];sampling=true;await _wait_steps(SAMPLE_TICKS);sampling=false;_analyse(mode,speed)
	_keys([]);await _wait_steps(90)

func _run() -> void:
	for path: String in ["res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_gait_support.gd","res://scripts/player/exploration_camera.gd","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_human_gait_continuity.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	if before_bob_replay:
		source_hashes.erase("res://scripts/player/human_gait_support.gd")
		for title: String in ["textured_human_rig","textured_human_surface","exploration_avatar","exploration_camera"]:
			source_hashes.erase("res://scripts/player/"+title+".gd")
			var frozen:=FROZEN_ROOT+title+".before_bob.gd.txt";source_hashes[frozen]=FileAccess.get_sha256(frozen)
	_setup_stable();await _wait_steps(20);await _place(Vector3(0,.08,0))
	surface=avatar._textured_surface;human=surface.rig;skeleton=surface.skeleton
	var frame:=avatar.global_transform.affine_inverse()*skeleton.global_transform
	for side: String in ["Left","Right"]:
		var hip: Vector3=(frame*human._rest_global[human._find(side+"Thigh")]).origin;var knee: Vector3=(frame*human._rest_global[human._find(side+"Shin")]).origin;var ankle: Vector3=(frame*human._rest_global[human._find(side+"Foot")]).origin
		native_dimensions[side]={"rest_hip_avatar_m":hip,"rest_knee_avatar_m":knee,"rest_ankle_avatar_m":ankle,"thigh_m":hip.distance_to(knee),"shin_m":knee.distance_to(ankle),"leg_m":hip.distance_to(knee)+knee.distance_to(ankle)}
	native_dimensions["pelvis_rest_avatar_m"]=(frame*human._rest_global[human._find("Pelvis")]).origin
	_prepare_skin_patches();await _trial("walk",1.4);await _trial("run",3.5)
	var same:=true
	for path: String in source_hashes:same=same and FileAccess.get_sha256(path)==source_hashes[path]
	_check("source_bindings_unchanged",same)
	_check("original_capsule_and_physics_roots_preserved",_capsule()==initial_capsule and avatar.find_children("*","CollisionObject3D",true,false).is_empty())
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;sampling=false;_keys([])
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var report:={"task":"EXP30_PRODUCTION_HUMAN_GAIT_CONTINUITY","replay_before_bob":before_bob_replay,"result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"model_id":surface.model_id if is_instance_valid(surface) else "","physics_hz":Engine.physics_ticks_per_second,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"trials":gait_results,"source_sha256":source_hashes,"scope":"Actual production controller Input actions and weighted native skeleton/CPU sparse skin at120Hz in isolated flat fixture. Steady4seconds each walk/run after2secondsettle. Numeric motion design limits, not OS input, native pixels, motion capture, terrain/turn/start-stop or subjective realism acceptance. Body/camera heights use actual displayed root, excluding submillimetre physics-floor settling/interpolation. Sparse sole centroid excludes contact boundaries. No phase/pose assignment. Frozen replay redirects only three human source preload paths in temporary copies."}
	report["requested_render_cap_hz"]=OBSERVATION_HZ
	report["scope"]="Actual production controller Input actions and weighted native skeleton/CPU sparse skin in isolated flat fixture. Requested120renderframes/s;480 consecutive actual late-render observations after240render-frame settle for eachwalk/run. Physics30/60/120Hz is recorded independently; everyrender is sampled, including repeatedphysicalstates. Derivatives use actual engine renderdelta. Body/camera heights use actual displayed root, excluding physics-floor settling. Flatankle/sole androckingheel/toepatch contacts are separately measured. Numeric motion design limits, not OS input, nativepixels, motioncapture, terrain/start-stop or subjective realism acceptance. No phase/pose assignment. Frozen replay redirects three human source preload paths plus their original camera in temporarycopies. Headless fixed-fps is simulation acceleration and not performance evidence."
	report["native_dimensions"]=native_dimensions
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write continuity report");quit(2);return
	file.store_string(JSON.stringify(_json(report),"  ")+"\n");file.close();print("HUMAN_GAIT_CONTINUITY_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)

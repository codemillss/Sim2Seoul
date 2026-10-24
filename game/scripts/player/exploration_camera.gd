extends "res://scripts/player/camera_rig.gd"
## The exploration leaf owns camera transforms once. Older milestone rigs stay fixed.
## Physics solves obstruction; render frames interpolate only collision-tested paths.
## See Godot's advanced_physics_interpolation and PhysicsDirectSpaceState3D docs.
@export var exploration_far_m := 1400.0
var safe_distance := 4.5
var rendered_frames := 0
var transition_snaps := 0
var _previous_pose := Transform3D.IDENTITY
var _physics_pose := Transform3D.IDENTITY
var _pose_ready := false
var _transition_clear := true
var _reset_pending := true
var _query: PhysicsShapeQueryParameters3D
var _avatar_root: Node3D
var _avatar_proxy: Node3D
var _previous_avatar_pose := Transform3D.IDENTITY
var _physics_avatar_pose := Transform3D.IDENTITY
var _render_fraction := 1.0
var _facility_mode := false
var _moving_attachment := false
var _roof_camera_hint: Dictionary={}
var _roof_hint_physics_frame := -100
var _roof_camera_fallback := false
var _roof_pivot_offset_m := 0.0
var _roof_fallback_count := 0
var _roof_fallback_reason := "no_hint"
const HUMAN_PIVOT_M := 1.20
const HUMAN_DISTANCE_M := 3.40
const HUMAN_PITCH_DEGREES := -7.0
var _joint_nodes: Array[Node3D] = []
var _previous_joint_poses: Array[Transform3D] = []
var _physics_joint_poses: Array[Transform3D] = []
var _previous_foot_goals: Dictionary = {}
var _physics_foot_goals: Dictionary = {}
var _previous_gait_state: Dictionary = {}
var _physics_gait_state: Dictionary = {}
var _previous_sandbox_state: Dictionary = {}
var _physics_sandbox_state: Dictionary = {}
const COMBAT_POSES := preload("res://scripts/player/human_combat_poses.gd")
const ROOF_MAX_PIVOT_RAISE_M := 1.2
const ROOF_MIN_RETRY_DISTANCE_M := 1.8
const ROOF_RESTORE_DISTANCE_M := 1.9

class AvatarRenderProxy extends Node3D:
	# Restore simulation-space joint globals before the player, gait and
	# facility controllers run. Pausing retains the last displayed pose.
	var owner_rig: Node3D
	func _physics_process(_delta: float) -> void:
		transform=Transform3D.IDENTITY
		if is_instance_valid(owner_rig):owner_rig._restore_physics_joints()

func _init() -> void:
	pitch_min_degrees = -65.0
	pitch_max_degrees = 20.0
	# At rest the eye is 1.20 + sin(7deg)*3.40 = 1.614m above the feet.
	# Focus on the upper back rather than raising the whole camera overhead.
	pivot_height_m = HUMAN_PIVOT_M
	default_distance_m = HUMAN_DISTANCE_M
	default_pitch_degrees = HUMAN_PITCH_DEGREES

func _ready() -> void:
	super._ready()
	# SpringArm normally moves Camera itself each physics tick. Disable that owner
	# before using our custom collision solution and render interpolation.
	arm.set_physics_process_internal(false)
	# Capture after the player (0), facility visit (1) and avatar gait (2).
	process_physics_priority=3
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = 0.08
	camera.fov = 62.0
	apply_exploration_view_distance()
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = arm.shape
	_query.exclude = [target.get_rid()]
	_query.margin = 0.015

func apply_exploration_view_distance() -> void:
	# The inherited quality preset has a 200m cutoff; call after apply_quality too.
	if is_instance_valid(camera):camera.far = exploration_far_m

func use_human_eye_view() -> void:
	# A deliberate on-foot reset. Vehicle/room controllers still save/restore
	# their own camera and never inherit a continuously forced human pivot.
	_restore_physics_joints()
	pivot_height_m=HUMAN_PIVOT_M
	pitch=deg_to_rad(HUMAN_PITCH_DEGREES)
	requested_distance=HUMAN_DISTANCE_M
	current_distance=HUMAN_DISTANCE_M
	skip_motion=true
	snap_to_target_pose()

func set_roof_camera_hint(hint: Dictionary) -> void:
	# A live roof helper refreshes or clears this every physics tick. Never
	# retain a recommendation across an unrelated room, recovery or street.
	_roof_camera_hint={};_roof_hint_physics_frame=Engine.get_physics_frames()
	if hint.is_empty():return
	var minimum: Variant=hint.get("minimum_pivot_y_world")
	var maximum: Variant=hint.get("maximum_raise_m",ROOF_MAX_PIVOT_RAISE_M)
	if not (minimum is float or minimum is int) or not (maximum is float or maximum is int):return
	if not is_finite(float(minimum)) or not is_finite(float(maximum)):return
	if float(maximum)<=0.0 or float(maximum)>ROOF_MAX_PIVOT_RAISE_M:return
	_roof_camera_hint={"minimum_pivot_y_world":float(minimum),"maximum_raise_m":float(maximum),"building_id":String(hint.get("building_id","")),"basis":String(hint.get("basis",""))}

func _sphere_clear_world(point: Vector3) -> bool:
	_query.transform=Transform3D(Basis.IDENTITY,point);_query.motion=Vector3.ZERO
	return get_world_3d().direct_space_state.intersect_shape(_query,1).is_empty()

func _roof_retry(origin: Vector3,axis: Vector3) -> Dictionary:
	if _roof_camera_hint.is_empty():_roof_fallback_reason="no_hint";return {}
	if Engine.get_physics_frames()-_roof_hint_physics_frame>2:_roof_fallback_reason="stale_hint";return {}
	if target.get("interior_active")==true and target.get("interior_ceiling_unbounded")!=true:
		_roof_fallback_reason="ordinary_interior";return {}
	var offset: float=float(_roof_camera_hint.minimum_pivot_y_world)-origin.y
	if offset<=.001 or offset>minf(ROOF_MAX_PIVOT_RAISE_M,float(_roof_camera_hint.maximum_raise_m))+.001:
		_roof_fallback_reason="hint_height_outside_raise_limit";return {}
	var raised := origin+Vector3.UP*offset
	# cast_motion ignores starting penetration. Inspect both endpoints and
	# the complete vertical corridor before trying a raised camera cast.
	if not _sphere_clear_world(origin) or not _sphere_clear_world(raised):
		_roof_fallback_reason="pivot_sphere_blocked";return {}
	_query.transform=Transform3D(Basis.IDENTITY,origin);_query.motion=raised-origin
	if get_world_3d().direct_space_state.cast_motion(_query)[0]<.99999:
		_roof_fallback_reason="vertical_corridor_blocked";return {}
	_query.transform=Transform3D(Basis.IDENTITY,raised);_query.motion=axis*requested_distance
	var fractions: PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(_query)
	var distance := maxf(0.0,requested_distance*fractions[0]-arm.margin)
	if fractions[0]>=.99999:distance=requested_distance
	if distance<ROOF_MIN_RETRY_DISTANCE_M:
		_roof_fallback_reason="raised_cast_still_too_close";return {}
	if not _sphere_clear_world(raised+axis*distance):
		_roof_fallback_reason="raised_eye_sphere_blocked";return {}
	_roof_fallback_reason="accepted"
	return {"origin":raised,"offset_m":offset,"safe_distance_m":distance}

func reset_orientation() -> void:
	super.reset_orientation()
	_reset_pending = true

func _physics_process(delta: float) -> void:
	_solve_pose(delta,true)

func snap_to_target_pose() -> void:
	# A menu can move the player while this pausable rig has no physics ticks.
	# Resolve the same collision-safe pose now and collapse the render history.
	_reset_pending=true
	_solve_pose(0.0,false)

func _has_drawable(node: Node) -> bool:
	if node is GeometryInstance3D:return true
	for child in node.get_children():
		if _has_drawable(child):return true
	return false

func _has_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:return true
	for child in node.get_children():
		if _has_collider(child):return true
	return false

func _prepare_avatar_proxy() -> void:
	var avatar := target.get_node_or_null("Visual/ExplorationAvatar") as Node3D
	if avatar==null or avatar==_avatar_root:return
	_release_avatar_proxy()
	_avatar_root=avatar
	_avatar_proxy=AvatarRenderProxy.new();_avatar_proxy.name="RenderProxy";_avatar_proxy.owner_rig=self
	_avatar_proxy.process_mode=Node.PROCESS_MODE_PAUSABLE
	_avatar_proxy.process_physics_priority=-100
	_avatar_proxy.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	avatar.add_child(_avatar_proxy)
	# Keep the public avatar node and its animation state in simulation space.
	# Only drawable branches move beneath the presentation-only offset; cached
	# limb references and their local transforms remain unchanged.
	for child in avatar.get_children():
		if child==_avatar_proxy or not child is Node3D or _has_collider(child) or not _has_drawable(child):continue
		child.reparent(_avatar_proxy,false)
	_avatar_proxy.transform=Transform3D.IDENTITY
	_previous_avatar_pose=avatar.global_transform
	_physics_avatar_pose=avatar.global_transform
	_joint_nodes.clear();_previous_joint_poses.clear();_physics_joint_poses.clear()
	var joints: Variant=avatar.get("_joints")
	if joints is Dictionary:
		for joint: Variant in joints.values():
			if joint is Node3D and is_instance_valid(joint):_joint_nodes.append(joint)
	var pelvis: Variant=avatar.get("_pelvis")
	if pelvis is Node3D and is_instance_valid(pelvis):_joint_nodes.append(pelvis)
	_capture_joint_poses(true)
	_reset_pending=true

func _release_avatar_proxy() -> void:
	_restore_physics_joints()
	if is_instance_valid(_avatar_proxy):
		_avatar_proxy.transform=Transform3D.IDENTITY
		if is_instance_valid(_avatar_root) and not _avatar_root.is_queued_for_deletion():
			for child in _avatar_proxy.get_children():child.reparent(_avatar_root,false)
		_avatar_proxy.queue_free()
	_avatar_proxy=null;_avatar_root=null
	_joint_nodes.clear();_previous_joint_poses.clear();_physics_joint_poses.clear()
	_previous_foot_goals.clear();_physics_foot_goals.clear()
	_previous_gait_state.clear();_physics_gait_state.clear()
	_previous_sandbox_state.clear();_physics_sandbox_state.clear()

func _restore_physics_joints() -> void:
	# Rendered joint interpolation must never feed back into the next IK step,
	# physics-time hand contacts, or an independently controlled ride pose.
	for index: int in range(mini(_joint_nodes.size(),_physics_joint_poses.size())):
		if is_instance_valid(_joint_nodes[index]):_joint_nodes[index].transform=_physics_joint_poses[index]
	if is_instance_valid(_avatar_root):
		_avatar_root.remove_meta("render_gait_foot_goals_world");_avatar_root.remove_meta("render_gait_state")
		_avatar_root.remove_meta("render_sandbox_pose")

func _capture_joint_poses(reset: bool) -> void:
	var prior_sandbox:=_physics_sandbox_state.duplicate(true);_physics_sandbox_state.clear()
	if is_instance_valid(_avatar_root):
		var pose: Dictionary=_avatar_root.get("_sandbox_authored_pose")
		if not pose.is_empty():_physics_sandbox_state={"kind":String(pose.kind),"phase":float(pose.phase),"weight":float(pose.weight)}
	_previous_sandbox_state=_physics_sandbox_state.duplicate() if reset or prior_sandbox.is_empty() else prior_sandbox
	var prior_gait:=_physics_gait_state.duplicate();_physics_gait_state.clear()
	if is_instance_valid(_avatar_root):
		for field: String in ["stride_phase","walk_weight","_run_weight","_stance_fraction","_cycle_distance_m"]:_physics_gait_state[field]=float(_avatar_root.get(field))
	_previous_gait_state=_physics_gait_state.duplicate() if reset or prior_gait.is_empty() else prior_gait
	var prior_feet:=_physics_foot_goals.duplicate();_physics_foot_goals.clear();_previous_foot_goals.clear()
	if is_instance_valid(_avatar_root):
		for side: String in ["Left","Right"]:
			var joints: Dictionary=_avatar_root.get("_joints")
			var foot:=joints.get(side+"Foot") as Node3D
			if not is_instance_valid(foot):continue
			_physics_foot_goals[side]=foot.global_position
			_previous_foot_goals[side]=foot.global_position if reset or not prior_feet.has(side) else prior_feet[side]
	var previous: Array[Transform3D]=_physics_joint_poses.duplicate()
	_previous_joint_poses.clear();_physics_joint_poses.clear()
	for index: int in range(_joint_nodes.size()):
		var joint:=_joint_nodes[index]
		var pose: Transform3D=joint.transform if is_instance_valid(joint) else Transform3D.IDENTITY
		_physics_joint_poses.append(pose)
		_previous_joint_poses.append(pose if reset or index>=previous.size() else previous[index])

func _publish_joint_poses(fraction: float) -> void:
	for index: int in range(_joint_nodes.size()):
		if not is_instance_valid(_joint_nodes[index]) or index>=_physics_joint_poses.size():continue
		_joint_nodes[index].transform=_previous_joint_poses[index].interpolate_with(_physics_joint_poses[index],clampf(fraction,0.,1.))
	if is_instance_valid(_avatar_root):
		_avatar_root.remove_meta("render_sandbox_pose")
		var current_combat: Dictionary=_avatar_root.get("_sandbox_authored_pose")
		var combat_active:=not _physics_sandbox_state.is_empty() and not current_combat.is_empty() and not _facility_mode and not _moving_attachment
		if combat_active:
			var kind:=String(_physics_sandbox_state.kind);var phase:=float(_physics_sandbox_state.phase);var weight:=float(_physics_sandbox_state.weight)
			if not _previous_sandbox_state.is_empty() and String(_previous_sandbox_state.kind)==kind:
				phase=lerpf(float(_previous_sandbox_state.phase),phase,clampf(fraction,0.,1.));weight=lerpf(float(_previous_sandbox_state.weight),weight,clampf(fraction,0.,1.))
			_avatar_root.set_meta("render_sandbox_pose",COMBAT_POSES.sample(kind,phase,weight))
		# Interpolated thigh/shin rotations draw a small FK arc at the ankle.
		# Solve the native legs toward linearly interpolated physical endpoints,
		# so a planted heel/toe stays planted between the 30Hz physics steps.
		var goals:={}
		for side: String in _physics_foot_goals:goals[side]=Vector3(_previous_foot_goals[side]).lerp(Vector3(_physics_foot_goals[side]),clampf(fraction,0.,1.))
		_avatar_root.set_meta("render_gait_foot_goals_world",goals)
		if not _physics_gait_state.is_empty() and String(_avatar_root.get("state")) in ["walk","run","idle"] and not _facility_mode and not _moving_attachment:
			var gait:={};var phase_before: float=_previous_gait_state.stride_phase
			gait.stride_phase=phase_before+fposmod(float(_physics_gait_state.stride_phase)-phase_before,TAU)*clampf(fraction,0.,1.)
			for field: String in ["walk_weight","_run_weight","_stance_fraction","_cycle_distance_m"]:gait[field]=lerpf(float(_previous_gait_state[field]),float(_physics_gait_state[field]),clampf(fraction,0.,1.))
			_avatar_root.set_meta("render_gait_state",gait)
			var pelvis:=_avatar_root.get("_pelvis") as Node3D
			if not combat_active:pelvis.position.y=float(_avatar_root.get_script().get_script_constant_map().HIP_Y)+float(_avatar_root.call("gait_support_wave",gait.stride_phase,gait._run_weight,gait.walk_weight))
			if String(_avatar_root.get("state")) in ["walk","run"] or float(gait.walk_weight)>.001:
				for side: String in ["Left","Right"]:
					var point: Vector3=_avatar_root.call("sample_gait_foot",side,float(gait.stride_phase)+(PI if side=="Right" else 0.),float(gait._run_weight),float(gait.walk_weight),float(gait._stance_fraction),float(gait._cycle_distance_m))
					goals[side]=_avatar_proxy.global_transform*point
				_avatar_root.set_meta("render_gait_foot_goals_world",goals)

func _publish_avatar_pose(pose: Transform3D) -> void:
	if is_instance_valid(_avatar_proxy) and is_instance_valid(_avatar_root):
		_avatar_proxy.global_transform=pose

func _solve_pose(delta: float, physics_step: bool) -> void:
	if _query == null:return
	# A recovery can occur after the movement signal's follow callback, or
	# while paused. Every publication resolves the latest physical target.
	if target.recoveries!=previous_recoveries:
		previous_recoveries=target.recoveries
		reset_orientation()
	global_position=target.global_position+Vector3.UP*pivot_height_m
	rotation=Vector3(pitch,yaw,0)
	arm.spring_length=requested_distance
	_prepare_avatar_proxy()
	var controlled: bool=target.get("facility_control")==true
	# Rides retain the player's collision capsule but their native vehicle
	# controller moves it. Fixed eating/shower/exercise props instead need the
	# current physical hands. Do not make every controlled passenger bypass
	# presentation interpolation as though it were a stationary activity.
	var moving_attachment: bool=controlled and not target.is_physics_processing() and is_instance_valid(_avatar_root) and String(_avatar_root.get("_activity_kind")) in ["","rope"]
	var fixed_activity: bool=controlled and not moving_attachment
	if fixed_activity!=_facility_mode or moving_attachment!=_moving_attachment:
		_facility_mode=fixed_activity;_moving_attachment=moving_attachment;_reset_pending=true
	# An 84m/s aircraft legitimately moves 2.8m per 30Hz tick. Its explicit
	# mount/recovery/teleport paths already snap the history when required.
	if not _moving_attachment and _pose_ready and is_instance_valid(_avatar_root) and _physics_avatar_pose.origin.distance_to(_avatar_root.global_position)>2.0:_reset_pending=true
	var origin := global_position
	var basis := global_basis.orthonormalized()
	var axis := basis.z
	_query.collision_mask = arm.collision_mask
	_query.transform = Transform3D(Basis.IDENTITY, origin)
	_query.motion = axis * requested_distance
	var fractions := get_world_3d().direct_space_state.cast_motion(_query)
	safe_distance = maxf(0.0, requested_distance * fractions[0] - arm.margin)
	# A margin applies only on contact; open space retains the requested zoom.
	if fractions[0] >= 0.99999:safe_distance = requested_distance
	_roof_camera_fallback=false;_roof_pivot_offset_m=0.0;_roof_fallback_reason="normal_cast_clear"
	if safe_distance<ROOF_MIN_RETRY_DISTANCE_M and requested_distance>=2.0:
		var retry := _roof_retry(origin,axis)
		if not retry.is_empty():
			origin=retry.origin;global_position=origin;safe_distance=float(retry.safe_distance_m)
			_roof_camera_fallback=true;_roof_pivot_offset_m=float(retry.offset_m);_roof_fallback_count+=1
			# Expansion from a former 0.35m wall contact must not leave a
			# validated wide view hidden behind the slow expansion rate.
			current_distance=minf(safe_distance,maxf(current_distance,ROOF_RESTORE_DISTANCE_M))
	current_distance = minf(safe_distance, current_distance + expansion_mps * delta)
	if _overlaps_at(current_distance):
		var low := 0.0
		var high := current_distance
		for iteration in range(14):
			var middle := (low + high) * 0.5
			if _overlaps_at(middle):high = middle
			else:low = middle
		current_distance = maxf(low - 0.01, 0.0)
		clearance_corrections += 1
	var next_pose := Transform3D(basis, origin + axis * current_distance)
	# Sphere casts ignore initial overlap, so explicitly inspect the old eye too.
	# On newly blocked or teleported transitions, immediately publish the safe eye.
	_transition_clear = _pose_ready and not _reset_pending
	if _transition_clear:
		_query.transform = Transform3D(Basis.IDENTITY, _physics_pose.origin)
		_query.motion = next_pose.origin - _physics_pose.origin
		_transition_clear = get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()
		if _transition_clear and not _query.motion.is_zero_approx():
			_transition_clear = get_world_3d().direct_space_state.cast_motion(_query)[0] >= 0.99999
	if _transition_clear:
		_previous_pose = _physics_pose
		_previous_avatar_pose = _physics_avatar_pose
	else:
		_previous_pose = next_pose
		if is_instance_valid(_avatar_root):_previous_avatar_pose=_avatar_root.global_transform
		if _pose_ready:transition_snaps += 1
	_physics_pose = next_pose
	if is_instance_valid(_avatar_root):_physics_avatar_pose=_avatar_root.global_transform
	# The local limb poses need the same rendered time as their root. Fixed
	# eating/weights/shower props instead retain current physical hand contact.
	if not physics_step:
		# A paused portal/menu snap may carry an old displayed root offset.
		# Keep freshly authored activity joints, reset only that root before
		# collapsing the new world-space contact history.
		if is_instance_valid(_avatar_proxy):_avatar_proxy.transform=Transform3D.IDENTITY
		if is_instance_valid(_avatar_root):_avatar_root.remove_meta("render_gait_foot_goals_world");_avatar_root.remove_meta("render_gait_state")
	_capture_joint_poses(not _transition_clear or _facility_mode)
	# Live activity props use current physical hand positions. A fixed user
	# keeps that pose while the camera can still orbit normally.
	if _facility_mode:_previous_avatar_pose=_physics_avatar_pose
	_pose_ready = true
	_reset_pending = false
	camera.global_transform = next_pose
	# Physics observers see unshifted joint globals. Explicit portal/menu snaps
	# also restore the presentation immediately, without waiting for a tick.
	_publish_avatar_pose(_physics_avatar_pose)
	if current_distance < 1.5:target.get_node("Visual").visible = false
	elif current_distance > 1.8 or (_roof_camera_fallback and current_distance>=ROOF_MIN_RETRY_DISTANCE_M):target.get_node("Visual").visible = true
	if physics_step:
		observed_ticks += 1
		camera_stepped.emit(delta)

func _process(_delta: float) -> void:
	if not _pose_ready:return
	# Keeping the eye independent avoids inherited parent motion being applied twice
	# to an interpolated global pose. Rotation uses quaternion shortest-path slerp.
	_render_fraction=clampf(Engine.get_physics_interpolation_fraction(),0.0,1.0)
	camera.global_transform = _render_pose(_render_fraction)
	_publish_avatar_pose(_previous_avatar_pose.interpolate_with(_physics_avatar_pose,_render_fraction))
	# Equipment still publishes current local pedal/handle/seat transforms.
	# Keep attached limbs on that same clock until those local props interpolate;
	# their complete moving body and the camera continue to share render time.
	_publish_joint_poses(1.0 if _facility_mode or _moving_attachment else _render_fraction)
	rendered_frames += 1

func _render_pose(fraction: float) -> Transform3D:
	return _previous_pose.interpolate_with(_physics_pose, clampf(fraction, 0.0, 1.0))

func snapshot() -> Dictionary:
	var result := super.snapshot()
	result["hit_length"] = safe_distance
	result["far"] = camera.far
	result["rendered_frames"] = rendered_frames
	result["transition_snaps"] = transition_snaps
	result["interpolation_transition_clear"] = _transition_clear
	result["transform_owner"] = "exploration_camera"
	result["avatar_render_proxy_ready"]=is_instance_valid(_avatar_proxy)
	result["avatar_render_proxy_path"]=String(_avatar_proxy.get_path()) if is_instance_valid(_avatar_proxy) else ""
	result["render_fraction"]=_render_fraction
	result["render_visual_anchor"]=[_avatar_proxy.global_position.x,_avatar_proxy.global_position.y,_avatar_proxy.global_position.z] if is_instance_valid(_avatar_proxy) else []
	result["physics_visual_anchor"]=[_physics_avatar_pose.origin.x,_physics_avatar_pose.origin.y,_physics_avatar_pose.origin.z]
	result["previous_visual_anchor"]=[_previous_avatar_pose.origin.x,_previous_avatar_pose.origin.y,_previous_avatar_pose.origin.z]
	result["visual_root_physics_owned"]=true
	result["avatar_activity_pose_current"]=_facility_mode
	result["moving_attachment_interpolated"]=_moving_attachment
	result["roof_camera_fallback"]=_roof_camera_fallback
	result["roof_pivot_offset_m"]=_roof_pivot_offset_m
	result["roof_fallback_count"]=_roof_fallback_count
	result["roof_fallback_reason"]=_roof_fallback_reason
	result["roof_camera_hint"]=_roof_camera_hint.duplicate()
	result["joint_interpolation_ready"]=_joint_nodes.size()>0 and _joint_nodes.size()==_physics_joint_poses.size()
	result["joint_interpolation_count"]=_joint_nodes.size()
	result["joint_presentation_policy"]="current_equipment_contacts" if _facility_mode or _moving_attachment else "interpolated_onfoot_joints"
	result["human_eye_reference_m"]=HUMAN_PIVOT_M+sin(deg_to_rad(-HUMAN_PITCH_DEGREES))*HUMAN_DISTANCE_M
	return result

func _exit_tree() -> void:_release_avatar_proxy()

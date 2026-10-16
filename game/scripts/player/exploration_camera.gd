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

func _init() -> void:
	pitch_min_degrees = -65.0
	pitch_max_degrees = 20.0
	default_pitch_degrees = -18.0

func _ready() -> void:
	super._ready()
	# SpringArm normally moves Camera itself each physics tick. Disable that owner
	# before using our custom collision solution and render interpolation.
	arm.set_physics_process_internal(false)
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

func reset_orientation() -> void:
	super.reset_orientation()
	_reset_pending = true

func _physics_process(delta: float) -> void:
	if _query == null:return
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
	else:
		_previous_pose = next_pose
		if _pose_ready:transition_snaps += 1
	_physics_pose = next_pose
	_pose_ready = true
	_reset_pending = false
	camera.global_transform = next_pose
	if current_distance < 1.5:target.get_node("Visual").visible = false
	elif current_distance > 1.8:target.get_node("Visual").visible = true
	observed_ticks += 1
	camera_stepped.emit(delta)

func _process(_delta: float) -> void:
	if not _pose_ready:return
	# Keeping the eye independent avoids inherited parent motion being applied twice
	# to an interpolated global pose. Rotation uses quaternion shortest-path slerp.
	camera.global_transform = _render_pose(Engine.get_physics_interpolation_fraction())
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
	return result

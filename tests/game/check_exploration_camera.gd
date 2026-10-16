extends SceneTree
## Synthetic physics regression for the exploration camera, with no city-data dependency.
class FixturePlayer extends CharacterBody3D:
	signal physics_stepped(delta: float)
	var recoveries := 0
	var walking := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		velocity.x = walking.x
		velocity.z = walking.z
		if velocity.y > 0.0 or not is_on_floor():velocity.y -= 9.8 * delta
		move_and_slide()
		physics_stepped.emit(delta)

var world: Node3D
var player: FixturePlayer
var rig: Node3D
var wall: StaticBody3D
var failures := []
var cases := []
var output_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output_path = arg.trim_prefix("--result=")
	Engine.max_fps = 144
	_run.call_deferred()

func _box(title: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = title
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	return body

func _check(condition: bool, message: String) -> void:
	if not condition:failures.append(message)

func _wait(ticks: int) -> void:
	for index in range(ticks):await rig.camera_stepped

func _pose(at: Vector3, yaw_radians := 0.0, pitch_degrees := -18.0) -> void:
	player.walking = Vector3.ZERO
	player.global_position = at
	player.velocity = Vector3.ZERO
	rig.reset_orientation()
	rig.yaw = yaw_radians
	rig.pitch = deg_to_rad(pitch_degrees)
	await _wait(5)

func _eye_overlaps(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rig.arm.shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = rig.arm.collision_mask
	query.exclude = [player.get_rid()]
	return not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _inspect_samples(record: Dictionary) -> void:
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var pose: Transform3D = rig._render_pose(fraction)
		record.samples += 1
		if _eye_overlaps(pose.origin):record.overlaps += 1
		if not pose.origin.is_finite() or not pose.basis.is_finite():record.invalid += 1
		if pose.basis.y.dot(Vector3.UP) <= 0.0:record.inversions += 1
		record.min_y = minf(record.min_y, pose.origin.y)

func _orbit(title: String, ticks: int, degrees_per_tick: float) -> Dictionary:
	var result := {"name":title,"samples":0,"overlaps":0,"invalid":0,"inversions":0,"min_y":INF,"max_step_m":0.0,"max_distance":0.0}
	var previous: Vector3 = rig.camera.global_position
	for index in range(ticks):
		rig.yaw = wrapf(rig.yaw + deg_to_rad(degrees_per_tick), -PI, PI)
		await rig.camera_stepped
		_inspect_samples(result)
		var current: Vector3 = rig._physics_pose.origin
		result.max_step_m = maxf(result.max_step_m, current.distance_to(previous))
		result.max_distance = maxf(result.max_distance, rig.current_distance)
		previous = current
	_check(result.overlaps == 0, title + " eye collision")
	_check(result.invalid == 0 and result.inversions == 0, title + " invalid/inverted pose")
	_check(result.min_y >= 0.19, title + " ground clipping")
	cases.append(result)
	return result

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box("Floor", Vector3(100, 1, 100), Vector3(0, -0.5, 0))
	wall = _box("Wall", Vector3(10, 4, 0.4), Vector3(0, 2, 3))
	_box("CornerReturn", Vector3(0.4, 4, 6), Vector3(-5, 2, 6))
	_box("JumpLintel", Vector3(5, 0.5, 0.5), Vector3(12, 4.5, 3))
	player = FixturePlayer.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	player.position = Vector3(0, 0.02, -10)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var body_shape := CollisionShape3D.new()
	body_shape.shape = capsule
	body_shape.position.y = 0.85
	player.add_child(body_shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	world.add_child(player)
	rig = load("res://scenes/player/camera_rig.tscn").instantiate()
	rig.set_script(load("res://scripts/player/exploration_camera.gd"))
	rig.target_path = NodePath("../Player")
	world.add_child(rig)
	await _wait(10)
	_check(rig.camera.top_level, "camera must own its global transform")
	_check(not rig.arm.is_physics_processing_internal(), "SpringArm second transform owner enabled")
	_check(rig.camera.near >= 0.079 and rig.camera.far >= 1400.0, "exploration clipping planes")
	await _pose(Vector3(0, 0.02, -10))
	var open := await _orbit("open_full_orbit", 360, 1.0)
	_check(open.max_step_m < 0.1, "open orbit has a discontinuous step")
	_check(absf(rig.current_distance - rig.requested_distance) < 0.001, "open zoom unexpectedly restricted")
	await _pose(Vector3(0, 0.02, 0))
	var near_wall_distance: float = rig.current_distance
	_check(near_wall_distance < 3.0 and near_wall_distance > 1.5, "wall camera failed to retract")
	await _orbit("near_wall_orbit", 360, 1.0)
	await _pose(Vector3(-4, 0.02, 1.8), PI)
	await _orbit("corner_orbit", 360, 1.0)
	await _pose(Vector3(0, 0.02, -10), 0.0, rig.pitch_max_degrees)
	await _orbit("lowest_eye_pitch", 180, 2.0)
	await _pose(Vector3(0, 0.02, -10), 0.0, rig.pitch_min_degrees)
	await _orbit("overhead_pitch", 180, 2.0)
	await _pose(Vector3(0, 0.02, -10))
	player.velocity.y = sqrt(2.0 * 9.8 * 3.0)
	var jump := {"name":"three_metre_jump_open","samples":0,"overlaps":0,"invalid":0,"inversions":0,"min_y":INF,"peak_feet_y":0.0,"max_follow_step_m":0.0}
	var previous_eye: Vector3 = rig.camera.global_position
	for index in range(125):
		rig.yaw = wrapf(rig.yaw + deg_to_rad(0.5), -PI, PI)
		await rig.camera_stepped
		_inspect_samples(jump)
		jump.peak_feet_y = maxf(jump.peak_feet_y, player.global_position.y)
		jump.max_follow_step_m = maxf(jump.max_follow_step_m, rig._physics_pose.origin.distance_to(previous_eye))
		previous_eye = rig._physics_pose.origin
	_check(jump.peak_feet_y >= 2.85 and jump.peak_feet_y <= 3.05, "jump fixture did not exercise three metres")
	_check(jump.overlaps == 0 and jump.inversions == 0 and jump.invalid == 0, "jump camera clipped/inverted")
	_check(jump.max_follow_step_m < 0.5, "jump follow excessive frame step")
	cases.append(jump)
	await _pose(Vector3(12, 0.02, 0))
	player.velocity.y = sqrt(2.0 * 9.8 * 3.0)
	var lintel := {"name":"three_metre_jump_near_lintel","samples":0,"overlaps":0,"invalid":0,"inversions":0,"min_y":INF}
	for index in range(125):
		rig.yaw = wrapf(rig.yaw + deg_to_rad(0.5), -PI, PI)
		await rig.camera_stepped
		_inspect_samples(lintel)
	_check(lintel.overlaps == 0 and lintel.inversions == 0 and lintel.invalid == 0, "jump camera clipped lintel")
	cases.append(lintel)
	# Shortest-path rotation must remain continuous as yaw wraps across -PI/PI.
	await _pose(Vector3(0, 0.02, -10), PI - 0.01)
	rig.yaw = -PI + 0.01
	await rig.camera_stepped
	var mid: Transform3D = rig._render_pose(0.5)
	_check(mid.basis.z.dot(Vector3.FORWARD) > 0.94, "yaw wrap interpolated the long way")
	var display_ticks_before: int = rig.rendered_frames
	await create_timer(0.2).timeout
	_check(rig.rendered_frames > display_ticks_before, "render interpolation never ran")
	# A recovery is a hard pose reset, never an interpolated trip across the map.
	player.global_position = Vector3(20, 0.02, -10)
	player.recoveries += 1
	await rig.camera_stepped
	_check(rig._previous_pose.origin.distance_to(rig._physics_pose.origin) < 0.001, "recovery interpolated through scene")
	var record := {"task":"exploration_camera","passed":failures.is_empty(),"failures":failures,"cases":cases,"camera":rig.snapshot(),"scope":"synthetic static physics fixtures; city GPU and human handling are separate"}
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:file.store_string(JSON.stringify(record) + "\n")
	print("EXPLORATION_CAMERA_CHECK ", JSON.stringify(record))
	world.queue_free()
	quit(0 if failures.is_empty() else 1)

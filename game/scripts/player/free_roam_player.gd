extends "res://scripts/player/public_player.gd"
## Extra outdoor movement belongs to the exploration scene, not the W03 source boundary.
## The latest scene registers physical Space as `jump`; historical scenes keep P02 unchanged.
@export_range(0.25, 8.0, 0.25) var jump_height_m := 3.0
var free_roam_enabled := true
var free_roam_bounds := Rect2(-450.0,-460.0,900.0,920.0)
const EDGE_MARGIN_M := 0.4
const SEGMENT_SAMPLE_M := 0.05
const JUMP_ACTION := &"jump"
var _jump_was_pressed := false
var _jump_requires_release := false

func _jump_pressed() -> bool:
	return InputMap.has_action(JUMP_ACTION) and Input.is_action_pressed(JUMP_ACTION)

func require_neutral_input() -> void:
	super.require_neutral_input()
	# No buffered takeoff may survive a menu, settings change, reset or recovery.
	_jump_was_pressed = false
	_jump_requires_release = true

func _physics_process(delta: float) -> void:
	# This is the latest-scene equivalent of P02's controller. P02 always erases
	# grounded vertical velocity, so calling it after setting an impulse loses jumps.
	step_delta = delta
	var jump_held := _jump_pressed()
	var jump_edge := jump_held and not _jump_was_pressed
	_jump_was_pressed = jump_held
	if _jump_requires_release:
		if not jump_held:_jump_requires_release = false
		jump_edge = false
	if not configured:
		velocity = Vector3.ZERO
		physics_stepped.emit(delta)
		return
	if not spawn_valid:spawn_valid = _valid_spawn()
	if not spawn_valid:
		velocity = Vector3.ZERO
		physics_stepped.emit(delta)
		return
	if not global_position.is_finite() or global_position.y<fall_limit_y:
		recover("fall")
		physics_stepped.emit(delta)
		return
	elif not _inside(global_position):
		recover("outside_test_area")
		physics_stepped.emit(delta)
		return
	var intent: Vector2 = router.movement_intent().limit_length(1.0)
	var fast: bool = router.fast_intent()
	if input_latched:
		if intent.length_squared()<0.000001 and not fast and not jump_held:input_latched = false
		intent = Vector2.ZERO
		fast = false
		jump_edge = false
	elif not router.gameplay_enabled:
		jump_edge = false
	last_direction = _direction(intent)
	var speed := run_speed_mps if fast else walk_speed_mps
	velocity.x = last_direction.x*speed
	velocity.z = last_direction.z*speed
	if is_on_floor():
		velocity.y = 0.0
		if jump_edge:
			# Compensate half a gravity step so the discrete apex stays near the
			# exported metre height at the configured physics tick rate.
			velocity.y = sqrt(2.0*gravity_mps2*jump_height_m)+0.5*gravity_mps2*delta
	velocity.y -= gravity_mps2*delta
	if last_direction.length_squared()>0.000001:
		visual.rotation.y = rotate_toward(visual.rotation.y,atan2(-last_direction.x,-last_direction.z),turn_speed_radians*delta)
	move_and_slide()
	physics_stepped.emit(delta)

func _inside(point: Vector3) -> bool:
	if not free_roam_enabled:return super._inside(point)
	if not point.is_finite():return false
	var p:=Vector2(point.x,point.z)
	if not free_roam_bounds.grow(-EDGE_MARGIN_M).has_point(p):return false
	# Preserve the authored private exclusion, including the capsule's footprint.
	if connection_world._contains(p,connection_world.private_cache):return false
	for polygon in connection_world.private_cache:
		for ring in polygon:
			for i in range(ring.size()-1):
				if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,ring[i],ring[i+1]))<EDGE_MARGIN_M*EDGE_MARGIN_M:return false
	return true

func _segment_inside(direction: Vector3) -> bool:
	var speed:=run_speed_mps if router.fast_intent() else walk_speed_mps
	var offset:=direction*speed*step_delta
	var samples:=maxi(1,int(ceil(offset.length()/SEGMENT_SAMPLE_M)))
	for i in range(1,samples+1):
		if not _inside(global_position+offset*float(i)/float(samples)):return false
	return true

func _direction(intent: Vector2) -> Vector3:
	var result: Vector3=super._direction(intent)
	if result.is_zero_approx() or not _inside(global_position):return result
	if _segment_inside(result):return result
	boundary_stops+=1
	last_boundary_reason="exploration_edge" if free_roam_enabled else "walk_edge"
	for along in [Vector3(result.x,0,0),Vector3(0,0,result.z)]:
		if not along.is_zero_approx() and _segment_inside(along):return along
	return Vector3.ZERO

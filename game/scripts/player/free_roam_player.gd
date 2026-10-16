extends "res://scripts/player/public_player.gd"
## Extra outdoor movement belongs to the exploration scene, not the W03 source boundary.
## The latest scene registers physical Space as `jump`; historical scenes keep P02 unchanged.
@export_range(0.25, 8.0, 0.25) var jump_height_m := 3.0
var free_roam_enabled := true
var free_roam_bounds := Rect2(-450.0,-460.0,900.0,920.0)
const EDGE_MARGIN_M := 0.4
const SEGMENT_SAMPLE_M := 0.05
const JUMP_ACTION := &"jump"
const MAX_AIR_JUMPS := 1
const SWIM_SPEED_MPS := 3.0
const FLOAT_DEPTH_M := 1.0
const WATER_EXIT_HEIGHT_M := 2.4
signal water_splashed(world_point: Vector3, impact_speed_mps: float)
var _jump_was_pressed := false
var _jump_requires_release := false
var _air_jumps_used := 0
var interior_active := false
var interior_bounds := AABB()
var interior_frame := Transform3D.IDENTITY
var interior_walkable_rect := Rect2()
var _outdoor_recovery := {}
var _water_region: Dictionary = {}
var _water_contacting := false
var _swimming := false
var _water_jump_locked := false
var _water_entries := 0
var _water_exits := 0
var _water_jumps := 0

func begin_interior(point: Vector3, bounds: AABB) -> bool:
	if interior_active or not configured or not point.is_finite() or not bounds.has_point(point):return false
	var before := {"spawn":spawn_transform,"fall_limit":fall_limit_y,"spawn_valid":spawn_valid,"configured":configured}
	interior_active = true
	interior_bounds = bounds
	interior_frame = Transform3D.IDENTITY
	interior_walkable_rect = Rect2()
	fall_limit_y = bounds.position.y - 2.0
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	spawn_valid = _valid_spawn()
	if not spawn_valid:
		interior_active = false
		spawn_transform = before.spawn
		fall_limit_y = before.fall_limit
		spawn_valid = before.spawn_valid
		return false
	_outdoor_recovery = before
	global_transform = spawn_transform
	visual.rotation = Vector3.ZERO
	_air_jumps_used = 0
	clear_water_region()
	require_neutral_input()
	reset_physics_interpolation()
	return true

func end_interior(point: Vector3) -> bool:
	if not interior_active or _outdoor_recovery.is_empty() or not point.is_finite():return false
	var indoor_spawn := spawn_transform
	interior_active = false
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	if not _valid_spawn():
		interior_active = true
		spawn_transform = indoor_spawn
		return false
	global_transform = spawn_transform
	spawn_transform = _outdoor_recovery.spawn
	fall_limit_y = _outdoor_recovery.fall_limit
	configured = _outdoor_recovery.configured
	spawn_valid = _outdoor_recovery.spawn_valid
	_outdoor_recovery = {}
	interior_frame = Transform3D.IDENTITY
	interior_walkable_rect = Rect2()
	visual.rotation = Vector3.ZERO
	_air_jumps_used = 0
	clear_water_region()
	require_neutral_input()
	reset_physics_interpolation()
	return true

func relocate_interior(point: Vector3) -> bool:
	# Lifts hand control back only on a verified landing. Its floor also becomes
	# recovery's destination, so falling upstairs never returns to the lobby.
	if not interior_active or not point.is_finite() or not interior_bounds.has_point(point):return false
	var previous := spawn_transform
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	if not _valid_spawn():
		spawn_transform = previous
		return false
	global_transform = spawn_transform
	spawn_valid = true
	_air_jumps_used = 0
	require_neutral_input();reset_physics_interpolation()
	return true

func set_water_region(region: Dictionary) -> bool:
	if not interior_active or not region.get("id") is String or region.id.is_empty():return false
	var candidate_frame: Variant = region.get("frame")
	var rect: Variant = region.get("rect")
	var bottom: Variant = region.get("floor_y")
	var surface: Variant = region.get("surface_y")
	if not candidate_frame is Transform3D or not rect is Rect2:return false
	if not (bottom is float or bottom is int) or not (surface is float or surface is int):return false
	if not candidate_frame.is_finite() or not candidate_frame.is_equal_approx(interior_frame):return false
	if not candidate_frame.basis.y.is_equal_approx(Vector3.UP):return false
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<1.0 or rect.size.y<1.0:return false
	if interior_walkable_rect==Rect2() or not interior_walkable_rect.encloses(rect.grow(.20)):return false
	if not is_finite(float(bottom)) or not is_finite(float(surface)) or float(surface)-float(bottom)<.5 or float(surface)-float(bottom)>3.0:return false
	var middle: Vector2 = rect.get_center()
	for y in [float(bottom),float(surface)+2.0]:
		if not interior_bounds.has_point(candidate_frame*Vector3(middle.x,y,middle.y)):return false
	clear_water_region()
	_water_region = region.duplicate(true)
	return true

func clear_water_region() -> void:
	if _water_contacting:_water_exits += 1
	_water_region = {};_water_contacting = false;_swimming = false;_water_jump_locked = false

func is_swimming() -> bool:return _swimming

func _submerged(point: Vector3) -> bool:
	if _water_region.is_empty() or not point.is_finite():return false
	var local: Vector3 = _water_region.frame.affine_inverse()*point
	return _water_region.rect.has_point(Vector2(local.x,local.z)) and local.y<float(_water_region.surface_y)-.08 and local.y>=float(_water_region.floor_y)-.35

func water_snapshot() -> Dictionary:
	var registered := not _water_region.is_empty()
	var local := Vector3.ZERO
	if registered:local = _water_region.frame.affine_inverse()*global_position
	return {"registered":registered,"id":_water_region.get("id",""),"swimming":_swimming,"under_surface":_submerged(global_position),
		"depth_m":maxf(0.0,float(_water_region.get("surface_y",0.0))-local.y) if registered else 0.0,"surface_y_world":float(_water_region.get("surface_y",0.0))+(_water_region.frame.origin.y if registered else 0.0),
		"float_target_foot_y_world":float(_water_region.get("surface_y",0.0))-FLOAT_DEPTH_M+(_water_region.frame.origin.y if registered else 0.0),
		"horizontal_speed_mps":Vector2(velocity.x,velocity.z).length(),"vertical_speed_mps":velocity.y,"swim_speed_limit_mps":SWIM_SPEED_MPS,
		"entry_count":_water_entries,"exit_count":_water_exits,"water_jump_count":_water_jumps,"exit_jump_locked":_water_jump_locked}

func relocate_interior_region(point: Vector3, bounds: AABB, frame := Transform3D.IDENTITY, rect := Rect2()) -> bool:
	# A lift may connect the detached room with a source-positioned rooftop.
	# Validate the complete candidate region before replacing the recovery state.
	if not interior_active or not point.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():return false
	if bounds.size.x<=0.0 or bounds.size.y<=0.0 or bounds.size.z<=0.0 or not frame.is_finite():return false
	if absf(frame.basis.determinant()-1.0)>.001 or not frame.basis.is_equal_approx(frame.basis.orthonormalized()):return false
	if not rect.position.is_finite() or not rect.size.is_finite():return false
	if rect!=Rect2() and (rect.size.x<=EDGE_MARGIN_M*2.0 or rect.size.y<=EDGE_MARGIN_M*2.0):return false
	var previous := {"bounds":interior_bounds,"frame":interior_frame,"rect":interior_walkable_rect,"spawn":spawn_transform,"fall_limit":fall_limit_y,"spawn_valid":spawn_valid}
	interior_bounds = bounds;interior_frame = frame;interior_walkable_rect = rect
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	fall_limit_y = bounds.position.y-2.0
	if not _valid_spawn():
		interior_bounds = previous.bounds;interior_frame = previous.frame;interior_walkable_rect = previous.rect
		spawn_transform = previous.spawn;fall_limit_y = previous.fall_limit;spawn_valid = previous.spawn_valid
		return false
	global_transform = spawn_transform
	spawn_valid = true
	_air_jumps_used = 0
	clear_water_region()
	require_neutral_input();reset_physics_interpolation()
	return true

func exterior_contains(point: Vector3) -> bool:
	# Portal return validation must use the selected outdoor boundary even indoors.
	return _inside_outdoors(point)

func _jump_pressed() -> bool:
	return InputMap.has_action(JUMP_ACTION) and Input.is_action_pressed(JUMP_ACTION)

func air_jumps_remaining() -> int:
	return MAX_AIR_JUMPS - _air_jumps_used

func recover(reason: String) -> bool:
	var recovered := super.recover(reason)
	if recovered:
		_air_jumps_used = 0
		if _water_contacting:_water_exits += 1
		_water_contacting = false;_swimming = false;_water_jump_locked = false
	return recovered

func require_neutral_input() -> void:
	super.require_neutral_input()
	# No buffered takeoff may survive a menu, settings change, reset or recovery.
	# Keep spent air jumps: opening a menu in flight must not recharge them.
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
	var submerged := _submerged(global_position)
	if submerged and not _water_contacting:
		_water_entries += 1
		var local: Vector3 = _water_region.frame.affine_inverse()*global_position
		var splash_point: Vector3 = _water_region.frame*Vector3(local.x,float(_water_region.surface_y),local.z)
		water_splashed.emit(splash_point,maxf(0.0,-velocity.y))
	elif not submerged and _water_contacting:
		_water_exits += 1
	_water_contacting = submerged
	if not submerged:_water_jump_locked = false
	_swimming = submerged and not _water_jump_locked
	var speed := run_speed_mps if fast else walk_speed_mps
	if submerged:speed = SWIM_SPEED_MPS
	velocity.x = last_direction.x*speed
	velocity.z = last_direction.z*speed
	var grounded := is_on_floor()
	if grounded:
		_air_jumps_used = 0
		velocity.y = 0.0
	if submerged and jump_edge and not _water_jump_locked:
		# A deliberate water exit replaces vertical speed without spending or
		# refilling the separate outdoor air-jump budget.
		velocity.y = sqrt(2.0*gravity_mps2*WATER_EXIT_HEIGHT_M)+.5*gravity_mps2*delta
		_water_jump_locked = true;_swimming = false;_water_jumps += 1
	elif not submerged and jump_edge and (grounded or _air_jumps_used < MAX_AIR_JUMPS):
		# Walking off a ledge also leaves one air jump. Replace vertical speed
		# rather than stacking impulses, including during a late downward fall.
		if not grounded:_air_jumps_used += 1
		# Compensate half a gravity step so the discrete apex stays near the
		# exported metre height at the configured physics tick rate.
		velocity.y = sqrt(2.0*gravity_mps2*jump_height_m)+0.5*gravity_mps2*delta
	if _swimming:
		var surface_world: float = _water_region.frame.origin.y+float(_water_region.surface_y)
		var target := surface_world-FLOAT_DEPTH_M
		var buoyancy := (target-global_position.y)*20.0-velocity.y*6.0
		velocity.y = clampf(velocity.y+buoyancy*delta,-4.0,4.0)
	else:
		velocity.y -= gravity_mps2*delta
	if last_direction.length_squared()>0.000001:
		visual.rotation.y = rotate_toward(visual.rotation.y,atan2(-last_direction.x,-last_direction.z),turn_speed_radians*delta)
	move_and_slide()
	if is_on_floor():_air_jumps_used = 0
	physics_stepped.emit(delta)

func _inside(point: Vector3) -> bool:
	if interior_active:
		if not point.is_finite() or not interior_bounds.has_point(point):return false
		if interior_walkable_rect==Rect2():return true
		var local: Vector3 = interior_frame.affine_inverse()*point
		return interior_walkable_rect.grow(-EDGE_MARGIN_M).has_point(Vector2(local.x,local.z))
	return _inside_outdoors(point)

func _inside_outdoors(point: Vector3) -> bool:
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

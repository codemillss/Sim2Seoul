extends "res://scripts/player/public_player.gd"
## Extra outdoor movement belongs to the exploration scene, not the W03 source boundary.
## The latest scene registers physical Space as `jump`; historical scenes keep P02 unchanged.
@export_range(0.25, 8.0, 0.25) var jump_height_m := 3.0
var free_roam_enabled := true
var free_roam_bounds := Rect2(-450.0,-460.0,900.0,920.0)
var free_roam_polygon := PackedVector2Array()
const EDGE_MARGIN_M := 0.4
const SEGMENT_SAMPLE_M := 0.05
const JUMP_ACTION := &"jump"
## Negative means unlimited fresh-press air jumps in this exploration sandbox.
const MAX_AIR_JUMPS := -1
const SWIM_SPEED_MPS := 3.0
const FLOAT_DEPTH_M := 1.0
const WATER_EXIT_HEIGHT_M := 2.4
const GROUND_ACCEL_TIME_S := .14
const GROUND_BRAKE_TIME_S := .12
const TURN_ACCEL_RADIANS_S2 := 45.0
signal water_splashed(world_point: Vector3, impact_speed_mps: float)
var _jump_was_pressed := false
var _jump_requires_release := false
var _air_jumps_used := 0
var interior_active := false
var interior_bounds := AABB()
var interior_frame := Transform3D.IDENTITY
var interior_walkable_rect := Rect2()
var interior_ceiling_unbounded := false
var _outdoor_recovery := {}
var _water_region: Dictionary = {}
var _water_contacting := false
var _swimming := false
var _water_jump_locked := false
var _water_entries := 0
var _water_exits := 0
var _water_jumps := 0
var facility_control := false
var pool_preparation_guard: Node3D
var terrain_surface: Node
var _terrain_recovery_rebased := false
var _visual_turn_speed := 0.0
var _motion_previous_position := Vector3.INF
var motion_guard_stops := 0

func bind_terrain_surface(service: Node) -> bool:
	# Root warps the live actor separately. Rebase only the outdoor recovery
	# anchor here, once, so falling on a low street never returns underground.
	if not is_instance_valid(service) or not service.has_method("ground_y_world") or interior_active:return false
	if _terrain_recovery_rebased:return terrain_surface==service
	var base: float=service.ground_y_world(spawn_transform.origin)
	if not is_finite(base):return false
	terrain_surface=service
	spawn_transform.origin.y+=base
	fall_limit_y=spawn_transform.origin.y-3.0
	spawn_valid=false
	_terrain_recovery_rebased=true
	return true

func terrain_ground_y(point: Vector3) -> float:
	return terrain_surface.ground_y_world(point) if is_instance_valid(terrain_surface) else NAN

func _valid_spawn() -> bool:
	if not is_instance_valid(terrain_surface):return super._valid_spawn()
	# Retain the selected exterior/private boundary and the complete capsule.
	# A legacy analytic obstacle interval has flat Y and is unsuitable for a
	# rebased source building; its unchanged native body remains authoritative.
	var point := spawn_transform.origin
	if not _inside(point) or not spawn_transform.basis.is_finite():return false
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP*.25,collision_mask,[get_rid()])
	var ground := space.intersect_ray(ray)
	if ground.is_empty() or ground.normal.dot(Vector3.UP)<cos(floor_max_angle):return false
	var gap: float=point.y-ground.position.y
	if gap<.005 or gap>.20:return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=$CollisionShape.shape
	query.transform=spawn_transform*$CollisionShape.transform
	query.collision_mask=collision_mask;query.exclude=[get_rid()]
	return space.intersect_shape(query,1).is_empty()

func _current_fall_limit_y() -> float:
	if interior_active:return fall_limit_y
	var ground_y := terrain_ground_y(global_position)
	return ground_y-3.0 if is_finite(ground_y) else fall_limit_y

func set_facility_control(enabled: bool) -> void:
	if facility_control==enabled:return
	facility_control=enabled
	velocity=Vector3.ZERO;last_direction=Vector3.ZERO
	# Activities retain the physical capsule and the airborne jump count.
	# Releasing an activity never converts a held movement/Space key to input.
	require_neutral_input()

func begin_interior(point: Vector3, bounds: AABB) -> bool:
	if interior_active or not configured or not point.is_finite() or not bounds.has_point(point):return false
	var before := {"spawn":spawn_transform,"fall_limit":fall_limit_y,"spawn_valid":spawn_valid,"configured":configured}
	interior_active = true
	interior_bounds = bounds
	interior_frame = Transform3D.IDENTITY
	interior_walkable_rect = Rect2()
	interior_ceiling_unbounded = false
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
	set_facility_control(false)
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
	set_facility_control(false)
	spawn_transform = _outdoor_recovery.spawn
	fall_limit_y = _outdoor_recovery.fall_limit
	configured = _outdoor_recovery.configured
	spawn_valid = _outdoor_recovery.spawn_valid
	_outdoor_recovery = {}
	interior_frame = Transform3D.IDENTITY
	interior_walkable_rect = Rect2()
	interior_ceiling_unbounded = false
	visual.rotation = Vector3.ZERO
	_air_jumps_used = 0
	clear_water_region()
	require_neutral_input()
	reset_physics_interpolation()
	return true

func release_rooftop_to_exterior() -> bool:
	# No relocation: preserve the current physical pose and momentum when a
	# source-positioned roof rejoins the outdoor world, including mid-jump.
	if not interior_active or not interior_ceiling_unbounded or _outdoor_recovery.is_empty():return false
	if not global_position.is_finite() or not _inside_outdoors(global_position):return false
	interior_active=false
	spawn_transform=_outdoor_recovery.spawn;fall_limit_y=_outdoor_recovery.fall_limit
	configured=_outdoor_recovery.configured;spawn_valid=_outdoor_recovery.spawn_valid
	_outdoor_recovery={};interior_frame=Transform3D.IDENTITY;interior_walkable_rect=Rect2();interior_ceiling_unbounded=false
	clear_water_region()
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
	set_facility_control(false)
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

func set_outdoor_water_region(region: Dictionary, bounds: AABB, walkable_rect: Rect2) -> bool:
	# Roof helpers register bounded source-positioned water without converting
	# the whole outdoor world into a detached interior or moving the player.
	if interior_active or not configured or not region.get("id") is String or region.id.is_empty():return false
	var frame: Variant=region.get("frame")
	var rect: Variant=region.get("rect")
	var bottom: Variant=region.get("floor_y")
	var surface: Variant=region.get("surface_y")
	if not frame is Transform3D or not rect is Rect2:return false
	if not (bottom is float or bottom is int) or not (surface is float or surface is int):return false
	if not frame.is_finite() or not frame.basis.is_equal_approx(frame.basis.orthonormalized()) or absf(frame.basis.determinant()-1.0)>.001 or not frame.basis.y.is_equal_approx(Vector3.UP):return false
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0.0 or bounds.size.y<=0.0 or bounds.size.z<=0.0:return false
	if not walkable_rect.position.is_finite() or not walkable_rect.size.is_finite() or not walkable_rect.has_area():return false
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<1.0 or rect.size.y<1.0 or not walkable_rect.encloses(rect.grow(.2)):return false
	if not is_finite(float(bottom)) or not is_finite(float(surface)) or float(surface)-float(bottom)<.5 or float(surface)-float(bottom)>3.0:return false
	for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
		for y in [float(bottom),float(surface)+2.0]:
			var point: Vector3=frame*Vector3(corner.x,y,corner.y)
			if not bounds.has_point(point) or not _inside_outdoors(point):return false
	if _water_region.get("id","")==region.id and _water_region.get("frame")==frame:return true
	clear_water_region();_water_region=region.duplicate(true);_water_region["outdoor"]=true
	return true

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

func relocate_interior_region(point: Vector3, bounds: AABB, frame := Transform3D.IDENTITY, rect := Rect2(),ceiling_unbounded := false) -> bool:
	# A lift may connect the detached room with a source-positioned rooftop.
	# Validate the complete candidate region before replacing the recovery state.
	if not interior_active or not point.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():return false
	if bounds.size.x<=0.0 or bounds.size.y<=0.0 or bounds.size.z<=0.0 or not frame.is_finite():return false
	if absf(frame.basis.determinant()-1.0)>.001 or not frame.basis.is_equal_approx(frame.basis.orthonormalized()):return false
	if not rect.position.is_finite() or not rect.size.is_finite():return false
	if rect!=Rect2() and (rect.size.x<=EDGE_MARGIN_M*2.0 or rect.size.y<=EDGE_MARGIN_M*2.0):return false
	if not bounds.has_point(point):return false
	if ceiling_unbounded and (not rect.has_area() or not frame.basis.y.is_equal_approx(Vector3.UP)):return false
	var previous := {"bounds":interior_bounds,"frame":interior_frame,"rect":interior_walkable_rect,"ceiling_unbounded":interior_ceiling_unbounded,"spawn":spawn_transform,"fall_limit":fall_limit_y,"spawn_valid":spawn_valid}
	interior_bounds = bounds;interior_frame = frame;interior_walkable_rect = rect;interior_ceiling_unbounded=ceiling_unbounded
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	fall_limit_y = bounds.position.y-2.0
	if not _valid_spawn():
		interior_bounds = previous.bounds;interior_frame = previous.frame;interior_walkable_rect = previous.rect;interior_ceiling_unbounded=previous.ceiling_unbounded
		spawn_transform = previous.spawn;fall_limit_y = previous.fall_limit;spawn_valid = previous.spawn_valid
		return false
	global_transform = spawn_transform
	set_facility_control(false)
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
	return MAX_AIR_JUMPS if has_unlimited_air_jumps() else maxi(0,MAX_AIR_JUMPS-_air_jumps_used)

func has_unlimited_air_jumps() -> bool:return MAX_AIR_JUMPS<0

func air_jump_count() -> int:return _air_jumps_used

func has_open_sky() -> bool:
	# Source-positioned roofs explicitly opt in after region validation.
	# Detached interiors retain their complete finite volume and physical ceilings.
	return interior_active and interior_ceiling_unbounded

func recover(reason: String) -> bool:
	var recovered := super.recover(reason)
	if recovered:
		set_facility_control(false)
		_air_jumps_used = 0
		if _water_contacting:_water_exits += 1
		_water_contacting = false;_swimming = false;_water_jump_locked = false
	return recovered

func require_neutral_input() -> void:
	super.require_neutral_input()
	_visual_turn_speed=0.0
	# No buffered takeoff may survive a menu, settings change, reset or recovery.
	# Preserve the airborne count; menus never create a new Space press.
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
	# The retained controller owns actual water entry. A jump or fall cannot
	# bypass roof-local swimwear/shower preparation through the visual gate.
	if is_instance_valid(pool_preparation_guard) and not pool_preparation_guard.enforce_player_water_access():
		physics_stepped.emit(delta);return
	if not global_position.is_finite() or global_position.y<_current_fall_limit_y():
		recover("fall")
		physics_stepped.emit(delta)
		return
	elif not _inside(global_position):
		recover("outside_test_area")
		physics_stepped.emit(delta)
		return
	if facility_control:
		velocity=Vector3.ZERO;last_direction=Vector3.ZERO
		physics_stepped.emit(delta)
		return
	var intent: Vector2 = router.movement_intent().limit_length(1.0)
	var fast: bool = router.fast_intent()
	if input_latched:
		if intent.length_squared()<0.000001 and not fast and not jump_held:input_latched = false
		intent = Vector2.ZERO
		fast = false
		# Old movement keys may remain held after a lift/menu. A separate
		# Space-release gate permits a deliberate fresh jump without walking.
	if not router.gameplay_enabled:
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
	var grounded := is_on_floor()
	_apply_horizontal_motion(last_direction*speed,intent,grounded and not submerged,delta)
	if grounded:
		_air_jumps_used = 0
		velocity.y = 0.0
	if submerged and jump_edge and not _water_jump_locked:
		# A deliberate water exit replaces vertical speed independently of the
		# separate fresh-press air-jump count.
		velocity.y = sqrt(2.0*gravity_mps2*WATER_EXIT_HEIGHT_M)+.5*gravity_mps2*delta
		_water_jump_locked = true;_swimming = false;_water_jumps += 1
	elif not submerged and jump_edge and (grounded or has_unlimited_air_jumps() or _air_jumps_used<MAX_AIR_JUMPS):
		# Every fresh press can redirect a fall or continue climbing. Replace
		# vertical speed instead of stacking impulses; held Space never repeats.
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
		_update_visual_heading(atan2(-last_direction.x,-last_direction.z),delta)
	else:_visual_turn_speed=move_toward(_visual_turn_speed,0.,TURN_ACCEL_RADIANS_S2*delta)
	move_and_slide()
	_motion_previous_position=global_position
	if is_instance_valid(pool_preparation_guard):pool_preparation_guard.enforce_player_water_access()
	if is_on_floor():_air_jumps_used = 0
	physics_stepped.emit(delta)

func _offset_inside(offset: Vector3) -> bool:
	var samples:=maxi(1,int(ceil(offset.length()/SEGMENT_SAMPLE_M)))
	for index in range(1,samples+1):
		if not _inside(global_position+offset*float(index)/float(samples)):return false
	return true

func _apply_horizontal_motion(desired: Vector3,intent: Vector2,grounded: bool,delta: float) -> void:
	var before:=Vector3(velocity.x,0,velocity.z)
	# Explicit transitions, controller ownership and boundary refusal always stop
	# immediately. Easing must never turn stale momentum into an edge bypass.
	var transition:=not _motion_previous_position.is_finite() or global_position.distance_to(_motion_previous_position)>2.
	var refused:=intent.length_squared()>.000001 and desired.is_zero_approx()
	var candidate:=desired
	if grounded and not transition and not input_latched and router.gameplay_enabled and not refused:
		var cap:=maxf(walk_speed_mps,maxf(before.length(),desired.length()))
		var braking:=desired.length_squared()<before.length_squared() or before.dot(desired)<0.
		var seconds:=GROUND_BRAKE_TIME_S if braking else GROUND_ACCEL_TIME_S
		candidate=before.move_toward(desired,cap/seconds*delta)
		if desired.is_zero_approx() and candidate.length()<.015:candidate=Vector3.ZERO
	if not _offset_inside(candidate*delta):
		candidate=desired if _offset_inside(desired*delta) else Vector3.ZERO
		motion_guard_stops+=1
	velocity.x=candidate.x;velocity.z=candidate.z

func _update_visual_heading(target_yaw: float,delta: float) -> void:
	var difference:=angle_difference(visual.rotation.y,target_yaw)
	var wanted:=clampf(difference/maxf(delta,.000001),-turn_speed_radians,turn_speed_radians)
	_visual_turn_speed=move_toward(_visual_turn_speed,wanted,TURN_ACCEL_RADIANS_S2*delta)
	var advance:=_visual_turn_speed*delta
	if absf(advance)>absf(difference):advance=difference;_visual_turn_speed=0.
	visual.rotation.y=wrapf(visual.rotation.y+advance,-PI,PI)

func locomotion_snapshot() -> Dictionary:
	return {"ground_accel_time_s":GROUND_ACCEL_TIME_S,"ground_brake_time_s":GROUND_BRAKE_TIME_S,"visual_turn_accel_radians_s2":TURN_ACCEL_RADIANS_S2,"visual_turn_speed_radians_s":_visual_turn_speed,"guard_stops":motion_guard_stops,"walk_speed_mps":walk_speed_mps,"run_speed_mps":run_speed_mps,"air_control":"Retained direct sandbox air control and fresh-press jumps","camera_bob_added":false}

func _inside(point: Vector3) -> bool:
	if interior_active:
		if not point.is_finite():return false
		if has_open_sky():
			# The roof AABB validates landings/water, not an invisible ceiling.
			# Keep its lower recovery plane and world/source XZ footprints.
			if point.y<interior_bounds.position.y:return false
			var world_xz := Rect2(Vector2(interior_bounds.position.x,interior_bounds.position.z),Vector2(interior_bounds.size.x,interior_bounds.size.z))
			if not world_xz.has_point(Vector2(point.x,point.z)):return false
		elif not interior_bounds.has_point(point):return false
		if not interior_walkable_rect.has_area():return true
		var local: Vector3 = interior_frame.affine_inverse()*point
		return interior_walkable_rect.grow(-EDGE_MARGIN_M).has_point(Vector2(local.x,local.z))
	return _inside_outdoors(point)

func _inside_outdoors(point: Vector3) -> bool:
	if not free_roam_enabled:return super._inside(point)
	if not point.is_finite():return false
	var p:=Vector2(point.x,point.z)
	if free_roam_polygon.size()>=3:
		if not free_roam_bounds.has_point(p) or not Geometry2D.is_point_in_polygon(p,free_roam_polygon):return false
		for index in range(free_roam_polygon.size()):
			var first: Vector2=free_roam_polygon[index]
			var second: Vector2=free_roam_polygon[(index+1)%free_roam_polygon.size()]
			if not first.is_finite() or not second.is_finite() or p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,first,second))<EDGE_MARGIN_M*EDGE_MARGIN_M:return false
	elif not free_roam_bounds.grow(-EDGE_MARGIN_M).has_point(p):return false
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

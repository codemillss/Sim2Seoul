extends RefCounted
## N04 probe input guidance only. Never moves, pauses or changes an actor.
## The caller retains the original source endpoint order and applies ordinary input.

const PERSON_HEIGHT_M: float=1.7
const PERSON_RADIUS_M: float=.305
const ARRIVAL_M: float=.06
const NPC_AHEAD_M: float=1.8
const YIELD_SIDE_M: float=.85
const YIELD_FORWARD_M: float=.25
const SOURCE_START_TOLERANCE_M: float=.18
const MAX_SOURCE_DEVIATION_M: float=1.
const WAIT_LIMIT_S: float=8.

var events: Array[Dictionary]=[]
var _source_leg: String=""
var _source_from: Vector3=Vector3.ZERO
var _source_to: Vector3=Vector3.ZERO
var _forward: Vector3=Vector3.ZERO
var _leg_length_m: float=0.
var _mode: String="source"
var _target: Vector3=Vector3.ZERO
var _origin: Vector3=Vector3.ZERO
var _waypoint: Vector3=Vector3.ZERO
var _last_position: Vector3=Vector3.ZERO
var _npc: CharacterBody3D
var _npc_id: String=""
var _start_tick: int=-1
var _phase_tick: int=-1
var _wait_tick: int=-1
var _return_tick: int=-1
var _return_reason: String=""
var _last_tick: int=-1
var _max_source_deviation_m: float=0.
var _blocked_reason: String=""
var _capsule: CapsuleShape3D=CapsuleShape3D.new()


func _init() -> void:
	_capsule.height=PERSON_HEIGHT_M
	_capsule.radius=PERSON_RADIUS_M


func set_leg(id: String,from: Vector3,to: Vector3) -> void:
	if _mode!="source":_finish_yield("source_leg_changed",_last_position)
	_source_leg=id
	_source_from=from
	_source_to=to
	_forward=to-from
	_forward.y=0.
	_leg_length_m=_forward.length()
	_forward=_forward.normalized()
	_target=to
	_mode="source"
	_phase_tick=Engine.get_physics_frames()
	_blocked_reason=""


func next_direction(player: CharacterBody3D,npcs: Array,city: Node3D) -> Vector3:
	var point: Vector3=player.global_position
	_last_position=point
	_last_tick=Engine.get_physics_frames()
	_max_source_deviation_m=maxf(_max_source_deviation_m,_source_distance(point))
	_blocked_reason=""
	if _mode=="yield":
		if _flat_delta(point,_target).length()<=ARRIVAL_M:
			_mode="yield_wait"
			_wait_tick=_last_tick
			_phase_tick=_last_tick
		else:
			# Recheck a short physical corridor as the NPC continues to move.
			var motion: Vector3=_flat_delta(point,_target).limit_length(.07)
			if not _capsule_sweep_clear(player,city,point,motion):
				_blocked_reason="dynamic_yield_step_occupied"
				return Vector3.ZERO
			return _flat_delta(point,_target).normalized()
	if _mode=="yield_wait":
		var reason: String=""
		if not is_instance_valid(_npc):reason="npc_missing"
		else:
			var separation: Vector3=_flat_delta(point,_npc.global_position)
			if separation.length()>2.:reason="npc_clear_distance"
			elif separation.dot(_forward)<=0.:reason="npc_passed_behind"
		if reason.is_empty() and float(_last_tick-_wait_tick)/float(Engine.physics_ticks_per_second)>=WAIT_LIMIT_S:
			reason="wait_limit_elapsed"
		if reason.is_empty():return Vector3.ZERO
		_mode="yield_return"
		_target=_source_to
		_return_tick=_last_tick
		_return_reason=reason
		_phase_tick=_last_tick
	if _mode=="yield_return":
		if _source_distance(point)>SOURCE_START_TOLERANCE_M:
			return _flat_delta(point,_source_to).normalized()
		_finish_yield(_return_reason,point)
	var source_direction: Vector3=_flat_delta(point,_source_to).normalized()
	if _leg_length_m<=.000001 or _source_distance(point)>SOURCE_START_TOLERANCE_M:
		return source_direction
	var nearest: CharacterBody3D
	var nearest_m: float=NPC_AHEAD_M
	for item: Variant in npcs:
		var npc: CharacterBody3D=item as CharacterBody3D
		if not is_instance_valid(npc):continue
		var offset: Vector3=_flat_delta(point,npc.global_position)
		if offset.length()<nearest_m and offset.dot(source_direction)>0.:
			nearest=npc
			nearest_m=offset.length()
	if not is_instance_valid(nearest):return source_direction
	var normal: Vector3=Vector3(-_forward.z,0.,_forward.x)
	for sign_value: float in [1.,-1.]:
		var candidate: Vector3=point+normal*YIELD_SIDE_M*sign_value+_forward*YIELD_FORWARD_M
		if not _candidate_clear(player,city,point,candidate):continue
		_origin=point
		_target=candidate
		_waypoint=candidate
		_npc=nearest
		# Production pedestrians expose route_id through snapshot(), not a getter.
		var npc_row: Dictionary=nearest.call("snapshot") as Dictionary
		_npc_id=String(npc_row.get("route_id",String(nearest.name)))
		_mode="yield"
		_start_tick=_last_tick
		_phase_tick=_last_tick
		_wait_tick=-1
		_return_tick=-1
		_return_reason=""
		events.append({"type":"yield_start","source_leg":_source_leg,"tick":_last_tick,
			"origin":_vector(_origin),"waypoint":_vector(_target),"npc_id":_npc_id})
		return _flat_delta(point,_target).normalized()
	_blocked_reason="no_valid_yield_waypoint"
	return source_direction


func _candidate_clear(player: CharacterBody3D,city: Node3D,origin: Vector3,waypoint: Vector3) -> bool:
	if _source_distance(waypoint)>MAX_SOURCE_DEVIATION_M:return false
	# Eight path intervals and eight circumference points check the complete
	# walking/support footprint; the actual capsule sweep also includes the NPC.
	for sample_index: int in range(9):
		var point: Vector3=origin.lerp(waypoint,float(sample_index)/8.)
		if not bool(city.call("volume_clear",point,PERSON_HEIGHT_M,PERSON_RADIUS_M)):return false
		if not _supported_movement_point(player,city,point):return false
		for circle_index: int in range(8):
			var angle: float=TAU*float(circle_index)/8.
			var rim: Vector3=point+Vector3(cos(angle),0.,sin(angle))*PERSON_RADIUS_M
			if not _supported_movement_point(player,city,rim):return false
	return _capsule_sweep_clear(player,city,origin,_flat_delta(origin,waypoint))


func _supported_movement_point(player: CharacterBody3D,city: Node3D,point: Vector3) -> bool:
	if not bool(city.call("movement_contains",Vector2(point.x,point.z))):return false
	var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.25,point-Vector3.UP*.25,1,[player.get_rid()])
	var hit: Dictionary=player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return false
	var normal: Vector3=hit.get("normal",Vector3.ZERO)
	var support: StaticBody3D=city.get("fragments").get("W03_support") as StaticBody3D
	return is_instance_valid(support) and hit.get("rid",RID())==support.get_rid() and normal.dot(Vector3.UP)>.99


func _capsule_sweep_clear(player: CharacterBody3D,city: Node3D,feet: Vector3,motion: Vector3) -> bool:
	var exclusions: Array[RID]=[player.get_rid()]
	var fragments: Dictionary=city.get("fragments") as Dictionary
	var support: StaticBody3D=fragments.get("W03_support") as StaticBody3D
	if not is_instance_valid(support):return false
	exclusions.append(support.get_rid())
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new()
	query.shape=_capsule
	query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*(PERSON_HEIGHT_M*.5))
	query.collision_mask=player.collision_mask
	query.exclude=exclusions
	query.margin=.001
	query.collide_with_areas=false
	query.collide_with_bodies=true
	var space: PhysicsDirectSpaceState3D=player.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=motion
	var fractions: PackedFloat32Array=space.cast_motion(query)
	return fractions.size()==2 and fractions[0]>=1.


func _source_distance(point: Vector3) -> float:
	var offset: Vector3=_flat_delta(_source_from,point)
	var closest: Vector3=_source_from+_forward*clampf(offset.dot(_forward),0.,_leg_length_m)
	return _flat_delta(closest,point).length()


func _flat_delta(from: Vector3,to: Vector3) -> Vector3:
	var result: Vector3=to-from
	result.y=0.
	return result


func _finish_yield(reason: String,point: Vector3) -> void:
	events.append({"type":"yield_end","source_leg":_source_leg,"tick":Engine.get_physics_frames(),
		"origin":_vector(_origin),"waypoint":_vector(_waypoint),"position":_vector(point),
		"npc_id":_npc_id,"reason":reason,"start_tick":_start_tick,"wait_tick":_wait_tick,
		"return_tick":_return_tick,"source_error_m":_source_distance(point)})
	_mode="source"
	_target=_source_to
	_phase_tick=Engine.get_physics_frames()
	_npc=null
	_npc_id=""


func _vector(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]


func snapshot() -> Dictionary:
	return {"source_leg":_source_leg,"mode":_mode,"target":_vector(_target),"npc_id":_npc_id,
		"tick":_last_tick,"phase_start_tick":_phase_tick,"yield_start_tick":_start_tick,
		"wait_start_tick":_wait_tick,"return_start_tick":_return_tick,"return_reason":_return_reason,
		"max_source_deviation_m":_max_source_deviation_m,
		"blocked_reason":_blocked_reason}

extends RefCounted
## Exploration-only local passing. Plans retain source station + a bounded offset;
## they never assign an actor position or grant permission to cross a road.
const MAX_OFFSET_M := 1.25
const LOOK_AHEAD_M := 2.4
const SAMPLE_M := .22
const PERSONAL_MARGIN_M := .12
var host: Node3D
var point_at: Callable
var ground_at: Callable
var allowed_at: Callable
var neighbors: Callable
var plans_started := 0
var plans_completed := 0
var rejected_plans := 0

func setup(owner_node: Node3D, route_point: Callable, floor_point: Callable, allowed: Callable, bodies: Callable) -> void:
	host=owner_node;point_at=route_point;ground_at=floor_point;allowed_at=allowed;neighbors=bodies

func _flat(value: Vector3) -> Vector2:return Vector2(value.x,value.z)

func radius(row: Dictionary) -> float:
	return .45 if row.kind=="dog" else float(row.collider.shape.radius)

func _other_radius(body: CharacterBody3D) -> float:
	if body.get_meta("street_actor_kind","")=="dog":return .45
	var shape: CollisionShape3D=body.get_node_or_null("CollisionShape")
	return float(shape.shape.radius) if shape!=null and shape.shape is CapsuleShape3D else .35

func _excluded(group: Dictionary) -> Array[RID]:
	var result: Array[RID]=[]
	for row: Dictionary in group.members:result.append(row.body.get_rid())
	return result

func _feet(group: Dictionary, station: float, lateral: float, row: Dictionary) -> Dictionary:
	var at: Vector3=point_at.call(group,station,float(row.side)+lateral)
	if not allowed_at.call(at,radius(row)):return {}
	var support: Dictionary=ground_at.call(at)
	if support.is_empty() or absf(support.point.y-at.y)>.45:return {}
	# Centre-only rays can allow a foot to leave a ledge. Probe the footprint
	# too, and reject a surface step greater than an ordinary shallow curb.
	for side: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var edge: Dictionary=ground_at.call(at+side*radius(row))
		if edge.is_empty() or absf(edge.point.y-support.point.y)>.19:return {}
	return support

func _sweep(row: Dictionary, start: Vector3, end: Vector3, floor_a: RID, floor_b: RID, excluded: Array[RID], direction: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=row.collider.shape
	query.collision_mask=row.body.collision_mask;query.margin=.007
	query.exclude=excluded.duplicate();query.exclude.append(floor_a);query.exclude.append(floor_b)
	var basis:=Basis.IDENTITY
	if row.kind=="dog":basis=Basis(Vector3.UP,atan2(-direction.x,-direction.z))
	query.transform=Transform3D(basis,start+row.collider.position+Vector3.UP*.02)
	var space:=host.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=end-start
	if query.motion.length()>.00001 and space.cast_motion(query)[0]<.9999:return false
	query.transform.origin+=query.motion;query.motion=Vector3.ZERO
	if not space.intersect_shape(query,1).is_empty():return false
	# A dog turns gradually. Check its actual current orientation as well as
	# the proposed direction, so planning cannot instantly rotate its box.
	if row.kind=="dog":
		query.transform.basis=row.collider.global_basis
		if not space.intersect_shape(query,1).is_empty():return false
	return true

func segment_clear(group: Dictionary, starts: Array, ends: Array, supports: Array, others: Array) -> bool:
	var excluded:=_excluded(group)
	# People use conservative round footprints below. Keep cars/static world
	# in the physical sweep; avoid inflating already-touching actor shapes.
	var sweep_excluded:=excluded.duplicate()
	for other: CharacterBody3D in others:
		if is_instance_valid(other):sweep_excluded.append(other.get_rid())
	for index in range(group.members.size()):
		var row: Dictionary=group.members[index];var a: Vector3=starts[index];var b: Vector3=ends[index]
		var floor_a: Dictionary=ground_at.call(a)
		if floor_a.is_empty() or absf(a.y-b.y)>.24:return false
		var direction:=b-a;direction.y=0.
		if direction.is_zero_approx():direction=-row.visual.global_basis.z
		if not _sweep(row,a,b,floor_a.rid,supports[index].rid,sweep_excluded,direction.normalized()):return false
		for other: CharacterBody3D in others:
			if not is_instance_valid(other) or excluded.has(other.get_rid()) or absf(other.global_position.y-b.y)>1.8:continue
			var distance:=_flat(other.global_position).distance_to(Geometry2D.get_closest_point_to_segment(_flat(other.global_position),_flat(a),_flat(b)))
			var required:=radius(row)+_other_radius(other)+PERSONAL_MARGIN_M
			if distance<required:
				var initial:=_flat(other.global_position).distance_to(_flat(a));var final:=_flat(other.global_position).distance_to(_flat(b))
				if initial>=required or final<=initial+.00001:return false
	if group.record.dog:
		# Keep the whole pair on the same translated corridor. Reject a lane
		# that puts a player, wall or another actor between keeper and dog.
		var human: Vector3=ends[0];var dog: Vector3=ends[1]
		if _flat(human).distance_to(_flat(dog))>1.12 or absf(human.y-dog.y)>.24:return false
		var ray:=PhysicsRayQueryParameters3D.create(human+Vector3.UP*.62,dog+Vector3.UP*.48,1|2|4|8,excluded)
		if not host.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
	return true

func _supports(group: Dictionary, station: float, offset: float) -> Array:
	var result:=[]
	for row: Dictionary in group.members:
		var support:=_feet(group,station,offset,row)
		if support.is_empty():return []
		result.append(support)
	return result

func _positions(group: Dictionary) -> Array:
	var result:=[]
	for row: Dictionary in group.members:result.append(row.body.global_position)
	return result

func _centres(supports: Array) -> Array:
	var result:=[]
	for support: Dictionary in supports:result.append(support.point)
	return result

func _offset(group: Dictionary) -> float:
	var centre: Vector3=point_at.call(group,group.station,0.)
	var lateral: Vector3=point_at.call(group,group.station,1.)-centre;lateral.y=0.
	return (group.members[0].body.global_position-centre).dot(lateral)/maxf(.0001,lateral.length_squared())

func _build_plan(group: Dictionary, lane: float, obstacle_distance: float) -> Array:
	var start_s: float=group.station;var sign: float=group.direction
	var available: float=group.length-start_s if sign>0. else start_s
	if available<1.65:return []
	var pass_distance:=minf(available-.55,obstacle_distance+1.0)
	var enter_distance:=minf(.7,maxf(0.,obstacle_distance-1.05))
	var exit_distance:=minf(available,pass_distance+1.0)
	var knots: Array=[Vector2(start_s,_offset(group)),Vector2(start_s+sign*enter_distance,lane),Vector2(start_s+sign*pass_distance,lane),Vector2(start_s+sign*exit_distance,0.)]
	var plan:=[]
	for index in range(1,knots.size()):
		var a: Vector2=knots[index-1];var b: Vector2=knots[index]
		var count:=maxi(1,int(ceil(a.distance_to(b)/SAMPLE_M)))
		for step in range(1,count+1):
			var point:=a.lerp(b,float(step)/count);plan.append({"station":point.x,"offset":point.y})
	var starts:=_positions(group);var others: Array=neighbors.call(group)
	for waypoint: Dictionary in plan:
		var supports:=_supports(group,waypoint.station,waypoint.offset)
		if supports.is_empty():return []
		var ends:=_centres(supports)
		if not segment_clear(group,starts,ends,supports,others):return []
		starts=ends
	return plan

func _obstacle_distance(group: Dictionary) -> float:
	var start: Vector3=point_at.call(group,group.station,0.)
	var ahead: Vector3=point_at.call(group,clampf(group.station+group.direction*.2,0.,group.length),0.)-start
	if ahead.is_zero_approx():return 1.0
	ahead=ahead.normalized();var result:=LOOK_AHEAD_M;var excluded:=_excluded(group)
	for row: Dictionary in group.members:
		for other: CharacterBody3D in neighbors.call(group):
			if not is_instance_valid(other) or excluded.has(other.get_rid()) or absf(other.global_position.y-row.body.global_position.y)>1.8:continue
			var difference: Vector3=other.global_position-row.body.global_position;difference.y=0.
			var along:=difference.dot(ahead);var across: float=(difference-ahead*along).length()
			if along>-.15 and along<LOOK_AHEAD_M and across<radius(row)+_other_radius(other)+.35:result=minf(result,maxf(0.,along))
	return result

func _new_plan(group: Dictionary, distance: float) -> bool:
	# Commit to one side for the whole manoeuvre; no per-frame left/right
	# switching when the closest actor changes by a few centimetres.
	for amount in [.95,MAX_OFFSET_M]:
		for side in [float(group.direction),-float(group.direction)]:
			var plan:=_build_plan(group,amount*side,distance)
			if plan.is_empty():continue
			group.avoidance_plan=plan;group.avoidance_lane_m=amount*side;group.avoidance_count=int(group.get("avoidance_count",0))+1
			plans_started+=1;return true
	rejected_plans+=1;return false

func choose(group: Dictionary, delta: float, speed: float) -> Dictionary:
	if not group.has("avoidance_plan"):group.avoidance_plan=[];group.avoidance_retry_s=0.;group.avoidance_lane_m=0.;group.avoidance_count=0
	group.avoidance_retry_s=maxf(0.,float(group.avoidance_retry_s)-delta)
	group.avoidance_offset_m=_offset(group)
	var actual: Vector3=group.members[0].body.global_position
	while not group.avoidance_plan.is_empty():
		var waypoint: Dictionary=group.avoidance_plan[0]
		var target: Vector3=point_at.call(group,waypoint.station,waypoint.offset)
		if _flat(actual).distance_to(_flat(target))>.045:break
		group.avoidance_plan.pop_front()
		if group.avoidance_plan.is_empty():plans_completed+=1;group.avoidance_lane_m=0.
	var distance:=_obstacle_distance(group)
	if group.avoidance_plan.is_empty() and group.avoidance_retry_s<=0.:
		var obstructed:=distance<LOOK_AHEAD_M
		if not obstructed:
			var look_s: float=clampf(group.station+group.direction*.9,0.,group.length)
			var look_supports:=_supports(group,look_s,0.)
			obstructed=look_supports.is_empty() or not segment_clear(group,_positions(group),_centres(look_supports),look_supports,neighbors.call(group))
			if obstructed:distance=.9
		if obstructed and not _new_plan(group,distance):group.avoidance_retry_s=.35
	var station: float=clampf(group.station+group.direction*speed*delta,0.,group.length)
	var offset:=0.
	if not group.avoidance_plan.is_empty():
		station=group.avoidance_plan[0].station;offset=group.avoidance_plan[0].offset
	var supports:=_supports(group,station,offset)
	if supports.is_empty():return {"clear":false,"reason":"floor_or_protected_boundary","targets":_positions(group)}
	var ends:=_centres(supports);var starts:=_positions(group)
	# Validate precisely this physical tick, not a sweep to a distant goal.
	# Planning observes a snapshot; a moving player can enter it afterwards.
	for index in range(ends.size()):
		var difference: Vector3=ends[index]-starts[index];difference.y=0.
		var capped:=difference.limit_length(speed*delta)
		var point: Vector3=starts[index]+capped
		var support: Dictionary=ground_at.call(point)
		if support.is_empty():return {"clear":false,"reason":"missing_step_support","targets":starts}
		ends[index]=support.point;supports[index]=support
	if not segment_clear(group,starts,ends,supports,neighbors.call(group)):
		group.avoidance_stuck_s=float(group.get("avoidance_stuck_s",0.))+delta
		if group.avoidance_stuck_s>.45 and group.avoidance_retry_s<=0.:
			# Replan from the current physical offset if the old lane changed.
			group.avoidance_plan=[];group.avoidance_retry_s=.25;group.avoidance_stuck_s=0.
		return {"clear":false,"reason":"occupied_passing_corridor","targets":starts}
	group.avoidance_stuck_s=0.
	return {"clear":true,"reason":"","targets":ends,"passing":not group.avoidance_plan.is_empty()}

func can_reverse(group: Dictionary, distance: float) -> bool:
	var target:=clampf(float(group.station)-float(group.direction)*distance,0.,float(group.length))
	if absf(target-float(group.station))<distance*.9:return false
	var supports:=_supports(group,target,_offset(group))
	return not supports.is_empty() and segment_clear(group,_positions(group),_centres(supports),supports,neighbors.call(group))

extends Node3D
## Leaf-scene adapter: historical N02/N04 scripts and source routes are intact.
## It takes over only their physics callbacks after exploration has initialized.
var loaded := false
var running := true
var groups: Array[Dictionary]=[]
var street: Node3D
var _original: Array[CharacterBody3D]=[]

func setup(_city: Node3D,_player: CharacterBody3D,original_people: Array[CharacterBody3D],street_people: Node3D) -> bool:
	if loaded or not is_instance_valid(street_people) or not street_people.loaded or original_people.size()!=2:return false
	street=street_people;name="ExplorationPedestrianAvoidance";process_mode=Node.PROCESS_MODE_PAUSABLE
	for actor: CharacterBody3D in original_people:
		if not actor.get("_configured"):return false
	for actor: CharacterBody3D in original_people:
		var group:={"id":"legacy_"+String(actor._route_id),"record":{"side_offset_m":0.,"dog":false},"points":Array(actor._points),"arc":Array(actor._arc),"sides":[],"length":actor._length_m,"station":actor._station_m,"direction":actor._direction,"members":[],"state":"walking","blocked_reason":"","blocked_s":0.,"clear_s":.3,"dwell_s":0.,"turns":0,"actual_distance_m":0.}
		for index in range(group.points.size()):
			var before: Vector3=group.points[index]-group.points[maxi(0,index-1)]
			var after: Vector3=group.points[mini(group.points.size()-1,index+1)]-group.points[index]
			before.y=0.;after.y=0.
			if before.is_zero_approx():before=after
			if after.is_zero_approx():after=before
			before=before.normalized();after=after.normalized()
			var a:=Vector3(before.z,0,-before.x);var b:=Vector3(after.z,0,-after.x);var side: Vector3=(a+b).normalized()
			group.sides.append(side/maxf(.8,side.dot(b)))
		group.members.append({"body":actor,"collider":actor.capsule,"visual":actor.visual,"kind":"walker","side":0.})
		_original.append(actor);groups.append(group)
		actor.set_meta("exploration_avoidance_adapter",true)
		actor.collision_mask|=32;actor.floor_snap_length=.35
		actor.set_physics_process(false)
	loaded=true;print("EXPLORATION_PEDESTRIAN_AVOIDANCE_READY people=2 original_core_unchanged=true")
	return true

func set_running(enabled: bool) -> void:
	running=enabled
	for actor: CharacterBody3D in _original:actor.velocity=Vector3.ZERO

func _record_station(group: Dictionary) -> void:
	var actor: CharacterBody3D=group.members[0].body;var p:=Vector2(actor.global_position.x,actor.global_position.z)
	var best:=INF;var station: float=group.station
	for index in range(1,group.points.size()):
		var a: Vector3=street._at(group,group.arc[index-1]);var b: Vector3=street._at(group,group.arc[index])
		var q:=Geometry2D.get_closest_point_to_segment(p,Vector2(a.x,a.z),Vector2(b.x,b.z));var distance:=q.distance_to(p)
		if distance>=best:continue
		best=distance;station=lerpf(group.arc[index-1],group.arc[index],q.distance_to(Vector2(a.x,a.z))/maxf(.0001,Vector2(b.x-a.x,b.z-a.z).length()))
	group.actual_distance_m+=absf(station-group.station);group.station=station
	actor._station_m=station;actor._segment=actor._segment_at(station,group.direction)

func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	for group: Dictionary in groups:
		var actor: CharacterBody3D=group.members[0].body;var enabled: bool=running and actor._running
		actor._physics_steps+=1
		var target:=actor.global_position
		if enabled:
			actor._elapsed_s+=delta
			var choice: Dictionary=street.avoidance.choose(group,delta,1.2)
			if choice.clear:
				group.clear_s+=delta;group.blocked_s=0.;group.blocked_reason=""
				group.state="passing" if choice.get("passing",false) else "walking"
				if group.clear_s>=.3:target=choice.targets[0]
			else:
				group.state="waiting";group.blocked_reason=choice.reason;group.blocked_s+=delta;group.clear_s=0.
				if group.blocked_s>=2. and street.avoidance.can_reverse(group,.8):
					group.direction=-group.direction;group.blocked_s=0.;group.dwell_s=.5;group.turns+=1;group.avoidance_plan=[]
					actor._obstacle_reversals+=1;actor._reversals+=1;actor._turn_count+=1
			if group.dwell_s>0.:group.dwell_s=maxf(0.,group.dwell_s-delta);target=actor.global_position;group.state="turning"
		else:actor._pause_ticks+=1
		var before:=actor.global_position;var difference:=target-before;difference.y=0.
		var velocity:=difference.limit_length(1.2*delta)/delta
		actor.velocity=Vector3(velocity.x,-.12 if actor.is_on_floor() else maxf(actor.velocity.y-9.8*delta,-8.),velocity.z)
		actor.move_and_slide()
		var achieved:=actor.global_position-before;achieved.y=0.
		actor._distance_m+=achieved.length();actor._max_step_m=maxf(actor._max_step_m,achieved.length())
		if achieved.length()>.000001:actor._moves+=1;actor._rotate_visual(actor._heading(achieved),delta)
		elif group.state=="turning":
			var direction: Vector3=street._tangent(group,group.station)*float(group.direction)
			actor._rotate_visual(actor._heading(direction),delta)
		_record_station(group);actor._update_player_distance()
		var support: Dictionary=street._ground(actor.global_position,.65)
		if not support.is_empty():actor._floor_name=String(support.collider.name);actor._floor_path=String(support.collider.get_path())
		if enabled and group.dwell_s<=0. and ((group.direction>0 and group.station>group.length-.025) or (group.direction<0 and group.station<.025)):
			group.direction=-group.direction;group.dwell_s=.5;group.turns+=1;group.avoidance_plan=[]
			actor._end_events+=1;actor._turn_count+=1;actor._reversals+=1
			actor._endpoint_history.append({"time_s":actor._elapsed_s,"endpoint":0 if group.direction>0 else group.points.size()-1,"station_m":group.station,"position":actor._vector(actor.global_position)})
		actor._direction=group.direction;actor._state=group.state;actor._blocked_reason=group.blocked_reason;actor._blocked_s=group.blocked_s

func snapshot() -> Dictionary:
	var rows:=[]
	for group: Dictionary in groups:rows.append({"id":group.id,"station_m":group.station,"direction":group.direction,"state":group.state if running else "paused","offset_m":group.get("avoidance_offset_m",0.),"avoidance_count":group.get("avoidance_count",0),"blocked_reason":group.blocked_reason,"position":group.members[0].body.global_position})
	return {"loaded":loaded,"running":running,"routes":rows,"original_controller_source_changed":false}

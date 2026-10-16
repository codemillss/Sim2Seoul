extends Node3D
## Small authored outdoor population. Original N02 controllers/routes stay fixed.
## Only spawn assigns a position; every subsequent actor move uses move_and_slide.
const DESIGN_PATH := "res://assets/authored/street_pedestrians.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
const AVATAR := preload("res://scripts/player/exploration_avatar.gd")
class StreetActor extends CharacterBody3D:
	var facility_control := false
	func _physics_process(_delta: float) -> void:pass
class RenderProxy extends Node3D:
	func _physics_process(_delta: float) -> void:transform=Transform3D.IDENTITY
class FinishPose extends Node:
	var host: Node3D
	func _physics_process(delta: float) -> void:host._finish_poses(delta)
var loaded := false
var load_error := ""
var city: Node3D
var player: CharacterBody3D
var rig: Node3D
var actors: Array[Dictionary] = []
var groups: Array[Dictionary] = []
var skipped: Array[Dictionary] = []
var elapsed := 0.0
var running := true
var _design: Dictionary = {}
var _traffic: Node
var _traffic_routes: Array = []
var _old_people: Array = []
var _doors: Array[Vector3] = []
var _maximum_step := 0.0
var _minimum_player_distance := INF
var _minimum_neighbor_distance := INF
var _maximum_leash := 0.0
var _leash_blocked_ticks := 0
var _maximum_local_density := 0

func setup(source_city: Node3D,controlled_player: CharacterBody3D,camera_rig: Node3D) -> bool:
	if loaded or not is_instance_valid(source_city) or not is_instance_valid(controlled_player) or not is_instance_valid(camera_rig):return false
	city=source_city;player=controlled_player;rig=camera_rig;name="StreetPedestrians"
	process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH):return _fail("거리 보행 자료와 원본 도시가 다릅니다.")
	_design=raw
	var parent:=city.get_parent();_traffic=parent.get("traffic")
	var old: Variant=parent.get("pedestrians")
	if old is Array:_old_people=old.duplicate()
	var traffic: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic.json"))
	if traffic is Dictionary:_traffic_routes=traffic.get("routes",[])
	var visit: Variant=parent.get("interior_visit")
	if is_instance_valid(visit):
		for row: Dictionary in visit.catalog:
			for entry: Dictionary in row.entry_candidates:_doors.append(entry.entrance)
	for record: Dictionary in _design.routes:_make_group(record)
	if groups.size()!=6 or actors.size()!=8:return _fail("안전한 거리 보행 공간을 확보하지 못했습니다.")
	var finish:=FinishPose.new();finish.host=self;finish.process_physics_priority=3;add_child(finish)
	loaded=true
	print("STREET_PEDESTRIANS_READY walkers=6 dogs=2 source_geometry_changed=false")
	return true

func _fail(message: String) -> bool:load_error=message;return false

func _route(record: Dictionary) -> Dictionary:
	if record.has("museum_stations_m"):
		var hill: Variant=city.get_parent().get("museum_approach")
		if not is_instance_valid(hill) or not hill.loaded:return {}
		var points: Array[Vector3]=[];var start: float=record.museum_stations_m[0];var end: float=record.museum_stations_m[1]
		for index in range(int(ceil(end-start))+1):points.append(hill.point_at_station(minf(end,start+index)))
		return {"points":points,"source":record.source_route,"authored_height":true}
	var data: Variant=city.get("public_data")
	if not data is Dictionary:return {}
	for route: Dictionary in data.routes:
		if route.id!=record.source_route:continue
		var i: int=record.source_segment[0];var j: int=record.source_segment[1]
		if i<0 or j>=route.xz.size():return {}
		var a:=city.to_global(Vector3(route.xz[i][0],0,route.xz[i][1]));var b:=city.to_global(Vector3(route.xz[j][0],0,route.xz[j][1]))
		return {"points":[a.lerp(b,record.fractions[0]),a.lerp(b,record.fractions[1])],"source":record.source_route,"authored_height":false}
	return {}

func _at(group: Dictionary,station: float,side_extra := 0.0) -> Vector3:
	var s:=clampf(station,0.,group.length)
	for index in range(1,group.points.size()):
		if s>group.arc[index] and index<group.points.size()-1:continue
		var a: Vector3=group.points[index-1];var b: Vector3=group.points[index]
		var tangent: Vector3=b-a;tangent.y=0.;tangent=tangent.normalized()
		var at: Vector3=a.lerp(b,(s-group.arc[index-1])/(group.arc[index]-group.arc[index-1]))
		return at+Vector3(tangent.z,0,-tangent.x)*(float(group.record.side_offset_m)+side_extra)
	return group.points.back()

func _tangent(group: Dictionary,station: float) -> Vector3:
	var offset:=_at(group,minf(station+.05,group.length))-_at(group,maxf(station-.05,0.));offset.y=0.;return offset.normalized()

func _ground(at: Vector3,height := 2.0) -> Dictionary:
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*height,at-Vector3.UP*height,1|32)
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.75:return {}
	return {"point":Vector3(at.x,hit.position.y+.025,at.z),"normal":hit.normal,"rid":hit.rid,"collider":hit.collider}

func _clear_static(point: Vector3,kind: String,yaw := 0.) -> bool:
	var shape: Shape3D
	if kind=="dog":var box:=BoxShape3D.new();box.size=Vector3(.42,.52,.84);shape=box
	else:var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70;shape=capsule
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1|32;query.margin=.003
	query.transform=Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP*(.28 if kind=="dog" else .86))
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _traffic_distance(point: Vector3) -> float:
	var best:=INF
	for route: Dictionary in _traffic_routes:
		for index in range(1,route.xz.size()):
			var a:=Vector2(route.xz[index-1][0],route.xz[index-1][1]);var b:=Vector2(route.xz[index][0],route.xz[index][1])
			var local:=city.to_local(point);best=minf(best,Vector2(local.x,local.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(local.x,local.z),a,b)))
	return best

func _make_group(record: Dictionary) -> void:
	var route:=_route(record)
	if route.is_empty():skipped.append({"id":record.id,"reason":"missing_source_route"});return
	var group:={"id":record.id,"record":record,"points":route.points,"source":route.source,"authored_height":route.authored_height,"arc":[0.],"length":0.,"station":0.,"direction":int(record.direction),"state":"walking","blocked_reason":"","blocked_s":0.,"clear_s":0.,"dwell_s":0.,"members":[],"turns":0,"actual_distance_m":0.,"minimum_traffic_distance_m":INF}
	for index in range(1,group.points.size()):
		var a: Vector3=group.points[index-1];var b: Vector3=group.points[index];group.length+=Vector2(b.x-a.x,b.z-a.z).length();group.arc.append(group.length)
	# Certify the whole future corridor on current physical geometry, rather
	# than assuming a source centreline has enough space for two bodies.
	var extra: float=record.get("dog_side_m",_design.policy.dog_side_m) if record.dog else 0.
	for index in range(int(ceil(group.length/float(_design.policy.sample_spacing_m)))+1):
		var s:=minf(group.length,index*float(_design.policy.sample_spacing_m))
		for side in ([0.,extra] if record.dog else [0.]):
			var sample:=_ground(_at(group,s,side))
			if sample.is_empty() or not _clear_static(sample.point,"dog" if side!=0. else "walker",atan2(-_tangent(group,s).x,-_tangent(group,s).z)):
				skipped.append({"id":record.id,"reason":"unsupported_or_occupied_corridor","station_m":s,"side_m":side});return
			var traffic_distance:=_traffic_distance(sample.point);group.minimum_traffic_distance_m=minf(group.minimum_traffic_distance_m,traffic_distance)
			if traffic_distance<float(_design.policy.traffic_route_clearance_m):skipped.append({"id":record.id,"reason":"moving_traffic_corridor"});return
			for door: Vector3 in _doors:
				if Vector2(door.x-sample.point.x,door.z-sample.point.z).length()<1.25:skipped.append({"id":record.id,"reason":"entrance_corridor","station_m":s});return
	group.station=group.length*float(record.initial_fraction)
	var human:=_make_actor(group,"walker",0.);group.members.append(human);actors.append(human)
	if record.dog:
		var dog:=_make_actor(group,"dog",extra);group.members.append(dog);actors.append(dog)
		var leash:=MeshInstance3D.new();leash.name="Leash";var mesh:=CylinderMesh.new();mesh.top_radius=.009;mesh.bottom_radius=.009;mesh.height=1.;mesh.radial_segments=8;leash.mesh=mesh;leash.material_override=_material(Color(.26,.17,.12));add_child(leash);group["leash"]=leash;group["leash_blocked"]=false
	groups.append(group)

func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.85;return material

func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=at;node.material_override=material;parent.add_child(node);return node

func _round(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=SphereMesh.new();mesh.radius=.5;mesh.height=1.;mesh.radial_segments=12;mesh.rings=6
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.scale=size;node.position=at;node.material_override=material;parent.add_child(node);return node

func _make_actor(group: Dictionary,kind: String,side: float) -> Dictionary:
	var body:=StreetActor.new();body.name=String(group.id)+("_dog" if kind=="dog" else "_walker")
	body.collision_layer=4;body.collision_mask=1|2|4|8|32;body.safe_margin=.001;body.floor_snap_length=.35;body.floor_max_angle=deg_to_rad(42.);body.process_mode=Node.PROCESS_MODE_PAUSABLE
	body.set_meta("street_pedestrian",true);body.set_meta("street_actor_kind",kind)
	var collision:=CollisionShape3D.new();collision.name="CollisionShape"
	if kind=="dog":
		var box:=BoxShape3D.new();box.size=Vector3(.36,.48,.80);collision.shape=box;collision.position.y=.24
	else:
		var capsule:=CapsuleShape3D.new();capsule.radius=.25;capsule.height=1.68;collision.shape=capsule;collision.position.y=.84
	body.add_child(collision)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual)
	var original:=MeshInstance3D.new();original.name="Body";visual.add_child(original)
	add_child(body)
	var support:=_ground(_at(group,group.station,side));body.global_position=support.point
	var tangent:=_tangent(group,group.station)*float(group.direction);visual.rotation.y=atan2(-tangent.x,-tangent.z)
	if kind=="dog":collision.rotation.y=visual.rotation.y
	var row:={"body":body,"kind":kind,"group":group.id,"side":side,"visual":visual,"collider":collision,"phase":0.,"distance_m":0.,"moves":0,"floor_rid":support.rid,"floor_normal":support.normal,"minimum_ground_gap_m":INF,"maximum_ground_gap_m":-INF,"previous_pose":visual.global_transform,"current_pose":visual.global_transform,"registered_traffic":false}
	if kind=="walker":
		var avatar:=AVATAR.new();avatar.setup(body);row["avatar"]=avatar
		var color:=Color(group.record.clothing[0],group.record.clothing[1],group.record.clothing[2])
		for key in ["jacket","jacket_trim"]:avatar._materials[key].albedo_color=color.lightened(.12 if key=="jacket_trim" else 0.)
	else:_make_dog(row,group.record)
	var proxy:=RenderProxy.new();proxy.name="RenderProxy";proxy.process_physics_priority=-100;proxy.process_mode=Node.PROCESS_MODE_PAUSABLE;visual.add_child(proxy)
	for child in visual.get_children():
		if child==proxy or child==original:continue
		child.reparent(proxy,false)
	row["proxy"]=proxy
	body.set_physics_process(true)
	if is_instance_valid(_traffic) and _traffic.has_method("register_human"):_traffic.register_human(body);row.registered_traffic=true
	return row

func _make_dog(row: Dictionary,record: Dictionary) -> void:
	var visual: Node3D=row.visual;var color:=Color(record.dog_color[0],record.dog_color[1],record.dog_color[2]);var coat:=_material(color);var dark:=_material(color.darkened(.32));var nose:=_material(Color(.045,.04,.035));var collar_mat:=_material(Color(.66,.18,.16))
	_round(visual,"DogTorso",Vector3(.31,.32,.57),Vector3(0,.37,.015),coat)
	_round(visual,"DogChest",Vector3(.28,.34,.27),Vector3(0,.38,-.20),coat)
	var head:=Node3D.new();head.name="DogHead";head.position=Vector3(0,.49,-.32);visual.add_child(head)
	_round(head,"DogSkull",Vector3(.25,.24,.25),Vector3.ZERO,coat)
	_round(head,"DogMuzzle",Vector3(.16,.11,.20),Vector3(0,-.04,-.16),coat)
	_round(head,"DogNose",Vector3(.09,.065,.045),Vector3(0,-.025,-.26),nose)
	for side in [-1.,1.]:
		var ear:=_round(head,"DogEar",Vector3(.095,.20,.12),Vector3(side*.115,-.02,.01),dark);ear.rotation.z=side*.22
		_round(head,"DogEye",Vector3(.028,.028,.018),Vector3(side*.065,.055,-.105),nose)
	var collar:=_box(visual,"DogCollar",Vector3(.30,.055,.12),Vector3(0,.47,-.22),collar_mat);row["collar"]=collar
	var tail:=Node3D.new();tail.name="DogTail";tail.position=Vector3(0,.45,.29);tail.rotation.x=.65;visual.add_child(tail)
	_round(tail,"DogTailCoat",Vector3(.07,.08,.31),Vector3(0,0,.12),dark);row["tail"]=tail
	var legs:=[]
	for front in [true,false]:
		for side in [-1.,1.]:
			var leg:=Node3D.new();leg.name=("Front" if front else "Back")+("LeftLeg" if side<0 else "RightLeg");leg.position=Vector3(side*.105,.25,-.18 if front else .20);visual.add_child(leg)
			_box(leg,"DogLowerLeg",Vector3(.065,.22,.07),Vector3(0,-.11,0),coat)
			var paw:=_round(leg,"DogPaw",Vector3(.09,.065,.13),Vector3(0,-.22,-.025),dark)
			legs.append({"joint":leg,"paw":paw,"phase_offset":0. if (front and side<0) or (not front and side>0) else PI,"rest":leg.position})
	row["legs"]=legs;row["head"]=head

func _members_excluded(group: Dictionary) -> Array[RID]:
	var result: Array[RID]=[]
	for row: Dictionary in group.members:result.append(row.body.get_rid())
	return result

func _block(group: Dictionary,direction: int,distance: float) -> String:
	var excludes:=_members_excluded(group)
	for row: Dictionary in group.members:
		var body: CharacterBody3D=row.body;var target:=_ground(_at(group,clampf(group.station+direction*distance,0.,group.length),row.side))
		if target.is_empty():return "missing_ground"
		var motion: Vector3=target.point-body.global_position
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=row.collider.shape;query.collision_mask=body.collision_mask;query.margin=.005
		query.exclude=excludes.duplicate();query.exclude.append(row.floor_rid);query.exclude.append(target.rid)
		query.transform=body.global_transform*row.collider.transform;query.transform.origin.y+=.025
		var space:=get_world_3d().direct_space_state
		if not space.intersect_shape(query,1).is_empty():return "occupied_capsule"
		query.motion=motion
		if motion.length()>.001 and space.cast_motion(query)[0]<.9999:return "swept_body"
		var others: Array=[player];others.append_array(_old_people)
		for other: Dictionary in actors:
			if other.group!=group.id:others.append(other.body)
		for other: CharacterBody3D in others:
			if not is_instance_valid(other) or absf(other.global_position.y-body.global_position.y)>2.:continue
			var point:=Vector2(other.global_position.x,other.global_position.z)
			var nearest:=Geometry2D.get_closest_point_to_segment(point,Vector2(body.global_position.x,body.global_position.z),Vector2(target.point.x,target.point.z))
			if point.distance_to(nearest)<(.43 if row.kind=="dog" else .27)+.30+float(_design.policy.player_clearance_m):return "neighbor_clearance"
	return ""

func _step_member(row: Dictionary,target: Vector3,speed: float,delta: float,direction: Vector3) -> void:
	var body: CharacterBody3D=row.body;var before:=body.global_position
	var support:=_ground(target)
	if support.is_empty():body.velocity=Vector3.ZERO;return
	row.floor_rid=support.rid;row.floor_normal=support.normal
	var flat:=Vector3(target.x-before.x,0,target.z-before.z)
	var desired:=flat.limit_length(speed*delta)/delta
	body.velocity.x=desired.x;body.velocity.z=desired.z
	body.velocity.y=-.12 if body.is_on_floor() else maxf(body.velocity.y-9.8*delta,-8.)
	body.move_and_slide()
	var achieved:=body.global_position-before;var distance:=Vector2(achieved.x,achieved.z).length()
	row.distance_m+=distance;row.moves+=1 if distance>.0001 else 0;row.phase=fmod(row.phase+distance/.65*TAU,TAU)
	_maximum_step=maxf(_maximum_step,distance)
	var yaw:=atan2(-direction.x,-direction.z)
	row.visual.rotation.y=rotate_toward(row.visual.rotation.y,yaw,2.8*delta)
	var floor_hit:=_ground(body.global_position,.65)
	if not floor_hit.is_empty():
		var gap: float=body.global_position.y-(floor_hit.point.y-.025)
		row.minimum_ground_gap_m=minf(row.minimum_ground_gap_m,gap);row.maximum_ground_gap_m=maxf(row.maximum_ground_gap_m,gap)
	if row.kind=="dog":
		row.collider.rotation.y=row.visual.rotation.y
		for leg: Dictionary in row.legs:
			var phase: float=row.phase+leg.phase_offset;var lift:=maxf(0.,sin(phase))*.055 if distance>.0001 else 0.
			leg.joint.rotation.x=sin(phase)*.34 if distance>.0001 else 0.
			leg.joint.position=leg.rest+Vector3.UP*lift
			var foot_at: Vector3=leg.paw.global_position
			var floor_at:=_ground(foot_at,.75)
			if not floor_at.is_empty():leg.joint.position.y+=floor_at.point.y-.025+.028+lift-foot_at.y
		row.tail.rotation.y=sin(elapsed*3.2)*.20 if distance>.0001 else 0.

func set_running(enabled: bool) -> void:
	running=enabled
	for group: Dictionary in groups:
		group.clear_s=0.;group.blocked_s=0.
	for row: Dictionary in actors:row.body.velocity=Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	if not running:
		# Keep physical support current while the movement checkbox is off.
		for row: Dictionary in actors:_step_member(row,row.body.global_position,0.,delta,-row.visual.global_basis.z)
		return
	elapsed+=delta
	for group: Dictionary in groups:
		var reason:=_block(group,group.direction,.55)
		var stopped: bool=not reason.is_empty() or group.get("leash_blocked",false)
		if stopped:
			group.state="waiting";group.blocked_reason=reason if not reason.is_empty() else "leash_corridor";group.blocked_s+=delta;group.clear_s=0.
			if group.blocked_s>=float(_design.policy.blocked_reverse_s) and _block(group,-group.direction,.8).is_empty():group.direction=-group.direction;group.blocked_s=0.;group.dwell_s=.7;group.turns+=1
		else:
			group.clear_s+=delta
			if group.clear_s>=float(_design.policy.clear_hold_s):group.state="walking";group.blocked_reason="";group.blocked_s=0.
		if group.dwell_s>0.:group.dwell_s=maxf(0.,group.dwell_s-delta);stopped=true;group.state="turning"
		var speed: float=0. if stopped or group.clear_s<float(_design.policy.clear_hold_s) else float(_design.policy.speed_mps)
		var next:=clampf(group.station+group.direction*speed*delta,0.,group.length)
		var direction:=_tangent(group,group.station)*float(group.direction)
		for row: Dictionary in group.members:
			_step_member(row,_at(group,next,row.side),float(_design.policy.maximum_dog_speed_mps) if row.kind=="dog" and speed>0. else speed,delta,direction)
		var human: Dictionary=group.members[0];var closest:=INF;var station: float=group.station
		for index in range(1,group.points.size()):
			var a:=_at(group,group.arc[index-1]);var b:=_at(group,group.arc[index]);var p: Vector3=human.body.global_position
			var q:=Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(a.x,a.z),Vector2(b.x,b.z));var error:=q.distance_to(Vector2(p.x,p.z))
			if error<closest:closest=error;station=group.arc[index-1]+q.distance_to(Vector2(a.x,a.z))
		group.actual_distance_m+=absf(station-group.station);group.station=station
		if speed>0. and ((group.direction>0 and group.station>group.length-.04) or (group.direction<0 and group.station<.04)):
			group.direction=-group.direction;group.dwell_s=float(_design.policy.end_dwell_s);group.turns+=1;group.clear_s=0.
	for row: Dictionary in actors:
		var p: Vector3=row.body.global_position;var local_density:=0
		_minimum_player_distance=minf(_minimum_player_distance,Vector2(p.x-player.global_position.x,p.z-player.global_position.z).length())
		for other: Dictionary in actors:
			if other==row:continue
			var distance:=p.distance_to(other.body.global_position)
			if other.group!=row.group:_minimum_neighbor_distance=minf(_minimum_neighbor_distance,distance)
			if distance<10.:local_density+=1
		_maximum_local_density=maxi(_maximum_local_density,local_density+1)

func _finish_poses(_delta: float) -> void:
	if not loaded:return
	for group: Dictionary in groups:
		if not group.record.dog:continue
		var human: Dictionary=group.members[0];var dog: Dictionary=group.members[1]
		var local_dog: Vector3=human.visual.to_local(dog.body.global_position)
		var side: String="Right" if local_dog.x>0 else "Left"
		var radial:=Vector3(local_dog.x,0,local_dog.z).normalized()*.40
		# The grip stays outside the torso even as the owner turns around.
		human.avatar._arm_to(side,Vector3(radial.x,.98,radial.z))
	for row: Dictionary in actors:
		row.previous_pose=row.current_pose;row.current_pose=row.visual.global_transform
		if row.previous_pose.origin.distance_to(row.current_pose.origin)>2.:row.previous_pose=row.current_pose
	_update_leashes(false)

func _update_leashes(render: bool) -> void:
	for group: Dictionary in groups:
		if not group.record.dog:continue
		var human: Dictionary=group.members[0];var dog: Dictionary=group.members[1]
		var local_dog: Vector3=human.visual.to_local(dog.body.global_position)
		var side: String="Right" if local_dog.x>0 else "Left"
		var hand: Node3D=human.avatar._hands[1 if side=="Right" else 0]
		var start:=hand.global_position;var end: Vector3=dog.collar.global_position+Vector3.UP*.015
		var difference:=end-start;var length:=difference.length();var leash: MeshInstance3D=group.leash
		if not render:
			_maximum_leash=maxf(_maximum_leash,length)
			var ray:=PhysicsRayQueryParameters3D.create(start,end,1|2|4|8,_members_excluded(group))
			group.leash_blocked=not get_world_3d().direct_space_state.intersect_ray(ray).is_empty() or length>float(_design.policy.maximum_leash_m)
			if group.leash_blocked:_leash_blocked_ticks+=1
		leash.visible=not group.leash_blocked
		if length>.001:leash.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,difference.normalized())).scaled(Vector3(1,length,1)),(start+end)*.5)

func _process(_delta: float) -> void:
	if not loaded:return
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for row: Dictionary in actors:row.proxy.global_transform=row.previous_pose.interpolate_with(row.current_pose,fraction)
	_update_leashes(true)

func snapshot() -> Dictionary:
	var rows:=[];var routes:=[]
	for row: Dictionary in actors:
		var body: CharacterBody3D=row.body
		var item:={"path":String(body.get_path()),"kind":row.kind,"route_id":row.group,"position":body.global_position,"velocity":body.velocity,"on_floor":body.is_on_floor(),"actual_distance_m":row.distance_m,"moves":row.moves,"phase":row.phase,"layer":body.collision_layer,"mask":body.collision_mask,"registered_traffic":row.registered_traffic,"ground_gap_range_m":[row.minimum_ground_gap_m,row.maximum_ground_gap_m],"render_anchor":row.proxy.global_position,"previous_anchor":row.previous_pose.origin,"physics_anchor":row.current_pose.origin}
		if row.kind=="walker":item["avatar"]=row.avatar.snapshot()
		else:
			var feet:=[]
			for leg: Dictionary in row.legs:feet.append({"position":leg.paw.global_position,"joint_rotation":leg.joint.rotation})
			item["feet"]=feet;item["tail_rotation"]=row.tail.rotation;item["collar"]=row.collar.global_position
		rows.append(item)
	for group: Dictionary in groups:routes.append({"id":group.id,"source":group.source,"source_points":group.points,"side_offset_m":group.record.side_offset_m,"dog":group.record.dog,"station_m":group.station,"length_m":group.length,"state":group.state if running else "paused","blocked_reason":group.blocked_reason,"direction":group.direction,"turns":group.turns,"actual_distance_m":group.actual_distance_m,"minimum_traffic_route_distance_m":group.minimum_traffic_distance_m,"leash_visible":group.leash.visible if group.record.dog else false,"authored_height":group.authored_height})
	return {"loaded":loaded,"error":load_error,"authored_population":true,"source_geometry_modified":false,"running":running,"elapsed":elapsed,"walker_count":groups.size(),"dog_count":actors.size()-groups.size(),"actor_count":actors.size(),"actors":rows,"routes":routes,"skipped":skipped,"maximum_step_m":_maximum_step,"minimum_player_distance_m":_minimum_player_distance,"minimum_neighbor_distance_m":_minimum_neighbor_distance,"maximum_leash_length_m":_maximum_leash,"leash_blocked_ticks":_leash_blocked_ticks,"maximum_observed_actors_within_10m":_maximum_local_density,"maximum_authored_actors":8,"traffic_registration_count":actors.filter(func(row: Dictionary)->bool:return row.registered_traffic).size()}

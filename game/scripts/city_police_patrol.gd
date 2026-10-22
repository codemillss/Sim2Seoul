extends Node3D
## Additional physical patrol vehicle on a certified source-road sector loop.
## It never replaces or appends to the fourteen original traffic-car arrays.
const DESIGN := "res://assets/authored/police_patrol.json"
const SIZE := Vector3(2.20,1.65,4.50)
class PatrolBody extends CharacterBody3D:
	func _physics_process(_delta: float) -> void:pass
class VisualReset extends Node3D:
	func _physics_process(_delta: float) -> void:transform=Transform3D.IDENTITY
var host: Node3D
var safety: Node3D
var facility: Node3D
var loaded:=false
var load_error:=""
var body: CharacterBody3D
var vehicle: CharacterBody3D
var emergency_active:=false
var state:="parked"
var speed_mps:=0.
var actual_distance_m:=0.
var completed_cycles:=0
var blocked_ticks:=0
var maximum_native_step_m:=0.
var events: Array=[]
var certificate: Dictionary={}
var design: Dictionary={}
var points: Array[Dictionary]=[]
var total_length_m:=0.
var progress_m:=0.
var _reverse_end_m:=0.
var _early_return:=false
var _gear_pause_s:=0.
var _clock:=0.
var _guard: Node3D
var _visual: Node3D
var _proxy: Node3D
var _previous:=Transform3D.IDENTITY
var _current:=Transform3D.IDENTITY
var _wheels: Array[Node3D]=[]
var _lights: Array[MeshInstance3D]=[]
var _forecourt:=PackedVector2Array()
var _moving:=false
var _last_wanted:=false
var _pose_cache: Dictionary={}
var _initial_original_ids: Array=[]
func setup(scene: Node3D,controller: Node3D,police_facility: Node3D) -> bool:
	host=scene;safety=controller;facility=police_facility;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0;_guard=host.drivable_car_service
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	if not raw is Dictionary or raw.source_world_sha256!=FileAccess.get_sha256("res://resources/world_geometry/world.json"):load_error="순찰차 원본 도로 자료가 다릅니다.";return false
	design=raw
	for point: Array in design.forecourt_access_xz:_forecourt.append(Vector2(point[0],point[1]))
	for actor: CharacterBody3D in host.vehicles:_initial_original_ids.append(actor.get_instance_id())
	for actor: CharacterBody3D in host.neighborhood_population.traffic.vehicles:_initial_original_ids.append(actor.get_instance_id())
	for path: Array in [design.reverse_departure_xz,design.forward_sector_loop_xz]:
		var gear: float=-1. if points.is_empty() else 1.
		for index: int in range(path.size()):
			if index==0 and not points.is_empty():continue
			var point:=Vector3(path[index][0],0,path[index][1]);var next: Array=path[mini(index+1,path.size()-1)];var before: Array=path[maxi(0,index-1)];var direction:=Vector3(next[0]-before[0],0,next[1]-before[1]).normalized()
			if direction.is_zero_approx():continue
			if not points.is_empty():total_length_m+=Vector2(point.x-points.back().flat.x,point.z-points.back().flat.z).length()
			points.append({"flat":point,"direction":direction,"gear":gear,"station":total_length_m})
		if gear<0.:_reverse_end_m=total_length_m
	certificate={"accepted":false,"samples":0,"failures":[],"source_feature_ids":design.source_features.map(func(row: Dictionary)->String:return row.id),"full_box_m":SIZE,"scope":"Dense full-source/native-static body preflight; dynamic player/people/traffic are checked fresh on every real move."}
	for index: int in range(0,points.size(),2):
		var pose:=_pose(points[index].flat,points[index].direction*float(points[index].gear));certificate.samples+=1
		if pose.is_empty() or not _full_source(pose.point,pose.basis) or not _native_clear(pose.point,pose.basis,[],false):
			if certificate.failures.size()<16:certificate.failures.append({"index":index,"point":points[index].flat,"pose_valid":not pose.is_empty(),"source_valid":not pose.is_empty() and _full_source(pose.point,pose.basis),"native_valid":not pose.is_empty() and _native_clear(pose.point,pose.basis,[],false),"native_contacts":_native_contacts(pose.point,pose.basis) if not pose.is_empty() else []})
	if not certificate.failures.is_empty():load_error="순찰차 전체 차체가 원본 도로/진입로 또는 실제 장애물을 벗어납니다.";print("POLICE_PATROL_PREFLIGHT_REJECTED ",JSON.stringify(certificate));return false
	certificate.accepted=true
	body=PatrolBody.new();body.name="GamePolicePatrolCar";body.collision_layer=8;body.collision_mask=1|2|4|8|32;body.safe_margin=.001;body.floor_snap_length=.45;var shape:=CollisionShape3D.new();shape.name="CollisionShape";var box:=BoxShape3D.new();box.size=SIZE;shape.shape=box;shape.position.y=SIZE.y*.5;body.add_child(shape);add_child(body);vehicle=body
	var start:=_pose(points[0].flat,points[0].direction*float(points[0].gear));body.global_transform=Transform3D(start.basis,start.point);_build_vehicle();_previous=body.global_transform;_current=_previous;_paint_bay();facility.patrol_car=body
	loaded=true;print("POLICE_PATROL_READY extra_cars=1 original_cars=",_initial_original_ids.size()," loop_m=",total_length_m," native_full_box=true");return true
func _mat(color: Color,emission:=false) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=.45
	if emission:result.emission_enabled=true;result.emission=color;result.emission_energy_multiplier=2.0
	return result
func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,mat: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.material_override=mat;node.position=at;parent.add_child(node);return node
func _label(parent: Node3D,title: String,text: String,at: Vector3,pixel:=.003) -> Label3D:
	var node:=Label3D.new();node.name=title;node.text=text;node.font_size=38;node.pixel_size=pixel;node.position=at;node.outline_size=2;node.modulate=Color(.015,.11,.28);parent.add_child(node);return node
func _build_vehicle() -> void:
	_visual=Node3D.new();_visual.name="Visual";body.add_child(_visual);_proxy=VisualReset.new();_proxy.name="PatrolRenderProxy";_proxy.process_physics_priority=-100;_visual.add_child(_proxy)
	# Reuse only the authored car geometry builder on an isolated controller.
	# This never changes the player's parked-car steering/grip references.
	var dresser:=preload("res://scripts/drivable_car_service.gd").new();var row: Dictionary={"wheels":[],"pedals":[]};dresser._build_bike(row,_proxy);_wheels.assign(row.wheels);dresser.free()
	var white:=_mat(Color(.90,.94,.96));var blue:=_mat(Color(.015,.20,.52));var lime:=_mat(Color(.74,.87,.12))
	for child: Node in _proxy.get_children():
		if child is MeshInstance3D and (String(child.name).begins_with("FrontDoor") or String(child.name).begins_with("RearDoor") or String(child.name) in ["LowerBody","Trunk","CabinRoof","Hood","Mirror"]):child.material_override=white
	for side: float in [-1.,1.]:
		_box(_proxy,"ElectricBluePoliceSideStripe",Vector3(.045,.18,3.56),Vector3(side*.932,.55,0),blue);_box(_proxy,"LimeVisibilityStripe",Vector3(.05,.045,2.8),Vector3(side*.94,.69,.15),lime)
		var label:=_label(_proxy,"PoliceDoorMarking","경찰\nPOLICE 112",Vector3(side*.947,.98,-.4),.0022);label.rotation.y=side*PI*.5
	_box(_proxy,"BluePoliceHood",Vector3(1.30,.012,.92),Vector3(0,.885,-1.48),blue)
	var front:=_label(_proxy,"Front112","112",Vector3(0,.64,-2.21),.002);front.rotation.y=PI
	_box(_proxy,"LightbarPedestal",Vector3(1.26,.08,.24),Vector3(0,1.57,-.04),_mat(Color(.10,.13,.16)))
	_lights.append(_box(_proxy,"RedPoliceBeacon",Vector3(.45,.12,.25),Vector3(-.36,1.66,-.04),_mat(Color(.95,.04,.04),true)))
	_lights.append(_box(_proxy,"BluePoliceBeacon",Vector3(.45,.12,.25),Vector3(.36,1.66,-.04),_mat(Color(.035,.25,1.),true)))
	_box(_proxy,"DriverUniform",Vector3(.35,.40,.23),Vector3(-.42,.97,-.12),blue);var head:=SphereMesh.new();head.radius=.115;head.height=.26;var node:=MeshInstance3D.new();node.mesh=head;node.position=Vector3(-.42,1.30,-.12);node.material_override=_mat(Color(.76,.58,.43));_proxy.add_child(node);_box(_proxy,"DriverPoliceCap",Vector3(.25,.075,.25),Vector3(-.42,1.42,-.12),blue)
	var old_marker:=_proxy.get_node_or_null("ParkedInteractionMarker")
	if old_marker!=null:old_marker.queue_free()
func _paint_bay() -> void:
	var blue:=_mat(Color(.04,.26,.58));var white:=_mat(Color(.89,.94,.94));var center:=Vector3(design.bay_xz[0],0,design.bay_xz[1])
	for x: float in [-1.50,1.50]:
		var at:=center+Vector3(x,0,0);var y: float=host.terrain_surface.ground_y_world(at);_box(self,"AuthoredPoliceBayLine",Vector3(.09,.014,5.55),Vector3(at.x,y+.025,at.z),white)
	var at:=center+Vector3(0,0,3.2);var y: float=host.terrain_surface.ground_y_world(at);var sign:=_label(self,"PoliceBayLabel","순찰차 전용 · 게임용 주차",Vector3(at.x,y+.08,at.z),.0025);sign.rotation.x=-PI*.5;sign.modulate=Color(.035,.18,.44)
	_box(self,"PoliceBayWheelStop",Vector3(1.65,.08,.12),Vector3(center.x,host.terrain_surface.ground_y_world(center+Vector3(0,0,2.0))+.04,center.z+2.0),blue)
func _point_allowed(point: Vector3) -> bool:
	if not host.player.free_roam_bounds.grow(-2.5).has_point(Vector2(point.x,point.z)):return false
	var local: Vector3=host.city.to_local(point);var flat:=Vector2(local.x,local.z)
	if _guard._private_index.contains(flat):return false
	if not _guard._inside_drive(flat) and not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),_forecourt):return false
	for door: Vector3 in _guard._doors:
		if Vector2(door.x-point.x,door.z-point.z).length()<2.:return false
	return Vector2(point.x-facility.entry_point.x,point.z-facility.entry_point.z).length()>2.5
func _pose(at: Vector3,direction: Vector3) -> Dictionary:
	var ground: Dictionary=_guard._ground(at)
	if ground.is_empty():return {}
	var yaw:=atan2(-direction.x,-direction.z);var basis: Basis=_guard._pose_basis(ground.point,yaw)
	return {"point":ground.point+Vector3.UP*.035,"basis":basis,"rid":ground.rid,"yaw":yaw}
func _full_source(point: Vector3,basis: Basis) -> bool:
	for x: float in [-1.12,-.56,0.,.56,1.12]:
		for z: float in [-2.27,-1.51,-.75,0.,.75,1.51,2.27]:
			var sample: Vector3=point+basis*Vector3(x,0,z)
			if not _point_allowed(sample) or _guard._ground(sample).is_empty():return false
	return true
func _native_contacts(point: Vector3,basis: Basis) -> Array:
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=SIZE;query.shape=shape;query.transform=Transform3D(basis,point+basis*Vector3(0,SIZE.y*.5+.015,0));query.collision_mask=1|32;query.margin=.004
	if is_instance_valid(host.terrain_surface.support):query.exclude=[host.terrain_surface.support.get_rid()]
	var ground: Dictionary=_guard._ground(point)
	if not ground.is_empty():query.exclude.append(ground.rid)
	var rows: Array=[]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,8):rows.append({"node":String(hit.collider.get_path()),"geometry_id":hit.collider.get_meta("geometry_id","")})
	return rows
func _native_clear(point: Vector3,basis: Basis,exclude: Array[RID]=[],dynamic:=true,motion:=Vector3.ZERO) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=SIZE;query.shape=shape;query.transform=Transform3D(basis,point+basis*Vector3(0,SIZE.y*.5+.015,0));query.collision_mask=1|32|(2|4|8 if dynamic else 0);query.margin=.004
	var excluded: Array[RID]=exclude.duplicate()
	if is_instance_valid(body):excluded.append(body.get_rid())
	if is_instance_valid(host.terrain_surface.support):excluded.append(host.terrain_surface.support.get_rid())
	var ground: Dictionary=_guard._ground(point)
	if not ground.is_empty() and not excluded.has(ground.rid):excluded.append(ground.rid)
	query.exclude=excluded
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	query.motion=motion;return motion.is_zero_approx() or space.cast_motion(query)[0]>=.9999
func _frame(station: float) -> Dictionary:
	var s:=clampf(station,0.,total_length_m)
	var low:=0;var high:=points.size()-1
	while low<high:
		var mid:=int((low+high)/2)
		if float(points[mid].station)<s:low=mid+1
		else:high=mid
	var index:=maxi(1,low);var a: Dictionary=points[index-1];var b: Dictionary=points[index];var fraction:=clampf((s-float(a.station))/maxf(.00001,float(b.station)-float(a.station)),0.,1.);var direction: Vector3=(a.direction*float(a.gear)).lerp(b.direction*float(b.gear),fraction).normalized()
	return {"flat":a.flat.lerp(b.flat,fraction),"direction":direction,"gear":-1. if s<_reverse_end_m-.0001 else 1.,"index":index}
func _speed_limit(station: float) -> float:
	var row:=_frame(station);var limit: float=design.policy.reverse_speed_mps if row.gear<0. else (design.policy.forecourt_speed_mps if Geometry2D.is_point_in_polygon(Vector2(row.flat.x,row.flat.z),_forecourt) else design.policy.road_speed_mps)
	var before:=_frame(maxf(0.,station-.7));var after:=_frame(minf(total_length_m,station+.7));var angle:=absf(before.direction.signed_angle_to(after.direction,Vector3.UP));var radius:=1.4/maxf(angle,.001)
	return minf(limit,sqrt(maxf(.5,radius)*1.4))
func _physics_process(delta: float) -> void:
	if not loaded or host.menu.visible:return
	_clock+=delta;emergency_active=bool(safety.wanted)
	if emergency_active and state=="parked":state="dispatching";_moving=true;_early_return=false;progress_m=0.;events.append({"event":"source_sector_dispatch_started","clock_s":_clock})
	if not emergency_active and _moving and progress_m<_reverse_end_m+.1:_early_return=true
	if not _moving:body.velocity=Vector3(0,-.9,0);body.move_and_slide();_previous=_current;_current=body.global_transform;return
	state="responding" if emergency_active else "returning"
	if _gear_pause_s>0.:_gear_pause_s=maxf(0.,_gear_pause_s-delta);body.velocity=Vector3(0,-.9,0);body.move_and_slide();_previous=_current;_current=body.global_transform;return
	var target_speed:=_speed_limit(progress_m)
	if not _early_return and progress_m<_reverse_end_m:
		target_speed=minf(target_speed,sqrt(maxf(0.,2.*float(design.policy.braking_mps2)*(_reverse_end_m-progress_m))))
		if _reverse_end_m-progress_m<.045 and absf(speed_mps)<.4:progress_m=_reverse_end_m;speed_mps=0.;_gear_pause_s=.45;return
	for ahead: float in [2.,4.,7.]:target_speed=minf(target_speed,sqrt(pow(_speed_limit(minf(total_length_m,progress_m+ahead)),2)+2.*float(design.policy.braking_mps2)*ahead))
	var remaining:=progress_m if _early_return else total_length_m-progress_m;target_speed=minf(target_speed,sqrt(maxf(0.,2.*float(design.policy.braking_mps2)*remaining)))
	if _early_return:target_speed=minf(target_speed,1.6)
	var old_abs:=absf(speed_mps);var rate: float=design.policy.acceleration_mps2 if target_speed>old_abs else design.policy.braking_mps2;var next_speed:=move_toward(old_abs,target_speed,rate*delta)
	var next_station:=clampf(progress_m+(-1. if _early_return else 1.)*next_speed*delta,0.,total_length_m);var frame:=_frame(next_station);var pose:=_pose(frame.flat,frame.direction);var before:=body.global_position
	if pose.is_empty() or not _full_source(pose.point,pose.basis) or not _native_clear(before,body.global_basis,[],true) or not _native_clear(before,body.global_basis.slerp(pose.basis,.5),[],true) or not _native_clear(pose.point,pose.basis,[],true) or not _native_clear(before,pose.basis,[],true,pose.point-before):
		blocked_ticks+=1;speed_mps=move_toward(speed_mps,0.,float(design.policy.braking_mps2)*delta);body.velocity=Vector3.ZERO;state="blocked";_previous=_current;_current=body.global_transform;return
	body.global_basis=pose.basis;body.velocity=(pose.point-before)/delta;body.velocity.y-=.9;body.move_and_slide();var step: float=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length();actual_distance_m+=step;maximum_native_step_m=maxf(maximum_native_step_m,step)
	if step>0.00001:progress_m=next_station
	speed_mps=next_speed*float(frame.gear)*(-1. if _early_return else 1.)
	for wheel: Node3D in _wheels:wheel.rotation.x-=speed_mps*delta/.315
	_previous=_current;_current=body.global_transform
	if remaining<.08 and absf(speed_mps)<.6:
		_moving=false;state="parked";speed_mps=0.;completed_cycles+=1;progress_m=0.;_early_return=false;events.append({"event":"physical_bay_returned","clock_s":_clock})
func _process(_delta: float) -> void:
	if not loaded:return
	_proxy.global_transform=_previous.interpolate_with(_current,clampf(Engine.get_physics_interpolation_fraction(),0.,1.))
	for index: int in range(_lights.size()):_lights[index].visible=not emergency_active or int(_clock*8.)%2==index
func audio_state() -> Dictionary:return {"body":body,"speed_mps":speed_mps,"engine_active":_moving,"siren_active":emergency_active and _moving}
func snapshot() -> Dictionary:
	var original_ids: Array=[]
	for actor: CharacterBody3D in host.vehicles:original_ids.append(actor.get_instance_id())
	for actor: CharacterBody3D in host.neighborhood_population.traffic.vehicles:original_ids.append(actor.get_instance_id())
	return {"loaded":loaded,"load_error":load_error,"state":state,"emergency_active":emergency_active,"speed_mps":speed_mps,"actual_distance_m":actual_distance_m,"completed_cycles":completed_cycles,"blocked_ticks":blocked_ticks,"maximum_native_step_m":maximum_native_step_m,"position":body.global_position if is_instance_valid(body) else Vector3.ZERO,"progress_m":progress_m,"route_length_m":total_length_m,"certificate":certificate,"original14_car_identities_retained":original_ids==_initial_original_ids,"events":events,"scope":"Additional visible physical patrol car on a bounded source-direction police-block circuit, authored bay/parking manoeuvre. It does not replace original traffic or claim a universal city-wide pursuit/navigation service; foot officers retain the sixty-second catch rule."}

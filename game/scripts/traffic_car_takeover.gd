extends "res://scripts/drivable_car_service.gd"
## Reuses each original traffic actor, collision box and visible model. An E
## request brakes that actor on its source polyline before transferring control.
## A seized car stays parked and driveable; its former FIFO reservation is freed.
var traffic_cars: Array[CharacterBody3D]=[]
var pending_car: CharacterBody3D
var pending_elapsed_s:=0.0
var pending_initial_speed_mps:=0.0
var pending_actual_distance_m:=0.0
var _pending_was_running:=true
var _identity: Dictionary={}
var _seized: Dictionary={}
var _current_pose_row: Dictionary={}
const DRIVER_AVATAR:=preload("res://scripts/player/exploration_avatar.gd")
const MAX_DEPARTED_DRIVERS:=4
const ENTRY_SECONDS:=.78
class DepartedDriver extends CharacterBody3D:
	var facility_control:=false
	func _physics_process(_delta: float) -> void:pass
var pending_stage:=""
var pending_stage_elapsed_s:=0.
var drivers: Array[Dictionary]=[]
var _pending_driver: Dictionary={}
var _entry_owned_control:=false
var _entry_saved_physics:=true
var _pending_side:=-1.
var _door_cue: Node3D
var _horn: AudioStreamPlayer3D
var horn_count:=0
var _horn_cooldown_until:=0.

func _ride_label() -> String:return "도로 자동차"
func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=0
	var donor: Node3D=scene.drivable_car_service
	if not is_instance_valid(donor) or not donor.loaded:return _fail("자동차 운전 제어가 준비되지 않았습니다.")
	# Reuse the already source-checked car policy/indices, without spawning a
	# replacement car or running the parked-car placement routine a second time.
	design=donor.design.duplicate(true);design.policy.interact_distance_m=3.0
	_private_index=donor._private_index;_road_index=donor._road_index;_walk_index=donor._walk_index
	_drive_grid=donor._drive_grid;_doors=donor._doors.duplicate()
	for body: CharacterBody3D in host.vehicles:traffic_cars.append(body)
	for body: CharacterBody3D in host.neighborhood_population.traffic.vehicles:traffic_cars.append(body)
	for body: CharacterBody3D in traffic_cars:
		if not is_instance_valid(body) or not body.has_method("_move_on_polyline") or not is_instance_valid(body.get_node_or_null("Visual")):return _fail("도로 자동차의 원본 제어/모델이 없습니다.")
		_identity[body.get_instance_id()]={"body_id":body.get_instance_id(),"visual_id":body.get_node("Visual").get_instance_id(),"shape_id":body.get_node("CollisionShape").get_instance_id(),"route_id":body.get_route_id(),"manager":body._manager,"original_mask":body.collision_mask,"original_shape":body.get_node("CollisionShape").shape.get_instance_id()}
	source_ai_car_count_before=traffic_cars.size()
	var finish:=PoseFinish.new();finish.service=self;finish.process_physics_priority=2;add_child(finish)
	loaded=traffic_cars.size()==14
	if not loaded:return _fail("도로 자동차 원본14대가 모두 필요합니다.")
	print("TRAFFIC_TAKEOVER_READY original_cars=",traffic_cars.size()," spawned_replacement_cars=0")
	return true

func _door_distance_for(body: CharacterBody3D) -> float:
	var best:=INF
	for side: float in [-1.,1.]:best=minf(best,host.player.global_position.distance_to(body.to_global(Vector3(side*1.20,0,-.38))))
	return best
func _visible_car(body: CharacterBody3D) -> bool:
	var excludes: Array[RID]=[host.player.get_rid(),body.get_rid()]
	for person: CharacterBody3D in host.traffic.humans:
		if is_instance_valid(person):excludes.append(person.get_rid())
	for height: float in [.65,1.20]:
		var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,body.global_position+Vector3.UP*height,1|4|8|32,excludes)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return false
	return absf(host.player.global_position.y-body.global_position.y)<.65
func _nearest_car() -> CharacterBody3D:
	var result: CharacterBody3D;var best:=float(design.policy.interact_distance_m)
	for body: CharacterBody3D in traffic_cars:
		var distance:=_door_distance_for(body)
		if distance<best and _visible_car(body):best=distance;result=body
	return result
func _nearest_bike() -> int:
	var body:=_nearest_car()
	if not is_instance_valid(body):return -1
	for index: int in range(bikes.size()):
		if bikes[index].body==body:return index
	return -1
func _visible_bike(index: int) -> bool:return index>=0 and _visible_car(bikes[index].body)
func _door_distance() -> float:
	var body:=pending_car if is_instance_valid(pending_car) else _nearest_car()
	return _door_distance_for(body) if is_instance_valid(body) else INF
func interaction_distance_m() -> float:
	return 0.0 if riding else _door_distance() if loaded and _context_ready() else INF
func interaction_distance() -> float:return interaction_distance_m()
func can_interact() -> bool:
	if not _context_ready():return false
	if riding or is_instance_valid(pending_car):return true
	return host.player.free_roam_enabled and not host.player.facility_control and host.player.is_physics_processing() and _player_supported_for_mount() and is_instance_valid(_nearest_car())
func prompt_text() -> String:
	if not loaded or not _context_ready():return ""
	if is_instance_valid(pending_car):
		var message:="차량을 세우는 중 · 문 옆으로 따라가세요"
		if pending_stage=="approach":message="정차했습니다 · 앞좌석 문 바로 옆으로 다가가세요"
		elif pending_stage=="driver_exit":message="운전자가 차에서 내리는 중"
		elif pending_stage=="player_enter":message="문을 잡고 운전석에 들어가는 중"
		return message+"\nE · 취소"
	if riding:return "도로 자동차 · %d km/h · W 가속 / S 제동·후진\nA·D 조향 / Space 브레이크 / H 경적 / E 정차 후 내리기"%roundi(absf(speed_mps)*3.6) if not exit_requested else "안전하게 정차하고 내릴 공간을 확인하는 중\nE · 취소하고 계속 운전"
	if _clock<_notice_until:return _notice
	if not is_instance_valid(_nearest_car()):return ""
	return "E · 주차한 자동차 다시 타기" if _seized.has(_nearest_car().get_instance_id()) else "E · 자동차 세우고 빼앗아 타기 · 경찰이 출동합니다"
func handle_interact() -> bool:
	if not can_interact():return false
	if is_instance_valid(pending_car):_cancel_pending();return true
	if riding:exit_requested=not exit_requested;return true
	var body:=_nearest_car()
	if not is_instance_valid(body):return false
	var index:=_nearest_bike()
	if index>=0:
		if not _mount(index):_notice="문 옆 공간이 비고 차가 길 위에 안전하게 서 있어야 탈 수 있습니다.";_notice_until=_clock+3.0
		return true
	pending_car=body;pending_elapsed_s=0.;pending_actual_distance_m=0.;pending_initial_speed_mps=float(body._speed_mps);_pending_was_running=bool(body._running);_set_pending_stage("braking")
	# Keep its manager reservation while braking, so following AI still yield.
	# Directly suspend the AI/recycle flag without set_running(false), which
	# would erase the measured speed before the physical braking phase.
	body._running=false;body.set_physics_process(false);riding=true
	_event("traffic_stop_requested",{"body_id":body.get_instance_id(),"route_id":body.get_route_id(),"initial_speed_mps":pending_initial_speed_mps})
	return true
func interact() -> bool:return handle_interact()

func _cancel_pending() -> void:
	if not is_instance_valid(pending_car):return
	var body:=pending_car;var resume_running: bool=_pending_was_running
	_release_entry_control()
	if host.exploration_avatar.has_method("cancel_sandbox_action"):host.exploration_avatar.cancel_sandbox_action("vehicle_enter")
	if not _pending_driver.is_empty():
		var actor: CharacterBody3D=_pending_driver.body
		if is_instance_valid(actor):
			host.traffic.humans.erase(actor);actor.queue_free()
		drivers.erase(_pending_driver);_pending_driver={}
	_clear_door_cue()
	# The vehicle-movement checkbox can change while this request is paused in
	# the menu. Respect that current choice on E, timeout or external cancel.
	if is_instance_valid(host.traffic_switch):resume_running=host.traffic_switch.button_pressed
	if resume_running:body._running=true
	else:body.set_running(false)
	body.set_physics_process(true)
	pending_car=null;riding=false;pending_stage="";pending_stage_elapsed_s=0.;pending_elapsed_s=0.;_event("traffic_stop_cancelled",{"body_id":body.get_instance_id(),"current_traffic_enabled":resume_running})
func _release_manager(body: CharacterBody3D) -> void:
	var manager: Node=body._manager;var route_id: String=body.get_route_id()
	manager.vehicles.erase(body);manager.queue.erase(route_id)
	if String(manager.zone_owner)==route_id:manager.zone_owner=""
	var zones: Variant=manager.get("zones")
	if zones is Dictionary:
		for zone: Dictionary in zones.values():
			zone.queue.erase(route_id)
			if String(zone.owner)==route_id:zone.owner=""
	manager.guards.erase(route_id)
	manager.events.append({"type":"player_takeover_released","tick":Engine.get_physics_frames(),"route_id":route_id})
	manager.refreshed_tick=-1
func _adopt(body: CharacterBody3D) -> int:
	var visual: Node3D=body.get_node("Visual")
	var original_children:=visual.get_children()
	var proxy:=PhysicsReset.new();proxy.name="PlayerTakeoverRenderProxy";proxy.process_physics_priority=-100;visual.add_child(proxy)
	for child: Node in original_children:child.reparent(proxy,false)
	# The existing car model stays intact. Small interior driver anchors serve
	# the same animated avatar hands, without replacing any visible body part.
	var steering:=Node3D.new();steering.name="TakeoverSteering";steering.position=Vector3(-.42,.98,-.48);proxy.add_child(steering)
	var grips: Array[Node3D]=[]
	for side: float in [-1.,1.]:
		var grip:=Node3D.new();grip.position=Vector3(side*.16,0,0);steering.add_child(grip);grips.append(grip)
	var front:=Node3D.new();front.name="PlayerSteeringAnchor";proxy.add_child(front)
	var crank:=Node3D.new();crank.name="PlayerMotionAnchor";proxy.add_child(crank)
	var marker:=Node3D.new();marker.name="ParkedTakeoverAnchor";proxy.add_child(marker)
	var row: Dictionary={"body":body,"visual":visual,"proxy":proxy,"shape":body.get_node("CollisionShape"),"station_id":"","rented":false,"yaw":body.global_rotation.y,"wheel_phase":0.,"distance_m":0.,"previous":body.global_transform,"current":body.global_transform,"front":front,"wheels":[],"crank":crank,"pedals":[],"kickstand":marker,"steering":steering,"grips":grips}
	bikes.append(row);_seized[body.get_instance_id()]=true;body.set_meta("player_seized_traffic_car",true)
	body.collision_mask=int(_identity[body.get_instance_id()].original_mask)|32;body.floor_snap_length=.45
	_release_manager(body)
	_event("original_actor_adopted",{"body_id":body.get_instance_id(),"visual_id":visual.get_instance_id(),"route_id":body.get_route_id(),"stopping_distance_m":pending_actual_distance_m})
	return bikes.size()-1
func _mount(index: int) -> bool:
	_current_pose_row=bikes[index];_car_steering_wheel=_current_pose_row.steering;_driver_grips=_current_pose_row.grips
	return super._mount(index)
func _rider_pose(measure:=true) -> void:
	if is_instance_valid(pending_car) or rental_index<0:return
	super._rider_pose(measure)
func _process(delta: float) -> void:
	super._process(delta)
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for row: Dictionary in drivers:
		if is_instance_valid(row.body):row.proxy.global_transform=row.previous.interpolate_with(row.current,fraction)
	if is_instance_valid(_horn) and _horn.playing:
		var audio: Node3D=host.get("city_vehicle_audio")
		if not is_instance_valid(audio) or not audio.enabled or audio.gain<=.001 or not riding or rental_index<0:_horn.stop()
		else:_horn.volume_db=-17.+linear_to_db(audio.gain);_horn.bus=audio.bus_name;_horn.global_position=bikes[rental_index].body.global_position+Vector3.UP*.7
	if is_instance_valid(_door_cue):_door_cue.scale=Vector3.ONE*(.90+.10*sin(pending_stage_elapsed_s*7.))
func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	_move_departed_drivers(delta)
	if is_instance_valid(pending_car):
		_finish_collision_release();_clock+=delta;pending_elapsed_s+=delta;pending_stage_elapsed_s+=delta
		if _custody_owner() or host.player.interior_active or host.interior_visit.active:_cancel_pending();return
		var body:=pending_car
		if pending_elapsed_s>18. or host.player.global_position.distance_to(body.global_position)>12.:_cancel_pending();return
		if pending_stage=="braking":
			var before:=body.global_position
			body._terrain_clearance_distance_this_tick_m=0.;body._apply_terrain_orientation(delta);body._find_support()
			body._permission=body._manager.permission(body)
			var safe_budget: float=body._choose_step_budget(delta)
			var stopping_speed:=move_toward(float(body._speed_mps),0.,float(body.BRAKE_MPS2)*delta)
			var distance: float=body._move_on_polyline(minf(safe_budget,stopping_speed*delta),delta)
			body._speed_mps=distance/delta;body.velocity=-body.global_basis.z*body._speed_mps;pending_actual_distance_m+=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length()
			if body._speed_mps>.05:return
			body._speed_mps=0.;body.velocity=Vector3.ZERO;_set_pending_stage("approach")
		if not _handoff_clear(body):blocked_reason="traffic_safe_handoff_blocked";return
		if pending_stage=="approach":
			if not _player_supported_for_mount() or _door_distance_for(body)>1.10 or not _visible_car(body):return
			_pending_side=-1. if host.player.global_position.distance_to(body.to_global(Vector3(-1.20,0,-.38)))<host.player.global_position.distance_to(body.to_global(Vector3(1.20,0,-.38))) else 1.
			var departure:=_driver_departure(body,-_pending_side)
			if departure.is_empty():blocked_reason="driver_egress_blocked";_notice="운전자가 안전하게 내릴 공간이 부족합니다. 열린 문 쪽에서 다시 시도하세요.";_notice_until=_clock+3.;return
			if not _spawn_driver(departure):blocked_reason="driver_actor_unavailable";_cancel_pending();return
			_make_door_cue(body,_pending_side);_set_pending_stage("driver_exit")
			_pending_driver.avatar.play_sandbox_action("vehicle_exit",.65)
			_event("driver_exited",{"body_id":body.get_instance_id(),"driver_id":_pending_driver.body.get_instance_id(),"point":_pending_driver.body.global_position,"exit_sweep_checked":true})
			return
		if pending_stage=="driver_exit":
			if _door_distance_for(body)>1.4 or not _visible_car(body):_cancel_pending();return
			if pending_stage_elapsed_s<.65:return
			_pending_driver.state="leaving";_entry_owned_control=true;_entry_saved_physics=host.player.is_physics_processing();host.player.set_facility_control(true);host.player.velocity=Vector3.ZERO
			var visual: Node3D=host.player.get_node("Visual");var toward: Vector3=body.global_position-host.player.global_position;toward.y=0.
			if toward.length()>.05:visual.global_rotation.y=atan2(-toward.x,-toward.z)
			host.exploration_avatar.play_sandbox_action("vehicle_enter",ENTRY_SECONDS);_set_pending_stage("player_enter");_event("player_entry_started",{"body_id":body.get_instance_id(),"duration_s":ENTRY_SECONDS,"player_capsule_id":host.player.get_node("CollisionShape").shape.get_instance_id()});return
		if pending_stage=="player_enter":
			if pending_stage_elapsed_s<ENTRY_SECONDS:return
			_release_entry_control();_clear_door_cue()
			var index:=_adopt(body);pending_car=null;riding=false;pending_stage="";pending_stage_elapsed_s=0.;_pending_driver={}
			if _mount(index):
				var safety: Variant=host.get("city_public_safety")
				if is_instance_valid(safety) and safety.has_method("report_offense"):safety.report_offense("vehicle_theft",body.global_position)
			else:_notice="자동차가 정차했습니다. 문 옆에서 E로 다시 타세요.";_notice_until=_clock+3.
			return
		return
	super._physics_process(delta)
func _set_pending_stage(value: String) -> void:
	pending_stage=value;pending_stage_elapsed_s=0.;_event("takeover_stage_changed",{"stage":value})
func _custody_owner() -> bool:
	return host.has_method("_sandbox_detained") and host._sandbox_detained()
func _release_entry_control() -> void:
	if not _entry_owned_control:return
	_entry_owned_control=false
	if not _custody_owner():host.player.set_facility_control(false);host.player.set_physics_process(_entry_saved_physics);host.player.require_neutral_input()
func _handoff_clear(body: CharacterBody3D) -> bool:
	var support:=_ground(body.global_position)
	var excludes: Array[RID]=[body.get_rid(),host.player.get_rid()]
	if not support.is_empty():excludes.append(support.rid)
	if is_instance_valid(host.terrain_surface.support):excludes.append(host.terrain_surface.support.get_rid())
	return not support.is_empty() and _footprint_allowed(body.global_position,body.global_basis) and _clear_box(body.global_position,body.global_basis,excludes)
func _public_driver_floor(at: Vector3,exclude: Array[RID]=[]) -> Dictionary:
	for offset: Vector3 in [Vector3.ZERO,Vector3(.28,0,0),Vector3(-.28,0,0),Vector3(0,0,.28),Vector3(0,0,-.28)]:
		var sample:=at+offset;var local: Vector3=host.city.to_local(sample)
		if not host.player.free_roam_bounds.grow(-.6).has_point(Vector2(sample.x,sample.z)) or _private_index.contains(Vector2(local.x,local.z)):return {}
		for door: Vector3 in _doors:
			if Vector2(sample.x-door.x,sample.z-door.z).length()<.75:return {}
	var floor:=_ground(at)
	if floor.is_empty() or absf(floor.point.y-at.y)>.45:return {}
	var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,floor.point+Vector3.UP*.86);query.collision_mask=1|2|4|8|32;query.exclude=exclude.duplicate();query.exclude.append(floor.rid);query.margin=.003
	if is_instance_valid(host.terrain_surface.support):query.exclude.append(host.terrain_surface.support.get_rid())
	return floor if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty() else {}
func _driver_segment_clear(a: Vector3,b: Vector3,exclude: Array[RID]) -> bool:
	for step: int in range(1,maxi(1,ceili(a.distance_to(b)/.18))+1):
		if _public_driver_floor(a.lerp(b,float(step)/maxi(1,ceili(a.distance_to(b)/.18))),exclude).is_empty():return false
	var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,a+Vector3.UP*.86);query.collision_mask=1|2|4|8|32;query.exclude=exclude;query.margin=.003;query.motion=b-a
	return get_world_3d().direct_space_state.cast_motion(query)[0]>=.9999
func _driver_departure(body: CharacterBody3D,preferred_side: float) -> Dictionary:
	# No pre-existing seated driver is replaced. A separately authored adult is
	# introduced only at a full native exterior capsule; the original car box
	# remains solid. The short visible step-away is then physically swept.
	for side: float in [preferred_side,-preferred_side]:
		for lateral: float in [1.60,1.85,2.15]:
			for z: float in [-.38,.20,.70]:
				var start:=_public_driver_floor(body.to_global(Vector3(side*lateral,0,z)))
				if start.is_empty() or not _outside_future_car_box(body,start.point,side):continue
				for offset: Vector3 in [Vector3(side*1.8,0,0),Vector3(side*1.4,0,1.2),Vector3(side*1.4,0,-1.2)]:
					var goal:=_public_driver_floor(start.point+body.global_basis*offset)
					if not goal.is_empty() and _driver_segment_clear(start.point,goal.point,[]):return {"point":start.point,"goal":goal.point,"car_id":body.get_instance_id(),"side":side}
	return {}
func _outside_future_car_box(body: CharacterBody3D,feet: Vector3,side: float) -> bool:
	# The later player car uses a larger conservative guard box than some AI
	# originals. On a banked road, an upright adult's shoulders may otherwise
	# enter that tilted box despite a clear original shape at foot level.
	for height: float in [0.,1.70]:
		if side*body.to_local(feet+Vector3.UP*height).x<CAR_SIZE.x*.5+.30:return false
	return true
func _spawn_driver(departure: Dictionary) -> bool:
	if drivers.size()>=MAX_DEPARTED_DRIVERS:
		var oldest: Dictionary=drivers[0]
		if oldest==_pending_driver:return false
		host.traffic.humans.erase(oldest.body);oldest.body.queue_free();drivers.pop_front()
	var actor:=DepartedDriver.new();actor.name="DepartedTrafficDriver"+str(_clock*1000.);actor.set_meta("authored_departed_driver",true);actor.collision_layer=4;actor.collision_mask=1|2|4|8|32;actor.floor_snap_length=.35;actor.safe_margin=.001
	var shape:=CollisionShape3D.new();shape.name="CollisionShape";var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70;shape.shape=capsule;shape.position.y=.85;actor.add_child(shape)
	var visual:=Node3D.new();visual.name="Visual";actor.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";visual.add_child(original);add_child(actor);actor.global_position=departure.point
	var avatar:=DRIVER_AVATAR.new()
	if not avatar.setup(actor):actor.queue_free();return false
	var facing: Vector3=departure.goal-departure.point;visual.rotation.y=atan2(-facing.x,-facing.z)
	var proxy:=PhysicsReset.new();proxy.name="InterpolatedDepartedDriverVisual";proxy.process_physics_priority=-100;visual.add_child(proxy)
	for child: Node in visual.get_children():
		if child!=proxy:child.reparent(proxy,false)
	_pending_driver={"body":actor,"visual":visual,"avatar":avatar,"proxy":proxy,"state":"exiting","goal":departure.goal,"car_id":departure.car_id,"distance_m":0.,"maximum_step_m":0.,"spawn":departure.point,"previous":visual.global_transform,"current":visual.global_transform}
	drivers.append(_pending_driver);host.traffic.register_human(actor);return true
func _move_departed_drivers(delta: float) -> void:
	for row: Dictionary in drivers:
		var actor: CharacterBody3D=row.body
		if not is_instance_valid(actor):continue
		if preload("res://scripts/actor_hit_reaction.gd").owns(actor):
			# The reaction moves the retained capsule earlier in this tick.
			# Publish both render endpoints even while route control yields.
			row.previous=row.current;row.current=row.visual.global_transform
			continue
		row.previous=row.visual.global_transform
		var toward: Vector3=row.goal-actor.global_position;toward.y=0.
		var motion:=toward.limit_length(1.35*delta) if row.state=="leaving" else Vector3.ZERO
		if not motion.is_zero_approx() and not _driver_segment_clear(actor.global_position,actor.global_position+motion,[actor.get_rid()]):motion=Vector3.ZERO;row.state="waiting_for_clearance"
		if row.state=="waiting_for_clearance" and _driver_segment_clear(actor.global_position,actor.global_position+toward.limit_length(.2),[actor.get_rid()]):row.state="leaving"
		var before:=actor.global_position;actor.velocity=Vector3(motion.x/delta,-.12 if actor.is_on_floor() else maxf(actor.velocity.y-9.8*delta,-8.),motion.z/delta);actor.move_and_slide()
		var distance:=Vector2(actor.global_position.x-before.x,actor.global_position.z-before.z).length();row.distance_m+=distance;row.maximum_step_m=maxf(row.maximum_step_m,distance);row.current=row.visual.global_transform
		if toward.length()<.10 and row.state=="leaving":row.state="standing"
func _make_door_cue(body: CharacterBody3D,side: float) -> void:
	_clear_door_cue();_door_cue=Node3D.new();_door_cue.name="AuthoredDoorHandleCue";body.get_node("Visual").add_child(_door_cue);_door_cue.position=Vector3(side*1.10,.96,-.12)
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.035,.04,.22);mesh.mesh=box
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.85,.88,.90);material.metallic=.7;mesh.material_override=material;_door_cue.add_child(mesh)
func _clear_door_cue() -> void:
	if is_instance_valid(_door_cue):_door_cue.queue_free()
	_door_cue=null
func honk() -> bool:
	if not loaded or not riding or is_instance_valid(pending_car) or rental_index<0 or not _context_ready() or _clock<_horn_cooldown_until:return false
	var audio: Node3D=host.get("city_vehicle_audio")
	if not is_instance_valid(audio) or not audio.loaded or not audio.enabled or audio.gain<=.001:return false
	if not is_instance_valid(_horn):
		_horn=AudioStreamPlayer3D.new();_horn.name="OriginalSynthesizedCarHorn";_horn.max_distance=70.;_horn.unit_size=5.;_horn.max_db=-8.;add_child(_horn)
		var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=22050;var pcm:=PackedByteArray();pcm.resize(11025*2)
		for index: int in range(11025):
			var t:=float(index)/22050.;var envelope:=minf(1.,t/.025)*minf(1.,(.5-t)/.06);var sample:=(sin(TAU*384.*t)*.30+sin(TAU*512.*t)*.23)*envelope;pcm.encode_s16(index*2,roundi(sample*32767.))
		stream.data=pcm;_horn.stream=stream
	_horn.bus=audio.bus_name;_horn.volume_db=-17.+linear_to_db(audio.gain);_horn.global_position=bikes[rental_index].body.global_position+Vector3.UP*.7;_horn.play();_horn_cooldown_until=_clock+.7;horn_count+=1;_event("car_horn",{"body_id":bikes[rental_index].body.get_instance_id(),"original_synthesized_audio":true});return true
func _try_dismount() -> bool:
	var result:=super._try_dismount()
	if result:
		rental_index=-1
		host.exploration_avatar.play_sandbox_action("vehicle_exit",.55)
	return result
func cancel_ride_for_teleport() -> void:
	if is_instance_valid(pending_car):_cancel_pending();return
	super.cancel_ride_for_teleport()
func cancel_for_external_teleport() -> void:cancel_ride_for_teleport()
func after_external_teleport() -> void:cancel_ride_for_teleport()
func viewpoint() -> Dictionary:
	for body: CharacterBody3D in traffic_cars:
		for offset: Vector3 in [Vector3(-2.15,0,-.38),Vector3(2.15,0,-.38)]:
			var safe: Dictionary=host.interior_visit._safe_external_point(body.to_global(offset))
			if not safe.is_empty():return {"point":safe.point,"toward":body.global_position+Vector3.UP*.85,"id":body.get_route_id(),"camera_yaw":body.global_rotation.y+.6,"camera_pitch_degrees":-14.,"camera_distance_m":7.2}
	return {}
func snapshot() -> Dictionary:
	var rows: Array=[];var retained:=true
	for body: CharacterBody3D in traffic_cars:
		var initial: Dictionary=_identity[body.get_instance_id()]
		var same: bool=body.get_instance_id()==initial.body_id and body.get_node("Visual").get_instance_id()==initial.visual_id and body.get_node("CollisionShape").get_instance_id()==initial.shape_id and body.get_node("CollisionShape").shape.get_instance_id()==initial.original_shape and body.get_route_id()==initial.route_id
		retained=retained and same
		rows.append({"body_id":body.get_instance_id(),"route_id":body.get_route_id(),"seized":_seized.has(body.get_instance_id()),"position":body.global_position,"identity_retained":same,"ai_processing":body.is_physics_processing(),"registered_with_ai_manager":body._manager.vehicles.has(body)})
	var driver_rows: Array=[]
	for driver: Dictionary in drivers:
		if is_instance_valid(driver.body):driver_rows.append({"body_id":driver.body.get_instance_id(),"car_id":driver.car_id,"state":driver.state,"position":driver.body.global_position,"spawn":driver.spawn,"goal":driver.goal,"distance_m":driver.distance_m,"maximum_step_m":driver.maximum_step_m,"capsule":driver.body.get_node("CollisionShape").shape is CapsuleShape3D,"textured_adult":is_instance_valid(driver.avatar._textured_surface),"render_anchor":driver.proxy.global_position,"physics_anchor":driver.current.origin,"previous_anchor":driver.previous.origin})
	return {"pending_stage":pending_stage,"pending_stage_elapsed_s":pending_stage_elapsed_s,"entry_control_owned":_entry_owned_control,"driver_count":drivers.size(),"driver_limit":MAX_DEPARTED_DRIVERS,"departed_drivers":driver_rows,"horn_count":horn_count,"loaded":loaded,"error":load_error,"riding":riding,"pending_stop":is_instance_valid(pending_car),"pending_elapsed_s":pending_elapsed_s,"pending_initial_speed_mps":pending_initial_speed_mps,"pending_actual_distance_m":pending_actual_distance_m,"exit_requested":exit_requested,"speed_mps":speed_mps,"seized_car_count":bikes.size(),"original_ai_car_count":traffic_cars.size(),"original_identities_retained":retained,"spawned_replacement_cars":0,"actual_distance_m":actual_distance_m,"blocked_reason":blocked_reason,"pending_pair_release_count":_collision_release_pending.size(),"cars":rows,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"Original traffic-car bodies, original shape resources and original visible models retained; stopped along their original physical source route, exterior driver reaction and near-door timed player entry, then direct player car controls. Exterior authored textured drivers use swept native capsules; original monolithic car doors are not articulated. Seized cars remain parked and driveable; other original AI continues."}

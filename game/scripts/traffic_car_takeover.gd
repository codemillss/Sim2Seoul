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
	if riding:return true
	return host.player.free_roam_enabled and not host.player.facility_control and host.player.is_physics_processing() and _player_supported_for_mount() and is_instance_valid(_nearest_car())
func prompt_text() -> String:
	if not loaded or not _context_ready():return ""
	if is_instance_valid(pending_car):return "차량을 세우는 중 · 가까이 따라가 문 옆에서 기다리세요\nE · 취소" if float(pending_car._speed_mps)>.05 else "정차했습니다 · 차 문 옆으로 다가가면 탑승\nE · 취소"
	if riding:return "도로 자동차 · %d km/h · W 가속 / S 제동·후진\nA·D 조향 / Space 브레이크 / E 정차 후 내리기"%roundi(absf(speed_mps)*3.6) if not exit_requested else "안전하게 정차하고 내릴 공간을 확인하는 중\nE · 취소하고 계속 운전"
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
	pending_car=body;pending_elapsed_s=0.;pending_actual_distance_m=0.;pending_initial_speed_mps=float(body._speed_mps);_pending_was_running=bool(body._running)
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
	# The vehicle-movement checkbox can change while this request is paused in
	# the menu. Respect that current choice on E, timeout or external cancel.
	if is_instance_valid(host.traffic_switch):resume_running=host.traffic_switch.button_pressed
	if resume_running:body._running=true
	else:body.set_running(false)
	body.set_physics_process(true)
	pending_car=null;riding=false;pending_elapsed_s=0.;_event("traffic_stop_cancelled",{"body_id":body.get_instance_id(),"current_traffic_enabled":resume_running})
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
func _process(delta: float) -> void:super._process(delta)
func _physics_process(delta: float) -> void:
	if not loaded or delta<=0.:return
	if is_instance_valid(pending_car):
		_finish_collision_release();_clock+=delta;pending_elapsed_s+=delta
		var body:=pending_car;var before:=body.global_position
		body._terrain_clearance_distance_this_tick_m=0.;body._apply_terrain_orientation(delta);body._find_support()
		body._permission=body._manager.permission(body)
		var safe_budget: float=body._choose_step_budget(delta)
		var stopping_speed:=move_toward(float(body._speed_mps),0.,float(body.BRAKE_MPS2)*delta)
		var distance: float=body._move_on_polyline(minf(safe_budget,stopping_speed*delta),delta)
		body._speed_mps=distance/delta;body.velocity=-body.global_basis.z*body._speed_mps;pending_actual_distance_m+=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length()
		if pending_elapsed_s>10. or host.player.global_position.distance_to(body.global_position)>12.:_cancel_pending();return
		if body._speed_mps>.05:return
		if not _player_supported_for_mount() or _door_distance_for(body)>float(design.policy.interact_distance_m) or not _visible_car(body):return
		# Validate with the same complete source/native car guards BEFORE removing
		# the original AI manager entry. A denied handoff never strands its FIFO.
		var support:=_ground(body.global_position)
		var excludes: Array[RID]=[body.get_rid(),host.player.get_rid()]
		if not support.is_empty():excludes.append(support.rid)
		if is_instance_valid(host.terrain_surface.support):excludes.append(host.terrain_surface.support.get_rid())
		if support.is_empty() or not _footprint_allowed(body.global_position,body.global_basis) or not _clear_box(body.global_position,body.global_basis,excludes):blocked_reason="traffic_safe_handoff_blocked";return
		var index:=_adopt(body);pending_car=null;riding=false
		if _mount(index):
			var safety: Variant=host.get("city_public_safety")
			if is_instance_valid(safety) and safety.has_method("report_offense"):safety.report_offense("vehicle_theft",body.global_position)
		else:_notice="자동차가 정차했습니다. 문 옆에서 E로 다시 타세요.";_notice_until=_clock+3.
		return
	super._physics_process(delta)
func _try_dismount() -> bool:
	var result:=super._try_dismount()
	if result:rental_index=-1
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
	return {"loaded":loaded,"error":load_error,"riding":riding,"pending_stop":is_instance_valid(pending_car),"pending_elapsed_s":pending_elapsed_s,"pending_initial_speed_mps":pending_initial_speed_mps,"pending_actual_distance_m":pending_actual_distance_m,"exit_requested":exit_requested,"speed_mps":speed_mps,"seized_car_count":bikes.size(),"original_ai_car_count":traffic_cars.size(),"original_identities_retained":retained,"spawned_replacement_cars":0,"actual_distance_m":actual_distance_m,"blocked_reason":blocked_reason,"pending_pair_release_count":_collision_release_pending.size(),"cars":rows,"events":events.duplicate(true),"source_geometry_changed":false,"scope":"Original traffic-car bodies, original shape resources and original visible models retained; stopped along their original physical source route, then direct player car controls. Seized cars remain parked and driveable; other original AI continues."}

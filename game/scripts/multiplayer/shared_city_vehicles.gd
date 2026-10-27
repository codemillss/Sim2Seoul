extends "res://scripts/drivable_car_service.gd"
## Reversible shared-room adapter for the fourteen existing traffic cars.
## AI belongs to the room host. Only an approved lease holder runs local driving.
## This is pose replication, not server-owned shared collision simulation.
const DELAY_MS := 600.0
const REPLICA_META := "shared_city_vehicle_replica"
const CONTROLLED_META := "shared_city_vehicle_controlled"
const NO_RECYCLE_META := "shared_city_no_recycle"
const IDS := ["sejong_south", "sejong_north", "sejong_south_stream_1", "sejong_south_stream_2", "sejong_north_stream_1", "sejong_north_stream_2", "coverage_drive_0_car_0", "coverage_drive_0_car_1", "coverage_drive_1_car_0", "coverage_drive_1_car_1", "coverage_drive_2_car_0", "coverage_drive_2_car_1", "coverage_drive_3_car_0", "coverage_drive_3_car_1"]
var _request_action: Callable
var _cars: Dictionary = {}
var _rows: Dictionary = {}
var _saved_cars: Dictionary = {}
var _saved_managers: Dictionary = {}
var _buffers: Dictionary = {}
var _latest: Dictionary = {}
var _active := false
var _self_id := ""
var _host_id := ""
var _driver_id := ""
var _driver_epoch := -1
var _drive_sequence := 0
var _server_ms := -1.0
var _received_ms := -1
var _presented_ms := -1.0
var _pending_action := ""
var _pending_action_ms := -1
var _exit_sent_for := ""
var _exit_sent_epoch := -1
var _prejoin_player := Vector3.ZERO
var _cleanup_pending := false
var _bus_saved: Dictionary = {}
var _ending := false

func setup(scene: Node3D, request_action: Callable = Callable()) -> bool:
	if loaded or not is_instance_valid(scene) or not request_action.is_valid() or not is_inside_tree(): return false
	host = scene
	var donor: Node = host.get("drivable_car_service")
	var neighborhood: Node = host.get("neighborhood_population")
	if not is_instance_valid(donor) or not donor.loaded or not is_instance_valid(neighborhood) or not is_instance_valid(neighborhood.traffic): return false
	var source: Array = []
	source.append_array(host.vehicles); source.append_array(neighborhood.traffic.vehicles)
	if source.size() != IDS.size(): return false
	for body: CharacterBody3D in source:
		if not is_instance_valid(body) or not body.has_method("get_route_id"): return false
		var route: String = body.get_route_id()
		if route not in IDS or _cars.has("car:" + route) or not body.get_node_or_null("Visual") is Node3D or not body.get_node_or_null("CollisionShape") is CollisionShape3D: return false
		_cars["car:" + route] = body
	design = donor.design.duplicate(true)
	design.policy.interact_distance_m = 5.0
	_private_index = donor._private_index; _road_index = donor._road_index; _walk_index = donor._walk_index
	_drive_grid = donor._drive_grid; _doors = donor._doors.duplicate()
	_request_action = request_action
	# Cleanup must finish even when the room/menu keeps the local tree paused.
	# Explicitly gate player driving below; this node does not activate physics.
	process_mode = Node.PROCESS_MODE_ALWAYS; process_physics_priority = 2
	var finish := PoseFinish.new(); finish.service = self; finish.process_physics_priority = 3; add_child(finish)
	loaded = true
	return true

func _pose(body: CharacterBody3D, motion: String) -> Dictionary:
	return {"id": "car:" + body.get_route_id(), "kind": "vehicle", "position": _vector3(body.global_position), "rotation": _vector3(body.global_rotation), "velocity": _vector3(body.velocity), "motion": motion}

func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not loaded: return result
	for id: String in _cars:
		var body: CharacterBody3D = _cars[id]
		result.append(_pose(body, "ai" if bool(body.get("_running")) and body.is_physics_processing() else "parked"))
	return result

func begin(local_self_id: String, host_id: String, entities: Array) -> bool:
	if not loaded or _active or _cleanup_pending or local_self_id.is_empty() or host_id.is_empty(): return false
	if host.player.facility_control or host.player.interior_active or host._street_transport_riding(): return false
	var checked := _validated(entities)
	if checked.size() != IDS.size(): return false
	for body: CharacterBody3D in _cars.values():
		if bool(body.get_meta("player_seized_traffic_car", false)) or not body.get("_manager").vehicles.has(body):
			load_error = "이미 빼앗은 도로 자동차가 있어 함께 운전을 시작할 수 없습니다. 기존 차량 상태는 유지했습니다."
			return false
	_self_id = local_self_id; _host_id = host_id; _prejoin_player = host.player.global_position
	for id: String in _cars:
		var body: CharacterBody3D = _cars[id]
		_saved_cars[id] = {"script": _script_state(body), "transform": body.global_transform, "velocity": body.velocity, "physics": body.is_physics_processing(), "process_mode": body.process_mode, "layer": body.collision_layer, "mask": body.collision_mask, "replica": _metadata(body, REPLICA_META), "controlled": _metadata(body, CONTROLLED_META), "no_recycle": _metadata(body, NO_RECYCLE_META)}
		# Prevent the original camera-only respawn from jumping across a shared
		# snapshot. Cars remain visible/stationary at the endpoint and driveable.
		body.set_meta(NO_RECYCLE_META, true)
		var manager: Node = body.get("_manager")
		if not _saved_managers.has(manager): _saved_managers[manager] = {"script": _script_state(manager), "replica": _metadata(manager, REPLICA_META)}
		_rows[id] = _make_row(body)
		_buffers[id] = []
	for manager: Node in _saved_managers: manager.set_meta(REPLICA_META, _self_id != _host_id)
	_suspend_solo_buses()
	_active = true; _ending = false; _latest = {}; _server_ms = -1.0; _received_ms = -1; _presented_ms = -1.0
	apply_snapshot(checked.values(), 0.0)
	return true

func _suspend_solo_buses() -> void:
	if not _has_property(host, "city_bus_service"): return
	var service: Node = host.get("city_bus_service")
	if not is_instance_valid(service) or not bool(service.get("loaded")): return
	var bodies: Array = []
	for body: CharacterBody3D in service.buses:
		bodies.append({"body": body, "script": _script_state(body), "transform": body.global_transform, "velocity": body.velocity, "visible": body.visible, "physics": body.is_physics_processing(), "layer": body.collision_layer, "mask": body.collision_mask})
		body.set_physics_process(false); body.visible = false; body.collision_layer = 0; body.collision_mask = 0
	_bus_saved = {"service": service, "script": _script_state(service), "physics": service.is_physics_processing(), "process": service.is_processing(), "bodies": bodies}
	service.set_physics_process(false); service.set_process(false); service.loaded = false

func _restore_solo_buses() -> void:
	if _bus_saved.is_empty(): return
	var service: Node = _bus_saved.service
	for property: String in _bus_saved.script: service.set(property, _copy(_bus_saved.script[property]))
	for row: Dictionary in _bus_saved.bodies:
		var body: CharacterBody3D = row.body
		for property: String in row.script: body.set(property, _copy(row.script[property]))
		body.global_transform = row.transform; body.velocity = row.velocity; body.visible = row.visible
		body.collision_layer = row.layer; body.collision_mask = row.mask; body.set_physics_process(row.physics); body.reset_physics_interpolation()
	service.set_physics_process(_bus_saved.physics); service.set_process(_bus_saved.process)
	_bus_saved.clear()

func _make_row(body: CharacterBody3D) -> Dictionary:
	var visual: Node3D = body.get_node("Visual")
	var children := visual.get_children()
	var proxy := PhysicsReset.new(); proxy.name = "SharedCityVehicleProxy"; proxy.process_physics_priority = -100; visual.add_child(proxy)
	for child: Node in children: child.reparent(proxy, false)
	var steering := Node3D.new(); steering.position = Vector3(-.42, .98, -.48); proxy.add_child(steering)
	var grips: Array[Node3D] = []
	for side: float in [-1.0, 1.0]:
		var grip := Node3D.new(); grip.position = Vector3(side * .16, 0, 0); steering.add_child(grip); grips.append(grip)
	var front := Node3D.new(); proxy.add_child(front)
	var crank := Node3D.new(); proxy.add_child(crank)
	var kickstand := Node3D.new(); proxy.add_child(kickstand)
	return {"body": body, "visual": visual, "proxy": proxy, "original_children": children, "visual_transform": visual.transform, "shape": body.get_node("CollisionShape"), "station_id": "", "rented": false, "yaw": body.global_rotation.y, "wheel_phase": 0.0, "distance_m": 0.0, "previous": body.global_transform, "current": body.global_transform, "front": front, "wheels": [], "crank": crank, "pedals": [], "kickstand": kickstand, "steering": steering, "grips": grips}

func _vector3(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func _valid_vector(value: Variant, position := false) -> bool:
	if not value is Array or value.size() != 3: return false
	for part: Variant in value:
		if not (part is int or part is float) or not is_finite(float(part)): return false
	if position and (absf(float(value[0])) > 1000.0 or absf(float(value[2])) > 1000.0 or float(value[1]) < -100.0 or float(value[1]) > 500.0): return false
	return true

func _validated(entities: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in entities:
		if not value is Dictionary: continue
		var id: Variant = value.get("id")
		if not id is String or not _cars.has(id): continue
		if result.has(id): return {}
		if value.get("kind", "vehicle") != "vehicle" or value.get("mode") not in ["ai", "parked", "driven"]: return {}
		if not _valid_vector(value.get("position"), true) or not _valid_vector(value.get("rotation")) or not _valid_vector(value.get("velocity")): return {}
		var epoch: Variant = value.get("leaseEpoch", 0)
		var driver: Variant = value.get("driverId", "")
		if not (epoch is int or epoch is float) or not is_finite(float(epoch)) or float(epoch) < 0 or float(epoch) != floorf(float(epoch)) or float(epoch) > 2147483647.0 or not driver is String: return {}
		if (value.mode == "driven") != (not String(driver).is_empty()): return {}
		result[id] = value.duplicate(true)
	return result

func apply_snapshot(entities: Array, server_now_ms: float) -> bool:
	if not _active or _ending: return true
	if not is_finite(server_now_ms) or server_now_ms < 0: return false
	if server_now_ms < _server_ms: return true
	var checked := _validated(entities)
	if checked.size() != IDS.size(): return false
	# Validate the whole batch before changing authority or accepting any pose.
	var local_claims := 0
	for id: String in checked:
		var row: Dictionary = checked[id]
		if _latest.has(id) and int(row.leaseEpoch) < int(_latest[id].leaseEpoch): return true
		if row.driverId == _self_id: local_claims += 1
	if local_claims > 1: return false
	var received := Time.get_ticks_msec()
	var authority_transitions: Array[String] = []
	for id: String in checked:
		var row: Dictionary = checked[id]
		var previous: Dictionary = _latest.get(id, {})
		if not previous.is_empty() and server_now_ms == _server_ms and row == previous: continue
		var body: CharacterBody3D = _cars[id]
		var host_ai: bool = _self_id == _host_id and row.mode == "ai"
		body.set_meta(REPLICA_META, not host_ai)
		body.set_meta(CONTROLLED_META, row.mode != "ai")
		if host_ai: body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.set_physics_process(host_ai)
		if not host_ai: body.velocity = Vector3.ZERO
		if row.mode != "ai": _drop_reservation(body)
		var buffer: Array = _buffers[id]
		if not previous.is_empty() and (int(previous.leaseEpoch) != int(row.leaseEpoch) or previous.driverId != row.driverId or previous.mode != row.mode):
			# A released car must not revisit its earlier driven poses while the
			# 600ms clock catches up. A lease/mode boundary starts a new segment.
			buffer.clear(); authority_transitions.append(id)
		buffer.append({"at": server_now_ms, "row": row})
		while buffer.size() > 32: buffer.pop_front()
		if previous.is_empty() and not host_ai: _place_row(id, row)
	_latest = checked; _server_ms = server_now_ms; _received_ms = received
	# Keep the original inventories locally, but omit leased/parked cars from
	# the host FIFO loops. They still exist as physical obstacles in the city.
	for manager: Node in _saved_managers:
		var eligible: Array[CharacterBody3D] = []
		for body: CharacterBody3D in _saved_managers[manager].script.vehicles:
			var id: String = "car:" + body.get_route_id()
			if _latest[id].mode == "ai": eligible.append(body)
		manager.vehicles = eligible
	if not _pending_action.is_empty() and String(_latest[_pending_action].driverId) == _self_id:
		_pending_action = ""; _pending_action_ms = -1
	if riding and (_latest[_driver_id].driverId != _self_id or int(_latest[_driver_id].leaseEpoch) != _driver_epoch):
		_release_drive(false)
	if not riding:
		for id: String in _latest:
			if _latest[id].driverId == _self_id:
				_try_approved_mount(id)
				break
	for id: String in authority_transitions:
		# If a local lease was revoked while its safe exit is blocked, keep the
		# held capsule/car pair still until exit succeeds. Every other replica
		# publishes the new approved collision pose immediately.
		if not riding or id != _driver_id: _place_row(id, _latest[id])
	return true

func _drop_reservation(body: CharacterBody3D) -> void:
	var manager: Node = body.get("_manager")
	var route: String = body.get_route_id()
	manager.queue.erase(route)
	if manager.zone_owner == route: manager.zone_owner = ""
	if _has_property(manager, "zones"):
		for zone: Dictionary in manager.zones.values():
			zone.queue.erase(route)
			if zone.owner == route: zone.owner = ""
	manager.guards.erase(route); manager.refreshed_tick = -1

func _try_approved_mount(id: String) -> void:
	if not _active or _ending or _cleanup_pending or riding or not _latest.has(id): return
	var lease: Dictionary = _latest[id]
	if lease.driverId != _self_id or lease.mode != "driven": return
	if get_tree().paused or host.menu.visible: return
	var body: CharacterBody3D = _cars[id]
	var approved_pose := Transform3D(Basis.from_euler(_v(lease.rotation)), _v(lease.position))
	var approved_distance := INF
	for side: float in [-1.0, 1.0]: approved_distance = minf(approved_distance, host.player.global_position.distance_to(approved_pose * Vector3(side * 1.20, 0, -.38)))
	if host.player.facility_control or host.player.interior_active or host._street_transport_riding() or approved_distance > 5.0:
		_reject_lease(id); return
	_place_row(id, lease)
	var row: Dictionary = _rows[id]
	row.yaw = body.global_rotation.y; row.previous = body.global_transform; row.current = body.global_transform
	bikes = [row]; rental_index = -1
	_car_steering_wheel = row.steering; _driver_grips = row.grips
	if not super._mount(0):
		bikes.clear(); rental_index = -1; _reject_lease(id); return
	_driver_id = id; _driver_epoch = int(lease.leaseEpoch); _drive_sequence = 0; _exit_sent_for = ""; _exit_sent_epoch = -1
	_notice = "같은 방 자동차 · 운전권 승인"; _notice_until = _clock + 2.0

func _reject_lease(id: String) -> void:
	var epoch := int(_latest[id].leaseEpoch)
	if _exit_sent_for == id and _exit_sent_epoch == epoch: return
	if not _queue_exit(id): return
	_exit_sent_for = id; _exit_sent_epoch = epoch
	_notice = "지금은 안전하게 탈 수 없어 운전권을 반납했습니다."; _notice_until = _clock + 3.0

func _queue_exit(id: String) -> bool:
	var result: Variant = _request_action.call("vehicle_exit", id)
	if not result is String: return false
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return pattern.search(result) != null

func _door_distance_for(body: CharacterBody3D) -> float:
	var best := INF
	for side: float in [-1.0, 1.0]: best = minf(best, host.player.global_position.distance_to(body.to_global(Vector3(side * 1.20, 0, -.38))))
	return best

func _nearest_shared() -> String:
	var selected := ""; var best := 5.0
	for id: String in _cars:
		var distance := _door_distance_for(_cars[id])
		if distance < best and _visible_shared(_cars[id]): best = distance; selected = id
	return selected

func _visible_shared(body: CharacterBody3D) -> bool:
	if absf(host.player.global_position.y - body.global_position.y) > .65: return false
	var excludes: Array[RID] = [body.get_rid(), host.player.get_rid()]
	for height: float in [.65, 1.20]:
		var ray := PhysicsRayQueryParameters3D.create(host.player.global_position + Vector3.UP * height, body.global_position + Vector3.UP * height, 1 | 4 | 8 | 32, excludes)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	return true

func is_riding() -> bool:
	return riding

func cleanup_pending() -> bool:
	return _cleanup_pending

func interaction_distance_m() -> float:
	if not _active: return INF
	if riding: return 0.0
	var id := _nearest_shared()
	return _door_distance_for(_cars[id]) if not id.is_empty() else INF

func can_interact() -> bool:
	if not _active or not _context_ready(): return false
	if riding: return true
	return not host.player.facility_control and host.player.is_physics_processing() and _player_supported_for_mount() and not _nearest_shared().is_empty()

func handle_interact() -> bool:
	if not can_interact(): return false
	if riding:
		exit_requested = not exit_requested
		return true
	if not _pending_action.is_empty() and Time.get_ticks_msec() - _pending_action_ms < 6500: return true
	var id := _nearest_shared()
	if not _latest.has(id): return true
	if not String(_latest[id].driverId).is_empty():
		_notice = "다른 참가자가 운전 중입니다."; _notice_until = _clock + 3.0; return true
	_pending_action = id; _pending_action_ms = Time.get_ticks_msec()
	_request_action.call("vehicle_enter", id)
	_notice = "차량 운전권을 확인하고 있습니다."; _notice_until = _clock + 6.5
	return true

func prompt_text() -> String:
	if not _active: return ""
	if riding: return "같은 방 자동차 · %d km/h · W/S 가속·제동 / A·D 조향 / Space 브레이크 / E 안전 하차" % roundi(absf(speed_mps) * 3.6) if not exit_requested else "정차하고 하차 승인을 기다리는 중 · E 취소"
	if _clock < _notice_until: return _notice
	if not _nearest_shared().is_empty(): return "E · 같은 방 자동차 운전권 요청"
	return ""

func _try_dismount() -> bool:
	if not riding or absf(speed_mps) > float(design.policy.dismount_speed_mps): return false
	if _safe_dismount().is_empty(): blocked_reason = "dismount_blocked"; return false
	if _exit_sent_for != _driver_id or _exit_sent_epoch != _driver_epoch:
		if not _queue_exit(_driver_id): return false
		_exit_sent_for = _driver_id; _exit_sent_epoch = _driver_epoch
	return false # The server's release snapshot is the only exit approval.

func _release_drive(for_end: bool) -> bool:
	if not riding: return true
	var safe := _safe_end_point() if for_end else _safe_dismount()
	if safe.is_empty():
		# Lost lease must never keep reading movement input. Hold safely in place;
		# retry a real collision-checked exit on a later physics tick.
		speed_mps = 0.0; exit_requested = true; blocked_reason = "shared_exit_blocked"
		return false
	host.player.global_transform = Transform3D(Basis.IDENTITY, safe.point)
	_restore_player(true)
	_cleanup_pending = not _collision_release_pending.is_empty()
	_driver_id = ""; _driver_epoch = -1; _drive_sequence = 0; rental_index = -1
	return true

func drive_sample() -> Dictionary:
	if not _active or _ending or not riding or _driver_id.is_empty() or not _latest.has(_driver_id): return {}
	var lease: Dictionary = _latest[_driver_id]
	if lease.driverId != _self_id or int(lease.leaseEpoch) != _driver_epoch: return {}
	var body: CharacterBody3D = _cars[_driver_id]
	_drive_sequence += 1
	return {"entityId": _driver_id, "leaseEpoch": _driver_epoch, "sequence": _drive_sequence, "position": _vector3(body.global_position), "rotation": _vector3(body.global_rotation), "velocity": _vector3(body.velocity)}

func sample_authority() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _active or _self_id != _host_id: return result
	for id: String in _cars:
		# Fixed catalog: server ignores these proposals for leased/parked cars.
		result.append(_pose(_cars[id], "ai" if _latest[id].mode == "ai" else "parked"))
	return result

func _sample_row(id: String, target: float) -> Dictionary:
	var buffer: Array = _buffers[id]
	if buffer.is_empty(): return {}
	if target <= float(buffer[0].at): return buffer[0].row
	for index: int in range(1, buffer.size()):
		var left: Dictionary = buffer[index - 1]; var right: Dictionary = buffer[index]
		if target > float(right.at): continue
		if float(right.at) <= float(left.at) or int(left.row.leaseEpoch) != int(right.row.leaseEpoch): return right.row
		var ratio := clampf((target - float(left.at)) / (float(right.at) - float(left.at)), 0.0, 1.0)
		var result: Dictionary = right.row.duplicate(true)
		result.position = _vector3(_v(left.row.position).lerp(_v(right.row.position), ratio))
		var qa := Quaternion(Basis.from_euler(_v(left.row.rotation))); var qb := Quaternion(Basis.from_euler(_v(right.row.rotation)))
		result.rotation = _vector3(Basis(qa.slerp(qb, ratio)).get_euler())
		result.velocity = _vector3(_v(left.row.velocity).lerp(_v(right.row.velocity), ratio))
		return result
	return buffer[-1].row # Hold, never extrapolate unapproved travel.

func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _place_row(id: String, value: Dictionary) -> void:
	var body: CharacterBody3D = _cars[id]
	body.global_transform = Transform3D(Basis.from_euler(_v(value.rotation)), _v(value.position))
	body.velocity = _v(value.velocity)
	var row: Dictionary = _rows[id]
	row.previous = body.global_transform; row.current = body.global_transform
	row.proxy.global_transform = body.global_transform * row.visual_transform

func _physics_process(delta: float) -> void:
	if not loaded or delta <= 0: return
	_finish_collision_release(); _cleanup_pending = not _collision_release_pending.is_empty()
	if _ending:
		_clock += delta
		return
	if get_tree().paused or host.menu.visible:
		_clock += delta
		return
	if not _active:
		_clock += delta
		if not _cleanup_pending: bikes.clear()
		return
	if riding:
		if not _latest.has(_driver_id) or _latest[_driver_id].driverId != _self_id or int(_latest[_driver_id].leaseEpoch) != _driver_epoch:
			_release_drive(false); _clock += delta
		else: super._physics_process(delta)
	else:
		_clock += delta
		for id: String in _latest:
			if _latest[id].driverId == _self_id: _try_approved_mount(id); break
	for id: String in _rows:
		if riding and id == _driver_id: continue
		var row: Dictionary = _rows[id]
		if _self_id == _host_id and _latest[id].mode == "ai":
			row.previous = row.current; row.current = row.body.global_transform

func _process(_delta: float) -> void:
	if not _active: return
	var target := _server_ms + maxf(0.0, float(Time.get_ticks_msec() - _received_ms)) - DELAY_MS
	_presented_ms = maxf(_presented_ms, target)
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		if (riding and id == _driver_id) or (_self_id == _host_id and _latest[id].mode == "ai"):
			row.proxy.global_transform = row.previous.interpolate_with(row.current, fraction) * row.visual_transform
		else:
			var value := _sample_row(id, _presented_ms)
			if not value.is_empty(): _place_row(id, value)

func _metadata(node: Node, key: String) -> Dictionary:
	return {"exists": node.has_meta(key), "value": node.get_meta(key) if node.has_meta(key) else null}

func _restore_metadata(node: Node, key: String, saved: Dictionary) -> void:
	if saved.exists: node.set_meta(key, saved.value)
	else: node.remove_meta(key)

func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary: return value.duplicate(true)
	if value is PackedVector3Array or value is PackedFloat64Array or value is PackedFloat32Array or value is PackedVector2Array or value is PackedStringArray: return value.duplicate()
	return value

func _has_property(node: Object, key: String) -> bool:
	for property: Dictionary in node.get_property_list():
		if String(property.name) == key: return true
	return false

func _script_state(node: Object) -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in node.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			result[String(property.name)] = _copy(node.get(property.name))
	return result

func _overlaps_saved_car(point: Vector3) -> bool:
	# Conservative capsule/OBB exclusion for the original, pre-room car poses.
	# The normal city safe-point query independently verifies current static space.
	for id: String in _saved_cars:
		var body: CharacterBody3D = _cars[id]
		var shape_node: CollisionShape3D = body.get_node("CollisionShape")
		if not shape_node.shape is BoxShape3D: return true
		var pose: Transform3D = _saved_cars[id].transform * shape_node.transform
		var feet: Vector3 = pose.affine_inverse() * point
		var half: Vector3 = shape_node.shape.size * .5
		if absf(feet.x) < half.x + .45 and absf(feet.z) < half.z + .45 and feet.y < half.y + .15 and feet.y + 1.85 > -half.y: return true
	return false

func _safe_end_point() -> Dictionary:
	var candidates: Array[Vector3] = [host.player.global_position, _prejoin_player]
	for offset: Vector3 in [Vector3(-2.4, 0, 0), Vector3(2.4, 0, 0), Vector3(0, 0, 3.4), Vector3(0, 0, -3.4)]:
		candidates.append(host.player.global_position + offset)
	if riding and rental_index >= 0:
		var body: CharacterBody3D = bikes[rental_index].body
		for offset: Vector3 in [Vector3(-2.4, 0, 0), Vector3(2.4, 0, 0), Vector3(0, 0, 3.4), Vector3(0, 0, -3.4)]: candidates.append(body.to_global(offset))
	for point: Vector3 in candidates:
		var safe: Dictionary = host.interior_visit._safe_external_point(point)
		if not safe.is_empty() and not _overlaps_saved_car(safe.point): return safe
	return {}

func end() -> bool:
	if not _active: return true
	_ending = true
	var owned_mount := riding
	var moved_foot := false
	if riding:
		if not _release_drive(true): return false
	if _cleanup_pending: return false
	if not owned_mount and _overlaps_saved_car(host.player.global_position):
		# Another facility/transport may already own the solo player. Never
		# overwrite its capsule, camera, flags or transform while ending presence.
		if host.player.facility_control or host.player.interior_active or host._street_transport_riding(): return false
		var safe := _safe_end_point()
		if safe.is_empty(): return false
		host.player.global_transform = Transform3D(Basis.IDENTITY, safe.point)
		host.player.velocity = Vector3.ZERO; host.player.require_neutral_input(); host.player.reset_physics_interpolation()
		moved_foot = true
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		for child: Node in row.original_children:
			if is_instance_valid(child): child.reparent(row.visual, false)
		row.visual.transform = row.visual_transform
		row.proxy.get_parent().remove_child(row.proxy); row.proxy.queue_free()
	for manager: Node in _saved_managers:
		for property: String in _saved_managers[manager].script: manager.set(property, _copy(_saved_managers[manager].script[property]))
		_restore_metadata(manager, REPLICA_META, _saved_managers[manager].replica)
	for id: String in _saved_cars:
		var body: CharacterBody3D = _cars[id]; var saved: Dictionary = _saved_cars[id]
		for property: String in saved.script: body.set(property, _copy(saved.script[property]))
		body.global_transform = saved.transform; body.velocity = saved.velocity; body.collision_layer = saved.layer; body.collision_mask = saved.mask
		_restore_metadata(body, REPLICA_META, saved.replica); _restore_metadata(body, CONTROLLED_META, saved.controlled)
		_restore_metadata(body, NO_RECYCLE_META, saved.no_recycle)
		body.process_mode = saved.process_mode; body.set_physics_process(saved.physics); body.reset_physics_interpolation()
	_restore_solo_buses()
	_active = false; _rows.clear(); _latest.clear(); _buffers.clear(); _saved_cars.clear(); _saved_managers.clear()
	_self_id = ""; _host_id = ""; _pending_action = ""; _exit_sent_for = ""; _exit_sent_epoch = -1
	if owned_mount or moved_foot: host.rig.snap_to_target_pose()
	return true

func cancel_ride_for_teleport() -> void:
	if riding:
		_request_action.call("vehicle_exit", _driver_id)
		_release_drive(false)

func diagnostic() -> Dictionary:
	return {"active": _active, "cars": _cars.size(), "riding": riding, "driver_entity": _driver_id, "lease_epoch": _driver_epoch, "pending_action": not _pending_action.is_empty(), "cleanup_pending": _cleanup_pending, "host_ai": _active and _self_id == _host_id, "error": load_error, "scope": "Fourteen retained traffic bodies; host AI and approved local driver; presentation replication, not authoritative shared physics"}

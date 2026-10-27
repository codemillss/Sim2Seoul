extends Node3D
## The owner retains existing route AI. Guests display only approved poses.
## No shared melee, custody, free chat or additional NPC population is created.
const INTERPOLATION_MS := 600
const MAX_SAMPLES := 16
const RANGE_M := 3.0
var host: Node3D
var active := false
var authority := false
var _request_action: Callable
var _actors: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _controllers: Array[Node] = []
var _saved_nodes: Array[Dictionary] = []
var _saved_bodies: Array[Dictionary] = []
var _saved_groups: Array[Dictionary] = []
var _saved_controllers: Array[Dictionary] = []
var _hidden: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _approved: Dictionary = {}
var _server_ms := -1.0
var _received_ms := 0
var _render_floor := 0.0
var _visual_clock := 0.0
var _saved_node_ids: Dictionary = {}

func setup(scene: Node3D, request_action: Callable) -> bool:
	if host != null or not is_instance_valid(scene) or not request_action.is_valid():return false
	host = scene; _request_action = request_action; name = "SharedCityNPCs"
	process_mode = Node.PROCESS_MODE_ALWAYS; process_priority = 20
	var legacy: Variant = host.get("exploration_pedestrians")
	var street: Variant = host.get("street_pedestrians")
	var population: Variant = host.get("neighborhood_population")
	if not is_instance_valid(legacy) or not is_instance_valid(street) or not is_instance_valid(population):return false
	var coverage: Variant = population.get("walkers")
	if not is_instance_valid(coverage):return false
	_controllers.assign([legacy, street, coverage])
	for row: Dictionary in legacy.human_visuals:
		var body: CharacterBody3D = row.body
		if not _register("npc:n02:" + String(body.get("_route_id")), "npc", body, body.get_node("Visual"), row.proxy, row):return false
	for controller: Node in [street, coverage]:
		for row: Dictionary in controller.actors:
			var kind: String = "dog" if row.kind == "dog" else "npc"
			var prefix: String = "npc:street:" if controller == street else "npc:coverage:"
			var suffix: String = (":dog" if kind == "dog" else ":walker") if controller == street else ""
			if not _register(prefix + String(row.group) + suffix, kind, row.body, row.visual, row.proxy, row):return false
	var dogs := 0
	for row: Dictionary in _actors:
		if row.kind == "dog":dogs += 1
	return _actors.size() == 30 and dogs == 2

func _register(id: String, kind: String, body: CharacterBody3D, visual: Node3D, proxy: Node3D, source: Dictionary) -> bool:
	if id.is_empty() or _by_id.has(id) or not is_instance_valid(body) or not is_instance_valid(visual) or not is_instance_valid(proxy):return false
	var row := {"id": id, "kind": kind, "body": body, "visual": visual, "proxy": proxy, "source": source}
	_actors.append(row); _by_id[id] = row
	return true

func _pose(row: Dictionary) -> Dictionary:
	var body: CharacterBody3D = row.body
	var rotation: Vector3 = row.visual.global_rotation
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	return {"id": row.id, "kind": row.kind, "position": _array(body.global_position), "rotation": _array(rotation),
		"velocity": _array(body.velocity), "motion": "run" if speed > 1.9 else ("walk" if speed > .08 else "idle")}

func catalog() -> Array:
	var result: Array = []
	for row: Dictionary in _actors:result.append(_pose(row))
	return result

func sample_authority() -> Array:
	return catalog() if active and authority else []

static func _array(value: Vector3) -> Array:return [value.x, value.y, value.z]

static func _vector(value: Variant) -> Variant:
	if not value is Array or value.size() != 3:return null
	for number: Variant in value:
		if not (number is int or number is float) or not is_finite(float(number)):return null
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _validated(entities: Array) -> Dictionary:
	var result: Dictionary = {}
	for item: Variant in entities:
		if not item is Dictionary:return {}
		# The shared world also contains vehicles. Only this stable catalog is owned here.
		if item.get("kind") not in ["npc", "dog"]:continue
		var id: Variant = item.get("id")
		if not id is String or not _by_id.has(id) or result.has(id) or item.kind != _by_id[id].kind:return {}
		var at: Variant = _vector(item.get("position")); var rotation: Variant = _vector(item.get("rotation")); var velocity: Variant = _vector(item.get("velocity"))
		if at == null or rotation == null or velocity == null or item.get("motion") not in ["idle", "walk", "run"]:return {}
		if absf(at.x) > 1000.0 or absf(at.z) > 1000.0 or at.y < -100.0 or at.y > 500.0:return {}
		var reaction: Variant = item.get("reactionKind", "")
		var until: Variant = item.get("reactionUntilMs", 0)
		if reaction not in ["", "greet", "pet", "hit", "shove"] or not (until is int or until is float) or not is_finite(float(until)) or float(until) < 0.0:return {}
		result[id] = {"position": at, "rotation": rotation, "velocity": velocity, "motion": item.motion,
			"reactionKind": reaction, "reactionUntilMs": float(until)}
	return result if result.size() == _actors.size() else {}

func begin(local_self_id: String, host_id: String, entities: Array) -> bool:
	if active or _actors.size() != 30 or local_self_id.is_empty() or host_id.is_empty():return false
	var accepted := _validated(entities)
	if accepted.is_empty():return false
	# Existing physical staggers/custody cannot safely change movement owner mid-step.
	var safety: Variant = host.get("city_public_safety")
	if is_instance_valid(safety) and (bool(safety.get("wanted")) or bool(safety.get("detained"))):return false
	for row: Dictionary in _actors:
		if preload("res://scripts/actor_hit_reaction.gd").owns(row.body):return false
	authority = local_self_id == host_id; _approved = accepted
	for controller: Node in _controllers:
		var previous_neighbors: Array = controller.get("shared_city_neighbors") if controller != _controllers[0] else []
		_saved_controllers.append({"node": controller, "replica": controller.shared_city_replica, "neighbors": previous_neighbors.duplicate(),
			"running": controller.running, "elapsed": controller.get("elapsed") if controller != _controllers[0] else 0.0})
		controller.shared_city_replica = not authority
		_save_always(controller)
		for group: Dictionary in controller.groups:
			var state: Dictionary = group.duplicate(true); state.erase("members")
			_saved_groups.append({"group": group, "state": state})
	for row: Dictionary in _actors:
		var body: CharacterBody3D = row.body
		_save_always(body)
		var metadata: Dictionary = {}
		for key: String in ["shared_city_remote", "shared_city_motion", "exploration_avoidance_adapter"]:
			metadata[key] = {"present": body.has_meta(key), "value": body.get_meta(key) if body.has_meta(key) else null}
		_saved_bodies.append({"body": body, "transform": body.global_transform, "velocity": body.velocity,
			"visual": row.visual.transform, "proxy": row.proxy.transform, "layer": body.collision_layer, "mask": body.collision_mask,
			"pickable": body.input_ray_pickable, "metadata": metadata, "script_state": _script_state(body),
			"source_state": _data_state(row.source), "dog_state": _script_state(row.source.get("dog_model"))})
		var collider: CollisionShape3D = _collider(body)
		_saved_bodies.back()["collider"] = collider
		_saved_bodies.back()["collider_transform"] = collider.transform if collider != null else Transform3D.IDENTITY
		if not authority:
			body.collision_layer = 0; body.collision_mask = 0; body.input_ray_pickable = false
			body.set_meta("shared_city_remote", true); body.set_meta("exploration_avoidance_adapter", true)
		var label := Label3D.new(); label.name = "SharedRoomReaction"; label.position.y = .9 if row.kind == "dog" else 2.05
		label.font_size = 36; label.pixel_size = .003; label.outline_size = 6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.visible = false
		body.add_child(label); row["label"] = label
	_suspend_extra(safety, "officers")
	if is_instance_valid(safety):
		var patrol: Variant = safety.get("patrol_vehicle_service")
		if is_instance_valid(patrol):_hide_node(patrol.get("body"))
	var emergency: Variant = host.get("city_weather_emergency")
	_suspend_extra(emergency, "firefighters")
	if is_instance_valid(emergency):
		for key: String in ["engine", "standby_engine", "_fire", "_rain"]:_hide_node(emergency.get(key))
		for key: String in ["_water", "_puddles"]:
			var list: Variant = emergency.get(key)
			if list is Array:
				for node: Variant in list:_hide_node(node)
	active = true; _samples.clear(); _server_ms = -1.0; _render_floor = 0.0
	if not authority:_present(accepted, 0.0)
	return true

func _save_always(node: Node) -> void:
	if _saved_node_ids.has(node.get_instance_id()):return
	_saved_node_ids[node.get_instance_id()] = true
	_saved_nodes.append({"node": node, "mode": node.process_mode, "process": node.is_processing(), "physics": node.is_physics_processing()})
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	for child: Node in node.get_children():_save_always(child)

func _data_state(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		var value: Variant = source[key]
		if value is Object:continue
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func _script_state(object: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(object) or object.get_script() == null:return result
	for property: Dictionary in object.get_script().get_script_property_list():
		var key: String = property.name
		if key == "script":continue
		var value: Variant = object.get(key)
		if value is Object:continue
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func _suspend_extra(service: Variant, field: String) -> void:
	if not is_instance_valid(service):return
	_suspend_processing(service)
	var rows: Variant = service.get(field)
	if rows is Array:
		for row: Dictionary in rows:_hide_node(row.get("body"))

func _suspend_processing(node: Node) -> void:
	_saved_nodes.append({"node": node, "mode": node.process_mode, "process": node.is_processing(), "physics": node.is_physics_processing()})
	node.set_process(false); node.set_physics_process(false)
	for child: Node in node.get_children():_suspend_processing(child)

func _hide_node(node: Variant) -> void:
	if not is_instance_valid(node) or not node is Node3D:return
	var row := {"node": node, "visible": node.visible}
	if node is CollisionObject3D:
		row["layer"] = node.collision_layer; row["mask"] = node.collision_mask
		node.collision_layer = 0; node.collision_mask = 0
	_hidden.append(row); node.visible = false

func set_remote_neighbors(peers: Array) -> void:
	var approved: Array[CharacterBody3D] = []
	if active and authority:
		for peer: Variant in peers:
			if peer is CharacterBody3D and is_instance_valid(peer) and bool(peer.get_meta("shared_city_remote", false)):approved.append(peer)
	for index: int in range(1, _controllers.size()):_controllers[index].shared_city_neighbors = approved

func apply_snapshot(entities: Array, server_now_ms: float) -> bool:
	if not active or not is_finite(server_now_ms) or server_now_ms < 0.0 or server_now_ms < _server_ms:return false
	var accepted := _validated(entities)
	if accepted.is_empty():return false
	_approved = accepted
	if server_now_ms > _server_ms:
		_samples.append({"time": server_now_ms, "entities": accepted})
		while _samples.size() > MAX_SAMPLES:_samples.pop_front()
		_server_ms = server_now_ms; _received_ms = Time.get_ticks_msec()
		if _samples.size() == 1:_render_floor = server_now_ms
	return true

func _sample_at(local_now_ms: int) -> Dictionary:
	if _samples.is_empty():return _approved
	var target := clampf(maxf(_render_floor, _server_ms + maxi(0, local_now_ms - _received_ms) - INTERPOLATION_MS), _samples.front().time, _samples.back().time)
	var first: Dictionary = _samples.front(); var second: Dictionary = first
	for index: int in range(1, _samples.size()):
		second = _samples[index]
		if target <= float(second.time):break
		first = second
	var span: float = second.time - first.time
	var fraction: float = clampf((target - first.time) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var result: Dictionary = {}
	for id: String in _by_id:
		var a: Dictionary = first.entities[id]; var b: Dictionary = second.entities[id]
		var row: Dictionary = a.duplicate()
		row.position = Vector3(a.position).lerp(b.position, fraction)
		row.rotation = Vector3(lerp_angle(a.rotation.x, b.rotation.x, fraction), lerp_angle(a.rotation.y, b.rotation.y, fraction), lerp_angle(a.rotation.z, b.rotation.z, fraction))
		row.velocity = Vector3(a.velocity).lerp(b.velocity, fraction)
		row.motion = b.motion if fraction >= 1.0 else a.motion
		result[id] = row
	_render_floor = target
	return result

func _present(frame: Dictionary, delta: float) -> void:
	for row: Dictionary in _actors:
		var state: Dictionary = frame[row.id]; var body: CharacterBody3D = row.body
		var before := body.global_position
		body.global_position = state.position; row.visual.global_rotation = state.rotation
		body.velocity = (body.global_position - before) / delta if delta > 0.0 else Vector3.ZERO
		body.set_meta("shared_city_motion", state.motion); row.proxy.transform = Transform3D.IDENTITY
		if row.kind == "dog" and row.source.has("dog_model"):
			row.source.collider.rotation.y = row.visual.rotation.y
			var petting: bool = _approved[row.id].reactionKind == "pet" and _approved[row.id].reactionUntilMs > _estimated_server_ms()
			row.source.dog_model.pose(before.distance_to(body.global_position), delta, "looking" if petting else ("walking" if state.motion != "idle" else "looking"), _visual_clock, host.player.global_position)
	for controller: Node in _controllers:
		if controller.has_method("_update_leashes"):controller._update_leashes(true)

func _estimated_server_ms() -> float:
	return _server_ms + maxi(0, Time.get_ticks_msec() - _received_ms) if _server_ms >= 0.0 else 0.0

func _process(delta: float) -> void:
	if not active:return
	_visual_clock += delta
	if not authority:_present(_sample_at(Time.get_ticks_msec()), delta)
	var now := _estimated_server_ms()
	for row: Dictionary in _actors:
		var state: Dictionary = _approved[row.id]; var label: Label3D = row.label
		label.visible = state.reactionUntilMs > now and state.reactionKind in ["greet", "pet"]
		label.text = "안녕하세요!" if state.reactionKind == "greet" else "강아지를 쓰다듬었어요."

func _nearest() -> Dictionary:
	if not active or not is_instance_valid(host.player):return {}
	var nearest: Dictionary = {}; var distance := RANGE_M
	for row: Dictionary in _actors:
		var current: float = host.player.global_position.distance_to(row.body.global_position)
		if current <= distance:nearest = row; distance = current
	return nearest

func interaction_distance_m() -> float:
	var row := _nearest()
	return host.player.global_position.distance_to(row.body.global_position) if not row.is_empty() else INF

func can_interact() -> bool:return not _nearest().is_empty()

func prompt_text() -> String:
	var row := _nearest()
	return ("E · 강아지 쓰다듬기 · 방에 공유" if row.kind == "dog" else "E · 인사하기 · 방에 공유") if not row.is_empty() else ""

func handle_interact() -> bool:
	var row := _nearest()
	if row.is_empty():return false
	return handle_action("npc_pet" if row.kind == "dog" else "npc_greet")

func handle_action(type: String) -> bool:
	var row := _nearest()
	if row.is_empty() or type not in ["npc_greet", "npc_pet"] or (type == "npc_pet") != (row.kind == "dog"):return false
	var result: Variant = _request_action.call(type, row.id)
	return not result.is_empty() if result is String else result == true

func diagnostic() -> Dictionary:
	return {"active": active, "authority": authority, "actors": _actors.size(), "interpolation_ms": INTERPOLATION_MS,
		"buffered_snapshots": _samples.size(), "shared_actions": ["npc_greet", "npc_pet"], "shared_police": false}

func _collider(body: CharacterBody3D) -> CollisionShape3D:
	for child: Node in body.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null:return child
	return null

func _envelope(body_pose: Transform3D, collider: CollisionShape3D, collider_pose: Transform3D) -> Dictionary:
	var pose: Transform3D = body_pose * collider_pose
	var radius := .3; var half_height := .85
	if collider != null:
		if collider.shape is CapsuleShape3D:
			radius = collider.shape.radius; half_height = collider.shape.height * .5
		elif collider.shape is BoxShape3D:
			var size: Vector3 = collider.shape.size
			radius = Vector2(size.x, size.z).length() * .5; half_height = size.y * .5
	return {"center": pose.origin, "radius": radius * maxf(pose.basis.x.length(), pose.basis.z.length()), "half_height": half_height * pose.basis.y.length()}

func can_restore_at(point: Vector3) -> bool:
	if not active:return true
	var player: CharacterBody3D = host.player
	if not is_instance_valid(player):return false
	var player_pose := player.global_transform; player_pose.origin = point
	var collider: CollisionShape3D = _collider(player)
	var player_shape: Dictionary = _envelope(player_pose, collider, collider.transform if collider != null else Transform3D(Basis.IDENTITY, Vector3.UP * .85))
	for saved: Dictionary in _saved_bodies:
		if saved.layer == 0:continue
		var restored: Dictionary = _envelope(saved.transform, saved.collider, saved.collider_transform)
		if absf(player_shape.center.y - restored.center.y) >= player_shape.half_height + restored.half_height:continue
		var flat := Vector2(player_shape.center.x - restored.center.x, player_shape.center.z - restored.center.z)
		if flat.length() < player_shape.radius + restored.radius + .04:return false
	return true

func end() -> bool:
	if not active:return true
	# Restoring local capsules is atomic. The manager keeps walking available
	# and retries after the player leaves an occupied prejoin footprint.
	if not can_restore_at(host.player.global_position):return false
	active = false
	for row: Dictionary in _hidden:
		if not is_instance_valid(row.node):continue
		row.node.visible = row.visible
		if row.has("layer"):row.node.collision_layer = row.layer; row.node.collision_mask = row.mask
	for saved: Dictionary in _saved_groups:
		var group: Dictionary = saved.group
		for key: Variant in group.keys():
			if key != "members":group.erase(key)
		for key: Variant in saved.state:group[key] = saved.state[key]
	for index: int in range(_actors.size()):
		var row: Dictionary = _actors[index]; var saved: Dictionary = _saved_bodies[index]; var body: CharacterBody3D = row.body
		if not is_instance_valid(body):continue
		body.global_transform = saved.transform; body.velocity = saved.velocity; row.visual.transform = saved.visual; row.proxy.transform = saved.proxy
		if is_instance_valid(saved.collider):saved.collider.transform = saved.collider_transform
		for key: String in saved.script_state:body.set(key, saved.script_state[key])
		for key: Variant in saved.source_state:row.source[key] = saved.source_state[key]
		if row.source.has("dog_model"):
			for key: String in saved.dog_state:row.source.dog_model.set(key, saved.dog_state[key])
		if row.source.has("avatar") and is_instance_valid(row.source.avatar):row.source.avatar._last_position = body.global_position
		body.collision_layer = saved.layer; body.collision_mask = saved.mask; body.input_ray_pickable = saved.pickable
		for key: String in saved.metadata:
			if saved.metadata[key].present:body.set_meta(key, saved.metadata[key].value)
			else:body.remove_meta(key)
		if row.has("label") and is_instance_valid(row.label):body.remove_child(row.label); row.label.queue_free()
		row.erase("label")
	for saved: Dictionary in _saved_controllers:
		saved.node.shared_city_replica = saved.replica
		saved.node.running = saved.running
		if saved.node != _controllers[0]:
			saved.node.shared_city_neighbors.assign(saved.neighbors); saved.node.elapsed = saved.elapsed
	# Refresh render anchors at the restored local poses, before ordinary processing resumes.
	for controller: Node in _controllers:
		if controller.has_method("_finish_human_poses"):controller._finish_human_poses(); controller._finish_human_poses()
		elif controller.has_method("_finish_poses"):controller._finish_poses(0.0); controller._finish_poses(0.0)
	for saved: Dictionary in _saved_nodes:
		if not is_instance_valid(saved.node):continue
		saved.node.process_mode = saved.mode; saved.node.set_process(saved.process); saved.node.set_physics_process(saved.physics)
	_saved_nodes.clear(); _saved_node_ids.clear(); _saved_bodies.clear(); _saved_groups.clear(); _saved_controllers.clear(); _hidden.clear(); _samples.clear(); _approved.clear()
	authority = false; _server_ms = -1.0
	return true

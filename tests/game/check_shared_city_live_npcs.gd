extends SceneTree
## One full city, live host AI for 120 seconds, normal room HTTP updates.
## No NPC/car position writes, traffic pauses, manual driving or external service.
const SCENE := "res://scenes/world/explore_walk.tscn"
const SETTINGS := ["user://sim2seoul_quality.json", "user://sim2seoul_exploration.json", "user://sim2seoul_exploration.json.time.json", "user://sim2seoul_character.json"]
var _report := ""
var _scene: Node3D
var _manager: Node
var _client: Node
var _checks: Array = []
var _metrics: Dictionary = {}
var _outliers: Array = []
var _settings_before: Dictionary = {}
var _monitoring := false
var _started := 0
var _live_started := 0
var _physics_start := 0
var _snapshots_start := 0
var _accepted_snapshots := 0
var _accepted_catalog_min := 999
var _accepted_catalog_max := 0
var _physics_samples := 0
var _ground_gap_max := 0.0
var _car_contacts := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):_report = arg.trim_prefix("--report=")
	if not _report.is_absolute_path():quit(2);return
	Engine.max_fps = 60
	_run.call_deferred()

func _settings() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SETTINGS:result[path] = {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func _check(label: String, passed: bool) -> bool:
	_checks.append({"name": label, "passed": passed})
	return passed

func _until(predicate: Callable, ms := 10000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():return true
		await process_frame
	return bool(predicate.call())

func _observe_snapshot(value: Dictionary) -> void:
	var entities: Array = value.get("world", {}).get("entities", [])
	_accepted_catalog_min = mini(_accepted_catalog_min, entities.size()); _accepted_catalog_max = maxi(_accepted_catalog_max, entities.size())
	_accepted_snapshots += 1

func _sample_physics() -> void:
	if not _monitoring or not is_instance_valid(_manager):return
	_physics_samples += 1
	for row: Dictionary in _manager.npcs._actors:
		var body: CharacterBody3D = row.body
		var metric: Dictionary = _metrics[row.id]
		var at := body.global_position
		var step: float = at.distance_to(metric.last)
		metric.distance_m += step; metric.maximum_step_m = maxf(metric.maximum_step_m, step)
		metric.maximum_velocity_mps = maxf(metric.maximum_velocity_mps, body.velocity.length())
		metric.minimum_y = minf(metric.minimum_y, at.y); metric.maximum_y = maxf(metric.maximum_y, at.y)
		metric.last = at
		var contact := false
		for index: int in range(body.get_slide_collision_count()):
			var other: Object = body.get_slide_collision(index).get_collider()
			if is_instance_valid(other) and other.has_method("get_route_id"):contact = true
		if contact:metric.car_contact_ticks += 1; _car_contacts += 1
		if _outliers.size() < 32 and (step > 24.0 / float(Engine.physics_ticks_per_second) + .25 or body.velocity.length() > 24.0 or not at.is_finite()):
			_outliers.append({"id": row.id, "elapsed_ms": Time.get_ticks_msec() - _live_started, "step_m": step, "velocity": body.velocity, "position": at, "car_contact": contact})

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x, value.y, value.z]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:result[str(key)] = _json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:result.append(_json(item))
		return result
	return value

func _run() -> void:
	_started = Time.get_ticks_msec(); _settings_before = _settings()
	_scene = load(SCENE).instantiate()
	var prefix := _report.get_basename() + "_absent_settings"
	_scene.exploration_settings_path = prefix + "_exploration.json"; _scene.quality_settings_path = prefix + "_quality.json"; _scene.character_settings_path = prefix + "_character.json"
	root.add_child(_scene)
	for frame in range(3):await process_frame
	for tick in range(6):await physics_frame
	if _scene.menu.visible:_scene.toggle_menu()
	_manager = _scene.shared_city_walk
	if not _check("actual_full_city_and_manager_ready", _scene.runtime_ok and _scene.terrain_surface.loaded and is_instance_valid(_manager)):
		await _finish();return
	_client = _manager.client; _client.snapshot_received.connect(_observe_snapshot)
	_check("actual_44_entity_catalog_14cars_28humans_2dogs", _manager._catalog().size() == 44 and _manager.npcs._actors.size() == 30 and _manager.vehicles._cars.size() == 14)
	_check("existing_native_AI_switches_start_enabled", _scene.pedestrians_running and _scene.traffic_switch.button_pressed and _scene.street_pedestrians.running and _scene.exploration_pedestrians.running and _scene.neighborhood_population.walkers.running)
	_client.check_service()
	if not _check("actual_loopback_service_bootstrap", await _until(func()->bool:return _client.available and not _client.busy())):
		await _finish();return
	_check("host_create_requested", _client.create_room())
	if not _check("host_world_active", await _until(func()->bool:return _client.connected and _manager.world_active and _manager.npcs.authority)):
		await _finish();return
	for row: Dictionary in _manager.npcs._actors:
		var at: Vector3 = row.body.global_position
		_metrics[row.id] = {"kind": row.kind, "first": at, "last": at, "distance_m": 0.0, "maximum_step_m": 0.0, "maximum_velocity_mps": 0.0, "minimum_y": at.y, "maximum_y": at.y, "car_contact_ticks": 0}
	_physics_start = Engine.get_physics_frames(); _snapshots_start = _accepted_snapshots; _live_started = Time.get_ticks_msec(); _monitoring = true
	physics_frame.connect(_sample_physics)
	var last_progress := 0
	while Time.get_ticks_msec() - _live_started < 120000 and _client.connected and _manager.world_active:
		await process_frame
		var elapsed := Time.get_ticks_msec() - _live_started
		if elapsed - last_progress >= 1000:
			last_progress = elapsed
			for row: Dictionary in _manager.npcs._actors:
				var at: Vector3 = row.body.global_position; var ground: float = _scene.terrain_surface.ground_y_world(at)
				if is_finite(ground):_ground_gap_max = maxf(_ground_gap_max, absf(at.y - ground))
			var progress := FileAccess.open(_report.get_basename() + "_progress.json", FileAccess.WRITE)
			if progress != null:progress.store_string(JSON.stringify({"live_ms": elapsed, "connected": _client.connected, "accepted_snapshots": _accepted_snapshots - _snapshots_start, "physics_samples": _physics_samples, "outliers": _outliers.size(), "car_contact_ticks": _car_contacts}));progress.close()
	_monitoring = false
	_check("connected_for_full_120_seconds_with_live_AI", Time.get_ticks_msec() - _live_started >= 120000 and _client.connected and _manager.world_active)
	_check("all_accepted_snapshots_keep_44_entities", _accepted_catalog_min == 44 and _accepted_catalog_max == 44)
	_check("at_least_100_actual_HTTP_snapshots_accepted", _accepted_snapshots - _snapshots_start >= 100)
	_check("actual_physics_kept_advancing", Engine.get_physics_frames() - _physics_start >= 2000 and _physics_samples >= 2000)
	var movers := 0
	for id: String in _metrics:
		if _metrics[id].distance_m > .5:movers += 1
	_check("native_route_NPCs_actually_travelled", movers > 0)
	_check("native_AI_switches_remain_enabled", _scene.pedestrians_running and _scene.traffic_switch.button_pressed and _scene.street_pedestrians.running and _scene.exploration_pedestrians.running and _scene.neighborhood_population.walkers.running)
	await _finish()

func _finish() -> void:
	_monitoring = false
	var live_ms := Time.get_ticks_msec() - _live_started if _live_started > 0 else 0
	var diagnostic: Dictionary = _client.diagnostic() if is_instance_valid(_client) else {}
	if is_instance_valid(_client):
		_client.leave_room(); _check("actual_http_leave_completes", await _until(func()->bool:return not _client.connected and not _client.busy(), 6000))
	var after := _settings(); _check("actual_user_settings_unchanged", after == _settings_before)
	var no_writes := true; var prefix := _report.get_basename() + "_absent_settings"
	for suffix: String in ["_exploration.json", "_exploration.json.time.json", "_quality.json", "_character.json"]:no_writes = no_writes and not FileAccess.file_exists(prefix + suffix)
	_check("scoped_missing_settings_remain_unwritten", no_writes)
	var failed := 0
	for item: Dictionary in _checks:
		if not item.passed:failed += 1
	var report := {"task": "EXP41_LIVE_HOST_NPC_STABILITY", "result": "PASS" if failed == 0 else "FAIL", "checks": _checks.size(), "failed": failed, "cases": _checks, "elapsed_ms": Time.get_ticks_msec() - _started, "live_ms": live_ms, "accepted_snapshots": _accepted_snapshots - _snapshots_start, "physics_samples": _physics_samples, "maximum_terrain_gap_m": _ground_gap_max, "car_contact_ticks": _car_contacts, "npc_metrics": _metrics, "local_physics_outliers": _outliers, "client": diagnostic, "user_settings_before": _settings_before, "user_settings_after": after, "scope": "One actual full headless explore_walk host with all native NPC and AI traffic enabled for120seconds; actual own loopback API, no guest/manual driving/production identity/performance claim. No actor teleports or AI pause setters. Local outliers are diagnostics, API422 is captured separately by the bounded proxy."}
	var file := FileAccess.open(_report, FileAccess.WRITE)
	if file == null:quit(2);return
	file.store_string(JSON.stringify(_json(report), "  ") + "\n"); file.close()
	if is_instance_valid(_scene):_scene.queue_free()
	await process_frame; await process_frame
	_scene = null; _manager = null; _client = null
	print("LIVE_NPCS_CHECK result=", report.result, " checks=", report.checks, " failed=", failed, " live_ms=", live_ms)
	create_timer(.1, true, false, true).timeout.connect(Callable(self, "quit").bind(0 if failed == 0 else 1))

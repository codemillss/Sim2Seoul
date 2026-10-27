extends SceneTree
## Flat isolated physics fixture. No production city/GUI/backend acceptance.
const ADAPTER = preload("res://scripts/multiplayer/shared_city_vehicles.gd")
const MANAGER = preload("res://scripts/traffic/traffic_manager.gd")
const REAL_VEHICLE = preload("res://scripts/traffic/vehicle.gd")
var checks: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var reject_action_queue := false
var scene: FixtureHost
var adapter: FlatAdapter

class FixturePlayer extends CharacterBody3D:
	var facility_control := false
	var interior_active := false
	var free_roam_enabled := true
	var input_latched := false
	signal physics_stepped(delta: float)
	func set_facility_control(value: bool) -> void: facility_control = value
	func require_neutral_input() -> void: input_latched = true
	func _physics_process(_delta: float) -> void: pass

class FixtureInput extends Node:
	var intent := Vector2.ZERO
	func movement_intent() -> Vector2: return intent

class FixtureAvatar extends Node3D:
	var _joints: Dictionary = {}
	var _upper_body: Node3D
	var _hands: Array[Node3D] = []
	func initialize() -> void:
		_upper_body = Node3D.new(); add_child(_upper_body)
		for key: String in ["LeftThigh", "RightThigh", "LeftFoot", "RightFoot"]:
			var part := Node3D.new(); part.name = key; add_child(part); _joints[key] = part
		for side: int in range(2):
			var hand := Node3D.new(); add_child(hand); _hands.append(hand)
	func _leg_pose(_side: String, _target: Vector3) -> void: pass
	func _arm_to(_side: String, _target: Vector3) -> void: pass
	func _rest_pose() -> void: pass

class FixtureRig extends Node3D:
	var distance_max_m := 7.0
	var pivot_height_m := 1.5
	var requested_distance := 5.0
	var current_distance := 5.0
	var yaw := .2
	var pitch := -.2
	var _query := PhysicsRayQueryParameters3D.new()
	var arm: SpringArm3D
	var snaps := 0
	func initialize() -> void: arm = SpringArm3D.new(); add_child(arm)
	func snap_to_target_pose() -> void: snaps += 1

class FixtureInterior extends Node:
	var blocked := false
	var active := false
	func _safe_external_point(at: Vector3) -> Dictionary:
		return {} if blocked else {"point": Vector3(at.x, 0, at.z)}

class FixtureCar extends CharacterBody3D:
	var _route_id := ""
	var _manager: Node
	var _running := true
	var _station_m := 0.0
	var _segment := 0
	var _speed_mps := 1.0
	var _state := "accelerating"
	var ticks := 0
	func get_route_id() -> String: return _route_id
	func set_running(value: bool) -> void: _running = value
	func _physics_process(delta: float) -> void:
		if bool(get_meta("shared_city_vehicle_replica", false)) or bool(get_meta("shared_city_vehicle_controlled", false)) or not _running: return
		ticks += 1; _station_m += delta; position.z -= delta; velocity = Vector3(0, 0, -1)

class FixtureNeighborhood extends Node:
	var traffic: Node

class FixturePopulationTraffic extends Node:
	var vehicles: Array[CharacterBody3D] = []

class FixtureDonor extends Node:
	var loaded := true
	var design: Dictionary
	var _private_index: RefCounted
	var _road_index: RefCounted
	var _walk_index: RefCounted
	var _drive_grid: Dictionary = {}
	var _doors: Array[Vector3] = []

class FixtureTerrain extends Node:
	var support: StaticBody3D

class FixtureSoloBuses extends Node3D:
	var loaded := true
	var running := true
	var buses: Array[CharacterBody3D] = []
	func _physics_process(_delta: float) -> void: pass
	func _process(_delta: float) -> void: pass

class FixtureHost extends Node3D:
	var runtime_ok := true
	var player: FixturePlayer
	var input_router: FixtureInput
	var exploration_avatar: FixtureAvatar
	var rig: FixtureRig
	var menu: Control
	var terrain_surface: FixtureTerrain
	var interior_visit: FixtureInterior
	var drivable_car_service: FixtureDonor
	var neighborhood_population: FixtureNeighborhood
	var vehicles: Array[CharacterBody3D] = []
	var traffic: Node
	var city_bus_service: FixtureSoloBuses
	var another_transport := false
	func _street_transport_riding() -> bool: return another_transport
	func _street_transport_riding_except(_service: Node3D) -> bool: return another_transport
	func transport_motion_policy(_kind: String, authored: Dictionary) -> Dictionary: return authored

class FlatAdapter extends ADAPTER:
	func _ground(at: Vector3, _distance: float = 2.0) -> Dictionary: return {"point": Vector3(at.x, 0, at.z), "rid": host.terrain_surface.support.get_rid(), "normal": Vector3.UP}
	func _footprint_allowed(_at: Vector3, _basis: Basis) -> bool: return true
	func _clear_box(_at: Vector3, _basis: Basis, _exclude: Array[RID], _motion: Vector3 = Vector3.ZERO) -> bool: return true
	func _source_motion_clear(_before: Vector3, _motion: Vector3, _yaw: float) -> bool: return true

func _initialize() -> void:
	create_timer(12.0).timeout.connect(func(): print("VEHICLE_FIXTURE_WATCHDOG"); quit(2))
	call_deferred("_run")

func _check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	if not passed: print("FIXTURE_CHECK_FAILED ", name)

func _action(kind: String, id: String) -> String:
	if reject_action_queue: return ""
	actions.append({"type": kind, "id": id})
	return "00000000-0000-4000-8000-" + str(actions.size()).pad_zeros(12)

func _host() -> FixtureHost:
	var host := FixtureHost.new(); root.add_child(host)
	host.menu = Control.new(); host.add_child(host.menu); host.menu.visible = false
	host.input_router = FixtureInput.new(); host.add_child(host.input_router)
	host.player = FixturePlayer.new(); host.add_child(host.player); host.player.position = Vector3(1.25, 0, -.38); host.player.collision_layer = 2; host.player.collision_mask = 25
	var capsule := CollisionShape3D.new(); capsule.name = "CollisionShape"; var capsule_shape := CapsuleShape3D.new(); capsule_shape.radius = .3; capsule_shape.height = 1.7; capsule.shape = capsule_shape; capsule.position.y = .85; host.player.add_child(capsule)
	var visual := Node3D.new(); visual.name = "Visual"; host.player.add_child(visual)
	host.exploration_avatar = FixtureAvatar.new(); visual.add_child(host.exploration_avatar); host.exploration_avatar.initialize()
	host.rig = FixtureRig.new(); host.add_child(host.rig); host.rig.initialize()
	host.interior_visit = FixtureInterior.new(); host.add_child(host.interior_visit)
	host.terrain_surface = FixtureTerrain.new(); host.add_child(host.terrain_surface)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 16; floor_body.collision_mask = 0; host.add_child(floor_body)
	var floor_shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(1000, .2, 1000); floor_shape.shape = box; floor_shape.position.y = -.1; floor_body.add_child(floor_shape); host.terrain_surface.support = floor_body
	host.drivable_car_service = FixtureDonor.new(); host.drivable_car_service.design = JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/car_service.json")); host.add_child(host.drivable_car_service)
	host.neighborhood_population = FixtureNeighborhood.new(); host.add_child(host.neighborhood_population)
	host.neighborhood_population.traffic = FixturePopulationTraffic.new(); host.neighborhood_population.add_child(host.neighborhood_population.traffic)
	host.traffic = MANAGER.new(); host.add_child(host.traffic)
	host.city_bus_service = FixtureSoloBuses.new(); host.add_child(host.city_bus_service)
	var stop := Node3D.new(); stop.name = "RetainedBusStop"; host.city_bus_service.add_child(stop)
	for index: int in range(3):
		var bus := FixtureCar.new(); bus._route_id = "unshared_bus_" + str(index); host.city_bus_service.add_child(bus); bus.position = Vector3(400 + 15 * index, 0, 0); bus.collision_layer = 8; bus.collision_mask = 17; host.city_bus_service.buses.append(bus)
	for index: int in range(ADAPTER.IDS.size()):
		var body := FixtureCar.new(); body._route_id = ADAPTER.IDS[index]; body._manager = host.traffic; body.collision_layer = 8; body.collision_mask = 17
		host.add_child(body); body.position = Vector3(index * 20.0, 0, 0)
		var shape := CollisionShape3D.new(); shape.name = "CollisionShape"; var car_box := BoxShape3D.new(); car_box.size = Vector3(1.8, 1.5, 4.2); shape.shape = car_box; shape.position.y = .75; body.add_child(shape)
		var car_visual := Node3D.new(); car_visual.name = "Visual"; body.add_child(car_visual)
		var mesh := MeshInstance3D.new(); mesh.name = "RetainedOriginalMesh"; mesh.mesh = BoxMesh.new(); car_visual.add_child(mesh)
		host.traffic.vehicles.append(body)
		if index < 6: host.vehicles.append(body)
		else: host.neighborhood_population.traffic.vehicles.append(body)
	return host

func _entities() -> Array:
	var result: Array = []
	for row: Dictionary in adapter.catalog():
		row["mode"] = row.motion; row["driverId"] = ""; row["leaseEpoch"] = 0
		result.append(row)
	return result

func _run() -> void:
	if not InputMap.has_action("jump"): InputMap.add_action("jump")
	scene = _host(); await physics_frame
	adapter = FlatAdapter.new(); scene.add_child(adapter)
	_check("setup_existing_fourteen_route_ids", adapter.setup(scene, _action))
	var initial := _entities()
	_check("catalog_fourteen_unique_json_poses", initial.size() == 14 and initial[0].id == "car:sejong_south" and initial[13].id == "car:coverage_drive_3_car_1")
	var original_mesh: Node = scene.vehicles[0].get_node("Visual/RetainedOriginalMesh")
	var original_pose := scene.vehicles[0].global_transform
	var original_station: float = scene.vehicles[0]._station_m
	scene.vehicles[0].set_meta(ADAPTER.NO_RECYCLE_META, false)
	scene.vehicles[1].set_meta(ADAPTER.NO_RECYCLE_META, true)
	_check("begin_guest", adapter.begin("guest", "host", initial))
	var all_no_recycle := true
	for body: CharacterBody3D in adapter._cars.values(): all_no_recycle = all_no_recycle and bool(body.get_meta(ADAPTER.NO_RECYCLE_META, false))
	_check("shared_session_disables_discontinuous_respawn_for_all_fourteen", all_no_recycle)
	_check("no_double_begin", not adapter.begin("guest", "host", initial))
	_check("original_mesh_and_body_retained", scene.vehicles[0].get_node("Visual/SharedCityVehicleProxy/RetainedOriginalMesh") == original_mesh)
	_check("guest_has_no_authority_samples", adapter.sample_authority().is_empty())
	_check("unshared_moving_buses_hidden_and_suspended", not scene.city_bus_service.loaded and not scene.city_bus_service.buses[0].visible and not scene.city_bus_service.buses[0].is_physics_processing() and scene.city_bus_service.buses[0].collision_layer == 0)
	_check("bus_stop_remains_visible", scene.city_bus_service.get_node("RetainedBusStop").is_visible_in_tree())
	_check("guest_disables_body_physics_and_manager_callback", not scene.vehicles[0].is_physics_processing() and bool(scene.traffic.get_meta(ADAPTER.REPLICA_META, false)))
	var ticks: int = scene.vehicles[0].ticks
	scene.vehicles[0].set_running(true); scene.vehicles[0].set_physics_process(true)
	await physics_frame; await physics_frame
	_check("menu_reenable_cannot_restart_replica_ai", scene.vehicles[0].ticks == ticks)
	adapter.apply_snapshot(initial, 1000.0)
	var moved := initial.duplicate(true); moved[0].position[0] += 10.0; moved[0].rotation[1] = -PI + .1
	initial[0].rotation[1] = PI - .1; adapter.apply_snapshot(initial, 1100.0); adapter.apply_snapshot(moved, 2100.0)
	var midpoint: Dictionary = adapter._sample_row(initial[0].id, 1600.0)
	_check("approved_pose_midpoint", absf(float(midpoint.position[0]) - 5.0) < .001)
	_check("rotation_short_arc_across_pi", absf(absf(float(midpoint.rotation[1])) - PI) < .001)
	_check("no_extrapolation", adapter._sample_row(initial[0].id, 9000.0).position == moved[0].position)
	adapter.apply_snapshot(initial, 2000.0)
	_check("older_server_clock_rejected", adapter._latest[initial[0].id].position == moved[0].position)
	var invalid := moved.duplicate(true); invalid[3].position[0] = INF
	adapter.apply_snapshot(invalid, 2200.0)
	_check("invalid_batch_changes_no_entity", adapter._server_ms == 2100.0)
	invalid = moved.duplicate(true); invalid.append(invalid[0]); adapter.apply_snapshot(invalid, 2300.0)
	_check("duplicate_id_batch_rejected", adapter._server_ms == 2100.0)
	_check("end_guest", adapter.end())
	_check("exact_original_body_pose_station_restored", scene.vehicles[0].global_transform == original_pose and scene.vehicles[0]._station_m == original_station)
	_check("original_mesh_parent_restored", original_mesh.get_parent() == scene.vehicles[0].get_node("Visual"))
	_check("manager_inventory_and_metadata_restored", scene.traffic.vehicles.size() == 14 and not scene.traffic.has_meta(ADAPTER.REPLICA_META) and not scene.vehicles[0].has_meta(ADAPTER.REPLICA_META))
	_check("unshared_buses_restored", scene.city_bus_service.loaded and scene.city_bus_service.buses[0].visible and scene.city_bus_service.buses[0].is_physics_processing() and scene.city_bus_service.buses[0].collision_layer == 8)
	_check("no_recycle_metadata_original_false_true_and_absent_restored", scene.vehicles[0].has_meta(ADAPTER.NO_RECYCLE_META) and not bool(scene.vehicles[0].get_meta(ADAPTER.NO_RECYCLE_META)) and bool(scene.vehicles[1].get_meta(ADAPTER.NO_RECYCLE_META)) and not scene.vehicles[2].has_meta(ADAPTER.NO_RECYCLE_META))
	_check("end_idempotent", adapter.end())
	_check("late_approval_after_end_ignored", not adapter.is_riding())
	adapter.apply_snapshot(moved, 2400.0)
	_check("late_snapshot_does_not_mount_or_move", not adapter.is_riding() and scene.vehicles[0].global_transform == original_pose)
	# A previous solo takeover is explicitly unsupported rather than overwritten.
	scene.vehicles[0].set_meta("player_seized_traffic_car", true)
	_check("solo_taken_car_safely_rejected", not adapter.begin("guest", "host", initial) and scene.vehicles[0].global_transform == original_pose and not adapter.load_error.is_empty())
	scene.vehicles[0].remove_meta("player_seized_traffic_car")
	initial = _entities(); _check("begin_host", adapter.begin("host", "host", initial))
	_check("host_ai_remains_local", scene.vehicles[0].is_physics_processing() and not bool(scene.traffic.get_meta(ADAPTER.REPLICA_META, true)) and adapter.sample_authority().size() == 14)
	_check("host_ai_bodies_process_while_tree_paused", scene.vehicles[0].process_mode == Node.PROCESS_MODE_ALWAYS)
	var paused_ticks: int = scene.vehicles[0].ticks
	paused = true
	await physics_frame; await physics_frame; await physics_frame
	paused = false
	_check("host_ai_actual_callback_runs_during_pause", scene.vehicles[0].ticks > paused_ticks)
	_check("host_end", adapter.end())
	_check("host_ai_original_process_mode_restored", scene.vehicles[0].process_mode == Node.PROCESS_MODE_INHERIT)
	# Never reset another solo controller's player/camera during room cleanup.
	initial = _entities(); _check("begin_before_solo_activity", adapter.begin("guest", "host", initial))
	scene.player.position = Vector3(7, 0, 9); scene.player.facility_control = true; scene.rig.yaw = 1.234
	var snaps := scene.rig.snaps
	_check("end_preserves_other_activity", adapter.end() and scene.player.facility_control and scene.player.position == Vector3(7, 0, 9) and scene.rig.yaw == 1.234 and scene.rig.snaps == snaps)
	scene.player.facility_control = false; scene.player.position = Vector3(1.25, 0, -.38)
	initial = _entities(); _check("begin_for_driver", adapter.begin("guest", "host", initial))
	adapter._pending_action = ""; actions.clear()
	_check("fresh_interact_requests_only", adapter.handle_interact() and actions.size() == 1 and actions[0].type == "vehicle_enter" and not adapter.is_riding())
	adapter.handle_interact(); _check("pending_claim_not_duplicated", actions.size() == 1)
	var claimed := initial.duplicate(true); claimed[0].mode = "driven"; claimed[0].driverId = "guest"; claimed[0].leaseEpoch = 1
	adapter.apply_snapshot(claimed, 3000.0)
	_check("approved_lease_mounts_original_car", adapter.is_riding() and adapter.bikes[0].body == scene.vehicles[0])
	_check("mount_saves_capsule_and_disables_local_physics", scene.player.facility_control and not scene.player.is_physics_processing() and scene.player.get_collision_exceptions().has(scene.vehicles[0]))
	_check("claimed_car_removed_from_fifo_only_reversibly", scene.traffic.vehicles.size() == 13)
	var sample := adapter.drive_sample()
	_check("driver_sample_is_scoped_to_approved_epoch", sample.entityId == initial[0].id and sample.leaseEpoch == 1 and sample.sequence == 1)
	var before_drive := scene.vehicles[0].global_position
	scene.player.input_latched = false; scene.input_router.intent = Vector2(0, -1)
	for frame: int in range(16): await physics_frame
	_check("actual_inherited_physical_driving_moves_original_body", scene.vehicles[0].global_position.distance_to(before_drive) > .05)
	scene.input_router.intent = Vector2.ZERO; adapter.speed_mps = 0.0
	reject_action_queue = true
	adapter.exit_requested = true; adapter._try_dismount()
	_check("full_queue_does_not_mark_driver_exit_sent", adapter._exit_sent_for.is_empty())
	reject_action_queue = false
	adapter.exit_requested = true; adapter._try_dismount()
	_check("same_epoch_driver_exit_retries_after_queue_frees", adapter._exit_sent_for == initial[0].id and adapter._exit_sent_epoch == 1)
	_check("exit_waits_for_server_approval", adapter.is_riding() and actions[-1].type == "vehicle_exit")
	var parked := claimed.duplicate(true); parked[0].mode = "parked"; parked[0].driverId = ""; parked[0].leaseEpoch = 2
	adapter.apply_snapshot(parked, 4000.0)
	_check("approved_exit_restores_player_and_retains_parked_car", not adapter.is_riding() and adapter._latest[initial[0].id].mode == "parked" and not scene.vehicles[0].is_physics_processing())
	for frame: int in range(5): await physics_frame
	_check("collision_exception_and_delayed_control_released", not scene.player.get_collision_exceptions().has(scene.vehicles[0]) and not scene.player.facility_control and scene.player.is_physics_processing())
	adapter.apply_snapshot(claimed, 4100.0)
	_check("older_lease_epoch_cannot_remount", not adapter.is_riding() and adapter._server_ms == 4000.0)
	_check("end_restores_after_drive", adapter.end() and scene.traffic.vehicles.size() == 14 and original_mesh.get_parent() == scene.vehicles[0].get_node("Visual"))
	# Mixed world catalogs may also carry NPCs; only the fixed vehicle subset is used.
	scene.player.position = Vector3(1.25, 0, -.38); scene.player.input_latched = false
	initial = _entities(); var mixed := initial.duplicate(true); mixed.append({"id": "npc:ignored", "kind": "npc"})
	_check("mixed_world_uses_only_fourteen_cars", adapter.begin("guest", "host", mixed))
	claimed = initial.duplicate(true); claimed[0].mode = "driven"; claimed[0].driverId = "guest"; claimed[0].leaseEpoch = 3
	scene.player.facility_control = true; actions.clear(); reject_action_queue = true
	_check("late_claim_after_other_activity_is_accepted_batch", adapter.apply_snapshot(claimed, 5000.0))
	_check("full_queue_does_not_mark_rejected_lease_exit_sent", adapter._exit_sent_for.is_empty() and actions.is_empty())
	reject_action_queue = false
	adapter.apply_snapshot(claimed, 5001.0)
	_check("late_claim_released_without_taking_player_control", not adapter.is_riding() and scene.player.facility_control and actions.size() == 1 and actions[0].type == "vehicle_exit")
	claimed[0].leaseEpoch = 4; adapter.apply_snapshot(claimed, 5100.0)
	_check("new_rejected_lease_epoch_is_released_again", actions.size() == 2)
	scene.player.facility_control = false; scene.menu.visible = true
	claimed[0].leaseEpoch = 5; adapter.apply_snapshot(claimed, 5200.0)
	_check("approved_mount_waits_for_menu_close", not adapter.is_riding())
	scene.menu.visible = false
	for frame: int in range(3): await physics_frame
	_check("approved_mount_continues_after_menu", adapter.is_riding())
	_check("non_host_never_reports_ai_authority_while_driving", adapter.sample_authority().is_empty())
	var claim_sequence := adapter.drive_sample()
	_check("drive_samples_sequence_increases", adapter.drive_sample().sequence == int(claim_sequence.sequence) + 1)
	scene.interior_visit.blocked = true
	var occupied_pose := scene.vehicles[0].global_transform
	_check("blocked_end_returns_false_and_does_not_restore_occupied_car", not adapter.end() and adapter.is_riding() and scene.vehicles[0].global_transform == occupied_pose)
	var pending_sample: Dictionary = adapter.drive_sample()
	adapter.apply_snapshot(initial, 6000.0)
	_check("late_snapshot_during_cleanup_cannot_take_authority", adapter.is_riding() and adapter._latest[initial[0].id].leaseEpoch == 5)
	scene.interior_visit.blocked = false
	_check("end_waits_for_native_collision_pair_release", not adapter.end() and not adapter.is_riding() and adapter.cleanup_pending())
	for frame: int in range(5): await physics_frame
	_check("end_retry_restores_everything_after_safe_exit", adapter.end() and not scene.player.facility_control and scene.player.is_physics_processing() and not scene.player.get_collision_exceptions().has(scene.vehicles[0]) and scene.traffic.vehicles.size() == 14)
	_check("drive_sample_during_and_after_end_empty", adapter.drive_sample().is_empty() and pending_sample.is_empty())
	_check("repeated_room_session_restores_proxy_count", scene.vehicles[0].get_node("Visual").get_child_count() == 1 and original_mesh.get_parent() == scene.vehicles[0].get_node("Visual"))
	scene.player.position = Vector3(1.25, 0, -.38); initial = _entities()
	_check("begin_host_for_fixed_catalog", adapter.begin("host", "host", initial))
	claimed = initial.duplicate(true); claimed[0].mode = "driven"; claimed[0].driverId = "guest"; claimed[0].leaseEpoch = 7
	adapter.apply_snapshot(claimed, 7000.0)
	_check("host_authority_catalog_keeps_leased_car_row", adapter.sample_authority().size() == 14 and scene.traffic.vehicles.size() == 13)
	_check("other_driver_does_not_mount_local_player", not adapter.is_riding())
	var malformed := claimed.duplicate(true); malformed[1].mode = "driven"; malformed[1].driverId = "host"; malformed[2].mode = "driven"; malformed[2].driverId = "host"
	_check("two_local_driver_claims_rejected_atomically", not adapter.apply_snapshot(malformed, 7100.0) and adapter._server_ms == 7000.0)
	_check("nonfinite_clock_rejected", not adapter.apply_snapshot(claimed, NAN))
	_check("final_host_end", adapter.end())
	# A former lease's delayed render samples must never overwrite the newly
	# approved parked body's collision pose. Probe the actual physics space.
	scene.player.position = Vector3(7, 0, 9); initial = _entities()
	_check("begin_replica_for_lease_boundary", adapter.begin("guest", "host", initial))
	var leased := initial.duplicate(true); leased[0].mode = "driven"; leased[0].driverId = "peer"; leased[0].leaseEpoch = 20; leased[0].position = [20.0, 0.0, -30.0]
	adapter.apply_snapshot(leased, 10000.0)
	var leased_next := leased.duplicate(true); leased_next[0].position = [26.0, 0.0, -30.0]
	adapter.apply_snapshot(leased_next, 10600.0)
	var delayed: Dictionary = adapter._sample_row(initial[0].id, 10300.0)
	_check("same_lease_still_interpolates_approved_motion", absf(float(delayed.position[0]) - 23.0) < .001)
	adapter._place_row(initial[0].id, delayed)
	var released := leased_next.duplicate(true); released[0].mode = "parked"; released[0].driverId = ""; released[0].leaseEpoch = 21; released[0].position = [27.5, 0.0, -30.0]; released[0].velocity = [0.0, 0.0, 0.0]
	adapter.apply_snapshot(released, 10700.0)
	_check("release_publishes_approved_parked_body_immediately", scene.vehicles[0].global_position.distance_to(Vector3(27.5, 0, -30)) < .001)
	_check("release_discards_previous_lease_samples", adapter._buffers[initial[0].id].size() == 1 and adapter._sample_row(initial[0].id, 10100.0).position == released[0].position)
	adapter._process(0.0)
	await physics_frame; await physics_frame
	_check("old_600ms_clock_cannot_rewind_parked_body", scene.vehicles[0].global_position.distance_to(Vector3(27.5, 0, -30)) < .001)
	var probe := PhysicsShapeQueryParameters3D.new(); var probe_box := BoxShape3D.new(); probe_box.size = Vector3(.1, .1, .1); probe.shape = probe_box; probe.collision_mask = 8; probe.margin = 0.0
	probe.transform = Transform3D(Basis.IDENTITY, Vector3(27.5, .75, -30))
	var parked_hits := scene.get_world_3d().direct_space_state.intersect_shape(probe, 16)
	var new_pose_has_body := false
	for hit: Dictionary in parked_hits:
		if hit.collider == scene.vehicles[0]: new_pose_has_body = true
	probe.transform.origin = Vector3(23, .75, -30)
	var old_hits := scene.get_world_3d().direct_space_state.intersect_shape(probe, 16)
	var old_pose_has_body := false
	for hit: Dictionary in old_hits:
		if hit.collider == scene.vehicles[0]: old_pose_has_body = true
	_check("native_collision_pose_is_new_parked_location_only", new_pose_has_body and not old_pose_has_body)
	_check("end_restores_after_lease_boundary", adapter.end())
	# Production guards are independently exercised without a configured world.
	var real_car := REAL_VEHICLE.new(); real_car.set_meta(ADAPTER.REPLICA_META, true)
	real_car.set_running(true); real_car._physics_process(.033)
	_check("production_vehicle_replica_guard_precedes_world_queries", real_car._physics_steps == 0 and not real_car.can_recycle())
	real_car.remove_meta(ADAPTER.REPLICA_META); real_car.set_meta(ADAPTER.CONTROLLED_META, true); real_car._physics_process(.033)
	_check("production_vehicle_driver_guard", real_car._physics_steps == 0 and not real_car.can_recycle())
	real_car.free()
	var real_manager := MANAGER.new(); real_manager.set_meta(ADAPTER.REPLICA_META, true); real_manager.after_camera_step(.033)
	_check("production_manager_camera_guard_precedes_world_queries", real_manager.refreshed_tick == -1); real_manager.free()
	# Real production vehicle + original box + native ground contact at a short
	# labelled fixture endpoint. No fake is_on_floor override is involved.
	var world := Node3D.new(); scene.add_child(world)
	var endpoint_car: CharacterBody3D = load("res://scenes/npc/vehicle.tscn").instantiate()
	endpoint_car.configure({"id": "fixture_endpoint", "xz": [[0.0, -100.0], [0.0, -120.0]], "ground_y_m": 0.0, "length_m": 20.0, "source_binding": {"source_direction": "source_forward"}}, scene.traffic, world)
	scene.add_child(endpoint_car); endpoint_car.set_physics_process(false)
	endpoint_car.global_position = Vector3(0, 0, -120); endpoint_car._station_m = 20.0; endpoint_car._segment = 0; endpoint_car._state = "endpoint_wait"; endpoint_car._speed_mps = 0.0
	await physics_frame
	endpoint_car.velocity = Vector3(0, -.12, 0); endpoint_car.move_and_slide()
	_check("real_production_endpoint_has_native_floor_and_solo_recycle_eligibility", endpoint_car.is_on_floor() and endpoint_car.can_recycle())
	var stopped_pose := endpoint_car.global_transform
	endpoint_car.set_meta(ADAPTER.NO_RECYCLE_META, true)
	var endpoint_guard := {"allowed": true, "tick": Engine.get_physics_frames()}
	_check("shared_guard_refuses_actual_endpoint_to_start_transform", not endpoint_car.try_recycle(endpoint_guard) and endpoint_car.global_transform == stopped_pose and endpoint_car._cycle_count == 0)
	_check("shared_endpoint_body_still_available_for_claim", is_instance_valid(endpoint_car.get_node("Visual")) and endpoint_car.collision_layer == 8 and endpoint_car.get_route_id() == "fixture_endpoint")
	endpoint_car.remove_meta(ADAPTER.NO_RECYCLE_META)
	_check("original_solo_can_recycle_condition_restored", endpoint_car.can_recycle())
	_check("original_solo_recycle_still_moves_to_start", endpoint_car.try_recycle(endpoint_guard) and endpoint_car.global_position.distance_to(Vector3(0, 0, -100)) < .001 and endpoint_car._cycle_count == 1)
	var failed := 0
	for check: Dictionary in checks:
		if not check.passed: failed += 1
	var report: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report = argument.trim_prefix("--report=")
	var result := {"task": "SHARED_CITY_VEHICLE_COMPONENT", "result": "PASS" if failed == 0 else "FAIL", "checks": checks.size(), "failed": failed, "cases": checks, "scope": "Actual native engine and inherited car physics on an isolated flat fixture with injected terrain/source-clearance and avatar stubs. Fourteen original fixture body/visual identities. No full city, real skin/GUI, network lease race, backend/production authentication or performance acceptance."}
	if not report.is_empty():
		var file := FileAccess.open(report, FileAccess.WRITE); file.store_string(JSON.stringify(result, "\t") + "\n"); file = null
	print(JSON.stringify({"result": result.result, "checks": checks.size(), "failed": failed}))
	scene.queue_free(); scene = null; adapter = null
	await process_frame; await create_timer(.1).timeout
	quit(1 if failed else 0)

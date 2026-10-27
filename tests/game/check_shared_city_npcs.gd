extends SceneTree
## Tiny production-adapter fixture. No city scene, renderer benchmark or network.
const NPCS := preload("res://scripts/multiplayer/shared_city_npcs.gd")
const STREET := preload("res://scripts/street_pedestrians.gd")
const LEGACY := preload("res://scripts/exploration_pedestrian_avoidance.gd")
class Body extends CharacterBody3D:
	var _route_id := ""
	var route_station := 5.0
class Avatar extends Node3D:
	var _last_position := Vector3.ZERO
class Population extends Node3D:
	var walkers: Node3D
class Host extends Node3D:
	var player: CharacterBody3D
	var exploration_pedestrians: Node3D
	var street_pedestrians: Node3D
	var neighborhood_population: Node3D
	var city_public_safety: Node3D
	var city_weather_emergency: Node3D
class Safety extends Node3D:
	var wanted := false
	var detained := false
	var officers: Array[Dictionary] = []
	var patrol_vehicle_service: Node3D
	func _physics_process(_delta: float) -> void:pass
class Emergency extends Node3D:
	var firefighters: Array[Dictionary] = []
	var engine: Node3D
	var standby_engine: Node3D
	var _fire: Node3D
	var _rain: Node3D
	var _water: Array = []
	var _puddles: Array = []
	func _process(_delta: float) -> void:pass
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report_path := ""
var host: Host
var adapter: Node3D
var requested: Array = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path = arg.trim_prefix("--report=")
	if not report_path.is_absolute_path():quit(2);return
	_run.call_deferred()

func check(title: String, passed: bool) -> void:
	checks.append({"name": title, "passed": passed})
	if not passed:failures.append(title)

func _body(parent: Node3D, id: String, index: int) -> Dictionary:
	var body := Body.new(); body._route_id = id; body.name = id
	body.collision_layer = 4; body.collision_mask = 47; body.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(body); body.position = Vector3(index * 8, 0, 0)
	var shape := CollisionShape3D.new(); shape.shape = CapsuleShape3D.new(); body.add_child(shape)
	var visual := Node3D.new(); visual.name = "Visual"; body.add_child(visual)
	var proxy := Node3D.new(); visual.add_child(proxy)
	var avatar := Avatar.new(); proxy.add_child(avatar)
	return {"body": body, "visual": visual, "proxy": proxy, "avatar": avatar, "kind": "walker", "group": id, "phase": .25,
		"previous_pose": visual.global_transform, "current_pose": visual.global_transform}

func _request(type: String, id: String) -> String:
	requested.append([type, id]); return "fixture-request"

func _run() -> void:
	host = Host.new(); root.add_child(host)
	host.player = CharacterBody3D.new(); host.add_child(host.player)
	host.exploration_pedestrians = LEGACY.new(); host.add_child(host.exploration_pedestrians)
	host.street_pedestrians = STREET.new(); host.add_child(host.street_pedestrians)
	host.neighborhood_population = Population.new(); host.add_child(host.neighborhood_population)
	host.neighborhood_population.walkers = STREET.new(); host.neighborhood_population.add_child(host.neighborhood_population.walkers)
	for index: int in range(2):
		var row := _body(host, ["palace_court", "plaza_front"][index], index)
		row["previous"] = row.avatar.global_transform; row["current"] = row.avatar.global_transform
		row.body.set_physics_process(false)
		host.exploration_pedestrians.human_visuals.append(row)
		host.exploration_pedestrians.groups.append({"station": 5.0, "members": [{"body": row.body}], "points": [Vector3.ZERO]})
	var street_ids := ["stonewall_east", "stonewall_dog", "stonewall_west", "plaza_dog", "plaza_west", "museum_slope"]
	for index: int in range(6):
		var row := _body(host.street_pedestrians, street_ids[index], index + 2)
		host.street_pedestrians.actors.append(row)
		if index in [1, 3]:
			var dog := _body(host.street_pedestrians, street_ids[index] + "_dog", index + 8)
			dog.group = street_ids[index]; dog.kind = "dog"; host.street_pedestrians.actors.append(dog)
	for index: int in range(20):
		var row := _body(host.neighborhood_population.walkers, "coverage_walk_%02d_%d" % [index / 2, index % 2], index + 10)
		host.neighborhood_population.walkers.actors.append(row)
	host.city_public_safety = Safety.new(); host.add_child(host.city_public_safety)
	var officer := _body(host.city_public_safety, "Officer", 40)
	host.city_public_safety.officers.append(officer)
	host.city_weather_emergency = Emergency.new(); host.add_child(host.city_weather_emergency)
	var firefighter := _body(host.city_weather_emergency, "Firefighter", 41)
	host.city_weather_emergency.firefighters.append(firefighter)
	adapter = NPCS.new(); host.add_child(adapter)
	check("production adapter accepts exact existing population", adapter.setup(host, _request))
	var catalog: Array = adapter.catalog()
	var ids: Array = catalog.map(func(row: Dictionary) -> String:return row.id)
	check("stable catalog has 28 humans and 2 dogs without duplicates", catalog.size() == 30 and catalog.filter(func(row: Dictionary) -> bool:return row.kind == "dog").size() == 2 and ids.size() == 30 and ids.has("npc:n02:palace_court") and ids.has("npc:street:plaza_dog:dog") and ids.has("npc:coverage:coverage_walk_09_1"))
	check("inactive adapter never publishes authority", adapter.sample_authority().is_empty())
	var bad: Array = catalog.duplicate(true); bad.pop_back()
	check("partial catalog fails before local ownership mutation", not adapter.begin("guest", "owner", bad) and not adapter.active and not host.street_pedestrians.shared_city_replica)
	bad = catalog.duplicate(true); bad[1] = bad[0].duplicate(true)
	check("duplicate catalog fails transactionally", not adapter.begin("guest", "owner", bad))
	bad = catalog.duplicate(true); bad[0].position[0] = INF
	check("nonfinite pose fails transactionally", not adapter.begin("guest", "owner", bad))
	host.city_public_safety.wanted = true
	check("pending local police cannot change authority mid pursuit", not adapter.begin("guest", "owner", catalog))
	host.city_public_safety.wanted = false
	var original: Transform3D = adapter._actors[0].body.global_transform
	var original_mode: int = adapter._actors[0].body.process_mode
	check("guest begins from complete approved catalog", adapter.begin("guest", "owner", catalog))
	check("all native movement and render writers are guarded for guest", host.street_pedestrians.shared_city_replica and host.exploration_pedestrians.shared_city_replica and host.neighborhood_population.walkers.shared_city_replica)
	host.street_pedestrians.loaded = true; host.exploration_pedestrians.loaded = true
	# These production callbacks would access deliberately absent city/physics data if the guard failed.
	host.street_pedestrians._physics_process(.1); host.street_pedestrians._finish_poses(.1); host.street_pedestrians._process(.1)
	host.exploration_pedestrians._physics_process(.1); host.exploration_pedestrians._finish_human_poses(); host.exploration_pedestrians._process(.1)
	check("guarded production callbacks do not advance route state", host.exploration_pedestrians.groups[0].station == 5.0)
	check("replicas have zero collision but retained original body identities", adapter._actors.all(func(row: Dictionary) -> bool:return row.body.collision_layer == 0 and row.body.collision_mask == 0 and row.body.get_meta("shared_city_remote", false)))
	check("legacy avatars can run during menu pause", adapter._actors[0].body.process_mode == Node.PROCESS_MODE_ALWAYS)
	check("unshared police and fire actors are hidden and paused reversibly", not officer.body.visible and officer.body.collision_layer == 0 and not firefighter.body.visible and not host.city_public_safety.is_physics_processing() and not host.city_weather_emergency.is_processing())
	check("guest cannot publish local AI poses", adapter.sample_authority().is_empty())
	check("first timestamp accepted", adapter.apply_snapshot(catalog, 1000))
	var second: Array = catalog.duplicate(true); second[0].position[0] = 2.0; second[0].rotation[1] = -PI + .1
	catalog[0].rotation[1] = PI - .1
	# Replace initial frame only for the deterministic seam interpolation fixture.
	adapter._samples[0].entities = adapter._validated(catalog)
	check("next timestamp accepted", adapter.apply_snapshot(second, 1500))
	var receive: int = adapter._received_ms
	var sample: Dictionary = adapter._sample_at(receive + 350)
	var first_id: String = catalog[0].id
	check("six hundred millisecond delayed midpoint uses approved poses", absf(sample[first_id].position.x - 1.0) < .00001)
	check("angle interpolation crosses pi by the short path", absf(absf(sample[first_id].rotation.y) - PI) < .0001)
	check("late frames hold endpoint without extrapolation", adapter._sample_at(receive + 5000)[first_id].position == Vector3(2, 0, 0))
	check("render clock cannot rewind", adapter._sample_at(receive)[first_id].position == Vector3(2, 0, 0))
	check("older server snapshot rejected", not adapter.apply_snapshot(catalog, 1400))
	var accepted: Dictionary = adapter._approved.duplicate(true)
	bad = second.duplicate(true); bad[0].kind = "dog"
	check("kind mismatch rejects entire update without changing approved state", not adapter.apply_snapshot(bad, 2000) and adapter._approved == accepted)
	adapter._present(adapter._sample_at(receive + 5000), .5)
	host.player.global_position = adapter._actors[0].body.global_position
	check("human E sends only stable greeting action callback", adapter.handle_interact() and requested.back() == ["npc_greet", first_id])
	check("melee never reaches local public safety or shared request callback", not adapter.handle_action("npc_hit") and not adapter.handle_action("npc_shove") and requested.size() == 1)
	var dog_row: Dictionary = adapter._actors.filter(func(row: Dictionary) -> bool:return row.kind == "dog")[0]
	host.player.global_position = dog_row.body.global_position
	check("dog E sends pet with stable ID and fixed shared prompt", adapter.handle_interact() and requested.back() == ["npc_pet", dog_row.id] and "쓰다듬기" in adapter.prompt_text())
	check("wrong species action is rejected", not adapter.handle_action("npc_greet"))
	host.player.global_position = Vector3(-50, 0, -50)
	check("outside three metres there is no interaction", not adapter.can_interact() and not adapter.handle_interact() and is_inf(adapter.interaction_distance_m()))
	second[0].reactionKind = "greet"; second[0].reactionUntilMs = 100000
	check("approved top level shared reaction accepted", adapter.apply_snapshot(second, 2000))
	adapter._process(0.0)
	check("approved greeting has fixed Korean display", adapter._actors[0].label.visible and adapter._actors[0].label.text == "안녕하세요!")
	# Avoid running unsupported fixture route internals during restore anchors.
	host.street_pedestrians.loaded = false; host.neighborhood_population.walkers.loaded = false
	host.player.global_position = original.origin
	var current_pose: Transform3D = adapter._actors[0].body.global_transform
	check("overlapping prejoin capsule blocks end before any ownership mutation", not adapter.end() and adapter.active and adapter._actors[0].body.global_transform == current_pose and adapter._actors[0].body.collision_layer == 0 and host.street_pedestrians.shared_city_replica and not officer.body.visible)
	check("restore footprint helper is read only and respects separated heights", adapter.can_restore_at(original.origin + Vector3.UP * 10.0) and not adapter.can_restore_at(original.origin) and adapter.active)
	adapter._collider(dog_row.body).rotation.y = .9
	host.player.global_position = Vector3(-50, 0, -50)
	check("guest end succeeds", adapter.end())
	check("replica dog collider orientation restores with the original local body", is_zero_approx(adapter._collider(dog_row.body).rotation.y))
	check("prejoin transforms collision metadata and original processing restore", adapter._actors[0].body.global_transform == original and adapter._actors[0].body.collision_layer == 4 and adapter._actors[0].body.collision_mask == 47 and not adapter._actors[0].body.has_meta("shared_city_remote") and adapter._actors[0].body.process_mode == original_mode and not adapter._actors[0].body.is_physics_processing())
	check("extra local actors and original process callbacks restore", officer.body.visible and officer.body.collision_layer == 4 and firefighter.body.visible and host.city_public_safety.is_physics_processing() and host.city_weather_emergency.is_processing())
	check("controller ownership and group station restore", not host.street_pedestrians.shared_city_replica and not host.exploration_pedestrians.shared_city_replica and host.exploration_pedestrians.groups[0].station == 5.0)
	check("repeat end is safe", adapter.end())
	check("owner begins without disabling native AI or collisions", adapter.begin("owner", "owner", catalog) and not host.street_pedestrians.shared_city_replica and adapter._actors[0].body.collision_layer == 4)
	check("owner publishes exactly existing catalog", adapter.sample_authority().size() == 30)
	var peer := CharacterBody3D.new(); host.add_child(peer); peer.set_meta("shared_city_remote", true)
	adapter.set_remote_neighbors([peer, host.player])
	check("only approved remote presentation actors enter owner avoidance list", host.street_pedestrians.shared_city_neighbors == [peer] and host.neighborhood_population.walkers.shared_city_neighbors == [peer])
	adapter._actors[0].body.route_station = 99.0
	host.exploration_pedestrians.groups[0].station = 99.0
	check("owner end restores prejoin local route state and clears room neighbors", adapter.end() and adapter._actors[0].body.route_station == 5.0 and host.exploration_pedestrians.groups[0].station == 5.0 and host.street_pedestrians.shared_city_neighbors.is_empty())
	var output := {"checks": checks, "passed": checks.size() - failures.size(), "failed": failures.size(), "failures": failures, "scope": "Production NPC adapter/controller component fixture, no full game or network."}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:quit(2);return
	file.store_string(JSON.stringify(output, "\t") + "\n"); file.close()
	print("SHARED_CITY_NPCS_CHECKS ", output.passed, "/", checks.size(), " failed=", failures.size())
	for failure: String in failures:print("FAILED ", failure)
	host.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

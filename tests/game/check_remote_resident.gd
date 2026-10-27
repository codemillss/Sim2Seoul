extends SceneTree
## Actual production Avatar/GLBs in a tiny component world, never the city.
const REMOTE := preload("res://scripts/multiplayer/remote_resident.gd")
const AVATAR := preload("res://scripts/player/exploration_avatar.gd")
class FailedAvatar extends Node3D:
	func setup(_actor: CharacterBody3D) -> bool:return false
class TransactionRemote extends "res://scripts/multiplayer/remote_resident.gd":
	var fail_next := false
	var load_attempts := 0
	func _new_avatar() -> Node3D:
		load_attempts += 1
		return FailedAvatar.new() if fail_next else super._new_avatar()
class LocalController extends CharacterBody3D:
	func set_facility_control(_enabled: bool) -> void:pass
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report_path := ""
var capture_dir := ""
var captures: Array[String] = []
var measurements: Dictionary = {}
var world: Node3D
var source_before: Dictionary = {}
const SOURCES := ["res://scripts/multiplayer/remote_resident.gd", "res://scripts/player/exploration_avatar.gd", "res://../tests/game/check_remote_resident.gd"]

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--capture-dir="):capture_dir = argument.trim_prefix("--capture-dir=")
	if not report_path.is_absolute_path():quit(2);return
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name": title, "passed": passed, "evidence": evidence})
	if not passed:failures.append(title)

func _row(id: String, sequence: int, updated: int, at := Vector3.ZERO, yaw := 0.0, motion := "walk", model := "SeoulResident_M01", profile := "standard", swimwear := false) -> Dictionary:
	return {"id": id, "sequence": sequence, "position": [at.x, at.y, at.z], "yaw": yaw, "motion": motion,
		"avatar": {"modelId": model, "bodyProfile": profile, "swimwear": swimwear}, "updatedAtMs": updated}

func _remote() -> TransactionRemote:
	var value := TransactionRemote.new()
	world.add_child(value)
	return value

func _run() -> void:
	for path: String in SOURCES:source_before[path] = FileAccess.get_sha256(path)
	world = Node3D.new();root.add_child(world)
	var male: TransactionRemote = _remote()
	_check("valid_first_approved_model_setup", male.setup(_row("male_peer", 0, 1000, Vector3.ZERO, deg_to_rad(170.0)), 1000, 1000))
	male.set_process(false);male.avatar.set_physics_process(false)
	_check("first_position_is_immediate", male.global_position == Vector3.ZERO and is_equal_approx(male.visual.rotation.y, deg_to_rad(170.0)))
	var male_skin: Dictionary = male.avatar.textured_model_snapshot(false)
	_check("actual_authored_male_mesh_loaded_and_visible", male_skin.loaded and male_skin.model_id == "SeoulResident_M01" and male_skin.visible_mesh_count > 0 and male_skin.skeleton_bone_count == 52)
	_check("no_collision_shape_mask_layer_or_ai_membership", male.collision_layer == 0 and male.collision_mask == 0 and not male.is_physics_processing() and not male.input_ray_pickable and male.get_groups().is_empty() and male.find_children("*", "CollisionShape3D", true, false).is_empty(), {"physics_processing": male.is_physics_processing(), "groups": male.get_groups(), "collision_layer": male.collision_layer, "collision_mask": male.collision_mask})
	_check("original_body_is_not_a_visible_fallback", not male.get_node("Visual/Body").visible and male.get_node("Visual/Body").mesh == null)
	_check("second_approved_snapshot_ingested", male.ingest(_row("male_peer", 1, 1500, Vector3(1.5, 0, 0), deg_to_rad(-170.0)), 1500, 1500))
	var middle: Dictionary = male.sample_at(1850)
	_check("six_hundred_ms_delay_approved_midpoint", middle.position.distance_to(Vector3(.75, 0, 0)) < .00001 and is_equal_approx(middle.fraction, .5) and middle.first_sequence == 0 and middle.second_sequence == 1)
	_check("yaw_uses_shortest_path_across_pi", absf(absf(wrapf(middle.yaw, -PI, PI)) - PI) < .00001)
	male._present_at(1850, .5)
	male.avatar._physics_process(.5)
	_check("remote_ground_adapter_animates_actual_gait_without_native_floor", not male.is_on_floor() and male.avatar.state in ["walk", "run"] and male.avatar.walk_weight > 0.0 and male.avatar._air_weight < .001)
	_check("visual_heading_and_body_world_position_use_sample", male.global_position.distance_to(Vector3(.75, 0, 0)) < .00001 and absf(absf(wrapf(male.visual.rotation.y, -PI, PI)) - PI) < .00001)
	male._present_at(2500, .5)
	_check("after_newest_snapshot_hold_without_extrapolation", male.global_position == Vector3(1.5, 0, 0))
	male._present_at(3500, .5)
	_check("held_approved_endpoint_has_zero_velocity", male.global_position == Vector3(1.5, 0, 0) and male.velocity == Vector3.ZERO)
	_check("render_time_never_rewinds_on_clock_read", male.sample_at(1500).position == Vector3(1.5, 0, 0))
	var accepted_before: Dictionary = male.presentation_snapshot()
	_check("same_sequence_is_not_a_new_snapshot", not male.ingest(_row("male_peer", 1, 1600), 1600, 1600))
	_check("older_sequence_rejected", not male.ingest(_row("male_peer", 0, 1600), 1600, 1600))
	_check("new_sequence_with_old_timestamp_rejected", not male.ingest(_row("male_peer", 2, 1499), 1600, 1600))
	_check("future_snapshot_rejected", not male.ingest(_row("male_peer", 2, 1700), 1600, 1600))
	_check("other_actor_id_cannot_replace_resident", not male.ingest(_row("other_peer", 2, 1600), 1600, 1600))
	_check("older_local_receive_time_rejected", not male.ingest(_row("male_peer", 2, 1600), 1600, 1499))
	_check("rejects_do_not_change_accepted_state_or_model", male.presentation_snapshot() == accepted_before and male.load_attempts == 1)
	var bad: Dictionary = _row("male_peer", 2, 1600)
	bad.avatar.modelId = "res://unknown.glb"
	_check("unknown_model_rejected_before_any_asset_load", not male.ingest(bad, 1600, 1600) and male.load_attempts == 1)
	bad = _row("male_peer", 2, 1600);bad.avatar.bodyProfile = "outside"
	_check("unknown_body_profile_rejected", not male.ingest(bad, 1600, 1600) and male.load_attempts == 1)
	bad = _row("male_peer", 2, 1600);bad.position[0] = INF
	_check("nonfinite_position_rejected", not male.ingest(bad, 1600, 1600))
	bad = _row("male_peer", 2, 1600);bad.position[2] = 1000.1
	_check("protocol_envelope_rejected", not male.ingest(bad, 1600, 1600))
	bad = _row("male_peer", 2, 1600);bad.sequence = 2.5
	_check("fractional_sequence_rejected", not male.ingest(bad, 1600, 1600))
	bad = _row("male_peer", 2, 1600);bad.avatar.swimwear = "true"
	_check("swimwear_requires_boolean", not male.ingest(bad, 1600, 1600))
	bad = _row("male_peer", 2, 1600);bad.assetPath = "outside"
	_check("unknown_wire_fields_rejected", not male.ingest(bad, 1600, 1600))
	var old_avatar: Node3D = male.avatar
	var old_visual: Node3D = male.visual
	male.fail_next = true
	_check("failed_swap_rejects_entire_new_snapshot", not male.ingest(_row("male_peer", 2, 2000, Vector3(2, 0, 0), 0.0, "idle", "SeoulResident_F01", "athletic"), 2000, 2000))
	_check("failed_swap_preserves_display_and_actor_metadata", male.avatar == old_avatar and male.visual == old_visual and male.visual.visible and male.get_node("Visual") == old_visual and male.get_meta("human_model_id") == "SeoulResident_M01" and male.presentation_snapshot() == accepted_before)
	male.fail_next = false
	_check("female_soft_swim_profile_transaction_succeeds", male.ingest(_row("male_peer", 2, 2000, Vector3(2, 0, 0), 0.0, "swim", "SeoulResident_F01", "soft", true), 2000, 2000))
	var female_skin: Dictionary = male.avatar.textured_model_snapshot(false)
	_check("actual_female_soft_swim_body_is_visible", female_skin.loaded and female_skin.model_id == "SeoulResident_F01" and female_skin.body_profile == "soft" and female_skin.swimwear_active and female_skin.visible_mesh_count > 0 and female_skin.skeleton_bone_count == 52)
	_check("return_from_swim_to_athletic_street_succeeds", male.ingest(_row("male_peer", 3, 2500, Vector3(2, 0, 0), 0.0, "idle", "SeoulResident_F01", "athletic", false), 2500, 2500))
	var athletic_skin: Dictionary = male.avatar.textured_model_snapshot(false)
	_check("athletic_profile_uses_real_authored_street_asset", athletic_skin.loaded and athletic_skin.body_profile == "athletic" and not athletic_skin.swimwear_active and "athletic_street.glb" in String(athletic_skin.active_glb_path))
	_check("jump_snapshot_accepted", male.ingest(_row("male_peer", 4, 3000, Vector3(2, 1, 0), 0.0, "jump", "SeoulResident_F01", "athletic", false), 3000, 3000))
	male._present_at(3700, .5);male.avatar._physics_process(.5)
	_check("approved_jump_presents_air_without_moving_physics", male.avatar.state == "air" and male.avatar._air_weight > .9 and male.collision_layer == 0 and male.collision_mask == 0)
	for index: int in range(5, 45):
		var stamp: int = 3000 + (index - 4) * 500
		_check("ordered_buffer_snapshot_" + str(index), male.ingest(_row("male_peer", index, stamp, Vector3(2, 0, 0), 0.0, "idle", "SeoulResident_F01", "athletic", false), stamp, stamp))
	_check("snapshot_history_is_bounded", male.presentation_snapshot().buffered_snapshots == REMOTE.MAX_BUFFERED_SNAPSHOTS)
	var invalid: TransactionRemote = _remote()
	bad = _row("invalid_peer", 0, 1000);bad.avatar.modelId = "unknown"
	_check("invalid_first_snapshot_never_constructs_avatar", not invalid.setup(bad, 1000, 1000) and invalid.load_attempts == 0 and not invalid.visible and invalid.get_child_count() == 0)
	invalid.queue_free()
	var idle: TransactionRemote = _remote()
	_check("active_idle_member_can_have_old_position_timestamp", idle.setup(_row("idle_peer", 0, 1000, Vector3.ZERO, 0.0, "idle"), 20000, 20000))
	idle.set_process(false);idle.avatar.set_physics_process(false)
	_check("idle_approved_position_still_holds_without_extrapolation", idle.sample_at(50000).position == Vector3.ZERO and idle.presentation_snapshot().sequence == 0)
	idle.queue_free()
	# A real local-controller method keeps native floor contact even if someone
	# sets the remote metadata and zero layers on that separate fixture.
	var local := LocalController.new();world.add_child(local)
	local.collision_layer = 0;local.collision_mask = 0;local.set_physics_process(false)
	local.set_meta("shared_city_remote", true);local.set_meta("exploration_avoidance_adapter", true);local.set_meta("shared_city_motion", "walk");local.set_meta("human_model_id", "SeoulResident_M01")
	var local_visual := Node3D.new();local_visual.name = "Visual";local.add_child(local_visual)
	var local_body := MeshInstance3D.new();local_body.name = "Body";local_visual.add_child(local_body)
	var local_avatar: Node3D = AVATAR.new();local_visual.add_child(local_avatar)
	_check("local_controller_fixture_uses_original_avatar", local_avatar.setup(local))
	local_avatar.set_physics_process(false);local_avatar._physics_process(.1)
	_check("grounded_seam_never_overrides_local_controller", not local.is_on_floor() and local_avatar.state == "air")
	local.queue_free()
	var second: TransactionRemote = _remote()
	_check("separate_male_for_native_display", second.setup(_row("display_male", 0, 1000, Vector3(-.85, 0, 0), 0.0, "idle"), 1000, 1000))
	second.set_process(false);second.avatar.set_physics_process(false)
	male.global_position = Vector3(.85, 0, 0);male.visual.rotation.y = 0.0;male.velocity = Vector3.ZERO
	male.set_meta("shared_city_motion", "idle");male.avatar._last_position = male.global_position;male.avatar._physics_process(.5)
	second.avatar._physics_process(.5)
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await _capture_display(male, second)
	measurements = {"midpoint_position": [.75, 0, 0], "midpoint_actual": [middle.position.x, middle.position.y, middle.position.z], "midpoint_yaw": middle.yaw,
		"male_initial_skin": {"loaded": male_skin.loaded, "bones": male_skin.skeleton_bone_count, "meshes": male_skin.visible_mesh_count},
		"female_soft_swim": {"loaded": female_skin.loaded, "bones": female_skin.skeleton_bone_count, "meshes": female_skin.visible_mesh_count},
		"captures": captures, "final_buffer": male.presentation_snapshot().buffered_snapshots}
	var after: Dictionary = {}
	for path: String in SOURCES:after[path] = FileAccess.get_sha256(path)
	_check("component_source_unchanged_during_execution", after == source_before)
	world.queue_free();await process_frame;await process_frame
	_check("remote_actor_lifecycle_releases_display", not is_instance_valid(male) and not is_instance_valid(second))
	var result: Dictionary = {"task": "SHARED_CITY_REMOTE_RESIDENT", "result": "PASS" if failures.is_empty() else "FAIL", "checks": checks.size(), "failures": failures, "conditions": checks,
		"measurements": measurements, "source_sha256": source_before, "engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"scope": "Production remote component/Avatar with actual authored M/F GLBs. Approved snapshot interpolation and presentation only; no city launch, hosted multiplayer, shared physics/combat, anatomy quality or sustained comfort acceptance. Swimwear is real clothing; swimming stroke is not added."}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:quit(2);return
	file.store_string(JSON.stringify(result, "  ") + "\n");file.close()
	print("REMOTE_RESIDENT_CHECK ", checks.size() - failures.size(), "/", checks.size())
	quit(0 if failures.is_empty() else 1)

func _capture_display(female: TransactionRemote, male: TransactionRemote) -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var camera := Camera3D.new();world.add_child(camera);camera.position = Vector3(0, 1.25, 4.4);camera.look_at(Vector3(0, .9, 0));camera.make_current()
	var environment := WorldEnvironment.new();environment.environment = Environment.new();environment.environment.background_mode = Environment.BG_COLOR;environment.environment.background_color = Color(.11, .14, .17);environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color = Color(.78, .83, .92);environment.environment.ambient_light_energy = .8;world.add_child(environment)
	var light := DirectionalLight3D.new();light.rotation_degrees = Vector3(-35, -20, 0);light.light_energy = 1.4;world.add_child(light)
	for angle: float in [0.0, PI * .5, PI]:
		female.visual.rotation.y = angle;male.visual.rotation.y = angle
		female.avatar._textured_surface.active_native_rig().sync_pose();male.avatar._textured_surface.active_native_rig().sync_pose()
		await process_frame;await process_frame
		RenderingServer.force_draw(false)
		var image: Image = root.get_texture().get_image()
		var path: String = capture_dir.path_join("remote_pair_" + str(captures.size()) + ".png")
		var error: Error = image.save_png(path)
		_check("native_real_mesh_capture_" + str(captures.size()), error == OK and image.get_width() > 0 and image.get_height() > 0)
		if error == OK:captures.append(path)

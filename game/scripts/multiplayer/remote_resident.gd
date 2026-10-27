extends CharacterBody3D
## Presentation of approved room snapshots only. Never moves via physics,
## registers with city AI, or participates in combat/vehicle/game decisions.
const AVATAR := preload("res://scripts/player/exploration_avatar.gd")
const MODELS := ["SeoulResident_M01", "SeoulResident_F01"]
const PROFILES := ["standard", "soft", "athletic"]
const MOTIONS := ["idle", "walk", "run", "jump", "swim"]
const INTERPOLATION_MS := 600
const MAX_BUFFERED_SNAPSHOTS := 32
const MAX_SAFE_INTEGER := 9007199254740991.0
var resident_id := ""
var avatar: Node3D
var visual: Node3D
var _ready_remote := false
var _appearance: Dictionary = {}
var _samples: Array[Dictionary] = []
var _anchor_server_ms := 0.0
var _anchor_received_ms := 0
var _render_server_floor := 0.0
var _last_sequence := -1
var _last_updated_ms := -1.0
var _last_render_motion := "idle"

func _init() -> void:
	name = "RemoteResident"
	visible = false
	collision_layer = 0
	collision_mask = 0
	input_ray_pickable = false
	set_physics_process(false)
	set_meta("shared_city_remote", true)
	set_meta("exploration_avoidance_adapter", true)
	set_meta("shared_city_motion", "idle")
	set_meta("presentation_only", true)

func _ready() -> void:
	# Godot enables declared callbacks while entering the tree, after _init.
	set_physics_process(false)
	set_process(false)

func setup(row: Dictionary, server_now_ms: float, recv_ms: int = -1) -> bool:
	if _ready_remote or not is_inside_tree():return false
	var received: int = Time.get_ticks_msec() if recv_ms == -1 else recv_ms
	var data: Dictionary = _validated(row, server_now_ms)
	if received < 0 or data.is_empty():return false
	global_transform = Transform3D(Basis.IDENTITY, data.position)
	if not _apply_appearance(data.avatar):return false
	resident_id = data.id
	_ready_remote = true
	_accept(data, server_now_ms, received)
	visual.rotation.y = data.yaw
	_last_render_motion = data.motion
	set_meta("shared_city_motion", _last_render_motion)
	visible = true
	set_process(true)
	return true

func ingest(row: Dictionary, server_now_ms: float, recv_ms: int = -1) -> bool:
	if not _ready_remote:return false
	var received: int = Time.get_ticks_msec() if recv_ms == -1 else recv_ms
	var data: Dictionary = _validated(row, server_now_ms)
	if data.is_empty() or received < _anchor_received_ms or server_now_ms < _anchor_server_ms:return false
	if data.id != resident_id or data.sequence <= _last_sequence or data.updated_ms <= _last_updated_ms:return false
	if not _apply_appearance(data.avatar):return false
	_accept(data, server_now_ms, received)
	return true

func _accept(data: Dictionary, server_now_ms: float, received: int) -> void:
	_samples.append(data)
	while _samples.size() > MAX_BUFFERED_SNAPSHOTS:_samples.pop_front()
	_anchor_server_ms = server_now_ms
	_anchor_received_ms = received
	_last_sequence = data.sequence
	_last_updated_ms = data.updated_ms
	if _samples.size() == 1:_render_server_floor = data.updated_ms

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum and floorf(float(value)) == float(value)

static func _valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45,95]):return false
	return true

static func _validated(row: Dictionary, server_now_ms: float) -> Dictionary:
	if not _integer(server_now_ms, 0.0, MAX_SAFE_INTEGER):return {}
	for key: Variant in row:
		if key not in ["id", "sequence", "position", "yaw", "motion", "avatar", "updatedAtMs"]:return {}
	if not _valid_id(row.get("id")) or not _integer(row.get("sequence"), 0.0, 2147483647.0):return {}
	if not _integer(row.get("updatedAtMs"), 0.0, server_now_ms):return {}
	# updatedAtMs tracks the last position mutation, not membership liveness.
	# An idle participant's GET heartbeats may keep it active for much longer;
	# the manager removes actors absent from the server-approved room listing.
	var point: Variant = row.get("position")
	if not point is Array or point.size() != 3:return {}
	for value: Variant in point:
		if not _number(value):return {}
	var at := Vector3(float(point[0]), float(point[1]), float(point[2]))
	if absf(at.x) > 1000.0 or absf(at.z) > 1000.0 or at.y < -100.0 or at.y > 500.0:return {}
	if not _number(row.get("yaw")) or absf(float(row.yaw)) > PI:return {}
	if row.get("motion") not in MOTIONS or not row.get("avatar") is Dictionary:return {}
	var appearance: Dictionary = row.avatar
	if appearance.size() != 3 or appearance.get("modelId") not in MODELS or appearance.get("bodyProfile") not in PROFILES or not appearance.get("swimwear") is bool:return {}
	return {"id": row.id, "sequence": int(row.sequence), "position": at, "yaw": float(row.yaw), "motion": row.motion,
		"avatar": appearance.duplicate(true), "updated_ms": float(row.updatedAtMs)}

func _new_avatar() -> Node3D:
	return AVATAR.new()

func _assets_available(appearance: Dictionary) -> bool:
	var stem: String = "seoul_resident_f01" if appearance.modelId == "SeoulResident_F01" else "seoul_resident_m01"
	if appearance.bodyProfile != "standard":stem += "_" + String(appearance.bodyProfile)
	var prefix: String = "res://assets/original/seoul_resident/" + stem
	return ResourceLoader.exists(prefix + "_street.glb", "PackedScene") and (not appearance.swimwear or ResourceLoader.exists(prefix + "_swim.glb", "PackedScene"))

func _apply_appearance(appearance: Dictionary) -> bool:
	if appearance == _appearance and is_instance_valid(avatar):return true
	if not _assets_available(appearance):return false
	# Stage the complete display, including optional swimwear, while the accepted
	# display remains intact. Failure cannot replace it with pose proxies/boxes.
	var previous_visual: Node3D = visual
	var previous_model: Variant = get_meta("human_model_id") if has_meta("human_model_id") else null
	var previous_profile: Variant = get_meta("human_body_profile") if has_meta("human_body_profile") else null
	if is_instance_valid(previous_visual):previous_visual.name = "PreviousVisual"
	var candidate_visual := Node3D.new()
	candidate_visual.name = "Visual"
	candidate_visual.visible = false
	add_child(candidate_visual)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.visible = false
	candidate_visual.add_child(body)
	set_meta("human_model_id", appearance.modelId)
	set_meta("human_body_profile", appearance.bodyProfile)
	var candidate: Node3D = _new_avatar()
	candidate_visual.add_child(candidate)
	var accepted: bool = candidate.setup(self)
	if accepted:
		candidate.set_swimwear_visuals(appearance.swimwear)
		var skin: Dictionary = candidate.textured_model_snapshot(false)
		accepted = bool(skin.get("loaded", false)) and int(skin.get("skeleton_bone_count", 0)) > 0 and bool(skin.get("swimwear_active", false)) == bool(appearance.swimwear)
	if not accepted:
		remove_child(candidate_visual)
		candidate_visual.queue_free()
		if is_instance_valid(previous_visual):previous_visual.name = "Visual"
		if previous_model == null:remove_meta("human_model_id")
		else:set_meta("human_model_id", previous_model)
		if previous_profile == null:remove_meta("human_body_profile")
		else:set_meta("human_body_profile", previous_profile)
		return false
	visual = candidate_visual
	avatar = candidate
	_appearance = appearance.duplicate(true)
	if is_instance_valid(previous_visual):
		previous_visual.visible = false
		remove_child(previous_visual)
		previous_visual.queue_free()
	visual.visible = true
	return true

func sample_at(local_now_ms: int = -1) -> Dictionary:
	if _samples.is_empty():return {}
	var now_ms: int = Time.get_ticks_msec() if local_now_ms == -1 else local_now_ms
	var target: float = _anchor_server_ms + maxi(0, now_ms - _anchor_received_ms) - INTERPOLATION_MS
	target = clampf(maxf(target, _render_server_floor), _samples.front().updated_ms, _samples.back().updated_ms)
	var first: Dictionary = _samples.front()
	var second: Dictionary = first
	for index: int in range(1, _samples.size()):
		second = _samples[index]
		if target <= float(second.updated_ms):break
		first = second
	var span: float = float(second.updated_ms) - float(first.updated_ms)
	var fraction: float = clampf((target - float(first.updated_ms)) / span, 0.0, 1.0) if span > 0.0 else 0.0
	return {"position": Vector3(first.position).lerp(Vector3(second.position), fraction),
		"yaw": lerp_angle(float(first.yaw), float(second.yaw), fraction),
		"motion": second.motion if fraction >= 1.0 else first.motion,
		"server_ms": target, "first_sequence": first.sequence, "second_sequence": second.sequence, "fraction": fraction}

func _present_at(local_now_ms: int, delta: float) -> void:
	var frame: Dictionary = sample_at(local_now_ms)
	if frame.is_empty():return
	var previous: Vector3 = global_position
	global_transform = Transform3D(Basis.IDENTITY, frame.position)
	visual.rotation.y = frame.yaw
	velocity = (global_position - previous) / delta if delta > 0.0 else Vector3.ZERO
	_render_server_floor = frame.server_ms
	_last_render_motion = frame.motion
	set_meta("shared_city_motion", _last_render_motion)

func _process(delta: float) -> void:
	if _ready_remote:_present_at(Time.get_ticks_msec(), delta)

func _physics_process(_delta: float) -> void:
	pass

func presentation_snapshot() -> Dictionary:
	return {"ready": _ready_remote, "id": resident_id, "sequence": _last_sequence, "updatedAtMs": _last_updated_ms,
		"buffered_snapshots": _samples.size(), "interpolation_ms": INTERPOLATION_MS, "motion": _last_render_motion,
		"appearance": _appearance.duplicate(true), "position": global_position, "velocity": velocity,
		"collision_layer": collision_layer, "collision_mask": collision_mask, "presentation_only": true,
		"extrapolation": false, "scope": "Approved remote display only; no shared physics, collisions, combat, vehicle ownership or game decisions."}

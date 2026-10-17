extends Node3D
## Door-local visual cues and a compass pin. The pin gives a bearing, never a route.
const LIBRARY_ID := "osm:relation:10757525:building"
const TARGET_RADIUS_M := 150.0
const SIGN_RADIUS_M := 120.0
const MAX_VISIBLE_LABELS := 3
var host: Node3D
var visit: Node3D
var loaded := false
var target_spec: Dictionary = {}
var world_frames: Node3D
var panel: PanelContainer
var caption: Label
var direction_label: Label
var target_label: Label
var bearing_arrow: Label
var markers: Array[Dictionary] = []
var anchors: Array[Dictionary] = []
var _cyan: Array[Transform3D] = []
var _white: Array[Transform3D] = []
var _navy: Array[Transform3D] = []
var _hidden := true
var _target_distance := 0.0
var _occluded := false
var _behind := false
var _on_screen := false
var _visible_labels := 0
var _visible_ground_labels := 0
var _last_los_id := ""
var _los_elapsed := 1.0
var _viewport_size := Vector2.ZERO
var _height_above_ground_m := 0.0
var _ground_height_known := false

func setup(root_scene: Node3D, visit_controller: Node3D) -> bool:
	if loaded or not is_instance_valid(root_scene) or not is_instance_valid(visit_controller): return false
	host = root_scene
	visit = visit_controller
	if visit.catalog.is_empty() or host.get_node_or_null("Interface") == null: return false
	global_transform = Transform3D.IDENTITY
	world_frames = Node3D.new()
	world_frames.name = "WorldFrames"
	add_child(world_frames)
	for spec: Dictionary in visit.catalog: _build_entrance(spec)
	_add_batch("PortalCyan", _cyan, Color(0.02, 0.85, 0.94))
	_add_batch("PortalWhite", _white, Color(0.97, 1.0, 1.0))
	_add_batch("PortalBackplates", _navy, Color(0.015, 0.12, 0.22))
	_build_pin()
	world_frames.visible = false
	loaded = true
	return true

func _box(basis: Basis, origin: Vector3, offset: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(basis.scaled_local(size), origin + basis * offset)

func _build_entrance(spec: Dictionary) -> void:
	var outward: Vector3 = spec.outward
	outward.y = 0.0
	outward = outward.normalized()
	var basis := Basis(Vector3(outward.z, 0.0, -outward.x), Vector3.UP, outward)
	var ground: float = float(spec.get("base_offset_m",0.0))+(spec.flat_source_entrance.y if spec.has("flat_source_entrance") else spec.entrance.y)
	# The facade frame follows the level foundation. Its separate E pad follows
	# the actual outdoor pavement triangle at the source foot anchor.
	# Source door Y denotes its facade centre, not the pavement elevation.
	var door_anchor := Vector3(spec.door.x, ground, spec.door.z)
	var width := 4.79 if spec.id == LIBRARY_ID else 2.44
	var height := 6.325 if spec.id == LIBRARY_ID else 2.725
	var portal_index := _cyan.size()
	for side: float in [-1.0, 1.0]:
		_cyan.append(_box(basis, door_anchor, Vector3(side * width * 0.5, height * 0.5, 0.22), Vector3(0.24, height, 0.26)))
	_cyan.append(_box(basis, door_anchor, Vector3(0.0, height, 0.22), Vector3(width + 0.24, 0.25, 0.26)))
	_white.append(_box(basis, door_anchor, Vector3(0.0, height - 0.23, 0.37), Vector3(width - 0.15, 0.09, 0.07)))
	var sign_point := door_anchor + basis * Vector3(0.0, height + 0.63, 0.26)
	_navy.append(_box(basis, door_anchor, Vector3(0.0, height + 0.63, 0.24), Vector3(width + 0.24, 1.0, 0.20)))
	_cyan.append(_box(basis, door_anchor, Vector3(0.0, height + 1.15, 0.27), Vector3(width + 0.24, 0.10, 0.22)))
	var sign := _world_label("정문" if spec.id == LIBRARY_ID else "입구", 64, 0.014)
	sign.name = "FacadeSign"
	sign.transform = Transform3D(basis, sign_point + outward * 0.13)
	# The E pad marks the controller's exact ground anchor two metres outside.
	var entrance: Vector3 = spec.entrance
	var threshold_index := _navy.size()
	var threshold := _box(basis, entrance, Vector3(0.0, 0.035, 0.0), Vector3(1.5, 0.035, 1.25))
	_navy.append(threshold)
	for side: float in [-1.0, 1.0]:
		_cyan.append(_box(basis, entrance, Vector3(side * 0.79, 0.045, 0.0), Vector3(0.09, 0.04, 1.4)))
		_cyan.append(_box(basis, entrance, Vector3(0.0, 0.045, side * 0.68), Vector3(1.65, 0.04, 0.09)))
	var floor_basis := Basis(basis.x, -outward, Vector3.UP)
	var floor_letter := _world_label("E", 64, 0.013)
	floor_letter.name = "GroundE"
	floor_letter.transform = Transform3D(floor_basis, entrance + Vector3.UP * 0.075)
	# Short chevron points from the pad toward its source facade; no path claim.
	for side: float in [-1.0, 1.0]:
		var chevron_basis := basis * Basis(Vector3.UP, side * PI / 4.0)
		_white.append(_box(chevron_basis, entrance + basis * Vector3(side * 0.22, 0.06, -0.99), Vector3.ZERO, Vector3(0.11, 0.04, 0.65)))
	markers.append({"spec": spec, "sign": sign, "ground": floor_letter, "outward": outward})
	anchors.append({"id": spec.id, "door_anchor": door_anchor, "entrance": entrance,
		"outward": outward, "portal_width": width, "portal_height": height,
		"portal_transform": Transform3D(basis, door_anchor), "portal_cyan_index": portal_index,
		"threshold_transform": threshold, "threshold_backplate_index": threshold_index})

func _world_label(value: String, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.01, 0.08, 0.16)
	label.outline_size = 6
	label.no_depth_test = false
	label.shaded = false
	label.double_sided = false
	label.visible = false
	world_frames.add_child(label)
	return label

func _add_batch(title: String, transforms: Array[Transform3D], color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.8
	mesh.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for index in transforms.size(): batch.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_frames.add_child(node)

func _build_pin() -> void:
	panel = PanelContainer.new()
	panel.name = "EntranceCompassPin"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 4
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.11, 0.19, 0.96)
	style.border_color = Color(0.08, 0.91, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	# Containers reset transforms on their direct children during layout. Keep
	# the rotating arrow inside a plain Control so its bearing survives resize.
	var arrow_slot:=Control.new()
	arrow_slot.custom_minimum_size=Vector2(32,36)
	arrow_slot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow_slot)
	bearing_arrow = Label.new()
	bearing_arrow.text = "▲"
	bearing_arrow.add_theme_font_size_override("font_size", 26)
	bearing_arrow.add_theme_color_override("font_color", Color(0.10, 0.94, 1.0))
	bearing_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bearing_arrow.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	bearing_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_slot.add_child(bearing_arrow)
	bearing_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	caption = _pin_label(words, 18, Color.WHITE)
	target_label = _pin_label(words, 14, Color(0.82, 0.96, 1.0))
	direction_label = _pin_label(words, 12, Color(0.70, 0.85, 0.91))
	panel.visible = false
	host.get_node("Interface").add_child(panel)

func _pin_label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func update_guidance(delta: float, hidden: bool) -> void:
	if not loaded or not is_instance_valid(host) or not is_instance_valid(visit): return
	# EXP21's absolute height can be tens of metres on an ordinary street.
	# Compare against the same local terrain that carries the pavement.
	var ground_y := 0.0
	var terrain := host.get_node_or_null("TerrainSurface")
	_ground_height_known = false
	if is_instance_valid(terrain) and terrain.has_method("ground_y_world"):
		var sampled: float = terrain.ground_y_world(host.player.global_position)
		if is_finite(sampled):
			ground_y = sampled
			_ground_height_known = true
	_height_above_ground_m = host.player.global_position.y-ground_y
	var elevated: bool=not host.player.interior_active and _height_above_ground_m>6.0
	_hidden = hidden or bool(visit.active) or elevated
	if elevated:target_spec={}
	world_frames.visible = not _hidden
	panel.visible = false
	_visible_labels = 0
	_visible_ground_labels = 0
	for marker: Dictionary in markers:
		marker.sign.visible = false
		marker.ground.visible = false
	if _hidden: return
	var camera: Camera3D = host.rig.camera
	if not is_instance_valid(camera): return
	_viewport_size = host.get_viewport().get_visible_rect().size
	var player_position: Vector3 = host.player.global_position
	target_spec = _select_target(player_position)
	if target_spec.is_empty(): return
	_target_distance = _ground_distance(player_position, target_spec.entrance)
	# Let the existing interaction prompt use this same door this frame.
	if not bool(visit.get("_entry_requested")): visit._set_entry(target_spec)
	_los_elapsed += maxf(delta, 0.0)
	if _last_los_id != String(target_spec.id) or _los_elapsed >= 0.15 or _target_distance<=8.0:
		_last_los_id = target_spec.id
		_los_elapsed = 0.0
		_occluded = _entry_blocked(player_position, target_spec)
	_update_labels(camera, player_position)
	_update_pin(camera, player_position)

func _ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _select_target(player_position: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var aimed: Dictionary = {}
	var nearest_distance := TARGET_RADIUS_M
	var names: Node = host.get("building_names")
	var aimed_id := ""
	if is_instance_valid(names) and bool(names.get("current_is_targeted")):
		aimed_id = String(names.get("current_id"))
	for spec: Dictionary in visit.catalog:
		var distance := _ground_distance(player_position, spec.entrance)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = spec
		if String(spec.id) == aimed_id and distance <= TARGET_RADIUS_M: aimed = spec
	# E remains usable at the door even when the camera faces another building.
	if nearest_distance <= 5.0: return nearest
	return aimed if not aimed.is_empty() else nearest

func _entry_blocked(player_position: Vector3, spec: Dictionary) -> bool:
	var origin := player_position + Vector3.UP
	var destination: Vector3 = spec.entrance + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, destination, 1, [host.player.get_rid()])
	return not host.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_labels(camera: Camera3D, player_position: Vector3) -> void:
	var candidates: Array[Dictionary] = []
	var ground_candidates: Array[Dictionary] = []
	for marker: Dictionary in markers:
		var spec: Dictionary = marker.spec
		var distance := _ground_distance(player_position, spec.entrance)
		# Looking down at the pad must not hide E just because the facade sign
		# is above the viewport. Floor and facade labels have separate visibility.
		if distance<=16.0 and not camera.is_position_behind(marker.ground.global_position):
			var floor_point := camera.unproject_position(marker.ground.global_position)
			if Rect2(Vector2.ZERO,_viewport_size).has_point(floor_point):ground_candidates.append({"marker":marker,"distance":distance})
		if distance > SIGN_RADIUS_M: continue
		# A wall sign faces the street; depth testing hides it behind other walls.
		if (camera.global_position - marker.sign.global_position).dot(marker.outward) <= 0.0: continue
		if camera.is_position_behind(marker.sign.global_position): continue
		var point := camera.unproject_position(marker.sign.global_position)
		if not Rect2(Vector2.ZERO, _viewport_size).has_point(point): continue
		candidates.append({"marker": marker, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for index in mini(MAX_VISIBLE_LABELS, candidates.size()):
		var candidate: Dictionary = candidates[index]
		candidate.marker.sign.visible = true
		_visible_labels += 1
	ground_candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
	for index in mini(MAX_VISIBLE_LABELS,ground_candidates.size()):
		ground_candidates[index].marker.ground.visible=true
		_visible_ground_labels+=1

func _direction_word(camera: Camera3D, entrance: Vector3) -> String:
	var local := camera.global_basis.inverse() * (entrance - camera.global_position)
	var angle := atan2(local.x, -local.z)
	if absf(angle) < 0.35: return "앞쪽 입구"
	if absf(angle) > 2.45: return "뒤쪽 입구"
	return "오른쪽 입구" if angle > 0.0 else "왼쪽 입구"

func _avatar_screen_rect(camera: Camera3D) -> Rect2:
	if not host.player.get_node("Visual").is_visible_in_tree():return Rect2()
	var result:=Rect2();var first:=true
	for x: float in [-.45,.45]:
		for y: float in [0.,1.85]:
			for z: float in [-.45,.45]:
				var point: Vector3=host.player.global_position+Vector3(x,y,z)
				if camera.is_position_behind(point):continue
				var pixel:=camera.unproject_position(point)
				if not pixel.is_finite():continue
				result=Rect2(pixel,Vector2.ZERO) if first else result.expand(pixel)
				first=false
	return result.grow(10.) if not first else Rect2()

func _update_pin(camera: Camera3D, player_position: Vector3) -> void:
	if _viewport_size.x < 100.0 or _viewport_size.y < 100.0: return
	var entrance: Vector3 = target_spec.entrance
	var world_point := entrance + Vector3.UP * 2.4
	_behind = camera.is_position_behind(world_point)
	var center := _viewport_size * 0.5
	var projected := camera.unproject_position(world_point) if not _behind else center
	_on_screen = not _behind and Rect2(Vector2(12, 12), _viewport_size - Vector2(24, 24)).has_point(projected)
	var bearing := projected - center
	if _behind:
		var local := camera.global_basis.inverse() * (world_point - camera.global_position)
		bearing = Vector2(local.x, absf(local.z))
		if bearing.length_squared() < 0.01: bearing = Vector2.DOWN
	if bearing.length_squared() < 0.01: bearing = Vector2.UP
	caption.text = "%s · %.0f m" % ["정문" if target_spec.id == LIBRARY_ID else "입구", _target_distance]
	target_label.text = String(target_spec.title)
	var backside := (player_position - entrance).dot(Vector3(target_spec.outward)) < -1.0
	var status := "건물 반대편 입구" if _occluded and backside else ("입구 방향" if _occluded else _direction_word(camera, entrance))
	var near: bool = visit._entry_near()
	direction_label.text = visit.entry_action_text() if near and not _occluded else status + " · 직선거리"
	# Width comes from the viewport, and ellipsis prevents long OSM names from
	# expanding the badge beyond the edge clamp on a small window.
	var width := minf(282.0, _viewport_size.x - 24.0)
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size = Vector2(width, 0)
	panel.reset_size()
	var panel_size := panel.get_combined_minimum_size()
	panel_size.x = width
	panel.size = panel_size
	var half := panel_size * 0.5
	var margin := Vector2(12, 12)
	var desired: Vector2
	if _on_screen:
		desired = projected - Vector2(0, half.y + 18)
	else:
		var extent := center - half - margin
		var unit := bearing.normalized()
		var factor := minf(extent.x / maxf(absf(unit.x), 0.001), extent.y / maxf(absf(unit.y), 0.001))
		desired = center + unit * factor
	desired.x = clampf(desired.x, half.x + margin.x, _viewport_size.x - half.x - margin.x)
	desired.y = clampf(desired.y, half.y + margin.y, _viewport_size.y - half.y - margin.y)
	var avatar_rect: Rect2=_avatar_screen_rect(camera)
	if avatar_rect.has_area() and Rect2(desired-half,panel_size).intersects(avatar_rect):
		var status_rect: Rect2=host.status.get_global_rect().grow(12.)
		var choices: Array[Vector2]=[
			Vector2(desired.x,avatar_rect.position.y-half.y-12.),
			Vector2(avatar_rect.position.x-half.x-12.,desired.y),
			Vector2(avatar_rect.end.x+half.x+12.,desired.y),
			Vector2(desired.x,avatar_rect.end.y+half.y+12.)]
		for candidate: Vector2 in choices:
			candidate.x=clampf(candidate.x,half.x+margin.x,_viewport_size.x-half.x-margin.x)
			candidate.y=clampf(candidate.y,half.y+margin.y,_viewport_size.y-half.y-margin.y)
			var rect:=Rect2(candidate-half,panel_size)
			if rect.intersects(avatar_rect) or rect.intersects(status_rect):continue
			desired=candidate;break
	panel.position = desired - half
	bearing_arrow.pivot_offset = bearing_arrow.size * 0.5
	bearing_arrow.rotation = bearing.angle() + PI * 0.5
	panel.visible = true

func snapshot() -> Dictionary:
	return {"loaded": loaded, "hidden": _hidden, "marker_count": markers.size(),
		"visible_label_count": _visible_labels,"visible_ground_label_count":_visible_ground_labels, "target_id": String(target_spec.get("id", "")),
		"target_distance_m": _target_distance, "target_entrance": target_spec.get("entrance", Vector3.ZERO),
		"target_door": target_spec.get("door", Vector3.ZERO), "target_occluded": _occluded,
		"target_behind_camera": _behind, "target_on_screen": _on_screen,
		"panel_visible": is_instance_valid(panel) and panel.visible,
		"panel_rect": panel.get_rect() if is_instance_valid(panel) else Rect2(),
		"panel_text": caption.text + "\n" + target_label.text + "\n" + direction_label.text if loaded else "",
		"viewport_size": _viewport_size, "geometry_body_count": 0, "anchors": anchors.duplicate(true),
		"height_above_ground_m":_height_above_ground_m,"ground_height_known":_ground_height_known}

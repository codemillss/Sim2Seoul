extends Node3D
## Isolated, metre-scale form review. No production avatar, controller or
## city resource is replaced. Numerical integrity is not an art acceptance.
signal selection_changed
const SOURCES := {
	"new": "res://assets/original/resident_study/resident_form_m01.glb",
	"previous": "res://assets/original/resident_study/resident_form_m01_previous.glb"
}
const MANIFESTS := {
	"new": "res://assets/original/resident_study/FORM_STUDY_MANIFEST.json",
	"previous": "res://assets/original/resident_study/FORM_STUDY_PREVIOUS_MANIFEST.json"
}
const POSES: Array[String] = ["a_pose", "arm_raise", "deep_squat", "single_support"]
const VIEWS := {"front": 0., "right": 90., "back": 180., "oblique": 45.}
const NEW_BONES: Array[String] = ["root", "pelvis", "spine", "chest", "neck", "head", "clavicle.L", "upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L", "foot.L", "toe.L", "clavicle.R", "upper_arm.R", "forearm.R", "hand.R", "thigh.R", "shin.R", "foot.R", "toe.R"]
const SAMPLE_TIME_S := 1.0 # Inside authored frame24..36 hold (glTF time starts at frame1).
const CAMERA_FOV_DEG := 32.
const FRAMING := {
	"a_pose": {"target":Vector3(0, 1.05, 0), "distance":4.7},
	"arm_raise": {"target":Vector3(0, 1.2, 0), "distance":6.2},
	"deep_squat": {"target":Vector3(0, .75, .10), "distance":4.7},
	"single_support": {"target":Vector3(0, 1., 0), "distance":4.9}
}
const CORRECTIVES := {
	"a_pose": [0., 0., 0.], "arm_raise": [1., 0., 0.],
	"deep_squat": [0., 1., 1.], "single_support": [0., .2, .2]
}
const CORRECTIVE_NAMES: Array[String] = ["StudyShoulderSupport", "StudyHipCompression", "StudyKneeCompression"]
var selected_model := "new"
var selected_pose := "a_pose"
var selected_view := "front"
var loaded := false
var load_error := ""
var review_mode := false
var automatic := false
var camera: Camera3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var environment: Environment
var model_anchor: Node3D
var model_root: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var clay: StandardMaterial3D
var _stage_materials: Array[StandardMaterial3D] = []
var ui: CanvasLayer
var status: Label
var ruler: MeshInstance3D
var _angle := 0.
var _rest_local: Array[Transform3D] = []
var _rest_world: Array[Transform3D] = []
var _materials: Array[Dictionary] = []
var _rest_bounds := AABB()
var _source_sha := ""
var _manifest: Dictionary = {}
var _manifest_sha := ""
var _clip := ""
var _strategy := ""
var _buttons: Dictionary = {}
var _pose_application_ok := false
var _surface_cache: Array[Dictionary] = []
var _posed_bounds := AABB()
var _posed_vertices := 0
var _posed_finite := false
var _panel: PanelContainer

func _ready() -> void:
	# The exploration menu pauses the tree. Its owner has been unloaded by
	# this scene change, so the independent gallery owns a fresh input state.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_make_stage()
	_make_ui()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--study-review": review_mode = true
		if arg.begins_with("--study-model="): selected_model = arg.trim_prefix("--study-model=")
	set_view("front")
	select_model(selected_model)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.
	material.metallic_specular = .24
	# Keep every per-instance override alive until this parent and its child
	# rendering instances finish exiting the tree (the same lifetime contract
	# used by the production surface).
	_stage_materials.append(material)
	return material

func _box(title: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.name = title; node.mesh = box; node.material_override = material; node.position = at
	add_child(node)
	return node

func _make_stage() -> void:
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.22, .22, .22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .30
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.
	environment.ssao_enabled = true
	world.environment = environment; add_child(world)
	key_light = DirectionalLight3D.new()
	key_light.name = "FixedNeutralKey"
	key_light.rotation_degrees = Vector3(-35, -35, 0)
	key_light.light_color = Color.WHITE; key_light.light_energy = 1.15
	key_light.shadow_enabled = true; key_light.directional_shadow_max_distance = 12.
	add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.name = "FixedNeutralFill"; fill_light.rotation_degrees = Vector3(-20, 130, 0)
	fill_light.light_color = Color.WHITE; fill_light.light_energy = .55; fill_light.shadow_enabled = false
	add_child(fill_light)
	clay = _make_material(Color(.52, .52, .52), .72)
	clay.resource_name = "StudyOnlyMatteGray"
	clay.vertex_color_use_as_albedo = false
	clay.cull_mode = BaseMaterial3D.CULL_BACK
	_box("FloorAtZeroMetres", Vector3(5., .04, 5.), Vector3(0, -.02, 0), _make_material(Color(.31, .31, .31), .90))
	var dark := _make_material(Color(.12, .12, .12), .85)
	ruler = _box("OneMetreReference", Vector3(.012, 1., .012), Vector3(-.85, .5, 0), dark)
	for index: int in range(11):
		_box("RulerTick"+str(index), Vector3(.055 if index%5 == 0 else .032, .004, .012), Vector3(-.85, index*.1, 0), dark)
	var label := Label3D.new()
	label.text = "1 m"; label.position = Vector3(-.85, 1.09, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.font_size = 48
	label.modulate = Color(.76, .76, .76); add_child(label)
	model_anchor = Node3D.new(); model_anchor.name = "UnscaledStudyModel"; add_child(model_anchor)
	camera = Camera3D.new(); camera.name = "FixedLensStudyCamera"
	camera.fov = CAMERA_FOV_DEG; camera.near = .05; camera.far = 25.; camera.current = true
	add_child(camera)

func _button(row: HBoxContainer, key: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text; button.pressed.connect(callback)
	row.add_child(button); _buttons[key] = button
	return button

func _make_ui() -> void:
	ui = CanvasLayer.new(); ui.name = "StudyControls"; add_child(ui)
	var panel := PanelContainer.new()
	_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 12; panel.offset_right = -12; panel.offset_top = 10
	var style := StyleBoxFlat.new(); style.bg_color = Color(.10, .10, .10, .94)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 6; style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style); ui.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 4); panel.add_child(column)
	var source_row := HBoxContainer.new(); column.add_child(source_row)
	var title := Label.new(); title.text = "인체 원형 비교"; source_row.add_child(title)
	_button(source_row, "model_new", "새 원형", select_model.bind("new"))
	_button(source_row, "model_previous", "이전 원형(v04)", select_model.bind("previous"))
	status = Label.new(); status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; source_row.add_child(status)
	_button(source_row, "return_city", "거리로 돌아가기", _return_city)
	var views := HBoxContainer.new(); column.add_child(views)
	for entry: Array in [["front", "정면"], ["right", "옆면"], ["back", "후면"], ["oblique", "45도"]]:
		_button(views, "view_"+entry[0], entry[1], set_view.bind(entry[0]))
	_button(views, "turntable", "자동 둘러보기", _toggle_automatic)
	var poses := HBoxContainer.new(); column.add_child(poses)
	for entry: Array in [["a_pose", "기본 자세"], ["arm_raise", "팔 올림"], ["deep_squat", "깊은 앉기"], ["single_support", "한발 지지"]]:
		_button(poses, "pose_"+entry[0], entry[1], apply_pose.bind(entry[0]))
	var note := Label.new(); note.text = "동일 렌즈·조명·무채색 / 양쪽 원형의 원본 자세·모프 재생"
	note.add_theme_font_size_override("font_size", 13); poses.add_child(note)

func _toggle_automatic() -> void:
	if not review_mode: automatic = not automatic

func _return_city() -> void:
	get_tree().change_scene_to_file("res://scenes/world/explore_walk.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_return_city()

func set_review_mode(enabled: bool) -> void:
	review_mode = enabled
	if enabled: automatic = false

func _process(delta: float) -> void:
	if automatic and not review_mode:
		_angle += delta*deg_to_rad(20.)
		_place_camera()

func _place_camera() -> void:
	var target: Vector3 = FRAMING[selected_pose].target
	camera.position = target + Vector3(sin(_angle), 0, cos(_angle))*float(FRAMING[selected_pose].distance)
	camera.look_at(target, Vector3.UP)

func set_view(title: String) -> bool:
	if not VIEWS.has(title): return false
	selected_view = title; automatic = false; _angle = deg_to_rad(float(VIEWS[title])); _place_camera()
	return true

func _role_name(role: String, side := "") -> String:
	return role+("."+side if not side.is_empty() else "")

func _bone(role: String, side := "") -> int:
	return skeleton.find_bone(_role_name(role, side)) if is_instance_valid(skeleton) else -1

func select_model(title: String) -> bool:
	if not SOURCES.has(title): return false
	if is_instance_valid(model_root):
		model_root.visible = false; model_root.get_parent().remove_child(model_root); model_root.queue_free()
	loaded = false; load_error = ""; meshes.clear(); _rest_local.clear(); _rest_world.clear(); _materials.clear(); _surface_cache.clear()
	model_root = null; skeleton = null; animation_player = null; selected_model = title
	_source_sha = ""; _manifest.clear(); _manifest_sha = ""; _clip = ""; _strategy = ""; _pose_application_ok = false
	_posed_vertices = 0; _posed_finite = false
	var path: String = SOURCES[title]
	if not FileAccess.file_exists(path): return _load_failure("새 원형을 준비 중입니다." if title == "new" else "이전 모델을 찾지 못했습니다.")
	_source_sha = FileAccess.get_sha256(path)
	var manifest_path: String = MANIFESTS[title]
	if FileAccess.file_exists(manifest_path):
		_manifest_sha = FileAccess.get_sha256(manifest_path)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if parsed is Dictionary: _manifest = parsed
	var packed: PackedScene = load(path)
	if packed == null: return _load_failure("모델을 불러오지 못했습니다.")
	model_root = packed.instantiate(); model_anchor.add_child(model_root)
	for node: Node in model_root.find_children("*", "Skeleton3D", true, false):
		if skeleton == null: skeleton = node as Skeleton3D
	for node: Node in model_root.find_children("*", "AnimationPlayer", true, false):
		if animation_player == null: animation_player = node as AnimationPlayer
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		meshes.append(mesh)
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null: _materials.append({"resource":source, "color":source.albedo_color, "roughness":source.roughness, "texture":source.albedo_texture})
		mesh.material_override = clay
	if skeleton == null or meshes.is_empty(): return _load_failure("골격 또는 표면을 찾지 못했습니다.")
	skeleton.reset_bone_poses(); skeleton.force_update_all_bone_transforms()
	for index: int in range(skeleton.get_bone_count()):
		_rest_local.append(skeleton.get_bone_pose(index))
		_rest_world.append(skeleton.global_transform*skeleton.get_bone_global_pose(index))
	var initialized := false
	for mesh: MeshInstance3D in meshes:
		var bounds := mesh.global_transform*mesh.get_aabb()
		_rest_bounds = bounds if not initialized else _rest_bounds.merge(bounds); initialized = true
	_cache_geometry()
	loaded = true
	var result := apply_pose(selected_pose)
	selection_changed.emit()
	return result

func _load_failure(message: String) -> bool:
	load_error = message
	if is_instance_valid(status): status.text = message
	return false

func _reset_pose() -> void:
	if animation_player != null: animation_player.stop()
	for index: int in range(_rest_local.size()):
		var rest: Transform3D = _rest_local[index]
		skeleton.set_bone_pose_position(index, rest.origin)
		skeleton.set_bone_pose_rotation(index, rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(index, rest.basis.get_scale())
	for mesh: MeshInstance3D in meshes:
		for index: int in range(mesh.get_blend_shape_count()): mesh.set_blend_shape_value(index, 0.)
	skeleton.force_update_all_bone_transforms()

func _find_clip(title: String) -> String:
	if animation_player == null: return ""
	for name_: String in animation_player.get_animation_list():
		if name_ == title or name_.get_file() == title: return name_
	return ""

func apply_pose(title: String) -> bool:
	if not loaded or title not in POSES: return false
	selected_pose = title; load_error = ""; _reset_pose(); _clip = ""; _pose_application_ok = false
	# Both sides use their own exported native NLA/morph tracks. No forced
	# bone retargeting, legacy adapter or vertex-count normalization is used.
	_strategy = "actual_imported_NLA_animation_and_corrective_morph"
	_clip = _find_clip(title)
	if _clip.is_empty(): return _load_failure("이 자세의 자료를 찾지 못했습니다.")
	var animation := animation_player.get_animation(_clip)
	if animation.length < SAMPLE_TIME_S-.0001: return _load_failure("자세 기록의 길이가 부족합니다.")
	animation_player.play(_clip)
	animation_player.seek(SAMPLE_TIME_S, true)
	animation_player.advance(0.)
	animation_player.pause()
	_pose_application_ok = true
	publish_skin_state()
	_refresh_pose_bounds()
	_place_camera()
	status.text = ("새 원형 / " if selected_model == "new" else "이전 원형(v04) / ")+String({"a_pose":"기본 자세", "arm_raise":"팔 올림", "deep_squat":"깊은 앉기", "single_support":"한발 지지"}[title])
	selection_changed.emit()
	return _pose_application_ok

func _cache_geometry() -> void:
	for mesh: MeshInstance3D in meshes:
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var referenced := {}
			if indices.is_empty():
				for index: int in range(vertices.size()): referenced[index] = true
			else:
				for index: int in indices: referenced[index] = true
			var morphs: Array = mesh.mesh.surface_get_blend_shape_arrays(surface)
			_surface_cache.append({"mesh":mesh, "vertices":vertices, "bones":arrays[Mesh.ARRAY_BONES], "weights":arrays[Mesh.ARRAY_WEIGHTS], "referenced":referenced.keys(), "morphs":morphs})

func _refresh_pose_bounds() -> void:
	# The installed renderer's skeleton.glsl applies absolute morph targets
	# with base*(1-sum) in NORMALIZED mode, additive targets in RELATIVE mode,
	# then the actual bone palette. This is a conservative framing envelope,
	# not a mesh-quality or pixel-level GPU position acceptance.
	# https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/servers/rendering/renderer_rd/shaders/skeleton.glsl
	_posed_vertices = 0; _posed_finite = true
	for row: Dictionary in _surface_cache:
		var mesh: MeshInstance3D = row.mesh
		var matrices: Array[Transform3D] = []
		var owner := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if mesh.skin != null and owner != null:
			for binding: int in range(mesh.skin.get_bind_count()):
				var name_ := mesh.skin.get_bind_name(binding)
				var bone := owner.find_bone(name_) if not name_.is_empty() else mesh.skin.get_bind_bone(binding)
				if bone < 0: _posed_finite = false; continue
				matrices.append(owner.global_transform*owner.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(binding))
		var source: PackedVector3Array = row.vertices
		var bones: PackedInt32Array = row.bones if row.bones != null else PackedInt32Array()
		var weights: PackedFloat32Array = row.weights if row.weights != null else PackedFloat32Array()
		var slots: int = bones.size()/source.size() if not source.is_empty() else 0
		for index: int in row.referenced:
			var point: Vector3 = source[index]
			var total := 0.; var blend := Vector3.ZERO
			for shape: int in range(row.morphs.size()):
				var weight: float = mesh.get_blend_shape_value(shape)
				if absf(weight) <= .0001: continue
				var targets: PackedVector3Array = row.morphs[shape][Mesh.ARRAY_VERTEX]
				if targets.size() != source.size(): _posed_finite = false; continue
				blend += targets[index]*weight; total += weight
			if mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED: point *= 1.-total
			point += blend
			var world := mesh.global_transform*point
			if not matrices.is_empty():
				world = Vector3.ZERO
				for slot: int in range(slots):
					var binding: int = bones[index*slots+slot]
					if binding < 0 or binding >= matrices.size(): _posed_finite = false; continue
					world += (matrices[binding]*point)*weights[index*slots+slot]
			_posed_finite = _posed_finite and world.is_finite()
			_posed_bounds = AABB(world, Vector3.ZERO) if _posed_vertices == 0 else _posed_bounds.expand(world)
			_posed_vertices += 1

func projected_frame() -> Dictionary:
	var minimum := Vector2(INF, INF); var maximum := Vector2(-INF, -INF); var front := true
	for corner: int in range(8):
		var point := _posed_bounds.get_endpoint(corner)
		front = front and not camera.is_position_behind(point)
		var pixel := camera.unproject_position(point)
		minimum = minimum.min(pixel); maximum = maximum.max(pixel)
	var viewport := get_viewport().get_visible_rect().size
	var top := _panel.get_global_rect().end.y+10. if ui.visible else 10.
	var inside := _posed_finite and _posed_vertices > 0 and front and minimum.x >= 10. and maximum.x <= viewport.x-10. and minimum.y >= top and maximum.y <= viewport.y-10.
	return {"inside_unobscured_frame":inside, "projected_min_px":minimum, "projected_max_px":maximum, "ui_bottom_plus_margin_px":top, "viewport_size":viewport, "actual_morphed_skinned_world_aabb":_posed_bounds, "referenced_vertices":_posed_vertices, "finite":_posed_finite, "scope":"Project all8 corners of the actual indexed morph-then-skin CPU envelope; conservative whole-body inclusion. Bone/rest AABB alone is not used. Renderer palette is checked separately."}

func _joint(index: int) -> Transform3D:
	return skeleton.global_transform*skeleton.get_bone_global_pose(index)

func publish_skin_state() -> Dictionary:
	if not is_instance_valid(skeleton): return {"valid":false, "matrices":0}
	skeleton.force_update_all_bone_transforms()
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	var count := 0; var error := 0.; var finite := true
	for mesh: MeshInstance3D in meshes:
		if mesh.skin == null: continue
		var owner := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var reference := mesh.get_skin_reference()
		if owner == null or reference == null: finite = false; continue
		var rid := reference.get_skeleton()
		if RenderingServer.skeleton_get_bone_count(rid) != mesh.skin.get_bind_count(): finite = false; continue
		for bind: int in range(mesh.skin.get_bind_count()):
			var name_ := mesh.skin.get_bind_name(bind)
			var index := owner.find_bone(name_) if not name_.is_empty() else mesh.skin.get_bind_bone(bind)
			if index < 0: finite = false; continue
			var expected := owner.get_bone_global_pose(index)*mesh.skin.get_bind_pose(bind)
			var actual := RenderingServer.skeleton_bone_get_transform(rid, bind)
			finite = finite and actual.is_finite()
			error = maxf(error, actual.origin.distance_to(expected.origin))
			for axis: int in range(3): error = maxf(error, actual.basis[axis].distance_to(expected.basis[axis]))
			count += 1
	return {"valid":finite and count > 0 and error < .00002, "matrices":count, "max_matrix_error":error, "method":"actual SkinReference RenderingServer palette vs actual native bone global pose times inverse bind"}

func control_rects() -> Dictionary:
	var result := {}
	for key: String in _buttons: result[key] = (_buttons[key] as Button).get_global_rect()
	return result

func lighting_contract() -> Dictionary:
	# Actual scene readback, shared by both selected source models. This
	# records rear-reading conditions without changing lens, clay or rig.
	return {"key":{"color":key_light.light_color, "energy":key_light.light_energy, "transform":key_light.global_transform, "shadows":key_light.shadow_enabled}, "fill":{"color":fill_light.light_color, "energy":fill_light.light_energy, "transform":fill_light.global_transform, "shadows":fill_light.shadow_enabled}, "ambient":{"source":environment.ambient_light_source, "color":environment.ambient_light_color, "energy":environment.ambient_light_energy}, "background_color":environment.background_color, "tonemap_mode":environment.tonemap_mode, "exposure":environment.tonemap_exposure}

func manifest_contract() -> Dictionary:
	var rig: Dictionary = _manifest.get("rig", {})
	var names: Array = []
	for bone: Dictionary in rig.get("bones", []): names.append(String(bone.get("name", "")))
	var corrective_names: Array = []
	for group: Dictionary in rig.get("correctives", []):
		for title: String in group.get("keys", []):
			if title not in corrective_names: corrective_names.append(title)
	return {"declared_asset_sha256":_manifest.get("files", {}).get("resident_form_m01.glb", {}).get("sha256", ""), "bone_count":rig.get("bone_count", 0), "bone_names":names, "nla_track_names":rig.get("animation", {}).get("nla_track_names", []), "corrective_names":corrective_names, "declared_export_vertices":_manifest.get("export_surface_vertices", 0), "declared_export_faces":_manifest.get("export_surface_faces", 0), "declared_export_subdivision_level":_manifest.get("export_subdivision_level", -1), "scope":"Declared source contract, not a mesh-quality score. Import seam splits can differ from source vertex counts."}

func snapshot() -> Dictionary:
	var bones: Array = []; var links: Array = []; var blend_shapes: Array = []
	var clay_properties := {"roughness":clay.roughness, "albedo":clay.albedo_color, "vertex_color_use_as_albedo":clay.vertex_color_use_as_albedo, "has_albedo_texture":clay.albedo_texture != null, "has_normal_texture":clay.normal_texture != null}
	var visible := 0; var same_material := true; var source_materials_unchanged := true; var finite := true
	for mesh: MeshInstance3D in meshes:
		if mesh.is_visible_in_tree(): visible += 1
		same_material = same_material and mesh.material_override == clay
		for index: int in range(mesh.get_blend_shape_count()): blend_shapes.append({"mesh":str(mesh.name), "name":mesh.mesh.get_blend_shape_name(index), "value":mesh.get_blend_shape_value(index)})
	for row: Dictionary in _materials:
		var material: StandardMaterial3D = row.resource
		source_materials_unchanged = source_materials_unchanged and material.albedo_color == row.color and material.roughness == row.roughness and material.albedo_texture == row.texture
	if is_instance_valid(skeleton):
		for index: int in range(skeleton.get_bone_count()):
			var transform := _joint(index); finite = finite and transform.is_finite()
			bones.append({"name":skeleton.get_bone_name(index), "parent":skeleton.get_bone_parent(index), "rest_local":_rest_local[index], "source_rest_local":skeleton.get_bone_rest(index), "pose_local":skeleton.get_bone_pose(index), "actual_world":transform})
		for side: String in ["L", "R"]:
			for pair: Array in [["upper_arm", "forearm"], ["forearm", "hand"], ["thigh", "shin"], ["shin", "foot"]]:
				var first := _bone(pair[0], side); var second := _bone(pair[1], side)
				if first < 0 or second < 0: continue
				var rest := _rest_world[first].origin.distance_to(_rest_world[second].origin)
				var actual := _joint(first).origin.distance_to(_joint(second).origin)
				links.append({"side":side, "link":pair, "rest_m":rest, "actual_m":actual, "error_m":absf(actual-rest)})
	var joint_positions := {}
	for role: String in ["pelvis", "head"]:
		var index := _bone(role)
		if index >= 0: joint_positions[role] = _joint(index).origin
	for side: String in ["L", "R"]:
		for role: String in ["upper_arm", "forearm", "hand", "thigh", "shin", "foot"]:
			var index := _bone(role, side)
			if index >= 0: joint_positions[role+"."+side] = _joint(index).origin
	return {"loaded":loaded, "error":load_error, "model":selected_model, "pose":selected_pose, "view":selected_view, "asset_path":SOURCES.get(selected_model, ""), "asset_sha256":_source_sha, "manifest_path":MANIFESTS[selected_model], "manifest_sha256":_manifest_sha, "manifest_contract":manifest_contract(), "enabled_pose_controls":POSES.filter(func(pose: String) -> bool: return not (_buttons["pose_"+pose] as Button).disabled), "pose_application_ok":_pose_application_ok, "pose_strategy":_strategy, "actual_animation":_clip, "sample_time_s":SAMPLE_TIME_S, "imported_animation_names":animation_player.get_animation_list() if animation_player != null else [], "actual_mesh_count":meshes.size(), "visible_mesh_count":visible, "same_clay_material":same_material, "clay_properties":clay_properties, "source_materials_unchanged":source_materials_unchanged, "model_anchor_transform":model_anchor.transform, "rest_mesh_aabb_world":_rest_bounds, "rest_mesh_aabb_scope":"Imported native mesh AABB at load; not a CPU-skinned or corrective-morph posed-bound claim.", "finite_bones":finite, "bones":bones, "long_bone_links":links, "joints":joint_positions, "blend_shapes":blend_shapes, "camera_transform":camera.global_transform, "camera_fov":camera.fov, "camera_distance_m":camera.global_position.distance_to(Vector3(FRAMING[selected_pose].target)), "shared_pose_framing":FRAMING[selected_pose], "projected_frame":projected_frame(), "lighting_contract":lighting_contract(), "fixed_key_transform":key_light.global_transform, "fixed_key_shadow":key_light.shadow_enabled, "ruler_size_m":(ruler.mesh as BoxMesh).size, "automatic":automatic, "review_mode":review_mode, "scope":"Separate metre-scale clay review only. EXP36 compares the refinement with frozen v04 under identical per-pose camera/light/material, each using actual imported native NLA/morphs. No legacy52 retargeting or forced pose adapter. Numerical pose/visibility checks are not realistic anatomy, cloth simulation or art acceptance."}

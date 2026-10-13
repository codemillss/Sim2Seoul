extends Node3D
@export var world_config: Resource
var runtime_state: Dictionary = {}
var menu_open := false
var status_label: Label
var menu_panel: PanelContainer
var resume_button: Button
var elapsed := 0.0
var observed := false
var observe_prefix := ""
var auto_quit := false
var input_history: Array[Dictionary] = []
var last_input_state := ""
var selected_view := "overview"
var landmark_labels: Array[Dictionary] = []
var view_bar: HBoxContainer

@onready var input_router = $InputRouter

func _ready() -> void:
	runtime_state = world_config.read_runtime()
	input_router.menu_toggle_requested.connect(toggle_menu)
	_build_interface()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--observe-prefix="):
			observe_prefix = argument.trim_prefix("--observe-prefix=")
		elif argument.begins_with("--view="):
			selected_view = argument.trim_prefix("--view=")
		elif argument == "--auto-quit":
			auto_quit = true
	if not runtime_state.ok:
		input_router.gameplay_enabled = false
		status_label.text = "서울 시뮬레이션\n\n실행 자료를 확인해주세요\n%s" % runtime_state.error
		push_error(runtime_state.error)
		if auto_quit:
			get_tree().quit(1)
		return
	$World.populate(runtime_state.world)
	_build_map_labels()
	_set_view(selected_view)
	print("E03_READY local_contract=true meshes=%s triangles=%s renderer=%s driver=%s" % [$World.loaded_geometry_count,$World.triangle_count,RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])

func _build_interface() -> void:
	status_label = Label.new()
	var status_panel := PanelContainer.new()
	status_panel.position = Vector2(16,16)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.96,0.97,0.95,0.93)
	backdrop.content_margin_left = 12
	backdrop.content_margin_right = 12
	backdrop.content_margin_top = 10
	backdrop.content_margin_bottom = 10
	status_panel.add_theme_stylebox_override("panel",backdrop)
	$Interface.add_child(status_panel)
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color",Color(0.08,0.12,0.14))
	status_label.add_theme_color_override("font_shadow_color",Color(0.95,0.96,0.92))
	status_label.add_theme_constant_override("shadow_offset_x",1)
	status_label.add_theme_constant_override("shadow_offset_y",1)
	status_panel.add_child(status_label)
	view_bar = HBoxContainer.new()
	view_bar.position = Vector2(24,652)
	view_bar.add_theme_constant_override("separation",8)
	$Interface.add_child(view_bar)
	for item in [["overview","전체 배치"],["top","위에서 보기"],["palace","덕수궁 가까이"]]:
		var button := Button.new()
		button.text = item[1]
		button.pressed.connect(_set_view.bind(item[0]))
		view_bar.add_child(button)
	var attribution := Label.new()
	attribution.text = "지도 © OpenStreetMap contributors · ODbL"
	attribution.position = Vector2(826,690)
	attribution.add_theme_font_size_override("font_size",12)
	attribution.add_theme_color_override("font_color",Color(0.08,0.12,0.14))
	attribution.add_theme_color_override("font_outline_color",Color(0.97,0.98,0.96))
	attribution.add_theme_constant_override("outline_size",3)
	$Interface.add_child(attribution)
	menu_panel = PanelContainer.new()
	menu_panel.position = Vector2(380, 250)
	menu_panel.custom_minimum_size = Vector2(392, 220)
	menu_panel.visible = false
	$Interface.add_child(menu_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	menu_panel.add_child(content)
	var title := Label.new()
	title.text = "잠시 멈춤"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	resume_button = Button.new()
	resume_button.text = "돌아가기 · Esc"
	resume_button.pressed.connect(func(): set_menu_open(false))
	content.add_child(resume_button)
	var quit_button := Button.new()
	quit_button.text = "종료"
	quit_button.pressed.connect(_quit_project)
	content.add_child(quit_button)

func _process(delta: float) -> void:
	elapsed += delta
	if runtime_state.get("ok", false):
		var direction: Vector2 = input_router.movement_intent()
		var fast: bool = input_router.fast_intent()
		status_label.text = "서울 시뮬레이션 · 덕수궁과 시청\n실제 지도 배치 · 미터 축척\n임시 건물 외형·높이 / 지면·도로 폭 추정\n보기 선택은 아래 버튼 · 메뉴 Esc\n걷기와 문 통과는 다음 단계에서 준비합니다."
		_update_map_labels()
		var input_state := "%s/%s/%s" % [direction, fast, menu_open]
		if input_state != last_input_state:
			last_input_state = input_state
			input_history.append({"seconds":elapsed, "intent":[direction.x,direction.y],"fast":fast,"menu_open":menu_open})
			if input_history.size() > 1024:
				input_history.pop_front()
			print("E03_INPUT %s" % JSON.stringify(input_history.back()))
	if not observe_prefix.is_empty() and elapsed >= 12 and not observed:
		observed = true
		_observe_and_finish.call_deferred()

func toggle_menu() -> void:
	set_menu_open(not menu_open)

func _quit_project() -> void:
	var saved := true
	if not observe_prefix.is_empty():
		saved = await _record_observation()
	get_tree().quit(0 if saved else 1)

func _observe_and_finish() -> void:
	var saved: bool = await _record_observation()
	if auto_quit or not saved:
		get_tree().quit(0 if saved and runtime_state.get("ok",false) else 1)

func set_menu_open(value: bool) -> void:
	menu_open = value
	get_tree().paused = value
	input_router.gameplay_enabled = not value and runtime_state.get("ok", false)
	menu_panel.visible = value
	status_label.get_parent().visible = not value
	status_label.visible = not value
	view_bar.visible = not value
	_update_map_labels()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if value:
		resume_button.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()

func _record_observation() -> bool:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image_error := get_viewport().get_texture().get_image().save_png(observe_prefix + ".png")
		if image_error != OK:
			push_error("Cannot save E03 observation image")
			return false
	var record := {
		"task":"E03", "engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"display_server":DisplayServer.get_name(),
		"runtime_ok":runtime_state.get("ok",false),
		"loaded_geometry_count":$World.loaded_geometry_count, "loaded_triangles":$World.triangle_count, "view":selected_view, "world_counts":runtime_state.get("world",{}).get("counts",{}), "elapsed_seconds":elapsed,
		"input_history":input_history,
		"region":runtime_state.get("region",{}),
		"scope":"local city display only; no collision, walking, physical position/height accuracy or performance acceptance"
	}
	var file := FileAccess.open(observe_prefix + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save E03 observation record")
		return false
	file.store_string(JSON.stringify(record,"\t") + "\n")
	print("E03_OBSERVED local_contract=%s" % runtime_state.get("ok",false))
	return true

func _set_view(key: String) -> void:
	if not runtime_state.get("ok",false) or not runtime_state.world.display.views.has(key):
		return
	selected_view = key
	var view: Dictionary = runtime_state.world.display.views[key]
	var camera: Camera3D = $Presentation/OverviewCamera
	camera.position = Vector3(view.position[0],view.position[1],view.position[2])
	var target := Vector3(view.target[0],view.target[1],view.target[2])
	camera.look_at(target,Vector3(0,0,-1) if key == "top" else Vector3.UP)
	camera.size = view.size_m
	_update_map_labels()

func _build_map_labels() -> void:
	var anchors: Array = runtime_state.world.landmarks.duplicate()
	anchors.append({"name":"원점", "position":[0,1,0]})
	anchors.append({"name":"N · 북쪽", "position":[0,1,-35]})
	for anchor in anchors:
		var label := Label.new()
		label.text = anchor.name
		label.add_theme_font_size_override("font_size",14)
		label.add_theme_color_override("font_color",Color(0.06,0.09,0.12))
		label.add_theme_color_override("font_outline_color",Color(0.95,0.97,0.94))
		label.add_theme_constant_override("outline_size",5)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Interface.add_child(label)
		landmark_labels.append({"label":label,"position":Vector3(anchor.position[0],anchor.position[1],anchor.position[2])})
	# These are labelled display aids, never source buildings/collision/spawn.
	for axis in [Vector3(20,0.1,0),Vector3(0,0.1,-35)]:
		var line := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(abs(axis.x)+0.7,0.3,abs(axis.z)+0.7)
		line.mesh = shape
		line.position = axis/2
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.95,0.78,0.29)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.material_override = material
		$Presentation.add_child(line)

func _update_map_labels() -> void:
	var camera: Camera3D = $Presentation/OverviewCamera
	for item in landmark_labels:
		var point: Vector2 = camera.unproject_position(item.position)
		var label: Label = item.label
		label.visible = not menu_open and not camera.is_position_behind(item.position) and Rect2(12,12,1128,608).has_point(point) and not Rect2(16,16,420,148).has_point(point)
		label.position = point - Vector2(label.size.x/2,16)
		if label.text == "원점": label.position += Vector2(-30,18)
		elif label.text == "N · 북쪽": label.position += Vector2(-20,-8)
		elif label.text == "대한문": label.position += Vector2(22,10)

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

@onready var input_router = $InputRouter

func _ready() -> void:
	runtime_state = world_config.read_runtime()
	input_router.menu_toggle_requested.connect(toggle_menu)
	_build_interface()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--observe-prefix="):
			observe_prefix = argument.trim_prefix("--observe-prefix=")
		elif argument == "--auto-quit":
			auto_quit = true
	if not runtime_state.ok:
		input_router.gameplay_enabled = false
		status_label.text = "서울 시뮬레이션\n\n실행 자료를 확인해주세요\n%s" % runtime_state.error
		push_error(runtime_state.error)
		if auto_quit:
			get_tree().quit(1)
		return
	print("E02_READY local_contract=true assets=0 renderer=%s driver=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])

func _build_interface() -> void:
	status_label = Label.new()
	status_label.position = Vector2(40, 40)
	status_label.add_theme_font_size_override("font_size", 22)
	$Interface.add_child(status_label)
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
		status_label.text = "서울 시뮬레이션\n덕수궁 · 시청\n\n프로젝트 준비 완료\n서울 지도는 다음 단계에서 표시됩니다.\n\n입력 확인: WASD / 방향키 · Shift\n메뉴: Esc\n입력 방향: (%.2f, %.2f) · 빠른 이동 요청: %s\n캐릭터 이동은 아직 준비 중입니다." % [direction.x, direction.y, "켜짐" if fast else "꺼짐"]
		var input_state := "%s/%s/%s" % [direction, fast, menu_open]
		if input_state != last_input_state:
			last_input_state = input_state
			input_history.append({"seconds":elapsed, "intent":[direction.x,direction.y],"fast":fast,"menu_open":menu_open})
			if input_history.size() > 1024:
				input_history.pop_front()
			print("E02_INPUT %s" % JSON.stringify(input_history.back()))
	if not observe_prefix.is_empty() and elapsed >= 12 and not observed:
		observed = true
		_record_observation.call_deferred()

func toggle_menu() -> void:
	set_menu_open(not menu_open)

func _quit_project() -> void:
	if not observe_prefix.is_empty():
		await _record_observation()
	get_tree().quit()

func set_menu_open(value: bool) -> void:
	menu_open = value
	get_tree().paused = value
	input_router.gameplay_enabled = not value and runtime_state.get("ok", false)
	menu_panel.visible = value
	status_label.visible = not value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if value:
		resume_button.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()

func _record_observation() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image_error := get_viewport().get_texture().get_image().save_png(observe_prefix + ".png")
		if image_error != OK:
			push_error("Cannot save E02 observation image")
			get_tree().quit(1)
			return
	var record := {
		"task":"E02", "engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"display_server":DisplayServer.get_name(),
		"runtime_ok":runtime_state.get("ok",false),
		"loaded_geometry_count":0, "elapsed_seconds":elapsed,
		"input_history":input_history,
		"region":runtime_state.get("region",{}),
		"scope":"project structure and input intent only; no city movement or scale acceptance"
	}
	var file := FileAccess.open(observe_prefix + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot save E02 observation record")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(record,"\t") + "\n")
	print("E02_OBSERVED local_contract=%s" % runtime_state.get("ok",false))
	if auto_quit:
		get_tree().quit(0 if runtime_state.get("ok",false) else 1)

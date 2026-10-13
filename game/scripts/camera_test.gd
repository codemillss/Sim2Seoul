extends "res://scripts/movement_test.gd"
## P03 camera in the synthetic P02 arena only.
@onready var rig: Node3D = $Presentation/CameraRig
var automatic_probe := false

func _ready() -> void:
	automatic_probe = "--automatic-probe" in OS.get_cmdline_user_args()
	_build_guides()
	_add_movement_fixtures()
	_solid_box("CornerReturn",Vector3(0.25,3,3),Vector3(-8.5,1.5,-5.5),Color(0.46,0.57,0.62))
	_build_ui()
	player.configure_recovery(START,TEST_REGIONS)
	input_router.menu_toggle_requested.connect(toggle_menu)
	$Presentation/Camera.current = false
	camera = rig.camera
	camera.make_current()
	view_key = "third_person"
	rig.set_capture(true)
	print("P03_READY camera=third_person mouse=orbit obstruction=sphere_sweep")

func set_view(_key: String) -> void:
	view_key = "third_person"
	camera = rig.camera
	camera.make_current()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98,0.99,0.98,0.94)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	$Interface.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var text := Label.new()
	text.text = "P03 · 3인칭 걷기와 카메라 시험\nWASD / 방향키 · Shift 달리기\n마우스 회전 · 휠 거리 · Esc 메뉴/마우스 해제\n단차는 녹색 램프로 진입 · 서울 적용은 다음 단계"
	text.add_theme_font_size_override("font_size",16)
	text.add_theme_color_override("font_color",Color(0.10,0.16,0.21))
	column.add_child(text)
	status = Label.new()
	status.add_theme_font_size_override("font_size",14)
	status.add_theme_color_override("font_color",Color(0.10,0.16,0.21))
	column.add_child(status)
	menu = PanelContainer.new()
	menu.position = Vector2(380,265)
	menu.visible = false
	$Interface.add_child(menu)
	var options := VBoxContainer.new()
	menu.add_child(options)
	var help := Label.new()
	help.text = "일시 정지 · 이동키를 놓고 다시 시작하세요"
	options.add_child(help)
	for title in ["돌아가기 · Esc","시작점으로 복귀","시험 장면 종료"]:
		var button := Button.new()
		button.text = title
		if title.begins_with("돌아가기"):button.pressed.connect(toggle_menu)
		elif title.begins_with("시작점"):
			reset_button = button
			button.pressed.connect(reset_player)
		else:button.pressed.connect(func():Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;get_tree().quit())
		options.add_child(button)

func toggle_menu() -> void:
	super.toggle_menu()
	rig.set_capture(not menu.visible)
	if not menu.visible:get_viewport().gui_release_focus()

func focus_changed(focused: bool) -> void:
	if not focused and not menu.visible:toggle_menu()
	# Regaining focus deliberately keeps the menu open until Esc/Return.

func _notification(what: int) -> void:
	if not is_node_ready():return
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and not automatic_probe:focus_changed(false)
	elif what==NOTIFICATION_EXIT_TREE:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	status.text = "속도 %.2fm/s · 카메라 %.2fm%s"%[Vector2(player.velocity.x,player.velocity.z).length(),rig.current_distance," · 이동키를 놓아주세요" if player.input_latched else ""]
	for item in labels:item.label.visible = false

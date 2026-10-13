extends "res://scripts/camera_test.gd"
## Separate fixture and city-inspection modes; no city walkability acceptance.
var mode := "fixture"
var runtime_state: Dictionary={}
var ui_help: Label
@onready var city: Node3D=$City
@onready var city_camera: Camera3D=$Presentation/CityCamera

func _ready() -> void:
	super._ready()
	_solid_box("BuildingProxy",Vector3(3,4,3),Vector3(8,2,6),Color(0.47,0.60,0.72))
	for body in $Fixtures.get_children():body.collision_mask=14
	player.collision_mask=13
	var config: Resource=load("res://resources/world_config.tres")
	runtime_state=config.read_runtime()
	if runtime_state.ok:
		if not city.load_collision(runtime_state.world):runtime_state={"ok":false,"error":city.collision_error}
	if not runtime_state.ok:
		input_router.gameplay_enabled=false
		rig.set_capture(false)
		push_error(runtime_state.error)
		ui_help.text="서울 충돌 자료를 준비해주세요\n"+runtime_state.error
		return
	city.set_collision_enabled(false)
	for id in city.bodies:
		var tint:=StandardMaterial3D.new()
		tint.albedo_color=Color(0.28,0.56,0.65) if id!="temporary_support" else Color(0.80,0.85,0.86)
		city.source_nodes[id].material_override=tint
	print("P04_READY fixture=14 city_static=685 excluded_display=548 gates=W01_pending")

func _build_ui() -> void:
	super._build_ui()
	ui_help=status.get_parent().get_child(0)
	ui_help.text="P04 · 충돌 시험장\nWASD / 방향키 · Shift 달리기\n마우스 회전 · 휠 거리 · Esc 메뉴\n메뉴에서 서울 충돌 배치 보기로 전환"
	var options: VBoxContainer=menu.get_child(0)
	for entry in [["fixture","시험장으로 돌아가기"],["city","서울 충돌 배치 보기"],["city_palace","덕수궁 충돌 가까이 보기"]]:
		var button:=Button.new()
		button.text=entry[1]
		button.pressed.connect(func():set_mode(entry[0]);if menu.visible:toggle_menu())
		options.add_child(button)
	var attribution:=Label.new()
	attribution.text="지도 © OpenStreetMap contributors · ODbL"
	attribution.position=Vector2(822,690)
	attribution.add_theme_font_size_override("font_size",12)
	attribution.add_theme_color_override("font_color",Color(0.08,0.12,0.14))
	$Interface.add_child(attribution)

func set_mode(key: String) -> void:
	if not runtime_state.get("ok",false):return
	mode="fixture" if key=="fixture" else "city"
	var fixture_mode:=mode=="fixture"
	for body in $Fixtures.get_children():
		body.collision_layer=1 if fixture_mode else 0
		body.collision_mask=14 if fixture_mode else 0
	$Fixtures.visible=fixture_mode
	$Guides.visible=fixture_mode
	city.visible=not fixture_mode
	city.set_collision_enabled(not fixture_mode)
	player.visible=fixture_mode
	player.set_physics_process(fixture_mode)
	rig.set_physics_process(fixture_mode)
	rig.arm.set_physics_process(fixture_mode)
	input_router.gameplay_enabled=fixture_mode and not menu.visible
	if fixture_mode:
		player.configure_recovery(START,TEST_REGIONS)
		player.global_transform=Transform3D(Basis.IDENTITY,START)
		player.spawn_valid=false
		player.require_neutral_input()
		rig.reset_orientation()
		camera=rig.camera
		camera.make_current()
		rig.set_capture(not menu.visible)
		ui_help.text="P04 · 충돌 시험장\nWASD / 방향키 · Shift 달리기\n마우스 회전 · 휠 거리 · Esc 메뉴\n메뉴에서 서울 충돌 배치 보기로 전환"
	else:
		var view: Dictionary=runtime_state.world.display.views["palace" if key=="city_palace" else "overview"]
		city_camera.position=Vector3(view.position[0],view.position[1],view.position[2])
		city_camera.look_at(Vector3(view.target[0],view.target[1],view.target[2]))
		city_camera.size=view.size_m
		city_camera.make_current()
		rig.set_capture(false)
		ui_help.text="P04 · 서울 충돌 배치 확인\n청록색 건물·담장에 정적 충돌 연결\n길·토지 색은 보기용 / 지면은 임시 평면\n대한문 개구부·실제 보행은 다음 단계 · Esc 메뉴"

func toggle_menu() -> void:
	super.toggle_menu()
	if mode=="city":
		input_router.gameplay_enabled=false
		rig.set_capture(false)

func reset_player() -> void:
	if mode=="fixture":super.reset_player()

func _process(delta: float) -> void:
	if mode=="fixture":super._process(delta)
	else:status.text="충돌 685개 · 보기용 548개 · 실제 보행은 미검증"

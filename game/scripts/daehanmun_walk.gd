extends "res://scripts/camera_test.gd"
## Actual source placement, limited Daehanmun entrance walk; W02–W04 remain pending.
@onready var city: Node3D=$World
var runtime_ok := false
var starting_yaw := 0.0
var prior_recoveries := 0
func _ready() -> void:
	automatic_probe="--automatic-probe" in OS.get_cmdline_user_args()
	for body in $Fixtures.get_children():body.free()
	_build_ui()
	input_router.gameplay_enabled=false
	input_router.menu_toggle_requested.connect(toggle_menu)
	var config: Resource=load("res://resources/world_config.tres")
	var data: Dictionary=config.read_runtime()
	if not data.ok or not city.load_connection(data.world):
		status.text="대한문 자료를 준비해주세요."
		rig.set_capture(false)
		push_error(data.error if not data.ok else city.walk_error)
		return
	player.collision_layer=2
	player.collision_mask=13
	var s: Array=city.connection.spawn
	var point:=Vector3(s[0],s[1],s[2])
	var regions: Array[Rect2]=[]
	player.configure_recovery(point,regions)
	player.global_position=point
	player.require_neutral_input()
	var u: Array=city.connection.direction_xz
	starting_yaw=atan2(-u[0],-u[1])
	rig.yaw=starting_yaw
	rig.global_position=point+Vector3.UP*rig.pivot_height_m
	rig.rotation=Vector3(rig.pitch,starting_yaw,0)
	$Presentation/Camera.current=false
	camera=rig.camera
	camera.make_current()
	view_key="third_person"
	player.physics_stepped.connect(_recovery_heading)
	runtime_ok=true
	input_router.gameplay_enabled=true
	rig.set_capture(true)
	var attribution:=Label.new()
	attribution.text="지도 © OpenStreetMap contributors · ODbL"
	attribution.position=Vector2(822,690)
	attribution.add_theme_font_size_override("font_size",12)
	$Interface.add_child(attribution)
	print("W01_READY active=687 source_path=65.608m opening=3x3m_engineering_assumption")
func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="대한문 앞 ↔ 덕수궁 입구\nWASD / 방향키 · Shift 달리기\n마우스 회전 · 휠 거리 · Esc 메뉴\n밝은 길을 따라 문을 통과하세요 · 문 폭과 지면은 임시 표현"
	reset_button.text="대한문 밖으로 복귀"
func reset_player() -> void:
	if runtime_ok:player.recover("manual_restart")
func toggle_menu() -> void:
	super.toggle_menu()
	if not runtime_ok:
		input_router.gameplay_enabled=false
		rig.set_capture(false)
func _process(_delta: float) -> void:
	if not runtime_ok:return
	var inside: Array=city.connection.route_xz[2]
	var u: Array=city.connection.direction_xz
	var depth: float=(player.position.x-inside[0])*u[0]+(player.position.z-inside[1])*u[1]
	var place: String="경내 입구" if depth>0.5 else "대한문 통과 중" if depth> -city.connection.passage_length_m else "대한문 밖"
	status.text="%s · 속도 %.2fm/s%s"%[place,Vector2(player.velocity.x,player.velocity.z).length()," · 이동키를 놓아주세요" if player.input_latched else ""]

func _recovery_heading(_delta: float) -> void:
	if player.recoveries!=prior_recoveries:
		prior_recoveries=player.recoveries
		rig.yaw=starting_yaw
		rig.rotation=Vector3(rig.pitch,starting_yaw,0)

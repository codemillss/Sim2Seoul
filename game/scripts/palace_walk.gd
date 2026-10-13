extends "res://scripts/daehanmun_walk.gd"
## W02 playable local palace loop and courtyard, with original layout/units preserved.
func _ready() -> void:
	automatic_probe="--automatic-probe" in OS.get_cmdline_user_args()
	for body in $Fixtures.get_children():body.free()
	_build_ui()
	input_router.gameplay_enabled=false
	input_router.menu_toggle_requested.connect(toggle_menu)
	var config: Resource=load("res://resources/world_config.tres")
	var data: Dictionary=config.read_runtime()
	if not data.ok or not city.load_connection(data.world):
		status.text="경내 자료를 준비해주세요."
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
	for c in city.palace.checkpoints:
		var label:=Label3D.new()
		label.name="Checkpoint"
		label.text=c.name
		label.position=Vector3(c.xz[0],2.8,c.xz[1])
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size=40
		label.pixel_size=0.015
		label.modulate=Color(0.95,0.88,0.5)
		$Presentation.add_child(label)
	var attribution:=Label.new()
	attribution.text="지도 © OpenStreetMap contributors · ODbL"
	attribution.position=Vector2(822,690)
	attribution.add_theme_font_size_override("font_size",12)
	$Interface.add_child(attribution)
	print("W02_READY active=%d loop=%.3fm courtyard=%.3fm flat_support_assumption"%[city.palace.counts.active_bodies,city.palace.routes[1].length_m,city.palace.routes[2].length_m])

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="덕수궁 경내 순환 · 중화전 앞마당 · 석조전 계단 아래\nWASD / 방향키 · Shift 달리기 · 마우스 회전 / 휠 거리\n표식을 따라 둘러보세요 · Esc 메뉴 / 대한문 밖으로 복귀\n지면은 임시 평면 · 잔디 / 기단 / 계단 / 실내는 제외"

func _process(_delta: float) -> void:
	if not runtime_ok:return
	var closest: Dictionary=city.palace.checkpoints[0]
	var distance:=INF
	var p:=Vector2(player.position.x,player.position.z)
	for c in city.palace.checkpoints:
		var next:=p.distance_to(Vector2(c.xz[0],c.xz[1]))
		if next<distance:distance=next;closest=c
	status.text="%s 부근 · 속도 %.2fm/s%s"%[closest.name,Vector2(player.velocity.x,player.velocity.z).length()," · 이동키를 놓아주세요" if player.input_latched else ""]

extends "res://scripts/palace_walk.gd"
## W03 connected palace, city/plaza and wall paths; visual guides have no collision.
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
		label.font_size=28
		label.pixel_size=0.005
		label.modulate=Color(0.95,0.88,0.5)
		$Presentation.add_child(label)
	var attribution:=Label.new()
	attribution.text="지도 © OpenStreetMap contributors · ODbL"
	attribution.position=Vector2(822,690)
	attribution.add_theme_font_size_override("font_size",12)
	$Interface.add_child(attribution)
	_build_boundary_guide()
	print("W03_READY active=%d city=%.3fm wall=%.3fm boundary=%s"%[city.public_data.counts.active_bodies,city.public_data.routes[3].length_m,city.public_data.routes[4].length_m,city.boundary_resource.contract_id])

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="덕수궁 · 서울광장 / 시청 전면 · 돌담길\nWASD / 방향키 · Shift 달리기 · 마우스 회전 / 휠 거리\n표식 / 밝은 경계선 안에서 이동 · Esc 메뉴 / 문 밖으로 복귀\n길 밖 / 잔디 / 실내 제외 · 실제 공사 통로와 다를 수 있음"

func _process(_delta: float) -> void:
	if not runtime_ok:return
	var closest: Dictionary=city.palace.checkpoints[0]
	var distance:=INF
	var p:=Vector2(player.position.x,player.position.z)
	for c in city.palace.checkpoints:
		var next:=p.distance_to(Vector2(c.xz[0],c.xz[1]))
		if next<distance:distance=next;closest=c
	status.text="%s 부근 · 속도 %.2fm/s%s"%[closest.name,Vector2(player.velocity.x,player.velocity.z).length()," · 이동키를 놓아주세요" if player.input_latched else ""]

	var junction: String=city.crossing_at(p)
	if not junction.is_empty():status.text+=" · 도로 접속부 (현재 차량 없음)"
	elif not player.last_boundary_reason.is_empty():status.text+=" · 보행 범위 끝"

func _build_boundary_guide() -> void:
	var vertices:=PackedVector3Array()
	for poly in city.public_data.movement_rings:
		for ring in poly:
			for i in range(ring.size()-1):
				var a:=Vector3(ring[i][0],.08,ring[i][1])
				var b:=Vector3(ring[i+1][0],.08,ring[i+1][1])
				if a.distance_to(b)<.00001:continue
				var n: Vector3=(b-a).normalized().cross(Vector3.UP)*.025
				vertices.append_array(PackedVector3Array([a-n,b+n,b-n,a-n,a+n,b+n]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var guide:=MeshInstance3D.new();guide.name="BoundaryGuide";guide.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.95,.75,.3)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	guide.material_override=material;guide.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Presentation.add_child(guide)

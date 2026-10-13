extends "res://scripts/player_fixture.gd"
## P02 authored fixture; no city geometry, permissions or geographic boundary.
@onready var input_router: Node = $InputRouter
var reset_button: Button
const TEST_REGIONS: Array[Rect2] = [Rect2(-11.5,-9.5,23,19),Rect2(-3.5,9,7,3),Rect2(-39.5,10,79,39.5)]

func _ready() -> void:
	_build_guides()
	_add_movement_fixtures()
	_build_ui()
	player.configure_recovery(START,TEST_REGIONS)
	input_router.menu_toggle_requested.connect(toggle_menu)
	set_view("overview")
	print("P02_READY synthetic_fixture walk=1.4m/s run=3.5m/s camera=fixed")

func _solid_box(title: String, size: Vector3, point: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = title
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = point
	$Fixtures.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_box(body,"Visual",size,Vector3.ZERO,color)

func _ramp(title: String, x0: float, x1: float, z0: float, z1: float, low: float, high: float) -> void:
	# Explicit temporary entry ramp, not automatic stair climbing or real terrain.
	var bottom := low-0.1
	var points := PackedVector3Array([Vector3(x0,bottom,z0),Vector3(x1,bottom,z0),Vector3(x1,bottom,z1),Vector3(x0,bottom,z1),
		Vector3(x0,low,z0),Vector3(x1,high,z0),Vector3(x1,high,z1),Vector3(x0,low,z1)])
	var body := StaticBody3D.new()
	body.name = title
	body.collision_layer = 1
	body.collision_mask = 2
	$Fixtures.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in [[4,7,6],[4,6,5],[0,1,2],[0,2,3],[0,4,5],[0,5,1],[1,5,6],[1,6,2],[2,6,7],[2,7,3],[3,7,4],[3,4,0]]:
		var normal: Vector3 = (points[face[1]]-points[face[0]]).cross(points[face[2]]-points[face[0]]).normalized()
		for index in face:
			vertices.append(points[index])
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24,0.57,0.48)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = material
	body.add_child(visual)

func _add_movement_fixtures() -> void:
	_solid_box("DistanceFloor",Vector3(80,0.2,40),Vector3(0,-0.1,30),Color(0.79,0.85,0.85))
	_ramp("StepEntry015",2,3,1,3,0,0.15)
	_ramp("StepEntry030",4,5,1,3,0.15,0.30)
	_ramp("Slope",-9,-5,-2,0,0,1)
	_solid_box("SlopeLanding",Vector3(2,1,2),Vector3(-4,0.5,-1),Color(0.24,0.57,0.48))
	# Decorative forward marker rotates with Visual only; capsule remains unchanged.
	var marker := MeshInstance3D.new()
	marker.name = "ForwardMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	marker.mesh = sphere
	marker.position = Vector3(0,1.15,-0.30)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08,0.20,0.48)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	$Actors/Player/Visual.add_child(marker)
	for x in range(-35,36,5):
		_box($Guides,"DistanceGridX_%s"%x,Vector3(0.025,0.002,40),Vector3(x,0.002,30),Color(0.55,0.64,0.67))
	for z in range(10,51,5):
		_box($Guides,"DistanceGridZ_%s"%z,Vector3(80,0.002,0.025),Vector3(0,0.002,z),Color(0.55,0.64,0.67))
	_label("단차 진입 램프 · 시험용",$Fixtures/StepEntry015,Vector3(2,0.5,3))
	_label("경사 1:4 · 시험용",$Fixtures/Slope,Vector3(-8,1,-1))

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
	text.text = "P02 · 걷기와 달리기 시험\nWASD / 방향키 · Shift 달리기 · Esc 메뉴\n걷기 1.4m/s · 달리기 3.5m/s · 파란 점이 정면\n단차는 녹색 램프로 진입 · 시점 조작은 다음 단계"
	text.add_theme_font_size_override("font_size",16)
	text.add_theme_color_override("font_color",Color(0.10,0.16,0.21))
	column.add_child(text)
	status = Label.new()
	status.add_theme_font_size_override("font_size",14)
	status.add_theme_color_override("font_color",Color(0.10,0.16,0.21))
	column.add_child(status)
	var bar := HBoxContainer.new()
	bar.position = Vector2(24,650)
	bar.add_theme_constant_override("separation",8)
	$Interface.add_child(bar)
	for key in ["overview","person","door","distance"]:
		var button := Button.new()
		button.text = "거리 시험 구간" if key=="distance" else VIEWS[key].title
		button.pressed.connect(set_view.bind(key))
		bar.add_child(button)
	reset_button = Button.new()
	reset_button.text = "시작점으로 복귀"
	reset_button.pressed.connect(reset_player)
	bar.add_child(reset_button)
	var menu_button := Button.new()
	menu_button.text = "메뉴 · Esc"
	menu_button.pressed.connect(toggle_menu)
	bar.add_child(menu_button)
	menu = PanelContainer.new()
	menu.position = Vector2(440,280)
	menu.visible = false
	$Interface.add_child(menu)
	var options := VBoxContainer.new()
	menu.add_child(options)
	for title in ["일시 정지 · 이동 입력을 놓은 뒤 다시 시작","돌아가기 · Esc","시험 장면 종료"]:
		if title.begins_with("일시"):
			var label := Label.new()
			label.text = title
			options.add_child(label)
		else:
			var button := Button.new()
			button.text = title
			if title.begins_with("돌아가기"):button.pressed.connect(toggle_menu)
			else:button.pressed.connect(func():get_tree().quit())
			options.add_child(button)

func set_view(key: String) -> void:
	if key=="distance":
		view_key = key
		camera.position = Vector3(0,60,20)
		camera.look_at(Vector3(0,0,20),Vector3(0,0,-1))
		camera.size = 64
	else:super.set_view(key)

func reset_player() -> void:
	player.recover("manual_restart")

func toggle_menu() -> void:
	menu.visible = not menu.visible
	input_router.gameplay_enabled = not menu.visible
	player.require_neutral_input()
	get_tree().paused = menu.visible

func _unhandled_input(_event: InputEvent) -> void:
	# InputRouter owns Esc; do not dispatch it twice through the P01 parent.
	pass

func _process(delta: float) -> void:
	super._process(delta)
	status.text = "지면: %s · 속도 %.2fm/s · 복귀 %d회%s"%["접촉" if player.is_on_floor() else "공중",Vector2(player.velocity.x,player.velocity.z).length(),player.recoveries," · 이동 입력을 놓아주세요" if player.input_latched else ""]
	if view_key=="distance":status.text += " · 큰 격자 5m"

func movement_contract() -> Dictionary:
	var collision: CollisionShape3D = $Actors/Player/CollisionShape
	return {"walk_mps":player.walk_speed_mps,"run_mps":player.run_speed_mps,"gravity_mps2":player.gravity_mps2,
		"turn_radians_per_second":player.turn_speed_radians,"height":collision.shape.height,"radius":collision.shape.radius,
		"layer":player.collision_layer,"mask":player.collision_mask,"spawn":_vector(player.spawn_transform.origin),
		"spawn_valid":player.spawn_valid,"physics_hz":Engine.physics_ticks_per_second,
		"camera_fixed":true,"ramp_substitution":true,"static_count":$Fixtures.get_child_count(),
		"distance_floor_size":_vector($Fixtures/DistanceFloor/CollisionShape.shape.size)}

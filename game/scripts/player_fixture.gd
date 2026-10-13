extends Node3D
## Authored synthetic metre fixture. No map import or horizontal movement.
@onready var player: CharacterBody3D = $Actors/Player
@onready var camera: Camera3D = $Presentation/Camera
const START := Vector3(-2,0.08,2)
const VIEWS := {
	"overview":{"position":Vector3(15,13,18),"target":Vector3(0,0.8,-1),"size":17.0,"title":"전체 시험장"},
	"person":{"position":Vector3(-2,2.0,8),"target":Vector3(-2,0.9,2),"size":3.5,"title":"사람 크기"},
	"door":{"position":Vector3(0,2.7,6),"target":Vector3(0,1.3,-4),"size":5.2,"title":"시험문"}}
var view_key := "overview"
var menu: PanelContainer
var labels: Array[Dictionary] = []
var ruler: MeshInstance3D
var height_bar: MeshInstance3D
var status: Label

func _ready() -> void:
	_build_guides()
	_build_ui()
	set_view("overview")
	print("P01_READY synthetic_fixture player=1.7m radius=0.3m horizontal_movement=false")

func _box(parent: Node3D, title: String, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.position = point
	parent.add_child(node)
	return node

func _label(text: String, node: Node3D, point: Vector3, filter := "overview") -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Color(0.10,0.16,0.21))
	label.add_theme_color_override("font_outline_color",Color(1,1,1))
	label.add_theme_constant_override("outline_size",5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Interface.add_child(label)
	labels.append({"label":label,"node":node,"point":point,"filter":filter})

func _build_guides() -> void:
	for x in range(-12,13):
		_box($Guides,"GridX_%s" % x,Vector3(0.012,0.002,20),Vector3(x,0.002,0),Color(0.61,0.67,0.69))
	for z in range(-10,11):
		_box($Guides,"GridZ_%s" % z,Vector3(24,0.002,0.012),Vector3(0,0.002,z),Color(0.61,0.67,0.69))
	ruler = _box($Guides,"Ruler10m",Vector3(10,0.025,0.05),Vector3(0,0.03,6),Color(0.12,0.36,0.58))
	for x in range(-5,6):
		_box($Guides,"RulerTick_%s" % x,Vector3(0.025,0.025,0.25),Vector3(x,0.03,6),Color(0.12,0.36,0.58))
	_label("10m · 1칸=1m",ruler,Vector3(0,0,0.5))
	height_bar = _box($Guides,"Height2m",Vector3(0.03,2,0.03),Vector3(-1.2,1,2),Color(0.12,0.36,0.58))
	for y in [0.0,1.0,1.7,2.0]:
		_box($Guides,"HeightTick_%s" % y,Vector3(0.20,0.02,0.03),Vector3(-1.2,y,2),Color(0.12,0.36,0.58))
	_label("2m 기준물",height_bar,Vector3(0.2,0.75,0),"person")
	_label("1.70m 임시 캐릭터",player,Vector3(-0.7,1.85,0),"person")
	_label("시험문 · 폭 1.20m / 높이 2.20m",$Fixtures/DoorLintel,Vector3(-1,0.6,0),"door")
	_label("시험문",$Fixtures/DoorLintel,Vector3(-0.5,0.6,0))
	_label("벽 · 3m",$Fixtures/Wall,Vector3(-0.5,1.6,0))
	_label("0.15m",$Fixtures/Step015,Vector3(-0.3,0.3,0))
	_label("0.30m",$Fixtures/Step030,Vector3(-0.3,0.4,0))
	_label("사람 · 1.70m",player,Vector3(-0.5,1.85,0))

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98,0.99,0.98,0.95)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	$Interface.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var text := Label.new()
	text.text = "P01 · 사람 크기와 정지 시험\n키 1.70m · 폭 0.60m · 합성 시험장\n걷기와 카메라 조작은 다음 단계에서 연결합니다."
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
	for key in VIEWS:
		var button := Button.new()
		button.text = VIEWS[key].title
		button.pressed.connect(set_view.bind(key))
		bar.add_child(button)
	var reset := Button.new()
	reset.text = "다시 놓기"
	reset.pressed.connect(reset_player)
	bar.add_child(reset)
	var menu_button := Button.new()
	menu_button.text = "메뉴 · Esc"
	menu_button.pressed.connect(toggle_menu)
	bar.add_child(menu_button)
	menu = PanelContainer.new()
	menu.position = Vector2(470,280)
	menu.visible = false
	$Interface.add_child(menu)
	var options := VBoxContainer.new()
	menu.add_child(options)
	for title in ["돌아가기 · Esc","시험 장면 종료"]:
		var button := Button.new()
		button.text = title
		if title.begins_with("돌아가기"):button.pressed.connect(toggle_menu)
		else:button.pressed.connect(func():get_tree().quit())
		options.add_child(button)

func set_view(key: String) -> void:
	view_key = key
	camera.position = VIEWS[key].position
	camera.look_at(VIEWS[key].target,Vector3.UP)
	camera.size = VIEWS[key].size

func reset_player() -> void:
	# Manual fixture placement only, not P02 fall/boundary recovery.
	player.position = START
	player.velocity = Vector3.ZERO

func toggle_menu() -> void:
	menu.visible = not menu.visible
	get_tree().paused = menu.visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu") and not event.is_echo():
		toggle_menu()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	status.text = "지면 접촉: %s · 바닥 1칸=1m" % ["확인" if player.is_on_floor() else "정착 중"]
	if view_key=="door":status.text += " · 문 1.20 × 2.20m"
	for item in labels:
		var point: Vector3 = item.node.to_global(item.point)
		var pixel := camera.unproject_position(point)
		item.label.visible = item.filter==view_key and not menu.visible and not camera.is_position_behind(point) and pixel.x>8 and pixel.x<1060 and pixel.y>150 and pixel.y<620
		item.label.position = pixel

func _vector(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _transform(node: Node3D) -> Dictionary:
	var t := node.global_transform
	return {"origin":_vector(t.origin),"basis":[_vector(t.basis.x),_vector(t.basis.y),_vector(t.basis.z)]}

func _bounds(mesh: MeshInstance3D) -> Dictionary:
	var lo := Vector3(INF,INF,INF)
	var hi := Vector3(-INF,-INF,-INF)
	var count := 0
	for surface in range(mesh.mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var world := mesh.to_global(vertex)
			lo = lo.min(world)
			hi = hi.max(world)
			count += 1
	return {"min":_vector(lo),"max":_vector(hi),"size":_vector(hi-lo),"vertices":count,"transform":_transform(mesh)}

func _overlap(feet: Vector3) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = $Actors/Player/CollisionShape.shape
	query.transform = Transform3D(player.global_basis,feet+player.global_basis*$Actors/Player/CollisionShape.position)
	query.collision_mask = 1
	var names := []
	for hit in get_world_3d().direct_space_state.intersect_shape(query,16):names.append(String(hit.collider.name))
	names.sort()
	return names

func measure() -> Dictionary:
	var collision: CollisionShape3D = $Actors/Player/CollisionShape
	var fixtures := []
	for body in $Fixtures.get_children():
		var shape: CollisionShape3D = body.get_node("CollisionShape")
		fixtures.append({"name":String(body.name),"type":body.get_class(),"layer":body.collision_layer,
			"mask":body.collision_mask,"disabled":shape.disabled,"shape_size":_vector(shape.shape.size),
			"shape_transform":_transform(shape),"visual":_bounds(body.get_node("Visual"))})
	var ray := PhysicsRayQueryParameters3D.create(Vector3(START.x,3,START.z),Vector3(START.x,-2,START.z),1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return {"player":{"class":player.get_class(),"root_transform":_transform(player),
		"layer":player.collision_layer,"mask":player.collision_mask,"safe_margin":player.safe_margin,
		"gravity_mps2":player.gravity_mps2,"velocity":_vector(player.velocity),"floor":player.is_on_floor(),
		"collision_disabled":collision.disabled,"collision_class":collision.shape.get_class(),
		"height":collision.shape.height,"radius":collision.shape.radius,"collision_transform":_transform(collision),
		"visual":_bounds($Actors/Player/Visual/Body)},"fixtures":fixtures,
		"fixture_transform":_transform(self),"fixtures_transform":_transform($Fixtures),"actors_transform":_transform($Actors),
		"ruler":_bounds(ruler),"height_bar":_bounds(height_bar),"spawn_xyz":_vector(START),
		"spawn_overlap":_overlap(START),"spawn_support":String(hit.collider.name) if not hit.is_empty() else "",
		"spawn_support_position":_vector(hit.position) if not hit.is_empty() else [],
		"queries":{"door_clear":_overlap(Vector3(0,0.02,-4)),"door_left":_overlap(Vector3(-0.8,0.02,-4)),
			"door_right":_overlap(Vector3(0.8,0.02,-4)),"door_lintel":_overlap(Vector3(0,1,-4)),
			"wall":_overlap(Vector3(-7,0.02,-4)),"step015":_overlap(Vector3(4,0.1,2)),"step030":_overlap(Vector3(6,0.25,2))},
		"camera":{"view":view_key,"transform":_transform(camera),"size":camera.size,"projection":camera.projection,
			"viewport":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y]}}

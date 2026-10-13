extends Node3D
## Frozen source-vertex inspection scene, not gameplay or physical survey.
@export var world_config: Resource
var runtime_state: Dictionary = {}
var scale_state: Dictionary = {}
var scale_data: Dictionary = {}
var anchor_nodes := {}
var control_nodes := {}
var ruler_nodes := {}
var labels: Array[Dictionary] = []
var origin: Marker3D
var cube_mesh: MeshInstance3D
var current_view := "map"
var menu_open := false
var header: PanelContainer
var view_bar: HBoxContainer
var menu: PanelContainer
@onready var camera: Camera3D = $Presentation/Camera

func _ready() -> void:
	runtime_state = world_config.read_runtime()
	if not runtime_state.ok:
		_error(runtime_state.error)
		return
	scale_state = load("res://scripts/scale_config.gd").new().read_scale(runtime_state)
	if not scale_state.ok:
		_error(scale_state.error)
		return
	scale_data = scale_state.data
	$World.populate(runtime_state.world)
	_build_reference_geometry()
	_build_interface()
	set_view("map")
	print("E04_READY anchors=%s distance_pairs=%s controls=%s city_meshes=%s" % [anchor_nodes.size(),scale_data.distance_pairs.size(),control_nodes.size(),$World.loaded_geometry_count])

func _error(message: String) -> void:
	var label := Label.new()
	label.position = Vector2(24,24)
	label.text = "거리·축척 검증\n"+message
	$Interface.add_child(label)
	push_error(message)

func _v(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material

func _line(parent: Node3D, start: Vector3, end: Vector3, color: Color, name_text: String) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([start,end])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	var line := MeshInstance3D.new()
	line.name = name_text
	line.mesh = mesh
	line.material_override = _material(color)
	parent.add_child(line)
	return line

func _label(text: String, node: Node3D, local_point := Vector3.ZERO, offset := Vector2.ZERO, view_filter := "all") -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color(0.07,0.11,0.15))
	label.add_theme_color_override("font_outline_color",Color(0.98,0.98,0.96))
	label.add_theme_constant_override("outline_size",5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Interface.add_child(label)
	labels.append({"label":label,"node":node,"point":local_point,"offset":offset,"view":view_filter})

func _build_reference_geometry() -> void:
	origin = Marker3D.new()
	origin.name = "TechnicalOrigin"
	$Controls.add_child(origin)
	_label("원점 · 시작 위치 아님",origin,Vector3.ZERO,Vector2(-40,18),"axes")
	for entry in scale_data.anchors:
		var marker := Marker3D.new()
		marker.name = entry.id.replace("/","_")
		marker.position = _v(entry.world_xyz_m)
		$Anchors.add_child(marker)
		anchor_nodes[entry.id] = marker
		var dot := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.6
		mesh.height = 3.2
		dot.mesh = mesh
		dot.material_override = _material(Color(1,0.82,0.15))
		marker.add_child(dot)
		_label(entry.name+" · 외곽점",marker,Vector3.ZERO,Vector2(0,-10),"city")
	var colors := [Color(0.17,0.58,1),Color(1,0.35,0.59),Color(0.99,0.65,0.12),Color(0.63,0.30,0.88)]
	for i in range(scale_data.distance_pairs.size()):
		var pair: Dictionary = scale_data.distance_pairs[i]
		var a: Vector3 = anchor_nodes[pair.from].position
		var b: Vector3 = anchor_nodes[pair.to].position
		var line := _line($Anchors,a,b,colors[i],"Distance_%s" % i)
		ruler_nodes["pair_%s" % i] = line
		_label("%.3fm" % Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z)),line,(a+b)/2,Vector2(0,-16-i*3),"city")
	var titles := {"grid_east_10m":"동 +X · 10m","grid_west_10m":"서 −X · 10m","grid_north_10m":"북 −Z · 10m","grid_south_10m":"남 +Z · 10m","local_up_10m":"위 +Y · 10m"}
	for entry in scale_data.controls:
		var marker := Marker3D.new()
		marker.name = entry.id
		marker.position = _v(entry.expected_world_xyz_m)
		$Controls.add_child(marker)
		control_nodes[entry.id] = marker
		var color := Color(0.16,0.47,0.92) if "north" in entry.id or "south" in entry.id else Color(0.92,0.46,0.17) if "east" in entry.id or "west" in entry.id else Color(0.60,0.27,0.80)
		ruler_nodes[entry.id] = _line($Controls,Vector3.ZERO,marker.position,color,entry.id+"_line")
		_label(titles[entry.id],marker,Vector3.ZERO,Vector2(0,-10),"axes")
	cube_mesh = MeshInstance3D.new()
	cube_mesh.name = "Synthetic10mCube"
	var cube := BoxMesh.new()
	var edge: float = scale_data.settings.cube.edge_m
	cube.size = Vector3(edge,edge,edge)
	cube_mesh.mesh = cube
	cube_mesh.position = _v(scale_data.settings.cube.position)
	var material := _material(Color(0.95,0.72,0.19,0.30))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cube_mesh.material_override = material
	$Controls.add_child(cube_mesh)
	_label("10 × 10 × 10m 시험 큐브",cube_mesh,Vector3(0,edge/2,0),Vector2(0,-16),"axes")

func _build_interface() -> void:
	header = PanelContainer.new()
	header.position = Vector2(16,16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97,0.98,0.96,0.94)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel",style)
	$Interface.add_child(header)
	var text := Label.new()
	text.add_theme_font_size_override("font_size",16)
	text.add_theme_color_override("font_color",Color(0.08,0.12,0.15))
	text.text = "서울 · 거리와 축척 확인\n건물 외곽 정점 사이의 직선거리\n보행 경로나 출입구 간 거리가 아닙니다.\n\n"
	for pair in scale_data.distance_pairs:
		text.text += "%s → %s  %.3fm\n" % [pair.names[0],pair.names[1],pair.projected_distance_m]
	text.text += "\n10m 기준물은 합성 시험 도형입니다."
	header.add_child(text)
	view_bar = HBoxContainer.new()
	view_bar.position = Vector2(24,650)
	view_bar.add_theme_constant_override("separation",8)
	$Interface.add_child(view_bar)
	for key in ["map","axes","oblique"]:
		var button := Button.new()
		button.text = scale_data.settings.views[key].title
		button.pressed.connect(set_view.bind(key))
		view_bar.add_child(button)
	var quit_button := Button.new()
	quit_button.text = "메뉴 · Esc"
	quit_button.pressed.connect(toggle_menu)
	view_bar.add_child(quit_button)
	var credit := Label.new()
	credit.position = Vector2(790,692)
	credit.add_theme_font_size_override("font_size",12)
	credit.text = "지도 © OpenStreetMap contributors · ODbL"
	credit.add_theme_color_override("font_outline_color",Color(0.12,0.14,0.15))
	credit.add_theme_constant_override("outline_size",3)
	$Interface.add_child(credit)
	menu = PanelContainer.new()
	menu.position = Vector2(400,270)
	menu.visible = false
	$Interface.add_child(menu)
	var content := VBoxContainer.new()
	menu.add_child(content)
	var resume := Button.new()
	resume.text = "돌아가기 · Esc"
	resume.pressed.connect(toggle_menu)
	content.add_child(resume)
	var exit := Button.new()
	exit.text = "검증 장면 종료"
	exit.pressed.connect(func():get_tree().quit())
	content.add_child(exit)

func set_view(key: String) -> void:
	if scale_data.is_empty() or not scale_data.settings.views.has(key):return
	current_view = key
	var view: Dictionary = scale_data.settings.views[key]
	camera.position = _v(view.position)
	camera.look_at(_v(view.target),Vector3(0,0,-1) if key=="map" else Vector3.UP)
	camera.size = view.size_m
	_update_labels()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu") and not event.is_echo():
		toggle_menu()
		get_viewport().set_input_as_handled()

func toggle_menu() -> void:
	if scale_data.is_empty():return
	menu_open = not menu_open
	get_tree().paused = menu_open
	header.visible = not menu_open
	view_bar.visible = not menu_open
	menu.visible = menu_open
	_update_labels()

func _process(_delta: float) -> void:
	_update_labels()

func _update_labels() -> void:
	for item in labels:
		var point: Vector3 = item.node.to_global(item.point)
		var screen := camera.unproject_position(point)
		var selected: bool = item.view=="all" or item.view==current_view or item.view=="city" and current_view!="axes"
		item.label.visible = selected and not menu_open and not camera.is_position_behind(point) and Rect2(8,8,1136,625).has_point(screen) and not Rect2(16,16,390,265).has_point(screen)
		item.label.position = screen - Vector2(item.label.size.x/2,16)+item.offset

func measure() -> Dictionary:
	var anchors := []
	for entry in scale_data.anchors:
		var node: MeshInstance3D = $World.source_nodes[entry.feature_id]
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var source := _v(entry.world_xyz_m)
		var nearest := Vector3.ZERO
		var error := INF
		for vertex in vertices:
			var point := node.to_global(vertex)
			var distance := Vector2(source.x,source.z).distance_to(Vector2(point.x,point.z))
			if distance < error:
				error = distance
				nearest = point
		var anchor: Marker3D = anchor_nodes[entry.id]
		anchors.append({"id":entry.id,"feature_id":entry.feature_id,"name":entry.name,
			"anchor_global_xyz":_array(anchor.global_position),"mesh_global_xyz":_array(nearest),
			"mesh_transform":_transform(node.global_transform),"mesh_vertex_count":vertices.size()})
	var controls := []
	for entry in scale_data.controls:
		var line: MeshInstance3D = ruler_nodes[entry.id]
		var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		controls.append({"id":entry.id,"marker_global_xyz":_array(control_nodes[entry.id].global_position),
			"line_global_xyz":[_array(line.to_global(vertices[0])),_array(line.to_global(vertices[1]))]})
	var cube_vertices: PackedVector3Array = cube_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var cube_points := []
	for vertex in cube_vertices:cube_points.append(_array(cube_mesh.to_global(vertex)))
	var pairs := []
	for i in range(scale_data.distance_pairs.size()):
		var line: MeshInstance3D = ruler_nodes["pair_%s" % i]
		var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		pairs.append({"from":scale_data.distance_pairs[i].from,"to":scale_data.distance_pairs[i].to,
			"line_global_xyz":[_array(line.to_global(vertices[0])),_array(line.to_global(vertices[1]))]})
	return {"anchors":anchors,"controls":controls,"pairs":pairs,"origin_global_xyz":_array(origin.global_position),
		"cube_global_vertices":cube_points,"world_transform":_transform($World.global_transform),
		"anchor_parent_transform":_transform($Anchors.global_transform),"control_parent_transform":_transform($Controls.global_transform),
		"loaded_geometry_count":$World.loaded_geometry_count,"world_sha256":scale_data.world_sha256,
		"camera":{"view":current_view,"size_m":camera.size,"projection":camera.projection,"keep_aspect":camera.keep_aspect,
			"viewport":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],
			"render_target_size":[get_viewport().size.x,get_viewport().size.y],"global_transform":_transform(camera.global_transform),
			"origin_pixel":_pixel(camera.unproject_position(origin.global_position)),
			"east_pixel":_pixel(camera.unproject_position(control_nodes.grid_east_10m.global_position)),
			"north_pixel":_pixel(camera.unproject_position(control_nodes.grid_north_10m.global_position))}}

func _array(vector: Vector3) -> Array:return [vector.x,vector.y,vector.z]
func _pixel(vector: Vector2) -> Array:return [vector.x,vector.y]
func _transform(value: Transform3D) -> Dictionary:
	return {"origin":_array(value.origin),"basis":[_array(value.basis.x),_array(value.basis.y),_array(value.basis.z)]}

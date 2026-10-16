extends Node3D
## A source-linked visit, not a surveyed reconstruction. Outdoor bodies stay intact.
const LIBRARY_ID := "osm:relation:10757525:building"
const INTERACT_ACTION := &"interact"
const ROOM_ORIGIN := Vector3(650.0,-100.0,0.0)
const ROOM_SIZE := Vector3(16.0,4.8,12.0)
const INTERACTION_RADIUS_M := 2.5
var entrance_world_position := Vector3(145.8338,0.08,-114.8415)
var entrance_outward_direction := Vector3(-0.031243,0.0,0.999512)
var door_world_position := Vector3(145.8989,3.1,-116.9254)
var active := false
var loaded := false
var load_error := ""
var entry_count := 0
var exit_count := 0
var rejected_entries := 0
var rejected_exits := 0
var e_requires_release := true
var _e_was_pressed := false
var host: Node3D
var room: Node3D
var room_bodies: Array[StaticBody3D] = []
var prompt: PanelContainer
var prompt_text: Label
var indoor_panel: PanelContainer
var indoor_text: Label
var door_marker: Label3D
var _outside_position := Vector3.ZERO
var _world_spawn := Vector3.ZERO
var _outside_view := {}
var _outside_starting_yaw := 0.0
var _hud_was_visible := true
var _names_were_processing := true
var _notice := ""
var _materials := {}

func setup(root_scene: Node3D) -> bool:
	if loaded or not root_scene.runtime_ok:return false
	host = root_scene
	if not host.city.source_nodes.has(LIBRARY_ID):return _fail("서울도서관 원천 건물이 없습니다.")
	if not entrance_world_position.is_finite() or not entrance_outward_direction.is_finite():return _fail("서울도서관 입구 좌표가 다릅니다.")
	if not InputMap.has_action(INTERACT_ACTION):
		InputMap.add_action(INTERACT_ACTION)
		var key := InputEventKey.new();key.physical_keycode = KEY_E
		InputMap.action_add_event(INTERACT_ACTION,key)
	# Observe E while menus pause the world so a held key cannot enter on resume.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1
	_world_spawn = host.player.spawn_transform.origin
	_build_room()
	_build_interface()
	_build_entrance_marker()
	loaded = true
	print("INTERIOR_VISIT_READY feature=",LIBRARY_ID," room=",ROOM_ORIGIN," authored_not_surveyed=true")
	return true

func _fail(message: String) -> bool:
	load_error = message
	return false

func _material(id: String, color: Color) -> StandardMaterial3D:
	if _materials.has(id):return _materials[id]
	var result := StandardMaterial3D.new();result.albedo_color = color;result.roughness = .86
	_materials[id] = result
	return result

func _box(title: String, size: Vector3, point: Vector3, material: Material, solid := false) -> MeshInstance3D:
	var visual := MeshInstance3D.new();visual.name = title;visual.position = point
	var mesh := BoxMesh.new();mesh.size = size;visual.mesh = mesh;visual.material_override = material
	room.add_child(visual)
	if solid:
		var body := StaticBody3D.new();body.name = title+"Body"
		body.position = point;body.collision_layer = 1;body.collision_mask = 0
		body.set_meta("geometry_id","EXP03_library_"+title)
		var collision := CollisionShape3D.new();collision.name = "CollisionShape"
		var shape := BoxShape3D.new();shape.size = size;collision.shape = shape
		body.add_child(collision);room.add_child(body);room_bodies.append(body)
	return visual

func _sign(title: String, text: String, point: Vector3, size := 38) -> Label3D:
	var sign := Label3D.new();sign.name = title;sign.text = text;sign.position = point
	sign.font_size = size;sign.pixel_size = .008;sign.outline_size = 2
	sign.modulate = Color(.15,.20,.20);sign.outline_modulate = Color(.95,.94,.88)
	room.add_child(sign)
	return sign

func _shelf(title: String, point: Vector3, colors: Array) -> void:
	var wood: Material = _materials.wood
	_box(title+"Back",Vector3(2.5,2.05,.16),point+Vector3(0,1.025,-.26),wood,true)
	for x in [-1.22,1.22]:_box(title+"Side",Vector3(.09,2.05,.62),point+Vector3(x,1.025,0),wood,true)
	for level in range(4):
		var y := .12+level*.55
		_box(title+"Shelf",Vector3(2.5,.075,.62),point+Vector3(0,y,0),wood,true)
		if level==3:continue
		for column in range(8):
			var h := .31+float((column+level)%3)*.055
			_box(title+"Books",Vector3(.225,h,.36),point+Vector3(-1.05+column*.30,y+.04+h*.5,.03),colors[(column+level)%colors.size()])

func _build_room() -> void:
	room = Node3D.new();room.name = "LibraryLobby";room.position = ROOM_ORIGIN;add_child(room)
	var stone := _material("stone",Color(.79,.78,.71))
	var wall := _material("wall",Color(.89,.87,.80))
	var ceiling := _material("ceiling",Color(.92,.91,.85))
	var trim := _material("trim",Color(.27,.32,.32))
	var glass := _material("glass",Color(.25,.36,.38))
	var wood := _material("wood",Color(.46,.32,.19))
	var seam := _material("seam",Color(.64,.64,.59))
	var seat := _material("seat",Color(.27,.39,.34))
	var books := [_material("book_red",Color(.48,.20,.16)),_material("book_green",Color(.20,.34,.27)),_material("book_blue",Color(.20,.30,.42)),_material("book_cream",Color(.76,.68,.47))]
	_box("Floor",Vector3(16.4,.2,12.4),Vector3(0,-.1,0),stone,true)
	_box("Ceiling",Vector3(16.4,.25,12.4),Vector3(0,4.925,0),ceiling,true)
	_box("WestWall",Vector3(.25,4.8,12.4),Vector3(-8.125,2.4,0),wall,true)
	_box("EastWall",Vector3(.25,4.8,12.4),Vector3(8.125,2.4,0),wall,true)
	_box("NorthWall",Vector3(16.4,4.8,.25),Vector3(0,2.4,-6.125),wall,true)
	_box("SouthWall",Vector3(16.4,4.8,.25),Vector3(0,2.4,6.125),wall,true)
	# The exit is an opaque glass-like portal. It never exposes the outdoor world.
	_box("ExitGlass",Vector3(3.4,3.1,.06),Vector3(0,1.55,5.955),glass)
	for x in [-1.75,0.,1.75]:_box("ExitMullion",Vector3(.07,3.2,.09),Vector3(x,1.60,5.91),trim)
	_box("ExitLintel",Vector3(3.6,.10,.10),Vector3(0,3.20,5.91),trim)
	_box("ExitHandle",Vector3(.055,.52,.15),Vector3(.20,1.18,5.84),stone)
	var exit_sign := _sign("ExitSign","출입구",Vector3(0,3.58,5.90),40);exit_sign.rotation.y = PI
	for x in range(-6,8,2):_box("TileSeam",Vector3(.014,.004,12.),Vector3(float(x),.002,0),seam)
	for z in range(-4,6,2):_box("TileSeam",Vector3(16.,.004,.014),Vector3(0,.002,float(z)),seam)
	# Small paired door bays recall the public plan's central stair/lift circulation.
	for x in [-6.5,6.5]:
		_box("SideDoor",Vector3(1.50,2.65,.07),Vector3(x,1.325,-5.955),trim)
		_box("SideDoorInset",Vector3(1.34,2.44,.08),Vector3(x,1.325,-5.91),stone)
	_sign("LibraryTitle","서울도서관",Vector3(0,3.65,-5.94),58)
	_sign("ReadingSign","1층 · 책과 함께 쉬어가는 공간",Vector3(0,2.95,-5.94),30)
	_shelf("ShelfLeft",Vector3(-3.8,0,-5.45),books)
	_shelf("ShelfRight",Vector3(3.8,0,-5.45),books)
	_shelf("ShelfWest",Vector3(-6.35,0,-2.1),books)
	_box("InformationDesk",Vector3(2.8,1.0,1.1),Vector3(5.2,.50,1.1),wood,true)
	_box("DeskTop",Vector3(3.0,.10,1.25),Vector3(5.2,1.05,1.1),stone,true)
	var desk_sign := _sign("Information","안내",Vector3(5.2,.70,1.67),32);desk_sign.rotation.y = 0.0
	for x in [-1.8,1.8]:
		_box("ReadingTable",Vector3(2.25,.12,1.25),Vector3(x,.78,-1.3),wood,true)
		for dx in [-.85,.85]:
			for dz in [-.4,.4]:_box("TableLeg",Vector3(.075,.72,.075),Vector3(x+dx,.36,-1.3+dz),trim,true)
		for z in [-2.35,-.25]:
			_box("ReadingSeat",Vector3(1.55,.16,.5),Vector3(x,.46,z),seat,true)
			_box("SeatSupport",Vector3(1.3,.38,.34),Vector3(x,.19,z),wood,true)
	for x in [-4.,4.]:
		var light := OmniLight3D.new();light.name = "LobbyLight";light.position = Vector3(x,3.9,0)
		light.omni_range = 15.;light.light_energy = 2.2;light.light_color = Color(1.,.94,.82);light.shadow_enabled = false
		room.add_child(light)
		var fixture := _box("CeilingLight",Vector3(3.0,.055,1.1),Vector3(x,4.76,0),_material("light",Color(.98,.96,.85)))
		fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.visible = false

func _panel(title: String, size: int) -> PanelContainer:
	var panel := PanelContainer.new();panel.name = title;panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new();style.bg_color = Color(.055,.09,.12,.92)
	style.content_margin_left = 15;style.content_margin_right = 15;style.content_margin_top = 9;style.content_margin_bottom = 9
	style.corner_radius_top_left = 6;style.corner_radius_top_right = 6;style.corner_radius_bottom_left = 6;style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel",style)
	var label := Label.new();label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",Color(.98,.97,.9))
	panel.add_child(label);host.get_node("Interface").add_child(panel)
	return panel

func _build_interface() -> void:
	prompt = _panel("LibraryEntryPrompt",17);prompt_text = prompt.get_child(0);prompt.visible = false
	indoor_panel = _panel("LibraryInteriorGuide",15);indoor_text = indoor_panel.get_child(0);indoor_panel.visible = false
	indoor_text.text = "서울도서관 · 1층 로비와 작은 열람 공간\n출입문 근처 E 나가기 · Esc 메뉴\n공식 안내를 참고해 단순화한 공간입니다. 실제 치수·세부 배치와 다를 수 있습니다."

func _build_entrance_marker() -> void:
	door_marker = Label3D.new();door_marker.name = "LibraryVisitEntrance"
	door_marker.text = "서울도서관\nE · 1층 로비"
	door_marker.position = entrance_world_position+Vector3.UP*2.2
	door_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED;door_marker.font_size = 38;door_marker.pixel_size = .006
	door_marker.modulate = Color(.98,.95,.80);door_marker.outline_modulate = Color(.06,.10,.13);door_marker.outline_size = 10
	add_child(door_marker);door_marker.visible = false

func _menu_open() -> bool:
	return host.menu.visible or not host.input_router.gameplay_enabled

func _entry_near() -> bool:
	return host.player.global_position.distance_to(entrance_world_position)<=INTERACTION_RADIUS_M

func _exit_near() -> bool:
	return host.player.global_position.distance_to(ROOM_ORIGIN+Vector3(0,.08,5.75))<=INTERACTION_RADIUS_M

func _entry_visible() -> bool:
	var from: Vector3 = host.player.global_position+Vector3.UP
	var to := entrance_world_position+Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[host.player.get_rid()])
	return host.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _physics_process(_delta: float) -> void:
	if not loaded or not is_instance_valid(host) or not host.runtime_ok:return
	var held := Input.is_action_pressed(INTERACT_ACTION)
	var edge := held and not _e_was_pressed
	_e_was_pressed = held
	if _menu_open():
		e_requires_release = true
		return
	if e_requires_release:
		if not held:e_requires_release = false
		return
	if not edge:return
	if active:exit_visit()
	else:enter_visit()

func _process(_delta: float) -> void:
	if not loaded or not is_instance_valid(host):return
	var menu_open := _menu_open()
	var view := host.get_viewport().get_visible_rect().size
	door_marker.visible = not active and not menu_open and host.player.global_position.distance_to(entrance_world_position)<45.
	indoor_panel.visible = active and not menu_open
	indoor_panel.custom_minimum_size.x = minf(650.,maxf(1.,view.x-32.))
	indoor_panel.size = Vector2(indoor_panel.custom_minimum_size.x,indoor_panel.get_combined_minimum_size().y)
	indoor_panel.position = Vector2(16,16)
	prompt_text.text = "E · 서울도서관 1층 로비 들어가기" if not active else "E · 서울광장 쪽으로 나가기"
	if not _notice.is_empty():prompt_text.text = _notice
	prompt.visible = not menu_open and ((active and _exit_near()) or (not active and _entry_near() and _entry_visible()) or not _notice.is_empty())
	prompt.custom_minimum_size.x = minf(520.,maxf(1.,view.x-32.))
	prompt.size = Vector2(prompt.custom_minimum_size.x,prompt.get_combined_minimum_size().y)
	prompt.position = Vector2(maxf(16.,(view.x-prompt.size.x)*.5),view.y-148.)
	if active:_hide_outdoor_labels()

func _hide_outdoor_labels() -> void:
	if is_instance_valid(host.hud_panel):host.hud_panel.visible = false
	if not is_instance_valid(host.building_names):return
	host.building_names.panel.visible = false;host.building_names.crosshair.visible = false
	for marker in host.building_names.markers:marker.node.visible = false

func _orient(yaw: float, pitch: float, distance: float) -> void:
	host.rig.reset_orientation()
	host.rig.yaw = yaw;host.rig.pitch = pitch
	host.rig.requested_distance = distance;host.rig.current_distance = distance
	host.rig.global_position = host.player.global_position+Vector3.UP*host.rig.pivot_height_m
	host.rig.rotation = Vector3(pitch,yaw,0)
	host.rig.snap_to_target_pose()

func enter_visit() -> bool:
	if not loaded or active or _menu_open() or not _entry_near() or not _entry_visible() or not host.player.is_on_floor() or host.player.input_latched:
		rejected_entries += 1
		return false
	var outside := _safe_external_point(host.player.global_position)
	if outside.is_empty():rejected_entries += 1;return false
	var bounds := AABB(ROOM_ORIGIN+Vector3(-7.6,-.3,-5.6),Vector3(15.2,5.2,11.2))
	var target := ROOM_ORIGIN+Vector3(0,.08,2.5)
	if not host.player.begin_interior(target,bounds):
		rejected_entries += 1
		_notice = "로비를 준비하지 못했습니다. 잠시 후 다시 시도해주세요."
		return false
	_outside_position = outside.point
	_outside_view = {"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance}
	_outside_starting_yaw = host.starting_yaw;host.starting_yaw = 0.
	_hud_was_visible = host.hud_panel.visible
	_names_were_processing = host.building_names.is_physics_processing()
	host.building_names.set_physics_process(false)
	active = true;room.visible = true;entry_count += 1;_notice = "";e_requires_release = true
	_orient(0.,deg_to_rad(-15.),3.6)
	_hide_outdoor_labels()
	return true

func _safe_external_point(requested: Vector3) -> Dictionary:
	if not requested.is_finite() or not host.player.exterior_contains(requested):return {}
	var space := host.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(requested+Vector3.UP,requested-Vector3.UP,host.player.collision_mask,[host.player.get_rid()])
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.dot(Vector3.UP)<cos(host.player.floor_max_angle):return {}
	var point := Vector3(requested.x,hit.position.y+.08,requested.z)
	if not host.player.exterior_contains(point):return {}
	var node: CollisionShape3D = host.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new();query.shape = node.shape
	query.transform = Transform3D(Basis.IDENTITY,point)*node.transform
	query.collision_mask = host.player.collision_mask;query.exclude = [host.player.get_rid()]
	if not space.intersect_shape(query,1).is_empty():return {}
	if not host.city.volume_clear(point,node.shape.height,node.shape.radius):return {}
	return {"point":point}

func _leave_at(requested: Vector3) -> bool:
	var safe := _safe_external_point(requested)
	if safe.is_empty() or not host.player.end_interior(safe.point):return false
	active = false;room.visible = false;exit_count += 1;_notice = "";e_requires_release = true
	host.starting_yaw = _outside_starting_yaw
	_orient(_outside_view.yaw,_outside_view.pitch,_outside_view.distance)
	host.hud_panel.visible = _hud_was_visible
	host.building_names.set_physics_process(_names_were_processing)
	return true

func exit_visit() -> bool:
	if not loaded or not active or _menu_open() or not _exit_near() or not host.player.is_on_floor() or host.player.input_latched:
		rejected_exits += 1
		return false
	for candidate in [_outside_position,_outside_position+entrance_outward_direction*.6,_world_spawn]:
		if _leave_at(candidate):return true
	rejected_exits += 1
	_notice = "밖의 복귀 위치가 막혀 있습니다. 잠시 후 다시 시도해주세요."
	return false

func return_to_world_spawn() -> bool:
	if not loaded or not active:return false
	if not _leave_at(_world_spawn):
		rejected_exits += 1;_notice = "대한문 밖 복귀 위치가 막혀 있습니다."
		return false
	host.player.recover("manual_restart")
	return true

func status_text() -> String:
	return "서울도서관 · 1층 로비 · 속도 %.2fm/s%s"%[Vector2(host.player.velocity.x,host.player.velocity.z).length()," · 이동키를 놓아주세요" if host.player.input_latched else ""]

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"active":active,"feature_id":LIBRARY_ID,"entry_count":entry_count,"exit_count":exit_count,
		"rejected_entries":rejected_entries,"rejected_exits":rejected_exits,"e_requires_release":e_requires_release,"room_static_bodies":room_bodies.size(),
		"room_origin":[ROOM_ORIGIN.x,ROOM_ORIGIN.y,ROOM_ORIGIN.z],"entrance":[entrance_world_position.x,entrance_world_position.y,entrance_world_position.z],
		"outside_return":[_outside_position.x,_outside_position.y,_outside_position.z],"authored_not_surveyed":true,"notice":_notice}

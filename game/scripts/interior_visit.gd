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
var _e_press_pending := false
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
var catalog: Array[Dictionary] = []
var current_spec := {}
var prepared_id := ""
var _room_ready_tick := 0
var _entry_requested := false
var markers: Array[Dictionary] = []
var elevator_panel: PanelContainer
var elevator_title: Label
var elevator_floors: GridContainer
var ride_panel: PanelContainer
var ride_text: Label
var elevator_open := false
var in_elevator := false
var selected_floor := 0
var _ride_from := 0
var _ride_elapsed := 0.
var _ride_duration := 0.
var _notice_until := 0
var _recovery_floor := -1
var wayfinding: Node3D

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
	process_physics_priority = 1
	_world_spawn = host.player.spawn_transform.origin
	catalog = preload("res://scripts/building_visit_catalog.gd").new().build(host)
	if catalog.is_empty():return _fail("건물 출입 자료가 없습니다.")
	_build_interface()
	_build_markers()
	if not select_building(LIBRARY_ID):return _fail("도서관 내부를 준비하지 못했습니다.")
	wayfinding=preload("res://scripts/entrance_wayfinding.gd").new()
	wayfinding.name="EntranceWayfinding";add_child(wayfinding)
	if not wayfinding.setup(host,self):return _fail("건물 입구 안내를 준비하지 못했습니다.")
	loaded = true
	print("INTERIOR_VISIT_READY buildings=",catalog.size()," source_scaled=true authored_not_surveyed=true")
	return true

func select_building(id: String) -> bool:
	if active or in_elevator:return false
	for spec in catalog:
		if spec.id!=id:continue
		_set_entry(spec)
		return _prepare_room()
	return false

func _set_entry(spec: Dictionary) -> void:
	current_spec = spec
	entrance_world_position = spec.entrance
	entrance_outward_direction = spec.outward
	door_world_position = spec.door

func _prepare_room() -> bool:
	if prepared_id==String(current_spec.get("id","")) and is_instance_valid(room):return true
	if is_instance_valid(room):
		for body in room_bodies:body.collision_layer = 0
		remove_child(room);room.queue_free()
	room_bodies.clear()
	room = preload("res://scripts/building_interior_space.gd").new()
	room.name = "BuildingInterior";add_child(room)
	if not room.setup(current_spec,ROOM_ORIGIN):return false
	room_bodies.assign(room.bodies)
	room.visible = false;room.set_process(false)
	prepared_id = current_spec.id
	_room_ready_tick = Engine.get_physics_frames()+3
	return true

func _fail(message: String) -> bool:
	load_error = message
	return false

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
	prompt = _panel("BuildingEntryPrompt",17);prompt_text = prompt.get_child(0);prompt.visible = false
	indoor_panel = _panel("BuildingInteriorGuide",15);indoor_text = indoor_panel.get_child(0);indoor_panel.visible = false
	elevator_panel = _panel("ElevatorFloorPicker",18)
	elevator_panel.get_child(0).queue_free()
	var content := VBoxContainer.new();elevator_panel.add_child(content)
	elevator_title = Label.new();elevator_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(elevator_title)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size = Vector2(300,180);content.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	elevator_floors = GridContainer.new();elevator_floors.columns = 4;scroll.add_child(elevator_floors)
	var close := Button.new();close.text = "닫기 · E";close.pressed.connect(_close_elevator);content.add_child(close)
	elevator_panel.visible = false
	ride_panel = _panel("ElevatorTravel",24);ride_text = ride_panel.get_child(0);ride_panel.visible = false
	var black := StyleBoxFlat.new();black.bg_color = Color(.025,.035,.045,1.0)
	black.content_margin_left = 32;black.content_margin_top = 32;black.content_margin_right = 32;black.content_margin_bottom = 32
	ride_panel.add_theme_stylebox_override("panel",black)
	# The closed car covers the 3D view, while pause/source controls stay usable.
	host.get_node("Interface").move_child(ride_panel,0)

func _build_markers() -> void:
	var material := StandardMaterial3D.new();material.albedo_color = Color(.13,.24,.27);material.roughness = .5
	for spec in catalog:
		var marker := Label3D.new();marker.name = "BuildingEntrance"
		marker.text = "%s\nE · 출입 · %d층"%[spec.title,int(spec.floor_count)]
		marker.position = spec.entrance+Vector3.UP*2.2
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED;marker.font_size = 34;marker.pixel_size = .006
		marker.modulate = Color(.98,.95,.80);marker.outline_modulate = Color(.06,.10,.13);marker.outline_size = 10
		add_child(marker);marker.visible = false
		# An authored doorway sits on the actual source perimeter. It is visual;
		# entry never opens or removes the retained exterior collision body.
		var door := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size = Vector3(2.2,2.6,.09)
		door.mesh = mesh;door.material_override = material
		door.position = spec.door+spec.outward*.08;door.position.y = spec.entrance.y+1.3
		door.rotation.y = atan2(spec.outward.x,spec.outward.z)
		add_child(door)
		if spec.id==LIBRARY_ID:door.visible = false;door_marker = marker
		markers.append({"spec":spec,"node":marker})

func _menu_open() -> bool:
	return host.menu.visible or (not host.input_router.gameplay_enabled and not elevator_open and not in_elevator)

func _entry_near() -> bool:
	# Test the visible doorway width and its front apron, not a sphere around a
	# point two metres away from the facade. Contact at either door leaf counts.
	var outward := entrance_outward_direction.normalized()
	var along := Vector3(outward.z,0.,-outward.x)
	var offset: Vector3 = host.player.global_position-entrance_world_position
	var front := offset.dot(outward)+2.
	var half_width := 2.35 if current_spec.get("id")==LIBRARY_ID else 1.4
	return absf(offset.dot(along))<=half_width and front>=.15 and front<=4.5 and absf(offset.y)<1.2

func _exit_near() -> bool:
	return active and room.floor_index_at(host.player.global_position)==0 and host.player.global_position.distance_to(room.exit_point())<=INTERACTION_RADIUS_M

func _elevator_near() -> bool:
	if not active or in_elevator:return false
	var floor_index: int = room.floor_index_at(host.player.global_position)
	return host.player.global_position.distance_to(room.elevator_point(floor_index))<=2.2

func _entry_visible() -> bool:
	var from: Vector3 = host.player.global_position+Vector3.UP
	var to := entrance_world_position+Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[host.player.get_rid()])
	return host.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func entry_action_text() -> String:
	if _entry_requested:return "입구를 준비하고 있습니다"
	if host.player.input_latched:return "이동키를 놓고 E · 들어가기"
	if not host.player.is_on_floor():return "착지한 뒤 E · 들어가기"
	return "E · 들어가기"

func _input(event: InputEvent) -> void:
	# A physical tap may begin and end between physics ticks. Retain its edge,
	# but never buffer a rejected press until the player later approaches a door.
	if event.is_action_pressed(INTERACT_ACTION) and not event.is_echo():
		if loaded and not _menu_open() and not e_requires_release:_e_press_pending = true

func _physics_process(delta: float) -> void:
	if not loaded or not is_instance_valid(host) or not host.runtime_ok:return
	var held := Input.is_action_pressed(INTERACT_ACTION)
	var edge := _e_press_pending or (held and not _e_was_pressed)
	_e_press_pending = false
	_e_was_pressed = held
	if _menu_open():
		e_requires_release = true
		_entry_requested = false
		if elevator_open:_close_elevator(false)
		return
	if in_elevator:
		_step_elevator(delta)
		e_requires_release = true
		return
	if e_requires_release:
		if not held:e_requires_release = false
		return
	if _entry_requested and not active:
		if Engine.get_physics_frames()>=_room_ready_tick:
			_entry_requested = false
			enter_visit()
		return
	if not edge:return
	if elevator_open:_close_elevator()
	elif active and _elevator_near():_open_elevator()
	elif active:exit_visit()
	else:enter_visit()

func _process(_delta: float) -> void:
	if not loaded or not is_instance_valid(host):return
	var menu_open := _menu_open()
	var view := host.get_viewport().get_visible_rect().size
	if _notice_until>0 and Time.get_ticks_msec()>_notice_until:_notice = "";_notice_until = 0
	wayfinding.update_guidance(_delta,active or menu_open)
	var closest: Dictionary = wayfinding.target_spec
	var nearest := INF
	if not closest.is_empty():nearest=host.player.global_position.distance_squared_to(closest.entrance)
	for marker in markers:marker.node.visible=false
	if not active and not closest.is_empty() and not _entry_requested:
		_set_entry(closest)
		if nearest<10.*10.:_prepare_room()
	indoor_panel.visible = active and not menu_open
	indoor_panel.custom_minimum_size.x = minf(650.,maxf(1.,view.x-32.))
	indoor_panel.size = Vector2(indoor_panel.custom_minimum_size.x,indoor_panel.get_combined_minimum_size().y)
	indoor_panel.position = Vector2(16,16)
	if active:
		var index: int = room.floor_index_at(host.player.global_position)
		room.set_active_floor(index)
		if index!=_recovery_floor and not in_elevator and host.player.is_on_floor() and absf(host.player.global_position.y-(ROOM_ORIGIN.y+index*float(current_spec.floor_height)))<.2:
			var recovery_point: Vector3 = room.floor_spawn(index)
			if _indoor_target_clear(recovery_point):
				host.player.spawn_transform = Transform3D(Basis.IDENTITY,recovery_point)
				_recovery_floor = index
		indoor_text.text = "%s · %d / %d층\n왼쪽 뒤 계단 · 앞쪽 엘리베이터에서 E · 1층 출입구 E\n건물 원본 크기·층수에 맞춘 게임 공간입니다. 방 배치와 동선은 재구성했습니다."%[current_spec.title,index+1,int(current_spec.floor_count)]
	prompt_text.text = "%s · %s · %d층"%[entry_action_text(),current_spec.get("title","건물"),int(current_spec.get("floor_count",1))] if not active else ("E · 엘리베이터 층 선택" if _elevator_near() else "E · 건물 밖으로 나가기")
	if not _notice.is_empty():prompt_text.text = _notice
	prompt.visible = not menu_open and not elevator_open and not in_elevator and ((active and (_exit_near() or _elevator_near())) or (not active and _entry_near() and _entry_visible()) or not _notice.is_empty())
	prompt.custom_minimum_size.x = minf(520.,maxf(1.,view.x-32.))
	prompt.size = Vector2(prompt.custom_minimum_size.x,prompt.get_combined_minimum_size().y)
	prompt.position = Vector2(maxf(16.,(view.x-prompt.size.x)*.5),view.y-148.)
	elevator_panel.visible = elevator_open and not menu_open
	elevator_panel.custom_minimum_size.x = minf(420.,maxf(1.,view.x-32.))
	elevator_panel.size = Vector2(elevator_panel.custom_minimum_size.x,elevator_panel.get_combined_minimum_size().y)
	elevator_panel.position = (view-elevator_panel.size)*.5
	ride_panel.visible = in_elevator
	ride_panel.position = Vector2.ZERO;ride_panel.size = view
	if active:_hide_outdoor_labels()

func _tell(message: String) -> void:
	_notice = message;_notice_until = Time.get_ticks_msec()+3000

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

func _open_elevator() -> void:
	if not _elevator_near() or not host.player.is_on_floor() or host.player.input_latched:return
	selected_floor = room.floor_index_at(host.player.global_position)
	for child in elevator_floors.get_children():
		elevator_floors.remove_child(child);child.queue_free()
	for index in range(int(current_spec.floor_count)):
		var button := Button.new();button.text = "%d층"%(index+1);button.custom_minimum_size = Vector2(72,38)
		button.disabled = index==selected_floor
		button.pressed.connect(request_floor.bind(index));elevator_floors.add_child(button)
	elevator_title.text = "%s · 엘리베이터\n현재 %d층 · 목적층을 선택하세요"%[current_spec.title,selected_floor+1]
	elevator_open = true;e_requires_release = true
	host.input_router.gameplay_enabled = false;host.rig.set_capture(false)
	host.player.require_neutral_input()

func _close_elevator(capture := true) -> void:
	elevator_open = false;elevator_panel.visible = false;e_requires_release = true
	if not host.menu.visible and not in_elevator:
		host.input_router.gameplay_enabled = true
		if capture:host.rig.set_capture(true)
	host.player.require_neutral_input()

func request_floor(index: int) -> bool:
	if not active or in_elevator or _menu_open() or not _elevator_near() or not host.player.is_on_floor():return false
	var from_index: int = room.floor_index_at(host.player.global_position)
	if index<0 or index>=int(current_spec.floor_count) or index==from_index:return false
	var target: Vector3 = room.elevator_point(index)
	if not _indoor_target_clear(target):_tell("목적층 승강장에 장애물이 있습니다.");return false
	_ride_from = from_index;selected_floor = index;_ride_elapsed = 0.
	_ride_duration = 1.5+minf(3.,absf(index-from_index)*.35)
	_close_elevator(false)
	in_elevator = true;e_requires_release = true
	host.input_router.gameplay_enabled = false;host.rig.set_capture(false)
	host.player.velocity = Vector3.ZERO;host.player.set_physics_process(false)
	return true

func _indoor_target_clear(point: Vector3) -> bool:
	if not host.player.interior_bounds.has_point(point):return false
	var space := host.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,host.player.collision_mask,[host.player.get_rid()])
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.7 or absf(hit.position.y-(point.y-.08))>.15:return false
	var shape_node: CollisionShape3D = host.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new();query.shape = shape_node.shape
	query.transform = Transform3D(Basis.IDENTITY,point)*shape_node.transform
	query.collision_mask = host.player.collision_mask;query.exclude = [host.player.get_rid()]
	return space.intersect_shape(query,1).is_empty()

func _step_elevator(delta: float) -> void:
	# The closed-car transition owns the passenger pose. Intermediate floor
	# slabs are hidden by the opaque car view; only safe landings regain input.
	host.input_router.gameplay_enabled = false
	_ride_elapsed += delta
	var progress := clampf(_ride_elapsed/_ride_duration,0.,1.)
	var floor_value := lerpf(float(_ride_from),float(selected_floor),smoothstep(0.,1.,progress))
	var from: Vector3 = room.elevator_point(_ride_from)
	var to: Vector3 = room.elevator_point(selected_floor)
	host.player.global_position = from.lerp(to,smoothstep(0.,1.,progress))
	ride_text.text = "엘리베이터\n\n%d층 %s %d층\n\n현재 %d층 · 이동 중"%[_ride_from+1,"↑" if selected_floor>_ride_from else "↓",selected_floor+1,int(round(floor_value))+1]
	ride_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;ride_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if progress<1.:return
	if not _indoor_target_clear(to) or not host.player.relocate_interior(to):
		if _cancel_ride():_tell("목적층이 막혀 있어 안전한 층으로 돌아왔습니다.")
		else:ride_text.text = "엘리베이터 대기\n\n승강장에 장애물이 있습니다.\n안전한 도착 위치를 확인하고 있습니다."
		return
	in_elevator = false;ride_panel.visible = false
	host.player.set_physics_process(true);host.input_router.gameplay_enabled = true
	room.set_active_floor(selected_floor)
	host.rig.set_capture(true);_orient(PI,deg_to_rad(-15.),3.6)

func _cancel_ride() -> bool:
	if not in_elevator:return true
	var candidates: Array[Vector3] = [room.elevator_point(_ride_from),room.floor_spawn(_ride_from)]
	for index in range(int(current_spec.floor_count)):candidates.append(room.floor_spawn(index))
	for point in candidates:
		if not _indoor_target_clear(point) or not host.player.relocate_interior(point):continue
		in_elevator = false;ride_panel.visible = false;selected_floor = room.floor_index_at(point)
		host.player.set_physics_process(true);host.input_router.gameplay_enabled = not host.menu.visible
		if not host.menu.visible:host.rig.set_capture(true)
		_orient(host.rig.yaw,host.rig.pitch,host.rig.requested_distance)
		return true
	# Keep the passenger under the lift controller until a landing is safe.
	return false

func enter_visit() -> bool:
	if not loaded or active or _menu_open() or not _entry_near() or not _entry_visible() or not host.player.is_on_floor() or host.player.input_latched:
		rejected_entries += 1
		return false
	var outside := _entry_return_point()
	if outside.is_empty():rejected_entries += 1;return false
	if prepared_id!=current_spec.id:
		if not _prepare_room():rejected_entries += 1;_tell("내부 공간을 준비하지 못했습니다.");return false
	if Engine.get_physics_frames()<_room_ready_tick:
		_entry_requested = true
		return false
	var bounds: AABB = room.interior_bounds
	var target: Vector3 = room.floor_spawn(0)
	if not host.player.begin_interior(target,bounds):
		rejected_entries += 1
		_tell("내부 바닥을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.")
		return false
	_outside_position = outside.point
	_outside_view = {"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance}
	_outside_starting_yaw = host.starting_yaw;host.starting_yaw = 0.
	_hud_was_visible = host.hud_panel.visible
	_names_were_processing = host.building_names.is_physics_processing()
	host.building_names.set_physics_process(false)
	active = true;room.visible = true;room.set_process(true);entry_count += 1;_notice = "";e_requires_release = true
	selected_floor = 0;_recovery_floor = 0;room.set_active_floor(0)
	_orient(0.,deg_to_rad(-15.),3.6)
	_hide_outdoor_labels()
	return true

func _entry_return_point() -> Dictionary:
	# A physically valid wall contact can lack the stricter 5mm recovery margin.
	# Save a nearby safe point instead of weakening the outdoor spawn validator.
	for candidate in [host.player.global_position,host.player.global_position+entrance_outward_direction*.15,host.player.global_position+entrance_outward_direction*.6,entrance_world_position]:
		var safe := _safe_external_point(candidate)
		if not safe.is_empty():return safe
	return {}

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
	if in_elevator:return false
	var safe := _safe_external_point(requested)
	if safe.is_empty() or not host.player.end_interior(safe.point):return false
	if elevator_open:_close_elevator(false)
	active = false;room.visible = false;room.set_process(false);exit_count += 1;_notice = "";e_requires_release = true
	host.starting_yaw = _outside_starting_yaw
	_orient(_outside_view.yaw,_outside_view.pitch,_outside_view.distance)
	host.hud_panel.visible = _hud_was_visible
	host.building_names.set_physics_process(_names_were_processing)
	return true

func exit_visit() -> bool:
	if not loaded or not active or in_elevator or _menu_open() or not _exit_near() or not host.player.is_on_floor() or host.player.input_latched:
		rejected_exits += 1
		return false
	for candidate in [_outside_position,_outside_position+entrance_outward_direction*.6,_world_spawn]:
		if _leave_at(candidate):return true
	rejected_exits += 1
	_tell("밖의 복귀 위치가 막혀 있습니다. 잠시 후 다시 시도해주세요.")
	return false

func return_to_world_spawn() -> bool:
	if not loaded or not active:return false
	if in_elevator and not _cancel_ride():return false
	if not _leave_at(_world_spawn):
		rejected_exits += 1;_notice = "대한문 밖 복귀 위치가 막혀 있습니다."
		return false
	host.player.recover("manual_restart")
	return true

func go_to_library_entrance() -> bool:
	if not loaded:return false
	if active and not return_to_world_spawn():return false
	if not select_building(LIBRARY_ID):return false
	var safe := _safe_external_point(entrance_world_position)
	if safe.is_empty():_tell("도서관 정문 위치가 막혀 있습니다.");return false
	host.player.global_transform = Transform3D(Basis.IDENTITY,safe.point)
	host.player.require_neutral_input();host.player.reset_physics_interpolation()
	_orient(atan2(entrance_outward_direction.x,entrance_outward_direction.z),deg_to_rad(-15.),4.5)
	e_requires_release = true
	return true

func status_text() -> String:
	return "%s · %d층 · 속도 %.2fm/s%s"%[current_spec.title,room.floor_index_at(host.player.global_position)+1,Vector2(host.player.velocity.x,host.player.velocity.z).length()," · 이동키를 놓아주세요" if host.player.input_latched else ""]

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"active":active,"feature_id":current_spec.get("id",""),"entry_count":entry_count,"exit_count":exit_count,
		"rejected_entries":rejected_entries,"rejected_exits":rejected_exits,"e_requires_release":e_requires_release,"room_static_bodies":room_bodies.size(),
		"room_origin":[ROOM_ORIGIN.x,ROOM_ORIGIN.y,ROOM_ORIGIN.z],"entrance":[entrance_world_position.x,entrance_world_position.y,entrance_world_position.z],
		"outside_return":[_outside_position.x,_outside_position.y,_outside_position.z],"authored_not_surveyed":true,"notice":_notice,
		"catalog_count":catalog.size(),"floor_count":current_spec.get("floor_count",0),"current_floor":room.floor_index_at(host.player.global_position) if active else 0,"width":current_spec.get("width",0.),"depth":current_spec.get("depth",0.),
		"in_elevator":in_elevator,"elevator_open":elevator_open,"selected_floor":selected_floor}

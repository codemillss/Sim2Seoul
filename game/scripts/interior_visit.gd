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
var elevator_scroll: ScrollContainer
var elevator_content: VBoxContainer
var elevator_close_button: Button
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
var cabin: Node3D
var rooftop: Node3D
var facility_interaction: Node3D
var on_roof := false
var _roof_ready_tick := 0
var _ride_phase := "idle"
var _phase_elapsed := 0.0
var _motion_elapsed := 0.0
var _motion_duration := 0.0
var _motion_start_floor := 0.0
var _motion_distance := 0.0
var _motion_acceleration := 0.0
var _motion_accel_time := 0.0
var _motion_cruise_time := 0.0
var _motion_peak_speed := 0.0
var _current_floor_value := 0.0
var _ride_speed := 0.0
var _door_fraction := 1.0
var _ride_returning := false
var _release_point := Vector3.ZERO
var _blocked_retry_elapsed := 0.0
var _ride_saved := {}
const BOARDING_SECONDS := .45
const CLOSING_SECONDS := .85
const ARRIVING_SECONDS := .45
const OPENING_SECONDS := .85
const EXIT_HOLD_SECONDS := .30

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
	cabin=preload("res://scripts/elevator_cabin.gd").new()
	add_child(cabin)
	if not cabin.setup():return _fail("엘리베이터 객실을 준비하지 못했습니다.")
	_build_markers()
	if not select_building(LIBRARY_ID):return _fail("도서관 내부를 준비하지 못했습니다.")
	wayfinding=preload("res://scripts/entrance_wayfinding.gd").new()
	wayfinding.name="EntranceWayfinding";add_child(wayfinding)
	if not wayfinding.setup(host,self):return _fail("건물 입구 안내를 준비하지 못했습니다.")
	facility_interaction=preload("res://scripts/facility_interaction.gd").new()
	facility_interaction.name="FacilityInteraction";add_child(facility_interaction)
	facility_interaction.setup(host,self)
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
	if is_instance_valid(facility_interaction) and not facility_interaction.cancel():return false
	if is_instance_valid(room):
		for body in room_bodies:body.collision_layer = 0
		remove_child(room);room.queue_free()
	room_bodies.clear()
	room = preload("res://scripts/building_interior_space.gd").new()
	room.name = "BuildingInterior";add_child(room)
	if not room.setup(current_spec,ROOM_ORIGIN):return false
	room_bodies.assign(room.bodies)
	room.visible = false;room.set_process(false)
	if is_instance_valid(rooftop):
		for body: StaticBody3D in rooftop.bodies:body.collision_layer=0
		remove_child(rooftop);rooftop.queue_free()
	var roof_script: Script=load("res://scripts/rooftop_space.gd")
	if roof_script==null:return false
	rooftop=roof_script.new();add_child(rooftop)
	if not rooftop.setup(host,current_spec):return false
	rooftop.visible=not active;rooftop.set_process(false)
	on_roof=false
	_roof_ready_tick=Engine.get_physics_frames()+3
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
	elevator_content = VBoxContainer.new();elevator_content.name="ElevatorFloorContent";elevator_panel.add_child(elevator_content)
	elevator_title = Label.new();elevator_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;elevator_content.add_child(elevator_title)
	elevator_scroll = ScrollContainer.new();elevator_scroll.name="ElevatorFloorScroll";elevator_scroll.custom_minimum_size = Vector2(0,180);elevator_content.add_child(elevator_scroll)
	elevator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	elevator_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	elevator_scroll.clip_contents=true;elevator_scroll.follow_focus=true
	elevator_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;elevator_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	elevator_floors = GridContainer.new();elevator_floors.name="ElevatorFloorGrid";elevator_floors.columns = 4;elevator_floors.size_flags_horizontal=Control.SIZE_EXPAND_FILL;elevator_scroll.add_child(elevator_floors)
	elevator_close_button = Button.new();elevator_close_button.text = "닫기 · E";elevator_close_button.pressed.connect(_close_elevator);elevator_content.add_child(elevator_close_button)
	elevator_panel.visible = false
	ride_panel = _panel("ElevatorTravel",17);ride_text = ride_panel.get_child(0);ride_panel.visible = false
	var black := StyleBoxFlat.new();black.bg_color = Color(.025,.045,.055,.86)
	black.content_margin_left = 15;black.content_margin_top = 9;black.content_margin_right = 15;black.content_margin_bottom = 9
	ride_panel.add_theme_stylebox_override("panel",black)
	# Compact status leaves the actual 3D cabin in view, below pause/source UI.
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
	return active and not on_roof and not in_elevator and room.floor_index_at(host.player.global_position)==0 and host.player.global_position.distance_to(room.exit_point())<=INTERACTION_RADIUS_M

func _elevator_near() -> bool:
	if not active or in_elevator:return false
	var floor_index: int = _current_destination()
	return host.player.global_position.distance_to(_landing_point(floor_index))<=2.2

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
	if is_instance_valid(facility_interaction):facility_interaction.step(delta,_menu_open() or in_elevator or elevator_open)
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
	elif is_instance_valid(facility_interaction) and facility_interaction.handle_interact():e_requires_release=true
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
	indoor_panel.visible = active and not menu_open and not in_elevator and not elevator_open
	indoor_panel.custom_minimum_size.x = minf(650.,maxf(1.,view.x-32.))
	indoor_panel.size = Vector2(indoor_panel.custom_minimum_size.x,indoor_panel.get_combined_minimum_size().y)
	indoor_panel.position = Vector2(16,16)
	if active:
		var index: int = _current_destination()
		if not in_elevator and not on_roof:room.set_active_floor(index)
		if index!=_recovery_floor and not in_elevator and not on_roof and host.player.is_on_floor() and absf(host.player.global_position.y-(ROOM_ORIGIN.y+index*float(current_spec.floor_height)))<.2:
			var recovery_point: Vector3 = room.floor_spawn(index)
			if _indoor_target_clear(recovery_point):
				host.player.spawn_transform = Transform3D(Basis.IDENTITY,recovery_point)
				_recovery_floor = index
		if on_roof:
			indoor_text.text="%s · %s\n승강장 앞에서 E · 1층으로 내려가면 건물 밖으로 나갈 수 있습니다."%[current_spec.title,String(rooftop.profile_title)]
			if host.player.is_swimming():indoor_text.text+="\n수영 중 · WASD / 방향키 이동 · Space 물 밖으로 점프"
		else:
			indoor_text.text = "%s · %d / %d층\n왼쪽 뒤 계단 · 앞쪽 엘리베이터에서 E · 1층 출입구 E\n건물 원본 크기·층수에 맞춘 게임 공간입니다. 방 배치와 동선은 재구성했습니다."%[current_spec.title,index+1,int(current_spec.floor_count)]
			indoor_text.text=indoor_text.text.replace("건물 원본 크기·층수에 맞춘 게임 공간입니다. 방 배치와 동선은 재구성했습니다.","음식·샤워·운동기구 가까이에서 E · 사용 중 E로 그만하기")
	var facility_hint: String=facility_interaction.prompt_text() if is_instance_valid(facility_interaction) and active and not on_roof else ""
	prompt_text.text = "%s · %s · %d층"%[entry_action_text(),current_spec.get("title","건물"),int(current_spec.get("floor_count",1))] if not active else ("E · 엘리베이터 층 선택" if _elevator_near() else "E · 건물 밖으로 나가기")
	if not facility_hint.is_empty():prompt_text.text=facility_hint
	elif not _notice.is_empty():prompt_text.text = _notice
	prompt.visible = not menu_open and not elevator_open and not in_elevator and (not facility_hint.is_empty() or (active and (_exit_near() or _elevator_near())) or (not active and _entry_near() and _entry_visible()) or not _notice.is_empty())
	prompt.custom_minimum_size.x = minf(520.,maxf(1.,view.x-32.))
	prompt.size = Vector2(prompt.custom_minimum_size.x,prompt.get_combined_minimum_size().y)
	prompt.position = Vector2(maxf(16.,(view.x-prompt.size.x)*.5),view.y-148.)
	if active and is_instance_valid(facility_interaction):
		var activity_rect: Rect2=facility_interaction.status_rect()
		if activity_rect.has_area():prompt.position.y=minf(prompt.position.y,activity_rect.position.y-prompt.size.y-10.)
	elevator_panel.visible = elevator_open and not menu_open
	_layout_elevator_picker(view)
	ride_panel.visible = in_elevator
	ride_panel.custom_minimum_size.x=minf(430.,maxf(1.,view.x-32.))
	ride_panel.size=Vector2(ride_panel.custom_minimum_size.x,ride_panel.get_combined_minimum_size().y)
	ride_panel.position=Vector2(16.,16.)
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
	if is_instance_valid(facility_interaction) and facility_interaction.is_using():return
	if not _elevator_near() or not host.player.is_on_floor() or host.player.input_latched:return
	selected_floor = _current_destination()
	for child in elevator_floors.get_children():
		elevator_floors.remove_child(child);child.queue_free()
	for index in range(destination_count()):
		var button := Button.new();button.text = _landing_label(index);button.custom_minimum_size = Vector2(152,58)
		button.add_theme_font_size_override("font_size",15)
		if index<int(current_spec.floor_count):
			var programme_title: String=String(room.detail_kit.level_profiles[index].title)
			button.text+="\n"+programme_title.get_slice(" · ",0)
			button.tooltip_text=programme_title
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_ALL
		button.disabled = index==selected_floor or (index==int(current_spec.floor_count) and Engine.get_physics_frames()<_roof_ready_tick)
		button.pressed.connect(request_floor.bind(index));elevator_floors.add_child(button)
	elevator_title.text = "%s · 엘리베이터\n현재 %s · 목적층을 선택하세요"%[current_spec.title,_landing_label(selected_floor)]
	elevator_open = true;e_requires_release = true
	host.input_router.gameplay_enabled = false;host.rig.set_capture(false)
	host.player.require_neutral_input()
	elevator_scroll.scroll_vertical=0
	_layout_elevator_picker(host.get_viewport().get_visible_rect().size)
	_focus_elevator_floor.call_deferred(mini(selected_floor+1,destination_count()-1) if selected_floor<destination_count()-1 else 0)

func _layout_elevator_picker(view: Vector2) -> void:
	var panel_width := minf(420.,maxf(1.,view.x-32.))
	var padding: Vector2=elevator_panel.get_theme_stylebox("panel").get_minimum_size()
	var grid_separation := float(elevator_floors.get_theme_constant("h_separation"))
	# Reserve the vertical scrollbar's width even before it appears, avoiding
	# a one-frame horizontal overflow when a 28-floor grid is first populated.
	var bar_width := maxf(16.,elevator_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var grid_width := maxf(1.,panel_width-padding.x-bar_width)
	elevator_floors.columns=clampi(int(floor((grid_width+grid_separation)/(152.+grid_separation))),1,2)
	var fixed_height := padding.y+elevator_title.get_combined_minimum_size().y+elevator_close_button.get_combined_minimum_size().y+2.*float(elevator_content.get_theme_constant("separation"))
	var available_height := maxf(1.,view.y-32.)
	var list_height := maxf(1.,minf(320.,available_height-fixed_height))
	elevator_scroll.custom_minimum_size=Vector2(0.,list_height)
	elevator_panel.custom_minimum_size.x=panel_width
	elevator_panel.size=Vector2(panel_width,fixed_height+list_height)
	elevator_panel.position=Vector2(maxf(0.,(view.x-elevator_panel.size.x)*.5),maxf(0.,(view.y-elevator_panel.size.y)*.5))

func _focus_elevator_floor(index: int) -> void:
	if not elevator_open or host.menu.visible:return
	if index<0 or index>=elevator_floors.get_child_count():return
	var button := elevator_floors.get_child(index) as Button
	if button==null or button.disabled:return
	button.grab_focus()
	# Container sorting is deferred; focus-follow handles keyboard navigation,
	# and this deferred call also scrolls the initial focused row after layout.
	elevator_scroll.ensure_control_visible.call_deferred(button)

func _close_elevator(capture := true) -> void:
	elevator_open = false;elevator_panel.visible = false;e_requires_release = true
	if not host.menu.visible and not in_elevator:
		host.input_router.gameplay_enabled = true
		if capture:host.rig.set_capture(true)
	host.player.require_neutral_input()

func request_floor(index: int) -> bool:
	if is_instance_valid(facility_interaction) and facility_interaction.is_using():return false
	if not active or in_elevator or _menu_open() or not _elevator_near() or not host.player.is_on_floor():return false
	var from_index: int = _current_destination()
	if index<0 or index>=destination_count() or index==from_index:return false
	if index==int(current_spec.floor_count) and Engine.get_physics_frames()<_roof_ready_tick:_tell("옥상 승강장을 준비하고 있습니다.");return false
	var target: Vector3 = _landing_point(index)
	if not _landing_target_clear(index,target):_tell("목적층 승강장에 장애물이 있습니다.");return false
	_ride_from = from_index;selected_floor = index;_ride_elapsed = 0.
	_motion_start_floor=float(from_index);_current_floor_value=float(from_index)
	_configure_motion()
	_ride_duration=BOARDING_SECONDS+CLOSING_SECONDS+_motion_duration+ARRIVING_SECONDS+OPENING_SECONDS+EXIT_HOLD_SECONDS
	_ride_returning=false;_release_point=target;_blocked_retry_elapsed=0.;_ride_speed=0.;_door_fraction=1.
	_close_elevator(false)
	in_elevator = true;e_requires_release = true
	host.input_router.gameplay_enabled = false;host.rig.set_capture(false)
	_ride_saved={"rig_process":host.rig.is_processing(),"rig_physics":host.rig.is_physics_processing(),"visual":host.player.get_node("Visual").visible,"player_physics":host.player.is_physics_processing(),"yaw":host.rig.yaw,"pitch":host.rig.pitch,"distance":host.rig.requested_distance}
	host.rig.set_process(false);host.rig.set_physics_process(false)
	room.visible=false;room.set_process(false)
	if is_instance_valid(rooftop):rooftop.visible=false;rooftop.set_process(false)
	host.player.velocity = Vector3.ZERO;host.player.set_physics_process(false)
	host.player.clear_water_region()
	host.player.global_position=cabin.passenger_point();host.player.reset_physics_interpolation()
	host.player.get_node("Visual").visible=false
	cabin.begin(from_index,index,destination_count())
	_set_ride_phase("boarding")
	_update_cabin()
	return true

func destination_count() -> int:
	return int(current_spec.get("floor_count",0))+(1 if is_instance_valid(rooftop) else 0)

func landing_point(index: int) -> Vector3:return _landing_point(index)

func _current_destination() -> int:
	if in_elevator:return clampi(int(round(_current_floor_value)),0,maxi(0,destination_count()-1))
	if on_roof:return int(current_spec.floor_count)
	return room.floor_index_at(host.player.global_position)

func _landing_point(index: int) -> Vector3:
	if index==int(current_spec.floor_count) and is_instance_valid(rooftop):return rooftop.lift_point()
	return room.elevator_point(index)

func _landing_label(index: int) -> String:
	return "옥상" if index==int(current_spec.floor_count) else "%d층"%(index+1)

func _landing_bounds(index: int) -> AABB:
	return rooftop.world_bounds if index==int(current_spec.floor_count) and is_instance_valid(rooftop) else room.interior_bounds

func _landing_frame(index: int) -> Transform3D:
	return rooftop.frame if index==int(current_spec.floor_count) and is_instance_valid(rooftop) else Transform3D.IDENTITY

func _landing_rect(index: int) -> Rect2:
	return rooftop.walkable_rect if index==int(current_spec.floor_count) and is_instance_valid(rooftop) else Rect2()

func _landing_target_clear(index: int,point: Vector3) -> bool:
	if index<0 or index>=destination_count():return false
	return _point_supported_clear(point,_landing_bounds(index),_landing_frame(index),_landing_rect(index))

func _indoor_target_clear(point: Vector3) -> bool:
	return _point_supported_clear(point,host.player.interior_bounds,_landing_frame(int(current_spec.floor_count)) if on_roof else Transform3D.IDENTITY,_landing_rect(int(current_spec.floor_count)) if on_roof else Rect2())

func _point_supported_clear(point: Vector3,bounds: AABB,frame: Transform3D,rect: Rect2) -> bool:
	if not point.is_finite() or not bounds.has_point(point):return false
	if rect.has_area():
		var local: Vector3=frame.affine_inverse()*point
		if not rect.grow(-.4).has_point(Vector2(local.x,local.z)):return false
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
	# A detached 3D car owns the view and a fixed safe passenger pose. Logical
	# travel is distance-based; no passenger is swept through the source slabs.
	host.input_router.gameplay_enabled = false
	host.rig.set_capture(false)
	_ride_elapsed += delta
	_phase_elapsed += delta
	match _ride_phase:
		"boarding":
			if _phase_elapsed>=BOARDING_SECONDS:_set_ride_phase("closing")
		"closing":
			_door_fraction=1.-smoothstep(0.,1.,clampf(_phase_elapsed/CLOSING_SECONDS,0.,1.))
			if _phase_elapsed>=CLOSING_SECONDS:_door_fraction=0.;_motion_elapsed=0.;_set_ride_phase("accelerating")
		"accelerating","cruising","decelerating":_step_motion(delta)
		"arriving":
			if _phase_elapsed>=ARRIVING_SECONDS:_prepare_release()
		"opening":
			_door_fraction=smoothstep(0.,1.,clampf(_phase_elapsed/OPENING_SECONDS,0.,1.))
			if _phase_elapsed>=OPENING_SECONDS:_door_fraction=1.;_set_ride_phase("exit_hold")
		"exit_hold":
			if _phase_elapsed>=EXIT_HOLD_SECONDS:
				if not _release_landing(_release_point,selected_floor):_door_fraction=0.;_set_ride_phase("blocked")
		"blocked":
			_door_fraction=0.;_ride_speed=0.;_blocked_retry_elapsed+=delta
			if _blocked_retry_elapsed>=.30:_blocked_retry_elapsed=0.;_prepare_release()
	if in_elevator:_update_cabin()

func _set_ride_phase(phase: String) -> void:
	_ride_phase=phase;_phase_elapsed=0.

func _configure_motion() -> void:
	_motion_distance=absf(float(selected_floor)-_motion_start_floor)*float(current_spec.floor_height)
	var acceleration := 8.0
	var maximum := 18.0
	_motion_peak_speed=minf(maximum,sqrt(maxf(.0001,_motion_distance)*acceleration))
	_motion_accel_time=_motion_peak_speed/acceleration
	_motion_cruise_time=maxf(0.,(_motion_distance-_motion_peak_speed*_motion_peak_speed/acceleration)/_motion_peak_speed)
	if _motion_accel_time*2.+_motion_cruise_time<2.8:
		_motion_accel_time=1.4;_motion_cruise_time=0.;_motion_peak_speed=_motion_distance/_motion_accel_time
	_motion_acceleration=_motion_peak_speed/_motion_accel_time
	_motion_duration=_motion_accel_time*2.+_motion_cruise_time
	_motion_elapsed=0.

func _step_motion(delta: float) -> void:
	_motion_elapsed=minf(_motion_duration,_motion_elapsed+delta)
	var time := _motion_elapsed
	var distance := 0.0
	if time<_motion_accel_time:
		_ride_phase="accelerating";_phase_elapsed=time
		_ride_speed=_motion_acceleration*time;distance=.5*_motion_acceleration*time*time
	elif time<_motion_accel_time+_motion_cruise_time:
		_ride_phase="cruising";_phase_elapsed=time-_motion_accel_time
		_ride_speed=_motion_peak_speed;distance=.5*_motion_peak_speed*_motion_accel_time+_motion_peak_speed*(time-_motion_accel_time)
	else:
		_ride_phase="decelerating";_phase_elapsed=time-_motion_accel_time-_motion_cruise_time
		var remaining := _motion_duration-time
		_ride_speed=_motion_acceleration*remaining;distance=_motion_distance-.5*_motion_acceleration*remaining*remaining
	var progress := clampf(distance/maxf(.0001,_motion_distance),0.,1.)
	_current_floor_value=lerpf(_motion_start_floor,float(selected_floor),progress)
	if time>=_motion_duration:
		_current_floor_value=float(selected_floor);_ride_speed=0.;_set_ride_phase("arriving")

func _release_candidates() -> Array[Dictionary]:
	var points: Array[Dictionary]=[{"index":_ride_from,"point":_landing_point(_ride_from)}]
	if _ride_from<int(current_spec.floor_count):points.append({"index":_ride_from,"point":room.floor_spawn(_ride_from)})
	for index in range(int(current_spec.floor_count)):points.append({"index":index,"point":room.floor_spawn(index)})
	if is_instance_valid(rooftop):points.append({"index":int(current_spec.floor_count),"point":rooftop.spawn_point()})
	return points

func _prepare_release() -> void:
	if _landing_target_clear(selected_floor,_release_point):
		_set_ride_phase("opening")
		return
	for candidate: Dictionary in _release_candidates():
		if not _landing_target_clear(int(candidate.index),candidate.point):continue
		_release_point=candidate.point
		var next_floor := int(candidate.index)
		_ride_returning=true
		if absf(_current_floor_value-float(next_floor))>.001:
			_motion_start_floor=_current_floor_value;selected_floor=next_floor;_configure_motion()
			_ride_duration+=_motion_duration+ARRIVING_SECONDS+OPENING_SECONDS+EXIT_HOLD_SECONDS
			_set_ride_phase("accelerating")
		else:selected_floor=next_floor;_set_ride_phase("opening")
		return
	_set_ride_phase("blocked");_ride_speed=0.;_door_fraction=0.

func _update_cabin() -> void:
	var progress := clampf(_motion_elapsed/maxf(.001,_motion_duration),0.,1.)
	var leg_from := int(round(_motion_start_floor))
	cabin.update_state(_ride_phase,leg_from,selected_floor,_current_floor_value,progress,_ride_speed,_door_fraction,_ride_returning)
	var phase_text: String={"boarding":"승차 중","closing":"문이 닫힙니다","accelerating":"출발합니다","cruising":"이동 중","decelerating":"도착합니다","arriving":"정차 중","opening":"문이 열립니다","exit_hold":"내리세요","blocked":"안전한 승강장을 확인하고 있습니다"}.get(_ride_phase,"엘리베이터")
	ride_text.text="엘리베이터 · %s → %s\n%s%s"%[_landing_label(leg_from),_landing_label(selected_floor),phase_text," · 안전한 층으로 복귀" if _ride_returning else ""]

func _release_landing(point: Vector3,index: int) -> bool:
	if not _landing_target_clear(index,point):return false
	if not host.player.relocate_interior_region(point,_landing_bounds(index),_landing_frame(index),_landing_rect(index),index==int(current_spec.floor_count)):return false
	on_roof=index==int(current_spec.floor_count)
	# Water follows the successfully committed destination region. The closed
	# car never carries buoyancy state from the departure roof into another room.
	host.player.clear_water_region()
	if on_roof:
		var water: Dictionary=rooftop.pool_water_region()
		if not water.is_empty():host.player.set_water_region(water)
	room.visible=not on_roof;room.set_process(not on_roof)
	if is_instance_valid(rooftop):rooftop.visible=on_roof;rooftop.set_process(on_roof)
	cabin.finish();in_elevator=false;ride_panel.visible=false;selected_floor=index;_current_floor_value=float(index);_ride_speed=0.;_ride_phase="idle"
	host.rig.set_process(bool(_ride_saved.get("rig_process",true)));host.rig.set_physics_process(bool(_ride_saved.get("rig_physics",true)))
	host.rig.camera.make_current()
	host.player.get_node("Visual").visible=bool(_ride_saved.get("visual",true))
	host.player.set_physics_process(bool(_ride_saved.get("player_physics",true)))
	host.input_router.gameplay_enabled=not host.menu.visible
	host.player.require_neutral_input();e_requires_release=true
	if not on_roof:room.set_active_floor(index)
	_recovery_floor=index
	host.rig.set_capture(not host.menu.visible)
	if on_roof:
		var roof_frame: Transform3D=rooftop.frame
		_orient(atan2(roof_frame.basis.z.x,roof_frame.basis.z.z),deg_to_rad(-15.),2.8)
	else:_orient(float(_ride_saved.get("yaw",0.)),float(_ride_saved.get("pitch",deg_to_rad(-15.))),float(_ride_saved.get("distance",3.6)))
	if _ride_returning:_tell("목적층이 막혀 안전한 층으로 돌아왔습니다.")
	return true

func _cancel_ride() -> bool:
	if not in_elevator:return true
	for candidate: Dictionary in _release_candidates():
		if _release_landing(candidate.point,int(candidate.index)):return true
	# Keep the passenger under the lift controller until a landing is safe.
	return false

func elevator_snapshot() -> Dictionary:
	return {"phase":_ride_phase,"elapsed":_ride_elapsed,"phase_elapsed":_phase_elapsed,"duration":_ride_duration,"motion_elapsed":_motion_elapsed,"motion_duration":_motion_duration,"motion_start_floor":_motion_start_floor,"from_floor":_ride_from,"target_floor":selected_floor,"current_floor_value":_current_floor_value,"speed_mps":_ride_speed,"max_speed_mps":_motion_peak_speed,"acceleration_mps2":_motion_acceleration,"door_open_fraction":_door_fraction,"cabin_visible":cabin.visible if is_instance_valid(cabin) else false,"cabin_camera_current":cabin.camera.current if is_instance_valid(cabin) else false,"passenger_position":host.player.global_position,"cabin_bounds":cabin.cabin_bounds if is_instance_valid(cabin) else AABB(),"render_mode":"detached_3d_cabin","safe_release_pending":in_elevator,"returning_to_safe_floor":_ride_returning,"destination_count":destination_count(),"on_roof":on_roof}

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
	on_roof=false
	host.player.clear_water_region()
	if is_instance_valid(rooftop):rooftop.visible=false;rooftop.set_process(false)
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
	if safe.is_empty():return false
	if is_instance_valid(facility_interaction) and not facility_interaction.cancel():return false
	if not host.player.end_interior(safe.point):return false
	if elevator_open:_close_elevator(false)
	active = false;room.visible = false;room.set_process(false);exit_count += 1;_notice = "";e_requires_release = true
	on_roof=false
	host.player.clear_water_region()
	if is_instance_valid(rooftop):rooftop.visible=true;rooftop.set_process(false)
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
	if in_elevator:return "%s · 엘리베이터 · %s → %s"%[current_spec.title,_landing_label(_ride_from),_landing_label(selected_floor)]
	return "%s · %s · 속도 %.2fm/s%s"%[current_spec.title,"옥상" if on_roof else "%d층"%(room.floor_index_at(host.player.global_position)+1),Vector2(host.player.velocity.x,host.player.velocity.z).length()," · 이동키를 놓아주세요" if host.player.input_latched else ""]

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"active":active,"feature_id":current_spec.get("id",""),"entry_count":entry_count,"exit_count":exit_count,
		"rejected_entries":rejected_entries,"rejected_exits":rejected_exits,"e_requires_release":e_requires_release,"room_static_bodies":room_bodies.size(),
		"room_origin":[ROOM_ORIGIN.x,ROOM_ORIGIN.y,ROOM_ORIGIN.z],"entrance":[entrance_world_position.x,entrance_world_position.y,entrance_world_position.z],
		"outside_return":[_outside_position.x,_outside_position.y,_outside_position.z],"authored_not_surveyed":true,"notice":_notice,
		"catalog_count":catalog.size(),"floor_count":current_spec.get("floor_count",0),"current_floor":_current_destination() if active else 0,"width":current_spec.get("width",0.),"depth":current_spec.get("depth",0.),
		"in_elevator":in_elevator,"elevator_open":elevator_open,"selected_floor":selected_floor,"elevator":elevator_snapshot(),"on_roof":on_roof,"rooftop":rooftop.snapshot() if is_instance_valid(rooftop) else {},"roof_ready_tick":_roof_ready_tick,"facility_activity":facility_interaction.snapshot() if is_instance_valid(facility_interaction) else {}}

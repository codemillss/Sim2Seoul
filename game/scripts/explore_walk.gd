extends "res://scripts/v0_walk.gd"
## Optional exploration controls on a separate leaf; prior milestones stay fixed.
const SPEED_IDS := ["realistic", "brisk", "fast", "rapid", "turbo"]
const TIME_IDS := ["day", "evening", "night"]
const TIME_LABELS := ["낮", "해질녘", "밤"]
const SPEED_PROFILES := {
	"realistic": {"label": "현실 속도", "walk": 1.4, "run": 3.5},
	"brisk": {"label": "빠르게", "walk": 2.24, "run": 5.6},
	"fast": {"label": "아주 빠르게", "walk": 2.8, "run": 7.0},
	"rapid": {"label": "쾌속 (2배)", "walk": 5.6, "run": 14.0},
	"turbo": {"label": "초고속 (3배)", "walk": 8.4, "run": 21.0},
}

@export var exploration_settings_path := "user://sim2seoul_exploration.json"
# This growing exploration scene uses30Hz fixed physics on the M1 baseline.
# Rendering remains independent; validation may explicitly request60Hz stress.
@export var exploration_physics_hz: int=30
var speed_id := "brisk"
var free_roam_enabled := true
var exploration_settings_recovered := false
var exploration_error := ""
var exploration_overlay: Node3D
var speed_option: OptionButton
var free_roam_switch: CheckButton
var exploration_description: Label
var exploration_notice: Label
var exploration_menu_scroll: ScrollContainer
var exploration_menu_content: VBoxContainer
var menu_layout_pending := false
var seoul_identity: Node3D
var building_names: Node
var exploration_traffic: Node
var photo_civic_detail: Node3D
var photo_palace_detail: Node3D
var photo_wall_detail: Node3D
var photo_atmosphere: Node3D
var interior_visit: Node3D
var exploration_avatar: Node3D
var street_businesses: Node3D
var street_life: Node3D
var museum_approach: Node3D
var time_id := "day"
var time_option: OptionButton
var street_curbs: Node3D
var street_pedestrians: Node3D
var exploration_pedestrians: Node3D
var exploration_rooftop_access: Node3D
var neighborhood_life: Node3D
var building_type_identity: Node3D
var interior_room_access: Node3D
var building_exterior_identity: Node3D
var neighborhood_greenery: Node3D
var neighborhood_population: Node3D
var terrain_surface: Node3D
var terrain_binding: RefCounted
var street_network_detail: Node3D
var city_bus_service: Node3D
var city_bike_service: Node3D

func _ready() -> void:
	assert(exploration_physics_hz in [30,60])
	Engine.physics_ticks_per_second=exploration_physics_hz
	# Runtime binding belongs to this scene; historical project input stays fixed.
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var key:=InputEventKey.new();key.physical_keycode=KEY_SPACE
		InputMap.action_add_event("jump",key)
	super._ready()
	if not runtime_ok:return
	exploration_overlay=preload("res://scripts/exploration_overlay.gd").new()
	exploration_overlay.name="ExplorationOverlay"
	add_child(exploration_overlay)
	if not exploration_overlay.setup(city,player):
		_exploration_failure("자유 탐험을 준비하지 못했습니다. 다시 실행해주세요.")
		return
	player.free_roam_bounds=exploration_overlay.bounds
	var saved:=_read_exploration_settings()
	if not set_speed_profile(saved.speed_id):
		_exploration_failure("이동 속도를 준비하지 못했습니다.")
		return
	set_free_roam(saved.free_roam)
	if not exploration_error.is_empty():return
	exploration_avatar=preload("res://scripts/player/exploration_avatar.gd").new()
	exploration_avatar.name="ExplorationAvatar"
	player.get_node("Visual").add_child(exploration_avatar)
	if not exploration_avatar.setup(player):
		_exploration_failure("탐험 캐릭터와 걷기 동작을 준비하지 못했습니다.");return
	if exploration_settings_recovered:
		exploration_notice.text="저장된 탐험 설정을 읽지 못해 기본으로 시작했습니다."
		_save_exploration_settings()
	seoul_identity=preload("res://scripts/seoul_identity.gd").new()
	seoul_identity.name="SeoulIdentity";add_child(seoul_identity)
	if not seoul_identity.setup(city,self):
		_exploration_failure("덕수궁과 시청 외형을 준비하지 못했습니다.")
		return
	photo_civic_detail=preload("res://scripts/photo_civic_detail.gd").new()
	photo_civic_detail.name="PhotoCivicDetail";add_child(photo_civic_detail)
	if not photo_civic_detail.setup(self):
		_exploration_failure("시청과 서울도서관의 사진 참고 외형을 준비하지 못했습니다.");return
	photo_palace_detail=preload("res://scripts/photo_palace_detail.gd").new()
	photo_palace_detail.name="PhotoPalaceDetail";add_child(photo_palace_detail)
	if not photo_palace_detail.setup(self):
		_exploration_failure("덕수궁의 사진 참고 외형을 준비하지 못했습니다.");return
	photo_wall_detail=preload("res://scripts/photo_wall_detail.gd").new()
	photo_wall_detail.name="PhotoWallDetail";add_child(photo_wall_detail)
	if not photo_wall_detail.setup(self):
		_exploration_failure("돌담 기와 표현을 준비하지 못했습니다.");return
	photo_atmosphere=preload("res://scripts/photo_atmosphere.gd").new()
	photo_atmosphere.name="PhotoAtmosphere";add_child(photo_atmosphere)
	if not photo_atmosphere.setup(self):
		_exploration_failure("야외 조명과 바닥 재질을 준비하지 못했습니다.");return
	building_names=preload("res://scripts/building_names.gd").new()
	building_names.name="BuildingNames";add_child(building_names)
	if not building_names.setup(self):
		_exploration_failure("건물 이름을 준비하지 못했습니다.")
		return
	exploration_traffic=preload("res://scripts/exploration_traffic.gd").new()
	exploration_traffic.name="ExplorationTraffic";add_child(exploration_traffic)
	if not exploration_traffic.setup(self):
		_exploration_failure("도로 위 차량을 준비하지 못했습니다.")
		return
	interior_visit=preload("res://scripts/interior_visit.gd").new()
	interior_visit.name="InteriorVisit"
	interior_visit.entrance_world_position=photo_civic_detail.entrance_world_position
	interior_visit.entrance_world_position.y=0.08
	interior_visit.entrance_outward_direction=photo_civic_detail.entrance_outward_direction
	interior_visit.door_world_position=photo_civic_detail.door_world_position
	add_child(interior_visit)
	if not interior_visit.setup(self):
		_exploration_failure("건물 내부와 출입구를 준비하지 못했습니다.");return
	interior_room_access=preload("res://scripts/interior_room_access.gd").new();add_child(interior_room_access)
	if not interior_room_access.setup(self,interior_visit):
		_exploration_failure("객실 출입을 준비하지 못했습니다.");return
	exploration_rooftop_access=preload("res://scripts/exploration_rooftop_access.gd").new()
	exploration_rooftop_access.name="ExplorationRooftopAccess";add_child(exploration_rooftop_access)
	if not exploration_rooftop_access.setup(self,interior_visit):
		_exploration_failure("직접 접근할 수 있는 옥상을 준비하지 못했습니다.");return
	street_businesses=preload("res://scripts/street_businesses.gd").new()
	add_child(street_businesses)
	if not street_businesses.setup(city,player,rig):
		_exploration_failure("거리의 음식점과 편의점을 준비하지 못했습니다.");return
	museum_approach=preload("res://scripts/museum_approach.gd").new()
	add_child(museum_approach)
	if not museum_approach.setup(city,player,rig):
		_exploration_failure("미술관 언덕 진입로를 준비하지 못했습니다.");return
	street_life=preload("res://scripts/street_life.gd").new()
	add_child(street_life)
	if not street_life.setup(city,player,rig):
		_exploration_failure("돌담길의 사람과 새, 가로등을 준비하지 못했습니다.");return
	street_life.apply_quality(quality_id)
	street_curbs=preload("res://scripts/street_curbs.gd").new()
	add_child(street_curbs)
	if not street_curbs.setup(city,player,rig):
		_exploration_failure("보도와 차도의 경계석을 준비하지 못했습니다.");return
	street_pedestrians=preload("res://scripts/street_pedestrians.gd").new()
	add_child(street_pedestrians)
	if not street_pedestrians.setup(city,player,rig):
		_exploration_failure("산책하는 사람과 반려견을 준비하지 못했습니다.");return
	street_pedestrians.set_running(pedestrians_running)
	exploration_pedestrians=preload("res://scripts/exploration_pedestrian_avoidance.gd").new()
	add_child(exploration_pedestrians)
	if not exploration_pedestrians.setup(city,player,pedestrians,street_pedestrians):
		_exploration_failure("보행자의 비켜 지나가기를 준비하지 못했습니다.");return
	exploration_pedestrians.set_running(pedestrians_running)
	neighborhood_life=preload("res://scripts/neighborhood_life.gd").new();add_child(neighborhood_life)
	if not neighborhood_life.setup(self):
		_exploration_failure("대기 줄·피크닉·거리 안내를 준비하지 못했습니다.");return
	building_type_identity=preload("res://scripts/building_type_identity.gd").new();add_child(building_type_identity)
	if not building_type_identity.setup(self):
		_exploration_failure("교회와 호텔의 특징을 준비하지 못했습니다.");return
	building_exterior_identity=preload("res://scripts/building_exterior_identity.gd").new();add_child(building_exterior_identity)
	if not building_exterior_identity.setup(self):
		_exploration_failure("건물별 외관을 준비하지 못했습니다.");return
	neighborhood_greenery=preload("res://scripts/neighborhood_greenery.gd").new();add_child(neighborhood_greenery)
	if not neighborhood_greenery.setup(self):
		_exploration_failure("거리의 가로수를 준비하지 못했습니다.");return
	neighborhood_population=preload("res://scripts/neighborhood_population.gd").new();add_child(neighborhood_population)
	if not neighborhood_population.setup(self):
		_exploration_failure("거리 전반의 보행과 차량을 준비하지 못했습니다.");return
	neighborhood_population.set_people_running(pedestrians_running)
	terrain_surface=preload("res://scripts/terrain_surface.gd").new();terrain_surface.name="TerrainSurface";add_child(terrain_surface)
	if not terrain_surface.prepare():
		_exploration_failure("권역 지형을 준비하지 못했습니다. 지형 준비 도구를 확인해주세요.");return
	terrain_binding=preload("res://scripts/terrain_scene_binding.gd").new()
	if not terrain_binding.apply(self,terrain_surface):
		_exploration_failure("도로·건물·출입구 지형 연결을 완료하지 못했습니다.");return
	# New street props use the already-committed physical terrain once.
	street_network_detail=preload("res://scripts/street_network_detail.gd").new();add_child(street_network_detail)
	if not street_network_detail.setup(self):
		_exploration_failure("차선·횡단보도·신호등과 가로등을 준비하지 못했습니다.");return
	street_network_detail.apply_quality(quality_id)
	city_bus_service=preload("res://scripts/city_bus_service.gd").new();add_child(city_bus_service)
	if not city_bus_service.setup(self):
		_exploration_failure("버스와 정류장을 준비하지 못했습니다.");return
	city_bus_service.set_running(traffic_switch.button_pressed if is_instance_valid(traffic_switch) else true)
	city_bike_service=preload("res://scripts/city_bike_service.gd").new();add_child(city_bike_service)
	if not city_bike_service.setup(self):
		_exploration_failure("자전거와 대여소를 준비하지 못했습니다.");return
	set_time_profile(_read_street_time())
	_layout_v0.call_deferred()
	print("EXPLORATION_READY speed=",speed_id," free_roam=",free_roam_enabled," time=",time_id)

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="덕수궁 · 시청 · 돌담길 자유 탐험\nWASD / 방향키 이동 · Shift 달리기 · Space 점프 · 공중에서도 연속 점프\n마우스 회전 · 휠 거리 조절 · E 출입 / 엘리베이터 / 시설 사용 · Esc 메뉴"
	var options:=menu.get_child(0) as VBoxContainer
	var quit_action: Button
	for child in options.get_children():
		if child is Button and child.text=="종료":quit_action=child
	options.add_child(HSeparator.new())
	free_roam_switch=CheckButton.new()
	free_roam_switch.name="FreeRoam"
	free_roam_switch.text="자유 탐험 · 잔디와 도로까지"
	free_roam_switch.tooltip_text="끄면 산책길 안에서 이동합니다. 길 밖에 있으면 대한문 밖으로 돌아갑니다."
	free_roam_switch.set_pressed_no_signal(true)
	for color_name in ["font_color","font_hover_color","font_pressed_color"]:
		free_roam_switch.add_theme_color_override(color_name,Color(.08,.12,.16))
	free_roam_switch.toggled.connect(_free_roam_selected)
	options.add_child(free_roam_switch)
	var speed_row:=HBoxContainer.new()
	var caption:=Label.new();caption.text="이동 속도"
	caption.add_theme_color_override("font_color",Color(.08,.12,.16))
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	speed_row.add_child(caption)
	speed_option=OptionButton.new();speed_option.name="ExplorationSpeed"
	for id in SPEED_IDS:speed_option.add_item(SPEED_PROFILES[id].label)
	speed_option.select(SPEED_IDS.find(speed_id))
	speed_option.custom_minimum_size=Vector2(150,32)
	speed_option.item_selected.connect(_speed_selected)
	speed_row.add_child(speed_option);options.add_child(speed_row)
	var time_row:=HBoxContainer.new()
	var time_caption:=Label.new();time_caption.text="시간대"
	time_caption.add_theme_color_override("font_color",Color(.08,.12,.16))
	time_caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	time_row.add_child(time_caption)
	time_option=OptionButton.new();time_option.name="StreetTime"
	for title in TIME_LABELS:time_option.add_item(title)
	time_option.custom_minimum_size=Vector2(150,32)
	time_option.item_selected.connect(_time_selected)
	time_row.add_child(time_option);options.add_child(time_row)
	exploration_description=Label.new()
	exploration_description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	exploration_description.add_theme_font_size_override("font_size",13)
	exploration_description.add_theme_color_override("font_color",Color(.08,.12,.16))
	options.add_child(exploration_description)
	exploration_notice=Label.new()
	exploration_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	exploration_notice.add_theme_font_size_override("font_size",13)
	exploration_notice.add_theme_color_override("font_color",Color(.35,.15,.07))
	options.add_child(exploration_notice)
	var admin_switch:=CheckButton.new();admin_switch.name="AdministratorAccess";admin_switch.text="관리자 모드 · 객실 마스터키";admin_switch.set_pressed_no_signal(true)
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
		admin_switch.add_theme_color_override(color_name,Color(.08,.12,.16))
	admin_switch.toggled.connect(func(enabled: bool):
		if is_instance_valid(interior_room_access):interior_room_access.set_admin_access(enabled))
	options.add_child(admin_switch)
	var music_switch:=CheckButton.new();music_switch.name="BuskingMusic";music_switch.text="버스킹 기타 음악";music_switch.set_pressed_no_signal(true)
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
		music_switch.add_theme_color_override(color_name,Color(.08,.12,.16))
	music_switch.toggled.connect(func(enabled: bool):
		if is_instance_valid(neighborhood_life):neighborhood_life.set_music_enabled(enabled))
	options.add_child(music_switch)
	var library_shortcut := Button.new();library_shortcut.text = "서울도서관 정문으로 이동"
	library_shortcut.pressed.connect(_visit_library_entrance);options.add_child(library_shortcut)
	for detail in [["진주회관 앞 거리로 이동","restaurant"],["돌담길 버스킹으로 이동","busking"],["미술관 언덕 입구로 이동","hill"],["반려견 산책 구간으로 이동","dog_walk"],["호텔 야외 수영장으로 이동","hotel_pool"],["서울광장 피크닉으로 이동","picnic"],["성공회교회당 앞으로 이동","church"],["다음 거리 산책 지점으로 이동","street_walk"],["버스 정류장으로 이동","bus_stop"],["신호등·횡단보도로 이동","crossing"],["가로등 거리로 이동","street_lamps"],["자전거 대여소로 이동","bike_station"]]:
		var shortcut:=Button.new();shortcut.text=detail[0]
		shortcut.pressed.connect(_visit_street_detail.bind(detail[1]));options.add_child(shortcut)
	if quit_action!=null:options.move_child(quit_action,options.get_child_count()-1)
	# Keep every control reachable when the game window is shorter than the menu.
	exploration_menu_content=options
	menu.remove_child(options)
	exploration_menu_scroll=ScrollContainer.new()
	exploration_menu_scroll.name="ExplorationOptionsScroll"
	exploration_menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	exploration_menu_scroll.follow_focus=true
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	menu.add_child(exploration_menu_scroll)
	exploration_menu_scroll.add_child(options)
	options.minimum_size_changed.connect(_queue_menu_layout)
	_update_exploration_description()

func _visit_library_entrance() -> void:
	var was_riding: bool=_street_transport_riding()
	if is_instance_valid(interior_visit) and interior_visit.go_to_library_entrance():
		_cancel_bus_after_teleport()
		if was_riding:interior_visit._orient(atan2(interior_visit.entrance_outward_direction.x,interior_visit.entrance_outward_direction.z),deg_to_rad(-15.),4.5)
		if menu.visible:toggle_menu()

func set_time_profile(id: String) -> bool:
	if id not in TIME_IDS:return false
	if is_instance_valid(photo_atmosphere) and not photo_atmosphere.set_time_profile(id):return false
	if is_instance_valid(street_life) and not street_life.set_time_profile(id):return false
	if is_instance_valid(street_network_detail):street_network_detail.set_time_profile(id)
	if is_instance_valid(neighborhood_life) and not neighborhood_life.set_time_profile(id):return false
	time_id=id
	if is_instance_valid(time_option):time_option.select(TIME_IDS.find(id))
	return true

func _read_street_time() -> String:
	var path:=exploration_settings_path+".time.json"
	if not FileAccess.file_exists(path):return "day"
	var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if saved is Dictionary and saved.size()==2 and _number(saved.get("schema_version")) and saved.schema_version==1 and saved.get("time_id") is String and saved.time_id in TIME_IDS:return saved.time_id
	return "day"

func _time_selected(index: int) -> void:
	if index<0 or index>=TIME_IDS.size() or not set_time_profile(TIME_IDS[index]):return
	var file:=FileAccess.open(exploration_settings_path+".time.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"schema_version":1,"time_id":time_id})+"\n");file.close()
	else:exploration_notice.text="시간대를 저장하지 못했습니다. 이번 실행에는 적용됩니다."

var street_walk_index: int=0

func _visit_street_detail(kind: String) -> void:
	if not is_instance_valid(interior_visit) or kind not in ["restaurant","busking","hill","dog_walk","hotel_pool","picnic","church","street_walk","bus_stop","crossing","street_lamps","bike_station"]:return
	if interior_visit.active and not interior_visit.return_to_world_spawn():return
	if kind=="hotel_pool":
		var destination: Dictionary=exploration_rooftop_access.representative_pool_destination()
		if destination.is_empty() or not _roof_destination_clear(destination):
			exploration_notice.text="수영장 입구가 잠시 막혀 있습니다. 조금 뒤 다시 찾아주세요.";return
		_commit_exploration_teleport(destination.pool_entry)
		player.velocity=Vector3.ZERO;player.require_neutral_input();player.reset_physics_interpolation()
		# Look straight through the gate. An eight-metre diagonal orbit crossed
		# its upright and collapsed the camera into the player's hidden range.
		var forward: Vector3=-destination.roof.frame.basis.z
		rig.yaw=atan2(-forward.x,-forward.z);rig.pitch=deg_to_rad(-18.);rig.requested_distance=4.;rig.current_distance=4.;rig.snap_to_target_pose()
		if menu.visible:toggle_menu()
		return
	var requested:=Vector3.ZERO;var toward:=Vector3.ZERO
	if kind=="bike_station" and is_instance_valid(city_bike_service):
		var destination: Dictionary=city_bike_service.viewpoint()
		if destination.is_empty():return
		requested=destination.point;toward=destination.toward
	elif kind=="bus_stop" and is_instance_valid(city_bus_service):
		var destination: Dictionary=city_bus_service.viewpoint()
		if destination.is_empty():return
		requested=destination.point;toward=destination.toward
	elif kind in ["crossing","street_lamps"] and is_instance_valid(street_network_detail):
		var destination: Dictionary=street_network_detail.destination("crossing" if kind=="crossing" else "lamps")
		if destination.is_empty():return
		requested=destination.point;toward=destination.toward
	elif kind=="street_walk" and is_instance_valid(neighborhood_population):
		var points: Array=neighborhood_population.coverage_viewpoints()
		if points.is_empty():return
		var destination: Dictionary=points[street_walk_index%points.size()]
		street_walk_index+=1
		requested=destination.point;toward=destination.toward
	elif kind=="church":
		var destination: Dictionary=building_type_identity.destination()
		if destination.is_empty():return
		requested=destination.point;toward=destination.toward
	elif kind=="picnic" and not neighborhood_life.picnics.is_empty():
		toward=neighborhood_life.picnics[0].global_position;requested=toward+Vector3(0,0,4)
	elif kind=="restaurant" and is_instance_valid(street_businesses):
		for store: Dictionary in street_businesses.stores:
			if String(store.record.style)!="restaurant":continue
			var node: Node3D=store.node
			toward=node.global_position;requested=toward+node.global_basis.z*3.8;break
	elif kind=="busking" and is_instance_valid(street_life):
		for person: Dictionary in street_life.performers:
			if person.kind!="busker":continue
			var node: Node3D=person.actor
			toward=node.global_position;requested=toward-node.global_basis.z*3.0;break
	elif kind=="hill" and is_instance_valid(museum_approach):
		requested=museum_approach.point_at_station(2.0)+Vector3.UP*.08
		toward=museum_approach.point_at_station(10.0)
	elif kind=="dog_walk" and is_instance_valid(street_pedestrians):
		var destination: Dictionary=_dog_walk_viewpoint()
		if destination.is_empty():
			exploration_notice.text="산책 구간의 자리가 잠시 막혀 있습니다. 조금 뒤 다시 찾아주세요.";return
		requested=destination.point;toward=destination.toward
		street_pedestrians.pause_for_view(destination.group_id,5.5)
	if requested==Vector3.ZERO:return
	var safe: Dictionary=_exploration_destination(requested)
	if safe.is_empty():exploration_notice.text="이동할 곳이 막혀 있습니다. 주변에서 걸어서 접근해주세요.";return
	_commit_exploration_teleport(safe.point)
	player.require_neutral_input();player.reset_physics_interpolation()
	var direction: Vector3=toward-safe.point;direction.y=0
	player.get_node("Visual").rotation.y=atan2(-direction.x,-direction.z)
	rig.reset_orientation();rig.yaw=atan2(-direction.x,-direction.z);rig.pitch=deg_to_rad(-15.)
	rig.requested_distance=4.5;rig.current_distance=4.5;rig.snap_to_target_pose()
	if menu.visible:toggle_menu()

func _dog_walk_viewpoint() -> Dictionary:
	for group: Dictionary in street_pedestrians.groups:
		if not group.record.dog:continue
		var keeper: CharacterBody3D=group.members[0].body
		var dog: CharacterBody3D=group.members[1].body
		var center: Vector3=keeper.global_position.lerp(dog.global_position,.5)
		var forward: Vector3=street_pedestrians._tangent(group,group.station)*float(group.direction)
		var side:=Vector3(forward.z,0,-forward.x)
		for offset: Vector3 in [-forward*2.4+side*2.8,-forward*2.4-side*2.8,forward*2.4+side*2.8,forward*2.4-side*2.8]:
			var safe: Dictionary=_exploration_destination(center+offset)
			if safe.is_empty():continue
			var blocked:=false
			for subject: Vector3 in [keeper.global_position+Vector3.UP*1.0,dog.global_position+Vector3.UP*.4]:
				var ray:=PhysicsRayQueryParameters3D.create(safe.point+Vector3.UP*1.3,subject,1|32,[player.get_rid()])
				if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():blocked=true
			if blocked:continue
			# Keep both actors beside the player's shoulder in the regular camera.
			var toward: Vector3=center+forward*2.6
			var direction: Vector3=toward-safe.point;direction.y=0.;direction=direction.normalized()
			var query:=PhysicsShapeQueryParameters3D.new();query.shape=rig.arm.shape;query.collision_mask=rig.arm.collision_mask;query.exclude=[player.get_rid()]
			query.transform=Transform3D(Basis.IDENTITY,safe.point+Vector3.UP*rig.pivot_height_m)
			query.motion=-direction*4.1+Vector3.UP*1.1
			if get_world_3d().direct_space_state.cast_motion(query)[0]<.68:continue
			return {"point":safe.point,"toward":toward,"group_id":group.id,"keeper":keeper.global_position,"dog":dog.global_position}
	return {}

func _exploration_destination(requested: Vector3) -> Dictionary:
	# Synchronous prospective query: no actor tick advances with these flags.
	# Failed menu destinations leave both the passenger and original mode intact.
	var old_mode: bool=player.free_roam_enabled
	var old_mask: int=player.collision_mask
	player.free_roam_enabled=true;player.collision_mask=old_mask|32
	var safe: Dictionary=interior_visit._safe_external_point(requested)
	player.free_roam_enabled=old_mode;player.collision_mask=old_mask
	return safe

func _roof_destination_clear(destination: Dictionary) -> bool:
	var roof: Node3D=destination.get("roof")
	var point: Vector3=destination.get("pool_entry",Vector3(INF,INF,INF))
	if not is_instance_valid(roof) or not point.is_finite():return false
	var local: Vector3=roof.frame.affine_inverse()*point
	if not roof.walkable_rect.grow(-.3).has_point(Vector2(local.x,local.z)):return false
	if not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),exploration_overlay.polygon):return false
	var capsule: CollisionShape3D=player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.collision_mask=player.collision_mask|32;query.exclude=[player.get_rid()]
	query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;query.margin=.001
	var space:=get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.35,point-Vector3.UP*.4,query.collision_mask,[player.get_rid()]))
	return not hit.is_empty() and hit.normal.y>.7 and absf(point.y-hit.position.y)<.2

func _commit_exploration_teleport(point: Vector3) -> void:
	player.global_transform=Transform3D(Basis.IDENTITY,point)
	_cancel_bus_after_teleport()
	if not free_roam_enabled:set_free_roam(true)


func _street_transport_riding() -> bool:
	return (is_instance_valid(city_bus_service) and city_bus_service.riding) or (is_instance_valid(city_bike_service) and city_bike_service.riding)

func _cancel_bus_after_teleport() -> void:
	# Shared transport cleanup runs only after a validated destination is applied.
	if is_instance_valid(city_bike_service) and city_bike_service.riding:city_bike_service.cancel_ride_for_teleport()
	if is_instance_valid(city_bus_service) and city_bus_service.riding:city_bus_service.cancel_ride_for_teleport()

func try_street_interact() -> bool:
	# Existing fresh-E dispatcher remains the sole owner of street interactions.
	for service: Node3D in [city_bike_service,city_bus_service]:
		if is_instance_valid(service) and service.loaded and service.riding:
			service.handle_interact();return true
	for service: Node3D in [city_bike_service,city_bus_service]:
		if is_instance_valid(service) and service.loaded and service.can_interact():return service.handle_interact()
	return false

func street_interaction_hint() -> String:
	for service: Node3D in [city_bike_service,city_bus_service]:
		if is_instance_valid(service) and service.loaded and service.riding:return service.prompt_text()
	for service: Node3D in [city_bike_service,city_bus_service]:
		if is_instance_valid(service) and service.loaded:
			var hint: String=service.prompt_text()
			if not hint.is_empty():return hint
	return ""

func set_pedestrians_running(enabled: bool) -> void:
	super.set_pedestrians_running(enabled)
	if is_instance_valid(street_pedestrians):street_pedestrians.set_running(enabled)
	if is_instance_valid(exploration_pedestrians):exploration_pedestrians.set_running(enabled)
	if is_instance_valid(neighborhood_population):neighborhood_population.set_people_running(enabled)

func set_vehicles_running(enabled: bool) -> void:
	super.set_vehicles_running(enabled)
	if is_instance_valid(neighborhood_population):neighborhood_population.set_vehicles_running(enabled)
	if is_instance_valid(city_bus_service):city_bus_service.set_running(enabled)

func _queue_menu_layout() -> void:
	if menu_layout_pending:return
	menu_layout_pending=true
	_fit_menu.call_deferred()

func _fit_menu() -> void:
	menu_layout_pending=false
	_layout_v0()

func _layout_v0() -> void:
	super._layout_v0()
	if not is_instance_valid(exploration_menu_content):return
	var view:=get_viewport().get_visible_rect().size
	var padding:=menu.get_theme_stylebox("panel").get_minimum_size()
	var wanted_height:=exploration_menu_content.get_combined_minimum_size().y+padding.y
	menu.size=Vector2(minf(440.,view.x-32.),minf(wanted_height,view.y-32.))
	menu.position=Vector2(maxf(16.,(view.x-menu.size.x)/2.),maxf(16.,(view.y-menu.size.y)/2.))

func _exploration_failure(message: String) -> void:
	exploration_error=message;runtime_ok=false
	input_router.gameplay_enabled=false;rig.set_capture(false)
	status.text=message;exploration_notice.text=message
	free_roam_switch.disabled=true;speed_option.disabled=true
	push_error(message)

func apply_quality(id: String) -> bool:
	if not super.apply_quality(id):return false
	if rig.has_method("apply_exploration_view_distance"):rig.apply_exploration_view_distance()
	if is_instance_valid(photo_atmosphere):photo_atmosphere.apply_quality(id)
	if is_instance_valid(street_life):street_life.apply_quality(id)
	if is_instance_valid(street_network_detail):street_network_detail.apply_quality(id)
	return true

func _read_exploration_settings() -> Dictionary:
	var defaults:={"schema_version":1,"speed_id":"brisk","free_roam":true}
	if not FileAccess.file_exists(exploration_settings_path):return defaults
	var saved=_json_object(exploration_settings_path)
	if saved is Dictionary and saved.size()==3 and _number(saved.get("schema_version")) and saved.schema_version==1 and saved.get("speed_id") is String and saved.speed_id in SPEED_IDS and saved.get("free_roam") is bool:
		return saved
	exploration_settings_recovered=true
	return defaults

func set_speed_profile(id: String) -> bool:
	if not SPEED_PROFILES.has(id):return false
	var profile: Dictionary=SPEED_PROFILES[id]
	player.walk_speed_mps=profile.walk;player.run_speed_mps=profile.run
	speed_id=id
	if is_instance_valid(speed_option):speed_option.select(SPEED_IDS.find(id))
	player.require_neutral_input()
	_update_exploration_description()
	return true

func set_free_roam(enabled: bool) -> void:
	if _street_transport_riding():
		free_roam_switch.set_pressed_no_signal(free_roam_enabled)
		exploration_notice.text="버스나 자전거에서 내린 뒤 탐험 범위를 바꿀 수 있습니다.";return
	if not is_instance_valid(exploration_overlay):return
	if not enabled and is_instance_valid(interior_visit) and interior_visit.active and interior_visit.on_roof and not player.interior_active:
		# A roof visitor has already rejoined the outdoor world. Do not switch
		# its boundary underneath an active lift session or an airborne player.
		if is_instance_valid(free_roam_switch):free_roam_switch.set_pressed_no_signal(true)
		if is_instance_valid(exploration_notice):exploration_notice.text="옥상에서는 자유 탐험을 유지합니다. 승강기로 내려온 뒤 산책길 모드로 바꿀 수 있습니다."
		return
	var previous:=free_roam_enabled
	player.free_roam_enabled=enabled
	exploration_overlay.set_enabled(enabled)
	if not enabled and (interior_visit==null or not interior_visit.active) and not city.movement_contains(Vector2(player.global_position.x,player.global_position.z)):
		if not player.recover("free_roam_disabled"):
			player.free_roam_enabled=previous
			exploration_overlay.set_enabled(previous)
			free_roam_switch.set_pressed_no_signal(previous)
			exploration_notice.text="시작점으로 돌아갈 수 없어 현재 탐험 범위를 유지합니다."
			return
	free_roam_enabled=enabled
	free_roam_switch.set_pressed_no_signal(enabled)
	player.require_neutral_input()
	_update_exploration_description()

func _update_exploration_description() -> void:
	if not is_instance_valid(exploration_description):return
	var profile: Dictionary=SPEED_PROFILES[speed_id]
	exploration_description.text="걷기 %.2f · 달리기 %.1f m/s\n%s"%[profile.walk,profile.run,"잔디·도로를 자유롭게 탐험합니다. 출입 표지가 있는 건물 정문에서 E로 들어갑니다." if free_roam_enabled else "기존 산책길 안에서 이동합니다."]
	_layout_v0.call_deferred()

func _speed_selected(index: int) -> void:
	if index<0 or index>=SPEED_IDS.size():return
	exploration_notice.text=""
	if set_speed_profile(SPEED_IDS[index]):_save_exploration_settings()

func _free_roam_selected(enabled: bool) -> void:
	exploration_notice.text=""
	set_free_roam(enabled)
	_save_exploration_settings()

func _save_exploration_settings() -> void:
	var file:=FileAccess.open(exploration_settings_path,FileAccess.WRITE)
	if file==null:
		exploration_notice.text="탐험 설정을 저장하지 못했습니다. 이번 실행에는 적용됩니다."
		return
	file.store_string(JSON.stringify({"schema_version":1,"speed_id":speed_id,"free_roam":free_roam_enabled})+"\n")
	file.close()

func exploration_snapshot() -> Dictionary:
	return {"speed_id":speed_id,"walk_speed_mps":player.walk_speed_mps,"run_speed_mps":player.run_speed_mps,
		"free_roam":free_roam_enabled,"settings_recovered":exploration_settings_recovered,
		"settings_path":exploration_settings_path,"runtime_ok":runtime_ok,"error":exploration_error,"time_id":time_id}

func _select_source_document(index: int) -> void:
	super._select_source_document(index)
	if index==0:
		sources_text.text=sources_text.text.replace("실내·계단·잔디는 탐험 범위에서 제외합니다.","출입 표지가 있는 건물은 실내·계단·엘리베이터로 여러 층을 탐험할 수 있습니다. 자유 탐험을 켜면 잔디와 도로에서도 이동할 수 있습니다.")
		sources_text.text+="\n\n[b]이번 자유 탐험[/b]\n자유 탐험을 켜면 잔디와 도로까지 이동할 수 있습니다. 넓힌 바닥과 세부 외형은 탐험을 위한 표현이며 실제 현장의 지형·출입 가능 여부를 뜻하지 않습니다. 출입 표지가 있는 건물 정문에서 E로 들어갑니다. 실내 크기는 원본 건물 외곽 안에 맞췄으며, 층수는 OSM 원문 또는 높이 추정에 따릅니다. 방 배치·계단·엘리베이터와 실내 보행자는 게임용 재구성입니다. 작은 건물·사유지·일부 역사 건축물의 실내는 제외합니다. 석재 텍스처는 AI로 새로 제작했으며 공식 참조 사진 자체는 게임에 포함하지 않았습니다."
		sources_text.text+="\n\n[b]거리와 지형[/b]\n진주회관과 편의점 외관은 공식 장소 정보·OSM 스냅샷을 바탕으로 단순화했습니다. 현재 입점·정확한 점포 단위나 새 실내 출입을 확인한 표현은 아닙니다. 주차 차량·오토바이·새·버스킹·가로등 위치와 낮/해질녘/밤은 게임 창작입니다. 권역 지형은 서울시 공개 등고선·표고점을 보간하고 건물 기초를 게임용으로 평탄화했습니다. 도로·출입구·보행자·차량은 같은 지면에 연결했습니다. 실측 DEM·정문 높이·절대 해발고도의 정확도를 보증하지 않으며, 미술관의 이전 임의3m 경사는 제거했습니다."
		sources_text.text+="\n낮은 경계석/보도 띠와 산책하는 사람6명·반려견2마리는 기존 게임 도로/보행 공간에 더한 창작입니다. 실제 연석 위치·유동 인구나 동물 행동을 조사한 재현은 아닙니다. 기존 보행·횡단·입구를 비워 두며 보행자 이동 설정으로 산책을 멈출 수 있습니다."
		sources_text.text+="\n\n[b]거리 교통과 산책 보강[/b]\n차선·횡단보도·정지선은 기존 도로 안의 게임 표현입니다. 차량/보행 신호의 주기는 게임용이며 실제 서울 신호 운영이 아닙니다. 가로등 외형은 서울시 시설 사진을 참고했습니다. 도심01 버스의 두 정류장·짧은 운행과 도착 예상은 게임 구성으로 실제 버스 노선·실시간 도착을 복원하지 않습니다. 버스는 정차한 열린 문에서 E로 타고, 탑승 중 E로 다음 정류장 하차를 예약합니다. 반려견의 관절·발 디딤·주변 보기·냄새 맡기는 게임 동작이며 실제 동물 행동을 측정한 모델은 아닙니다. 녹색 공공자전거와 대여소는 따릉이 외형을 참고한 게임 체험이며 실제 대여·결제·실시간 재고와 연결되지 않습니다."

func _height_above_terrain(point: Vector3) -> float:
	if is_instance_valid(terrain_surface) and terrain_surface.loaded:
		var floor_y: float=terrain_surface.ground_y_world(point)
		if is_finite(floor_y):return point.y-floor_y
	return point.y

func _process(delta: float) -> void:
	super._process(delta)
	if not runtime_ok:return
	if is_instance_valid(city_bike_service) and city_bike_service.riding:
		status.text="자전거 탑승 중 · W 가속 · S/Space 제동 · A/D 조향 · E 내리기/반납"
	elif is_instance_valid(city_bus_service) and city_bus_service.riding:
		status.text="버스 탑승 중 · E · 다음 정류장 하차 예약"
	elif is_instance_valid(interior_visit) and interior_visit.active:
		status.text=interior_visit.status_text()
	elif not player.interior_active and _height_above_terrain(player.global_position)>6.0:
		var roof: Node3D=exploration_rooftop_access.active_outdoor_roof if is_instance_valid(exploration_rooftop_access) else null
		if is_instance_valid(roof):
			status.text=String(roof.spec.title)+" · 옥상 야외 수영장\nWASD 이동 / 수영 · Space 점프 / 물 밖으로 · 옥상 승강장 E"
		else:status.text="공중 · 옥상 탐험 · Space 연속 점프 · WASD 이동"
	else:
		status.text+=" · %s · %s"%["자유 탐험" if free_roam_enabled else "산책길",SPEED_PROFILES[speed_id].label]

func reset_player() -> void:
	if is_instance_valid(interior_visit) and interior_visit.active:
		interior_visit.return_to_world_spawn()
	else:
		var before: Vector3=player.global_position
		super.reset_player()
		if player.global_position.distance_to(before)>.05:_cancel_bus_after_teleport()

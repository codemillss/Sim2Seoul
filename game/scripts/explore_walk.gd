extends "res://scripts/v0_walk.gd"
## Optional exploration controls on a separate leaf; prior milestones stay fixed.
const SPEED_IDS := ["realistic", "brisk", "fast", "rapid", "turbo"]
const SPEED_PROFILES := {
	"realistic": {"label": "현실 속도", "walk": 1.4, "run": 3.5},
	"brisk": {"label": "빠르게", "walk": 2.24, "run": 5.6},
	"fast": {"label": "아주 빠르게", "walk": 2.8, "run": 7.0},
	"rapid": {"label": "쾌속 (2배)", "walk": 5.6, "run": 14.0},
	"turbo": {"label": "초고속 (3배)", "walk": 8.4, "run": 21.0},
}

@export var exploration_settings_path := "user://sim2seoul_exploration.json"
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

func _ready() -> void:
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
	_layout_v0.call_deferred()
	print("EXPLORATION_READY speed=",speed_id," free_roam=",free_roam_enabled)

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="덕수궁 · 시청 · 돌담길 자유 탐험\nWASD / 방향키 이동 · Shift 달리기 · Space 높은 점프\n마우스 회전 · 휠 거리 조절 · E 건물 출입 / 엘리베이터 · Esc 메뉴"
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
	var library_shortcut := Button.new();library_shortcut.text = "서울도서관 정문으로 이동"
	library_shortcut.pressed.connect(_visit_library_entrance);options.add_child(library_shortcut)
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
	if is_instance_valid(interior_visit) and interior_visit.go_to_library_entrance():
		if menu.visible:toggle_menu()

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
	if not is_instance_valid(exploration_overlay):return
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
		"settings_path":exploration_settings_path,"runtime_ok":runtime_ok,"error":exploration_error}

func _select_source_document(index: int) -> void:
	super._select_source_document(index)
	if index==0:
		sources_text.text=sources_text.text.replace("실내·계단·잔디는 탐험 범위에서 제외합니다.","출입 표지가 있는 건물은 실내·계단·엘리베이터로 여러 층을 탐험할 수 있습니다. 자유 탐험을 켜면 잔디와 도로에서도 이동할 수 있습니다.")
		sources_text.text+="\n\n[b]이번 자유 탐험[/b]\n자유 탐험을 켜면 잔디와 도로까지 이동할 수 있습니다. 넓힌 바닥과 세부 외형은 탐험을 위한 표현이며 실제 현장의 지형·출입 가능 여부를 뜻하지 않습니다. 출입 표지가 있는 건물 정문에서 E로 들어갑니다. 실내 크기는 원본 건물 외곽 안에 맞췄으며, 층수는 OSM 원문 또는 높이 추정에 따릅니다. 방 배치·계단·엘리베이터와 실내 보행자는 게임용 재구성입니다. 작은 건물·사유지·일부 역사 건축물의 실내는 제외합니다. 석재 텍스처는 AI로 새로 제작했으며 공식 참조 사진 자체는 게임에 포함하지 않았습니다."

func _process(delta: float) -> void:
	super._process(delta)
	if not runtime_ok:return
	if is_instance_valid(interior_visit) and interior_visit.active:
		status.text=interior_visit.status_text()
	else:
		status.text+=" · %s · %s"%["자유 탐험" if free_roam_enabled else "산책길",SPEED_PROFILES[speed_id].label]

func reset_player() -> void:
	if is_instance_valid(interior_visit) and interior_visit.active:
		interior_visit.return_to_world_spawn()
	else:
		super.reset_player()

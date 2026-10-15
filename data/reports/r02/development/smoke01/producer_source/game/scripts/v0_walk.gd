extends "res://scripts/traffic_walk.gd"
## Candidate V0 leaf: display preferences and notices, with inherited simulation.
const QUALITY_IDS := ["standard", "low"]
const LEGAL_FILES := [
	["자료 출처", "res://resources/legal/ATTRIBUTION.md"],
	["Godot 라이선스", "res://resources/legal/GODOT_LICENSE.txt"],
	["Godot 추가 고지", "res://resources/legal/GODOT_THIRD_PARTY.txt"],
	["Kenney 라이선스", "res://resources/legal/KENNEY_CC0.txt"],
	["자료 · 변경 방법 안내", "res://resources/legal/NOTICES.txt"],
]
const SOURCE_URLS := [
	"https://godotengine.org/license/", "https://www.openstreetmap.org/copyright",
	"https://opendatacommons.org/licenses/odbl/1-0/", "https://docs.overturemaps.org/attribution/",
	"https://doi.org/10.5281/zenodo.8174931", "https://creativecommons.org/licenses/by/4.0/",
	"https://kenney.nl/assets/city-kit-commercial",
]
const SOURCE_SUMMARY := """[b]엔진[/b]
[url=https://godotengine.org/license/]Godot Engine · MIT 라이선스[/url]

[b]지도 · 건물 자료[/b]
© OpenStreetMap contributors, Overture Maps Foundation
[url=https://www.openstreetmap.org/copyright]OSM 저작권 안내[/url] · [url=https://opendatacommons.org/licenses/odbl/1-0/]ODbL 1.0[/url] · [url=https://docs.overturemaps.org/attribution/]Overture 출처[/url]
Overture 추가 원천: Qian Shi et al. (2023), [url=https://doi.org/10.5281/zenodo.8174931]doi:10.5281/zenodo.8174931[/url], [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]. 지역 조회·분류, 미터 좌표 변환과 시각 표현을 적용했습니다.

[b]도시 외형[/b]
[url=https://kenney.nl/assets/city-kit-commercial]Kenney · City Kit Commercial 2.1 · CC0 1.0[/url]. 일부 모델의 크기·외곽·색·법선·저층부를 수정했습니다. 실제 서울 건물의 정확한 복제는 아닙니다.

[b]원본과 추정[/b]
공개 안내 자료의 사실·외관 관찰을 참고했으며 사진·도면·로고는 가져오지 않았습니다. 지도상 배치는 원천 자료에서 왔고, 높이·세부 비례·임시 지면에는 추정이 포함됩니다. 현재 현장 통로와 다를 수 있습니다. 실내·계단·잔디는 탐험 범위에서 제외합니다.
Copernicus DSM은 준비 단계의 참고 자료이며 게임의 보행 지면으로 사용하지 않았습니다.

[b]원천 자료와 변경 방법[/b]
원천 자료·변경 재현 방법은 동봉 출처 파일에 안내합니다. 같은 버전의 비공개 저장소는 접근 권한이 있는 경우에만 열람할 수 있습니다. 대중에게 공개 제공한다는 의미가 아닙니다."""

@export var quality_settings_path := "user://sim2seoul_quality.json"
var quality_id := "standard"
var quality_error := ""
var quality_presets := {}
var settings_recovered := false
var quality_option: OptionButton
var quality_description: Label
var quality_notice: Label
var sources_popup: PanelContainer
var sources_overlay: ColorRect
var sources_text: RichTextLabel
var sources_document: OptionButton
var sources_close: Button
var resume_action: Button
var hud_panel: PanelContainer
var attribution_label: Label

func _ready() -> void:
	super._ready()
	if not runtime_ok:return
	for child in $Interface.get_children():
		if child is Label and child.text.begins_with("지도 © OpenStreetMap"):
			attribution_label=child
			attribution_label.text="© OpenStreetMap contributors, Overture Maps Foundation\n지도 · 건물 자료 · ODbL 1.0 · Esc에서 출처 보기"
			attribution_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
			attribution_label.add_theme_font_size_override("font_size",14)
			attribution_label.add_theme_color_override("font_color",Color(.08,.12,.16))
			attribution_label.add_theme_color_override("font_outline_color",Color(1,1,1))
			attribution_label.add_theme_constant_override("outline_size",3)
			attribution_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout_v0)
	_layout_v0.call_deferred()
	if not _load_quality_presets():return
	var selected:=_read_quality_settings()
	if not apply_quality(selected):return
	if settings_recovered:
		quality_notice.text="저장된 설정을 읽지 못해 기본으로 시작했습니다."
		_save_quality_settings()
	print("V0_READY quality=",quality_id," pedestrians=",pedestrians.size()," vehicles=",vehicles.size())

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text="덕수궁 · 시청 · 돌담길\nWASD / 방향키 이동 · Shift 달리기 · 마우스 회전\n휠 거리 조절 · Esc 메뉴 / 마우스 해제"
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hud_panel=status.get_parent().get_parent() as PanelContainer
	var options:=menu.get_child(0) as VBoxContainer
	options.add_theme_constant_override("separation",8)
	var heading:=options.get_child(0) as Label
	heading.text="잠시 쉬어가기 · 이동키를 놓고 다시 시작하세요"
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color",Color(.08,.12,.16))
	for control in [movement_switch,traffic_switch]:
		for color_name in ["font_color","font_hover_color","font_pressed_color"]:
			control.add_theme_color_override(color_name,Color(.08,.12,.16))
	var quit_action: Button
	for child in options.get_children():
		if child is Button and child.text.begins_with("돌아가기"):resume_action=child
		elif child is Button and child.text=="시험 장면 종료":
			quit_action=child;quit_action.text="종료"
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.97,.98,.97,.98)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=16;style.content_margin_bottom=16
	menu.add_theme_stylebox_override("panel",style)
	options.add_child(HSeparator.new())
	var quality_row:=HBoxContainer.new()
	var caption:=Label.new();caption.text="화면 품질"
	caption.add_theme_color_override("font_color",Color(.08,.12,.16))
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	quality_row.add_child(caption)
	quality_option=OptionButton.new();quality_option.name="QualityPreset"
	quality_option.add_item("기본");quality_option.add_item("가볍게")
	quality_option.custom_minimum_size=Vector2(150,32)
	quality_option.item_selected.connect(_quality_selected)
	quality_row.add_child(quality_option);options.add_child(quality_row)
	quality_description=Label.new();quality_description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	quality_description.add_theme_font_size_override("font_size",14)
	quality_description.add_theme_color_override("font_color",Color(.08,.12,.16))
	options.add_child(quality_description)
	quality_notice=Label.new();quality_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	quality_notice.add_theme_font_size_override("font_size",13)
	quality_notice.add_theme_color_override("font_color",Color(.35,.15,.07))
	options.add_child(quality_notice)
	var source_button:=Button.new();source_button.name="SourcesButton";source_button.text="출처 보기"
	source_button.pressed.connect(_show_sources);options.add_child(source_button)
	if quit_action!=null:options.move_child(quit_action,options.get_child_count()-1)
	_build_sources_popup(style)

func _build_sources_popup(style: StyleBoxFlat) -> void:
	sources_overlay=ColorRect.new();sources_overlay.name="SourcesOverlay"
	sources_overlay.color=Color(0,0,0,.48);sources_overlay.visible=false
	sources_overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	$Interface.add_child(sources_overlay)
	sources_popup=PanelContainer.new();sources_popup.name="SourcesPopup"
	sources_popup.add_theme_stylebox_override("panel",style)
	sources_overlay.add_child(sources_popup)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10)
	sources_popup.add_child(column)
	var title:=Label.new();title.text="자료 출처와 표현 범위"
	title.add_theme_color_override("font_color",Color(.08,.12,.16))
	title.add_theme_font_size_override("font_size",20);column.add_child(title)
	sources_text=RichTextLabel.new();sources_text.name="SourcesText"
	sources_text.custom_minimum_size=Vector2(0,180)
	sources_text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	sources_text.selection_enabled=true;sources_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	sources_text.add_theme_color_override("default_color",Color(.08,.12,.16))
	sources_text.meta_clicked.connect(_source_link);column.add_child(sources_text)
	var actions:=HBoxContainer.new()
	sources_document=OptionButton.new();sources_document.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sources_document.add_item("안내 요약")
	for entry in LEGAL_FILES:
		sources_document.add_item(entry[0]);sources_document.set_item_disabled(sources_document.item_count-1,not FileAccess.file_exists(entry[1]))
	sources_document.item_selected.connect(_select_source_document);actions.add_child(sources_document)
	sources_close=Button.new();sources_close.text="닫기 · Esc"
	sources_close.pressed.connect(_close_sources);actions.add_child(sources_close);column.add_child(actions)
	# Keep keyboard traversal within the popup while its backdrop covers the menu.
	sources_document.focus_next=sources_document.get_path_to(sources_close)
	sources_document.focus_previous=sources_document.get_path_to(sources_close)
	sources_close.focus_next=sources_close.get_path_to(sources_document)
	sources_close.focus_previous=sources_close.get_path_to(sources_document)
	_select_source_document(0)

func _layout_v0() -> void:
	var view:=get_viewport().get_visible_rect().size
	if is_instance_valid(hud_panel):hud_panel.size=Vector2(minf(560.,view.x-32.),0)
	menu.size=Vector2(minf(440.,view.x-32.),menu.get_combined_minimum_size().y)
	menu.position=Vector2(maxf(16.,(view.x-menu.size.x)/2.),maxf(16.,(view.y-menu.size.y)/2.))
	if is_instance_valid(attribution_label):
		attribution_label.size=Vector2(view.x-32.,attribution_label.get_combined_minimum_size().y)
		attribution_label.position=Vector2(16.,view.y-attribution_label.size.y-12.)
	if is_instance_valid(sources_overlay):
		sources_overlay.size=view
		sources_popup.size=Vector2(minf(660.,view.x-32.),minf(480.,view.y-32.))
		sources_popup.position=(view-sources_popup.size)/2.

func toggle_menu() -> void:
	if is_instance_valid(sources_overlay) and sources_overlay.visible:
		_close_sources();return
	super.toggle_menu()
	if menu.visible:
		_layout_v0.call_deferred()
		if is_instance_valid(resume_action):resume_action.grab_focus()

func _show_sources() -> void:
	_select_source_document(0);sources_document.select(0)
	sources_overlay.visible=true;_layout_v0();sources_close.grab_focus()

func _close_sources() -> void:
	sources_overlay.visible=false
	if is_instance_valid(resume_action):resume_action.grab_focus()

func _select_source_document(index: int) -> void:
	if index==0:
		sources_text.bbcode_enabled=true;sources_text.text=SOURCE_SUMMARY
	else:
		var path: String=LEGAL_FILES[index-1][1]
		var file:=FileAccess.open(path,FileAccess.READ)
		sources_text.bbcode_enabled=false
		sources_text.text=file.get_as_text() if file!=null else "출처 파일을 읽지 못했습니다. 안내 요약과 공식 출처 링크를 확인해주세요."
	sources_text.scroll_to_line(0)

func _source_link(target) -> void:
	var address:=str(target)
	if address in SOURCE_URLS:OS.shell_open(address)

func _json_object(path: String):
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return null
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return null
	return parser.data

func _quality_failure(message: String) -> bool:
	quality_error=message;runtime_ok=false;input_router.gameplay_enabled=false;rig.set_capture(false)
	status.text=message;quality_notice.text=message;quality_option.disabled=true
	push_error(message)
	return false

func _load_quality_presets() -> bool:
	for id in QUALITY_IDS:
		var path: String="res://resources/quality_presets/"+id+".json"
		var preset=_json_object(path) if FileAccess.file_exists(path) else null
		if not preset is Dictionary or not _number(preset.get("schema_version")) or preset.schema_version!=1 or not preset.get("id") is String or preset.id!=id:
			return _quality_failure("화면 품질 자료를 읽지 못했습니다: "+id)
		var expected_scale: float=1. if id=="standard" else .75
		if not _number(preset.get("scaling_3d_scale")) or preset.scaling_3d_scale!=expected_scale or not preset.get("sun_shadow_enabled") is bool or preset.sun_shadow_enabled!=(id=="standard") or not _number(preset.get("camera_far_m")) or preset.camera_far_m!=200. or not preset.get("label") is String or not preset.get("description") is String:
			return _quality_failure("화면 품질 자료의 설정을 확인해주세요: "+id)
		quality_presets[id]=preset
	return true

func _read_quality_settings() -> String:
	if not FileAccess.file_exists(quality_settings_path):return "standard"
	var saved=_json_object(quality_settings_path)
	if saved is Dictionary and saved.size()==2 and _number(saved.get("schema_version")) and saved.schema_version==1 and saved.get("preset_id") is String and saved.preset_id in QUALITY_IDS:
		return saved.preset_id
	settings_recovered=true
	return "standard"

func apply_quality(id: String) -> bool:
	if not quality_presets.has(id):return _quality_failure("지원하지 않는 화면 품질입니다.")
	var sun:=get_node_or_null("Presentation/Sun") as DirectionalLight3D
	if sun==null:return _quality_failure("화면 조명을 찾지 못했습니다.")
	var preset: Dictionary=quality_presets[id]
	get_viewport().scaling_3d_scale=preset.scaling_3d_scale
	sun.shadow_enabled=preset.sun_shadow_enabled
	rig.camera.far=preset.camera_far_m
	quality_id=id;quality_option.select(QUALITY_IDS.find(id))
	quality_description.text=preset.description
	_layout_v0.call_deferred()
	return true

func quality_snapshot() -> Dictionary:
	var viewport:=get_viewport()
	var sun:=get_node_or_null("Presentation/Sun") as DirectionalLight3D
	var active_camera: Camera3D=rig.camera if is_instance_valid(rig) else null
	var people:=get_node_or_null("Actors/Pedestrians")
	var cars:=get_node_or_null("Actors/Vehicles")
	return {"preset_id":quality_id,"scaling_3d_scale":viewport.scaling_3d_scale if viewport!=null else null,
		"sun_shadow_enabled":sun.shadow_enabled if sun!=null else null,"camera_far_m":active_camera.far if active_camera!=null else null,
		"quality_settings_path":quality_settings_path,"pedestrian_count":people.get_child_count() if people!=null else 0,
		"vehicle_count":cars.get_child_count() if cars!=null else 0,"runtime_ok":runtime_ok}

func _quality_selected(index: int) -> void:
	quality_notice.text=""
	if apply_quality(QUALITY_IDS[index]):_save_quality_settings()

func _save_quality_settings() -> void:
	var file:=FileAccess.open(quality_settings_path,FileAccess.WRITE)
	if file==null:
		quality_notice.text="설정을 저장하지 못했습니다. 이번 실행에는 적용됩니다."
		return
	file.store_string(JSON.stringify({"schema_version":1,"preset_id":quality_id})+"\n")
	file.close()

func _process(delta: float) -> void:
	super._process(delta)
	if runtime_ok:status.text=status.text.replace("도로 접속부 (현재 차량 없음)","도로 횡단 구간 · 좌우를 살피세요")

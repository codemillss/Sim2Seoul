extends Node3D
## Optional dimension inspection of the retained original footprints. It does
## not scale, move, grant access to, or replace any world geometry.
const DATA_PATH:="res://assets/authored/city_metric_reference.json"
var host: Node3D
var loaded:=false
var load_error:=""
var enabled:=false
var data: Dictionary={}
var display: Node3D
var lines: MeshInstance3D
var captions: Array[Label3D]=[]
var selected: Array=[]
var panel: PanelContainer
var panel_text: Label
var _clock:=0.
var _line_material: StandardMaterial3D
func setup(scene: Node3D) -> bool:
	host=scene;process_priority=30
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or raw.get("world_sha256")!=FileAccess.get_sha256("res://resources/world_geometry/world.json") or raw.get("buildings",[]).size()!=635:load_error="건물 치수 비교 자료가 현재 도시와 다릅니다.";return false
	data=raw;display=Node3D.new();display.name="OptionalMetreInspection";add_child(display);display.visible=false
	_line_material=StandardMaterial3D.new();_line_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;_line_material.vertex_color_use_as_albedo=true;_line_material.no_depth_test=false
	lines=MeshInstance3D.new();lines.name="SourceFootprintAndOneMetreLines";display.add_child(lines)
	for index: int in range(5):
		var label:=Label3D.new();label.name="MeasuredDimension"+str(index);label.font_size=36;label.pixel_size=.0045;label.outline_size=7;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;display.add_child(label);captions.append(label)
	panel=PanelContainer.new();panel.name="MetreComparisonReadout";panel.z_index=30;panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.09,.12,.96);style.set_content_margin_all(12.);style.set_corner_radius_all(6);panel.add_theme_stylebox_override("panel",style)
	panel_text=Label.new();panel_text.add_theme_font_size_override("font_size",15);panel_text.add_theme_color_override("font_color",Color(.94,.98,.94));panel_text.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(panel_text);host.get_node("Interface").add_child(panel);panel.visible=false
	loaded=true;return true
func set_enabled(value: bool) -> void:
	enabled=value;display.visible=value;panel.visible=value
	if enabled:refresh()
func _height(x: float,z: float,extra:=.045) -> Vector3:
	var y: float=host.terrain_surface.ground_y_world(Vector3(x,0,z));return Vector3(x,y+extra if is_finite(y) else 0.,z)
func _segment(mesh: ImmediateMesh,a: Vector3,b: Vector3,color: Color) -> void:
	mesh.surface_set_color(color);mesh.surface_add_vertex(a);mesh.surface_set_color(color);mesh.surface_add_vertex(b)
func refresh() -> void:
	if not loaded:return
	var outdoor_y: float=host.terrain_surface.ground_y_world(host.player.global_position)
	display.visible=enabled and not host.player.interior_active and is_finite(outdoor_y)
	if not display.visible:return
	selected.clear();var nearby: Array=[];var player_point:=Vector2(host.player.global_position.x,host.player.global_position.z)
	for row: Dictionary in data.buildings:
		var center:=Vector2.ZERO;var count:=0
		for ring: Array in row.rings:
			for p: Array in ring:center+=Vector2(p[0],p[1]);count+=1
		center/=maxi(1,count);var distance:=center.distance_to(player_point)
		if distance<110.:nearby.append({"row":row,"center":center,"distance":distance})
	nearby.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES,_line_material)
	var readout:=PackedStringArray(["크기 비교 · 1칸 1m / 세로 눈금 2m", "사람 키 1.70m 기준 · 지도 외곽 치수"])
	var x:=roundf(player_point.x);var z:=roundf(player_point.y)
	for index: int in range(-5,6):
		var color:=Color(.91,.92,.82) if index%5 else Color(.97,.72,.13)
		for step: int in range(-5,5):
			_segment(mesh,_height(x+index,z+step),_height(x+index,z+step+1),color)
			_segment(mesh,_height(x+step,z+index),_height(x+step+1,z+index),color)
	for label: Label3D in captions:label.visible=false
	for index: int in range(mini(4,nearby.size())):
		var item: Dictionary=nearby[index];var row: Dictionary=item.row;selected.append(row.id)
		for ring: Array in row.rings:
			for edge: int in range(ring.size()-1):
				var a: Array=ring[edge];var b: Array=ring[edge+1];_segment(mesh,_height(a[0],a[1],.12),_height(b[0],b[1],.12),Color(.15,.91,.86))
		if index>=2:continue
		# Put readable dimensions outside the nearest actual footprint edge.
		# An anchor at a polygon centroid hides text inside most solid buildings.
		var edge_point:=item.center as Vector2;var edge_distance:=INF
		for ring: Array in row.rings:
			for edge: int in range(ring.size()-1):
				var a:=Vector2(ring[edge][0],ring[edge][1]);var b:=Vector2(ring[edge+1][0],ring[edge+1][1]);var point:=Geometry2D.get_closest_point_to_segment(player_point,a,b)
				if point.distance_to(player_point)<edge_distance:edge_point=point;edge_distance=point.distance_to(player_point)
		var out: Vector2=(player_point-edge_point).normalized();var caption_point: Vector2=edge_point+out*.8
		var label: Label3D=captions[index];var name_: String=row.name if not row.name.is_empty() else "건물"
		var height_note:="자료 높이" if row.height_basis=="source_tag" else "추정 높이"
		label.text="%s\n동서 폭 %.1fm · 남북 폭 %.1fm\n외곽 긴 변 %.1fm / 짧은 변 %.1fm\n%s %.1fm · 인접 간격 %.2fm"%[name_,row.width_x_m,row.depth_z_m,row.oriented_envelope_long_m,row.oriented_envelope_short_m,height_note,row.height_m,row.nearest_source_building.gap_m]
		label.global_position=_height(caption_point.x,caption_point.y,3.0+float(index)*.55);label.visible=false
		readout.append("\n"+label.text)
	var ruler:=_height(x-1.5,z-1.5,.02);_segment(mesh,ruler,ruler+Vector3.UP*2.,Color(1.,.72,.12))
	for tick: int in range(11):_segment(mesh,ruler+Vector3.UP*tick*.2-Vector3.RIGHT*.10,ruler+Vector3.UP*tick*.2+Vector3.RIGHT*.10,Color(1.,.72,.12))
	captions[4].text="1칸 1m · 세로 눈금 2m\n사람 키 1.70m 기준";captions[4].global_position=ruler+Vector3(0,2.6,0);captions[4].visible=true
	mesh.surface_end();lines.mesh=mesh;panel_text.text="\n".join(readout)
func _process(delta: float) -> void:
	if not loaded:return
	panel.visible=enabled and not host.menu.visible and not host.player.interior_active and is_finite(host.terrain_surface.ground_y_world(host.player.global_position))
	if not enabled or host.menu.visible:
		display.visible=false;return
	if panel.visible:
		host.interior_visit.wayfinding.panel.visible=false;host.interior_visit.prompt.visible=false;host.building_names.panel.visible=false
		var view:=host.get_viewport().get_visible_rect().size;panel.reset_size();panel.position=Vector2(16.,maxf(155.,view.y-panel.size.y-24.))
	_clock+=delta
	if _clock>.4:_clock=0.;refresh()
func snapshot() -> Dictionary:return {"loaded":loaded,"enabled":enabled,"selected_buildings":selected,"unit":"metre","changes_world_geometry":false,"accuracy":"Retained source footprint dimensions and pair gaps; labelled source/estimated height. Not an independent survey or a claim that every replacement visible facade matches this footprint."}

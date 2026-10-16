extends Node
## Names come only from the shared OSM snapshot and the already bound landmarks.
var records := {}
var markers := []
var named_count := 0
var host: Node3D
var panel: PanelContainer
var caption: Label
var crosshair: Label
var ticks := 0
var current_id := ""
var current_name := ""

func setup(root_scene: Node3D) -> bool:
	host=root_scene
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	if not data is Dictionary or not data.get("meshes") is Array:return false
	for entry in data.meshes:
		if entry.role!="Buildings":continue
		var id: String=entry.id
		var source: MeshInstance3D=host.city.source_nodes.get(id)
		if source==null:continue
		var box: AABB=source.get_aabb()
		var name: String=String(entry.metadata.get("name",""))
		records[id]={"name":name,"bounds":Rect2(box.position.x,box.position.z,box.size.x,box.size.z),"top":float(entry.top_y_m)}
		if name.is_empty():continue
		named_count+=1
		var marker:=Label3D.new();marker.text=name;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		marker.font_size=36;marker.outline_size=8;marker.pixel_size=.02
		marker.modulate=Color(.98,.96,.83);marker.outline_modulate=Color(.07,.10,.12)
		marker.position=Vector3(box.get_center().x,float(entry.top_y_m)+2.0,box.get_center().z)
		marker.visible=false;host.get_node("Presentation").add_child(marker)
		markers.append({"node":marker,"id":id,"point":marker.position})
	panel=PanelContainer.new();panel.name="BuildingName"
	var style:=StyleBoxFlat.new();style.bg_color=Color(.055,.09,.12,.90)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=7;style.content_margin_bottom=7;style.corner_radius_top_left=6;style.corner_radius_top_right=6;style.corner_radius_bottom_left=6;style.corner_radius_bottom_right=6
	panel.add_theme_stylebox_override("panel",style);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption=Label.new();caption.add_theme_font_size_override("font_size",17);caption.add_theme_color_override("font_color",Color(.98,.97,.9));caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(caption);host.get_node("Interface").add_child(panel)
	crosshair=Label.new();crosshair.text="·";crosshair.add_theme_font_size_override("font_size",28);crosshair.add_theme_color_override("font_color",Color(1,1,1,.8));crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.get_node("Interface").add_child(crosshair)
	process_physics_priority=4
	print("BUILDING_NAMES_READY named=",named_count)
	return true

func identify(id: String) -> String:
	if id.begins_with("W01_gate_"):return "대한문"
	if id in ["W01_palace_wall","osm:way:381941848:barrier","osm:way:381941854:barrier"]:return "덕수궁 돌담"
	if records.has(id):return String(records[id].name)
	return ""

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(host) or not host.runtime_ok:return
	ticks+=1
	if ticks%6!=0:return
	var camera: Camera3D=host.rig.camera
	var origin:=camera.global_position
	var query:=PhysicsRayQueryParameters3D.create(origin,origin-camera.global_basis.z*220.,1,[host.player.get_rid()])
	var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(query)
	current_id="";current_name=""
	var distance:=0.
	var prefix:=""
	if not hit.is_empty():
		current_id=String(hit.collider.get_meta("geometry_id",""));current_name=identify(current_id)
		distance=host.player.global_position.distance_to(hit.position)
		if current_name.is_empty() and records.has(current_id):current_name="이름 정보가 없는 건물"
	if current_name.is_empty():
		var point:=Vector2(host.player.position.x,host.player.position.z)
		var nearest:=55.
		for id in records:
			var record: Dictionary=records[id]
			if String(record.name).is_empty():continue
			var rect: Rect2=record.bounds
			var closest:=Vector2(clampf(point.x,rect.position.x,rect.end.x),clampf(point.y,rect.position.y,rect.end.y))
			var gap:=point.distance_to(closest)
			if gap<nearest:nearest=gap;current_name=record.name;current_id=id;distance=gap;prefix="가까운 건물 · "
	caption.text=prefix+current_name+"  ·  %.0fm"%distance
	panel.visible=not current_name.is_empty() and not host.menu.visible
	var view:=host.get_viewport().get_visible_rect().size
	panel.reset_size();panel.position=Vector2(maxf(16.,(view.x-panel.size.x)/2.),view.y-100.)
	crosshair.visible=not host.menu.visible;crosshair.position=view*.5-Vector2(5,20)
	var candidates:=[]
	for marker in markers:
		marker.node.visible=false
		var gap: float=origin.distance_to(marker.point)
		if gap>280. or camera.is_position_behind(marker.point):continue
		var projected:=camera.unproject_position(marker.point)
		if not Rect2(16,24,view.x-32,view.y-100).has_point(projected):continue
		candidates.append({"marker":marker.node,"distance":gap})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	for i in range(mini(8,candidates.size())):candidates[i].marker.visible=not host.menu.visible

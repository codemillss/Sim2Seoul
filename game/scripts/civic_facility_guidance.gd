extends Node
## New fictional institutions must not inherit a nearby unrelated source-door
## bearing. This late visual pass changes labels only, never an E/input owner.
var host: Node3D
var loaded:=false
var current: Dictionary={}
func setup(scene: Node3D) -> bool:
	host=scene;process_priority=20;loaded=true;return true
func nearby() -> Dictionary:
	if not loaded or host.menu.visible or host.player.interior_active or host._sandbox_detained():return {}
	var point: Vector3=host.player.global_position;var candidates: Array=[]
	var hospital: Node3D=host.get("city_hospital")
	if is_instance_valid(hospital) and hospital.loaded and Rect2(241,358,48,34).grow(14.).has_point(Vector2(point.x,point.z)) and absf(point.y-hospital.floor_y)<4.:
		for row: Dictionary in hospital.door_groups:candidates.append({"title":"서울시티 종합병원","entry":"응급실 접수" if float(row.z)<-.5 else "정문 · 원무 접수","point":row.point,"action":"E · 자동문 / 열린 문으로 걸어 들어가기"})
	var safety: Node3D=host.get("city_public_safety")
	if is_instance_valid(safety):
		var headquarters: Node3D=safety.get("police_headquarters")
		if is_instance_valid(headquarters) and headquarters.loaded and Rect2(-135,-431,30,22).grow(14.).has_point(Vector2(point.x,point.z)) and absf(point.y-headquarters.foundation_y)<4.:candidates.append({"title":"서울 생활안전 경찰청사","entry":"정문 · 민원실","point":headquarters.entry_point,"action":"E · 자동문 / 열린 문으로 걸어 들어가기"})
		var police_box: Node3D=safety.get("police_facility")
		if is_instance_valid(police_box) and police_box.loaded and point.distance_to(police_box.entry_point)<12.:candidates.append({"title":"세종로파출소","entry":"정문 · 민원실","point":police_box.entry_point,"action":"E · 민원실 출입"})
	var weather: Node3D=host.get("city_weather_emergency")
	if is_instance_valid(weather) and weather.loaded and is_instance_valid(weather.station):
		var local: Vector3=weather.station.to_local(point)
		if absf(local.x)<31. and absf(local.z)<34. and absf(local.y)<4.:
			candidates.append({"title":"서울시티 소방서","entry":"민원 · 안전교육 출입구","point":weather.station.to_global(Vector3(10.75,0,-15.0)),"action":"열린 민원 출입구로 걸어 들어가기"})
	var selected: Dictionary={};var distance:=INF
	for row: Dictionary in candidates:
		var gap: float=Vector2(row.point.x-point.x,row.point.z-point.z).length()
		if gap<distance:selected=row.duplicate();distance=gap;selected["distance_m"]=gap
	return selected
func _process(_delta: float) -> void:
	if not loaded or not host.runtime_ok:return
	current=nearby()
	if current.is_empty():return
	# The original source-entry catalog stays unchanged. Only its unrelated
	# compass badge and name are replaced while within this actual campus.
	if is_instance_valid(host.interior_visit) and is_instance_valid(host.interior_visit.wayfinding):
		host.interior_visit.wayfinding.panel.visible=false
		host.interior_visit.wayfinding.world_frames.visible=false
	var names: Node=host.building_names
	var local: Vector3=host.rig.camera.global_basis.inverse()*(current.point-host.rig.camera.global_position)
	var bearing: String="앞쪽" if absf(local.x)<absf(local.z)*.35 and local.z<0 else "뒤쪽" if local.z>absf(local.x)*1.7 else "오른쪽" if local.x>0 else "왼쪽"
	names.caption.text="%s · %s · %.0fm (%s)\n%s"%[current.title,current.entry,current.distance_m,bearing,current.action]
	names.panel.visible=true;names.panel.reset_size();var view:=host.get_viewport().get_visible_rect().size;names.panel.position=Vector2(maxf(16.,(view.x-names.panel.size.x)*.5),view.y-135.)
func snapshot() -> Dictionary:return {"loaded":loaded,"current":current,"changes_input_owner":false,"changes_source_catalog":false}

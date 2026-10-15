extends "res://scripts/pedestrian_walk.gd"
var traffic_bundle: Dictionary={}
var traffic_error:=""
var vehicles: Array[CharacterBody3D]=[]
var road_supports: Array[StaticBody3D]=[]
var traffic: Node
var traffic_switch: CheckButton

func _ready() -> void:
	super._ready()
	if not runtime_ok:return
	if not spawn_traffic():
		runtime_ok=false;input_router.gameplay_enabled=false;rig.set_capture(false)
		status.text=traffic_error;push_error(traffic_error);return
	print("N03_READY pedestrians=2 vehicles=2 original_active=687 new_vehicle_supports=2 total_active=689")

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text+="\n세종대로 차량은 횡단하는 사람을 기다립니다."
	traffic_switch=CheckButton.new();traffic_switch.text="차량 이동"
	traffic_switch.set_pressed_no_signal(true)
	traffic_switch.toggled.connect(set_vehicles_running)
	menu.get_child(0).add_child(traffic_switch)

func set_vehicles_running(enabled: bool) -> void:
	for body in vehicles:body.set_running(enabled)
	if is_instance_valid(traffic_switch):traffic_switch.set_pressed_no_signal(enabled)

func _traffic_fail(message: String) -> bool:
	traffic_error=message;return false

func _finite_data(value) -> bool:
	if value is float:return is_finite(value)
	if value is Array:
		for item in value:
			if not _finite_data(item):return false
	if value is Dictionary:
		for item in value.values():
			if not _finite_data(item):return false
	return true

func _valid_traffic(data: Dictionary) -> bool:
	if data.get("task")!="N03" or data.get("schema_version")!=1 or data.get("contract_id")!="N03-traffic-v1" or not _finite_data(data):return false
	var world_data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	if data.get("coordinate_system")!=world_data.get("coordinate_system"):return false
	if data.get("rules")!=JSON.parse_string(FileAccess.get_file_as_string("res://resources/collision/traffic_rules.json")):return false
	if data.get("scope")!=JSON.parse_string(JSON.stringify({"task":"N03","vehicles":2,"pedestrians":2,"new_vehicle_supports":2,"player_boundary_changed":false,"physical_terrain_access_verified":false})):return false
	if not data.get("actor") is Dictionary or data.actor.get("length_m")!=4.2 or data.actor.get("width_m")!=1.8 or data.actor.get("height_m")!=1.5 or data.actor.get("mask")!=31 or data.actor.get("layer")!=8:return false
	if not data.get("policy") is Dictionary:return false
	var policy: Dictionary=data.policy
	if policy.get("brake_mps2")!=3. or policy.get("reaction_s")!=.5 or policy.get("stop_margin_m")!=1. or policy.get("clear_hold_s")!=1. or policy.get("max_observation_age_s")!=.1 or policy.get("zone_vehicle_capacity")!=1 or policy.get("unknown_occupancy")!="stop":return false
	if policy.get("priority")!=["player_and_pedestrian","vehicle_already_inside","fifo_waiting_vehicle"]:return false
	if policy.get("vehicle_recycle")!=JSON.parse_string(JSON.stringify({"both_portals_outside_actual_camera_frustum":true,"minimum_human_distance_m":30.,"dynamic_entry_envelope_empty":true,"hold_until_eligible":true,"spatial_connection_between_portals":false})):return false
	if not data.get("routes") is Array or data.routes.size()!=2 or not data.get("supports") is Array or data.supports.size()!=2:return false
	for i in range(2):
		var r=data.routes[i];var support=data.supports[i]
		if not r is Dictionary or r.get("id")!=["sejong_south","sejong_north"][i] or r.get("speed_mps")!=5. or r.get("ground_y_m")!=0. or r.get("repeat")!="guarded_oneway_stream" or r.get("repeat_spatial_edge")!=null:return false
		if not r.get("source_binding") is Dictionary or r.source_binding.get("oneway")!="yes" or r.source_binding.get("source_direction")!="source_forward" or r.source_binding.get("lanes")!=8 or r.source_binding.get("right_offset_m")!=1.6:return false
		if not r.get("xz") is Array or r.xz.size()!=[4,9][i] or not _number(r.get("length_m")):return false
		var length:=0.
		for j in range(r.xz.size()):
			var p=r.xz[j]
			if not p is Array or p.size()!=2 or not _number(p[0]) or not _number(p[1]):return false
			if j>0:length+=Vector2(p[0]-r.xz[j-1][0],p[1]-r.xz[j-1][1]).length()
		if absf(length-r.length_m)>.001 or not r.get("conflicts") is Array or r.conflicts.size()!=1:return false
		var c: Dictionary=r.conflicts[0]
		if c.get("crossing_id")!="sejong_marked" or not _number(c.get("stop_s_m")) or not _number(c.get("enter_s_m")) or not _number(c.get("exit_s_m")) or c.stop_s_m<0 or c.enter_s_m-c.stop_s_m<7.6665 or c.exit_s_m<=c.enter_s_m or c.exit_s_m>=length:return false
		if not support is Dictionary or support.get("id")!="N03_support_"+r.id or support.get("route_id")!=r.id or support.get("layer")!=16 or support.get("mask")!=8 or support.get("bottom_y_m")!=-.2 or support.get("top_y_m")!=0:return false
		if not support.get("vertices") is Array or support.vertices.size()<9 or support.vertices.size()%9!=0:return false
	if not data.get("crossings") is Array or data.crossings.size()!=3:return false
	return true

func spawn_traffic() -> bool:
	if not vehicles.is_empty() or not road_supports.is_empty():return _traffic_fail("차량은 이미 배치돼 있습니다.")
	var path:="res://data/generated/traffic.json"
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic_manifest.json"))
	if not manifest is Dictionary or manifest.get("task")!="N03" or not manifest.get("file") is Dictionary or manifest.file.get("path")!=path or manifest.file.get("sha256")!=FileAccess.get_sha256(path) or manifest.file.get("bytes")!=FileAccess.get_file_as_bytes(path).size():return _traffic_fail("차량 자료 체크섬이 다릅니다.")
	if not manifest.get("runtime_sha256") is Dictionary:return _traffic_fail("차량 원천 목록이 없습니다.")
	for key in ["res://data/generated/public_walk.json","res://data/generated/pedestrians.json","res://resources/world_geometry/world.json","res://data/generated/region.json","res://resources/collision/rules.json","res://resources/collision/traffic_rules.json"]:
		if manifest.runtime_sha256.get(key)!=FileAccess.get_sha256(key):return _traffic_fail("차량 원천/충돌 자료가 다릅니다.")
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not _valid_traffic(data) or manifest.get("scope")!=data.scope:return _traffic_fail("지원하지 않는 차량 경로/설정입니다.")
	traffic_bundle=data
	var support_rids: Array[RID]=[city.fragments.W03_support.get_rid()]
	for source in data.supports:
		var body:=StaticBody3D.new();body.name=source.id;body.collision_layer=16;body.collision_mask=8
		body.set_meta("geometry_id",source.id)
		var shape_node:=CollisionShape3D.new();shape_node.name="CollisionShape"
		var shape:=ConcavePolygonShape3D.new();var faces:=PackedVector3Array()
		for i in range(0,source.vertices.size(),3):faces.append(Vector3(source.vertices[i],source.vertices[i+1],source.vertices[i+2]))
		shape.set_faces(faces);shape.backface_collision=true;shape_node.shape=shape
		body.add_child(shape_node);$Infrastructure/RoadSupports.add_child(body);road_supports.append(body);support_rids.append(body.get_rid())
	city.set_meta("vehicle_support_rids",support_rids)
	traffic=load("res://scripts/traffic/traffic_manager.gd").new();traffic.name="TrafficManager"
	$Actors.add_child(traffic)
	var people: Array=[player];people.append_array(pedestrians)
	traffic.configure(data,people,rig.camera,city)
	var packed: PackedScene=load("res://scenes/npc/vehicle.tscn")
	for route in data.routes:
		var body: CharacterBody3D=packed.instantiate();body.name="Vehicle_"+route.id;body.set_meta("geometry_id","N03_"+route.id)
		body.configure(route,traffic,city);$Actors/Vehicles.add_child(body);vehicles.append(body);traffic.register_vehicle(body)
	rig.camera_stepped.connect(traffic.after_camera_step)
	return true

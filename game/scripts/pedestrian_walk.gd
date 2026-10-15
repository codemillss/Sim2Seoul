extends "res://scripts/city_landmark_walk.gd"
## Add two source-bound walking actors; original city/controls remain inherited.
var pedestrians: Array[CharacterBody3D] = []
var pedestrian_bundle: Dictionary = {}
var pedestrian_error := ""
var pedestrians_running := true
var movement_switch: CheckButton
@onready var pedestrian_root: Node3D = $Actors/Pedestrians

func _ready() -> void:
	super._ready()
	if not runtime_ok:return
	if not spawn_pedestrians():
		runtime_ok=false
		input_router.gameplay_enabled=false
		rig.set_capture(false)
		status.text=pedestrian_error
		push_error(pedestrian_error)
		return
	print("N02_READY pedestrians=",pedestrians.size()," vehicles=0 inherited_static=687")

func _build_ui() -> void:
	super._build_ui()
	var help: Label=status.get_parent().get_child(0)
	help.text+="\n산책하는 사람들은 앞마당·광장 전면을 왕복합니다."
	movement_switch=CheckButton.new()
	movement_switch.name="PedestrianMovement"
	movement_switch.text="보행자 이동"
	movement_switch.set_pressed_no_signal(true)
	movement_switch.toggled.connect(set_pedestrians_running)
	menu.get_child(0).add_child(movement_switch)

func set_pedestrians_running(enabled: bool) -> void:
	pedestrians_running=enabled
	for actor in pedestrians:actor.set_running(enabled)
	if is_instance_valid(movement_switch):movement_switch.set_pressed_no_signal(enabled)

func _npc_fail(message: String) -> bool:
	pedestrian_error=message
	return false

func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_bundle(data: Dictionary) -> bool:
	if data.get("schema_version")!=1 or data.get("task")!="N02" or data.get("contract_id")!="N02-pedestrians-v1":return false
	var expected_scope:={"task":"N02","pedestrians":2.0,"vehicles":0.0,"new_static_collision":0.0,"source_permissions_unchanged":true,"physical_terrain_access_verified":false,"human_handling_M4_verified":false}
	if data.get("scope")!=expected_scope or not data.get("policy") is Dictionary:return false
	var policy: Dictionary=data.policy
	var expected_policy:={"speed_mps":1.2,"height_m":1.7,"radius_m":.3,"gravity_mps2":9.8,"end_dwell_s":.5,"turn_radians_per_s":PI,"clear_hold_s":.3,"retreat_after_s":2.,"retreat_probe_m":.6,"contact_margin_m":.1,"initial_phase":.5,"initial_direction":1,"layer":4,"mask":15}
	for key in expected_policy:
		if not _number(policy.get(key)) or absf(float(policy[key])-float(expected_policy[key]))>1e-12:return false
	if policy.size()!=expected_policy.size():return false
	var region=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/region.json"))
	var world_data=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	if not region is Dictionary or not world_data is Dictionary or data.get("coordinate_system")!=world_data.get("coordinate_system"):return false
	if not data.get("routes") is Array or data.routes.size()!=2:return false
	var ids:=["palace_court","plaza_front"]
	for index in range(2):
		var route=data.routes[index]
		if not route is Dictionary or route.get("id")!=ids[index] or route.get("repeat")!="ping_pong" or route.get("speed_mps")!=1.2 or route.get("ground_y_m")!=0:return false
		var binding=route.get("source_binding")
		if not binding is Dictionary:return false
		var parent_id: String="court_approach" if index==0 else "city_plaza"
		var a: int=0 if index==0 else 97
		var b: int=11 if index==0 else 98
		if binding!={"parent_route":parent_id,"first_vertex":float(a),"last_vertex":float(b)}:return false
		var parent: Dictionary={}
		for r in city.public_data.routes:
			if r.id==parent_id:parent=r
		if parent.is_empty() or not route.get("xz") is Array or route.xz!=parent.xz.slice(a,b+1):return false
		var length:=0.
		for i in range(route.xz.size()):
			var point=route.xz[i]
			if not point is Array or point.size()!=2 or not _number(point[0]) or not _number(point[1]):return false
			if not city.movement_contains(Vector2(point[0],point[1])):return false
			if i>0:length+=Vector2(point[0]-route.xz[i-1][0],point[1]-route.xz[i-1][1]).length()
		if not _number(route.get("length_m")) or absf(route.length_m-length)>.0001:return false
	return true

func spawn_pedestrians() -> bool:
	if not pedestrians.is_empty() or pedestrian_root.get_child_count()!=0:return _npc_fail("보행자는 이미 배치돼 있습니다.")
	var manifest_path:="res://data/generated/pedestrians_manifest.json"
	var bundle_path:="res://data/generated/pedestrians.json"
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(bundle_path):return _npc_fail("보행 자료를 준비해주세요.")
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or manifest.get("schema_version")!=1 or manifest.get("task")!="N02" or manifest.get("contract_id")!="N02-pedestrians-v1":return _npc_fail("보행 자료 버전이 다릅니다.")
	if not manifest.get("file") is Dictionary or manifest.file.get("path")!=bundle_path or manifest.file.get("sha256")!=FileAccess.get_sha256(bundle_path) or manifest.file.get("bytes")!=FileAccess.get_file_as_bytes(bundle_path).size():return _npc_fail("보행 파일 체크섬이 다릅니다.")
	for pair in [["public_sha256","res://data/generated/public_walk.json"],["world_sha256","res://resources/world_geometry/world.json"],["region_sha256","res://data/generated/region.json"]]:
		if manifest.get(pair[0])!=FileAccess.get_sha256(pair[1]):return _npc_fail("보행 원천/지원면이 다릅니다.")
	var data=JSON.parse_string(FileAccess.get_file_as_string(bundle_path))
	if not data is Dictionary or not _valid_bundle(data) or manifest.get("scope")!=data.scope:return _npc_fail("지원하지 않는 보행 경로/설정입니다.")
	pedestrian_bundle=data
	var packed: PackedScene=load("res://scenes/npc/pedestrian.tscn")
	for route in data.routes:
		var actor: CharacterBody3D=packed.instantiate()
		actor.name="Pedestrian_"+route.id
		actor.set_meta("geometry_id","N02_"+route.id)
		actor.configure(route,city,player)
		pedestrian_root.add_child(actor)
		pedestrians.append(actor)
	return true

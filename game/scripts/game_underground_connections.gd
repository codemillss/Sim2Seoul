extends Node3D
## Explicit game connectors between source-linked station/building identities.
## Portals connect detached game interiors; no real tunnel network is asserted.
const DATA_PATH:="res://assets/authored/game_underground_connections.json"
var host: Node3D
var metro: Node3D
var loaded:=false
var load_error:=""
var links: Array[Dictionary]=[]
var events: Array[Dictionary]=[]
var pending: Dictionary={}
var transfers_to_building:=0
var transfers_to_station:=0
var blocked_transfers:=0
var _last_interact_tick:=-1
func setup(scene: Node3D,subway: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not scene.runtime_ok or not is_instance_valid(subway) or not subway.loaded:return false
	host=scene;metro=subway;name="GameUndergroundConnections";process_mode=Node.PROCESS_MODE_ALWAYS;process_physics_priority=3
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("links") is Array or raw.links.size()!=2:return _fail("게임 지하 연결통로 자료가 다릅니다.")
	if raw.get("source_world_sha256")!=FileAccess.get_sha256("res://resources/world_geometry/world.json") or raw.get("source_catalog_sha256")!=FileAccess.get_sha256("res://assets/authored/interiors/source_catalog.json"):return _fail("게임 연결통로와 도시 원본이 다릅니다.")
	for source: Dictionary in raw.links:
		if not host.city.source_nodes.has(String(source.get("building_id",""))) or int(source.get("station_index",-1))!=0:return _fail("연결 대상 원본 건물이 없습니다.")
		var row: Dictionary=source.duplicate(true);var station: Dictionary=metro.stations[0];row.station_door=station.frame*Vector3(float(row.corridor_center_x),3.08,float(row.corridor_end_z)-1.2);row.station_return=station.frame*Vector3(float(row.corridor_center_x),3.08,float(row.corridor_end_z)-3.7)
		links.append(row)
	_build_corridors();loaded=true
	print("GAME_UNDERGROUND_READY links=2 authored_B1=2 original_source_floors_unchanged=true explicit_game_portals=true")
	return true
func _fail(message: String) -> bool:load_error=message;return false
func _event(kind: String,details: Dictionary={}) -> void:
	events.append({"event":kind,"tick":Engine.get_physics_frames(),"details":details.duplicate(true)})
	if events.size()>100:events.pop_front()
func _build_corridors() -> void:
	var station: Dictionary=metro.stations[0];var concourse: Node3D=station.node
	for title: String in ["ConcourseBackWallBody","ConcourseBackWall"]:
		var old: Node3D=concourse.get_node_or_null(title)
		if is_instance_valid(old):
			if old is CollisionObject3D:old.collision_layer=0
			old.queue_free()
	var tile:=Color(.79,.83,.80);var blue:=Color(.06,.31,.43)
	# Two native openings through the authored concourse back wall; centre
	# surface exit and the station's original stair/card-gate route stay intact.
	for section: Vector2 in [Vector2(-9.,-6.),Vector2(-2.8,2.8),Vector2(6.,9.)]:metro._box(concourse,"ConnectionWallSection",Vector3(section.y-section.x,3.6,.16),Vector3((section.x+section.y)*.5,4.8,36.),tile,true)
	metro._box(concourse,"ConnectionDoorHeaders",Vector3(18.,1.2,.16),Vector3(0.,6.1,36.),tile,true)
	metro._label(concourse,"GameConnectionWayfinding","지하철 계단 ↓   게임 지하 연결통로 ↑\n서울도서관 B1  ·  서울특별시청 B1",Vector3(-5.9,4.9,30.),5.,29)
	for row: Dictionary in links:
		var corridor:=Node3D.new();corridor.name=String(row.id);metro.underground.add_child(corridor);corridor.global_transform=station.frame;row.corridor=corridor
		var x: float=float(row.corridor_center_x);var start: float=float(row.corridor_start_z);var end: float=float(row.corridor_end_z);var width: float=float(row.corridor_width_m);var length: float=end-start
		metro._box(corridor,"GameConnectorFloor",Vector3(width,.22,length+.4),Vector3(x,2.89,(start+end)*.5),tile,true)
		metro._box(corridor,"GameConnectorCeiling",Vector3(width,.15,length+.4),Vector3(x,6.7,(start+end)*.5),Color(.73,.77,.73),true)
		for side: float in [-1.,1.]:
			metro._box(corridor,"GameConnectorSideWall",Vector3(.16,3.6,length+.4),Vector3(x+side*width*.5,4.8,(start+end)*.5),tile,true)
			metro._box(corridor,"GameConnectorLineBand",Vector3(.18,.20,length+.3),Vector3(x+side*(width*.5-.08),4.05,(start+end)*.5),blue)
		metro._box(corridor,"GameConnectorEndWall",Vector3(width,3.6,.16),Vector3(x,4.8,end),tile,true)
		metro._box(corridor,"GamePortalFrame",Vector3(2.55,2.6,.12),Vector3(x,4.3,end-.12),blue)
		metro._label(corridor,"GameBuildingPortal","E · "+String(row.building_title)+" B1\n게임 지하 연결통로",Vector3(x,4.5,end-.20),2.45,30)
		metro._label(corridor,"ConnectionDestination",String(row.building_title)+" B1 ↑\n게임 지하 연결통로",Vector3(x,5.8,start+.35),3.0,28)
		for z: float in [start+3.,start+8.,end-2.]:
			metro._box(corridor,"ConnectorTactileRoute",Vector3(.35,.012,2.2),Vector3(x,3.006,z),Color(.92,.72,.14))
			var light:=OmniLight3D.new();light.position=Vector3(x,6.1,z);light.omni_range=9.;light.light_energy=.85;light.shadow_enabled=false;corridor.add_child(light)
		metro.bounds=metro.bounds.expand(row.station_door+Vector3(3.,1.,3.)).expand(row.station_door-Vector3(3.,.4,3.))
func _paused() -> bool:return not loaded or host.menu.visible or get_tree().paused or not host.input_router.gameplay_enabled
func _foot_ready() -> bool:
	if _paused() or host.player.input_latched or host.player.facility_control or not host.player.is_physics_processing():return false
	if host.has_method("_street_transport_riding") and host._street_transport_riding():return false
	var shop: Node3D=host.get("shop_visit_service")
	if is_instance_valid(shop) and (shop.active or shop.ui_open or shop.swimwear_active):return false
	return metro._supported(host.player.global_position)
func _line_clear(point: Vector3) -> bool:
	for height: float in [.75,1.3]:
		var query:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*height,point+Vector3.UP*height,1|32,[host.player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():return false
	return true
func _candidate() -> Dictionary:
	if not _foot_ready():return {}
	if metro.active and not metro.riding and metro.visit_station==0 and not metro._release_pending:
		for row: Dictionary in links:
			if host.player.global_position.distance_to(row.station_door)<=1.9 and _line_clear(row.station_door):return {"kind":"building","link":row}
	var visit: Node3D=host.interior_visit
	if visit.active and not visit.in_elevator and not visit.elevator_open and not visit.on_roof and is_instance_valid(visit.room) and visit.room.authored_basement_count>0 and visit.room.floor_index_at(host.player.global_position)==-1 and not visit.facility_interaction.is_using():
		for row: Dictionary in links:
			if String(row.building_id)!=String(visit.current_spec.id):continue
			var point: Vector3=visit.room.basement_portal_point()
			if host.player.global_position.distance_to(point)<=1.9 and _line_clear(point):return {"kind":"station","link":row}
	return {}
func can_interact() -> bool:return not _candidate().is_empty()
func handle_interact() -> bool:
	var candidate: Dictionary=_candidate()
	if candidate.is_empty():return false
	if _last_interact_tick==Engine.get_physics_frames():return true
	_last_interact_tick=Engine.get_physics_frames()
	if not pending.is_empty():return true
	var row: Dictionary=candidate.link
	if String(candidate.kind)=="station":_return_to_station(row);return true
	if not host.interior_visit.prepare_connected_basement(String(row.building_id)):_blocked("건물 연결 공간을 확인하지 못했습니다.",row);return true
	pending={"id":row.id,"building_id":row.building_id,"started_tick":Engine.get_physics_frames()};metro._tell(String(row.building_title)+" 연결문을 준비합니다.");_event("requested_building_link",{"id":row.id});return true
func _blocked(message: String,row: Dictionary) -> void:
	blocked_transfers+=1
	if metro.active:metro._tell(message)
	elif host.interior_visit.active:host.interior_visit._tell(message)
	_event("transfer_refused_owner_preserved",{"id":row.get("id",""),"reason":message});pending.clear()
func _physics_process(_delta: float) -> void:
	if not loaded or pending.is_empty():return
	var candidate: Dictionary=_candidate()
	if candidate.is_empty() or String(candidate.get("kind",""))!="building" or String(candidate.link.id)!=String(pending.id):_event("pending_cancelled_owner_preserved");pending.clear();return
	var row: Dictionary=candidate.link
	if not host.interior_visit.connected_basement_ready(String(row.building_id)):return
	var visit: Node3D=host.interior_visit;var point: Vector3=visit.room.basement_arrival_point();var outside: Dictionary={}
	for at: Vector3 in [visit.current_spec.entrance,visit.current_spec.entrance+visit.current_spec.outward*.6]:
		outside=visit._safe_external_point(at)
		if not outside.is_empty():break
	if outside.is_empty() or not visit._point_supported_clear(point,visit.room.interior_bounds,Transform3D.IDENTITY,Rect2()) or not host.player.relocate_interior_region(point,visit.room.interior_bounds):_blocked("도착할 B1 공간이 막혀 있습니다. 연결문 앞에서 기다려 주세요.",row);return
	var context: Dictionary=metro.release_to_connected_building();visit.adopt_connected_basement(context,outside.point)
	transfers_to_building+=1;pending.clear();_event("entered_game_building_B1",{"id":row.id,"point":point,"outdoor_recovery_preserved":true})
func _return_to_station(row: Dictionary) -> bool:
	var point: Vector3=row.station_return
	if metro.active or metro.riding or not metro._safe_indoor(point) or not host.player.relocate_interior_region(point,metro.bounds):_blocked("역 연결문이 막혀 있습니다. B1에서 기다려 주세요.",row);return false
	var context: Dictionary=host.interior_visit.release_to_connected_station();metro.adopt_from_connected_building(context,int(row.station_index))
	transfers_to_station+=1;_event("returned_to_game_station",{"id":row.id,"point":point,"outdoor_recovery_preserved":true});return true
func prompt_text() -> String:
	var candidate: Dictionary=_candidate()
	if candidate.is_empty():return ""
	if not pending.is_empty():return "연결문 준비 중 · "+String(candidate.link.building_title)+" B1"
	return "E · "+String(candidate.link.building_title)+" B1 · 게임 지하 연결통로" if String(candidate.kind)=="building" else "E · 시청역 대합실로 돌아가기 · 게임 지하 연결통로"
func cancel_pending_for_transition() -> void:
	if not pending.is_empty():_event("external_transition_cancelled_pending");pending.clear()
func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in links:rows.append({"id":row.id,"building_id":row.building_id,"building_title":row.building_title,"source_floor_count":row.source_floor_count,"authored_basement_count":row.authored_basement_count,"station_door":row.station_door,"station_return":row.station_return,"geographic_center_distance_m":row.geographic_center_distance_from_source_entrance_m})
	return {"loaded":loaded,"error":load_error,"links":rows,"pending":pending.duplicate(true),"transfers_to_building":transfers_to_building,"transfers_to_station":transfers_to_station,"blocked_transfers":blocked_transfers,"events":events.duplicate(true),"scope":"Authored game B1/tunnels and explicit validated detached-interior portals; original building identities and source envelopes only, no real underground network/plan claim."}

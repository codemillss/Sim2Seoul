extends Node3D
## Fictional game police, non-graphic melee and short reversible custody.
## Original actor identities, routes, terrain and city geometry are retained.
const AVATAR := preload("res://scripts/player/exploration_avatar.gd")
const CHASE_SECONDS := 60.0
const GRID_M := 3.0
const POST_COVERAGE_M := 90.0
const MAX_DISTRICT_OFFICERS := 14
const RESPONDING_OFFICERS := 2
const REPORT_ARRIVAL_DISTANCE_M := 8.0
const REACTION := preload("res://scripts/actor_hit_reaction.gd")
const RENTAL_DEPARTURE_CLEAR_M := 8.0
const OFFICER_CLEARANCE_RADIUS_M := .27
const RENTAL_CLEARANCE_MARGIN_M := .15
class VisualReset extends Node3D:
	func _physics_process(_delta: float) -> void:transform=Transform3D.IDENTITY
class PoseFinish extends Node:
	var service: Node3D
	func _physics_process(_delta: float) -> void:service._finish_poses()
class Officer extends CharacterBody3D:
	var facility_control := false
	func _physics_process(_delta: float) -> void:pass
var police_facility: Node3D
var police_headquarters: Node3D
var patrol_vehicle_service: Node3D
var host: Node3D
var loaded := false
var load_error := ""
var wanted := false
var detained := false
var chase_remaining_s := 0.0
var detention_remaining_s := 0.0
var custody_kind := ""
var offense_count := 0
var officers: Array[Dictionary] = []
var events: Array[Dictionary] = []
var station_point := Vector3.ZERO
var maximum_step_m := 0.0
var actual_officer_distance_m := 0.0
var path_replans := 0
var catches := 0
var releases := 0
var hits := 0
var _clock := 0.0
var _next_punch_s := 0.0
var guarding := false
var _combat_action: Dictionary = {}
var _combo_step := 0
var _combo_expires_s := 0.0
var _notice := ""
var _notice_until := 0.0
var _cell_cache: Dictionary = {}
var _edge_cache: Dictionary = {}
var maximum_path_plan_ms := 0.0
var maximum_path_job_cpu_ms := 0.0
var render_frames := 0
var maximum_render_anchor_error_m := 0.0
var _saved: Dictionary = {}
var _room: Node3D
var _room_origin := Vector3(4800,120,4800)
var _custody_text: Label3D
var _cooldown_s := 0.0
var _mat_blue: StandardMaterial3D
var _source_hashes: Dictionary = {}
var _door_index: RefCounted
var public_playable_fallback_queries := 0
var _offense_point := Vector3.ZERO
var _offense_reason := ""
var _response_started_s := 0.0
var _first_arrival_s := -1.0
var _dispatch_coverage: Array[Dictionary] = []
var _dispatch_attempted: Dictionary = {}

func setup(scene: Node3D) -> bool:
	if loaded or not is_inside_tree() or not is_instance_valid(scene):return false
	host=scene;name="CityPublicSafety";process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=3
	if not is_instance_valid(host.get("city_bike_service")) or not host.city_bike_service.loaded:load_error="경찰의 원본 공공 지면이 준비되지 않았습니다.";return false
	for path: String in ["res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://assets/authored/neighborhood_population.json"]:_source_hashes[path]=FileAccess.get_sha256(path)
	_door_index=preload("res://scripts/source_polygon_index.gd").new()
	var door_points: Array[Vector2]=[]
	for door: Vector3 in host.city_bike_service._doors:door_points.append(Vector2(door.x,door.z))
	_door_index.setup_points(door_points)
	_mat_blue=_material(Color(.035,.12,.28))
	# Visible initial postings, never a crime-triggered teleport or replacement
	# of original NPC identities. All later travel uses native swept movement.
	var slots: Array[int]=[0,2,4,6]
	for index: int in slots:
		if index>=host.city_bike_service.stations.size():continue
		var station: Dictionary=host.city_bike_service.stations[index]
		var origin: Vector3=host.city_bike_service.bikes[index].body.global_position
		var safe:=_find_open(origin,5.0+float(index))
		if safe.is_empty():continue
		_make_officer(safe.point,index)
	_add_district_postings()
	if officers.is_empty():load_error="경찰의 안전한 공공 배치 공간이 없습니다.";return false
	var finish:=PoseFinish.new();finish.service=self;finish.process_physics_priority=4;add_child(finish)
	station_point=officers[0].home
	_make_custody_room()
	police_facility=preload("res://scripts/city_police_facility.gd").new();add_child(police_facility)
	if not police_facility.setup(host,self):load_error=police_facility.load_error;return false
	station_point=police_facility.entry_point
	patrol_vehicle_service=preload("res://scripts/city_police_patrol.gd").new();add_child(patrol_vehicle_service)
	if not patrol_vehicle_service.setup(host,self,police_facility):load_error=patrol_vehicle_service.load_error;return false
	police_headquarters=preload("res://scripts/city_police_headquarters.gd").new();add_child(police_headquarters)
	if not police_headquarters.setup(host,self):load_error=police_headquarters.load_error;return false
	loaded=true;print("CITY_PUBLIC_SAFETY_READY officers=",officers.size()," chase_seconds=",CHASE_SECONDS," game_authored=true")
	return true

func _event(kind: String,evidence: Dictionary={}) -> void:
	if events.size()>=100:events.pop_front()
	events.append({"event":kind,"clock_s":_clock,"evidence":evidence})
func _material(color: Color) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.86;return mat
func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,mat: Material,solid:=false) -> Node3D:
	var node:=MeshInstance3D.new();node.name=title;var shape:=BoxMesh.new();shape.size=size;node.mesh=shape;node.material_override=mat;node.position=at;parent.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.name=title+"Collision";body.collision_layer=32;var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;collider.shape=box;body.add_child(collider);parent.add_child(body);body.position=at
	return node
func _label(parent: Node3D,title: String,text: String,at: Vector3,size:=.004) -> Label3D:
	var node:=Label3D.new();node.name=title;node.text=text;node.font_size=38;node.pixel_size=size;node.position=at;node.outline_size=4;node.billboard=BaseMaterial3D.BILLBOARD_ENABLED;parent.add_child(node);return node
func _ground(at: Vector3) -> Dictionary:
	var y: float=host.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,y+1.0,at.z),Vector3(at.x,y-1.0,at.z),1|32))
	if hit.is_empty() or hit.normal.y<.78:return {}
	return {"point":Vector3(at.x,hit.position.y+.006,at.z),"rid":hit.rid}
func _source_allowed(at: Vector3) -> bool:
	var service: Node3D=host.city_bike_service
	var local: Vector3=host.city.to_local(at);var flat:=Vector2(local.x,local.z)
	if not host.player.free_roam_bounds.grow(-.6).has_point(Vector2(at.x,at.z)) or service._private_index.contains(flat):return false
	if is_instance_valid(_door_index) and _door_index.within_distance(Vector2(at.x,at.z),.75):return false
	if service._walk_index.contains(flat) or service._road_index.contains(flat):return true
	# The player's original free-exploration TIN joins several real source
	# footways and roads across narrow non-private verges. Police are walking
	# NPCs, so allow that same existing game-playable public ground rather than
	# inheriting rental-vehicle-only surface gaps. Native support, full capsule
	# clearance/sweeps, bounds, private rings and entry setbacks still gate it.
	if is_finite(host.terrain_surface.ground_y_world(at)):
		public_playable_fallback_queries+=1;return true
	return false
func _supported(at: Vector3,check_actors:=false) -> Dictionary:
	for offset: Vector3 in [Vector3.ZERO,Vector3(.28,0,0),Vector3(-.28,0,0),Vector3(0,0,.28),Vector3(0,0,-.28)]:
		if not _source_allowed(at+offset):return {}
	var floor:=_ground(at)
	if floor.is_empty():return {}
	var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,floor.point+Vector3.UP*.86);query.collision_mask=1|32|(2|4|8 if check_actors else 0);query.exclude=[floor.rid];query.margin=.003
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	return floor
func _rental_reservation_conflicts(point: Vector3) -> Array:
	var conflicts: Array=[]
	var padding:=OFFICER_CLEARANCE_RADIUS_M+RENTAL_CLEARANCE_MARGIN_M
	for service: Node3D in [host.city_bike_service,host.city_scooter_service]:
		for station: Dictionary in service.stations:
			var local: Vector3=station.node.to_local(point);var flat:=Vector2(local.x,local.z)
			# Exact retained rental-body footprint swept eight metres forward,
			# expanded by the police capsule radius plus a small safety margin.
			var departure:=Rect2(Vector2(-.35-padding,-.95-RENTAL_DEPARTURE_CLEAR_M-padding),Vector2(.70+2.*padding,1.90+RENTAL_DEPARTURE_CLEAR_M+2.*padding))
			if departure.has_point(flat):conflicts.append({"station":station.id,"kind":"full_body_forward_departure","station_local_xz":flat});continue
			# Full rack, post and board ground envelopes, independent of visual
			# mesh collisions, plus ordinary human access beside/behind a dock.
			var fixtures:=Rect2(Vector2(-1.66-padding,.475-padding),Vector2(2.26+2.*padding,.35+2.*padding))
			if fixtures.has_point(flat):conflicts.append({"station":station.id,"kind":"station_fixture_projection","station_local_xz":flat});continue
			for access: Vector2 in [Vector2(-1.9,.1),Vector2(1.9,.1),Vector2(0,1.9)]:
				if flat.distance_to(access)<.35+padding:conflicts.append({"station":station.id,"kind":"human_boarding_access","station_local_xz":flat});break
	return conflicts
func _posting_floor(point: Vector3) -> Dictionary:
	# Initial/home/release/viewpoint markers stay on explicit source walk/road;
	# only continuous pursuit uses original playable-TIN connectors.
	var local: Vector3=host.city.to_local(point);var flat:=Vector2(local.x,local.z)
	if not (host.city_bike_service._walk_index.contains(flat) or host.city_bike_service._road_index.contains(flat)):return {}
	if not _rental_reservation_conflicts(point).is_empty():return {}
	var floor:=_supported(point,true)
	if floor.is_empty():return {}
	for door: Vector3 in host.city_bike_service._doors:
		if Vector2(point.x-door.x,point.z-door.z).length()<1.6:return {}
	return floor
func _find_open(origin: Vector3,radius:=5.0,connected_to:=Vector3(INF,INF,INF)) -> Dictionary:
	for distance: float in [radius,radius+2.,radius+4.,radius+6.,radius+9.]:
		for index: int in range(16):
			var angle:=float(index)*TAU/16.;var point:=origin+Vector3(sin(angle),0,cos(angle))*distance;var floor:=_posting_floor(point)
			if not floor.is_empty() and (not connected_to.is_finite() or _segment_allowed(floor.point,connected_to,host.player)):return floor
			# Preserve already safe postings. A candidate blocked specifically by
			# a rental reservation can move a small amount across the footway,
			# before trying a distant radial point or altering other postings.
			if _rental_reservation_conflicts(point).is_empty():continue
			for nudge: float in [.9,1.2,1.6,2.1]:
				for offset: Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3(-.7071,0,-.7071),Vector3(.7071,0,-.7071),Vector3(-.7071,0,.7071),Vector3(.7071,0,.7071)]:
					floor=_posting_floor(point+offset*nudge)
					if not floor.is_empty() and (not connected_to.is_finite() or _segment_allowed(floor.point,connected_to,host.player)):return floor
	return {}
func rental_clearance_snapshot() -> Dictionary:
	var violations: Array=[];var posted_violations: Array=[]
	for row: Dictionary in officers:
		for conflict: Dictionary in _rental_reservation_conflicts(row.home):violations.append({"officer":String(row.body.name),"home":row.home,"conflict":conflict})
		if row.state=="posted":
			for conflict: Dictionary in _rental_reservation_conflicts(row.body.global_position):posted_violations.append({"officer":String(row.body.name),"point":row.body.global_position,"conflict":conflict})
	return {"reserved_docks":host.city_bike_service.stations.size()+host.city_scooter_service.stations.size(),"officers":officers.size(),"forward_clearance_m":RENTAL_DEPARTURE_CLEAR_M,"officer_radius_m":OFFICER_CLEARANCE_RADIUS_M,"extra_margin_m":RENTAL_CLEARANCE_MARGIN_M,"home_violations":violations,"posted_violations":posted_violations,"scope":"All original source rental fixtures, native-body forward departure and boarding access guarded during police posting/home/release/viewpoint choice. Pursuit remains physical and may temporarily occupy roads like other people."}
func _make_officer(at: Vector3,index: int) -> void:
	var body:=Officer.new();body.name="GamePoliceOfficer"+str(index+1);body.set_meta("game_police",true);body.collision_layer=4;body.collision_mask=1|2|4|8|32;body.floor_snap_length=.35;body.safe_margin=.001;body.floor_max_angle=deg_to_rad(38.)
	var collider:=CollisionShape3D.new();collider.name="CollisionShape";var capsule:=CapsuleShape3D.new();capsule.radius=.27;capsule.height=1.70;collider.shape=capsule;collider.position.y=.85;body.add_child(collider)
	var visual:=Node3D.new();visual.name="Visual";body.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";visual.add_child(original);add_child(body);body.global_position=at
	var avatar:=AVATAR.new();avatar.setup(body)
	for key: String in ["jacket","jacket_trim","trousers"]:avatar._materials[key].albedo_color=Color(.035,.12,.28) if key!="jacket_trim" else Color(.06,.25,.40)
	_box(visual,"PoliceCap",Vector3(.27,.10,.26),Vector3(0,1.64,0),_mat_blue)
	_box(visual,"CapVisor",Vector3(.28,.027,.17),Vector3(0,1.60,-.14),_mat_blue)
	_box(visual,"ReflectiveVest",Vector3(.44,.11,.27),Vector3(0,1.17,0),_material(Color(.85,.9,.18)))
	_label(visual,"PoliceIdentity","경찰\nPOLICE",Vector3(0,2.02,0),.0026)
	var proxy:=VisualReset.new();proxy.name="InterpolatedPoliceVisual";proxy.process_physics_priority=-100;visual.add_child(proxy)
	for child: Node in visual.get_children():
		if child!=proxy:child.reparent(proxy,false)
	host.traffic.register_human(body)
	officers.append({"body":body,"visual":visual,"avatar":avatar,"home":at,"path":PackedVector3Array(),"path_index":0,"replan_s":0.,"path_job":{},"proxy":proxy,"previous_pose":visual.global_transform,"current_pose":visual.global_transform,"state":"posted","distance_m":0.,"stuck_s":0.})
func _add_district_postings() -> void:
	# Initial public patrol posts cover the original dispersed city population.
	# No offense handler changes any officer transform or creates a responder.
	for adult: Dictionary in _adult_candidates():
		if adult.body.get_meta("game_police",false):continue
		var at: Vector3=adult.body.global_position;var nearest:=INF
		for row: Dictionary in officers:nearest=minf(nearest,row.home.distance_to(at))
		if nearest>POST_COVERAGE_M and officers.size()<MAX_DISTRICT_OFFICERS:
			var safe:=_find_open(at,24.,at)
			if safe.is_empty():safe=_find_open(at,12.,at)
			if not safe.is_empty():_make_officer(safe.point,officers.size()+10)
	for adult: Dictionary in _adult_candidates():
		if adult.body.get_meta("game_police",false):continue
		var nearest:=INF
		for row: Dictionary in officers:nearest=minf(nearest,row.home.distance_to(adult.body.global_position))
		_dispatch_coverage.append({"target_path":String(adult.body.get_path()),"nearest_initial_post_m":nearest})

func _make_station_sign() -> void:
	var marker:=Node3D.new();marker.name="GamePolicePostMarker";add_child(marker);marker.global_position=station_point
	_box(marker,"PostPole",Vector3(.07,2.6,.07),Vector3(-.65,1.3,0),_mat_blue)
	_box(marker,"PostSign",Vector3(1.7,.85,.09),Vector3(-.65,2.55,0),_mat_blue)
	_label(marker,"StationLabel","경찰 · 안전 안내소\n게임용 가상 시설",Vector3(-.65,2.55,-.06),.0027)
func _make_custody_room() -> void:
	_room=Node3D.new();_room.name="FictionalInvestigationAndHoldingRoom";add_child(_room);_room.global_position=_room_origin
	var wall:=_material(Color(.76,.79,.75));var floor:=_material(Color(.33,.39,.42));var wood:=_material(Color(.36,.24,.15));var metal:=_material(Color(.12,.16,.20))
	_box(_room,"AuthoredRoomFloor",Vector3(10,.25,10),Vector3(0,-.125,0),floor,true)
	for side: float in [-1.,1.]:_box(_room,"SideWall",Vector3(.2,3.3,10),Vector3(side*5.,1.65,0),wall,true)
	_box(_room,"BackWall",Vector3(10,3.3,.2),Vector3(0,1.65,5.),wall,true)
	_box(_room,"Desk",Vector3(1.5,.14,.8),Vector3(0,.74,-1.2),wood,true)
	_box(_room,"DeskLeg",Vector3(1.1,.7,.6),Vector3(0,.35,-1.2),metal)
	_box(_room,"Bench",Vector3(2.5,.4,.6),Vector3(2.9,.2,1.2),wood,true)
	for index: int in range(9):_box(_room,"HoldingBars",Vector3(.045,2.7,.045),Vector3(1.7,.0+1.35,-2.+index*.75),metal)
	_custody_text=_label(_room,"CustodyInformation","게임용 가상 조사실 · 유치장\n잠시 후 자동 귀가",Vector3(0,2.35,-2.4),.006)
	var light:=OmniLight3D.new();light.position=Vector3(0,3.1,0);light.light_energy=2.;light.omni_range=12.;_room.add_child(light)
	_room.visible=false
func _adult_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for body: CharacterBody3D in host.pedestrians:result.append({"body":body,"avatar":body.get_node_or_null("Visual/ExplorationAvatar")})
	for controller: Node in [host.street_pedestrians,host.neighborhood_population.walkers]:
		for row: Dictionary in controller.actors:
			if row.kind=="walker":result.append({"body":row.body,"avatar":row.get("avatar")})
	for row: Dictionary in officers:result.append({"body":row.body,"avatar":row.avatar})
	var takeover: Variant=host.get("traffic_car_takeover")
	if is_instance_valid(takeover):
		for row: Dictionary in takeover.drivers:
			if is_instance_valid(row.body):result.append({"body":row.body,"avatar":row.avatar})
	return result
func _line_clear(a: Vector3,b: Vector3,excludes: Array[RID]=[]) -> bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1|8|32,excludes)).is_empty()
func _on_ordinary_ground() -> bool:
	if host.player.interior_active or host.player.facility_control or not host.player.is_physics_processing():return false
	var floor:=_ground(host.player.global_position)
	return not floor.is_empty() and absf(host.player.global_position.y-floor.point.y)<.35 and absf(host.player.velocity.y)<1.0
func punch() -> bool:
	if not _can_start_melee():return false
	if _clock>_combo_expires_s:_combo_step=0
	var kinds: Array[String]=["jab_left","cross_right","hook_left"]
	var durations: Array[float]=[];var contacts: Array[float]=[]
	for kind: String in kinds:
		var duration: float=host.exploration_avatar.sandbox_action_duration(kind)
		durations.append(duration);contacts.append(duration*host.exploration_avatar.sandbox_contact_phase(kind))
	var index:=_combo_step%3;_combo_step=index+1
	_start_melee(kinds[index],durations[index],contacts[index],_combo_step)
	return true
func shove() -> bool:
	if not _can_start_melee():return false
	_combo_step=0;_combo_expires_s=0.
	var duration: float=host.exploration_avatar.sandbox_action_duration("shove")
	_start_melee("shove",duration,duration*host.exploration_avatar.sandbox_contact_phase("shove"),0)
	return true
func _can_start_melee() -> bool:
	return loaded and not detained and not guarding and _combat_action.is_empty() and _clock>=_next_punch_s and not host.menu.visible and _on_ordinary_ground()
func set_guarding(active: bool) -> bool:
	var allowed: bool=loaded and not detained and not host.menu.visible and _on_ordinary_ground() and _combat_action.is_empty()
	guarding=active and allowed
	if is_instance_valid(host) and is_instance_valid(host.exploration_avatar) and host.exploration_avatar.has_method("set_sandbox_guarding"):host.exploration_avatar.set_sandbox_guarding(guarding)
	if not guarding and not allowed and is_instance_valid(host) and host.exploration_avatar.has_method("cancel_sandbox_action"):host.exploration_avatar.cancel_sandbox_action("guard")
	if guarding:_combo_step=0;_combo_expires_s=0.
	return guarding
func _start_melee(kind: String,duration: float,contact: float,combo: int) -> void:
	_next_punch_s=_clock+duration;_combo_expires_s=_next_punch_s+.85
	_combat_action={"kind":kind,"started_s":_clock,"contact_s":_clock+contact,"ends_s":_next_punch_s,"contact_resolved":false,"combo_step":combo}
	if host.exploration_avatar.has_method("play_sandbox_action"):host.exploration_avatar.play_sandbox_action(kind,duration)
	_event("melee_started",{"action":kind,"combo_step":combo,"windup_s":contact,"duration_s":duration})
func _advance_melee() -> void:
	if guarding and (detained or not _on_ordinary_ground()):set_guarding(false)
	if _combat_action.is_empty():return
	# Targets are queried at contact, rather than reserved on the key press.
	# Walking away, turning, boarding or an intervening wall can make it miss.
	if detained or not _on_ordinary_ground():
		_cancel_melee_for_owner_change();return
	if not _combat_action.contact_resolved:
		var native: Dictionary=host.exploration_avatar.get_sandbox_strike_contact(String(_combat_action.kind)) if host.exploration_avatar.has_method("get_sandbox_strike_contact") else {}
		if bool(native.get("valid",false)):
			_combat_action["previous_knuckle"]= _combat_action.get("current_knuckle",native.point)
			_combat_action["current_knuckle"]=native.point
		if _clock+0.000001>=float(_combat_action.contact_s):
			_combat_action.contact_resolved=true;_resolve_melee_contact(String(_combat_action.kind))
	if _clock+0.000001>=float(_combat_action.ends_s):_combat_action.clear()
func _cancel_melee_for_owner_change() -> void:
	if _combat_action.is_empty():return
	var kind:=String(_combat_action.kind)
	if host.exploration_avatar.has_method("cancel_sandbox_action"):host.exploration_avatar.cancel_sandbox_action(kind)
	_event("melee_cancelled",{"action":kind,"reason":"ordinary_ground_ownership_lost"});_combat_action.clear()
func combat_snapshot() -> Dictionary:
	var phase:="idle"
	if not _combat_action.is_empty():phase="windup" if not _combat_action.contact_resolved else "recovery"
	return {"action":String(_combat_action.get("kind","")),"phase":phase,"combo_step":int(_combat_action.get("combo_step",_combo_step)),"guarding":guarding,"contact_resolved":bool(_combat_action.get("contact_resolved",false)),"remaining_s":maxf(0.,float(_combat_action.get("ends_s",_clock))-_clock),"contact_in_s":maxf(0.,float(_combat_action.get("contact_s",_clock))-_clock),"guard_is_cosmetic":true}
func _resolve_melee_contact(kind: String) -> void:
	var avatar: Node3D=host.exploration_avatar
	var contact: Dictionary=avatar.get_sandbox_strike_contact(kind) if avatar.has_method("get_sandbox_strike_contact") else {}
	var best:=INF;var target: Dictionary={};var contact_error:=INF
	# An actual knuckle/palm must overlap the victim's upper torso, rather
	# than selecting anyone inside a remote 1.9 m cone from the player root.
	if bool(contact.get("valid",false)):
		var fist: Vector3=contact.point
		for row: Dictionary in _adult_candidates():
			var body: CharacterBody3D=row.body
			var separation: float=body.global_position.distance_to(host.player.global_position)
			if separation>1.35 or absf(body.global_position.y-host.player.global_position.y)>.45:continue
			var spine_bottom:=body.global_position+Vector3.UP*.97;var spine_top:=body.global_position+Vector3.UP*1.56
			var nearest: Vector3=Geometry3D.get_closest_point_to_segment(fist,spine_bottom,spine_top)
			var error: float=nearest.distance_to(fist)
			var previous: Vector3=_combat_action.get("previous_knuckle",fist)
			if previous.distance_to(fist)<.6:
				for index: int in range(5):
					var swept: Vector3=previous.lerp(fist,float(index)/4.)
					var axis: Vector3=Geometry3D.get_closest_point_to_segment(swept,spine_bottom,spine_top)
					if swept.distance_to(axis)<error:nearest=axis;error=swept.distance_to(axis)
			contact["previous_point"]=previous
			if error>float(contact.get("radius_m",.105))+.255 or error>=best:continue
			if not _line_clear(fist,nearest,[host.player.get_rid(),body.get_rid()]):continue
			if not _line_clear(host.player.global_position+Vector3.UP*1.20,nearest,[host.player.get_rid(),body.get_rid()]):continue
			target=row;best=error;contact_error=error
	if target.is_empty():
		_notice="밀기 · 손이 몸에 닿아야 합니다" if kind=="shove" else "헛스윙 · 가까이서 주먹이 닿아야 합니다";_notice_until=_clock+1.2
		_event("melee_missed",{"action":kind,"native_contact":contact});_event("punch_missed",{"action":kind});return
	hits+=1
	var reaction_s:=.65 if kind=="shove" else .48
	if is_instance_valid(target.avatar) and target.avatar.has_method("play_sandbox_action"):target.avatar.play_sandbox_action("flinch",reaction_s)
	var away: Vector3=target.body.global_position-host.player.global_position;away.y=0.
	var reaction:=REACTION.new();reaction.name="PhysicalHitReaction";add_child(reaction);reaction.start(self,target.body,away.normalized(),kind)
	_event("melee_contact",{"action":kind,"target_path":String(target.body.get_path()),"distance_m":target.body.global_position.distance_to(host.player.global_position),"native_contact":contact,"native_contact_error_m":contact_error,"reaction_s":reaction_s,"non_graphic":true})
	_event("adult_hit",{"action":kind,"target_path":String(target.body.get_path()),"distance_m":target.body.global_position.distance_to(host.player.global_position),"non_graphic":true});report_offense("폭행 신고",host.player.global_position)
func report_offense(reason: String,at: Vector3) -> void:
	if not loaded or detained or not at.is_finite():return
	offense_count+=1;wanted=true;chase_remaining_s=CHASE_SECONDS;_cooldown_s=0.
	_offense_point=at;_offense_reason=reason;_response_started_s=_clock;_first_arrival_s=-1.
	var ranked: Array[Dictionary]=officers.duplicate();_dispatch_attempted.clear()
	for row: Dictionary in ranked:
		var distance: float=row.body.global_position.distance_to(at)
		row["dispatch_direct"]=distance<160. and _segment_allowed(row.body.global_position,at,row.body)
		row["dispatch_score"]=distance+(0. if row.dispatch_direct else 160.)
	ranked.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.dispatch_score<b.dispatch_score)
	for row: Dictionary in officers:
		var responding: bool=ranked.find(row)<RESPONDING_OFFICERS
		row.state="pursuing" if responding else ("posted" if row.body.global_position.distance_to(row.home)<.45 else "returning")
		row.replan_s=0.;row.path_job={};row.path=PackedVector3Array();row.path_index=0
		if responding:_dispatch_attempted[str(row.body.name)]=true;row["dispatch_progress_at_s"]=_clock;row["dispatch_progress_m"]=row.distance_m
	_notice=reason;_notice_until=_clock+3.;_event("offense_reported",{"reason":reason,"at":at,"reset_chase_s":CHASE_SECONDS,"nearest_initial_responder_m":ranked[0].body.global_position.distance_to(at),"responders":ranked.slice(0,RESPONDING_OFFICERS).map(func(row: Dictionary)->String:return String(row.body.name))})


func _replace_blocked_responder(row: Dictionary) -> void:
	if _clock-float(row.get("dispatch_progress_at_s",_clock))<8.:return
	var advanced: float=row.distance_m-float(row.get("dispatch_progress_m",row.distance_m))
	row.dispatch_progress_at_s=_clock;row.dispatch_progress_m=row.distance_m
	if advanced>1.:return
	var candidate: Dictionary={};var best:=INF;var at: Vector3=host.player.global_position
	for other: Dictionary in officers:
		if other==row or other.state=="pursuing" or _dispatch_attempted.has(str(other.body.name)):continue
		var distance: float=other.body.global_position.distance_to(at)
		if distance>160. or distance>=best or not _segment_allowed(other.body.global_position,at,other.body):continue
		candidate=other;best=distance
	if candidate.is_empty():return
	row.state="returning";row.replan_s=0.;row.path_job={};row.path=PackedVector3Array()
	candidate.state="pursuing";candidate.replan_s=0.;candidate.path_job={};candidate.path=PackedVector3Array();candidate.path_index=0;candidate["dispatch_progress_at_s"]=_clock;candidate["dispatch_progress_m"]=candidate.distance_m
	_dispatch_attempted[str(candidate.body.name)]=true
	_event("blocked_responder_reassigned",{"blocked_officer":str(row.body.name),"replacement":str(candidate.body.name),"replacement_distance_m":best,"stationary_for_game_s":8.,"teleported":false})

func _cell(key: Vector2i) -> Dictionary:
	if _cell_cache.has(key):return _cell_cache[key]
	var sample:=Vector3(float(key.x)*GRID_M,0,float(key.y)*GRID_M);var value:=_supported(sample)
	_cell_cache[key]=value;return value
func _segment_allowed(a: Vector3,b: Vector3,officer: CharacterBody3D) -> bool:
	var distance:=a.distance_to(b)
	for index: int in range(1,maxi(2,ceili(distance/.65))+1):
		var sample:=a.lerp(b,float(index)/maxi(2,ceili(distance/.65)))
		if not _source_allowed(sample):return false
	var shape:=CapsuleShape3D.new();shape.radius=.27;shape.height=1.70;var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,a+Vector3.UP*.88);query.collision_mask=1|32;query.exclude=[officer.get_rid()];query.margin=.003;query.motion=b-a
	return get_world_3d().direct_space_state.cast_motion(query)[0]>=.999
func _graph_edge_allowed(a: Vector3,b: Vector3,body: CharacterBody3D) -> bool:
	var key:=str(a)+":"+str(b)
	if _edge_cache.has(key):return bool(_edge_cache[key])
	if _edge_cache.size()>60000:_edge_cache.clear()
	var clear:=_segment_allowed(a,b,body);_edge_cache[key]=clear;return clear
func _request_path(row: Dictionary,target: Vector3) -> void:
	path_replans+=1
	var body: CharacterBody3D=row.body;var started:=Time.get_ticks_usec();var floor:=_supported(target)
	if not floor.is_empty() and _segment_allowed(body.global_position,floor.point,body):
		row.path=PackedVector3Array([floor.point]);row.path_index=0;row.path_job={};maximum_path_plan_ms=maxf(maximum_path_plan_ms,float(Time.get_ticks_usec()-started)/1000.);return
	var from:=Vector2i(roundi(body.global_position.x/GRID_M),roundi(body.global_position.z/GRID_M));var toward:=Vector2(target.x-body.global_position.x,target.z-body.global_position.z).limit_length(96.)
	var desired:=Vector2i(roundi((body.global_position.x+toward.x)/GRID_M),roundi((body.global_position.z+toward.y)/GRID_M));var low:=Vector2i(mini(from.x,desired.x)-4,mini(from.y,desired.y)-4);var high:=Vector2i(maxi(from.x,desired.x)+4,maxi(from.y,desired.y)+4)
	row.path_job={"phase":"nodes","target":target,"origin":body.global_position,"desired":desired,"low":low,"high":high,"x":low.x,"z":low.y,"graph":AStar3D.new(),"keys":{},"nearest_start":-1,"nearest_goal":-1,"start_distance":INF,"goal_distance":INF,"key_list":[],"edge_index":0,"edge_direction":0,"cpu_ms":0.}
	maximum_path_plan_ms=maxf(maximum_path_plan_ms,float(Time.get_ticks_usec()-started)/1000.)
func _advance_path_job(row: Dictionary,budget_ms:=1.5) -> void:
	if row.path_job.is_empty():return
	var started:=Time.get_ticks_usec();var job: Dictionary=row.path_job;var graph: AStar3D=job.graph;var body: CharacterBody3D=row.body
	# Spread graph construction across physics ticks. Each officer gets a small
	# budget, while its last native-safe path remains usable. No background
	# thread reads the physics world and no physics body is interpolated.
	while float(Time.get_ticks_usec()-started)/1000.<budget_ms:
		if job.phase=="nodes":
			if job.x>job.high.x:job.phase="edges";job.key_list=job.keys.keys();continue
			var key:=Vector2i(job.x,job.z);job.z+=1
			if job.z>job.high.y:job.z=job.low.y;job.x+=1
			var cell:=_cell(key)
			if cell.is_empty():continue
			var id:=graph.get_available_point_id();job.keys[key]=id;graph.add_point(id,cell.point)
			var first: float=job.origin.distance_to(cell.point);var last: float=Vector2(key-job.desired).length()
			if first<float(job.start_distance) and first<GRID_M*2. and _segment_allowed(job.origin,cell.point,body):job.start_distance=first;job.nearest_start=id
			if last<float(job.goal_distance):job.goal_distance=last;job.nearest_goal=id
		elif job.phase=="edges":
			if job.edge_index>=job.key_list.size():
				job.phase="reachable";job["frontier"]=[int(job.nearest_start)] if job.nearest_start>=0 else [];job["reached"]={int(job.nearest_start):true};job["cursor"]=0;job.nearest_goal=-1;job.goal_distance=INF;continue
			var key: Vector2i=job.key_list[job.edge_index];var directions: Array[Vector2i]=[Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)];var next: Vector2i=key+directions[job.edge_direction]
			job.edge_direction+=1
			if job.edge_direction>=4:job.edge_index+=1;job.edge_direction=0
			if job.keys.has(next) and _graph_edge_allowed(graph.get_point_position(job.keys[key]),graph.get_point_position(job.keys[next]),body):graph.connect_points(job.keys[key],job.keys[next])
		elif job.phase=="reachable":
			# Connectivity selection shares the same per-tick budget as graph
			# construction. An isolated point near a target is not a valid goal.
			if job.cursor>=job.frontier.size():job.phase="finish";continue
			var id: int=job.frontier[job.cursor];job.cursor+=1
			var distance: float=graph.get_point_position(id).distance_to(job.target)
			if distance<float(job.goal_distance):job.goal_distance=distance;job.nearest_goal=id
			for linked: int in graph.get_point_connections(id):
				if not job.reached.has(linked):job.reached[linked]=true;job.frontier.append(linked)
		else:
			var path:=PackedVector3Array()
			if job.nearest_start>=0 and job.nearest_goal>=0:
				path=graph.get_point_path(job.nearest_start,job.nearest_goal)
				var finish: Dictionary=_supported(job.target)
				if not path.is_empty() and not finish.is_empty() and _segment_allowed(path[-1],finish.point,body):path.append(finish.point)
			# The officer can have advanced along its prior path while searching.
			# Begin at a currently reachable point; never snap back to the old start.
			var best_index:=0;var best:=INF
			for index: int in range(path.size()):
				var distance: float=body.global_position.distance_to(path[index])
				if distance<best and distance<GRID_M*2. and _segment_allowed(body.global_position,path[index],body):best=distance;best_index=index
			row.path=path if is_finite(best) else PackedVector3Array();row.path_index=best_index;row.path_job={};break
	var spent:=float(Time.get_ticks_usec()-started)/1000.;maximum_path_plan_ms=maxf(maximum_path_plan_ms,spent);job.cpu_ms+=spent;maximum_path_job_cpu_ms=maxf(maximum_path_job_cpu_ms,float(job.cpu_ms))
func _move_officer(row: Dictionary,target: Vector3,delta: float,speed: float) -> void:
	var body: CharacterBody3D=row.body;var before:=body.global_position;var direction:=target-before;direction.y=0.
	var next:=before+direction.limit_length(speed*delta);var support:=_supported(next)
	if not support.is_empty() and _segment_allowed(before,support.point,body):
		body.velocity=Vector3(direction.x,0,direction.z).normalized()*minf(speed,direction.length()/delta);body.velocity.y=(support.point.y-before.y)/delta-.9
	else:body.velocity=Vector3.ZERO
	body.move_and_slide();var step: float=before.distance_to(body.global_position);maximum_step_m=maxf(maximum_step_m,step);actual_officer_distance_m+=step;row.distance_m+=step
	if step>.005:row.visual.rotation.y=atan2(-direction.x,-direction.z);row.stuck_s=0.
	else:row.stuck_s+=delta
	if row.stuck_s>1.5:row.replan_s=0.;row.stuck_s=0.;row.path_job={};_edge_cache.clear();_cell_cache.clear()
func _occupied_ground_car() -> Dictionary:
	for name: String in ["drivable_car_service","traffic_car_takeover"]:
		var service: Variant=host.get(name)
		if not is_instance_valid(service) or service.get("riding")!=true:continue
		var index: int=int(service.get("rental_index"))
		if index>=0 and index<service.bikes.size():return {"service":service,"body":service.bikes[index].body}
	return {}
func _pursuit_target(row: Dictionary) -> Vector3:
	var occupied:=_occupied_ground_car()
	if occupied.is_empty():return host.player.global_position
	var body: CharacterBody3D=occupied.body;var left: Vector3=body.to_global(Vector3(-1.75,0,-.38));var right: Vector3=body.to_global(Vector3(1.75,0,-.38))
	return left if row.body.global_position.distance_to(left)<row.body.global_position.distance_to(right) else right
func _catchable(row: Dictionary) -> bool:
	if _cooldown_s>0.:return false
	var excludes: Array[RID]=[row.body.get_rid(),host.player.get_rid()]
	var occupied:=_occupied_ground_car()
	if not occupied.is_empty():
		var car: CharacterBody3D=occupied.body
		if absf(float(occupied.service.speed_mps))>2.0:return false
		var car_floor:=_ground(car.global_position)
		if car_floor.is_empty() or absf(car.global_position.y-car_floor.point.y)>.35:return false
		var near_door:=false
		for side: float in [-1.,1.]:
			if row.body.global_position.distance_to(car.to_global(Vector3(side*1.20,0,-.38)))<=1.05:near_door=true
		if not near_door:return false
		excludes.append(car.get_rid())
	else:
		if row.body.global_position.distance_to(host.player.global_position)>1.30:return false
		var floor:=_ground(host.player.global_position)
		if floor.is_empty() or absf(host.player.global_position.y-floor.point.y)>.65 or absf(host.player.velocity.y)>1.2:return false
	# Vehicle owners keep their own speed. A zero rider velocity cannot make
	# an airborne helicopter or an underground train susceptible to arrest.
	for name: String in ["city_bike_service","city_scooter_service","city_helicopter_service","city_subway_service"]:
		var service: Variant=host.get(name)
		if is_instance_valid(service) and service.get("riding")==true:
			if name.contains("helicopter") or name.contains("subway") or absf(float(service.get("speed_mps")))>2.0:return false
	return _line_clear(row.body.global_position+Vector3.UP*1.2,host.player.global_position+Vector3.UP*1.2,excludes)
func _capture() -> bool:
	if detained or not host.has_method("city_sandbox_force_ground_exit"):return false
	var selected_host_mode: bool=host.free_roam_enabled
	var selected_player_mode: bool=host.player.free_roam_enabled
	var next_kind: String="investigation" if offense_count<2 else "holding"
	var room_point:=_room_origin+Vector3(0. if next_kind=="investigation" else 3.,.03,.5)
	if not host.city_sandbox_force_ground_exit(room_point):_event("capture_safe_transition_rejected");return false
	_cancel_melee_for_owner_change();set_guarding(false)
	if host.exploration_avatar.has_method("cancel_sandbox_action"):host.exploration_avatar.cancel_sandbox_action("guard")
	_saved={"free_roam":selected_host_mode,"player_free_roam":selected_player_mode,"physics":host.player.is_physics_processing(),"visual":host.player.get_node("Visual").transform,"rig_yaw":host.rig.yaw,"rig_pitch":host.rig.pitch,"rig_distance":host.rig.requested_distance,"rig_pivot":host.rig.pivot_height_m}
	detained=true;wanted=false;chase_remaining_s=0.;catches+=1;custody_kind=next_kind;detention_remaining_s=8. if custody_kind=="investigation" else 12.
	host.player.set_facility_control(true);host.player.set_physics_process(false);host.player.velocity=Vector3.ZERO;host.player.get_node("Visual").rotation=Vector3.ZERO;host.player.reset_physics_interpolation();_room.visible=true
	host.rig.yaw=0.;host.rig.pitch=deg_to_rad(-12.);host.rig.requested_distance=4.0;host.rig.current_distance=4.0;host.rig.pivot_height_m=1.;host.rig.snap_to_target_pose()
	for row: Dictionary in officers:row.state="returning";row.replan_s=0.
	_event("captured",{"room":"game_authored_detached_room","kind":custody_kind,"duration_s":detention_remaining_s});return true
func _release() -> bool:
	if not detained:return false
	var safe:=_find_open(station_point,3.)
	if not bool(_saved.get("free_roam",true)) and (safe.is_empty() or not host.city.movement_contains(Vector2(safe.point.x,safe.point.z))):
		safe={}
		# Return to the original connected public-walk spawn when the first
		# safe posting-side point belongs only to broader free exploration.
		var spawn: Dictionary=host.interior_visit._safe_external_point(host.player.spawn_transform.origin)
		if not spawn.is_empty() and host.city.movement_contains(Vector2(spawn.point.x,spawn.point.z)):safe=spawn
	if safe.is_empty():detention_remaining_s=1.;_event("release_safe_point_retry");return false
	# Internal custody exit must be allowed by the host while menu teleports
	# remain blocked for detained players.
	if not host.city_sandbox_force_ground_exit(safe.point):detention_remaining_s=1.;return false
	detained=false;releases+=1;_cooldown_s=5.;_room.visible=false;host.player.get_node("Visual").transform=_saved.visual;host.player.set_facility_control(false);host.player.set_physics_process(true);host.player.velocity=Vector3.ZERO;host.player.require_neutral_input();host.player.reset_physics_interpolation()
	host.set_free_roam(bool(_saved.get("free_roam",true)));host.player.free_roam_enabled=bool(_saved.get("player_free_roam",host.free_roam_enabled))
	host.rig.yaw=_saved.rig_yaw;host.rig.pitch=_saved.rig_pitch;host.rig.requested_distance=_saved.rig_distance;host.rig.current_distance=_saved.rig_distance;host.rig.pivot_height_m=_saved.rig_pivot;host.rig.snap_to_target_pose();_saved.clear();_notice="조사 종료 · 안전 안내소 앞 귀가";_notice_until=_clock+4.;_event("released",{"point":safe.point});return true
func _nearest_facility() -> Node3D:
	var target: Node3D;var distance:=INF
	for facility: Node3D in [police_facility,police_headquarters]:
		if not is_instance_valid(facility) or not facility.loaded or not facility.can_interact():continue
		var range_m: float=facility.interaction_distance_m()
		if range_m<distance:target=facility;distance=range_m
	return target
func can_interact() -> bool:return detained and detention_remaining_s<=.1 if detained else is_instance_valid(_nearest_facility())
func interaction_distance_m() -> float:
	if detained:return 0. if can_interact() else INF
	var target:=_nearest_facility();return target.interaction_distance_m() if is_instance_valid(target) else INF
func interact() -> bool:
	if detained:return _release() if can_interact() else false
	var target:=_nearest_facility();return target.handle_interact() if is_instance_valid(target) else false
func handle_interact() -> bool:return interact()
func prompt_text() -> String:
	if detained:return ("조사실" if custody_kind=="investigation" else "유치장")+" · "+str(ceili(detention_remaining_s))+"초 후 자동 귀가 · 게임용 가상 절차"
	if wanted:
		var nearest:=INF
		for row: Dictionary in officers:
			if row.state=="pursuing":nearest=minf(nearest,row.body.global_position.distance_to(host.player.global_position))
		return _offense_reason+" · 경찰 "+str(roundi(nearest))+"m · "+str(ceili(chase_remaining_s))+"초 후 추격 포기"
	var target:=_nearest_facility();return target.prompt_text() if is_instance_valid(target) else ""
func status_text() -> String:
	if is_instance_valid(police_facility) and police_facility.active:return police_facility.status_text()
	if detained or wanted:return prompt_text()
	if is_instance_valid(police_headquarters) and police_headquarters.contains_player():return police_headquarters.status_text()
	if guarding:return "G 방어 자세 · F 연속 타격 · X 밀기 · 경찰 체포는 막지 못합니다"
	return _notice if _clock<_notice_until else "F 잽→스트레이트→훅 · X 밀기 · G 방어 자세"
func viewpoint() -> Dictionary:
	if is_instance_valid(police_facility) and police_facility.loaded:return police_facility.viewpoint()
	var safe:=_find_open(station_point,4.)
	if safe.is_empty():return {}
	return {"point":safe.point,"toward":station_point+Vector3.UP,"camera_distance":4.8,"scope":"Game-authored police posting on retained public source surface."}
func _physics_process(delta: float) -> void:
	if not loaded or delta<=0. or host.menu.visible:return
	_clock+=delta;_cooldown_s=maxf(0.,_cooldown_s-delta)
	_advance_melee()
	if detained:
		detention_remaining_s=maxf(0.,detention_remaining_s-delta);_custody_text.text=("조사실 · 진술 확인 중" if custody_kind=="investigation" else "유치장 · 재범 임시 보호")+"\n"+str(ceili(detention_remaining_s))+"초 후 자동 귀가\n게임용 가상 시설 · 실제 절차와 무관"
		if detention_remaining_s<=0.:_release()
	elif wanted:
		chase_remaining_s=maxf(0.,chase_remaining_s-delta)
		if chase_remaining_s<=0.:
			wanted=false;_notice="추격 종료 · 경찰 복귀 중";_notice_until=_clock+4.;_event("escaped_after_sixty_seconds")
			for row: Dictionary in officers:row.state="returning";row.replan_s=0.
	for row: Dictionary in officers:
		if wanted and row.state=="pursuing":_replace_blocked_responder(row)
		if REACTION.owns(row.body):continue
		if row.state=="posted":row.body.velocity=Vector3(0,-.9,0);row.body.move_and_slide();continue
		var target: Vector3=_pursuit_target(row) if row.state=="pursuing" and wanted else row.home
		if row.state=="returning" and row.body.global_position.distance_to(row.home)<.45:
			# A route can finish a fraction of a metre short of its waypoint.
			# Do not publish a permanently posted officer inside a reserved dock
			# corridor merely because its correctly reserved home is nearby.
			if not _rental_reservation_conflicts(row.body.global_position).is_empty():_move_officer(row,row.home,delta,1.0);continue
			row.state="posted";row.body.velocity=Vector3.ZERO;_event("officer_returned",{"name":String(row.body.name)});continue
		row.replan_s-=delta
		if row.replan_s<=0.:
			if row.path_job.is_empty() or target.distance_to(row.path_job.target)>8.:_request_path(row,target)
			row.replan_s=2.0+float(officers.find(row))*.15
		_advance_path_job(row)
		var path: PackedVector3Array=row.path
		while row.path_index<path.size() and row.body.global_position.distance_to(path[row.path_index])<.35:row.path_index+=1
		if row.path_index<path.size():_move_officer(row,path[row.path_index],delta,5.4 if wanted else 2.5)
		else:row.body.velocity=Vector3(0,-.9,0);row.body.move_and_slide()
		if wanted and row.state=="pursuing" and _first_arrival_s<0. and row.body.global_position.distance_to(_offense_point)<REPORT_ARRIVAL_DISTANCE_M:
			_first_arrival_s=_clock-_response_started_s;_event("officer_arrived_at_report",{"officer":String(row.body.name),"elapsed_game_s":_first_arrival_s,"offense_distance_m":row.body.global_position.distance_to(_offense_point)})
		if wanted and row.state=="pursuing" and _catchable(row):
			if _capture():break
func _finish_poses() -> void:
	if not loaded:return
	for row: Dictionary in officers:row.previous_pose=row.current_pose;row.current_pose=row.visual.global_transform
func _process(_delta: float) -> void:
	if not loaded or get_tree().paused:return
	render_frames+=1;var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	for row: Dictionary in officers:
		var expected: Transform3D=row.previous_pose.interpolate_with(row.current_pose,fraction);row.proxy.global_transform=expected;maximum_render_anchor_error_m=maxf(maximum_render_anchor_error_m,row.proxy.global_position.distance_to(expected.origin))
func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in officers:rows.append({"name":String(row.body.name),"position":row.body.global_position,"home":row.home,"state":row.state,"on_floor":row.body.is_on_floor(),"avatar_state":row.avatar.state,"distance_m":row.distance_m,"source_allowed":_source_allowed(row.body.global_position),"native_supported":not _supported(row.body.global_position).is_empty(),"render_anchor":row.proxy.global_position,"previous_anchor":row.previous_pose.origin,"physics_anchor":row.current_pose.origin,"pending_path_job":not row.path_job.is_empty(),"capsule_retained":row.body.get_node("CollisionShape").shape is CapsuleShape3D,"layer":row.body.collision_layer,"mask":row.body.collision_mask})
	return {"loaded":loaded,"load_error":load_error,"combat":combat_snapshot(),"district_coverage":_dispatch_coverage,"active_responders":officers.filter(func(row: Dictionary)->bool:return row.state=="pursuing").size(),"offense_point":_offense_point,"offense_reason":_offense_reason,"first_arrival_s":_first_arrival_s,"report_arrival_radius_m":REPORT_ARRIVAL_DISTANCE_M,"police_facility":police_facility.snapshot() if is_instance_valid(police_facility) else {},"police_headquarters":police_headquarters.snapshot() if is_instance_valid(police_headquarters) else {},"patrol_vehicle":patrol_vehicle_service.snapshot() if is_instance_valid(patrol_vehicle_service) else {},"rental_posting_clearance":rental_clearance_snapshot(),"wanted":wanted,"detained":detained,"chase_remaining_s":chase_remaining_s,"detention_remaining_s":detention_remaining_s,"custody_kind":custody_kind,"offense_count":offense_count,"officers":rows,"hits":hits,"catches":catches,"releases":releases,"police_navigation_domain":"Original source walk/drive plus native-supported, non-private original game-playable TIN connectors; source entry setback .75m and complete native capsule guards retained. Vehicle domains unchanged.","public_playable_fallback_queries":public_playable_fallback_queries,"path_replans":path_replans,"maximum_path_plan_ms":maximum_path_plan_ms,"maximum_path_job_cpu_ms":maximum_path_job_cpu_ms,"path_job_budget_ms_per_officer":1.5,"render_frames":render_frames,"maximum_render_anchor_error_m":maximum_render_anchor_error_m,"static_graph_cells":_cell_cache.size(),"static_graph_edges":_edge_cache.size(),"maximum_step_m":maximum_step_m,"actual_officer_distance_m":actual_officer_distance_m,"events":events,"source_hashes":_source_hashes,"scope":"Fictional non-graphic sandbox; adult humans only; 60-second game-time pursuit, native original public-playable TIN capsule paths and LOS ground catch; reversible 8/12-second authored custody; no real police procedure or geography claim."}

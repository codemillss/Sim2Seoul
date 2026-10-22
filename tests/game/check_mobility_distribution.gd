extends SceneTree
## Distribution acceptance on the entire ordinary scene. Only supported player
## observer starts are placed. Vehicles, actors, source nodes and supports retain
## their production transforms and controllers throughout the test.
class HeldMovementFixture extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness.call("_refresh_held_actions")

var scene: Node3D
var checks: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var observer_starts: Array[Dictionary]=[]
var station_trials: Array[Dictionary]=[]
var dock_geometry: Dictionary={}
var report_path:="/tmp/mobility-distribution.json"
var finished:=false
var started:=0
var startup_elapsed_ms:=0
var _loaded_hashes: Dictionary={}
var _held_actions: Dictionary={}
var _initial_inventory: Dictionary={}
var _initial_actors: Array=[]
var _initial_capsule: Dictionary={}
var _initial_tin:=0
var _original_recovery_count:=0
var _completed_stations:=0
var _expected_stations:=0
var _native:=false
const DEPARTURE_M:=3.4
const HASH_PATHS: Array[String]=[
	"res://scripts/city_bike_service.gd","res://scripts/city_scooter_service.gd",
	"res://assets/authored/bike_service.json","res://assets/authored/scooter_service.json",
	"res://scripts/transport_motion_policy.gd","res://scripts/player/free_roam_player.gd",
	"res://scripts/player/public_player.gd","res://scripts/player/palace_player.gd",
	"res://scripts/player/daehanmun_player.gd","res://scripts/player/movement_controller.gd",
	"res://scripts/player/idle_support.gd","res://scripts/player/camera_rig.gd",
	"res://scripts/player/exploration_camera.gd","res://scripts/player/exploration_avatar.gd",
	"res://scripts/input_router.gd","res://scripts/interior_visit.gd",
	"res://scripts/explore_walk.gd","res://scripts/source_polygon_index.gd",
	"res://resources/world_geometry/world.json","res://data/generated/public_walk.json",
	"res://data/generated/terrain_surface.json","res://data/generated/traffic.json",
	"res://assets/authored/neighborhood_population.json","res://assets/authored/road_furniture.json",
	"res://assets/authored/bus_service.json","res://scenes/world/explore_walk.tscn",
	"res://../tests/game/check_mobility_distribution.gd"
]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):push_error("Use a new absolute report path");quit(2);return
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var held:=HeldMovementFixture.new();held.name="TestOnlyHeldMovementFixture";held.harness=self;held.process_physics_priority=-200;held.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(held)
	_native=DisplayServer.get_name()!="headless";Engine.max_fps=0;started=Time.get_ticks_msec()
	create_timer(540.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_completion_guard",false);_finish()
	)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	if value is float:return value if is_finite(value) else null
	return value

func _hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in HASH_PATHS:result[path]=FileAccess.get_sha256(path)
	return result

func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("MOBILITY_DISTRIBUTION_CHECK ",title," ",ok)
	if not ok:push_warning("MOBILITY_DISTRIBUTION_FAIL "+title)

func _ticks(count: int) -> void:
	for tick: int in range(count):await scene.rig.camera_stepped

func _key(action: String,down: bool) -> void:
	if down:_held_actions[action]=true
	else:_held_actions.erase(action);Input.action_release(action)
	var event:=InputEventAction.new();event.action=action;event.pressed=down;event.device=42;Input.parse_input_event(event)

func _refresh_held_actions() -> void:
	for action: String in _held_actions:Input.action_press(action)

func _e(down: bool) -> void:
	var key:=InputEventKey.new();key.physical_keycode=KEY_E;key.keycode=KEY_E;key.pressed=down;key.device=42;Input.parse_input_event(key)

func _tap_e() -> void:
	_e(true);await _ticks(2);_e(false);await _ticks(4)

func _inventory() -> Dictionary:
	var out: Dictionary={}
	for key: String in scene.city.source_nodes:
		var node: Node3D=scene.city.source_nodes[key];var children: Array=[]
		for child: Node in node.get_children():children.append(child.get_instance_id())
		out[key]={"instance":node.get_instance_id(),"transform":node.global_transform,"children":children}
	return out

func _actors() -> Array:
	var out: Array=[]
	for group: Array in [scene.pedestrians,scene.street_pedestrians.actors,scene.neighborhood_population.walkers.actors,scene.vehicles,scene.neighborhood_population.traffic.vehicles]:
		for row: Variant in group:
			var body: Node3D=row if row is Node3D else row.get("body",row.get("node"))
			if is_instance_valid(body):out.append(body.get_instance_id())
	out.sort();return out

func _capsule() -> Dictionary:
	var shape: CollisionShape3D=scene.player.get_node("CollisionShape")
	return {"player":scene.player.get_instance_id(),"shape":shape.shape.get_instance_id(),"shape_transform":shape.transform,"radius":shape.shape.radius,"height":shape.shape.height,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask}

func _native_support(service: Node3D,at: Vector3) -> Dictionary:
	var y: float=scene.terrain_surface.ground_y_world(at)
	if not is_finite(y):return {}
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(at.x,y+1.,at.z),Vector3(at.x,y-1.,at.z),1|32)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(float(service.design.policy.maximum_grade_degrees))):return {}
	return hit

func _sign_departure_intersections(body: CharacterBody3D,other: Node3D,own_id: String) -> Array:
	# Inspect actual rendered station fixture vertices in this vehicle's local
	# frame, rather than trusting an authored lateral offset or station ID.
	var conflicts: Array=[]
	for station: Dictionary in other.stations:
		if station.id==own_id:continue
		var pending: Array[Node]=[station.node]
		while not pending.is_empty():
			var node: Node=pending.pop_back()
			for child: Node in node.get_children():pending.append(child)
			if not node is MeshInstance3D or not is_instance_valid(node.mesh):continue
			var name:=String(node.name)
			if not (name.begins_with("StationPost") or name in ["StationHeader","StationInformation","IconBackground","ScooterIconBackground"]):continue
			var box: AABB=node.get_aabb();var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
			for corner: int in range(8):
				var point: Vector3=body.to_local(node.to_global(box.get_endpoint(corner)));low=low.min(point);high=high.max(point)
			if high.x>-.35 and low.x<.35 and high.y>.03 and low.y<1.93 and high.z>-.95-DEPARTURE_M and low.z<.95:conflicts.append({"station":station.id,"fixture":name,"local_min":low,"local_max":high})
	return conflicts

func _fixture_projection_source(service: Node3D,index: int) -> Dictionary:
	# Read complete actual fixture mesh AABB envelopes, including their posts,
	# sign edges and pictograms. The <=18cm surface lattice conservatively
	# projects these envelopes to source ground; it does not trust a few chosen
	# authored fixture offsets or add a test-only walk permission polygon.
	var pending: Array[Node]=[service.stations[index].node];var samples:=0;var failures: Array=[];var failed_samples:=0;var meshes:=0
	while not pending.is_empty():
		var node: Node=pending.pop_back()
		for child: Node in node.get_children():pending.append(child)
		if not node is MeshInstance3D or not is_instance_valid(node.mesh):continue
		meshes+=1;var box: AABB=node.get_aabb()
		var nx:=maxi(1,ceili(box.size.x/.18));var ny:=maxi(1,ceili(box.size.y/.18));var nz:=maxi(1,ceili(box.size.z/.18))
		for x: int in range(nx+1):
			for y: int in range(ny+1):
				for z: int in range(nz+1):
					if x not in [0,nx] and y not in [0,ny] and z not in [0,nz]:continue
					var vertex: Vector3=box.position+box.size*Vector3(float(x)/nx,float(y)/ny,float(z)/nz)
					var at: Vector3=node.to_global(vertex);var local: Vector3=scene.city.to_local(at);var flat:=Vector2(local.x,local.z);samples+=1
					if service._walk_index.contains(flat) and not service._road_index.contains(flat) and not scene.city._contains(flat,scene.city.private_cache):continue
					failed_samples+=1
					if failures.size()<12:failures.append({"mesh":String(node.name),"point":at})
	return {"ok":failed_samples==0 and meshes>0,"actual_meshes":meshes,"projection_samples":samples,"failed_samples":failed_samples,"sample_failures":failures,"scope":"Conservative actual mesh-envelope surface samples projected onto original exterior walk, with original drive/private exclusion; <=0.18m lattice spacing."}

func _terrain_departure_cast(service: Node3D,body: CharacterBody3D,support_rids: Array[RID],yaw: float) -> Dictionary:
	var shape:=BoxShape3D.new();shape.size=Vector3(.70,1.90,1.90)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1|2|4|8|32;query.margin=.003;query.exclude=[body.get_rid(),scene.player.get_rid()]
	for rid: RID in support_rids:query.exclude.append(rid)
	var start_hit:=_native_support(service,body.global_position)
	if start_hit.is_empty():return {"ok":false,"reason":"start_support_missing"}
	var foot_gap: float=maxf(.001,body.global_position.y-start_hit.position.y);var before: Vector3=body.global_position;var direction: Vector3=-Basis(Vector3.UP,yaw).z
	var steps:=ceili(DEPARTURE_M/.15);var minimum_fraction:=1.;var failures: Array=[];var native_initial_hits: Array=[];var query_count:=0;var maximum_segment:=0.
	var space:=scene.get_world_3d().direct_space_state
	for step: int in range(steps):
		var endpoint: Vector3=body.global_position+direction*DEPARTURE_M*float(step+1)/steps;var support:=_native_support(service,endpoint)
		if support.is_empty():failures.append({"step":step,"reason":"support_missing","point":endpoint});break
		endpoint.y=support.position.y+foot_gap
		if not query.exclude.has(support.rid):
			var excluded: Array[RID]=query.exclude;excluded.append(support.rid);query.exclude=excluded
		var basis: Basis=service._pose_basis(before,yaw)
		query.transform=Transform3D(basis,before+basis*Vector3(0,.98,0));query.motion=Vector3.ZERO
		var initial: Array=space.intersect_shape(query,8);var names: Array=[]
		for hit: Dictionary in initial:names.append(String(hit.collider.name))
		if step==0:native_initial_hits=names
		query.motion=endpoint-before;maximum_segment=maxf(maximum_segment,query.motion.length());var cast: PackedFloat32Array=space.cast_motion(query);query_count+=1;minimum_fraction=minf(minimum_fraction,cast[0])
		if not initial.is_empty() or cast[0]<.9999:
			query.transform.origin+=query.motion*minf(1.,cast[0]+.015);query.motion=Vector3.ZERO;var hit_names: Array=[]
			for hit: Dictionary in space.intersect_shape(query,8):hit_names.append(String(hit.collider.name))
			failures.append({"step":step,"from":before,"to":endpoint,"fraction":cast[0],"initial_hits":names,"end_contact_hits":hit_names})
		before=endpoint
	return {"ok":failures.is_empty() and maximum_segment<=.18,"minimum_cast_fraction":minimum_fraction,"initial_hits":native_initial_hits,"failures":failures,"queries":query_count,"maximum_segment_m":maximum_segment,"scope":"Independent retained full-box native casts along native terrain support at <=0.18m actual 3D segments. A long flat cast on a sloped walk incorrectly intersects later ground; this test follows the actual ground rather than weakening collision masks."}

func _blocked_contact(service: Node3D,index: int) -> Dictionary:
	var body: CharacterBody3D=service.bikes[index].body;var support:=_native_support(service,body.global_position)
	var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.70,1.90,1.90);query.shape=shape;query.collision_mask=1|2|4|8|32;query.margin=.003;query.exclude=[body.get_rid(),scene.player.get_rid()]
	if not support.is_empty():var excluded: Array[RID]=query.exclude;excluded.append(support.rid);query.exclude=excluded
	if is_instance_valid(scene.terrain_surface.support):var excluded: Array[RID]=query.exclude;excluded.append(scene.terrain_surface.support.get_rid());query.exclude=excluded
	query.transform=Transform3D(body.global_basis,body.global_position+body.global_basis*Vector3(0,.98,0));query.motion=-body.global_basis.z*.25
	var space:=scene.get_world_3d().direct_space_state;var cast: PackedFloat32Array=space.cast_motion(query);query.transform.origin+=query.motion*minf(1.,cast[0]+.02);query.motion=Vector3.ZERO;var contacts: Array=[]
	for hit: Dictionary in space.intersect_shape(query,12):
		var actor: CollisionObject3D=hit.collider
		contacts.append({"path":String(actor.get_path()),"class":actor.get_class(),"RID":str(hit.rid),"registered_NPC":scene.traffic.humans.has(actor),"original_AI_car":scene.vehicles.has(actor) or scene.neighborhood_population.traffic.vehicles.has(actor),"game_bus":scene.city_bus_service.buses.has(actor)})
	return {"body_point":body.global_position,"reason":service.blocked_reason,"fraction_of_0_25m_diagnostic_sweep":cast[0],"contacts":contacts,"scope":"Read-only native contact diagnostic when actual production W is blocked; no occupancy, collisions or actor pose is changed."}

func _station_geometry(service: Node3D,index: int,other: Node3D) -> Dictionary:
	var body: CharacterBody3D=service.bikes[index].body;var failures: Array=[];var support_rids: Array[RID]=[];var samples:=0;var minimum_door:=INF;var supported:=true;var source_clear:=true;var parked_on_exterior_walk:=true;var parked_drive_overlap:=false
	for along: float in [0.,.85,1.7,2.55,DEPARTURE_M]:
		for x: float in [-.36,0.,.36]:
			for z: float in [-.96,0.,.96]:
				var point: Vector3=body.global_position+body.global_basis*Vector3(x,0,z-along);samples+=1
				var hit:=_native_support(service,point)
				if hit.is_empty():supported=false
				elif not support_rids.has(hit.rid):support_rids.append(hit.rid)
				var local: Vector3=scene.city.to_local(point);var flat:=Vector2(local.x,local.z)
				if scene.city._contains(flat,scene.city.private_cache):source_clear=false
				if not service._source_allowed(point):source_clear=false
				if along==0.:
					parked_on_exterior_walk=parked_on_exterior_walk and service._walk_index.contains(flat)
					parked_drive_overlap=parked_drive_overlap or service._road_index.contains(flat)
				for door: Vector3 in service._doors:minimum_door=minf(minimum_door,Vector2(point.x-door.x,point.z-door.z).length())
	if not supported:failures.append("missing_native_support_or_grade")
	if not source_clear:failures.append("source_private_boundary_or_door")
	if not parked_on_exterior_walk or parked_drive_overlap:failures.append("parked_body_outside_exterior_walk_or_in_original_drive")
	var fixture_projection:=_fixture_projection_source(service,index)
	if not fixture_projection.ok:failures.append("station_fixture_mesh_projection_outside_original_exterior_walk")
	var departure:=_terrain_departure_cast(service,body,support_rids,float(service.bikes[index].yaw))
	if not departure.ok:failures.append("native_full_body_or_departure_blocked")
	var sign_conflicts:=_sign_departure_intersections(body,other,service.stations[index].id)
	sign_conflicts.append_array(_sign_departure_intersections(body,service,service.stations[index].id))
	if not sign_conflicts.is_empty():failures.append("other_service_sign_in_departure")
	var closest_actor:=INF
	for actor: CharacterBody3D in scene.vehicles+scene.neighborhood_population.traffic.vehicles:closest_actor=minf(closest_actor,body.global_position.distance_to(actor.global_position))
	for bus: CharacterBody3D in scene.city_bus_service.buses:closest_actor=minf(closest_actor,body.global_position.distance_to(bus.global_position))
	return {"ok":failures.is_empty(),"station":service.stations[index].id,"source_route":service.stations[index].source_route,"point":body.global_position,"heading":service.bikes[index].yaw,"support_samples":samples,"parked_body_samples_on_exterior_walk":parked_on_exterior_walk,"parked_body_overlaps_original_drive":parked_drive_overlap,"station_fixture_projection":fixture_projection,"minimum_door_clearance_m":minimum_door,"required_door_clearance_m":service.design.policy.door_clearance_m,"departure_m":DEPARTURE_M,"native_departure":departure,"other_station_fixture_conflicts":sign_conflicts,"closest_current_original_car_or_game_bus_origin_m":closest_actor,"failures":failures}

func _place_observer(service: Node3D,index: int) -> Dictionary:
	var body: CharacterBody3D=service.bikes[index].body
	for offset: Vector3 in [Vector3(1.9,0,.1),Vector3(-1.9,0,.1),Vector3(1.35,0,.6),Vector3(-1.35,0,.6),Vector3(0,0,1.9),Vector3(0,0,-1.9)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.global_position+body.global_basis*offset)
		if safe.is_empty():continue
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.velocity=Vector3.ZERO;scene.player.require_neutral_input();scene.player.reset_physics_interpolation();await _ticks(5)
		if service._nearest_bike()==index and service.can_interact() and scene._street_interact_target()==service:
			var entry: Dictionary={"station":service.stations[index].id,"point":scene.player.global_position,"requested_local_offset":offset,"nearest_index":service._nearest_bike(),"visible":service._visible_bike(index),"ordinary_dispatch_target":String(service.name),"scope":"Test-only positively supported player observer start. No vehicle, source node or actor transform is written."};observer_starts.append(entry);return entry
	return {}

func _capture(service: Node3D,index: int,region: String) -> void:
	if not _native:return
	await _ticks(2);await RenderingServer.frame_post_draw
	var path:=report_path.get_basename()+"_"+region+"_"+String(service.stations[index].id)+".png";var image:=root.get_texture().get_image();var error:=image.save_png(path)
	_check("native_capture_"+region,error==OK,{"path":path,"size":[image.get_width(),image.get_height()]})
	if error==OK:captures.append({"path":path,"sha256":FileAccess.get_sha256(path),"station":service.stations[index].id,"region":region,"camera":scene.rig.snapshot(),"scope":"Unmodified production mount camera and actual ordinary native scene. Explicit player observer start only; image saving alone is not visual review."})

func _trial(service: Node3D,index: int,other: Node3D) -> void:
	var id: String=service.stations[index].id;var body: CharacterBody3D=service.bikes[index].body
	var geometry: Dictionary=dock_geometry[id];_check(id+"_full_native_supported_source_private_door_and_departure_clear",geometry.ok,geometry)
	var observer: Dictionary=await _place_observer(service,index);_check(id+"_safe_visible_observer_targets_exact_station",not observer.is_empty(),observer)
	if observer.is_empty():return
	var before_index: int=service._nearest_bike();var entry_count: int=scene.interior_visit.entry_count;var before: Vector3=body.global_position
	await _tap_e();var mounted: bool=service.riding and service.rental_index==index and not other.riding and scene.interior_visit.entry_count==entry_count
	_check(id+"_fresh_physical_E_dispatch_mounts_requested_vehicle",mounted,{"nearest_before_E":before_index,"rental_index":service.rental_index,"riding":service.riding,"other_riding":other.riding,"reason":service.blocked_reason,"events":service.events.slice(maxi(0,service.events.size()-3))})
	if not mounted:return
	if service==scene.city_bike_service and index==3:await _capture(service,index,"north")
	if service==scene.city_scooter_service and index==4:await _capture(service,index,"east")
	if service==scene.city_bike_service and index==5:await _capture(service,index,"south")
	if service==scene.city_scooter_service and index==6:await _capture(service,index,"west")
	await _ticks(2);_key("move_forward",true)
	var top:=0.;var unsupported:=0;var sample_count:=0;var blocked: Dictionary={};var contact_diagnostics: Array=[];var maximum_step:=0.;var previous: Vector3=body.global_position
	for tick: int in range(75):
		await _ticks(1);sample_count+=1;top=maxf(top,absf(service.speed_mps));maximum_step=maxf(maximum_step,body.global_position.distance_to(previous));previous=body.global_position
		if not body.is_on_floor():unsupported+=1
		if not service.blocked_reason.is_empty():
			blocked[service.blocked_reason]=int(blocked.get(service.blocked_reason,0))+1
			if contact_diagnostics.size()<4 and tick%10==0:contact_diagnostics.append(_blocked_contact(service,index))
		if Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length()>=1.8:break
	_key("move_forward",false);_key("jump",true)
	for tick: int in range(45):
		await _ticks(1)
		if absf(service.speed_mps)<.02:break
	_key("jump",false);await _ticks(3)
	var distance: float=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length();var travel: Dictionary={"station":id,"from":before,"to":body.global_position,"actual_travel_m":distance,"maximum_speed_mps":top,"stopped_speed_mps":service.speed_mps,"unsupported_forward_ticks":unsupported,"forward_samples":sample_count,"maximum_native_step_m":maximum_step,"blocked_ticks":blocked,"native_blocked_contact_diagnostics":contact_diagnostics,"body_on_floor":body.is_on_floor(),"body_retained":body.get_instance_id(),"scope":"Actual production W movement, native full box/casts and source/support checks followed by Space braking; no vehicle pose fixture."}
	_check(id+"_actual_W_travel_native_support_and_Space_stop",distance>=1.8 and top>.5 and unsupported<=1 and body.is_on_floor() and absf(service.speed_mps)<.02,travel)
	# Normal short travel stays within the existing return radius. If an
	# unusually long physics step carries it outside, use actual low-speed S
	# to return before E; never reset or teleport a vehicle for the next test.
	if service._near_station(body.global_position).is_empty():
		_key("move_backward",true)
		for tick: int in range(120):
			await _ticks(1)
			if body.global_position.distance_to(service.stations[index].point)<2.2:break
		_key("move_backward",false);_key("jump",true);await _ticks(10);_key("jump",false);await _ticks(2)
	await _tap_e();await _ticks(8)
	var returned: bool=not service.riding and service.rental_index<0 and scene.player.is_physics_processing() and not scene.player.facility_control and _capsule()==_initial_capsule and service._collision_release_pending.is_empty()
	_check(id+"_E_alights_returns_and_restores_original_controls_capsule",returned,{"riding":service.riding,"rental_index":service.rental_index,"player_physics":scene.player.is_physics_processing(),"facility_control":scene.player.facility_control,"pending_pairs":service._collision_release_pending.size(),"camera":scene.rig.snapshot(),"reason":service.blocked_reason})
	station_trials.append(travel);_completed_stations+=1

func _run() -> void:
	_loaded_hashes=_hashes()
	var settings_path:="/tmp/mobility-distribution-"+str(OS.get_process_id())+".json";var settings:=FileAccess.open(settings_path,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));settings.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings_path;scene.quality_settings_path=settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8);startup_elapsed_ms=Time.get_ticks_msec()-started
	_check("ordinary_production_scene_both_services_ready",scene.runtime_ok and scene.exploration_error.is_empty() and is_instance_valid(scene.city_bike_service) and scene.city_bike_service.loaded and is_instance_valid(scene.city_scooter_service) and scene.city_scooter_service.loaded,{"runtime_error":scene.exploration_error})
	if not scene.runtime_ok or not scene.exploration_error.is_empty():_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_initial_inventory=_inventory();_initial_capsule=_capsule();_initial_actors=_actors();_initial_tin=hash(scene.terrain_surface.faces);_original_recovery_count=scene.player.recoveries
	var source_world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"));var source_ids: Array=[]
	for mesh: Dictionary in source_world.meshes:source_ids.append(mesh.id)
	var dogs: int=scene.street_pedestrians.actors.filter(func(row: Dictionary)->bool:return row.kind=="dog").size();var people: int=scene.pedestrians.size()+scene.street_pedestrians.actors.size()+scene.neighborhood_population.walkers.actors.size()-dogs
	_check("original_source_nodes_28_people_2_dogs_14_vehicles_and_native_capsule_present",_initial_inventory.size()==source_ids.size() and source_ids.all(func(id: String)->bool:return _initial_inventory.has(id)) and people==28 and dogs==2 and scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size()==14 and _initial_actors.size()==44 and _initial_capsule.radius>0.,{"source_nodes":_initial_inventory.size(),"expected_original_world_ids":source_ids.size(),"retained_actors":_initial_actors.size(),"people":people,"dogs":dogs,"original_vehicles":scene.vehicles.size()+scene.neighborhood_population.traffic.vehicles.size(),"capsule":_initial_capsule})
	var counts: Dictionary={};var ids: Dictionary={};var coverage:=true
	for service: Node3D in [scene.city_bike_service,scene.city_scooter_service]:
		var name: String=service._motion_kind();counts[name]=service.stations.size();var regions: Dictionary={}
		for station: Dictionary in service.stations:
			if ids.has(station.id):coverage=false
			ids[station.id]=true;regions[station.source_route]=true
		coverage=coverage and service.stations.size()==service.design.stations.size() and service.bikes.size()==service.stations.size() and service.stations.size()>2 and regions.size()>=5
		_expected_stations+=service.stations.size();counts[name+"_source_routes"]=regions.keys()
	_check("data_driven_distributed_unique_native_stations_beyond_original_two",coverage,counts)
	# Snapshot and preflight all docks before any rider moves a production body.
	for service: Node3D in [scene.city_bike_service,scene.city_scooter_service]:
		var other: Node3D=scene.city_scooter_service if service==scene.city_bike_service else scene.city_bike_service
		for index: int in range(service.stations.size()):dock_geometry[service.stations[index].id]=_station_geometry(service,index,other)
	for service: Node3D in [scene.city_bike_service,scene.city_scooter_service]:
		var other: Node3D=scene.city_scooter_service if service==scene.city_bike_service else scene.city_bike_service
		for index: int in range(service.stations.size()):await _trial(service,index,other)
	_check("every_authored_station_completed_an_actual_dispatch_ride_and_return",_completed_stations==_expected_stations,{"expected_stations":_expected_stations,"completed_stations":_completed_stations})
	_check("original_source_nodes_actors_capsule_and_TIN_retained",_inventory()==_initial_inventory and _actors()==_initial_actors and _capsule()==_initial_capsule and hash(scene.terrain_surface.faces)==_initial_tin,{"source_nodes":_initial_inventory.size(),"actors":_initial_actors.size(),"TIN_faces":scene.terrain_surface.faces.size()/3})
	_check("all_trials_without_recovery_or_transport_ownership_leak",scene.player.recoveries==_original_recovery_count and not scene._street_transport_riding() and scene.city_bike_service._collision_release_pending.is_empty() and scene.city_scooter_service._collision_release_pending.is_empty(),{"recovery_count_before":_original_recovery_count,"recovery_count_after":scene.player.recoveries})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	for action: String in _held_actions:Input.action_release(action)
	_held_actions.clear();_e(false)
	var hashes:=_hashes();_check("all_relevant_runtime_source_and_test_inputs_stable",not _loaded_hashes.values().has("") and hashes==_loaded_hashes,{"loaded":_loaded_hashes,"finished":hashes})
	var expected_total:=8+5*_expected_stations+(4 if _native else 0)
	_check("strict_complete_data_driven_check_denominator",checks.size()==expected_total-1,{"checks_before_guard":checks.size(),"expected_total_including_guard":expected_total,"station_count":_expected_stations,"native":_native})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Could not write mobility distribution report");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP26_MOBILITY_DISTRIBUTION","result":"PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"expected_total":expected_total,"checks":checks,"observer_starts":observer_starts,"station_trials":station_trials,"captures":captures,"source_hashes":hashes,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"startup_elapsed_ms":startup_elapsed_ms,"startup_timing_scope":"Single whole-scene test startup plus eight fixed ticks and input hashing on this Mac; not repeated load benchmark, frame-rate or another-Mac performance acceptance.","elapsed_ms":Time.get_ticks_msec()-started,"scope":"Entire ordinary production scene and all authored bicycle/scooter docks. Only positively supported player observer fixtures are placed; physical KEY_E press/release dispatch and synthetic maintained W/Space actions drive actual retained bodies and original collisions/supports. No vehicle/actor/source transform fixtures, no direct mount calls. Native saved images require separate image review; engine events are not human OS-key, subjective comfort or performance acceptance."}),"  "));file.close();print("MOBILITY_DISTRIBUTION_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)

extends SceneTree
## Integration ownership, not a repeat of detailed shop/driving/flight suites.
## Every place change uses a production host shortcut. Interior approach and
## flight use labelled held inputs; every E uses physical keyboard events.
class HeldInput extends Node:
	var harness: SceneTree
	func _physics_process(_delta: float) -> void:harness._refresh_inputs()
var scene: Node3D
var shop: Node3D
var car: Node3D
var helicopter: Node3D
var checks: Array[Dictionary]=[]
var held: Dictionary={}
var report_path:="/tmp/sim2seoul-city-life-integration.json"
var started:=0
var finished:=false
var allow_convenience_fallback:=false
var clothing_kind:="clothing"
var _hashes_loaded: Dictionary={}
var _source_ids: Dictionary={}
var _actor_ids: Dictionary={}
var _capsule_id:=0
var _layer:=0
var _mask:=0
var _terrain_id:=""
var _fixtures: Array[StaticBody3D]=[]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg=="--development-convenience-fallback":allow_convenience_fallback=true
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	var fixture:=HeldInput.new();fixture.name="TestOnlyIntegratedHeldInput";fixture.harness=self;fixture.process_physics_priority=-200;fixture.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(fixture)
	started=Time.get_ticks_msec();create_timer(420.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _refresh_inputs() -> void:
	for action: StringName in held:Input.action_press(action)
func _key(action: StringName,down: bool) -> void:
	if down:held[action]=true
	else:held.erase(action);Input.action_release(action)
func _e(down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_E;event.physical_keycode=KEY_E;event.device=0;event.pressed=down;Input.parse_input_event(event)
func _tap_e() -> void:_e(true);await _ticks(3);_e(false);await _ticks(5)
func _ticks(count: int) -> void:
	for tick: int in range(count):await scene.rig.camera_stepped
func _frames(count: int) -> void:
	for frame: int in range(count):await process_frame
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is RID:return str(value)
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
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("CITY_LIFE_CHECK ",title," ",ok)
func _input_hashes() -> Dictionary:
	var hashes: Dictionary={}
	for path: String in ["res://scripts/shop_visit_service.gd","res://scripts/drivable_car_service.gd","res://scripts/city_helicopter_service.gd","res://assets/authored/shop_service.json","res://assets/authored/car_service.json","res://assets/authored/helicopter_service.json","res://assets/authored/street_businesses.json","res://scripts/explore_walk.gd","res://scripts/interior_visit.gd","res://scripts/city_bike_service.gd","res://scripts/city_scooter_service.gd","res://scripts/city_bus_service.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_camera.gd","res://scripts/exploration_rooftop_access.gd","res://scripts/rooftop_space.gd","res://../tests/game/check_city_life_integration.gd","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json"]:hashes[path]=FileAccess.get_sha256(path)
	for path: String in ["res://scripts/pool_preparation_service.gd","res://assets/authored/pool_preparation.json"]:
		if FileAccess.file_exists(path):hashes[path]=FileAccess.get_sha256(path)
	return hashes
func _current_source_ids() -> Dictionary:
	var out: Dictionary={}
	for key: Variant in scene.city.source_nodes:out[str(key)]=str(scene.city.source_nodes[key].get_instance_id())
	return out
func _current_actor_ids() -> Dictionary:
	var out: Dictionary={};var rows: Array=[];rows.append_array(scene.pedestrians);rows.append_array(scene.street_pedestrians.actors);rows.append_array(scene.neighborhood_population.walkers.actors);rows.append_array(scene.vehicles);rows.append_array(scene.neighborhood_population.traffic.vehicles)
	for row: Variant in rows:
		var body: Node=row if row is Node else row.get("body")
		if is_instance_valid(body):out[str(body.get_path())]=str(body.get_instance_id())
	return out
func _ownership() -> Dictionary:
	var riding: Array[String]=[]
	for service: Node3D in scene._street_services():
		if is_instance_valid(service) and service.riding:riding.append(String(service.get_script().resource_path))
	return {"shop":shop.active,"shop_id":shop.current_shop_id,"shop_ui":shop.ui_open,"ordinary_interior":scene.interior_visit.active,"player_interior":scene.player.interior_active,"riding":riding,"facility_control":scene.player.facility_control,"player_physics":scene.player.is_physics_processing(),"gameplay":scene.input_router.gameplay_enabled,"camera_input":scene.rig.input_enabled,"mouse_mode":Input.mouse_mode,"position":scene.player.global_position,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"capsule":str(scene.player.get_node("CollisionShape").shape.get_instance_id())}
func _outside_control() -> bool:
	return not shop.active and not shop.ui_open and not scene.interior_visit.active and not scene.player.interior_active and not scene._street_transport_riding() and scene.player.is_physics_processing() and not scene.player.facility_control and scene.player.collision_layer==_layer and scene.player.collision_mask==_mask and scene.player.get_node("CollisionShape").shape.get_instance_id()==_capsule_id
func _shortcut(kind: String) -> bool:
	if not scene.menu.visible:scene.toggle_menu()
	if kind=="library":scene._visit_library_entrance()
	else:scene._visit_street_detail(kind)
	if scene.menu.visible:await _frames(5);return false
	await _ticks(9);return true
func _block_at(point: Vector3,basis:=Basis.IDENTITY) -> void:
	# Raised boxes cross the destination capsule, rather than adding a new
	# walkable ground plane. They do not overlap the parked vehicle body.
	var node:=StaticBody3D.new();node.name="IntegrationTestBlockedShortcut";node.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.15,1.5,1.3);shape.shape=box;node.add_child(shape);scene.add_child(node);node.global_transform=Transform3D(basis,point+Vector3.UP*1.62);_fixtures.append(node)
func _clear_fixtures() -> void:
	for node: StaticBody3D in _fixtures:node.queue_free()
	_fixtures.clear()
	if scene.menu.visible:await _frames(6)
	else:await _ticks(4)
func _walk_to_shop_product() -> bool:
	if not shop.active or shop._current.interactions.is_empty():return false
	var target: Vector3=shop._current.interactions[0].point
	# Use the unchanged production camera's right/forward directions. No
	# interior teleport or camera override is needed to reach the clear aisle.
	for tick: int in range(180):
		for action: StringName in [&"move_left",&"move_right",&"move_forward",&"move_backward"]:_key(action,false)
		var delta: Vector3=target-scene.player.global_position;delta.y=0.
		var right: Vector3=scene.rig.camera.global_basis.x;right.y=0.;right=right.normalized()
		var forward: Vector3=-scene.rig.camera.global_basis.z;forward.y=0.;forward=forward.normalized()
		var horizontal: float=delta.dot(right);var depth: float=delta.dot(forward)
		if absf(horizontal)>.22:_key(&"move_right" if horizontal>0. else &"move_left",true)
		if absf(depth)>.22:_key(&"move_forward" if depth>0. else &"move_backward",true)
		await _ticks(1)
		if scene.player.global_position.distance_to(target)<.65:break
	for action: StringName in [&"move_left",&"move_right",&"move_forward",&"move_backward"]:_key(action,false)
	await _ticks(4)
	return not shop._nearest_product().is_empty()
func _pool_support() -> Dictionary:
	var target: Dictionary=scene.exploration_rooftop_access.representative_pool_destination()
	if target.is_empty():return {"passed":false}
	var at: Vector3=scene.player.global_position;var ground: float=scene.terrain_surface.ground_y_world(at)
	var hit:=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.35,at-Vector3.UP*.5,scene.player.collision_mask,[scene.player.get_rid()]))
	var contact: bool=not hit.is_empty() and hit.normal.y>.7 and absf(at.y-hit.position.y)<.20
	return {"passed":at.distance_to(target.pool_entry)<.3 and at.y-ground>8. and contact,"position":at,"expected_pool_entry":target.pool_entry,"terrain_y":ground,"height_above_terrain_m":at.y-ground,"positive_native_support":contact,"ownership":_ownership()}
func _finish() -> void:
	if finished:return
	finished=true
	if is_instance_valid(scene) and scene.runtime_ok:
		_check("same_original_world_nodes_actor_IDs_terrain_and_capsule",_current_source_ids()==_source_ids and _current_actor_ids()==_actor_ids and str(scene.terrain_surface.support.get_rid())==_terrain_id and scene.player.get_node("CollisionShape").shape.get_instance_id()==_capsule_id,{"source_node_count":_source_ids.size(),"original_actor_count":_actor_ids.size(),"terrain_rid":_terrain_id})
	var hashes:=_input_hashes();_check("all_runtime_inputs_and_original_source_hashes_stable",not hashes.values().has("") and hashes==_hashes_loaded,{"loaded":_hashes_loaded,"finished":hashes})
	var passed:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:push_error("Cannot save integrated city life evidence");quit(2);return
	file.store_string(JSON.stringify(_json({"task":"city_life_integration","result":("DEVELOPMENT_PASS" if clothing_kind!="clothing" else "PASS") if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"source_hashes":hashes,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"recorded_at":Time.get_datetime_string_from_system(),"elapsed_ms":Time.get_ticks_msec()-started,"final_ownership":_ownership() if is_instance_valid(shop) else {},"development_convenience_substitution":clothing_kind!="clothing","scope":"Production host shortcuts only for every location change, physical KEY_E, test-only held walking/flight inputs and named raised shortcut blockers. Covers ownership/capsule/camera/UI restoration and original IDs/source hashes, not detailed product transactions, driving/flight completeness, OS keyboard control, rendered appearance or performance."}),"  "));file.close();print("CITY_LIFE_RESULT ",passed,"/",checks.size());quit(0 if passed==checks.size() else 1)
func _run() -> void:
	_hashes_loaded=_input_hashes();scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/city-life-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(10)
	shop=scene.get("shop_visit_service");car=scene.get("drivable_car_service");helicopter=scene.get("city_helicopter_service")
	_check("production_host_auto_sets_up_all_three_new_services",scene.runtime_ok and is_instance_valid(shop) and shop.loaded and is_instance_valid(car) and car.loaded and is_instance_valid(helicopter) and helicopter.loaded,{"runtime_error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(shop) or not shop.loaded or not is_instance_valid(car) or not car.loaded or not is_instance_valid(helicopter) or not helicopter.loaded:_finish();return
	_source_ids=_current_source_ids();_actor_ids=_current_actor_ids();_capsule_id=scene.player.get_node("CollisionShape").shape.get_instance_id();_layer=scene.player.collision_layer;_mask=scene.player.collision_mask;_terrain_id=str(scene.terrain_surface.support.get_rid());scene.set_speed_profile("brisk")
	var has_clothing: bool=shop.shops.any(func(row: Dictionary)->bool:return row.kind=="clothing")
	if not has_clothing and allow_convenience_fallback:clothing_kind="shop"
	_check("final_flow_requires_actual_clothing_shop",has_clothing or allow_convenience_fallback,{"has_clothing":has_clothing,"development_fallback":clothing_kind!="clothing"})
	if not has_clothing and not allow_convenience_fallback:_finish();return
	_check("host_shop_shortcut_reaches_supported_front_door",await _shortcut("shop") and _outside_control(),_ownership());await _tap_e()
	_check("physical_E_enters_shop_with_exclusive_detached_interior",shop.active and scene.player.interior_active and not scene.interior_visit.active and not scene._street_transport_riding(),_ownership())
	if not shop.active:_finish();return
	_check("walk_to_product_uses_native_movement",await _walk_to_shop_product());await _tap_e()
	_check("physical_E_opens_shop_picker_owning_mouse_and_movement",shop.ui_open and scene.player.facility_control and not scene.input_router.gameplay_enabled and not scene.rig.input_enabled,_ownership())
	scene.toggle_menu();await _frames(5);scene.toggle_menu();await _ticks(4)
	_check("closing_pause_preserves_open_picker_mouse_ownership",shop.ui_open and not scene.input_router.gameplay_enabled and not scene.rig.input_enabled and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,_ownership());await _tap_e()
	_check("physical_E_closes_picker_without_exiting_shop",shop.active and not shop.ui_open and not scene.player.facility_control and scene.input_router.gameplay_enabled,_ownership())
	var car_body: CharacterBody3D=car.bikes[0].body
	for side: float in [-1.,1.]:_block_at(car_body.to_global(Vector3(side*2.15,0,0)),car_body.global_basis)
	await _ticks(4);var previous: Transform3D=scene.player.global_transform;var previous_shop: String=shop.current_shop_id
	var blocked:=not await _shortcut("car_station")
	_check("blocked_car_shortcut_retains_shop_owner_and_exact_player_pose",blocked and shop.active and shop.current_shop_id==previous_shop and scene.player.global_transform==previous and scene.player.interior_active,_ownership());await _clear_fixtures()
	_check("shop_to_car_shortcut_releases_room_and_capsule",await _shortcut("car_station") and _outside_control(),_ownership());await _tap_e()
	_check("physical_E_boards_car_with_one_transport_owner",car.riding and _ownership().riding.size()==1 and not scene.player.is_physics_processing() and not shop.active,_ownership())
	for offset: Vector3 in [Vector3(2.6,0,-.7),Vector3(-2.6,0,-.7),Vector3(2.8,0,.5),Vector3(-2.8,0,.5)]:_block_at(helicopter.body.to_global(offset))
	await _ticks(3);previous=scene.player.global_transform;blocked=not await _shortcut("helipad")
	_check("blocked_helipad_shortcut_keeps_current_driver_attached",blocked and car.riding and not scene.player.is_physics_processing() and scene.player.facility_control and scene.player.global_transform==previous,_ownership());await _clear_fixtures()
	_check("car_to_clothing_shortcut_restores_driver_before_entry",await _shortcut(clothing_kind) and _outside_control() and not car.riding and car._collision_release_pending.is_empty(),_ownership());await _tap_e()
	_check("physical_E_enters_actual_clothing_shop",shop.active and scene.player.interior_active and (shop._current.kind=="clothing" or clothing_kind!="clothing"),_ownership())
	var pool_ok:=await _shortcut("hotel_pool")
	if not pool_ok:pool_ok=await _shortcut("hotel_pool")
	var pool:=_pool_support();_check("shop_to_hotel_pool_preserves_roof_altitude_and_native_support",pool_ok and pool.passed and not shop.active,pool)
	_check("pool_to_clothing_shortcut_returns_to_supported_exterior",await _shortcut(clothing_kind) and _outside_control(),_ownership());await _tap_e()
	_check("clothing_reentry_before_helicopter_transfer",shop.active,_ownership())
	_check("clothing_to_helipad_shortcut_releases_all_indoor_state",await _shortcut("helipad") and _outside_control(),_ownership());await _tap_e();await _ticks(65)
	_check("physical_E_boards_helicopter_with_exclusive_control",helicopter.riding and _ownership().riding.size()==1 and not shop.active and not scene.player.interior_active,_ownership())
	var before_y: float=helicopter.body.global_position.y;_key(helicopter.ASCEND,true);await _ticks(45);_key(helicopter.ASCEND,false);await _ticks(15)
	_check("integrated_helicopter_physically_takes_off",helicopter.body.global_position.y-before_y>2. and helicopter.riding)
	_check("airborne_library_shortcut_restores_player_and_recovers_aircraft",await _shortcut("library") and _outside_control() and not helicopter.riding,_ownership());await _ticks(25)
	_check("cancelled_aircraft_finishes_clear_pad_recovery",not helicopter.return_pending and helicopter.rotor_fraction<.01 and helicopter._release.is_empty() and helicopter._landed(),helicopter.snapshot());await _tap_e()
	_check("library_E_entry_still_works_after_all_transport_transfers",scene.interior_visit.active and scene.player.interior_active and not shop.active and not scene._street_transport_riding(),_ownership())
	pool_ok=await _shortcut("hotel_pool")
	if not pool_ok:pool_ok=await _shortcut("hotel_pool")
	pool=_pool_support();_check("ordinary_library_to_hotel_pool_preserves_roof_height",pool_ok and pool.passed and not scene.interior_visit.active,pool)
	_check("pool_to_library_returns_to_supported_ground",await _shortcut("library") and _outside_control(),_ownership());await _tap_e()
	_check("library_reentry_before_bicycle_transfer",scene.interior_visit.active,_ownership())
	_check("library_to_bike_shortcut_clears_library_state",await _shortcut("bike_station") and _outside_control(),_ownership());await _tap_e()
	_check("original_bicycle_still_borrows_with_physical_E",scene.city_bike_service.riding and _ownership().riding.size()==1,_ownership())
	_check("bike_to_scooter_shortcut_restores_bicycle_then_player",await _shortcut("scooter_station") and _outside_control() and scene.city_bike_service._collision_release_pending.is_empty(),_ownership());await _tap_e()
	_check("original_scooter_still_borrows_with_physical_E",scene.city_scooter_service.riding and _ownership().riding.size()==1,_ownership())
	_check("scooter_to_shop_shortcut_restores_final_walking_state",await _shortcut("shop") and _outside_control() and scene.city_scooter_service._collision_release_pending.is_empty(),_ownership())
	_finish()

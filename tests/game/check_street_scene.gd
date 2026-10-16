extends "res://../tests/game/check_building_visits.gd"
## Production exploration scene; compact independent geometry, input and view QA.
var started_at := ""
var observations: Dictionary = {}
var _settings_path := ""

func _initialize() -> void:
	started_at=Time.get_datetime_string_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("check_street_scene requires absolute --report");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=60;Engine.max_fps=60
	create_timer(360.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2 or value is Vector2i:return [value.x,value.y]
	if value is Color:return [value.r,value.g,value.b,value.a]
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String,passed: bool,evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("STREET_SCENE_CHECK_FAIL "+title)

func _desc(node: Node) -> Array:
	var result := []
	for child in node.get_children():result.append(child);result.append_array(_desc(child))
	return result

func _menu_edge() -> void:
	for pressed in [true,false]:
		var event := InputEventAction.new();event.action="toggle_menu";event.pressed=pressed;event.device=42;Input.parse_input_event(event)
	await process_frame;await process_frame

func _player_shape() -> Dictionary:
	var shape: CollisionShape3D=scene.player.get_node("CollisionShape")
	return {"node":shape.get_instance_id(),"shape":shape.shape.get_instance_id(),"transform":shape.transform,"height":shape.shape.height,"radius":shape.shape.radius,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask,"disabled":shape.disabled}

func _supported_clear(point: Vector3) -> bool:
	var capsule: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;query.collision_mask=1|32;query.exclude=[scene.player.get_rid()]
	var space: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var support: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.4,1|32,[scene.player.get_rid()]))
	return not support.is_empty() and support.normal.y>.7 and absf(support.position.y-(point.y-.08))<.15

func _route_distance(point: Vector3,routes: Array) -> float:
	var best := INF
	for route: Dictionary in routes:
		var line: Array=route.get("xz",[])
		for index in range(1,line.size()):
			var a: Vector3=scene.city.to_global(Vector3(float(line[index-1][0]),0,float(line[index-1][1])))
			var b: Vector3=scene.city.to_global(Vector3(float(line[index][0]),0,float(line[index][1])))
			best=minf(best,Vector2(point.x,point.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(a.x,a.z),Vector2(b.x,b.z))))
	return best

func _business_geometry() -> void:
	var module: Node3D=scene.street_businesses
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/street_businesses.json"))
	var rows := [];var errors := [];var styles := {};var names := {}
	for store: Dictionary in module.stores:
		var node: Node3D=store.node;var record: Dictionary=store.record
		var boxes := 0;var round_meshes := 0;var texts := [];var colliders := 0;var bound := AABB();var first := true
		for child in _desc(node):
			if child is CollisionObject3D or child is CollisionShape3D:colliders+=1
			if child is MultiMeshInstance3D:boxes+=child.multimesh.instance_count
			elif child is MeshInstance3D:round_meshes+=1
			if child is Label3D:texts.append(child.text);names[child.text]=true
			if child is GeometryInstance3D:
				var bounds: AABB=node.global_transform.affine_inverse()*(child.global_transform*child.get_aabb())
				bound=bounds if first else bound.merge(bounds);first=false
		styles[record.style]=true
		var point: Vector3=scene.city.to_global(Vector3(record.approach_xz[0],.08,record.approach_xz[1]))
		var safe := _supported_clear(point)
		var footprint_edge: Array=record.source_edge_xz
		var edge_a := Vector2(float(footprint_edge[0][0]),float(footprint_edge[0][1]));var edge_b := Vector2(float(footprint_edge[1][0]),float(footprint_edge[1][1]))
		var center := Vector2(float(record.facade_center_xz[0]),float(record.facade_center_xz[1]))
		var on_edge := center.distance_to(Geometry2D.get_closest_point_to_segment(center,edge_a,edge_b))<.001
		if not safe or not on_edge or colliders!=0 or boxes<20 or texts.size()<3:errors.append(record.id)
		rows.append({"id":record.id,"style":record.style,"source_feature_id":record.source_feature_id,"authored_facade_bounds":bound,"box_instances":boxes,"round_meshes":round_meshes,"actual_texts":texts,"clear_approach":safe,"center_on_source_edge":on_edge,"new_colliders":colliders,"offers_new_entry":record.offers_new_entry})
	observations["businesses"]=rows
	_check("shops.four_distinct_source_fitted_models_and_actual_clear_approaches",rows.size()==4 and styles.size()==4 and errors.is_empty(),{"errors":errors,"styles":styles.keys()})
	_check("shops.actual_signs_distinguish_Jinju_GS25_emart24_CU",names.has_all(["진주회관","GS25","emart24","CU"]))
	var jinju: Dictionary=raw.records[0]
	_check("shops.Jinju_official_address_and_OSM_disagreement_remain_explicit",String(jinju.official_address).contains("세종대로11길 26") and jinju.source_poi=="n/12062206099" and jinju.has("position_note") and String(jinju.position_note).contains("10.84") and not jinju.offers_new_entry)

func _street_geometry() -> void:
	var life: Node3D=scene.street_life;var state: Dictionary=life.snapshot()
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/street_life.json"))
	var public: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/public_walk.json"))
	var traffic: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/traffic.json"))
	var actual_counts := {};var original_ids := {};var errors := [];var checks_count := 0
	for body in scene.city.bodies.values():original_ids[body.get_instance_id()]=true
	for node in _desc(life):
		if node is Node3D and node.has_meta("street_life_kind"):
			var kind := String(node.get_meta("street_life_kind"));actual_counts[kind]=int(actual_counts.get(kind,0))+1
		if node is CollisionObject3D and original_ids.has(node.get_instance_id()):errors.append("owned_source_body")
	for anchor: Dictionary in life.anchors:
		var size: Vector3=anchor.size_m;var point: Vector3=anchor.frame.origin;var radius := Vector2(size.x,size.z).length()*.5
		var walk := _route_distance(point,public.routes);var drive := _route_distance(point,traffic.routes);var door := INF
		for spec: Dictionary in visit.catalog:
			for entry: Dictionary in spec.entry_candidates:
				door=minf(door,Vector2(point.x-entry.entrance.x,point.z-entry.entrance.z).length())
		var protected: bool=walk>=radius+float(raw.protection.walking_corridor_width_m)*.5+float(raw.protection.extra_margin_m)-.001 and drive>=radius+float(raw.protection.moving_vehicle_radius_margin_m)-.001 and door>=radius+float(raw.protection.door_clearance_m)-.001
		checks_count+=1
		if not protected:errors.append(String(anchor.id))
	var actual_lights := 0;var actual_solids := 0
	for node in _desc(life):
		if node is OmniLight3D:actual_lights+=1
		if node is StaticBody3D:actual_solids+=1
	observations["street_inventory"]={"actual_kind_counts":actual_counts,"actual_lights":actual_lights,"actual_owned_solids":actual_solids,"guarded_anchors":checks_count,"errors":errors,"skipped":state.skipped}
	_check("street.actual_parked_cars_motorcycles_people_lamps_counts",int(actual_counts.get("parked_cars",0))==3 and int(actual_counts.get("motorcycles",0))==3 and int(actual_counts.get("busker",0))==1 and int(actual_counts.get("audience",0))==3 and actual_lights==10 and actual_solids==16,{"counts":actual_counts,"lights":actual_lights,"solids":actual_solids})
	_check("street.actual_six_birds_are_noncolliding_models",life.birds.size()==6 and state.bird_count==6)
	_check("street.independent_route_traffic_and_door_clearance_checks",checks_count>=20 and errors.is_empty(),{"anchors":checks_count,"errors":errors})
	_check("street.authored_positions_do_not_claim_real_parking_or_event",raw.status=="authored_game_street_details_not_surveyed_parking_or_event_positions" and not state.audio)

func _animation_values() -> Dictionary:
	var life: Node3D=scene.street_life;var positions := [];var rotations := [];var people := []
	for row: Dictionary in life.birds:
		positions.append(row.actor.global_position);rotations.append([row.head.rotation,row.wings[0].rotation,row.wings[1].rotation])
	for row: Dictionary in life.performers:people.append([row.arms[0].transform,row.arms[1].transform,row.forearms[0].transform,row.forearms[1].transform])
	return {"elapsed":life.elapsed,"bird_positions":positions,"bird_rotations":rotations,"people_joints":people}

func _animation_probe() -> void:
	var life: Node3D=scene.street_life;var initial := _animation_values();var animated_birds := {};var animated_people := {};var maximum_radius := 0.;var maximum_height := 0.;var minimum_height := 0.
	for sample in range(85):
		await _ticks(6)
		var actual := _animation_values()
		for index in range(life.birds.size()):
			var row: Dictionary=life.birds[index];var point: Vector3=row.actor.global_position;var offset: Vector3=point-row.anchor
			maximum_radius=maxf(maximum_radius,Vector2(offset.x,offset.z).length());maximum_height=maxf(maximum_height,offset.y);minimum_height=minf(minimum_height,offset.y)
			if actual.bird_positions[index]!=initial.bird_positions[index] or actual.bird_rotations[index]!=initial.bird_rotations[index]:animated_birds[index]=true
		for index in range(life.performers.size()):
			if actual.people_joints[index]!=initial.people_joints[index]:animated_people[index]=true
	var evidence := {"samples":85,"seconds":8.5,"maximum_horizontal_excursion_m":maximum_radius,"maximum_vertical_excursion_m":maximum_height,"minimum_vertical_excursion_m":minimum_height,"actual_animated_birds":animated_birds.size(),"actual_animated_people":animated_people.size()}
	observations["animation"]=evidence
	_check("street.actual_bird_and_guitar_audience_joints_animate_boundedly",animated_birds.size()==6 and animated_people.size()==4 and maximum_radius<=.805 and maximum_height<=1.205 and minimum_height>=-.005,evidence)
	var before := _animation_values();var player_before: Vector3=scene.player.global_position
	await _menu_edge()
	var opened: bool=scene.menu.visible and paused
	before=_animation_values()
	for index in range(18):await process_frame
	_check("street.production_menu_pauses_actual_people_birds_and_player",opened and _animation_values()==before and scene.player.global_position==player_before)
	if scene.menu.visible:await _menu_edge()
	await _ticks(4)
	_check("street.menu_resume_continues_same_animation",life.elapsed>float(before.elapsed))

func _set_time_from_menu(id: String) -> void:
	if not scene.menu.visible:await _menu_edge()
	var index := ["day","evening","night"].find(id)
	var open: bool=scene.menu.visible and paused
	scene.time_option.select(index);scene.time_option.item_selected.emit(index)
	await process_frame;await process_frame
	var stored: Variant=JSON.parse_string(FileAccess.get_file_as_string(_settings_path+".time.json"))
	var speed: Variant=JSON.parse_string(FileAccess.get_file_as_string(_settings_path))
	_check("time."+id+".real_menu_signal_updates_atmosphere_lamps_and_separate_preferences",open and scene.time_id==id and scene.photo_atmosphere.time_profile==id and scene.street_life.time_profile==id and stored is Dictionary and stored.size()==2 and stored.time_id==id and speed is Dictionary and speed.size()==3 and speed.has_all(["schema_version","speed_id","free_roam"]))
	if scene.menu.visible:await _menu_edge()
	await _ticks(30)
	var visible := 0;var emitted := 0;var shadows := 0;var maximum_energy := 0.
	for row: Dictionary in scene.street_life.lamps:
		if row.light.visible:visible+=1
		if row.bulb.material_override.emission_enabled:emitted+=1
		if row.light.shadow_enabled:shadows+=1
		maximum_energy=maxf(maximum_energy,row.light.light_energy)
	var sunlight: float=scene.photo_atmosphere.sun.light_energy
	_check("time."+id+".actual_sun_and_distance_limited_warm_lights",shadows==0 and (visible==0 and emitted==0 and sunlight>1. if id=="day" else visible>0 and visible<=8 and emitted==10 and sunlight<1.),{"visible_lights":visible,"emissive_lamp_meshes":emitted,"shadowed_lights":shadows,"maximum_light_energy":maximum_energy,"sun_energy":sunlight})
	observations["lighting_"+id]={"visible_lights":visible,"emissive_lamps":emitted,"sun_energy":sunlight,"sky_top":scene.photo_atmosphere.sky_material.sky_top_color,"ambient_energy":scene.photo_atmosphere.environment.ambient_light_energy}

func _view(title: String,toward: Vector3,distance := 4.5) -> void:
	var direction: Vector3=toward-scene.player.global_position;direction.y=0.
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-10.);scene.rig.requested_distance=distance;scene.rig.snap_to_target_pose()
	await _ticks(5)
	_check("view."+title+".normal_camera_is_clear",scene.get_viewport().get_camera_3d()==scene.rig.camera and _camera_clear(),{"distance_m":scene.rig.camera.global_position.distance_to(scene.rig.global_position),"player":scene.player.global_position})
	if DisplayServer.get_name()=="headless":captures.append({"name":title,"captured":false,"reason":"headless"});return
	await process_frame
	RenderingServer.force_draw(false,0.)
	await RenderingServer.frame_post_draw
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path := report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row := {"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"time_id":scene.time_id,"normal_avatar_visible":scene.player.get_node("Visual").is_visible_in_tree()}
	captures.append(row);_check("capture."+title,saved)

func _store_views() -> void:
	for store: Dictionary in scene.street_businesses.stores:
		var node: Node3D=store.node;var record: Dictionary=store.record
		var point: Vector3=scene.city.to_global(Vector3(record.approach_xz[0],.08,record.approach_xz[1]))
		if await _pose("shop_"+String(record.id),point):await _view("shop_"+String(record.id),node.global_position+Vector3.UP*1.4,5.)

func _menu_layout_and_shortcuts() -> void:
	var saved_size: Vector2i=root.size;var saved_scale: Vector2i=root.content_scale_size;var saved_mode: int=root.content_scale_mode
	root.size=Vector2i(640,480);root.content_scale_size=Vector2i(640,480);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	await _ticks(5)
	if not scene.menu.visible:await _menu_edge()
	for index in range(4):await process_frame
	var view: Rect2=scene.get_viewport().get_visible_rect();var menu_rect: Rect2=scene.menu.get_global_rect()
	var scroll: ScrollContainer=scene.exploration_menu_scroll
	_check("menu.640x480_bounds_and_vertical_scroll_keep_controls_reachable",view.encloses(menu_rect) and scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+.5,{"viewport":view,"menu":menu_rect,"scroll":scroll.get_global_rect()})
	for title in ["진주회관 앞 거리로 이동","돌담길 버스킹으로 이동","미술관 언덕 입구로 이동"]:
		if not scene.menu.visible:await _menu_edge()
		var button: Button
		for node in _desc(scene.menu):
			if node is Button and node.text==title:button=node;break
		if button==null:_check("menu.shortcut."+title,false,{"reason":"button_missing"});continue
		scroll.ensure_control_visible(button)
		for index in range(4):await process_frame
		var button_rect: Rect2=button.get_global_rect();var clip: Rect2=scroll.get_global_rect()
		var reachable := clip.encloses(button_rect)
		button.pressed.emit();await _ticks(18)
		_check("menu.shortcut."+title+".real_button_closes_menu_and_places_supported_player",reachable and not scene.menu.visible and not paused and scene.player.is_on_floor() and not scene.player.input_latched and _supported_clear(scene.player.global_position+Vector3.UP*.03),{"button_rect":button_rect,"clip":clip,"player":scene.player.global_position,"notice":scene.exploration_notice.text})
	if scene.menu.visible:await _menu_edge()
	root.size=saved_size;root.content_scale_size=saved_scale;root.content_scale_mode=saved_mode
	await _ticks(5)

func _busker_viewpoint() -> Vector3:
	for row: Dictionary in scene.street_life.performers:
		if row.kind!="busker":continue
		var actor: Node3D=row.actor
		for distance in [3.0,4.0,5.0]:
			for side in [1.5,-1.5,0.]:
				var point: Vector3=actor.global_position-actor.global_basis.z*distance+actor.global_basis.x*side;point.y=.08
				if _supported_clear(point):return point
	return Vector3.INF

func _hill_walk(title: String,stations: Array) -> bool:
	var before: int=scene.player.recoveries;var minimum := INF;var maximum := -INF;var ticks := 0;var grounded := 0;var completed := true
	for raw in stations:
		var target: Vector3=scene.museum_approach.point_at_station(float(raw))+Vector3.UP*.08
		var reached := false
		for index in range(1500):
			var offset: Vector3=target-scene.player.global_position;var flat := Vector3(offset.x,0,offset.z)
			if flat.length()<.19 and absf(offset.y)<.35:reached=true;break
			_world_keys(flat.normalized());await scene.player.physics_stepped
			ticks+=1;minimum=minf(minimum,scene.player.global_position.y);maximum=maxf(maximum,scene.player.global_position.y)
			if scene.player.is_on_floor():grounded+=1
			if scene.player.recoveries!=before:break
		if not reached:completed=false;break
	_movement();await _ticks(5)
	var row := {"name":title,"stations":stations,"completed":completed,"actual_physics_ticks":ticks,"grounded_samples":grounded,"minimum_y_m":minimum,"maximum_y_m":maximum,"recovery_delta":scene.player.recoveries-before,"ending_point":scene.player.global_position,"method":"Real controller movement actions; no midwalk position assignment."}
	walks.append(row)
	_check("hill."+title+".real_controller_reaches_source_XZ_profile",completed and ticks>30 and grounded>ticks*.9 and scene.player.recoveries==before and scene.player.is_on_floor(),row)
	return completed

func _hill_checks() -> void:
	var hill: Node3D=scene.museum_approach;var state: Dictionary=hill.snapshot();var failures := [];var supported := 0
	for station in range(0,91):
		var point: Vector3=hill.point_at_station(float(station))
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.6,point-Vector3.UP*.6,1|32,[scene.player.get_rid()]))
		if hit.is_empty() or absf(hit.position.y-point.y)>.035:failures.append(station)
		else:supported+=1
	observations["hill"]={"source":state.source,"profile":state.profile,"anchors":state.anchors,"supported_stations":supported,"support_failures":failures,"collision_body_count":state.collision_body_count,"closed_shapes":state.closed_convex_shape_count,"original_museum_entrance_y_m":state.original_museum_entrance_y_m}
	_check("hill.actual_support_matches_91_profile_stations",supported==91 and failures.is_empty(),{"failures":failures})
	_check("hill.source_XZ_and_three_metre_authored_height_remain_distinct",state.source.feature_id=="osm:way:183272668:highway_line" and state.designed_height_m==3. and not state.physical_terrain_verified and not state.source_buildings_modified and state.original_museum_entrance_y_m==.08)
	if not await _pose("hill_lower",hill.point_at_station(0.)+Vector3.UP*.08):return
	await _view("hill_lower",hill.point_at_station(15.)+Vector3.UP,4.5)
	if await _hill_walk("uphill",[5.,10.,15.,20.,25.,30.,35.,42.]):await _view("hill_top",hill.point_at_station(20.)+Vector3.UP,4.5)
	await _hill_walk("downhill_to_flat",[45.,50.,55.,60.,65.,70.,75.,80.,85.,90.])

func _run() -> void:
	for path in ["res://scripts/explore_walk.gd","res://scripts/photo_atmosphere.gd","res://scripts/street_businesses.gd","res://scripts/street_life.gd","res://scripts/museum_approach.gd","res://scripts/player/free_roam_player.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/exploration_camera.gd","res://assets/authored/street_businesses.json","res://assets/authored/street_life.json","res://assets/authored/museum_approach.json","res://../tests/game/check_street_scene.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	_settings_path="/private/tmp/sim2seoul-street-scene-"+str(OS.get_process_id())+".json"
	var initial:=FileAccess.open(_settings_path,FileAccess.WRITE);initial.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));initial.close()
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json"
	root.add_child(scene);await _ticks(10)
	_check("startup.actual_production_city_and_all_three_modules_loaded",scene.runtime_ok and is_instance_valid(scene.street_businesses) and scene.street_businesses.loaded and is_instance_valid(scene.street_life) and scene.street_life.loaded and is_instance_valid(scene.museum_approach) and scene.museum_approach.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok:_finish();return
	visit=scene.interior_visit
	if scene.menu.visible:await _menu_edge()
	await _ticks(4);original_inventory=_inventory()
	var physical_shape := _player_shape()
	_business_geometry();_street_geometry()
	await _menu_layout_and_shortcuts()
	await _store_views()
	var busker: Vector3=Vector3.ZERO
	var busker_look_offset := Vector3.ZERO
	for row: Dictionary in scene.street_life.performers:
		if row.kind=="busker":busker=row.actor.global_position;busker_look_offset=row.actor.global_basis.x*1.0
	var point := _busker_viewpoint()
	_check("street.busker_has_an_actual_safe_observer_position",point.is_finite())
	if point.is_finite():
		await _pose("busker_observer",point)
		await _animation_probe()
		for id in ["day","evening","night"]:
			await _set_time_from_menu(id);await _view("busker_"+id,busker+Vector3.UP+busker_look_offset,4.5)
	var previous_id: String=scene.time_id
	_check("time.invalid_profile_is_rejected_without_state_change",not scene.set_time_profile("invalid") and scene.time_id==previous_id)
	scene.set_time_profile("day");await _ticks(5)
	await _hill_checks()
	if await _enter(LIBRARY_ID,"regression_library"):
		await _leave("regression_library")
	_check("regression.source_bodies_and_player_capsule_unchanged",_inventory()==original_inventory and _player_shape()==physical_shape and not scene.player.interior_active,{"source_body_count":original_inventory.size()})
	_check("regression.user_preferences_are_isolated_from_this_probe",scene.exploration_settings_path.begins_with("/private/tmp/sim2seoul-street-scene-") and scene.exploration_settings_path!= "user://sim2seoul_exploration.json")
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed := 0
	for row: Dictionary in checks:
		if not row.passed:failed+=1
	var evidence := {"task":"street_scene","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"scenario_starts":placements,"walks":walks,"captures":captures,"source_collision_count":original_inventory.size(),"scope":"Actual production exploration scene, independent physical approaches and route guards, actual mesh/text/joint/light state, whole bird cycle, real menu/time-preference signals, production controller hill ascent/descent and physical E library regression. Explicit scenario start positions only; no midwalk teleport. Native PNGs use the normal collision-tested third-person camera and frame_post_draw when GPU is available; headless performs no rendered-image acceptance. Store tenancy/frontages and 3m hill are authored/source-qualified; no complete surveyed terrain, human OS input, moving motorcycle, audio, all shops enterable or performance acceptance."}
	var output:=FileAccess.open(report_path,FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify(_json(evidence),"\t")+"\n");output.close()
	else:failed+=1;push_error("Could not save street scene report")
	print("STREET_SCENE_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

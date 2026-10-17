extends "res://../tests/game/check_facility_interactions.gd"
## Admin guest-room access uses real production E, moving door collision and
## unchanged player movement. Role placement/props are inspected independently.
var access: Node3D
var role_observations: Array=[]
var door_observations: Array=[]
var role_camera_observations: Array=[]

func _role_stance_clear(point: Vector3) -> bool:
	if not scene.player._inside(point):return false
	var capsule: CollisionShape3D=scene.player.get_node("CollisionShape")
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;query.collision_mask=scene.player.collision_mask;query.exclude=[scene.player.get_rid()];query.margin=.002
	var space: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.35,1,[scene.player.get_rid()]))
	return not hit.is_empty() and hit.normal.y>.95 and absf(float(hit.position.y)-(point.y-.08))<.03

func _project_mesh(mesh: MeshInstance3D) -> Rect2:
	var camera: Camera3D=scene.rig.camera;var bounds: AABB=mesh.get_aabb();var rect: Rect2=Rect2();var started: bool=false
	for index: int in range(8):
		var point: Vector3=mesh.to_global(bounds.position+Vector3(bounds.size.x if index&1 else 0.0,bounds.size.y if index&2 else 0.0,bounds.size.z if index&4 else 0.0))
		if camera.is_position_behind(point):continue
		var pixel: Vector2=camera.unproject_position(point)
		rect=Rect2(pixel,Vector2.ZERO) if not started else rect.expand(pixel);started=true
	return rect

func _role_frame(actor: Node3D,prop_name: String) -> Dictionary:
	var head: MeshInstance3D=actor.get_node("RoleHead");var prop: MeshInstance3D=actor.find_child(prop_name,true,false);var camera: Camera3D=scene.rig.camera
	var view: Rect2=Rect2(Vector2.ZERO,scene.get_viewport().get_visible_rect().size);var head_rect: Rect2=_project_mesh(head);var head_pixel: Vector2=camera.unproject_position(head.global_position)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position,head.global_position,1,[scene.player.get_rid()]))
	var avatar_rect: Rect2=Rect2();var avatar_started: bool=false
	for node in _descendants(scene.player.get_node("Visual")):
		if not node is MeshInstance3D or not node.is_visible_in_tree():continue
		var rect: Rect2=_project_mesh(node)
		if not rect.has_area():continue
		avatar_rect=rect if not avatar_started else avatar_rect.merge(rect);avatar_started=true
	var panels: Array=[]
	for panel: Control in [visit.indoor_panel,visit.prompt,scene.get_node("Interface/FacilityActivityStatus"),scene.attribution_label]:
		if panel.is_visible_in_tree():panels.append(panel.get_global_rect())
	var head_ui_clear: bool=true;var prop_ui_clear: bool=true;var prop_rect: Rect2=_project_mesh(prop) if is_instance_valid(prop) else Rect2()
	for panel: Rect2 in panels:
		if panel.intersects(head_rect):head_ui_clear=false
		if panel.intersects(prop_rect):prop_ui_clear=false
	var parts_in_frame: int=0
	for node in _descendants(actor):
		if node is MeshInstance3D and node.is_visible_in_tree() and not camera.is_position_behind(node.global_position) and view.has_point(camera.unproject_position(node.global_position)):parts_in_frame+=1
	var distance: float=scene.rig.camera.global_position.distance_to(scene.rig.global_position)
	var okay: bool=actor.is_visible_in_tree() and not camera.is_position_behind(head.global_position) and view.encloses(head_rect) and head_rect.size.y>=14.0 and hit.is_empty() and head_ui_clear and not avatar_rect.intersects(head_rect) and is_instance_valid(prop) and prop.is_visible_in_tree() and view.encloses(prop_rect) and prop_ui_clear and not avatar_rect.intersects(prop_rect) and parts_in_frame>=8 and _camera_clear() and distance>=1.8 and scene.player.get_node("Visual").is_visible_in_tree()
	return {"accepted":okay,"role":actor.get_meta("interior_role",""),"head_world":head.global_position,"head_pixel":head_pixel,"head_projected_rect":head_rect,"head_static_ray_clear":hit.is_empty(),"head_ray_obstacle":String(hit.collider.name) if not hit.is_empty() else "","head_clear_of_UI":head_ui_clear,"prop_name":prop_name,"prop_projected_rect":prop_rect,"prop_clear_of_UI":prop_ui_clear,"avatar_projected_rect":avatar_rect,"actual_role_mesh_centres_in_frame":parts_in_frame,"normal_camera_distance_m":distance,"camera_clear":_camera_clear(),"original_avatar_visible":scene.player.get_node("Visual").is_visible_in_tree(),"camera":camera.global_transform,"viewport":view,"HUD_rectangles":panels}

func _capture_role(title: String,role: String,prop_name: String) -> void:
	var actor: Node3D
	for person: Node3D in visit.room.people:
		if String(person.get_meta("interior_role",""))==role:actor=person;break
	_check("capture_role."+title+".actual_role_model_found",is_instance_valid(actor),{"role":role})
	if not is_instance_valid(actor):return
	var original_actor: Vector3=actor.global_position;var head: MeshInstance3D=actor.get_node("RoleHead");var attempts: Array=[];var chosen: Dictionary={}
	for offset: Vector3 in [Vector3(-1.8,0,-1.5),Vector3(-1.8,0,1.5),Vector3(1.8,0,-1.5),Vector3(1.8,0,1.5),Vector3(0,0,-2.2),Vector3(0,0,2.2)]:
		var stance: Vector3=actor.global_position+offset;stance.y=visit.room.floor_spawn(visit.room.active_floor).y
		if not _role_stance_clear(stance):continue
		if not await _pose("role_camera_"+title+"_clear_stance_"+str(attempts.size()),stance):continue
		for turn: float in [-18.0,18.0,0.0]:
			var pivot: Vector3=scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m;var direction: Vector3=head.global_position-pivot;var flat: float=Vector2(direction.x,direction.z).length()
			scene.rig.yaw=atan2(-direction.x,-direction.z)+deg_to_rad(turn);scene.rig.pitch=atan2(direction.y,flat);scene.rig.requested_distance=2.6;scene.rig.snap_to_target_pose();await _ticks(5)
			var evidence: Dictionary=_role_frame(actor,prop_name);evidence["stance"]=scene.player.global_position;evidence["yaw_offset_degrees"]=turn;attempts.append(evidence)
			if evidence.accepted:chosen=evidence;break
		if not chosen.is_empty():break
	var result: Dictionary={"name":title,"role":role,"accepted":not chosen.is_empty(),"chosen":chosen,"attempts":attempts,"NPC_position_before":original_actor,"NPC_position_after":actor.global_position,"NPC_position_unchanged":actor.global_position==original_actor,"method":"Labelled grounded player stance fixtures and ordinary rig yaw/pitch/2.6m zoom; no NPC move, avatar transform edit/hide, camera-node override or HUD hiding."}
	role_camera_observations.append(result)
	_check("capture_role."+title+".actual_head_and_role_prop_are_in_frame_clear_of_static_avatar_and_HUD",not chosen.is_empty() and actor.global_position==original_actor,result)
	if chosen.is_empty():return
	if DisplayServer.get_name()!="headless":
		var drawn: bool=await _draw_activity_frame(title)
		_check("capture_role."+title+".actual_forced_render_frame_observed",drawn,capture_progress.duplicate())
		if not drawn:return
	await _capture(title)

func _door() -> Dictionary:
	for row: Dictionary in visit.room.guest_doors:
		if int(row.level)==2:return row
	return {}

func _door_ray(door: Dictionary) -> Dictionary:
	var from: Vector3=visit.room.to_global(door.outside_point)+Vector3.UP*.9
	var to: Vector3=visit.room.to_global(door.inside_point)+Vector3.UP*.9
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[scene.player.get_rid()]))

func _walk_point(point: Vector3,title: String,expect_reached := true) -> bool:
	var start: Vector3=scene.player.global_position;var recoveries: int=scene.player.recoveries;var reached:=false;var steps:=0
	for tick in range(180):
		var difference: Vector3=point-scene.player.global_position;difference.y=0
		if difference.length()<.07:reached=true;break
		_world_keys(difference.normalized()*.75);await scene.player.physics_stepped;steps+=1
		if scene.player.recoveries!=recoveries:break
	_movement();await _ticks(5)
	var evidence:={"start":start,"end":scene.player.global_position,"target":point,"reached":reached,"controller_steps":steps,"recoveries":scene.player.recoveries-recoveries,"position_writes_during_walk":0}
	_check(title,reached==expect_reached and scene.player.recoveries==recoveries,evidence);walks.append(evidence)
	return reached

func _door_trial() -> void:
	var door := _door()
	_check("door.actual_registered_hotel_guest_room",not door.is_empty(),{"count":visit.room.guest_doors.size()})
	if door.is_empty() or not await _ride_to(2,"guest_rooms"):return
	var outside: Vector3=visit.room.to_global(door.outside_point);var inside: Vector3=visit.room.to_global(door.inside_point);var threshold: Vector3=visit.room.to_global(door.door_point)
	if not await _pose("labelled_guest_door_outside_start",outside):return
	access.set_admin_access(false);await _ticks(3)
	_e(true);_e(false);await _ticks(6)
	var locked: Dictionary=access.snapshot();var ray:=_door_ray(door)
	_check("door.admin_OFF_rejects_E_and_retains_actual_closed_leaf",int(locked.locked_rejections)>0 and float(door.fraction)==0.0 and not ray.is_empty() and ray.collider==door.body and door.body.collision_layer==1,{"state":locked,"ray_hit_door":not ray.is_empty() and ray.collider==door.body})
	await _walk_point(inside,"door.locked_leaf_physically_blocks_actual_controller",false)
	await _pose("guest_door_clear_approach",outside)
	access.set_admin_access(true);await _ticks(3);_e(true);_e(false);await _ticks(50)
	var actual_leaf: MeshInstance3D=door.body.get_node("GuestDoorLeaf")
	_check("door.admin_master_key_moves_real_leaf_and_keeps_collider_enabled",float(door.fraction)>.99 and not bool(door.locked) and door.body.position.distance_to(door.closed_position)>1.10 and actual_leaf.global_position.is_equal_approx(door.body.global_position) and door.body.collision_layer==1 and _door_ray(door).is_empty(),{"body_transform":door.body.global_transform,"leaf_transform":actual_leaf.global_transform,"state":access.snapshot()})
	scene.rig.yaw=-float(door.side)*PI*.5;scene.rig.pitch=deg_to_rad(-10);scene.rig.requested_distance=3.;scene.rig.snap_to_target_pose();await _ticks(4);await _capture("admin_open_hotel_guest_room")
	if not await _walk_point(inside,"door.opened_room_is_entered_with_actual_controller"):return
	await _walk_point(threshold,"door.walks_back_to_live_doorway_for_pinch_test")
	var blocked_before: int=access.blocked_closures;var body_before: Transform3D=door.body.global_transform;var player_before: Vector3=scene.player.global_position
	_e(true);_e(false);await _ticks(16)
	_check("door.capsule_in_full_closing_corridor_rejects_close_without_pinch",access.blocked_closures>blocked_before and float(door.target_fraction)==1.0 and float(door.fraction)>.99 and door.body.global_transform==body_before and scene.player.global_position.distance_to(player_before)<.005,{"state":access.snapshot(),"player":scene.player.global_position})
	await _walk_point(inside,"door.clear_inside_landing_before_close")
	_e(true);_e(false);await _ticks(9)
	var mid_fraction: float=door.fraction;var mid_transform: Transform3D=door.body.global_transform
	scene.toggle_menu();await _ticks(22)
	_check("door.pause_exactly_freezes_moving_leaf",paused and mid_fraction>0.0 and mid_fraction<1.0 and door.fraction==mid_fraction and door.body.global_transform==mid_transform,{"fraction":door.fraction,"body":door.body.global_transform})
	scene.toggle_menu();await _ticks(50)
	_check("door.clear_close_finishes_and_automatically_relocks",float(door.fraction)==0.0 and bool(door.locked) and not _door_ray(door).is_empty(),access.snapshot())
	access.set_admin_access(false);await _ticks(3);_e(true);_e(false);await _ticks(50)
	_check("door.inside_guest_can_exit_even_with_admin_OFF",float(door.fraction)>.99 and not bool(door.locked),access.snapshot())
	await _walk_point(outside,"door.inside_egress_keeps_actual_collision_contract")
	access.set_admin_access(true)
	door_observations.append(access.snapshot())

func _inspect_population(title: String,required_roles: Array,required_parts: Array) -> void:
	var module: Node3D=visit.room.population;var state: Dictionary=module.snapshot();var roles:=[];var parts:={};var body_count:=0;var blocked:=[];var reserved:=[];var missing_seats:=[]
	for row: Dictionary in state.roles:roles.append(String(row.role))
	for node in _descendants(module):
		if node is CollisionObject3D:body_count+=1
		if node is MeshInstance3D:parts[String(node.name)]=int(parts.get(String(node.name),0))+1
	var shape:=CapsuleShape3D.new();shape.radius=.22;shape.height=1.65
	for row: Dictionary in state.roles:
		if row.seated:
			var seat_found:=false
			for body: StaticBody3D in visit.room.bodies:
				if String(body.get_meta("geometry_id","")).trim_prefix("EXP04_interior_")==String(row.seat_geometry) and int(body.get_meta("detail_level",-1))==int(row.level):
					var point_on_floor: Vector3=body.position;point_on_floor.y=row.position.y
					if point_on_floor.distance_to(row.position)<.15:seat_found=true;break
			if not seat_found:missing_seats.append(row.role)
			continue
		var point: Vector3=visit.room.to_global(row.position)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.825)
		if not scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():blocked.append(row.role)
		for zone: AABB in visit.room.detail_kit.protected_zones:
			var floor_point:=Vector3(row.position.x,.8,row.position.z)
			if zone.has_point(floor_point):reserved.append(row.role)
	var covered:=true
	for role in required_roles:
		if not roles.has(role):covered=false
	for part in required_parts:
		if int(parts.get(part,0))==0:covered=false
	var evidence:={"title":title,"building":visit.current_spec.id,"population":state,"roles":roles,"actual_mesh_parts":parts,"added_collision_bodies":body_count,"standing_capsules_blocked":blocked,"protected_corridor_occupants":reserved,"seated_roles_without_actual_seats":missing_seats}
	role_observations.append(evidence)
	_check("population."+title+".distinct_roles_have_actual_props_and_safe_nonblocking_placements",covered and state.count>=2 and state.count<=5 and body_count==0 and blocked.is_empty() and reserved.is_empty() and missing_seats.is_empty(),evidence)

func _population_pause() -> void:
	var population: Node3D=visit.room.population;var before:=[]
	for node in _descendants(population):
		if node is Node3D:before.append(node.transform)
	scene.toggle_menu();await _ticks(20);var after:=[]
	for node in _descendants(population):
		if node is Node3D:after.append(node.transform)
	_check("population.menu_exactly_freezes_all_role_models_and_props",paused and before==after,{"transforms_observed":before.size()})
	scene.toggle_menu();await _ticks(3)

func _run() -> void:
	for path in ["res://scripts/interior_room_access.gd","res://scripts/interior_population.gd","res://scripts/building_interior_space.gd","res://scripts/interior_detail_kit.gd","res://scripts/interior_visit.gd","res://scripts/explore_walk.gd","res://../tests/game/check_interior_access_population.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);activity=visit.facility_interaction;access=scene.find_child("InteriorRoomAccess",true,false)
	_check("startup.production_admin_room_access_API",is_instance_valid(access) and access.has_method("set_admin_access") and access.admin_access)
	if not is_instance_valid(access):_finish();return
	original_inventory=_inventory();player_shape_before=_player_shape()
	if await _enter(HOTEL_ID,"roles_hotel"):
		_inspect_population("hotel_lobby",["hotel_reception","hotel_traveller"],["ReceptionBadge","Suitcase"])
		await _population_pause();await _people_check()
		await _door_trial()
		_inspect_population("hotel_guest",["hotel_housekeeper","hotel_guest"],["CleaningCart","FoldedCleaningTowel","Suitcase"])
		if await _ride_to(3,"roles_gym"):
			_inspect_population("hotel_gym",["gym_stretch","gym_rest"],["SportsTowel","BareSportCalf","WaterBottle"])
			await _population_pause();await _capture_role("gym_population_roles","gym_stretch","SportsTowel")
		visit.return_to_world_spawn();await _ticks(8)
	if await _enter(LIBRARY_ID,"roles_library"):
		if await _ride_to(1,"roles_library_reading"):
			_inspect_population("library_reading",["library_reader","library_browser"],["OpenBook","BookPages"])
			await _people_check();await _capture("library_population_roles")
		visit.return_to_world_spawn();await _ticks(8)
	if await _enter(OFFICE_ID,"roles_office"):
		var work_level:=-1
		for row: Dictionary in visit.room.detail_kit.level_profiles:
			if row.profile_id=="office_work":work_level=int(row.level);break
		if work_level>=0 and await _ride_to(work_level,"roles_office_work"):
			_inspect_population("office_work",["office_worker","office_colleague"],["LaptopScreen","Briefcase"])
			await _capture_role("office_population_roles","office_worker","LaptopScreen")
		visit.return_to_world_spawn();await _ticks(8)
	_check("regression.original_source_shapes_and_player_capsule_retained",_inventory()==original_inventory and _player_shape()==player_shape_before and not scene.player.interior_active and not scene.player.facility_control,{"original_source_bodies":original_inventory.size(),"player_shape":_player_shape()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var report:={"task":"ADMIN_GUEST_ROOMS_AND_ROLE_POPULATION","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"roles":role_observations,"doors":door_observations,"role_camera_observations":role_camera_observations,"scenario_starts":placements,"walks":walks,"captures":captures,"scope":"Source-sized representative hotel lobby/guest/gym, library reading floor and office work floor. Production E/admin mode, physical moving leaf, actual closed/open ray collision, capsule blocked-close, walk-through/inside-egress and pause; role parts and small standing capsules are independently observed. Role captures independently check actual head/prop projection, static LOS, original-avatar/HUD exclusion and a grounded player stance before a native forced frame. Scenario starts are labelled, movement contains no per-step teleports and no NPC/avatar model is relocated for a screenshot. Guest doors enclose authored game rooms only; exterior private/source bodies are unchanged. No surveyed occupancy, full catalog role audit, human usability or performance acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1
	print("INTERIOR_ACCESS_POPULATION_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed);quit(0 if failed==0 else 1)

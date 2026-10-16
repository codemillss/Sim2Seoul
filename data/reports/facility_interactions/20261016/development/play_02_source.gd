extends "res://../tests/game/check_building_visits.gd"
## EXP11 independent production-E, physical control and actual effect checks.
## Scenario starts are recorded; interaction sessions never call handle_interact.
const HOTEL_ID := "osm:way:233593619:building"
const OFFICE_ID := "osm:way:332565592:building"
var activity
var activity_observations: Array = []
var target_observations: Array = []
var deferred_checks: Array = []
var started_at := ""
var player_shape_before := {}

func _initialize() -> void:
	started_at = Time.get_datetime_string_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_facility_interactions requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second=60
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
		var result:={}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result:=[]
		for item in value:result.append(_json(item))
		return result
	return value

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("FACILITY_INTERACTION_CHECK_FAIL "+title)

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node]=[]
	for child in node.get_children():
		result.append(child);result.append_array(_descendants(child))
	return result

func _player_shape() -> Dictionary:
	var node: CollisionShape3D=scene.player.get_node("CollisionShape")
	return {"shape":node.shape.get_instance_id(),"shape_transform":node.transform,"shape_class":node.shape.get_class(),"height":node.shape.height,"radius":node.shape.radius,"disabled":node.disabled,"layer":scene.player.collision_layer,"mask":scene.player.collision_mask}

func _state() -> Dictionary:return activity.snapshot()

func _target(kind: String,level := -1) -> Dictionary:
	for target: Dictionary in visit.room.detail_kit.facility_kit.interactions:
		if String(target.kind)==kind and (level<0 or int(target.level)==level):return target
	return {}

func _mesh_observation() -> Dictionary:
	var result:={};var roles:={};var visible:=0;var solid:=0
	for node in _descendants(activity):
		if node is CollisionObject3D:solid+=1
		if not node is MeshInstance3D or not node.has_meta("role"):continue
		var role:=String(node.get_meta("role"))
		if node.is_visible_in_tree():visible+=1
		roles[role]=int(roles.get(role,0))+1
		result[String(activity.get_path_to(node))]={"role":role,"transform":node.global_transform,"visible":node.is_visible_in_tree(),"mesh":node.mesh.get_class() if node.mesh!=null else "missing"}
	return {"meshes":result,"roles":roles,"mesh_count":result.size(),"visible_mesh_count":visible,"solid_count":solid}

func _changed_meshes(first: Dictionary,second: Dictionary) -> int:
	var changed:=0
	for key in first.meshes:
		if second.meshes.has(key) and first.meshes[key].transform!=second.meshes[key].transform:changed+=1
	return changed

func _actual_roles(kind: String,observation: Dictionary) -> bool:
	var required: Array={"eat":["meal_plate","meal_food","chopstick","food_bite"],"shower":["shower_stream","shower_drop"],"treadmill":["belt_stripe"],"weights":["activity_dumbbell","activity_hand"]}.get(kind,[])
	for role in required:
		if int(observation.roles.get(role,0))==0:return false
	return not required.is_empty() and observation.visible_mesh_count>0 and observation.solid_count==0

func _inspect_targets(title: String) -> void:
	var errors:=[];var ids:={};var kinds:={};var rows:=[]
	for target: Dictionary in visit.room.detail_kit.facility_kit.interactions:
		var valid: bool=target.has_all(["id","kind","title","level","facility_id","use_point","approach_point","anchor_point"])
		valid=valid and target.get("use_point") is Vector3 and target.get("approach_point") is Vector3 and target.get("anchor_point") is Vector3
		if not valid:errors.append({"kind":"schema","target":target});continue
		if ids.has(target.id):errors.append({"kind":"duplicate_id","id":target.id})
		ids[target.id]=true;kinds[target.kind]=int(kinds.get(target.kind,0))+1
		if String(target.title).is_empty() or int(target.level)<0 or int(target.level)>=visit.room.floor_count:errors.append({"kind":"title_or_level","id":target.id})
		var matching:=false
		for facility: Dictionary in visit.room.detail_kit.facility_kit.facilities:
			if facility.id==target.facility_id and facility.level==target.level:matching=true
		if not matching:errors.append({"kind":"facility_link","id":target.id})
		for key in ["use_point","approach_point","anchor_point"]:
			if not target[key].is_finite():errors.append({"kind":"nonfinite_point","id":target.id,"key":key})
		rows.append(target)
	var evidence:={"building":visit.current_spec.id,"target_count":rows.size(),"kinds":kinds,"targets":rows,"errors":errors}
	target_observations.append(evidence)
	_check("targets."+title+".source_facility_links_and_finite_local_points",not rows.is_empty() and errors.is_empty(),evidence)
	if title=="hotel":_check("targets.hotel.all_four_usable_kinds",kinds.has_all(["eat","shower","treadmill","weights"]),evidence)

func _ride_to(level: int,title: String) -> bool:
	var current: int=int(visit.snapshot().current_floor)
	if current==level:return true
	if not await _pose(title+"_lift_call",visit.room.elevator_point(current)):return false
	_e(true);_e(false);await _ticks(4)
	var picker: bool=visit.elevator_open
	var accepted: bool=picker and visit.request_floor(level)
	_check("navigation."+title+".physical_E_picker_and_production_ride",accepted,{"from":current,"to":level,"picker":picker})
	if not accepted:return false
	await _wait_elevator_end();await _ticks(6)
	var arrived: bool=not visit.in_elevator and visit.selected_floor==level and scene.player.is_on_floor() and scene.rig.camera.current and scene.player.is_physics_processing()
	_check("navigation."+title+".actual_safe_floor_arrival",arrived,visit.snapshot())
	return arrived

func _walk_to_target(target: Dictionary,title: String) -> bool:
	# The treadmill deck is a real 10cm solid. Walk to its floor-side approach;
	# production E validates the short mount instead of test-teleporting on it.
	var treadmill: bool=String(target.kind)=="treadmill"
	var approach: Vector3=target.approach_point+Vector3(0,0,.60) if treadmill else target.approach_point
	if not await _pose(title+"_approach",visit.room.to_global(approach)):return false
	var endpoint: Vector3=visit.room.to_global(target.approach_point if treadmill else target.use_point)
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	var samples:=0;var reached:=false;var max_step:=0.
	for index in range(360):
		var offset: Vector3=endpoint-scene.player.global_position
		var flat:=Vector3(offset.x,0.,offset.z)
		if flat.length()<.13 and absf(offset.y)<.3:reached=true;break
		_world_keys(flat.normalized());var prior: Vector3=scene.player.global_position
		await scene.player.physics_stepped;samples+=1
		max_step=maxf(max_step,scene.player.global_position.distance_to(prior))
		if scene.player.recoveries!=recoveries:break
	_movement();await _ticks(5)
	var evidence:={"target":target.id,"start":start,"end":scene.player.global_position,"requested":endpoint,"samples":samples,"max_step_m":max_step,"grounded":scene.player.is_on_floor(),"recoveries_before":recoveries,"recoveries_after":scene.player.recoveries,"method":"production movement from an explicit approach start; no per-step position writes"}
	walks.append(evidence)
	_check("walk."+title+".real_controller_reaches_equipment",reached and samples>0 and max_step<.2 and scene.player.is_on_floor() and scene.player.recoveries==recoveries,evidence)
	return reached and scene.player.is_on_floor()

func _begin(target: Dictionary,title: String,held := false) -> bool:
	if not await _walk_to_target(target,title):return false
	var before:=_state()
	_e(true)
	if not held:_e(false)
	await _ticks(3)
	var after:=_state()
	var started: bool=after.active and after.kind==target.kind and after.target_id==target.id
	_check("action."+title+".physical_E_starts_actual_target",started,{"target":target,"before":before,"after":after,"tap_between_physics":not held})
	if not started:return false
	_check("action."+title+".existing_capsule_and_source_shapes_remain",_player_shape()==player_shape_before and _inventory()==original_inventory,{"player_shape":_player_shape(),"source_body_count":original_inventory.size()})
	if String(target.kind)=="treadmill":
		var at: Vector3=scene.player.global_position
		var support: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.15,at-Vector3.UP*.35,1,[scene.player.get_rid()]))
		var original_deck: bool=not support.is_empty() and String(support.collider.get_meta("geometry_id","")).ends_with("Detail_FacilityTreadmill")
		_check("mount."+title+".production_E_places_existing_capsule_on_actual_solid_deck",at.distance_to(visit.room.to_global(target.use_point))<.001 and original_deck and support.normal.y>.99,{"position":at,"target":target.use_point,"support":support.get("position",Vector3.INF),"support_id":String(support.collider.get_meta("geometry_id","")) if not support.is_empty() else "missing"})
	return true

func _pause_action(title: String) -> void:
	var before:=_state();var mesh_before:=_mesh_observation();var player_before: Vector3=scene.player.global_position
	var avatar_before: Transform3D=scene.player.get_node("Visual").transform
	scene.toggle_menu();_e(true);_e(false);await _ticks(18)
	var after:=_state();var mesh_after:=_mesh_observation()
	var exact: bool=before.elapsed==after.elapsed and before.fullness==after.fullness and before.cleanliness==after.cleanliness and before.workout_distance_m==after.workout_distance_m and before.workout_repetitions==after.workout_repetitions and before.session==after.session and mesh_before==mesh_after and scene.player.global_position==player_before and scene.player.get_node("Visual").transform==avatar_before
	_check("pause."+title+".actual_meshes_timers_stats_and_body_exactly_frozen",paused and exact and scene.menu.is_visible_in_tree(),{"before":before,"after":after,"mesh_before":mesh_before,"mesh_after":mesh_after})
	scene.toggle_menu();await _ticks(3)
	var resumed:=_state()
	_check("pause."+title+".resume_same_session_without_buffered_E",resumed.active and resumed.target_id==before.target_id and resumed.elapsed>before.elapsed,{"after":resumed})

func _held_control_check(title: String) -> void:
	var at: Vector3=scene.player.global_position;var air: int=scene.player.air_jumps_remaining()
	_movement(["move_forward","move_fast","jump"]);await _ticks(18)
	_check("control."+title+".held_walk_run_jump_cannot_move_or_spend_air_jump",scene.player.global_position.distance_to(at)<.001 and scene.player.velocity==Vector3.ZERO and scene.player.air_jumps_remaining()==air and scene.player.facility_control and _player_shape()==player_shape_before,{"before":at,"after":scene.player.global_position,"air_before":air,"air_after":scene.player.air_jumps_remaining(),"state":_state()})
	_movement();await _ticks(3)

func _cancel_by_E(title: String) -> void:
	_e(false);await _ticks(3)
	_movement(["move_forward","move_fast","jump"])
	_e(true);await _ticks(3)
	var after:=_state();var at: Vector3=scene.player.global_position
	await _ticks(12)
	var final:=_state()
	_check("action."+title+".physical_E_stops_and_held_key_cannot_restart",not after.active and not final.active and after.completed_counts==final.completed_counts and not scene.player.facility_control,{"after":after,"after_held_E":final})
	_check("control."+title+".stop_requires_neutral_before_walking_or_jumping",scene.player.input_latched and scene.player.global_position.distance_to(at)<.001 and scene.player.velocity==Vector3.ZERO,{"stopped_at":at,"after":scene.player.global_position})
	_e(false);_movement();await _ticks(6)
	_check("control."+title+".neutral_releases_without_ghost_visuals",not scene.player.input_latched and not scene.player.facility_control and _mesh_observation().visible_mesh_count==0,{"state":_state(),"meshes":_mesh_observation()})

func _capture_activity(title: String,target: Dictionary,small := false) -> void:
	if DisplayServer.get_name()=="headless":
		deferred_checks.append({"name":"capture."+title,"reason":"headless_has_no_rendered_viewport"});return
	var size_before:=root.size;var scale_before:=root.content_scale_size;var mode_before:=root.content_scale_mode
	if small:
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(640,480)
	var anchor: Vector3=visit.room.to_global(target.anchor_point)
	var pivot: Vector3=scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
	var direction:=anchor-pivot
	if Vector2(direction.x,direction.z).length()>.01:scene.rig.yaw=atan2(-direction.x,-direction.z)+deg_to_rad(24.)
	scene.rig.pitch=deg_to_rad(-8.);scene.rig.requested_distance=2.6;scene.rig.snap_to_target_pose()
	await _ticks(6)
	var view:=Rect2(Vector2.ZERO,scene.get_viewport().get_visible_rect().size)
	var prompt: Rect2=visit.prompt.get_global_rect();var indoor: Rect2=visit.indoor_panel.get_global_rect()
	var panel: Control=scene.get_node("Interface/FacilityActivityStatus")
	var status: Rect2=panel.get_global_rect()
	var layout_ok: bool=view.encloses(prompt) and view.encloses(indoor) and view.encloses(status) and not prompt.intersects(indoor) and not prompt.intersects(status) and not indoor.intersects(status) and visit.prompt.is_visible_in_tree() and visit.indoor_panel.is_visible_in_tree() and panel.is_visible_in_tree()
	_check("capture_pose."+title+".normal_camera_clear_and_activity_HUD_fits",scene.get_viewport().get_camera_3d()==scene.rig.camera and _camera_clear() and layout_ok,{"viewport":view,"prompt":prompt,"indoor":indoor,"activity_status":status,"prompt_text":visit.prompt_text.text,"activity_text":_state().status_text,"camera":scene.rig.camera.global_transform,"zoom":scene.rig.requested_distance,"active":_state().active})
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path:=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var evidence:={"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"state":_state(),"actual_meshes":_mesh_observation()}
	captures.append(evidence);_check("capture."+title,saved,evidence)
	if small:
		root.size=size_before;root.content_scale_size=scale_before;root.content_scale_mode=mode_before;await _ticks(5)

func _observe_animation(kind: String,title: String) -> void:
	var first:=_mesh_observation();var state_before:=_state()
	await _ticks(25)
	var second:=_mesh_observation();var state_after:=_state()
	var moving:=_changed_meshes(first,second)
	var evidence:={"kind":kind,"before":state_before,"after":state_after,"actual_before":first,"actual_after":second,"actual_mesh_transforms_changed":moving}
	activity_observations.append(evidence)
	_check("visual."+title+".actual_distinct_meshes_animate_without_added_collision",_actual_roles(kind,first) and _actual_roles(kind,second) and moving>0 and state_after.elapsed>state_before.elapsed,evidence)

func _eating(target: Dictionary,title: String) -> void:
	if not await _begin(target,title):return
	var initial:=_state()
	await _observe_animation("eat",title)
	await _held_control_check(title)
	await _pause_action(title)
	for index in range(120):
		if not _state().active or int(_state().session.get("bites",0))>0:break
		await _ticks(1)
	var bite_observation:=_mesh_observation();var visible_food:=0
	for row: Dictionary in bite_observation.meshes.values():
		if row.role=="meal_food" and row.visible:visible_food+=1
	_check("meal."+title+".actual_plate_food_decreases_after_first_bite",_state().active and int(_state().session.get("bites",0))==1 and visible_food==2,{"state":_state(),"visible_food_meshes":visible_food,"actual_meshes":bite_observation})
	await _capture_activity(title+"_meal_in_progress",target)
	await _capture_activity(title+"_meal_small_HUD",target,true)
	_movement(["move_forward","jump"])
	for index in range(800):
		if not _state().active:break
		await _ticks(1)
	var after:=_state();var at: Vector3=scene.player.global_position
	await _ticks(10)
	_check("meal."+title+".real_time_completion_increases_fullness_and_count",not after.active and absf(float(after.fullness)-float(initial.fullness)-minf(24.,100.-float(initial.fullness)))<.001 and int(after.last_session.bites)==3 and int(after.completed_counts.get("eat",0))==int(initial.completed_counts.get("eat",0))+1,{"initial":initial,"after":after})
	_check("meal."+title+".completion_releases_control_without_held_input_or_effect_leak",not scene.player.facility_control and scene.player.input_latched and scene.player.global_position.distance_to(at)<.001 and _mesh_observation().visible_mesh_count==0,{"after":after,"at":at,"held_after":scene.player.global_position})
	_movement();_e(false);await _ticks(6)
	_check("meal."+title+".completion_neutral_gate_can_release",not scene.player.input_latched)

func _shower(target: Dictionary) -> void:
	if not await _begin(target,"hotel_shower",true):return
	var initial:=_state()
	await _ticks(14)
	_check("input.shower.held_start_key_neither_cancels_nor_duplicates",_state().active and _state().target_id==target.id and _state().completed_counts==initial.completed_counts,{"initial":initial,"after":_state()})
	_e(false);await _ticks(3)
	await _observe_animation("shower","hotel_shower")
	await _held_control_check("hotel_shower")
	await _pause_action("hotel_shower")
	await _capture_activity("hotel_running_shower",target)
	for index in range(1000):
		if not _state().active or float(_state().elapsed)>float(_state().duration)+.5:break
		await _ticks(1)
	var washing:=_state()
	_check("shower.actual_elapsed_water_washes_and_cleanliness_increases",washing.active and washing.cleanliness>initial.cleanliness and washing.visual.water_on and int(_mesh_observation().roles.get("shower_stream",0))>0,{"initial":initial,"washing":washing})
	_check("shower.water_continues_past_reference_duration_until_E",washing.active and float(washing.elapsed)>float(washing.duration)+.5,{"state":washing})
	await _cancel_by_E("hotel_shower")
	_check("shower.E_stop_removes_water_streams_and_retains_earned_cleanliness",not bool(_state().get("visual",{}).get("water_on",false)) and _state().cleanliness>=washing.cleanliness and _mesh_observation().visible_mesh_count==0,{"state":_state()})

func _exercise(target: Dictionary) -> void:
	var kind:=String(target.kind);var title:="hotel_"+kind
	if not await _begin(target,title):return
	var initial:=_state()
	await _observe_animation(kind,title)
	await _held_control_check(title)
	await _pause_action(title)
	await _capture_activity(title+"_in_use",target)
	for index in range(1200):
		if not _state().active or float(_state().elapsed)>float(_state().duration)+.5:break
		await _ticks(1)
	var running:=_state()
	var earned: bool=running.workout_distance_m>initial.workout_distance_m if kind=="treadmill" else int(running.workout_repetitions)>int(initial.workout_repetitions)
	_check("exercise."+kind+".actual_work_increases_distance_or_full_repetition_count",running.active and earned,{"initial":initial,"running":running})
	_check("exercise."+kind+".continues_past_reference_duration_until_E",running.active and float(running.elapsed)>float(running.duration)+.5,{"state":running})
	_check("exercise."+kind+".cannot_call_lift_while_equipment_owns_player",not visit.request_floor(0) and not visit.in_elevator and not visit.elevator_open)
	await _cancel_by_E(title)
	var after:=_state()
	_check("exercise."+kind+".E_stop_preserves_earned_work",float(after.workout_distance_m)>=float(running.workout_distance_m) and int(after.workout_repetitions)>=int(running.workout_repetitions),{"before_stop":running,"after":after})

func _refusals(target: Dictionary) -> void:
	# Find a physically clear, target-free storey at the exact same XZ. The
	# lobby may have furniture here, so a guessed below-counter pose is invalid.
	var wrong_point:=Vector3.INF;var wrong_level:=-1
	var collider: CollisionShape3D=scene.player.get_node("CollisionShape")
	for level in range(visit.room.floor_count):
		if level==int(target.level):continue
		var has_target:=false
		for other: Dictionary in visit.room.detail_kit.facility_kit.interactions:
			if int(other.level)==level:has_target=true;break
		if has_target:continue
		var local: Vector3=target.use_point;local.y=level*visit.room.floor_height+.08
		var point: Vector3=visit.room.to_global(local)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=collider.shape;query.collision_mask=scene.player.collision_mask
		query.transform=Transform3D(Basis.IDENTITY,point)*collider.transform;query.exclude=[scene.player.get_rid()]
		var hits: Array=scene.get_world_3d().direct_space_state.intersect_shape(query,1)
		var support: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.20,point-Vector3.UP*.30,1,[scene.player.get_rid()]))
		if hits.is_empty() and not support.is_empty() and absf(support.position.y-point.y+.08)<.03:
			wrong_point=point;wrong_level=level;break
	_check("fixture.same_XZ_wrong_floor_is_physically_clear_and_target_free",wrong_point.is_finite(),{"selected_floor":wrong_level,"point":wrong_point,"target":target})
	if not wrong_point.is_finite():return
	if not await _pose("wrong_floor_same_XZ",wrong_point):return
	_e(true);_e(false);await _ticks(4)
	_check("refusal.same_XZ_wrong_floor_does_not_activate",not _state().active and not scene.player.facility_control,{"player":scene.player.global_position,"target":target,"state":_state()})
	if not await _pose("far_from_equipment",visit.room.floor_spawn(0)):return
	_e(true);_e(false);await _ticks(4)
	_check("refusal.far_E_is_not_buffered",not _state().active,{"state":_state(),"player":scene.player.global_position})
	if not await _pose("after_rejected_E_near_equipment",visit.room.to_global(target.use_point)):return
	await _ticks(8)
	_check("refusal.rejected_far_press_cannot_auto_start_on_approach",not _state().active)
	var from: Vector3=scene.player.global_position+Vector3.UP*1.0
	var to: Vector3=visit.room.to_global(target.anchor_point)
	var obstacle:=StaticBody3D.new();obstacle.name="EXP11ExplicitOcclusionFixture";obstacle.collision_layer=1;obstacle.collision_mask=0
	var shape_node:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.18,1.8,.18);shape_node.shape=box
	obstacle.add_child(shape_node);scene.add_child(obstacle);obstacle.global_position=from.lerp(to,.58)
	await _ticks(4)
	var ray:=PhysicsRayQueryParameters3D.create(from,to,1,[scene.player.get_rid()])
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	_e(true);_e(false);await _ticks(4)
	_check("refusal.actual_intervening_solid_blocks_E",not hit.is_empty() and hit.collider==obstacle and not _state().active,{"ray_hit_fixture":not hit.is_empty() and hit.collider==obstacle,"from":from,"to":to,"state":_state()})
	obstacle.queue_free();await _ticks(5)
	await _pose("refusals_return_to_lobby",visit.room.floor_spawn(0))

func _cleanup_checks(target: Dictionary) -> void:
	if not await _begin(target,"cleanup_world_reset"):return
	await _ticks(20)
	var earned:=_state()
	scene.reset_player();await _ticks(8)
	_check("cleanup.normal_game_reset_leaves_building_and_releases_facility_control",not visit.active and not scene.player.interior_active and not scene.player.facility_control and not _state().active and _mesh_observation().visible_mesh_count==0 and scene.player.is_physics_processing(),{"state":_state(),"visit":visit.snapshot(),"player":scene.player.global_position})
	_check("cleanup.normal_game_reset_preserves_accumulated_session_stats",_state().fullness>=earned.fullness and _state().cleanliness>=earned.cleanliness and _state().workout_distance_m>=earned.workout_distance_m and _state().workout_repetitions>=earned.workout_repetitions)
	_movement();_e(false);await _ticks(6)

func _run() -> void:
	for path in ["res://scripts/interior_visit.gd","res://scripts/facility_interaction.gd","res://scripts/facility_activity_visuals.gd","res://scripts/interior_facility_kit.gd","res://scripts/interior_detail_kit.gd","res://scripts/building_interior_space.gd","res://scripts/player/free_roam_player.gd","res://scripts/elevator_cabin.gd","res://scripts/rooftop_space.gd","res://scripts/water_effect.gd","res://../tests/game/check_building_visits.gd","res://../tests/game/check_facility_interactions.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25)
	activity=visit.get("facility_interaction")
	var api: bool=is_instance_valid(activity) and activity.has_method("snapshot") and activity.has_method("is_using") and scene.player.has_method("set_facility_control")
	_check("startup.production_activity_and_controller_API",api)
	if not api:_finish();return
	original_inventory=_inventory();player_shape_before=_player_shape()
	if await _enter(HOTEL_ID,"hotel"):
		_inspect_targets("hotel")
		var meal:=_target("eat",1)
		var shower:=_target("shower",4)
		var treadmill:=_target("treadmill",3)
		var weights:=_target("weights",3)
		_check("hotel.requested_source_floors_have_actual_action_targets",not meal.is_empty() and not shower.is_empty() and not treadmill.is_empty() and not weights.is_empty(),{"meal":meal,"shower":shower,"treadmill":treadmill,"weights":weights})
		if not meal.is_empty():
			await _refusals(meal)
			if await _ride_to(1,"hotel_buffet"):await _eating(meal,"hotel_buffet")
		if not shower.is_empty() and await _ride_to(4,"hotel_spa"):await _shower(shower)
		if not treadmill.is_empty() and await _ride_to(3,"hotel_gym"):
			await _exercise(treadmill)
			if not weights.is_empty():await _exercise(weights)
		if not treadmill.is_empty():await _cleanup_checks(treadmill)
	if visit.active:
		visit.return_to_world_spawn();await _ticks(8)
	if await _enter(OFFICE_ID,"office"):
		_inspect_targets("office")
		var meal:=_target("eat")
		_check("office.usable_food_is_not_hotel_exclusive",not meal.is_empty(),{"target":meal})
		if not meal.is_empty() and await _ride_to(int(meal.level),"office_cafeteria"):
			if await _begin(meal,"office_meal"):
				await _observe_animation("eat","office_meal")
				await _capture_activity("office_meal_in_progress",meal)
				await _cancel_by_E("office_meal")
		visit.return_to_world_spawn();await _ticks(8)
	_check("cleanup.room_replacement_and_outdoor_return_leave_no_activity",not _state().active and not scene.player.facility_control and _mesh_observation().visible_mesh_count==0 and not scene.player.interior_active,{"state":_state(),"player_shape":_player_shape()})
	_check("regression.original_outdoor_shapes_and_player_capsule_unchanged",_inventory()==original_inventory and _player_shape()==player_shape_before,{"source_body_count":original_inventory.size(),"player_shape_before":player_shape_before,"player_shape_after":_player_shape()})
	_check("regression.facility_exit_does_not_install_swimming_or_spend_ground_air_jump",not scene.player.is_swimming() and scene.player.air_jumps_remaining()==1 and scene.player.is_on_floor(),{"water":scene.player.water_snapshot(),"air_jumps_remaining":scene.player.air_jumps_remaining()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var report:={"task":"facility_interactions","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"source_sha256":source_hashes,"checks":checks,"summary":{"checks":checks.size(),"failed":failed},"scenario_starts":placements,"walks":walks,"targets":target_observations,"activity_observations":activity_observations,"captures":captures,"deferred_checks":deferred_checks,"final_state":_state() if is_instance_valid(activity) else {},"scope":"Representative actual hotel buffet2F, gym4F, spa5F and office cafeteria. Production physical E edges start/stop every happy-path action; floor navigation uses physical E picker plus production request_floor. Recorded scenario starts position only before controller walks; no handle_interact call or counter injection. Independent actual MeshInstance3D role/transform observations, real stats and physics lock, pause exactness, solid LOS rejection, reset cleanup and source collision inventory. Native normal-camera PNGs and HUD bounds only when display is not headless. Authored game facilities; no real hotel service, nutrition/health claim, full catalog action audit, human OS keyboard input, performance or fluid simulation acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(report),"\t")+"\n");file.close()
	else:failed+=1;push_error("Could not save facility interactions report")
	print("FACILITY_INTERACTIONS_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

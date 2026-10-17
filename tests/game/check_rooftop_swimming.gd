extends "res://../tests/game/check_building_visits.gd"
## Physics entry/float/exit in a real source-positioned roof pool.
const HOTEL_ID := "osm:way:233593619:building"
var swim_trials: Array = []
var deferred_checks: Array = []
var basin_observation := {}
var roof

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var result:={}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result:=[]
		for item in value:result.append(_json(item))
		return result
	return value

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node]=[]
	for child in node.get_children():result.append(child);result.append_array(_descendants(child))
	return result

func _effect_geometry() -> Array:
	var result:=[]
	if not is_instance_valid(roof) or not is_instance_valid(roof.water_effects):return result
	for node in _descendants(roof.water_effects):
		if node is MeshInstance3D and node.mesh!=null:result.append({"node":node.get_instance_id(),"name":String(node.name),"visible":node.is_visible_in_tree(),"transform":node.global_transform,"local_transform":node.transform,"mesh_bounds":node.mesh.get_aabb()})
	return result

func _capture_pool(title: String) -> void:
	var direction: Vector3=-roof.frame.basis.x
	scene.rig.yaw=atan2(-direction.x,-direction.z);scene.rig.pitch=deg_to_rad(-20.);scene.rig.requested_distance=4.
	scene.rig.global_position=scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
	scene.rig.rotation=Vector3(scene.rig.pitch,scene.rig.yaw,0);scene.rig.snap_to_target_pose()
	if DisplayServer.get_name()=="headless":deferred_checks.append({"name":"capture."+title,"reason":"headless_has_no_rendered_viewport"});return
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path:=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row:={"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"water":scene.player.water_snapshot(),"effects":roof.water_effects.snapshot()}
	captures.append(row);_check("capture."+title,saved,row)

func _body_bounds(body: StaticBody3D) -> AABB:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return body.global_transform*child.transform*AABB(-child.shape.size*.5,child.shape.size)
	return AABB()

func _observe_raised_basin() -> void:
	# Historical helper name retained for inheriting probes. Observe the new
	# sunken basin's actual collision floor, four deck panels and open hole.
	var floor: StaticBody3D=roof.get_node("PoolSafetyFloorBody")
	var floor_bounds: AABB=_body_bounds(floor)
	var deck_bounds: AABB=AABB()
	var deck_ids: Array=[]
	var first_panel: bool=true
	var rim_top: float=-INF
	for body: StaticBody3D in roof.bodies:
		var geometry: String=String(body.get_meta("geometry_id",""))
		if "DeckFloor" in geometry:
			var box: AABB=_body_bounds(body)
			deck_bounds=box if first_panel else deck_bounds.merge(box)
			first_panel=false;deck_ids.append(body.get_instance_id())
		if "PoolRim" in geometry:rim_top=maxf(rim_top,_body_bounds(body).end.y)
	var region: Dictionary=roof.pool_water_region()
	var surface: float=(region.frame*Vector3(0.,float(region.surface_y),0.)).y
	var observations: Array=[]
	var hole_errors: Array=[]
	var rect: Rect2=region.rect
	for ix: int in range(17):
		for iz: int in range(9):
			var x: float=lerpf(rect.position.x,rect.end.x,(float(ix)+.5)/17.0)
			var z: float=lerpf(rect.position.y,rect.end.y,(float(iz)+.5)/9.0)
			var start: Vector3=region.frame*Vector3(x,.12,z)
			var finish: Vector3=region.frame*Vector3(x,float(region.floor_y)-.20,z)
			var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,1,[scene.player.get_rid()]))
			var collider: Object=hit.get("collider")
			var geometry: String=String(collider.get_meta("geometry_id","")) if is_instance_valid(collider) else ""
			var row: Dictionary={"x":x,"z":z,"hit_geometry":geometry,"hit_world_y":hit.position.y if not hit.is_empty() else null}
			observations.append(row)
			if not ("PoolSafetyFloor" in geometry or "PoolSubmergedRamp" in geometry):hole_errors.append(row)
	basin_observation={"deck_bodies":deck_ids,"deck_bounds":deck_bounds,"pool_floor_body":floor.get_instance_id(),"pool_floor_bounds":floor_bounds,"rim_top_world_y":rim_top,"surface_world_y":surface,"region":region,"entry":roof.pool_entry_point(),"rim":roof.pool_rim_point(),"float":roof.pool_float_point(),"opening_rays":observations,"source_top_world_y":roof.observed_top_y,"deck_authored_raise_m":roof.pool_dimensions().get("deck_raise_m")}
	_check("basin.sunken_water_and_floor_below_flush_deck_above_unchanged_source",deck_ids.size()==4 and floor_bounds.end.y<deck_bounds.end.y-1.35 and surface<deck_bounds.end.y-.15 and surface>deck_bounds.end.y-.21 and absf(rim_top-deck_bounds.end.y)<.02 and floor_bounds.end.y>float(roof.observed_top_y)+.30,basin_observation)
	_check("basin.real_deck_hole_153_rays_reach_pool_floor_or_steps_without_deck_cover",hole_errors.is_empty(),{"rays":observations.size(),"errors":hole_errors})
	_check("basin.actual_water_depth_1_22_inside_original_XZ_footprint",region.rect.has_area() and absf(float(region.surface_y)-float(region.floor_y)-1.22)<.001 and roof.walkable_rect.encloses(region.rect) and roof.world_bounds.has_point(roof.pool_float_point()),basin_observation)

func _jump_into_pool() -> bool:
	if not await _pose("pool_external_ramp_start",roof.pool_entry_point()):return false
	var ramp_start: Vector3=scene.player.global_position
	var walked: bool=await _walk_path("pool.real_walk_on_deck_to_flush_entry",[roof.pool_rim_point()])
	_check("pool.flush_edge_reached_on_supported_deck_without_external_staircase",walked and scene.player.is_on_floor() and absf(scene.player.global_position.y-ramp_start.y)<.15,{"start":ramp_start,"end":scene.player.global_position})
	if not walked:return false
	var region: Dictionary=roof.pool_water_region()
	var center: Vector3=region.frame*Vector3(region.rect.get_center().x,0.,region.rect.get_center().y)
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	var before: Dictionary=scene.player.water_snapshot()
	var peak: float=start.y;var minimum:=INF;var first_wet:={};var observed:=[];var descending_before:=0.;var captured_fall:=false
	var direction:=Vector3(center.x-start.x,0.,center.z-start.z).normalized()
	_world_keys(direction);Input.action_press("jump")
	for tick in range(300):
		await _ticks(1)
		var point: Vector3=scene.player.global_position
		peak=maxf(peak,point.y)
		var remaining:=Vector3(center.x-point.x,0.,center.z-point.z)
		if remaining.length()>.16:_world_keys(remaining.normalized())
		else:_movement()
		if not scene.player.is_swimming():descending_before=minf(descending_before,scene.player.velocity.y)
		if not captured_fall and scene.player.velocity.y<-.8 and point.y>float(basin_observation.surface_world_y)+.5:captured_fall=true;await _capture_pool("jump_above_flush_pool")
		if scene.player.is_swimming():
			minimum=minf(minimum,point.y)
			first_wet={"tick":tick,"position":point,"velocity":scene.player.velocity,"state":scene.player.water_snapshot(),"effects":roof.water_effects.snapshot(),"effect_geometry":_effect_geometry()}
			_movement();await _ticks(12)
			await _capture_pool("splash_on_physical_entry");break
		if tick%5==0:observed.append({"tick":tick,"position":point,"velocity":scene.player.velocity})
	_movement()
	var entered: bool=not first_wet.is_empty()
	var after: Dictionary=scene.player.water_snapshot()
	var effects: Dictionary=roof.water_effects.snapshot()
	var active_meshes:=0
	for mesh: Dictionary in _effect_geometry():
		if mesh.visible:active_meshes+=1
	var row:={"start":start,"peak_world_y":peak,"descent_speed_before_entry":descending_before,"first_wet":first_wet,"entry_state_before":before,"entry_state_after":after,"recovery_delta":scene.player.recoveries-recoveries,"samples":observed,"active_effect_meshes":active_meshes,"effects":effects,"kind":"actual_move_and_slide_flush_deck_and_single_jump_no_midflight_teleports"}
	swim_trials.append(row)
	_check("pool.physical_jump_descends_below_flush_deck_and_emits_splash",entered and peak>start.y+2.8 and descending_before<-1. and int(after.entry_count)>int(before.entry_count) and int(effects.splash_count)>0 and active_meshes>0 and scene.player.recoveries==recoveries,row)
	return entered

func _float_and_swim() -> void:
	var region: Dictionary=roof.pool_water_region()
	var surface: float=basin_observation.surface_world_y
	var floor_top: float=basin_observation.pool_floor_bounds.end.y
	var ys:=[];var max_speed:=0.;var minimum:=INF;var recoveries: int=scene.player.recoveries
	for tick in range(150):
		await _ticks(1)
		minimum=minf(minimum,scene.player.global_position.y)
		max_speed=maxf(max_speed,absf(scene.player.velocity.y))
		if tick>=100:ys.append(scene.player.global_position.y)
	var depth: float=surface-scene.player.global_position.y
	var spread: float=float(ys.max())-float(ys.min())
	var row:={"settled_depth_m":depth,"minimum_foot_world_y":minimum,"retained_floor_world_y":floor_top,"last_50_tick_height_range_m":spread,"position":scene.player.global_position,"velocity":scene.player.velocity,"water":scene.player.water_snapshot(),"recoveries":scene.player.recoveries-recoveries}
	swim_trials.append(row)
	_check("water.real_buoyancy_settles_in_sunken_basin_without_source_roof_fall",scene.player.is_swimming() and depth>.35 and depth<1.3 and minimum>=floor_top-.03 and spread<.12 and scene.player.recoveries==recoveries,row)
	await _capture_pool("buoyant_swimming_in_sunken_basin")
	scene.set_speed_profile("turbo");_movement();await _ticks(3)
	var start: Vector3=scene.player.global_position
	var direction: Vector3=roof.frame.basis.z.normalized()
	_world_keys(direction);Input.action_press("move_fast")
	var horizontal_peak:=0.
	for tick in range(18):
		await _ticks(1)
		horizontal_peak=maxf(horizontal_peak,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
	_movement()
	_check("water.turbo_shift_is_limited_to_real_three_metre_swim_speed",scene.player.is_swimming() and horizontal_peak>1. and horizontal_peak<=3.02,{"maximum_horizontal_speed_mps":horizontal_peak,"distance_m":Vector2(scene.player.global_position.x-start.x,scene.player.global_position.z-start.z).length(),"selected_ground_run_speed":scene.player.run_speed_mps})
	scene.set_speed_profile("brisk");_movement();await _ticks(3)

func _menu_and_transactions() -> void:
	scene.toggle_menu()
	var pose: Transform3D=scene.player.global_transform
	var state: Dictionary=scene.player.water_snapshot()
	var geometry:=_effect_geometry()
	var effects: Dictionary=roof.water_effects.snapshot()
	await _ticks(18)
	_check("menu.pauses_actual_water_player_and_live_effect_meshes",paused and geometry.size()>0 and int(effects.active_splashes)>0 and scene.player.global_transform==pose and scene.player.water_snapshot()==state and roof.water_effects.snapshot()==effects and _effect_geometry()==geometry,{"actual_live_meshes":geometry.size(),"water_before":state,"water_after":scene.player.water_snapshot(),"effects_before":effects,"effects_after":roof.water_effects.snapshot()})
	scene.toggle_menu();_movement();await _ticks(3)
	_check("effects.real_splash_meshes_resume_motion_after_menu",_effect_geometry().size()>0 and _effect_geometry()!=geometry and float(roof.water_effects.snapshot().elapsed)>float(effects.elapsed),{"meshes_before":geometry,"meshes_after":_effect_geometry()})
	state=scene.player.water_snapshot();pose=scene.player.global_transform
	var velocity: Vector3=scene.player.velocity
	var rejected: bool=not scene.player.set_water_region({"id":"invalid_water","frame":Transform3D.IDENTITY,"rect":Rect2(),"floor_y":2.,"surface_y":1.})
	rejected=rejected and not scene.player.relocate_interior_region(Vector3.INF,roof.world_bounds,roof.frame,roof.walkable_rect) and not visit.request_floor(0)
	_check("transactions.invalid_water_region_landing_and_far_lift_preserve_swimming",rejected and scene.player.water_snapshot()==state and scene.player.global_transform==pose and scene.player.velocity==velocity,{"before":state,"after":scene.player.water_snapshot()})

func _exit_water() -> void:
	var region: Dictionary=roof.pool_water_region()
	var local: Vector3=region.frame.affine_inverse()*scene.player.global_position
	var shore: Vector3=region.frame*Vector3(region.rect.position.x+.58,local.y,clampf(local.z,region.rect.position.y+.7,region.rect.end.y-.7))
	for tick in range(300):
		var offset:=Vector3(shore.x-scene.player.global_position.x,0.,shore.z-scene.player.global_position.z)
		if offset.length()<.12:break
		_world_keys(offset.normalized());await _ticks(1)
	_movement();await _ticks(2)
	var before: Dictionary=scene.player.water_snapshot()
	var recoveries: int=scene.player.recoveries
	var outward: Vector3=-region.frame.basis.x
	_world_keys(outward);Input.action_press("jump")
	var peak: float=scene.player.global_position.y
	var dry_grounded:=false;var outside:=false
	for tick in range(300):
		await _ticks(1)
		peak=maxf(peak,scene.player.global_position.y)
		local=region.frame.affine_inverse()*scene.player.global_position
		outside=local.x<region.rect.position.x-.85
		if outside:_movement(["jump"])
		if outside and not scene.player.is_swimming() and scene.player.is_on_floor() and absf(scene.player.global_position.y-float(basin_observation.deck_bounds.end.y))<.15:dry_grounded=true;break
	var after: Dictionary=scene.player.water_snapshot()
	_check("water.Space_edge_exits_over_real_rim_and_lands_on_retained_deck",dry_grounded and peak>float(basin_observation.rim_top_world_y)+.25 and int(after.water_jump_count)==int(before.water_jump_count)+1 and scene.player.recoveries==recoveries,{"before":before,"after":after,"peak_world_y":peak,"rim_top_world_y":basin_observation.rim_top_world_y,"position":scene.player.global_position,"outside_pool":outside})
	await _capture_pool("Space_exit_back_on_deck")
	_movement(["jump"]);await _ticks(15)
	_check("water.held_Space_does_not_repeat_water_exit_or_ground_jump",not scene.player.is_swimming() and scene.player.is_on_floor() and int(scene.player.water_snapshot().water_jump_count)==int(after.water_jump_count))
	_movement()

func _run() -> void:
	for path in ["res://scripts/rooftop_space.gd","res://scripts/water_effect.gd","res://scripts/player/free_roam_player.gd","res://scripts/interior_visit.gd","res://scripts/elevator_cabin.gd","res://../tests/game/check_building_visits.gd","res://../tests/game/check_rooftop_swimming.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25);original_inventory=_inventory()
	if not await _enter(HOTEL_ID,"pool_hotel"):_finish();return
	if not await _pose("hotel_roof_lift_call",visit.room.elevator_point(0)):_finish();return
	_e(true);_e(false);await _ticks(4)
	var started: bool=visit.request_floor(visit.room.floor_count)
	_check("lift.roof_destination_accepted_for_pool_visit",started)
	if not started or not await _wait_elevator_end():_finish();return
	_movement();_e(false);await _ticks(12);roof=visit.rooftop
	var api: bool=roof.has_method("pool_water_region") and roof.has_method("pool_entry_point") and roof.has_method("pool_rim_point") and roof.has_method("pool_float_point") and scene.player.has_method("water_snapshot")
	_check("startup.real_rooftop_pool_and_water_API",api and visit.on_roof and roof.profile_id=="outdoor_pool")
	if not api:_finish();return
	_check("water.registered_only_after_successful_roof_landing",scene.player.water_snapshot().registered and not scene.player.is_swimming())
	_observe_raised_basin()
	if await _jump_into_pool():
		await _menu_and_transactions();await _float_and_swim();await _exit_water()
	if await _pose("pool_return_lift_call",roof.lift_point()):
		var accepted: bool=visit.request_floor(0)
		_check("lift.boarding_clears_registered_roof_water",accepted and not scene.player.water_snapshot().registered and not scene.player.is_swimming())
		await _wait_elevator_end();_movement();_e(false);await _ticks(8)
		_check("lift.indoor_arrival_stays_dry_with_original_region",not visit.on_roof and not scene.player.water_snapshot().registered and scene.player.interior_bounds==visit.room.interior_bounds and scene.player.is_on_floor())
	await _leave("pool_hotel")
	_check("street.original_world_and_water_state_restored",not visit.active and not scene.player.interior_active and not scene.player.water_snapshot().registered and _inventory()==original_inventory and original_inventory.size()==692,{"original_body_count":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var result:={"task":"ROOFTOP_SWIMMING","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"basin":basin_observation,"trials":swim_trials,"walks":walks,"placements":placements,"captures":captures,"deferred_checks":deferred_checks,"scope":"A fictional source-positioned hotel pool sits in a real opening between four authored deck panels. The authored deck is 1.55m higher than the normal clearance deck, water is 0.18m below it, and the 1.22m-deep basin floor remains above the retained source roof. Deck entry walking, jump descent, buoyancy, swimming and Space exit use production actions/move_and_slide, without per-step teleports or assigned flight velocity. Explicit scenario starts and invalid-transaction probes are labelled. Actual floor/rim shapes and effect meshes are observed; native images remain deferred in headless. Lift transactions and original692-body inventory are preserved. No real pool, public venue access, realistic fluid simulation, whole-map swimming or performance/export acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save swimming report")
	print("ROOFTOP_SWIMMING_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

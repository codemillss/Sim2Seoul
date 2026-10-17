extends "res://../tests/game/check_rooftop_swimming.gd"
## Retains physical deck/jump/float/Space-exit/lift regression,
## and observes actual larger water, open sky, swim distance and camera poses.

func _observe_raised_basin() -> void:
	super._observe_raised_basin()
	for path: String in ["res://../tests/game/check_large_outdoor_pool.gd","res://scripts/exploration_rooftop_access.gd"]:
		source_hashes[path]=FileAccess.get_sha256(path)
	var region: Dictionary=roof.pool_water_region()
	var dimensions: Dictionary=roof.pool_dimensions()
	var actual: Rect2=region.rect
	var water_mesh: MeshInstance3D=roof.get_node("PoolWaterSurface")
	var floor_mesh: MeshInstance3D=roof.get_node("PoolSafetyFloor")
	var water_shape: BoxMesh=water_mesh.mesh as BoxMesh
	var floor_shape: BoxMesh=floor_mesh.mesh as BoxMesh
	_check("large_pool.real_water_and_basin_support_24_by_10_metres",is_equal_approx(actual.size.x,24.0) and is_equal_approx(actual.size.y,10.0) and actual.get_area()>=239.99 and water_shape.size.x>=actual.size.x and water_shape.size.z>=actual.size.y and floor_shape.size.x>=actual.size.x and floor_shape.size.z>=actual.size.y,{"water_rect":actual,"water_mesh_size":water_shape.size,"floor_mesh_size":floor_shape.size,"dimensions":dimensions})
	var sky_queries: Array=[];var blocked: int=0
	for u: float in [.15,.50,.85]:
		for v: float in [.15,.50,.85]:
			var local: Vector3=Vector3(lerpf(actual.position.x,actual.end.x,u),float(region.surface_y)+.15,lerpf(actual.position.y,actual.end.y,v))
			var start: Vector3=region.frame*local
			var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,start+Vector3.UP*200.,1,[scene.player.get_rid()]))
			if not hit.is_empty():blocked+=1
			sky_queries.append({"world":start,"blocked":not hit.is_empty(),"collider":str(hit.get("collider",""))})
	_check("large_pool.actual_water_has_open_sky_at_nine_interior_points",blocked==0,{"queries":sky_queries})
	var hotel_rows: Array=[];var hotel_errors: Array=[];var expected_hotels: int=0
	var helper: Node3D=scene.get_node_or_null("ExplorationRooftopAccess")
	if is_instance_valid(helper):
		for building: Dictionary in visit.catalog:
			var title: String=String(building.title)
			if not title.contains("호텔") and not title.to_lower().contains("hotel"):continue
			expected_hotels+=1
			var hotel_roof: Node3D=helper.ensure_rooftop(String(building.id))
			if not is_instance_valid(hotel_roof):hotel_errors.append({"id":building.id,"kind":"missing_roof"});continue
			var water: Dictionary=hotel_roof.pool_water_region()
			var size: Dictionary=hotel_roof.pool_dimensions()
			var water_rect: Rect2=water.get("rect",Rect2())
			var deck_panel_count: int=0
			for body: StaticBody3D in hotel_roof.bodies:
				if not "DeckFloor" in String(body.get_meta("geometry_id","")):continue
				deck_panel_count+=1
				for collision: Node in body.get_children():
					if not collision is CollisionShape3D or not collision.shape is BoxShape3D:continue
					var floor_size: Vector3=collision.shape.size
					var footprint: Rect2=Rect2(Vector2(body.position.x,body.position.z)-Vector2(floor_size.x,floor_size.z)*.5,Vector2(floor_size.x,floor_size.z))
					if footprint.intersection(water_rect).has_area():hotel_errors.append({"id":building.id,"kind":"deck_panel_covers_water","floor_footprint":footprint})
			if deck_panel_count!=4:hotel_errors.append({"id":building.id,"kind":"expected_four_real_deck_surround_panels","count":deck_panel_count})
			if absf(float(size.get("water_depth_m",0.0))-1.22)>.001:hotel_errors.append({"id":building.id,"kind":"wrong_sunken_depth","dimensions":size})
			if water_rect.size.x<6.0 or water_rect.size.y<6.0 or maxf(water_rect.size.x,water_rect.size.y)<12.0 or not hotel_roof.walkable_rect.encloses(water_rect.grow(.2)):
				hotel_errors.append({"id":building.id,"kind":"undersize_or_outside_roof","water":water_rect})
			hotel_rows.append({"id":building.id,"title":title,"water_rect":water_rect,"pool_dimensions":size,"source_height":building.source_height,"deck_height":hotel_roof.deck_height_y})
	_check("large_pool.all_catalog_hotel_water_rectangles_are_real_12_by_6_minimum",hotel_rows.size()==expected_hotels and expected_hotels>=8 and hotel_errors.is_empty(),{"hotels":hotel_rows,"expected_catalog_hotels":expected_hotels,"errors":hotel_errors})
	var required: Array[String]=["SunLounger","ParasolCanopy","PoolLoungeDeck","PoolAccessHandrail","PoolSubmergedRampBody","PoolSubmergedHandrail","PoolLaneTile","OutdoorShowerColumn","TowelStand","FoldedPoolTowel","HotelPoolEntranceFascia","PoolLifeRing"]
	var missing: Array[String]=[]
	for title: String in required:
		if roof.get_node_or_null(NodePath(title))==null:missing.append(title)
	_check("large_pool.actual_outdoor_deck_furniture_steps_and_handrails",missing.is_empty(),{"required":required,"missing":missing})

func _swim_to(title: String,target: Vector3) -> bool:
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	var wet_ticks: int=0;var ticks: int=0;var max_speed: float=0.;var reached: bool=false
	for tick in range(1000):
		var offset: Vector3=Vector3(target.x-scene.player.global_position.x,0.,target.z-scene.player.global_position.z)
		if offset.length()<.18:reached=true;break
		_world_keys(offset.normalized());await _ticks(1);ticks+=1
		if scene.player.is_swimming():wet_ticks+=1
		max_speed=maxf(max_speed,Vector2(scene.player.velocity.x,scene.player.velocity.z).length())
		if scene.player.recoveries!=recoveries:break
	_movement();await _ticks(3)
	var row: Dictionary={"start":start,"end":scene.player.global_position,"target":target,"distance_m":Vector2(scene.player.global_position.x-start.x,scene.player.global_position.z-start.z).length(),"ticks":ticks,"wet_ticks":wet_ticks,"max_speed_mps":max_speed,"recoveries":scene.player.recoveries-recoveries,"kind":"continuous_production_Input_and_move_and_slide_no_swim_teleports"}
	swim_trials.append(row)
	_check(title,reached and wet_ticks>=ticks-2 and max_speed<=3.02 and scene.player.recoveries==recoveries,row)
	return reached

func _float_and_swim() -> void:
	await super._float_and_swim()
	var region: Dictionary=roof.pool_water_region()
	var rect: Rect2=region.rect
	var center: Vector2=rect.get_center()
	var first: Vector3=region.frame*Vector3(rect.position.x+1.0,float(region.surface_y)-1.0,center.y)
	var last: Vector3=region.frame*Vector3(rect.end.x-1.0,float(region.surface_y)-1.0,center.y)
	if await _swim_to("large_pool.swim_to_clear_lane_start",first):
		var before: Vector3=scene.player.global_position
		if await _swim_to("large_pool.real_twenty_two_metre_swim_across_water",last):
			var travelled: float=Vector2(scene.player.global_position.x-before.x,scene.player.global_position.z-before.z).length()
			_check("large_pool.actual_single_swim_traverses_over_twenty_metres",travelled>21.5,{"distance_m":travelled,"water_dimensions":roof.pool_dimensions()})
	await _swim_to("large_pool.return_to_center_for_edge_exit",region.frame*Vector3(center.x,float(region.surface_y)-1.0,center.y))
	await _upper_camera()
	await _capture_pool("large_open_sky_swimming_pool")

func _capture_pool(title: String) -> void:
	if title=="Space_exit_back_on_deck" or title=="Space_exit_right_back_on_deck":
		await _capture_normal_exit_camera(title)
		return
	if _testing_right_exit:return
	await super._capture_pool(title)

var _testing_right_exit: bool=false

func _capture_normal_exit_camera(title: String) -> void:
	# Preserve the player's pre-exit yaw/pitch/zoom. No photograph-only orbit,
	# no visibility assignment, and no camera collision-mask change is allowed.
	var view_before: Vector3=Vector3(scene.rig.yaw,scene.rig.pitch,scene.rig.requested_distance)
	var first_distance: float=scene.rig.current_distance
	var hidden_ticks: int=0
	for tick: int in range(30):
		await _ticks(1)
		if not scene.player.get_node("Visual").is_visible_in_tree():hidden_ticks+=1
	var visual: Node3D=scene.player.get_node("Visual")
	var visible_meshes: int=0
	for drawable: Node in _descendants(visual):
		if drawable is MeshInstance3D and drawable.is_visible_in_tree():visible_meshes+=1
	var camera_distance: float=scene.rig.current_distance
	var head: Vector3=scene.player.global_position+Vector3.UP*1.62
	var head_ray: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(scene.rig.camera.global_position,head,scene.rig.arm.collision_mask,[scene.player.get_rid()]))
	var head_pixel: Vector2=scene.rig.camera.unproject_position(head)
	var head_in_frame: bool=not scene.rig.camera.is_position_behind(head) and scene.get_viewport().get_visible_rect().has_point(head_pixel)
	var low_pivot: Vector3=scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m
	var old_ray: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(low_pivot,low_pivot+scene.rig.global_basis.z*scene.rig.requested_distance,scene.rig.arm.collision_mask,[scene.player.get_rid()]))
	var old_body: Object=old_ray.get("collider")
	var old_geometry: String=String(old_body.get_meta("geometry_id","")) if is_instance_valid(old_body) else ""
	var evidence: Dictionary={"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"camera_state":scene.rig.snapshot(),"normal_view_before":view_before,"normal_view_after":Vector3(scene.rig.yaw,scene.rig.pitch,scene.rig.requested_distance),"first_distance_m":first_distance,"settled_distance_m":camera_distance,"settle_physics_ticks":30,"hidden_ticks_during_settle":hidden_ticks,"visual_visible":visual.is_visible_in_tree(),"visible_avatar_meshes":visible_meshes,"head_in_frame":head_in_frame,"head_pixel":head_pixel,"head_ray_clear":head_ray.is_empty(),"unraised_pivot_obstruction_geometry_id":old_geometry,"camera_overlap_clear":_camera_clear(),"kind":"unchanged_production_camera_view_after_real_Space_exit_no_avatar_or_collision_override"}
	_check("camera."+title+".normal_view_keeps_visible_avatar_and_over_one_metre",camera_distance>1.0 and visual.is_visible_in_tree() and visible_meshes>0 and head_in_frame and head_ray.is_empty() and _camera_clear() and Vector3(scene.rig.yaw,scene.rig.pitch,scene.rig.requested_distance).is_equal_approx(view_before),evidence)
	if DisplayServer.get_name()=="headless":deferred_checks.append({"name":"capture."+title,"reason":"headless_has_no_rendered_viewport"});return
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path: String=report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row: Dictionary={"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"player":scene.player.global_position,"camera":scene.rig.camera.global_transform,"water":scene.player.water_snapshot(),"effects":roof.water_effects.snapshot(),"normal_camera_evidence":evidence}
	captures.append(row);_check("capture."+title,saved,row)

func _exit_water() -> void:
	await super._exit_water()
	await _right_side_exit()

func _right_side_exit() -> void:
	var region: Dictionary=roof.pool_water_region()
	var rect: Rect2=region.rect
	var local: Vector3=region.frame.affine_inverse()*scene.player.global_position
	var around_front_z: float=rect.end.y+4.44
	var entry: Vector3=roof.pool_entry_point()
	var path: Array[Vector3]=[region.frame*Vector3(local.x,.08,around_front_z),region.frame*Vector3((region.frame.affine_inverse()*entry).x,.08,around_front_z),entry]
	if not await _walk_path("pool.right_exit_walks_open_deck_back_to_entry",path):return
	_testing_right_exit=true
	if not await _walk_down_pool_steps():_testing_right_exit=false;return
	var shore: Vector3=region.frame*Vector3(rect.end.x-.58,float(region.surface_y)-1.0,rect.get_center().y)
	if not await _swim_to("pool.right_exit_swims_to_opposite_shore",shore):_testing_right_exit=false;return
	var recoveries: int=scene.player.recoveries
	var before: Dictionary=scene.player.water_snapshot()
	var outward: Vector3=region.frame.basis.x
	# A normal mouse orbit to face the impending movement direction happens
	# before Space, then remains unchanged through landing and the screenshot.
	scene.rig.yaw=atan2(-outward.x,-outward.z);scene.rig.pitch=deg_to_rad(-20.);scene.rig.requested_distance=4.;scene.rig.snap_to_target_pose()
	_world_keys(outward);Input.action_press("jump")
	var peak: float=scene.player.global_position.y
	var dry_grounded: bool=false
	var outside: bool=false
	for tick: int in range(300):
		await _ticks(1);peak=maxf(peak,scene.player.global_position.y)
		local=region.frame.affine_inverse()*scene.player.global_position
		outside=local.x>rect.end.x+.85
		if outside:_movement(["jump"])
		if outside and not scene.player.is_swimming() and scene.player.is_on_floor() and absf(scene.player.global_position.y-float(basin_observation.deck_bounds.end.y))<.15:dry_grounded=true;break
	var after: Dictionary=scene.player.water_snapshot()
	_check("water.opposite_side_Space_exits_real_rim_and_lands_on_clear_deck",dry_grounded and peak>float(basin_observation.rim_top_world_y)+.25 and int(after.water_jump_count)==int(before.water_jump_count)+1 and scene.player.recoveries==recoveries,{"before":before,"after":after,"position":scene.player.global_position,"peak_world_y":peak,"outside_pool":outside})
	await _capture_pool("Space_exit_right_back_on_deck")
	_movement(["jump"]);await _ticks(15);_movement();_testing_right_exit=false

func _walk_down_pool_steps() -> bool:
	if not await _walk_path("pool.real_walk_from_entry_to_flush_step_threshold",[roof.pool_rim_point()]):return false
	var start: Vector3=scene.player.global_position
	var before: Dictionary=scene.player.water_snapshot()
	var recoveries: int=scene.player.recoveries
	var region: Dictionary=roof.pool_water_region()
	var bottom: Vector3=roof.pool_steps_bottom_point()
	var grounded_ticks: int=0
	var wet_ticks: int=0
	var reached: bool=false
	for tick: int in range(480):
		var offset: Vector3=Vector3(bottom.x-scene.player.global_position.x,0.,bottom.z-scene.player.global_position.z)
		if offset.length()<.22 and scene.player.is_swimming():reached=true;break
		_world_keys(offset.normalized());await _ticks(1)
		if scene.player.is_on_floor():grounded_ticks+=1
		if scene.player.is_swimming():wet_ticks+=1
		if scene.player.recoveries!=recoveries:break
	_movement();await _ticks(6)
	var after: Dictionary=scene.player.water_snapshot()
	_check("pool.walks_down_real_sunken_steps_into_swimming_without_Space_or_teleport",reached and grounded_ticks>4 and wet_ticks>5 and start.y-scene.player.global_position.y>.55 and int(after.water_jump_count)==int(before.water_jump_count) and scene.player.recoveries==recoveries,{"start":start,"end":scene.player.global_position,"grounded_ticks":grounded_ticks,"wet_ticks":wet_ticks,"before":before,"after":after,"kind":"production_movement_down_real_support_slope_no_jump_no_relocation"})
	return reached

func _jump_into_pool() -> bool:
	if not _testing_right_exit:
		# Record the actual arrival view before moving to the pool entry. This
		# shows the hotel deck and sunken water together from normal play.
		await _capture_normal_exit_camera("hotel_pool_normal_arrival")
	return await super._jump_into_pool()

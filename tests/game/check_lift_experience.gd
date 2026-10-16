extends "res://../tests/game/check_building_visits.gd"
## Actual production phase/controller, door meshes, camera and floor-label checks.
const OFFICE_ID := "osm:way:332565592:building"
var lift_traces: Array = []
var deferred_checks: Array = []
var selector_layouts: Array = []

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Vector2i:return [value.x,value.y]
	if value is Rect2:return {"position":_json(value.position),"size":_json(value.size)}
	if value is AABB:return {"position":_json(value.position),"size":_json(value.size)}
	if value is Transform3D:return {"origin":_json(value.origin),"basis":[_json(value.basis.x),_json(value.basis.y),_json(value.basis.z)]}
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_json(item))
		return result
	return value

func _contains_rect(outer: Rect2,inner: Rect2,tolerance := 1.) -> bool:
	return outer.grow(tolerance).encloses(inner)

func _gui_key(keycode: int,shift := false) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=keycode;event.physical_keycode=keycode;event.shift_pressed=shift;event.pressed=pressed
		Input.parse_input_event(event)

func _selector_layout_checks() -> void:
	var previous_size: Vector2i=root.size
	var previous_scale: Vector2i=root.content_scale_size
	var previous_mode: int=root.content_scale_mode
	_e(true);_e(false);await _ticks(4)
	_check("selector.28_floor_fixture_has_29_actual_destinations",visit.elevator_open and visit.room.floor_count==28 and visit.elevator_floors.get_child_count()==29)
	if not visit.elevator_open:return
	for size: Vector2i in [Vector2i(1152,720),Vector2i(640,480)]:
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=size
		await _ticks(8)
		var view:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
		var panel: Rect2=visit.elevator_panel.get_global_rect()
		var scroll: Rect2=visit.elevator_scroll.get_global_rect()
		var grid: Rect2=visit.elevator_floors.get_global_rect()
		var close: Rect2=visit.elevator_close_button.get_global_rect()
		var errors:=[];var buttons:=[]
		var horizontal_limit: float=scroll.end.x-(visit.elevator_scroll.get_v_scroll_bar().size.x if visit.elevator_scroll.get_v_scroll_bar().visible else 0.)
		for index in range(visit.destination_count()):
			var button: Button=visit.elevator_floors.get_child(index)
			var rect: Rect2=button.get_global_rect()
			if not _contains_rect(grid,rect):errors.append({"index":index,"kind":"button_outside_grid","rect":rect})
			if rect.position.x<scroll.position.x-1. or rect.end.x>horizontal_limit+1.:errors.append({"index":index,"kind":"button_horizontal_overflow","rect":rect})
			buttons.append({"index":index,"text":button.text,"rect":rect,"disabled":button.disabled})
		var evidence:={"requested_viewport":size,"viewport":view,"panel":panel,"scroll_clip":scroll,"grid_content":grid,"close_button":close,"clip_contents":visit.elevator_scroll.clip_contents,"follow_focus":visit.elevator_scroll.follow_focus,"columns":visit.elevator_floors.columns,"buttons":buttons,"errors":errors}
		_check("selector."+str(size.x)+"x"+str(size.y)+".panel_clip_footer_and_button_widths_fit",_contains_rect(view,panel) and _contains_rect(panel,scroll) and _contains_rect(panel,close) and visit.elevator_scroll.clip_contents and visit.elevator_scroll.follow_focus and errors.is_empty(),evidence)
		_check("selector."+str(size.x)+"x"+str(size.y)+".indoor_guide_hidden_behind_open_picker",not visit.indoor_panel.is_visible_in_tree(),{"picker_visible":visit.elevator_panel.is_visible_in_tree(),"indoor_guide_visible":visit.indoor_panel.is_visible_in_tree()})
		var last_floor: Button=visit.elevator_floors.get_child(27)
		var roof: Button=visit.elevator_floors.get_child(28)
		_check("selector."+str(size.x)+"x"+str(size.y)+".last_floor_and_roof_enabled_and_named",last_floor.text.get_slice("\n",0)=="28층" and roof.text=="옥상" and not last_floor.disabled and not roof.disabled)
		var programme_errors:=[]
		for index in range(visit.room.floor_count):
			var button: Button=visit.elevator_floors.get_child(index)
			var title: String=String(visit.room.detail_kit.level_profiles[index].title)
			if button.text.get_slice("\n",1)!=title.get_slice(" · ",0) or button.tooltip_text!=title:programme_errors.append(index)
		_check("selector."+str(size.x)+"x"+str(size.y)+".actual_floor_uses_visible_on_all_buttons",programme_errors.is_empty(),{"floors":visit.room.floor_count,"errors":programme_errors})
		# Real keyboard focus travels backwards from the close action into the
		# last destinations. follow_focus must reveal the focused clipped row.
		visit.elevator_close_button.grab_focus();await _ticks(2)
		_gui_key(KEY_TAB,true);await _ticks(4)
		var focus: Control=scene.get_viewport().gui_get_focus_owner()
		var roof_rect: Rect2=roof.get_global_rect()
		_check("selector."+str(size.x)+"x"+str(size.y)+".keyboard_focus_scrolls_roof_into_clip",focus==roof and _contains_rect(scroll,roof_rect) and _contains_rect(view,roof_rect),{"focus":String(focus.name) if is_instance_valid(focus) else "none","roof_rect":roof_rect,"scroll_clip":scroll,"scroll_y":visit.elevator_scroll.scroll_vertical})
		_gui_key(KEY_TAB,true);await _ticks(4)
		focus=scene.get_viewport().gui_get_focus_owner()
		var last_rect: Rect2=last_floor.get_global_rect()
		_check("selector."+str(size.x)+"x"+str(size.y)+".keyboard_focus_scrolls_28th_floor_into_clip",focus==last_floor and _contains_rect(scroll,last_rect) and _contains_rect(view,last_rect),{"focus":String(focus.name) if is_instance_valid(focus) else "none","floor_rect":last_rect,"scroll_clip":scroll,"scroll_y":visit.elevator_scroll.scroll_vertical})
		selector_layouts.append(evidence)
		await _capture_lift("office_selector_"+str(size.x)+"x"+str(size.y)+"_last_destinations")
	root.size=previous_size;root.content_scale_size=previous_scale;root.content_scale_mode=previous_mode
	await _ticks(8)
	_check("selector.original_native_viewport_and_scale_restored",root.size==previous_size and root.content_scale_size==previous_scale and root.content_scale_mode==previous_mode,{"size":root.size,"content_scale_size":root.content_scale_size,"content_scale_mode":root.content_scale_mode})

func _label_bounds(label: Label3D) -> AABB:
	var bounds: AABB=label.get_aabb()
	if bounds.size.length_squared()>.00000001:return label.transform*bounds
	# Label3D's generated glyph triangles also work without GPU readback.
	var triangles: TriangleMesh=label.generate_triangle_mesh()
	if triangles==null:return AABB()
	var faces: PackedVector3Array=triangles.get_faces()
	if faces.is_empty():return AABB()
	bounds=AABB(faces[0],Vector3.ZERO)
	for point: Vector3 in faces:bounds=bounds.expand(point)
	return label.transform*bounds

func _cabin_panel_bounds_check() -> void:
	await _ticks(2)
	var panel: MeshInstance3D=visit.cabin.get_node("CabinOperatingPanel")
	var bounds: AABB=panel.transform*panel.mesh.get_aabb()
	var plane:=Rect2(Vector2(bounds.position.z,bounds.position.y),Vector2(bounds.size.z,bounds.size.y))
	var rows: Array=visit.cabin.get("_floor_buttons")
	var errors:=[];var observed:=[];var label_geometry:=0
	for index in range(rows.size()):
		var mesh: MeshInstance3D=rows[index].mesh
		var button: AABB=mesh.transform*mesh.mesh.get_aabb()
		var label: Label3D=rows[index].label
		var text: AABB=_label_bounds(label)
		var button_plane:=Rect2(Vector2(button.position.z,button.position.y),Vector2(button.size.z,button.size.y))
		var text_plane:=Rect2(Vector2(text.position.z,text.position.y),Vector2(text.size.z,text.size.y))
		if text.size.length_squared()>.00000001:label_geometry+=1
		if not _contains_rect(plane,button_plane,.0001):errors.append({"index":index,"kind":"physical_button_outside_operating_panel","bounds":button})
		if not _contains_rect(plane,text_plane,.0001):errors.append({"index":index,"kind":"glyph_outside_operating_panel","bounds":text})
		observed.append({"index":index,"text":label.text,"button_bounds":button,"glyph_bounds":text})
	var evidence:={"actual_panel_bounds":bounds,"panel_YZ":plane,"actual_buttons":rows.size(),"actual_label_geometry":label_geometry,"rows":observed,"errors":errors,"bounds_method":"actual BoxMesh AABB and Label3D glyph geometry transformed into cabin-local YZ; panel-normal X is excluded because buttons sit on its face"}
	selector_layouts.append(evidence)
	_check("cabin.29_button_meshes_and_glyphs_fit_actual_operating_panel",rows.size()==29 and label_geometry==29 and errors.is_empty(),evidence)
	_check("cabin.last_28_and_roof_button_glyphs_present",rows.size()==29 and rows[27].label.text=="28" and rows[28].label.text=="R",{"last_floor":rows[27].label.text if rows.size()>27 else "missing","roof":rows[28].label.text if rows.size()>28 else "missing"})
	var rail_bounds:=[];var rail_errors:=[]
	for child in visit.cabin.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("CabinHandrail") and child.position.x>0.:
			var box: AABB=child.transform*child.mesh.get_aabb()
			var rail_plane:=Rect2(Vector2(box.position.z,box.position.y),Vector2(box.size.z,box.size.y))
			rail_bounds.append({"name":String(child.name),"bounds":box,"YZ":rail_plane})
			if plane.intersects(rail_plane,true):rail_errors.append(String(child.name))
	_check("cabin.actual_right_handrail_sections_do_not_cross_operating_panel",rail_bounds.size()>=2 and rail_errors.is_empty(),{"panel_YZ":plane,"actual_rails":rail_bounds,"overlaps":rail_errors})
	await _capture_lift("office_cabin_29_buttons_within_operating_panel")

func _cabin_observation() -> Dictionary:
	var state: Dictionary=visit.elevator_snapshot()
	var observed_door: float=(visit.cabin.door_right.position.x-visit.cabin.door_left.position.x-1.08)/2.24
	var sphere:=SphereShape3D.new();sphere.radius=.13
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.collision_mask=1
	query.transform=Transform3D(Basis.IDENTITY,visit.cabin.camera.global_position);query.exclude=[scene.player.get_rid()]
	var overlaps: Array=scene.get_world_3d().direct_space_state.intersect_shape(query,1)
	return {"state":state,"door_fraction_from_actual_mesh_positions":observed_door,"left_door_x":visit.cabin.door_left.position.x,"right_door_x":visit.cabin.door_right.position.x,"floor_text":visit.cabin.floor_label.text,"status_text":visit.cabin.stage_label.text,"route_text":visit.cabin.status_label.text,"travel_band_scale_x":visit.cabin.floor_band.scale.x,"travel_band_x":visit.cabin.floor_band.position.x,"camera":visit.cabin.camera.global_transform,"actual_current_camera_is_cabin":scene.get_viewport().get_camera_3d()==visit.cabin.camera,"camera_overlap_count":overlaps.size(),"player":scene.player.global_position,"passenger_physics_enabled":scene.player.is_physics_processing(),"avatar_visible":scene.player.get_node("Visual").visible,"gameplay_enabled":scene.input_router.gameplay_enabled,"rig_processing":scene.rig.is_processing(),"rig_physics":scene.rig.is_physics_processing()}

func _capture_lift(title: String) -> void:
	if DisplayServer.get_name()=="headless":
		deferred_checks.append({"name":"capture."+title,"reason":"headless_has_no_rendered_viewport"});return
	await process_frame;RenderingServer.force_draw(false,0.)
	var picture: Image=scene.get_viewport().get_texture().get_image()
	var path:=report_path.trim_suffix(".json")+"_"+title+".png"
	var good: bool=not picture.is_empty() and picture.save_png(path)==OK
	var row:={"name":title,"captured":good,"path":path,"width":picture.get_width(),"height":picture.get_height(),"current_camera":String(scene.get_viewport().get_camera_3d().name),"visit":visit.snapshot(),"cabin":visit.cabin.snapshot()}
	captures.append(row);_check("capture."+title,good,row)

func _pause_observed_cabin() -> void:
	var before:=_cabin_observation()
	scene.toggle_menu();await _ticks(18)
	var after:=_cabin_observation()
	var stopped: bool=before.state.elapsed==after.state.elapsed and before.state.phase==after.state.phase and before.left_door_x==after.left_door_x and before.right_door_x==after.right_door_x and before.travel_band_scale_x==after.travel_band_scale_x and before.player==after.player and before.camera==after.camera
	_check("menu.real_cabin_doors_clock_band_camera_and_passenger_pause",paused and stopped,{"before":before,"after":after})
	_check("menu.pause_ui_above_cabin_status_and_resume_focused",scene.menu.visible and scene.menu.get_index()>visit.ride_panel.get_index() and scene.get_viewport().gui_get_focus_owner()==scene.resume_action)
	scene.toggle_menu();await _ticks(1)
	_check("menu.resume_continues_same_ride_without_extra_request",visit.in_elevator and visit.elevator_snapshot().elapsed>float(before.state.elapsed) and not visit.request_floor(0))

func _observe_ride(title: String,target: int,capture := false,block_target_midride := false,via_selector := false) -> Dictionary:
	var from: int=visit.room.floor_index_at(scene.player.global_position)
	var outside_before: Vector3=scene.player.global_position
	var accepted:=false
	if via_selector:
		if not visit.elevator_open:_e(true);_e(false);await _ticks(4)
		visit._focus_elevator_floor(target);await _ticks(4)
		var focused: Control=scene.get_viewport().gui_get_focus_owner()
		_gui_key(KEY_ENTER);await _ticks(1)
		accepted=visit.in_elevator and visit.selected_floor==target
		_check(title+".real_keyboard_activates_focused_last_destination",accepted and focused==visit.elevator_floors.get_child(target),{"target":target,"selected":visit.selected_floor})
	else:accepted=visit.request_floor(target)
	_check(title+".request_accepted",accepted and visit.in_elevator,{"from":from,"to":target})
	if not accepted:return {}
	var first:=_cabin_observation()
	_check(title+".actual_3d_camera_owns_fixed_hidden_passenger",first.actual_current_camera_is_cabin and visit.cabin.visible and not first.passenger_physics_enabled and not first.avatar_visible and not first.gameplay_enabled and not first.rig_processing and not first.rig_physics and visit.cabin.cabin_bounds.has_point(scene.player.global_position),first)
	_check(title+".held_movement_jump_and_E_cannot_replace_ride",not visit.request_floor(from) and scene.player.air_jumps_remaining()==1)
	if String(visit.current_spec.id)==OFFICE_ID and from==0:await _cabin_panel_bounds_check()
	_movement(["move_forward","jump"]);_e(true)
	var records:=[];var phases:=[];var errors:=[];var prior:=first
	var paused_once:=false;var saved_closing:=false;var saved_motion:=false;var saved_opening:=false
	var obstacle: StaticBody3D
	var max_derivative_error:=0.;var max_speed:=0.;var min_speed:=INF;var logical_distance:=0.;var labels:={};var returning_seen:=false
	for tick in range(3000):
		if not visit.in_elevator:break
		await _ticks(1)
		if not visit.in_elevator:break
		var observed:=_cabin_observation()
		var state: Dictionary=observed.state
		var phase:=String(state.phase)
		if phases.is_empty() or phases.back()!=phase:phases.append(phase)
		labels[String(observed.floor_text)]=true
		var dt: float=float(state.elapsed)-float(prior.state.elapsed)
		var df: float=float(state.current_floor_value)-float(prior.state.current_floor_value)
		logical_distance+=absf(df)*float(visit.current_spec.floor_height)
		if not visit.cabin.cabin_bounds.has_point(scene.player.global_position) or scene.player.global_position.distance_to(first.player)>.001:errors.append("passenger_left_fixed_cabin")
		if observed.passenger_physics_enabled or observed.gameplay_enabled or observed.avatar_visible or not observed.actual_current_camera_is_cabin or observed.rig_processing or observed.rig_physics:errors.append("ride_control_ownership")
		if observed.camera_overlap_count!=0:errors.append("cabin_camera_inside_solid")
		if absf(float(observed.door_fraction_from_actual_mesh_positions)-float(state.door_open_fraction))>.0001:errors.append("door_mesh_disagrees_with_state")
		var expected_label: String="옥상" if int(round(float(state.current_floor_value)))==visit.destination_count()-1 else "%02d"%(int(round(float(state.current_floor_value)))+1)
		if expected_label not in String(observed.floor_text):errors.append("actual_floor_label_disagrees")
		if phase in ["accelerating","cruising","decelerating"]:
			if float(observed.door_fraction_from_actual_mesh_positions)>.001:errors.append("doors_open_during_motion")
			max_speed=maxf(max_speed,float(state.speed_mps));min_speed=minf(min_speed,float(state.speed_mps))
			if dt>0. and String(prior.state.phase) in ["accelerating","cruising","decelerating"] and absf(float(state.motion_start_floor)-float(prior.state.motion_start_floor))<.001:
				var derivative: float=absf(df)*float(visit.current_spec.floor_height)/dt
				var expected_mean: float=(float(state.speed_mps)+float(prior.state.speed_mps))*.5
				max_derivative_error=maxf(max_derivative_error,absf(derivative-expected_mean))
				if absf(derivative-expected_mean)>.08:errors.append("logical_floor_derivative_disagrees_with_speed")
		if phase=="closing" and String(prior.state.phase)==phase and float(observed.door_fraction_from_actual_mesh_positions)>float(prior.door_fraction_from_actual_mesh_positions)+.001:errors.append("closing_mesh_reversed")
		if phase=="opening" and String(prior.state.phase)==phase and float(observed.door_fraction_from_actual_mesh_positions)<float(prior.door_fraction_from_actual_mesh_positions)-.001:errors.append("opening_mesh_reversed")
		if phase in ["boarding","closing"] and absf(float(state.current_floor_value)-float(from))>.001:errors.append("floor_motion_before_doors_closed")
		if bool(state.returning_to_safe_floor):returning_seen=true
		if block_target_midride and not is_instance_valid(obstacle) and phase=="accelerating" and float(state.motion_elapsed)>.3:
			obstacle=_blocker("LiftExperienceMidrideLandingObstruction",visit.landing_point(target));await _ticks(2)
		if capture and not saved_closing and phase=="closing" and float(state.phase_elapsed)>.3:saved_closing=true;await _capture_lift("doors_closing")
		if capture and not saved_motion and phase in ["accelerating","cruising","decelerating"] and float(state.motion_elapsed)>float(state.motion_duration)*.45:saved_motion=true;await _capture_lift("moving_floor_indicator")
		if capture and not saved_opening and phase=="opening" and float(state.phase_elapsed)>.4:saved_opening=true;await _capture_lift("doors_opening_at_arrival")
		if capture and not paused_once and phase=="accelerating" and float(state.motion_elapsed)>.35:paused_once=true;await _pause_observed_cabin()
		if tick%3==0 or phases.back()!=String(prior.state.phase):records.append(observed)
		prior=observed
	var arrived: bool=not visit.in_elevator and visit.active and scene.player.is_physics_processing() and scene.rig.is_processing() and scene.rig.is_physics_processing() and scene.get_viewport().get_camera_3d()==scene.rig.camera and not visit.cabin.visible
	var landing_valid: bool=scene.player._valid_spawn() and visit._indoor_target_clear(scene.player.global_position) and scene.player.input_latched
	var unique_errors:={}
	for error in errors:unique_errors[error]=int(unique_errors.get(error,0))+1
	var row:={"name":title,"from":from,"requested_target":target,"arrived_target":visit.selected_floor,"source_position_before_boarding":outside_before,"end_position":scene.player.global_position,"phases":phases,"observed_floor_labels":labels.keys(),"max_logical_derivative_error_mps":max_derivative_error,"max_speed_mps":max_speed,"minimum_motion_speed_mps":min_speed,"logical_distance_m":logical_distance,"returning_seen":returning_seen,"errors":unique_errors,"samples":records,"kind":"detached_cabin_fixed_passenger_and_distance_based_logical_motion"}
	lift_traces.append(row)
	_check(title+".actual_mesh_camera_phase_and_speed_consistency",unique_errors.is_empty() and max_speed>1. and phases.has("closing") and phases.has("accelerating") and phases.has("decelerating") and phases.has("arriving") and phases.has("opening") and phases.has("exit_hold"),row)
	_check(title+".safe_landing_releases_original_camera_and_requires_neutral",arrived and landing_valid,{"arrived":arrived,"landing_valid":landing_valid,"position":scene.player.global_position,"state":visit.snapshot()})
	if block_target_midride:_check(title+".closed_car_returns_to_safe_departure_before_opening",returning_seen and visit.selected_floor==from and logical_distance>float(visit.current_spec.floor_height)*1.8,row)
	else:_check(title+".selected_floor_reached_after_visible_arrival",visit.selected_floor==target and labels.size()>=2 and float(prior.state.door_open_fraction)>.99,row)
	if capture:await _capture_lift("restored_upper_floor_camera")
	if is_instance_valid(obstacle):obstacle.queue_free()
	_movement();_e(false);await _ticks(8)
	return row

func _run() -> void:
	for path in ["res://scripts/interior_visit.gd","res://scripts/elevator_cabin.gd","res://scripts/rooftop_space.gd","res://scripts/player/free_roam_player.gd","res://scripts/building_interior_space.gd","res://scripts/interior_detail_kit.gd","res://scripts/interior_surface.gdshader","res://assets/authored/interiors/source_catalog.json","res://../tests/game/check_building_visits.gd","res://../tests/game/check_lift_experience.gd"]:
		if FileAccess.file_exists(path):source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit=scene.interior_visit;await _ticks(25)
	original_inventory=_inventory()
	_check("startup.real_cabin_and_phase_API",visit.loaded and visit.has_method("elevator_snapshot") and visit.has_method("destination_count") and visit.has_method("landing_point") and is_instance_valid(visit.cabin.camera))
	var meshes:=0
	for child in visit.cabin.get_children():
		if child is MeshInstance3D:meshes+=1
	_check("cabin.actual_geometry_lights_and_depth_tested_labels",meshes>=20 and visit.cabin.bodies.size()>=6 and not visit.cabin.floor_label.no_depth_test and visit.cabin.get_node("CabinLight").light_energy>0.,{"actual_mesh_instances":meshes,"actual_static_supports":visit.cabin.bodies.size()})
	if await _enter(LIBRARY_ID,"library"):
		if await _pose("library_lift_call",visit.room.elevator_point(0)):
			_e(true);_e(false);await _ticks(4)
			_check("selector.actual_E_opens_all_destinations_including_roof",visit.elevator_open and visit.elevator_floors.get_child_count()==visit.destination_count() and visit.elevator_floors.get_child(visit.destination_count()-1).text=="옥상")
			await _observe_ride("short_up",1,true)
		if await _pose("library_lift_return",visit.room.elevator_point(1)):await _observe_ride("short_down",0)
		if await _pose("library_midride_obstruction",visit.room.elevator_point(0)):await _observe_ride("blocked_destination_return",1,false,true)
		await _leave("library")
	if not visit.active and await _enter(OFFICE_ID,"office"):
		if await _pose("long_distance_lift_call",visit.room.elevator_point(0)):
			await _selector_layout_checks()
			var trace:=await _observe_ride("long_distance_up",visit.room.floor_count-1,false,false,true)
			if not trace.is_empty():_check("long_distance.actual_cruise_between_acceleration_and_braking",trace.phases.has("cruising") and trace.max_speed_mps<=18.01 and trace.max_speed_mps>17.9,trace)
		if await _pose("office_roof_selector_call",visit.room.elevator_point(visit.room.floor_count-1)):
			await _observe_ride("office_roof_last_destination",visit.room.floor_count,false,false,true)
	_check("exterior.original_692_bodies_and_shapes_unchanged",original_inventory.size()==692 and _inventory()==original_inventory,{"original_body_count":original_inventory.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_movement();_e(false);paused=false
	var failed:=0
	for check in checks:
		if not check.passed:failed+=1
	var result:={"task":"LIFT_EXPERIENCE","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"rides":lift_traces,"selector_layouts":selector_layouts,"placements":placements,"captures":captures,"deferred_checks":deferred_checks,"scope":"Full production scene with real physical E, GUI keyboard events and phase controller. 28-storey 2D selectors are measured at 1152x720 and 640x480; scroll clipping and focused last destination visibility are distinct from offscreen scroll content. Actual 3D button and glyph AABBs are projected into the operating panel YZ bounds. Doors are measured from actual MeshInstance3D transforms; labels, active Camera3D, passenger bounds/control and finite differences of logical travel are independently observed. Passenger remains fixed inside a detached opaque car; logical floor progress is not physical travel through source slabs. Scenario starts and landing obstruction are explicit test-only fixtures. Headless defers native viewport captures; safety faults are also retained in check_building_visits. User settings and running native game are untouched. No human-input, whole-city route, surveyed shaft or performance/export acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json(result),"\t")+"\n");file.close()
	else:failed+=1;push_error("Cannot save lift experience report")
	print("LIFT_EXPERIENCE_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

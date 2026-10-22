extends SceneTree
## Uses the production menu shortcut and production mount camera without a
## test camera override. Pixel measurements bound framing, not visual quality.
var scene: Node3D
var service: Node3D
var checks: Array[Dictionary]=[]
var captures: Array[Dictionary]=[]
var report_path:="/tmp/sim2seoul-bike-visibility.json"
var finished:=false
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	for action: String in ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	create_timer(180.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_timeout",false);_finish()
	);_run.call_deferred()
func _ticks(count: int) -> void:
	for tick: int in range(count):await scene.rig.camera_stepped
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	return value
func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":ok,"evidence":_json(evidence)});print("BIKE_VIEW_CHECK ",title," ",ok)
func _frame_measure() -> Dictionary:
	var row: Dictionary=service.bikes[0];var camera: Camera3D=scene.rig.camera
	var first: Vector3=row.body.to_global(Vector3(0,.35,-.58));var last: Vector3=row.body.to_global(Vector3(0,.35,.58))
	var a:=camera.unproject_position(first);var b:=camera.unproject_position(last);var size:=root.get_visible_rect().size
	var bottom:=0.
	for z: float in [-.58,.58]:
		for step: int in range(16):
			var angle:=TAU*step/16.;var point: Vector3=row.body.to_global(Vector3(0,.35+sin(angle)*.357,z+cos(angle)*.357));bottom=maxf(bottom,camera.unproject_position(point).y/size.y)
	return {"front_wheel":a,"rear_wheel":b,"viewport":size,"wheel_separation_x_fraction":absf(a.x-b.x)/size.x,"wheel_bottom_y_fraction":bottom,"both_wheels_in_front":not camera.is_position_behind(first) and not camera.is_position_behind(last),"both_wheels_inside_view":Rect2(Vector2.ZERO,size).has_point(a) and Rect2(Vector2.ZERO,size).has_point(b),"camera_distance_m":scene.rig.current_distance,"camera_yaw":scene.rig.yaw,"camera_pivot_m":scene.rig.pivot_height_m,"body_yaw":row.yaw,"bike_scale":row.body.global_basis.get_scale()}
func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var path:=report_path.get_basename()+"_"+title+".png";var error:=image.save_png(path)
	_check("native_capture_"+title,error==OK)
	if error==OK:captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"frame":_frame_measure(),"scope":"Actual production shortcut or mount camera. Image opening/review is required separately."})
func _tap_e() -> void:
	var event:=InputEventAction.new();event.action="interact";event.pressed=true;event.device=42;Input.parse_input_event(event);await _ticks(3)
	event=InputEventAction.new();event.action="interact";event.pressed=false;event.device=42;Input.parse_input_event(event);await _ticks(6)
func _sign_native_clearance(station: Dictionary) -> Dictionary:
	var clear:=true;var parts: Array=[]
	# Query the actual upper sign meshes in their native global transforms.
	# Only the post's ground-contact portion is excluded from this upper test.
	for mesh: MeshInstance3D in [station.panel.get_node("StationHeader"),station.panel.get_node("StationInformation"),station.pictogram.get_node("IconBackground")]:
		var bounds:=mesh.mesh.get_aabb();var shape:=BoxShape3D.new();shape.size=bounds.size+Vector3(.01,.01,.01)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=mesh.global_transform.translated_local(bounds.get_center());query.collision_mask=1|32;query.margin=.002
		var hits:=scene.get_world_3d().direct_space_state.intersect_shape(query,4);clear=clear and hits.is_empty();parts.append({"name":mesh.name,"hits":hits.size(),"center":query.transform.origin,"size":shape.size})
	var envelope: bool=service._station_sign_clear(station.point,station.node.global_rotation.y)
	return {"clear":clear and envelope,"id":station.id,"upper_envelope_clear":envelope,"parts":parts}
func _finish() -> void:
	if finished:return
	finished=true
	var count:=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var hashes: Dictionary={}
	for path: String in ["res://scripts/city_bike_service.gd","res://scripts/explore_walk.gd","res://assets/authored/bike_service.json","res://../tests/game/check_bike_visibility.gd"]:hashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"production_bike_visibility","result":"PASS" if count==checks.size() else "FAIL","passed":count,"total":checks.size(),"checks":checks,"captures":captures,"source_hashes":hashes,"scope":"Production shortcut + E mount/dismount and numerical framing, meter scale, dock signage and source footprints. Native images require separate visual review; headless is not subjective visibility acceptance."}),"  "));file.close();print("BIKE_VIEW_RESULT ",count,"/",checks.size());quit(0 if count==checks.size() else 1)
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/bike-view-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(8)
	service=scene.get("city_bike_service")
	_check("production_setup",scene.runtime_ok and is_instance_valid(service) and service.loaded)
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	var expected: int=service.design.stations.size()
	_check("only_actual_rentable_bikes_no_fake_reserve_inventory",expected>=2 and service.bikes.size()==expected and service.stations.size()==expected)
	var marked:=0
	for station: Dictionary in service.stations:
		if station.node.has_node("StationBicyclePictogram") and station.panel.has_node("StationTitleFront") and station.panel.has_node("StationTitleBack") and station.pictogram.position.y>=2.8:marked+=1
	_check("all_docks_have_raised_pictogram_and_two_sided_signs",marked==expected)
	var signs_clear:=true;var sign_checks: Array=[]
	for station: Dictionary in service.stations:
		var result:=_sign_native_clearance(station);signs_clear=signs_clear and result.clear;sign_checks.append(result)
	_check("all_raised_signs_native_static_volumes_clear",signs_clear,{"signs":sign_checks,"collision_mask":1|32,"bike_own_layer_excluded":4})
	# A high blocker leaves the old low bike box clear; it must still reject
	# the sign envelope. This fixture is removed before the ordinary shortcut.
	var station: Dictionary=service.stations[0];var blocker:=StaticBody3D.new();blocker.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.20,.40,.20);shape.shape=box;blocker.add_child(shape);scene.add_child(blocker);blocker.global_position=station.node.to_global(Vector3(-.9,3.,.75));await _ticks(3)
	_check("high_static_fixture_rejects_upper_sign_envelope",not service._station_sign_clear(station.point,station.node.global_rotation.y));blocker.queue_free();await _ticks(3)
	scene._visit_street_detail("bike_station");await _ticks(8)
	var frame:=_frame_measure()
	_check("ordinary_shortcut_separates_wheels_within_view",frame.both_wheels_in_front and frame.both_wheels_inside_view and frame.wheel_separation_x_fraction>.045 and frame.camera_distance_m>2.8,frame)
	_check("ordinary_shortcut_in_E_reach_with_native_line_of_sight",service.can_interact(),{"prompt":service.prompt_text(),"bike_distance_m":scene.player.global_position.distance_to(service.bikes[0].body.global_position)})
	await _capture("production_shortcut")
	var walking_pivot: float=scene.rig.pivot_height_m
	await _tap_e();_check("ordinary_E_mount",service.riding)
	if service.riding:
		frame=_frame_measure()
		_check("production_mount_starts_in_three_quarter_view_with_separated_wheels",frame.both_wheels_in_front and frame.both_wheels_inside_view and frame.wheel_separation_x_fraction>.045 and absf(wrapf(float(frame.camera_yaw)-float(frame.body_yaw),-PI,PI))>.45,frame)
		_check("both_wheel_treads_fit_above_bottom_prompt_band",frame.wheel_bottom_y_fraction<.735,frame)
		_check("retained_meter_scale_and_source_footprint",service.bikes.all(func(row: Dictionary)->bool:return row.body.global_basis.get_scale().is_equal_approx(Vector3.ONE) and service._footprint_allowed(row.body.global_position,row.body.global_basis)))
		await _capture("production_mount")
		await _tap_e();await _ticks(8);_check("ordinary_E_return_restores_walking",not service.riding and scene.player.is_physics_processing() and not scene.player.facility_control and is_equal_approx(scene.rig.pivot_height_m,walking_pivot))
	_finish()

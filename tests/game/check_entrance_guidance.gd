extends SceneTree
## Production scene; each explicit scenario start is a test-only teleport.
## Projection uses the real camera and physical E taps use the production binding.
const LIBRARY_ID := "osm:relation:10757525:building"
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump","toggle_menu"]
var report_path := ""
var scene
var visit
var way
var checks: Array = []
var placements: Array = []
var observations: Array = []
var captures: Array = []
var source_hashes := {}
var deferred_checks: Array = []
var original_inventory := {}
var original_names := {}
var finished := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_entrance_guidance requires --report=<absolute path>");quit(1);return
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	# Setup must install the physical binding, never a test substitute.
	if InputMap.has_action("interact"):InputMap.erase_action("interact")
	Engine.physics_ticks_per_second = 60
	create_timer(120.,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json_value(evidence)})
	if not passed:push_warning("ENTRANCE_GUIDANCE_CHECK_FAIL "+title)

func _json_value(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2 or value is Vector2i:return [value.x,value.y]
	if value is Rect2:return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Transform3D:return {"origin":_json_value(value.origin),"basis":[_json_value(value.basis.x),_json_value(value.basis.y),_json_value(value.basis.z)]}
	if value is Dictionary:
		var result := {}
		for key in value:result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_json_value(item))
		return result
	return value

func _point(value: Variant) -> Vector3:
	if value is Vector3:return value
	if value is Array and value.size()>=3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.INF

func _rect(value: Variant) -> Rect2:
	if value is Rect2:return value
	if value is Array and value.size()==4:return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
	return Rect2(-1000,-1000,0,0)

func _keys() -> void:
	for action in ACTIONS:Input.action_release(action)

func _e(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E;event.keycode = KEY_E;event.pressed = pressed
	Input.parse_input_event(event)

func _ticks(count: int) -> void:
	for index in range(count):await physics_frame
	await process_frame

func _inventory() -> Dictionary:
	var result := {}
	for collection in [scene.city.bodies,scene.city.fragments]:
		for id in collection:
			var body: StaticBody3D = collection[id]
			var node: CollisionShape3D = body.get_node("CollisionShape")
			var shape: Shape3D = node.shape
			result[id] = {"node":body.get_instance_id(),"layer":body.collision_layer,"mask":body.collision_mask,"transform":str(body.transform),"shape":shape.get_instance_id(),"shape_transform":str(node.transform),"disabled":node.disabled,"faces":hash(shape.get_faces()) if shape is ConcavePolygonShape3D else 0}
	return result

func _name_inventory() -> Dictionary:
	var result := {}
	for row: Dictionary in scene.building_names.markers:result[row.id] = {"node":row.node.get_instance_id(),"text":row.node.text,"position":str(row.node.position)}
	return result

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child);result.append_array(_descendants(child))
	return result

func _visible_signs() -> int:
	var result := 0
	for marker: Dictionary in way.markers:
		if marker.sign.is_visible_in_tree():result += 1
	return result

func _visible_ground_labels() -> int:
	var result := 0
	for marker: Dictionary in way.markers:
		if marker.ground.is_visible_in_tree():result += 1
	return result

func _pose(title: String, point: Vector3, look_at: Vector3) -> bool:
	_keys();_e(false)
	var row := {"name":title,"kind":"explicit_test_only_scenario_start","requested":point,"look_at":look_at}
	if visit._safe_external_point(point).is_empty() and not visit.active:
		row["supported_clear"] = false;placements.append(_json_value(row));_check("fixture."+title,false,row);return false
	scene.player.global_transform = Transform3D(Basis.IDENTITY,point)
	scene.player.velocity = Vector3.ZERO
	scene.player.require_neutral_input();scene.player.reset_physics_interpolation()
	await _ticks(12)
	await _look_at(look_at)
	row["actual"] = scene.player.global_position
	row["grounded"] = scene.player.is_on_floor()
	row["neutral"] = not scene.player.input_latched
	row["movement_m"] = scene.player.global_position.distance_to(point)
	placements.append(_json_value(row))
	var passed: bool = row.grounded and row.neutral and row.movement_m<.15
	if not passed:_check("fixture."+title,false,row)
	return passed

func _look_at(point: Vector3) -> void:
	var direction: Vector3 = point-(scene.player.global_position+Vector3.UP*scene.rig.pivot_height_m)
	var flat := Vector2(direction.x,direction.z).length()
	visit._orient(atan2(-direction.x,-direction.z),atan2(direction.y,maxf(flat,.001)),4.5)
	await _ticks(18)

func _observe(title: String) -> Dictionary:
	var row: Dictionary = way.snapshot()
	row = row.duplicate(true)
	row.erase("anchors")
	row["scenario"] = title
	row["player"] = scene.player.global_position
	row["camera"] = scene.rig.camera.global_position
	row["actual_aimed_building"] = scene.building_names.current_id
	row["actual_visible_signs"] = _visible_signs()
	observations.append(_json_value(row))
	return row

func _fits(rect: Rect2, size: Vector2) -> bool:
	return rect.size.x>30. and rect.size.y>20. and rect.position.x>=7.9 and rect.position.y>=7.9 and rect.end.x<=size.x-7.9 and rect.end.y<=size.y-7.9

func _world_projection(row: Dictionary) -> Dictionary:
	var point: Vector3 = _point(row.get("target_entrance",Vector3.INF))+Vector3.UP*2.4
	var camera: Camera3D = scene.rig.camera
	var projected := camera.unproject_position(point)
	return {"point":point,"projected":projected,"behind":camera.is_position_behind(point),"viewport":scene.get_viewport().get_visible_rect().size}

func _distance_to_source(point: Vector3, spec: Dictionary) -> float:
	var best := INF
	for ring: Array in spec.source_rings[int(spec.source_part_index)]:
		for index in range(ring.size()-1):
			var start := Vector2(float(ring[index][0]),float(ring[index][1]))
			var end := Vector2(float(ring[index+1][0]),float(ring[index+1][1]))
			best = minf(best,Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),start,end).distance_to(Vector2(point.x,point.z)))
	return best

func _capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":
		captures.append({"name":title,"captured":false,"reason":"headless_has_no_rendered_viewport"});return
	await process_frame
	RenderingServer.force_draw(false,0.0)
	var picture: Image = scene.get_viewport().get_texture().get_image()
	var path := report_path.trim_suffix(".json")+"_"+title+".png"
	var saved: bool = not picture.is_empty() and picture.save_png(path)==OK
	var state: Dictionary = way.snapshot();state.erase("anchors")
	var row := {"name":title,"captured":saved,"path":path,"width":picture.get_width(),"height":picture.get_height(),"state":state}
	captures.append(_json_value(row));_check("capture."+title,saved,row)

func _blocker(point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();body.name = "EntranceGuidanceLineOfSightFault"
	body.collision_layer = 1;body.collision_mask = 0
	body.position = point+Vector3.UP
	var node := CollisionShape3D.new();var shape := BoxShape3D.new()
	shape.size = Vector3(2.5,2.,.15);node.shape = shape
	body.add_child(node);scene.add_child(body)
	return body

func _leave(title: String) -> bool:
	if not visit.active:return false
	if not await _pose(title+"_exit",visit.room.exit_point(),visit.room.exit_point()+Vector3.FORWARD*3.+Vector3.UP):return false
	var before: int = visit.exit_count
	_e(true);_e(false);await _ticks(10)
	var passed: bool = not visit.active and visit.exit_count==before+1 and scene.player.is_on_floor() and not visit._safe_external_point(scene.player.global_position).is_empty()
	_check(title+".physical_E_safe_exit",passed,{"position":scene.player.global_position,"state":visit.snapshot()})
	return passed

func _geometry() -> void:
	var state: Dictionary = way.snapshot()
	var anchors: Array = state.get("anchors",[])
	var specs := {}
	for spec: Dictionary in visit.catalog:specs[spec.id] = spec
	var marker_nodes := {}
	for marker: Dictionary in way.markers:marker_nodes[marker.spec.id] = marker
	var cyan: MultiMeshInstance3D = way.world_frames.get_node("PortalCyan")
	var navy: MultiMeshInstance3D = way.world_frames.get_node("PortalBackplates")
	var invalid_doors := [];var invalid_frames := [];var invalid_pads := []
	var ids := {};var max_source_gap := 0.;var max_pad_gap := 0.
	var headless: bool = DisplayServer.get_name()=="headless" and cyan.multimesh.get_instance_transform(0)==Transform3D.IDENTITY and way._cyan[0]!=Transform3D.IDENTITY
	var transform_source := "actual_MultiMesh_readback" if not headless else "CPU_transforms_submitted_to_RenderingServer"
	if headless:
		deferred_checks.append({"name":"actual_renderer_MultiMesh_transform_readback","reason":"headless_dummy_rendering_server_does_not_retain_MultiMesh_transforms","first_submitted":way._cyan[0],"first_dummy_readback":cyan.multimesh.get_instance_transform(0),"required_followup":"Run this same test with a native GPU display; geometry checks then use actual MultiMesh readback."})
	for anchor: Dictionary in anchors:
		var id := String(anchor.get("id",""));ids[id] = true
		if not specs.has(id):invalid_doors.append(id);continue
		var spec: Dictionary = specs[id]
		var door: Vector3 = _point(anchor.door_anchor)
		var source_gap := _distance_to_source(door,spec)
		max_source_gap = maxf(max_source_gap,source_gap)
		if source_gap>.15 or Vector2(door.x,door.z).distance_to(Vector2(spec.door.x,spec.door.z))>.001 or absf(door.y-spec.entrance.y)>.001:invalid_doors.append(id)
		# Native runs read back uploaded MultiMesh transforms. Godot's dummy
		# headless renderer returns identity; its CPU submission is a weaker check
		# explicitly separated in deferred_checks and each evidence record.
		var index := int(anchor.portal_cyan_index)
		var left: Transform3D = cyan.global_transform*(way._cyan[index] if headless else cyan.multimesh.get_instance_transform(index))
		var right: Transform3D = cyan.global_transform*(way._cyan[index+1] if headless else cyan.multimesh.get_instance_transform(index+1))
		var lintel: Transform3D = cyan.global_transform*(way._cyan[index+2] if headless else cyan.multimesh.get_instance_transform(index+2))
		var jamb_midpoint: Vector3 = (left.origin+right.origin)*.5
		var expected: Vector3 = door+spec.outward*.22
		var clear_width: float = left.origin.distance_to(right.origin)-(left.basis.x.length()+right.basis.x.length())*.5
		var expected_width := 4.55 if id==LIBRARY_ID else 2.2
		if Vector2(jamb_midpoint.x,jamb_midpoint.z).distance_to(Vector2(expected.x,expected.z))>.002 or absf(clear_width-expected_width)>.002 or left.basis.y.length()<2.6 or absf(left.origin.y-left.basis.y.length()*.5-door.y)>.002 or lintel.origin.y<=left.origin.y+1.:invalid_frames.append(id)
		var pad_index := int(anchor.threshold_backplate_index)
		var pad: Transform3D = navy.global_transform*(way._navy[pad_index] if headless else navy.multimesh.get_instance_transform(pad_index))
		var pad_gap := Vector2(pad.origin.x,pad.origin.z).distance_to(Vector2(spec.entrance.x,spec.entrance.z))
		max_pad_gap = maxf(max_pad_gap,pad_gap)
		var ground_letter: Label3D = marker_nodes[id].ground
		var letter_gap := Vector2(ground_letter.global_position.x,ground_letter.global_position.z).distance_to(Vector2(spec.entrance.x,spec.entrance.z))
		if pad_gap>.002 or pad.origin.y<spec.entrance.y or pad.origin.y>spec.entrance.y+.10 or pad.basis.x.length()<1.0 or pad.basis.z.length()<1.0 or letter_gap>.002 or ground_letter.text!="E" or ground_letter.global_position.y<spec.entrance.y or ground_letter.global_position.y>spec.entrance.y+.2:invalid_pads.append(id)
	_check("geometry.all_125_distinct_source_facade_anchors",anchors.size()==125 and ids.size()==125 and invalid_doors.is_empty(),{"anchors":anchors.size(),"distinct_ids":ids.size(),"max_source_perimeter_gap_m":max_source_gap,"invalid_ids":invalid_doors})
	_check("geometry.3D_frames_straddle_authored_doors",invalid_frames.is_empty() and cyan.multimesh.instance_count>=125*3,{"transform_source":transform_source,"invalid_ids":invalid_frames,"mesh_instances":cyan.multimesh.instance_count,"generic_clear_width_m":2.2,"library_clear_width_m":4.55})
	_check("geometry.ground_E_pads_match_entry_anchors",invalid_pads.is_empty(),{"transform_source":transform_source,"invalid_ids":invalid_pads,"max_XZ_gap_m":max_pad_gap})
	var collisions := 0
	for node in _descendants(way):
		if node is CollisionObject3D or node is CollisionShape3D:collisions += 1
	_check("geometry.guidance_adds_no_collision_objects",collisions==0 and _inventory()==original_inventory,{"guidance_collision_nodes":collisions,"original_collision_records":original_inventory.size()})
	var incorrect_names := []
	for marker: Dictionary in scene.building_names.markers:
		if marker.node.text!=String(scene.building_names.records[marker.id].name):incorrect_names.append(marker.id)
	_check("names.original_OSM_building_labels_preserved",incorrect_names.is_empty() and not original_names.is_empty(),{"named_buildings":original_names.size(),"incorrect_ids":incorrect_names})

func _direction_trials(spec: Dictionary) -> void:
	var entrance: Vector3 = spec.entrance
	var outward: Vector3 = spec.outward
	# At 100m another aimed building may legitimately become the new target.
	# Use a nearer supported pose and aim at pavement, letting nearest selection
	# operate without any artificial target ID or stale aimed-building override.
	var down := Vector3.UP*(1.3-50.*tan(deg_to_rad(15.)))
	var elevated_down := Vector3.UP*(1.3-50.*tan(deg_to_rad(35.)))
	var start := entrance+outward*30.
	if not await _pose("library_front_30m_elevated_lookaway",start,start+outward*50.+elevated_down):return
	var behind := _observe("library_front_30m_camera_away")
	var actual: Dictionary = _world_projection(behind)
	var arrow_direction := Vector2.UP.rotated(way.bearing_arrow.rotation)
	var camera_above: bool = scene.rig.camera.global_position.y>Vector3(actual.point).y+.5
	_check("bearing.elevated_rear_camera_arrow_points_down_and_card_clamps",String(behind.target_id)==LIBRARY_ID and behind.panel_visible and behind.target_behind_camera and actual.behind and not behind.target_on_screen and camera_above and arrow_direction.dot(Vector2.DOWN)>.95 and _fits(way.panel.get_rect(),actual.viewport),{"state":behind,"projection":actual,"arrow_direction":arrow_direction,"camera_above_marker":camera_above})
	# Rotate sideways in both directions; the words must track the real local bearing.
	var side := Vector3(outward.z,0.,-outward.x)
	await _look_at(scene.player.global_position+side*50.+down)
	var right := _observe("library_sideways_one")
	var one := String(way.direction_label.text)
	await _look_at(scene.player.global_position-side*50.+down)
	var left := _observe("library_sideways_other")
	var two := String(way.direction_label.text)
	var camera: Camera3D = scene.rig.camera
	var local: Vector3 = camera.global_basis.inverse()*(entrance-camera.global_position)
	var expected_word := "오른쪽" if local.x>0. else "왼쪽"
	_check("bearing.left_right_changes_with_actual_camera",one!=two and one.contains("입구") and two.contains(expected_word) and left.panel_visible and right.panel_visible,{"first":one,"second":two,"actual_local_X":local.x,"first_state":right,"second_state":left})
	# Test an actual small viewport, not a fabricated snapshot size.
	var saved_size: Vector2i = root.size
	var saved_scale: Vector2i = root.content_scale_size
	var saved_factor: float = root.content_scale_factor
	root.content_scale_size = Vector2i.ZERO;root.content_scale_factor = 1.
	root.size = Vector2i(640,480);await _ticks(6)
	var small := _observe("library_offscreen_640x480")
	var view: Vector2 = scene.get_viewport().get_visible_rect().size
	_check("UI.offscreen_card_fits_actual_640x480",view==Vector2(640,480) and small.panel_visible and not small.target_on_screen and _fits(way.panel.get_rect(),view) and way.panel.get_rect()==_rect(small.panel_rect),{"state":small,"actual_rect":way.panel.get_rect(),"actual_viewport":view})
	root.size = saved_size;root.content_scale_size = saved_scale;root.content_scale_factor = saved_factor;await _ticks(6)
	scene.toggle_menu();await _ticks(6)
	var menu := _observe("menu_open")
	_check("UI.menu_hides_card_world_frames_and_signs",paused and scene.menu.visible and menu.hidden and not way.panel.is_visible_in_tree() and not way.world_frames.is_visible_in_tree() and _visible_signs()==0,menu)
	scene.toggle_menu();_keys();_e(false);await _ticks(6)
	_check("UI.resume_restores_guidance",not paused and way.panel.is_visible_in_tree() and way.world_frames.is_visible_in_tree(),_observe("menu_resumed"))

func _entry_trials(spec: Dictionary, title: String, capture_near := false) -> bool:
	var entrance: Vector3 = spec.entrance
	var outward: Vector3 = spec.outward
	if not await _pose(title+"_near_door",entrance,Vector3(spec.door.x,1.5,spec.door.z)):return false
	var near := _observe(title+"_near_door")
	_check(title+".near_card_matches_physical_entry",near.target_id==spec.id and near.panel_visible and visit._entry_near() and visit._entry_visible() and way.direction_label.text.contains("E") and visit.prompt.visible,{"state":near,"entry_state":visit.snapshot()})
	if capture_near:await _capture("library_near_door")
	if title=="library":
		if not await _pose("library_downward_ground_E_view",entrance+outward*2.,entrance):return false
		var marker: Dictionary = {}
		for row: Dictionary in way.markers:
			if row.spec.id==LIBRARY_ID:marker = row;break
		var camera: Camera3D = scene.rig.camera
		var view: Vector2 = scene.get_viewport().get_visible_rect().size
		var ground_point := camera.unproject_position(marker.ground.global_position)
		var sign_point := camera.unproject_position(marker.sign.global_position)
		var ground_state := _observe("library_downward_ground_E_view")
		_check("labels.near_ground_E_visible_when_high_facade_sign_is_offscreen",not camera.is_position_behind(marker.ground.global_position) and Rect2(Vector2.ZERO,view).has_point(ground_point) and not Rect2(Vector2.ZERO,view).has_point(sign_point) and marker.ground.is_visible_in_tree() and int(ground_state.get("visible_ground_label_count",0))>=1 and int(ground_state.get("visible_ground_label_count",4))<=3,{"state":ground_state,"ground_projection":ground_point,"facade_sign_projection":sign_point})
		await _pose("library_line_of_sight_fault",entrance+outward,Vector3(spec.door.x,1.5,spec.door.z))
		var blocker := _blocker(entrance+outward*.5)
		await _ticks(14)
		var before: int = visit.entry_count
		_e(true);_e(false);await _ticks(5)
		var blocked := _observe("library_occluded_entry")
		_check("entry.occluder_rejects_short_physical_E",not visit.active and visit.entry_count==before and visit._entry_near() and not visit._entry_visible() and blocked.target_occluded and not visit.prompt.visible and not way.direction_label.text.contains("들어가기"),{"state":blocked,"entry_state":visit.snapshot()})
		blocker.queue_free();await _ticks(12)
		if not await _pose("library_near_lookaway",entrance,entrance+outward*30.+Vector3.UP*1.3):return false
	else:
		await _look_at(entrance+outward*30.+Vector3.UP*1.3)
		await _capture("generic_offscreen_near_door")
	var away := _observe(title+"_near_lookaway")
	var lookaway_dot: float = (-scene.rig.camera.global_basis.z).dot(outward)
	var entries: int = visit.entry_count
	_e(true);_e(false);await _ticks(10)
	_check(title+".lookaway_short_physical_E_enters_marked_building",away.target_id==spec.id and not away.target_on_screen and lookaway_dot>.95 and visit.active and visit.current_spec.id==spec.id and visit.entry_count==entries+1,{"before":away,"camera_forward_dot_outward":lookaway_dot,"entry_state":visit.snapshot()})
	if not visit.active:return false
	var inside := _observe(title+"_inside")
	_check(title+".indoors_hides_all_outdoor_guidance",inside.hidden and not way.panel.is_visible_in_tree() and not way.world_frames.is_visible_in_tree() and _visible_signs()==0 and not scene.building_names.panel.visible and not scene.building_names.crosshair.visible,inside)
	if title=="library":
		_check("people.existing_interior_population_preserved",visit.room.people.size()==4,{"people":visit.room.people.size()})
	return await _leave(title)

func _scenarios() -> void:
	var library: Dictionary = {}
	var generic: Dictionary = {}
	for spec: Dictionary in visit.catalog:
		if spec.id==LIBRARY_ID:library = spec
		elif generic.is_empty() and spec.kind=="office":generic = spec
	if library.is_empty() or generic.is_empty():_check("fixtures.library_and_office_present",false);return
	var entrance: Vector3 = library.entrance
	var outward: Vector3 = library.outward
	if not await _pose("library_front_100m",entrance+outward*100.,Vector3(library.door.x,1.4,library.door.z)):return
	var far := _observe("library_front_100m")
	var distance := Vector2(scene.player.global_position.x,scene.player.global_position.z).distance_to(Vector2(entrance.x,entrance.z))
	_check("far.library_is_discoverable_at_100m",far.target_id==LIBRARY_ID and far.panel_visible and distance>=80. and distance<=120. and way.target_label.text==library.title and way.caption.text.contains("정문"),{"state":far,"actual_distance_m":distance})
	_check("far.displayed_distance_matches_ground_distance",absf(float(far.target_distance_m)-distance)<.01 and way.caption.text.contains("%.0f"%distance) and way.direction_label.text.contains("직선거리"),{"actual_distance_m":distance,"state":far})
	var projected := _world_projection(far)
	var rect: Rect2 = way.panel.get_rect()
	_check("far.onscreen_card_tracks_real_entry_projection",far.target_on_screen and not far.target_behind_camera and not projected.behind and absf(rect.get_center().x-projected.projected.x)<1. and rect.end.y<=projected.projected.y+1. and _fits(rect,projected.viewport),{"state":far,"projection":projected,"actual_rect":rect})
	_check("labels.clutter_is_bounded_and_depth_tested",_visible_signs()<=3 and _visible_ground_labels()<=3 and int(far.visible_label_count)==_visible_signs() and int(far.get("visible_ground_label_count",-1))==_visible_ground_labels() and way.markers.all(func(row):return not row.sign.no_depth_test and not row.ground.no_depth_test),{"visible_facade_signs":_visible_signs(),"visible_ground_E":_visible_ground_labels(),"state":far})
	await _capture("library_far_100m")
	var before: int = visit.entry_count
	_e(true);_e(false);await _ticks(6)
	_check("entry.far_short_physical_E_still_rejected",not visit.active and visit.entry_count==before and not visit._entry_near(),visit.snapshot())
	await _direction_trials(library)
	# West/rear-side approach is outside the real library ring. Aim at its side
	# facade so selection comes from the production camera ray, not a forced ID.
	if not await _pose("library_rear_side",Vector3(103.,.08,-150.),Vector3(130.,1.5,-140.)):return
	var rear := _observe("library_rear_side")
	var backside: float = (scene.player.global_position-entrance).dot(outward)
	_check("rear.actual_facade_aim_keeps_front_entry_direction",rear.target_id==LIBRARY_ID and scene.building_names.current_id==LIBRARY_ID and scene.building_names.current_is_targeted and backside< -1. and rear.target_occluded and way.direction_label.text.contains("반대편") and rear.panel_visible,{"state":rear,"front_side_dot_m":backside})
	if not await _entry_trials(library,"library",true):return
	if not await _entry_trials(generic,"generic"):return

func _run() -> void:
	for path in ["res://scripts/interior_visit.gd","res://scripts/entrance_wayfinding.gd","res://scripts/building_names.gd","res://../tests/game/check_entrance_guidance.gd"]:source_hashes[path] = FileAccess.get_sha256(path)
	scene = load("res://scenes/world/explore_walk.tscn").instantiate()
	scene.exploration_settings_path = report_path+".settings.json"
	scene.quality_settings_path = report_path+".quality.json"
	root.add_child(scene)
	if not scene.runtime_ok:_check("startup",false);_finish();return
	visit = scene.interior_visit
	way = visit.get("wayfinding")
	var api: bool = is_instance_valid(way) and way.has_method("snapshot")
	_check("startup.catalog_125_and_wayfinding_API",api and visit.loaded and visit.catalog.size()==125,{"catalog_count":visit.catalog.size()})
	if not api:_finish();return
	await _ticks(25)
	original_inventory = _inventory();original_names = _name_inventory()
	_check("input.physical_E_production_binding",InputMap.action_get_events("interact").any(func(event):return event is InputEventKey and event.physical_keycode==KEY_E))
	_check("exterior.original_692_collision_records",original_inventory.size()==692,{"count":original_inventory.size()})
	_geometry()
	await _scenarios()
	_check("exterior.body_shapes_and_building_names_unchanged",_inventory()==original_inventory and _name_inventory()==original_names,{"collision_records":original_inventory.size(),"building_labels":original_names.size()})
	_finish()

func _timeout() -> void:
	if finished:return
	_check("timeout",false);_finish()

func _finish() -> void:
	if finished:return
	finished = true;_keys();_e(false);paused = false
	var failed := 0
	for check in checks:
		if not check.passed:failed += 1
	var report := {"schema_version":1,"task":"entrance_guidance","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"source_sha256_at_startup":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"placements":placements,"observations":observations,"captures":captures,"deferred_checks":deferred_checks,"isolated_files":{"exploration_settings":report_path+".settings.json","quality_settings":report_path+".quality.json"},"scope":"Production exploration scene. Explicit scenario-start teleports are fixtures, not a continuous route. Source facade/ground anchors, real camera ray/projection, viewport bounds, hidden states and physical E taps are checked. Native GPU geometry checks read actual uploaded MultiMesh transforms; headless dummy checks only CPU submissions and defers native readback. Synthetic occluder is a line-of-sight fault fixture. Headless output has no GPU capture or human-input acceptance; native captures use force_draw. No surveyed entrance, entire 125-building visit, performance, packaging or cross-Mac claim."}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_json_value(report),"\t")+"\n");file.close()
	else:failed += 1;push_error("Could not save entrance guidance report")
	print("ENTRANCE_GUIDANCE_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)

extends SceneTree
## Full production city in one of two independent headless processes. Only
## ordinary movement actions are supplied; the manager owns join handoff.
const SCENE := "res://scenes/world/explore_walk.tscn"
const ACTIONS := ["move_forward","move_backward","move_left","move_right","move_fast"]
const USER_SETTINGS := ["user://sim2seoul_quality.json","user://sim2seoul_exploration.json","user://sim2seoul_exploration.json.time.json","user://sim2seoul_character.json"]
var _role:=""
var _peer:=""
var _coord_url:=""
var _report:=""
var _scene: Node3D
var _manager: Node
var _client: Node
var _coord_http: HTTPRequest
var _checks: Array=[]
var _settings_before: Dictionary={}
var _initial_counts: Dictionary={}
var _movement: Dictionary={}
var _remote_before: Dictionary={}
var _remote_after: Dictionary={}
var _remote_rejoin: Dictionary={}
var _started:=0
var _physics_start:=0
var _ai_start:=0.
var _done:=false
var _finishing:=false
var _invite_memory:=""
var _capture_enabled:=false
var _captures: Array=[]

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-role="):_role=argument.trim_prefix("--test-role=")
		if argument.begins_with("--test-coord="):_coord_url=argument.trim_prefix("--test-coord=")
		if argument.begins_with("--test-report="):_report=argument.trim_prefix("--test-report=")
		if argument=="--test-owner-graphics":_capture_enabled=true
	if _role not in ["a","b"] or not _coord_url.begins_with("http://127.0.0.1:") or not _report.is_absolute_path():quit(2);return
	_peer="b" if _role=="a" else "a"
	Engine.max_fps=60
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for entry: Variant in value:result.append(_json(entry))
		return result
	return value

func _check(name_: String,passed: bool) -> bool:
	_checks.append({"name":name_,"passed":passed})
	if not passed:push_warning("SHARED_CITY_WORLD_CHECK_FAIL role="+_role+" case="+name_)
	return passed

func _settings() -> Dictionary:
	var result: Dictionary={}
	for path: String in USER_SETTINGS:result[path]={"exists":FileAccess.file_exists(path),"sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func _wait(milliseconds: int) -> void:
	var until:=Time.get_ticks_msec()+milliseconds
	while not _done and Time.get_ticks_msec()<until:await process_frame

func _until(predicate: Callable,timeout_ms:=10000) -> bool:
	var until:=Time.get_ticks_msec()+timeout_ms
	while not _done and Time.get_ticks_msec()<until:
		if predicate.call():return true
		await process_frame
	return bool(predicate.call())

func _coord(path: String,method:=HTTPClient.METHOD_GET,body: Dictionary={}) -> Dictionary:
	var headers:=PackedStringArray(["Content-Type: application/json","Origin: "+_coord_url])
	var error:=_coord_http.request(_coord_url+path,headers,method,JSON.stringify(body) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:return {}
	var response: Array=await _coord_http.request_completed
	if response[0]!=HTTPRequest.RESULT_SUCCESS or response[1]!=200:return {}
	var parser:=JSON.new()
	if parser.parse((response[3] as PackedByteArray).get_string_from_utf8())!=OK or not parser.data is Dictionary:return {}
	return parser.data

func _stage(value: String) -> bool:
	var result: Dictionary=await _coord("/state",HTTPClient.METHOD_POST,{"role":_role,"stage":value})
	return bool(result.get("stored",false))

func _peer_stage(value: String,timeout_ms:=12000) -> bool:
	var until:=Time.get_ticks_msec()+timeout_ms
	while not _done and Time.get_ticks_msec()<until:
		var state: Dictionary=await _coord("/state")
		var row: Dictionary=state.get(_peer,{})
		if row.get("stages",[]).has("failed"):return false
		if row.get("stages",[]).has(value):return true
		await _wait(200)
	return false

func _remote_ready() -> bool:
	if _manager.remotes.size()!=1:return false
	var remote: Node3D=_manager.remotes.values()[0]
	if not is_instance_valid(remote) or not remote._ready_remote or not is_instance_valid(remote.avatar):return false
	var skin: Dictionary=remote.avatar.textured_model_snapshot(false)
	return bool(skin.get("loaded",false)) and int(skin.get("skeleton_bone_count",0))>0

func _remote_state() -> Dictionary:
	if not _remote_ready():return {}
	var remote: Node3D=_manager.remotes.values()[0]
	var skin: Dictionary=remote.avatar.textured_model_snapshot(false)
	var accepted: Dictionary=remote._samples.back()
	return {"ready":remote._ready_remote,"instance_id":remote.get_instance_id(),"accepted_sequence":remote._last_sequence,"accepted_position":accepted.position,"displayed_position":remote.global_position,"skin_loaded":skin.loaded,"bones":skin.skeleton_bone_count,"physics_processing":remote.is_physics_processing(),"collision_layer":remote.collision_layer,"collision_mask":remote.collision_mask}

func _release_actions() -> void:
	for action: String in ACTIONS:Input.action_release(action)

func _capture_pair(stage: String) -> void:
	if not _capture_enabled:return
	var safe_ui: bool=not _manager.ui_open and not _manager._overlay.visible and not _manager._invite_output.is_visible_in_tree() and not _scene.menu.visible
	if not _check(stage+"_capture_has_native_display_and_no_invite_ui",DisplayServer.get_name()!="headless" and safe_ui and _remote_ready()):return
	var remote: Node3D=_manager.remotes.values()[0]
	var points: Array[Vector3]=[_scene.player.global_position,remote.global_position]
	var focus: Vector3=(points[0]+points[1])*.5+Vector3.UP*.9
	var radius:=maxf(5.5,points[0].distance_to(points[1])*1.2+3.)
	var original: Camera3D=root.get_camera_3d()
	var camera:=Camera3D.new();camera.name="FixturePairCaptureCamera";camera.fov=55.;camera.near=.08;camera.far=1400.;_scene.add_child(camera)
	var chosen:=false
	for direction: Vector3 in [Vector3.BACK,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3(1,0,1).normalized(),Vector3(-1,0,1).normalized(),Vector3(1,0,-1).normalized(),Vector3(-1,0,-1).normalized()]:
		var eye: Vector3=focus+direction*radius+Vector3.UP*2.2
		var clear:=true
		for point: Vector3 in points:
			var query:=PhysicsRayQueryParameters3D.create(eye,point+Vector3.UP*.9,1|32)
			clear=clear and _scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		camera.global_position=eye;camera.look_at(focus)
		for point: Vector3 in points:clear=clear and camera.is_position_in_frustum(point) and camera.is_position_in_frustum(point+Vector3.UP*2.2)
		if clear:chosen=true;break
	if not _check(stage+"_capture_camera_frames_both_physical_actors",chosen):camera.queue_free();return
	var markers: Array[Label3D]=[]
	for index in range(points.size()):
		var marker:=Label3D.new();marker.name="FixtureActorMarker"+str(index);marker.text="LOCAL (test)" if index==0 else "REMOTE (test)"
		marker.font_size=36;marker.outline_size=8;marker.pixel_size=.004;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate=Color(.2,.85,1.) if index==0 else Color(1.,.7,.2)
		_scene.add_child(marker);marker.global_position=points[index]+Vector3.UP*2.05;markers.append(marker)
	camera.make_current()
	for frame in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var path:=_report.get_basename()+"_"+stage+".png"
	var image:=root.get_texture().get_image()
	var saved:=image.save_png(path)==OK
	_check(stage+"_original_native_viewport_png_saved",saved and image.get_width()>0 and image.get_height()>0)
	if saved:_captures.append({"stage":stage,"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"camera_position":camera.global_position,"look_at":focus,"actor_positions":points,"remote_skin_loaded":true,"fixture_camera_and_local_remote_markers":true,"product_camera_transform_written":false,"invite_ui_visible":false,"scope":"Original native GPU viewport. Separate temporary fixture camera and clearly marked test labels frame the two actual production avatars; this is not the product camera or a production peer label."})
	if is_instance_valid(original):original.make_current()
	for marker: Label3D in markers:marker.queue_free()
	camera.queue_free();await process_frame
	_check(stage+"_product_camera_restored",root.get_camera_3d()==original)

func _move_with_input() -> void:
	_release_actions();await _wait(150)
	var actions:= ["move_right","move_forward","move_backward","move_left"] if _role=="a" else ["move_left","move_forward","move_backward","move_right"]
	var overall: Vector3=_scene.player.global_position
	var steps: Array=[]
	for action: String in actions:
		var before: Vector3=_scene.player.global_position
		var frames:=Engine.get_physics_frames();var began:=Time.get_ticks_msec()
		Input.action_press(action);await _wait(1000);Input.action_release(action)
		await _wait(350)
		var after: Vector3=_scene.player.global_position
		steps.append({"action":action,"pressed_ms":Time.get_ticks_msec()-began-350,"physics_steps":Engine.get_physics_frames()-frames,"before":before,"after":after,"metres":Vector2(after.x-before.x,after.z-before.z).length()})
		if Vector2(after.x-overall.x,after.z-overall.z).length()>.20:break
	_release_actions()
	var final_position: Vector3=_scene.player.global_position
	_movement={"local_start":overall,"local_end":final_position,"horizontal_metres":Vector2(final_position.x-overall.x,final_position.z-overall.z).length(),"input_steps":steps,"direct_fixture_position_writes":0}
	_check("ordinary_controller_input_moves_actual_capsule",_movement.horizontal_metres>.20 and _scene.player.is_on_floor())

func _run() -> void:
	_started=Time.get_ticks_msec();_settings_before=_settings()
	_coord_http=HTTPRequest.new();_coord_http.timeout=3.;_coord_http.body_size_limit=16384;_coord_http.max_redirects=0;root.add_child(_coord_http)
	_scene=load(SCENE).instantiate()
	# Missing per-test settings select existing defaults without writing files.
	var settings_prefix:=_report.get_basename()+"_absent_settings"
	_scene.exploration_settings_path=settings_prefix+"_exploration.json"
	_scene.quality_settings_path=settings_prefix+"_quality.json"
	_scene.character_settings_path=settings_prefix+"_character.json"
	root.add_child(_scene)
	# Synchronous city setup can make its first frame much longer than the HTTP
	# timeout. Let that startup delta pass before creating any network request.
	for frame in range(3):await process_frame
	for tick in range(6):await physics_frame
	if _scene.menu.visible:_scene.toggle_menu()
	_manager=_scene.shared_city_walk;_client=_manager.client if is_instance_valid(_manager) else null
	var ready: bool=_scene.runtime_ok and _scene.exploration_error.is_empty() and is_instance_valid(_client) and _scene.terrain_surface.loaded
	if not _check("full_production_city_terrain_and_manager_ready",ready):await _finish();return
	_initial_counts={"source_meshes":_scene.city.source_nodes.size(),"collision_objects":_scene.find_children("*","CollisionObject3D",true,false).size(),"street_actors":_scene.street_pedestrians.actors.size(),"distributed_actors":_scene.neighborhood_population.walkers.actors.size(),"player_capsule":_scene.player.get_node("CollisionShape").shape is CapsuleShape3D,"physics_hz":Engine.physics_ticks_per_second}
	_check("actual_city_ai_and_physical_player_remain_enabled",_initial_counts.source_meshes>100 and _initial_counts.collision_objects>100 and _initial_counts.street_actors>0 and _initial_counts.distributed_actors>0 and _initial_counts.player_capsule and _scene.street_pedestrians.running and not paused)
	_physics_start=Engine.get_physics_frames();_ai_start=_scene.street_pedestrians.elapsed
	_client.check_service()
	if not _check("actual_manager_client_bootstrap",await _until(func()->bool:return _client.available and not _client.busy())):await _finish();return
	await _stage("ready")
	if _role=="a":
		_check("manager_client_create_started",_client.create_room())
		if not _check("manager_client_created",await _until(func()->bool:return _client.connected and not _client.busy())):await _finish();return
		_invite_memory=_client.invite_code()
		var stored: Dictionary=await _coord("/invite",HTTPClient.METHOD_POST,{"code":_invite_memory})
		if not _check("fake_test_invite_relay_memory_only",stored.get("stored",false)):await _finish();return
		await _stage("created")
	else:
		var until:=Time.get_ticks_msec()+15000
		while _invite_memory.is_empty() and Time.get_ticks_msec()<until:
			var result: Dictionary=await _coord("/invite");_invite_memory=String(result.get("code",""))
			if _invite_memory.is_empty():await _wait(200)
		if not _check("fake_test_invite_received_in_memory",not _invite_memory.is_empty()):await _finish();return
		_check("manager_client_join_started",_client.join_room(_invite_memory))
	if not _check("production_remote_resident_real_skin_loaded",await _until(_remote_ready,15000)):await _finish();return
	var remote: Dictionary=_remote_state()
	_check("remote_remains_noncolliding_presentation",not remote.physics_processing and remote.collision_layer==0 and remote.collision_mask==0)
	await _stage("peer_loaded")
	if not _check("both_full_games_have_peer",await _peer_stage("peer_loaded")):await _finish();return
	await _wait(1400);await _stage("input_ready")
	if not _check("both_ready_for_physical_input",await _peer_stage("input_ready")):await _finish();return
	await _capture_pair("joined");await _stage("view_ready")
	if not _check("both_joined_view_captures_finished",await _peer_stage("view_ready")):await _finish();return
	_remote_before=_remote_state()
	await _move_with_input();await _stage("moved")
	if not _check("both_physical_input_sequences_finished",await _peer_stage("moved")):await _finish();return
	await _wait(1500);_remote_after=_remote_state()
	var accepted_delta: float=Vector3(_remote_before.accepted_position).distance_to(Vector3(_remote_after.accepted_position))
	_check("peer_accepted_position_changes_after_real_input",accepted_delta>.15 and int(_remote_after.accepted_sequence)>int(_remote_before.accepted_sequence))
	_check("peer_display_interpolates_to_accepted_position",Vector3(_remote_after.displayed_position).distance_to(Vector3(_remote_after.accepted_position))<.15)
	await _capture_pair("moved");await _stage("movement_view_ready")
	if not _check("both_movement_view_captures_finished",await _peer_stage("movement_view_ready")):await _finish();return
	if _role=="b":
		var old_self: String=_client.self_id
		_client.leave_room()
		if not _check("peer_leave_completes",await _until(func()->bool:return not _client.connected and not _client.busy() and _manager.remotes.is_empty(),5000)):await _finish();return
		await _stage("left")
		if not _check("owner_confirmed_remote_removal",await _peer_stage("absence_seen")):await _finish();return
		_check("peer_rejoin_started",_client.join_room(_invite_memory))
		if not _check("peer_rejoin_new_self_and_real_remote",await _until(func()->bool:return _client.connected and _client.self_id!=old_self and _remote_ready(),10000)):await _finish();return
		_remote_rejoin=_remote_state();await _stage("rejoined")
		if not _check("owner_confirmed_recreated_remote",await _peer_stage("done")):await _finish();return
		await _stage("done")
	else:
		var old_instance: int=_remote_after.instance_id
		if not _check("peer_announced_leave",await _peer_stage("left")):await _finish();return
		if not _check("owner_removes_departed_remote_node",await _until(func()->bool:return _manager.remotes.is_empty() and _client.participant_count==1,5000)):await _finish();return
		await _stage("absence_seen")
		if not _check("peer_announced_rejoin",await _peer_stage("rejoined")):await _finish();return
		if not _check("owner_recreates_loaded_remote_node",await _until(_remote_ready,10000)):await _finish();return
		_remote_rejoin=_remote_state()
		_check("rejoin_has_new_remote_object",int(_remote_rejoin.instance_id)!=old_instance)
		await _stage("done")
		_check("peer_finished_rejoin_checks",await _peer_stage("done"))
	await _finish()

func _finish() -> void:
	if _done or _finishing:return
	_finishing=true
	_release_actions()
	if is_instance_valid(_client):
		_client.leave_room()
		var left: bool=await _until(func()->bool:return not _client.busy() and not _client.connected and _client.state in ["ready","offline"],6000)
		_check("shutdown_waits_for_actual_leave_completion",left)
	if is_instance_valid(_scene) and is_instance_valid(_scene.street_pedestrians):
		_check("full_city_ai_and_physics_advanced",_scene.street_pedestrians.elapsed>_ai_start and Engine.get_physics_frames()>_physics_start+10)
	var after:=_settings()
	_check("actual_user_settings_bytes_unchanged",after==_settings_before)
	var settings_prefix:=_report.get_basename()+"_absent_settings"
	var no_writes:=true
	for suffix: String in ["_exploration.json","_exploration.json.time.json","_quality.json","_character.json"]:no_writes=no_writes and not FileAccess.file_exists(settings_prefix+suffix)
	_check("isolated_missing_settings_remain_unwritten",no_writes)
	var failed:=0
	for row: Dictionary in _checks:
		if not row.passed:failed+=1
	if failed>0:await _stage("failed")
	var record:={"task":"EXP40_FULL_SHARED_CITY_WORLD","role":_role,"result":"PASS" if failed==0 else "FAIL","checks":_checks.size(),"failed":failed,"cases":_checks,"elapsed_ms":Time.get_ticks_msec()-_started,"engine":Engine.get_version_info().string,"world_scene":SCENE,"world_counts":_initial_counts,"physics_steps_after_ready":Engine.get_physics_frames()-_physics_start,"ai_seconds_after_ready":_scene.street_pedestrians.elapsed-_ai_start if is_instance_valid(_scene) and is_instance_valid(_scene.street_pedestrians) else 0.,"movement":_movement,"remote_before":_remote_before,"remote_after":_remote_after,"remote_rejoin":_remote_rejoin,"user_settings_before":_settings_before,"user_settings_after":after,"diagnostic":_manager.diagnostic() if is_instance_valid(_manager) else {},"captures":_captures,"render_mode":"native_graphical" if _capture_enabled else "headless","scope":"One of two independent full explore_walk games with actual terrain, AI and physical controller. Input actions only; production manager owns join placement. Fake loopback coordinator relays invite only in memory. Native PNGs, when enabled for owner, use a separately labelled fixture camera and test markers; product camera transforms remain untouched. No shared NPC/vehicle/combat simulation, production identity or performance claim. No bearer/cookie/invite is written."}
	var file:=FileAccess.open(_report,FileAccess.WRITE)
	if file==null:push_error("Could not save shared city world report");quit(1);return
	file.store_string(JSON.stringify(_json(record),"  ")+"\n");file.close();file=null
	_done=true;_invite_memory=""
	if is_instance_valid(_scene):_scene.queue_free()
	_coord_http.queue_free();await process_frame
	await process_frame
	_scene=null;_manager=null;_client=null;_coord_http=null
	print("SHARED_CITY_WORLD_CHECK role=",_role," result=",record.result," checks=",record.checks," failed=",failed)
	# The completion may originate in HTTPRequest's own signal stack. Give the
	# awaiting run/finish states a fresh idle cycle to release before engine exit.
	create_timer(.1,true,false,true).timeout.connect(Callable(self,"quit").bind(0 if failed==0 else 1))
